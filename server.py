#!/usr/bin/env python3
"""
Rakhssh Web SSH Server - Lightweight, Zero-Dependency Web Terminal & WebSocket SSH Gateway.
Listens on port 8766 (completely independent from chat server on 8765).
"""

import os
import sys
import pty
import tty
import termios
import struct
import fcntl
import socket
import select
import threading
import json
import base64
import hashlib
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

PORT = int(os.environ.get("WEBSSH_PORT", "8766"))
HOST = os.environ.get("WEBSSH_HOST", "0.0.0.0")
WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")
SSH_TARGET_HOST = os.environ.get("SSH_HOST", "127.0.0.1")
SSH_TARGET_PORT = int(os.environ.get("SSH_PORT", "22"))

MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".svg": "image/svg+xml"
}


def compute_ws_accept(key):
    guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    h = hashlib.sha1((key + guid).encode("ascii")).digest()
    return base64.b64encode(h).decode("ascii")


def set_pty_size(fd, cols, rows):
    try:
        # winsize struct: ws_row, ws_col, ws_xpixel, ws_ypixel
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, winsize)
    except Exception:
        pass


class WebSocketConnection:
    def __init__(self, sock):
        self.sock = sock
        self.lock = threading.Lock()
        self.closed = False

    def send_frame(self, data, opcode=0x2):
        if self.closed:
            return
        frame = bytearray()
        frame.append(0x80 | (opcode & 0x0f))  # FIN + opcode
        length = len(data)
        if length < 126:
            frame.append(length)
        elif length <= 65535:
            frame.append(126)
            frame.extend(length.to_bytes(2, "big"))
        else:
            frame.append(127)
            frame.extend(length.to_bytes(8, "big"))
        frame.extend(data)
        with self.lock:
            try:
                self.sock.sendall(frame)
            except Exception:
                self.closed = True

    def send_text(self, text):
        self.send_frame(text.encode("utf-8"), opcode=0x1)

    def send_binary(self, data):
        self.send_frame(data, opcode=0x2)

    def close(self):
        if not self.closed:
            self.closed = True
            try:
                self.send_frame(b"", opcode=0x8)
            except Exception:
                pass
            try:
                self.sock.close()
            except Exception:
                pass

    def read_frame(self):
        try:
            head = self.sock.recv(2)
            if not head or len(head) < 2:
                return None, None
            b1, b2 = head[0], head[1]
            opcode = b1 & 0x0f
            if opcode == 0x8:  # Close
                return opcode, None
            payload_len = b2 & 0x7f
            if payload_len == 126:
                ext = self.sock.recv(2)
                payload_len = int.from_bytes(ext, "big")
            elif payload_len == 127:
                ext = self.sock.recv(8)
                payload_len = int.from_bytes(ext, "big")

            is_masked = bool(b2 & 0x80)
            mask = self.sock.recv(4) if is_masked else None

            payload = b""
            while len(payload) < payload_len:
                chunk = self.sock.recv(payload_len - len(payload))
                if not chunk:
                    return None, None
                payload += chunk

            if is_masked:
                payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))

            return opcode, payload
        except Exception:
            return None, None


class WebSshHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        # Quiet standard HTTP logging
        pass

    def do_HEAD(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        if path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            return
        if path == "/" or path == "":
            file_name = "index.html"
        else:
            file_name = path.lstrip("/")
        file_path = os.path.abspath(os.path.join(WEB_DIR, file_name))
        if not file_path.startswith(WEB_DIR) or not os.path.isfile(file_path):
            self.send_response(404)
            self.end_headers()
            return
        ext = os.path.splitext(file_path)[1].lower()
        mime = MIME_TYPES.get(ext, "application/octet-stream")
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/health":
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(json.dumps({
                "status": "ok",
                "service": "webssh",
                "port": PORT,
                "version": "1.0.0"
            }).encode("utf-8"))
            return

        # Check for WebSocket Upgrade
        if path.startswith("/ws/ssh"):
            if self.headers.get("Upgrade", "").lower() == "websocket":
                self.handle_websocket(parsed)
                return

        # Serve static files from WEB_DIR
        if path == "/" or path == "":
            file_name = "index.html"
        else:
            file_name = path.lstrip("/")

        file_path = os.path.abspath(os.path.join(WEB_DIR, file_name))
        if not file_path.startswith(WEB_DIR) or not os.path.isfile(file_path):
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b"404 Not Found")
            return

        ext = os.path.splitext(file_path)[1].lower()
        mime = MIME_TYPES.get(ext, "application/octet-stream")

        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()

        with open(file_path, "rb") as f:
            self.wfile.write(f.read())

    def handle_websocket(self, parsed):
        key = self.headers.get("Sec-WebSocket-Key")
        if not key:
            self.send_response(400)
            self.end_headers()
            return

        accept_val = compute_ws_accept(key)
        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept_val)
        self.end_headers()

        ws = WebSocketConnection(self.connection)
        qs = urllib.parse.parse_qs(parsed.query)
        mode = qs.get("mode", ["auto"])[0]

        # Determine mode:
        # If mode == 'tcp' or mode == 'bridge': Direct TCP relay to SSH port 22
        # If mode == 'auto' or 'terminal': Interactive PTY terminal
        if mode in ("tcp", "bridge", "tunnel"):
            self.run_tcp_proxy(ws, qs)
        else:
            self.run_interactive_terminal(ws)

    def run_tcp_proxy(self, ws, qs):
        """Direct raw TCP relay to local SSH server (useful for ProxyCommand / Tunnel mode)"""
        target_host = qs.get("host", [SSH_TARGET_HOST])[0]
        target_port = int(qs.get("port", [SSH_TARGET_PORT])[0])

        try:
            ssh_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            ssh_sock.connect((target_host, target_port))
            ssh_sock.setblocking(False)
        except Exception as e:
            ws.send_text(f"Connection to SSH target {target_host}:{target_port} failed: {e}")
            ws.close()
            return

        def ssh_to_ws():
            try:
                while not ws.closed:
                    rlist, _, _ = select.select([ssh_sock], [], [], 1.0)
                    if rlist:
                        data = ssh_sock.recv(8192)
                        if not data:
                            break
                        ws.send_binary(data)
            except Exception:
                pass
            finally:
                ws.close()
                try:
                    ssh_sock.close()
                except Exception:
                    pass

        t = threading.Thread(target=ssh_to_ws, daemon=True)
        t.start()

        try:
            while not ws.closed:
                opcode, payload = ws.read_frame()
                if opcode is None or opcode == 0x8:
                    break
                if payload:
                    ssh_sock.sendall(payload)
        except Exception:
            pass
        finally:
            ws.close()
            try:
                ssh_sock.close()
            except Exception:
                pass

    def run_interactive_terminal(self, ws):
        """Spawns an interactive PTY shell for browser terminal sessions"""
        master_fd, slave_fd = pty.openpty()
        set_pty_size(master_fd, 80, 24)

        pid = os.fork()
        if pid == 0:
            # Child process
            os.close(master_fd)
            os.setsid()
            fcntl.ioctl(slave_fd, termios.TIOCSCTTY, 0)
            os.dup2(slave_fd, 0)
            os.dup2(slave_fd, 1)
            os.dup2(slave_fd, 2)
            if slave_fd > 2:
                os.close(slave_fd)

            os.environ["TERM"] = "xterm-256color"
            os.environ["COLORTERM"] = "truecolor"
            os.environ["LANG"] = "en_US.UTF-8"

            # Execute bash login shell or login
            shell = os.environ.get("SHELL", "/bin/bash")
            os.execv(shell, [shell, "-l"])
            sys.exit(0)

        # Parent process
        os.close(slave_fd)
        flags = fcntl.fcntl(master_fd, fcntl.F_GETFL)
        fcntl.fcntl(master_fd, fcntl.F_SETFL, flags | os.O_NONBLOCK)

        def pty_to_ws():
            try:
                while not ws.closed:
                    rlist, _, _ = select.select([master_fd], [], [], 0.5)
                    if rlist:
                        try:
                            data = os.read(master_fd, 8192)
                            if not data:
                                break
                            ws.send_binary(data)
                        except (BlockingIOError, InterruptedError):
                            continue
                        except Exception:
                            break
            except Exception:
                pass
            finally:
                ws.close()
                try:
                    os.close(master_fd)
                except Exception:
                    pass

        t = threading.Thread(target=pty_to_ws, daemon=True)
        t.start()

        try:
            while not ws.closed:
                opcode, payload = ws.read_frame()
                if opcode is None or opcode == 0x8:
                    break
                if payload:
                    # Check if resize control message
                    if payload.startswith(b"{") and b'"type":' in payload:
                        try:
                            msg = json.loads(payload.decode("utf-8"))
                            if msg.get("type") == "resize":
                                cols = int(msg.get("cols", 80))
                                rows = int(msg.get("rows", 24))
                                set_pty_size(master_fd, cols, rows)
                                continue
                        except Exception:
                            pass
                    os.write(master_fd, payload)
        except Exception:
            pass
        finally:
            ws.close()
            try:
                os.close(master_fd)
            except Exception:
                pass
            try:
                os.kill(pid, 9)
                os.waitpid(pid, 0)
            except Exception:
                pass


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def run_server():
    server = ThreadedHTTPServer((HOST, PORT), WebSshHandler)
    print(f"⚡ Rakhssh Web SSH server running on http://{HOST}:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.server_close()


if __name__ == "__main__":
    run_server()

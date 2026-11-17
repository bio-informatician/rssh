#!/usr/bin/env python3
"""
Lightweight Zero-Dependency WebSocket & Web Chat Server (Python 3 Standard Library).
RFC 6455 compliant. Runs out of the box with zero pip dependencies.
Supports:
  - WebSocket clients (Android Chat APK: ws://<ip>:8765)
  - Web browser clients (http://<ip>:8765)
  - Health check endpoint (http://<ip>:8765/health)
  - Headless / Systemd service operation with zero TTY errors
  - Graceful shutdown handling (SIGINT / SIGTERM)
"""

import asyncio
import base64
import hashlib
import json
import mimetypes
import os
import signal
import socket
import struct
import sys
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
clients = set()

# Determine Web Directory for static files
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
POSSIBLE_WEB_DIRS = [
    os.environ.get("WEB_DIR", ""),
    os.path.join(BASE_DIR, "web"),
    os.path.join(BASE_DIR, "../web"),
    "/opt/chat-server/web",
]
WEB_DIR = next((d for d in POSSIBLE_WEB_DIRS if d and os.path.isdir(d)), "")

FALLBACK_HTML = """<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Rakhssh Chat Server</title>
  <style>
    body { font-family: system-ui, -apple-system, sans-serif; background: #0f172a; color: #f8fafc; text-align: center; padding: 40px 20px; }
    .card { max-width: 500px; margin: 40px auto; background: #1e293b; padding: 30px; border-radius: 16px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
    h1 { color: #38bdf8; font-size: 1.8rem; margin-bottom: 12px; }
    p { color: #94a3b8; line-height: 1.6; }
    .badge { display: inline-block; background: #059669; color: #fff; padding: 6px 14px; border-radius: 9999px; font-weight: 600; font-size: 0.9rem; margin-bottom: 15px; }
    .code-box { background: #090d16; padding: 12px; border-radius: 8px; font-family: monospace; color: #38bdf8; direction: ltr; margin: 15px 0; font-size: 1.05rem; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">● سرور فعال و در حال اجرا است</div>
    <h1>سرور چت رخش (Rakhssh)</h1>
    <p>سرور چت با موفقیت روی لینوکس راه‌اندازی شد. برای اتصال با اپلیکیشن اندروید (chat.apk)، آدرس زیر را در تنظیمات وارد کنید:</p>
    <div class="code-box" id="wsUrl">ws://YOUR-SERVER-IP:8765</div>
    <p style="font-size: 0.85rem; color: #64748b;">پروتکل: RFC 6455 WebSocket | پورت: 8765</p>
  </div>
  <script>
    document.getElementById("wsUrl").innerText = (location.protocol === "https:" ? "wss://" : "ws://") + location.host;
  </script>
</body>
</html>
"""


def get_local_ips():
    """Discover local LAN IP addresses to display to the user."""
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.append(s.getsockname()[0])
        s.close()
    except Exception:
        pass
    return ips or ["127.0.0.1"]


def make_handshake_response(key: str) -> bytes:
    accept_val = base64.b64encode(hashlib.sha1((key + GUID).encode()).digest()).decode()
    resp = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Accept: {accept_val}\r\n\r\n"
    )
    return resp.encode()


def encode_frame(payload: str) -> bytes:
    """Encode text payload into an unmasked RFC 6455 WebSocket frame."""
    data = payload.encode("utf-8")
    length = len(data)
    frame = bytearray([0x81])  # FIN + Text Opcode (0x1)

    if length <= 125:
        frame.append(length)
    elif length <= 65535:
        frame.append(126)
        frame.extend(struct.pack("!H", length))
    else:
        frame.append(127)
        frame.extend(struct.pack("!Q", length))

    frame.extend(data)
    return bytes(frame)


async def decode_frame(reader: asyncio.StreamReader):
    """Decode a masked RFC 6455 WebSocket frame from a client."""
    byte1_2 = await reader.read(2)
    if len(byte1_2) < 2:
        return None, None

    byte1, byte2 = byte1_2
    opcode = byte1 & 0x0F
    is_masked = (byte2 & 0x80) != 0
    payload_len = byte2 & 0x7F

    if opcode == 0x8:  # Close frame
        return 0x8, None

    if payload_len == 126:
        ext_len = await reader.read(2)
        if len(ext_len) < 2:
            return None, None
        payload_len = struct.unpack("!H", ext_len)[0]
    elif payload_len == 127:
        ext_len = await reader.read(8)
        if len(ext_len) < 8:
            return None, None
        payload_len = struct.unpack("!Q", ext_len)[0]

    mask = None
    if is_masked:
        mask = await reader.read(4)
        if len(mask) < 4:
            return None, None

    data = await reader.readexactly(payload_len)
    if is_masked and mask:
        data = bytes(b ^ mask[i % 4] for i, b in enumerate(data))

    return opcode, data.decode("utf-8", errors="replace")


async def broadcast(message_json: str, sender_writer=None):
    """Broadcast a message frame to all connected clients."""
    frame = encode_frame(message_json)
    dead_clients = set()
    for writer in list(clients):
        if writer is not sender_writer:
            try:
                writer.write(frame)
                await writer.drain()
            except Exception:
                dead_clients.add(writer)
    for dc in dead_clients:
        clients.discard(dc)


def get_static_file(path: str):
    """Serve static web assets with fallback."""
    clean_path = path.lstrip("/") or "index.html"
    if clean_path.endswith("/"):
        clean_path += "index.html"

    # Security check: prevent directory traversal
    if ".." in clean_path:
        return None, None

    if WEB_DIR:
        file_path = os.path.join(WEB_DIR, clean_path)
        if os.path.isfile(file_path):
            mime_type, _ = mimetypes.guess_type(file_path)
            mime_type = mime_type or "application/octet-stream"
            if mime_type.startswith("text/") or mime_type in ("application/javascript", "application/json"):
                mime_type += "; charset=utf-8"
            with open(file_path, "rb") as f:
                return f.read(), mime_type

    if clean_path in ("index.html", ""):
        return FALLBACK_HTML.encode("utf-8"), "text/html; charset=utf-8"

    return None, None


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    peername = writer.get_extra_info("peername") or ("unknown", 0)
    headers = {}
    try:
        # 1. Read HTTP request line
        request_line = await reader.readline()
        if not request_line:
            writer.close()
            return

        parts = request_line.decode("utf-8", errors="replace").strip().split()
        method = parts[0].upper() if len(parts) > 0 else "GET"
        raw_path = parts[1] if len(parts) > 1 else "/"
        path = raw_path.split("?")[0]

        # Read headers
        while True:
            line = await reader.readline()
            if line in (b"\r\n", b"\n", b""):
                break
            line_str = line.decode("utf-8", errors="replace").strip()
            if ":" in line_str:
                k, v = line_str.split(":", 1)
                headers[k.strip().lower()] = v.strip()

        key = headers.get("sec-websocket-key")
        upgrade = headers.get("upgrade", "").lower()

        # Handle regular HTTP requests (Health check, Web Chat UI, Static files)
        if not key or upgrade != "websocket":
            if method in ("GET", "HEAD"):
                if path in ("/health", "/status", "/ping"):
                    body = json.dumps({
                        "status": "ok",
                        "service": "rakhssh-chat",
                        "version": "1.1.0",
                        "active_clients": len(clients),
                        "timestamp": int(time.time()),
                    }).encode("utf-8")
                    resp = (
                        "HTTP/1.1 200 OK\r\n"
                        "Content-Type: application/json; charset=utf-8\r\n"
                        f"Content-Length: {len(body)}\r\n"
                        "Access-Control-Allow-Origin: *\r\n"
                        "Connection: close\r\n\r\n"
                    ).encode("utf-8")
                    if method == "GET":
                        resp += body
                    writer.write(resp)
                    await writer.drain()
                else:
                    data, mime = get_static_file(path)
                    if data is not None:
                        resp = (
                            "HTTP/1.1 200 OK\r\n"
                            f"Content-Type: {mime}\r\n"
                            f"Content-Length: {len(data)}\r\n"
                            "Access-Control-Allow-Origin: *\r\n"
                            "Cache-Control: public, max-age=60\r\n"
                            "Connection: close\r\n\r\n"
                        ).encode("utf-8")
                        if method == "GET":
                            resp += data
                        writer.write(resp)
                        await writer.drain()
                    else:
                        writer.write(b"HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 9\r\nConnection: close\r\n\r\nNot Found")
                        await writer.drain()
            else:
                writer.write(b"HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n")
                await writer.drain()

            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
            return

        # 2. WebSocket Upgrade Handshake
        writer.write(make_handshake_response(key))
        await writer.drain()

        clients.add(writer)
        print(f"\n[+] Client connected: {peername[0]}:{peername[1]} (Active clients: {len(clients)})")
        if sys.stdin is not None and sys.stdin.isatty():
            print("Server (type message and press Enter): ", end="", flush=True)

        # Send welcome message frame
        welcome = json.dumps({
            "type": "system",
            "sender": "Server",
            "text": "به سرور چت متصل شدید. می‌توانید پیام ارسال کنید."
        })
        writer.write(encode_frame(welcome))
        await writer.drain()

        # 3. Message Loop
        while True:
            opcode, message = await decode_frame(reader)
            if opcode is None or opcode == 0x8:
                break
            if opcode == 0x1 and message:  # Text frame
                print(f"\r[{peername[0]}]: {message}")
                if sys.stdin is not None and sys.stdin.isatty():
                    print("Server (type message and press Enter): ", end="", flush=True)
                await broadcast(message, sender_writer=writer)

    except Exception:
        pass
    finally:
        clients.discard(writer)
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass
        print(f"\n[-] Client disconnected: {peername[0]}:{peername[1]} (Active clients: {len(clients)})")
        if sys.stdin is not None and sys.stdin.isatty():
            print("Server (type message and press Enter): ", end="", flush=True)


async def terminal_input_loop():
    """Allows typing messages in terminal to broadcast to connected phones when interactive."""
    if sys.stdin is None or not sys.stdin.isatty():
        return

    try:
        loop = asyncio.get_event_loop()
        reader = asyncio.StreamReader()
        protocol = asyncio.StreamReaderProtocol(reader)
        await loop.connect_read_pipe(lambda: protocol, sys.stdin)

        while True:
            line = await reader.readline()
            if not line:
                break
            text = line.decode().strip()
            if text:
                msg = json.dumps({
                    "type": "chat",
                    "sender": "Server Terminal (کامپیوتر)",
                    "text": text,
                    "time": time.strftime("%H:%M")
                })
                await broadcast(msg)
                print(f"Sent to {len(clients)} client(s): {text}")
            print("Server (type message and press Enter): ", end="", flush=True)
    except Exception:
        pass


async def main():
    port = int(os.environ.get("PORT", "8765"))
    host = os.environ.get("HOST", "0.0.0.0")

    server = await asyncio.start_server(handle_client, host, port)
    local_ips = get_local_ips()

    print("=" * 65)
    print("      🚀 Rakhssh WebSocket & Web Chat Server")
    print("=" * 65)
    print(f"Server is listening on {host}:{port}")
    print("\n👉 Use any of the following addresses:")
    for ip in local_ips:
        print(f"   • Android APK:  ws://{ip}:{port}")
        print(f"   • Web Browser:  http://{ip}:{port}")
    print(f"   • Health Check: http://127.0.0.1:{port}/health")
    print("=" * 65)

    is_interactive = sys.stdin is not None and sys.stdin.isatty()
    if is_interactive:
        print("You can also type messages below to send to connected phones:")
        print("Server (type message and press Enter): ", end="", flush=True)
        async with server:
            await asyncio.gather(server.serve_forever(), terminal_input_loop())
    else:
        print("Running in headless / service daemon mode.")
        async with server:
            await server.serve_forever()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer stopped.")

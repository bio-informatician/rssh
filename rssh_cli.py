#!/usr/bin/env python3
"""
Rakhssh SSH CLI - Fast, Interactive Terminal SSH Client
Supports Direct OpenSSH PTY connection, saved profiles, latency tests,
and native RFC 6455 WebSocket proxy tunneling.
"""

import os
import sys
import json
import time
import socket
import ssl
import select
import subprocess
import argparse
import base64
import hashlib
import urllib.parse
from pathlib import Path

VERSION = "1.0.0"
CONFIG_FILE = Path.home() / ".rssh_cli_profiles.json"
DEFAULT_HOST = "193.168.175.227"
DEFAULT_PORT = 22
DEFAULT_USER = "agent"

# Colors for TUI
C_RESET = "\033[0m"
C_BOLD = "\033[1m"
C_GREEN = "\033[1;32m"
C_CYAN = "\033[1;36m"
C_YELLOW = "\033[1;33m"
C_RED = "\033[1;31m"
C_GRAY = "\033[90m"
C_MAGENTA = "\033[1;35m"


def print_banner():
    print(f"{C_CYAN}╔════════════════════════════════════════════════════════════╗{C_RESET}")
    print(f"{C_CYAN}║{C_RESET}     {C_GREEN}⚡ رخش ترمینال خط فرمان (Rakhssh SSH CLI v{VERSION}){C_RESET}        {C_CYAN}║{C_RESET}")
    print(f"{C_CYAN}╠════════════════════════════════════════════════════════════╣{C_RESET}")
    print(f"{C_CYAN}║{C_RESET} {C_GRAY}• کلاینت مستقل و سبک با پشتیبانی از سوکت مستقیم و تونل WSS{C_RESET} {C_CYAN}║{C_RESET}")
    print(f"{C_CYAN}║{C_RESET} {C_GRAY}• سازگار با لینوکس، مک، ویندوز و Termux{C_RESET}                   {C_CYAN}║{C_RESET}")
    print(f"{C_CYAN}╚════════════════════════════════════════════════════════════╝{C_RESET}")


def load_profiles():
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return []
    return []


def save_profiles(profiles):
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(profiles, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"{C_RED}خطا در ذخیره پروفایل‌ها: {e}{C_RESET}")


def measure_ping(host, port=22, timeout=3.0):
    start = time.time()
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        sock.connect((host, port))
        sock.close()
        latency = (time.time() - start) * 1000.0
        return True, latency
    except Exception as e:
        return False, str(e)


def run_direct_ssh(host, port=22, user="agent", identity=None, extra_args=None):
    cmd = ["ssh", "-p", str(port)]
    if identity:
        cmd.extend(["-i", identity])
    cmd.extend([
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR"
    ])
    if extra_args:
        cmd.extend(extra_args)
    
    target = f"{user}@{host}" if user else host
    cmd.append(target)
    
    print(f"{C_GREEN}--> در حال اتصال مستقیم به {target}:{port}...{C_RESET}")
    try:
        res = subprocess.call(cmd)
        return res
    except KeyboardInterrupt:
        return 0
    except Exception as e:
        print(f"{C_RED}خطا در اجرای SSH: {e}{C_RESET}")
        return 1


def run_tunnel_ssh(ws_url, host=DEFAULT_HOST, port=22, user="agent", identity=None):
    script_path = os.path.abspath(__file__)
    proxy_cmd = f"python3 '{script_path}' --bridge '{ws_url}'"
    
    cmd = [
        "ssh",
        "-o", f"ProxyCommand={proxy_cmd}",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-o", "LogLevel=ERROR",
        "-p", str(port)
    ]
    if identity:
        cmd.extend(["-i", identity])
    
    target = f"{user}@{host}" if user else host
    cmd.append(target)
    
    print(f"{C_MAGENTA}--> در حال اتصال از طریق تونل وب اس اس اچ: {ws_url}...{C_RESET}")
    try:
        return subprocess.call(cmd)
    except KeyboardInterrupt:
        return 0
    except Exception as e:
        print(f"{C_RED}خطای اتصال تونل: {e}{C_RESET}")
        return 1


def run_websocket_bridge(ws_url):
    """
    Pure Python RFC 6455 WebSocket client bridge for OpenSSH ProxyCommand.
    Pipes stdin/stdout directly to/from the WebSocket.
    """
    parsed = urllib.parse.urlparse(ws_url)
    is_secure = parsed.scheme in ("wss", "https")
    host = parsed.hostname
    port = parsed.port or (443 if is_secure else 80)
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query

    raw_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    raw_sock.settimeout(10)
    raw_sock.connect((host, port))

    if is_secure:
        ctx = ssl.create_default_context()
        sock = ctx.wrap_socket(raw_sock, server_hostname=host)
    else:
        sock = raw_sock

    # WebSocket Handshake
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    headers = [
        f"GET {path} HTTP/1.1",
        f"Host: {host}:{port}",
        "Upgrade: websocket",
        "Connection: Upgrade",
        f"Sec-WebSocket-Key: {key}",
        "Sec-WebSocket-Version: 13",
        "\r\n"
    ]
    sock.sendall("\r\n".join(headers).encode("ascii"))

    # Read Handshake Response
    resp = b""
    while b"\r\n\r\n" not in resp:
        chunk = sock.recv(4096)
        if not chunk:
            raise ConnectionError("Server closed connection during handshake")
        resp += chunk

    status_line = resp.split(b"\r\n")[0]
    if b" 101 " not in status_line:
        raise ConnectionError(f"WebSocket handshake failed: {status_line.decode('ascii', errors='replace')}")

    sock.setblocking(False)

    # Stdio to WS bidirectional pipe
    stdin_fd = sys.stdin.fileno()
    sock_fd = sock.fileno()

    try:
        while True:
            rlist, _, _ = select.select([stdin_fd, sock_fd], [], [], 30.0)
            if not rlist:
                # Send ping frame
                continue

            if stdin_fd in rlist:
                data = os.read(stdin_fd, 8192)
                if not data:
                    break
                # Send binary WebSocket frame (opcode 0x2, masked)
                frame = bytearray()
                frame.append(0x82)  # FIN + binary
                length = len(data)
                mask_key = os.urandom(4)
                if length < 126:
                    frame.append(0x80 | length)
                elif length <= 65535:
                    frame.append(0x80 | 126)
                    frame.extend(length.to_bytes(2, "big"))
                else:
                    frame.append(0x80 | 127)
                    frame.extend(length.to_bytes(8, "big"))
                frame.extend(mask_key)
                masked_data = bytearray(b ^ mask_key[i % 4] for i, b in enumerate(data))
                frame.extend(masked_data)
                sock.sendall(frame)

            if sock_fd in rlist:
                # Read WS frame header
                header = sock.recv(2)
                if not header:
                    break
                b1, b2 = header[0], header[1]
                opcode = b1 & 0x0f
                if opcode == 0x8:  # Close
                    break
                payload_len = b2 & 0x7f
                if payload_len == 126:
                    ext = sock.recv(2)
                    payload_len = int.from_bytes(ext, "big")
                elif payload_len == 127:
                    ext = sock.recv(8)
                    payload_len = int.from_bytes(ext, "big")

                is_masked = bool(b2 & 0x80)
                mask = sock.recv(4) if is_masked else None

                payload = b""
                while len(payload) < payload_len:
                    part = sock.recv(payload_len - len(payload))
                    if not part:
                        break
                    payload += part

                if is_masked:
                    payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))

                if opcode in (0x1, 0x2):  # Text or binary
                    sys.stdout.buffer.write(payload)
                    sys.stdout.buffer.flush()

    except Exception:
        pass
    finally:
        sock.close()


def interactive_menu():
    print_banner()
    profiles = load_profiles()

    ok, lat = measure_ping(DEFAULT_HOST, DEFAULT_PORT)
    status_str = f"{C_GREEN}🟢 برخط ({lat:.1f}ms){C_RESET}" if ok else f"{C_RED}🔴 آفلاین یا فیلتر{C_RESET}"

    while True:
        print(f"\n{C_BOLD}وضعیت سرور پیش‌فرض:{C_RESET} {DEFAULT_HOST}:{DEFAULT_PORT} ➔ {status_str}")
        print(f"\n{C_BOLD}انتخاب عملیات:{C_RESET}")
        print(f"  {C_GREEN}[1]{C_RESET} ⚡ اتصال مستقیم به سرور فعلی ({DEFAULT_USER}@{DEFAULT_HOST}:{DEFAULT_PORT})")
        print(f"  {C_MAGENTA}[2]{C_RESET} ☁️ اتصال امن از طریق تونل وب اس اس اچ (WebSocket / Cloudflare)")
        print(f"  {C_CYAN}[3]{C_RESET} 📋 فهرست سرورهای ذخیره‌شده ({len(profiles)} سرور)")
        print(f"  {C_YELLOW}[4]{C_RESET} ➕ اتصال سریع به سرور جدید")
        print(f"  {C_BOLD}[5]{C_RESET} 🎯 تست پینگ و بررسی تاخیر سرورها")
        print(f"  {C_RED}[q]{C_RESET} خروج\n")

        choice = input(f"{C_BOLD}گزینه مورد نظر (1-5, q): {C_RESET}").strip()

        if choice == "1":
            run_direct_ssh(DEFAULT_HOST, DEFAULT_PORT, DEFAULT_USER)
        elif choice == "2":
            cf_url = input(f"آدرس تونل WSS [پیش‌فرض: wss://occurring-nearby-salvador-photography.trycloudflare.com/ws/ssh]: ").strip()
            if not cf_url:
                cf_url = "wss://occurring-nearby-salvador-photography.trycloudflare.com/ws/ssh"
            run_tunnel_ssh(cf_url, DEFAULT_HOST, DEFAULT_PORT, DEFAULT_USER)
        elif choice == "3":
            if not profiles:
                print(f"{C_YELLOW}هیچ سروری ذخیره نشده است.{C_RESET}")
                continue
            print(f"\n{C_CYAN}--- سرورهای ذخیره‌شده ---{C_RESET}")
            for idx, p in enumerate(profiles, 1):
                print(f"  [{idx}] {p['name']} ➔ {p.get('user', 'root')}@{p['host']}:{p.get('port', 22)}")
            sel = input("\nشماره سرور برای اتصال (یا Enter برای برگشت): ").strip()
            if sel.isdigit() and 1 <= int(sel) <= len(profiles):
                p = profiles[int(sel) - 1]
                run_direct_ssh(p['host'], p.get('port', 22), p.get('user', 'root'), p.get('identity'))
        elif choice == "4":
            host = input("آدرس سرور (IP یا Domain): ").strip()
            if not host:
                continue
            port_str = input("پورت [22]: ").strip()
            port = int(port_str) if port_str.isdigit() else 22
            user = input("نام کاربری [root]: ").strip() or "root"
            save = input("آیا مایلید این سرور ذخیره شود؟ (y/n) [y]: ").strip().lower()
            if save != "n":
                name = input(f"نام دلخواه برای سرور [{user}@{host}]: ").strip() or f"{user}@{host}"
                profiles.append({"name": name, "host": host, "port": port, "user": user})
                save_profiles(profiles)
                print(f"{C_GREEN}سرور ذخیره شد.{C_RESET}")
            run_direct_ssh(host, port, user)
        elif choice == "5":
            target = input(f"آدرس سرور برای بررسی پینگ [{DEFAULT_HOST}]: ").strip() or DEFAULT_HOST
            port = 22
            print(f"در حال اندازه‌گیری پینگ TCP به {target}:{port}...")
            ok, res = measure_ping(target, port)
            if ok:
                print(f"{C_GREEN}✅ ارتباط با سرور برقرار است! تاخیر زمانی (Ping): {res:.1f} میلی‌ثانیه{C_RESET}")
            else:
                print(f"{C_RED}❌ خطا در اتصال به سرور: {res}{C_RESET}")
        elif choice.lower() in ("q", "exit", "quit"):
            print("خداحافظ!")
            break


def main():
    parser = argparse.ArgumentParser(description=f"Rakhssh SSH CLI v{VERSION}")
    parser.add_argument("target", nargs="?", help="[user@]host[:port]")
    parser.add_argument("-p", "--port", type=int, default=22, help="SSH port")
    parser.add_argument("-u", "--user", default="agent", help="SSH username")
    parser.add_argument("-i", "--identity", help="Path to private key")
    parser.add_argument("-W", "--tunnel", help="Connect through WebSocket tunnel URL")
    parser.add_argument("--bridge", help="Internal: Run stdio-websocket bridge mode")
    parser.add_argument("--ping", action="store_true", help="Measure latency and exit")
    parser.add_argument("--list", action="store_true", help="List saved profiles")

    args, unknown = parser.parse_known_args()

    if args.bridge:
        run_websocket_bridge(args.bridge)
        return

    if args.ping:
        host = args.target or DEFAULT_HOST
        ok, res = measure_ping(host, args.port)
        if ok:
            print(f"PING OK: {res:.1f} ms to {host}:{args.port}")
            sys.exit(0)
        else:
            print(f"PING FAIL: {res}")
            sys.exit(1)

    if args.list:
        profiles = load_profiles()
        print(f"Saved Profiles ({len(profiles)}):")
        for p in profiles:
            print(f" - {p['name']}: {p.get('user', 'root')}@{p['host']}:{p.get('port', 22)}")
        return

    if not args.target:
        interactive_menu()
        return

    # Parse target string
    target = args.target
    user = args.user
    port = args.port

    if "@" in target:
        user, target = target.split("@", 1)
    if ":" in target:
        target, port_str = target.split(":", 1)
        if port_str.isdigit():
            port = int(port_str)

    if args.tunnel:
        run_tunnel_ssh(args.tunnel, target, port, user, args.identity)
    else:
        run_direct_ssh(target, port, user, args.identity, unknown)


if __name__ == "__main__":
    main()

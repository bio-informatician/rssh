#!/usr/bin/env bash
# ==============================================================================
# 🚀 Rakhssh Chat Server v1.2.0 - Ubuntu Auto Installer & Systemd Service Setup
# Self-contained, automated installer for Ubuntu 20.04 / 22.04 / 24.04 LTS.
# Supports Android (chat.apk), iOS (PWA Web App), and Web Browsers.
#
# Usage:
#   sudo bash install.sh
#   sudo bash install.sh --port 8765
#   sudo bash install.sh --uninstall
#   bash install.sh --version
# ==============================================================================

set -e

# Version
INSTALLER_VERSION="1.2.0"

# ANSI Color codes
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_GREEN='\033[32m'
C_CYAN='\033[36m'
C_YELLOW='\033[33m'
C_RED='\033[31m'
C_BLUE='\033[34m'
C_MAGENTA='\033[35m'

INSTALL_DIR="/opt/chat-server"
SERVICE_NAME="chat-server"
SYSTEMD_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
APP_USER="chatserver"
DEFAULT_PORT="8765"
PORT="${DEFAULT_PORT}"

# Parse Command Line Arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"
      shift 2
      ;;
    --uninstall)
      ACTION="uninstall"
      shift
      ;;
    --version|-v)
      echo "Rakhssh Chat Server Installer v${INSTALLER_VERSION}"
      exit 0
      ;;
    --help|-h)
      echo -e "${C_BOLD}راهنمای نصب سرور چت رخش (Rakhssh Chat Server Installer v${INSTALLER_VERSION})${C_RESET}"
      echo "دستورات قابل استفاده:"
      echo "  sudo bash install.sh               نصب و راه‌اندازی کامل خودکار روی پورت پیش‌فرض (8765)"
      echo "  sudo bash install.sh --port 9000   نصب روی پورت سفارشی (مثلاً 9000)"
      echo "  sudo bash install.sh --uninstall   حذف کامل سرویس و فایل‌ها از سرور"
      echo "  bash install.sh --version          نمایش نسخه اسکریپت نصاب"
      exit 0
      ;;
    *)
      echo -e "${C_RED}گزینه ناشناخته: $1${C_RESET}"
      exit 1
      ;;
  esac
done

# Banner
echo -e "${C_CYAN}${C_BOLD}"
echo "========================================================================"
echo "    🚀  Rakhssh Chat Server v${INSTALLER_VERSION} (نصب خودکار سرور چت)               "
echo "========================================================================"
echo -e "${C_RESET}"

# Check Root Privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${C_RED}${C_BOLD}❌ خطا: این اسکریپت باید با دسترسی روت (sudo) اجرا شود.${C_RESET}"
  echo -e "لطفاً با دستور زیر اجرا کنید:"
  echo -e "   ${C_YELLOW}sudo bash $0${C_RESET}"
  exit 1
fi

# Handle Uninstall Option
if [ "$ACTION" == "uninstall" ]; then
  echo -e "${C_YELLOW}⚠️ در حال حذف کامل سرویس و فایل‌های سرور چت...${C_RESET}"
  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "${SYSTEMD_FILE}"
  systemctl daemon-reload 2>/dev/null || true
  rm -rf "${INSTALL_DIR}"
  if id -u "${APP_USER}" >/dev/null 2>&1; then
    userdel "${APP_USER}" 2>/dev/null || true
  fi
  echo -e "${C_GREEN}✅ سرور چت و سرویس سیستم با موفقیت به طور کامل حذف شدند.${C_RESET}"
  exit 0
fi

# 1. Update APT & Install Prerequisites
echo -e "${C_BLUE}▶ مرحله ۱/۶: بررسی و نصب پیش‌نیازهای سیستمی (Python 3, Curl)...${C_RESET}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 curl ufw >/dev/null

echo -e "${C_GREEN}   ✔ پایتون ۳ و ابزارهای لازم تأیید شدند.${C_RESET}"

# 2. Create System User and Directory Structure
echo -e "${C_BLUE}▶ مرحله ۲/۶: ساخت کاربر سیستمی و پوشه‌های کاری...${C_RESET}"
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  useradd -r -s /usr/sbin/nologin -d "${INSTALL_DIR}" -M "${APP_USER}"
  echo -e "${C_GREEN}   ✔ کاربر ایزوله سیستمی ${APP_USER} ساخته شد.${C_RESET}"
else
  echo -e "${C_GREEN}   ✔ کاربر سیستمی ${APP_USER} موجود است.${C_RESET}"
fi

mkdir -p "${INSTALL_DIR}/web"

# 3. Deploy Server Application & Web Assets
echo -e "${C_BLUE}▶ مرحله ۳/۶: نصب برنامه سرور و رابط کاربری وب و iOS PWA...${C_RESET}"

cat << 'SERVER_EOF' > "${INSTALL_DIR}/server.py"
#!/usr/bin/env python3
"""
Lightweight Zero-Dependency WebSocket & Web Chat Server (Python 3 Standard Library).
RFC 6455 compliant. Runs out of the box with zero pip dependencies.
Supports:
  - Private password-protected rooms (Zero room listing / Strict room isolation)
  - WebSocket clients (Android Chat APK: ws://<ip>:8765)
  - Web browser clients (http://<ip>:8765)
  - Background keepalive (RFC 6455 Ping/Pong + JSON Heartbeats)
  - Health check endpoint (http://<ip>:8765/health)
  - Headless / Systemd service operation with zero TTY errors
  - Graceful shutdown handling (SIGINT / SIGTERM)
"""

import asyncio
import base64
import hashlib
import hmac
import json
import mimetypes
import os
import secrets
import signal
import socket
import struct
import sys
import time

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
VERSION = "1.2.0"

# Connected WebSocket clients
clients = set()

# client_info: writer -> {"peer": (ip, port), "room": str|None, "nickname": str|None, "authenticated": bool}
client_info = {}

# rooms: room_name -> {"salt": hex, "hash": hex, "created_at": float, "creator": str, "clients": set(writers)}
rooms = {}

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
    <div class="badge">● سرور فعال و در حال اجرا است (v1.2.0)</div>
    <h1>سرور چت رخش (Rakhssh)</h1>
    <p>سرور چت با اتاق‌های رمزگذاری شده روی لینوکس راه‌اندازی شد. برای اتصال با اپلیکیشن اندروید (chat.apk)، آدرس زیر را در تنظیمات وارد کنید:</p>
    <div class="code-box" id="wsUrl">ws://YOUR-SERVER-IP:8765</div>
    <p style="font-size: 0.85rem; color: #64748b;">پروتکل: RFC 6455 WebSocket | پورت: 8765</p>
  </div>
  <script>
    document.getElementById("wsUrl").innerText = (location.protocol === "https:" ? "wss://" : "ws://") + location.host;
  </script>
</body>
</html>
"""


def hash_password(password: str, salt: str) -> str:
    """Compute cryptographic hash of password using salt."""
    return hashlib.sha256((salt + password).encode("utf-8")).hexdigest()


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


def encode_frame(payload: str, opcode: int = 0x1) -> bytes:
    """Encode text payload into an unmasked RFC 6455 WebSocket frame."""
    data = payload.encode("utf-8") if isinstance(payload, str) else payload
    length = len(data)
    frame = bytearray([0x80 | (opcode & 0x0F)])  # FIN + Opcode

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

    if opcode in (0x9, 0xA):  # Ping / Pong
        return opcode, data

    return opcode, data.decode("utf-8", errors="replace")


async def broadcast_room(room_name: str, message_json: str, sender_writer=None):
    """Broadcast a message frame ONLY to authenticated clients inside a specific room."""
    if not room_name or room_name not in rooms:
        return
    frame = encode_frame(message_json)
    dead_clients = set()
    for writer in list(rooms[room_name]["clients"]):
        if writer is not sender_writer:
            try:
                writer.write(frame)
                await writer.drain()
            except Exception:
                dead_clients.add(writer)
    for dc in dead_clients:
        rooms[room_name]["clients"].discard(dc)
        clients.discard(dc)
        client_info.pop(dc, None)


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
                        "version": VERSION,
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
        client_info[writer] = {
            "peer": peername,
            "room": None,
            "nickname": None,
            "authenticated": False,
        }
        print(f"\n[+] Client connected: {peername[0]}:{peername[1]} (Active clients: {len(clients)})")
        if sys.stdin is not None and sys.stdin.isatty():
            print("Server (type message and press Enter): ", end="", flush=True)

        # Send welcome message frame (Prompt to join a private room)
        welcome = json.dumps({
            "type": "system",
            "sender": "Server",
            "text": "به سرور چت امن رخش متصل شدید. لطفاً نام اتاق و رمز عبور را وارد کنید."
        }, ensure_ascii=False)
        writer.write(encode_frame(welcome))
        await writer.drain()

        # 3. Message Loop
        while True:
            opcode, message = await decode_frame(reader)
            if opcode is None or opcode == 0x8:  # Client closed
                break

            if opcode == 0x9:  # RFC 6455 Ping frame -> Respond with Pong frame (0xA)
                writer.write(encode_frame(message or b"", opcode=0xA))
                await writer.drain()
                continue

            if opcode == 0xA:  # Pong frame received
                continue

            if opcode == 0x1 and message:  # Text frame
                try:
                    payload = json.loads(message)
                except Exception:
                    continue

                msg_type = payload.get("type")

                # Heartbeat Ping from Web/Android client
                if msg_type == "ping":
                    pong_resp = json.dumps({"type": "pong", "time": int(time.time())})
                    writer.write(encode_frame(pong_resp))
                    await writer.drain()
                    continue

                # Room Join / Authentication request
                if msg_type == "join":
                    raw_room = str(payload.get("room") or "").strip()
                    password = str(payload.get("password") or "").strip()
                    sender = str(payload.get("sender") or "").strip() or "کاربر"

                    if not raw_room:
                        err = json.dumps({
                            "type": "auth_error",
                            "text": "نام اتاق نمی‌تواند خالی باشد."
                        }, ensure_ascii=False)
                        writer.write(encode_frame(err))
                        await writer.drain()
                        continue

                    if not password:
                        err = json.dumps({
                            "type": "auth_error",
                            "text": "رمز عبور اتاق الزامی است."
                        }, ensure_ascii=False)
                        writer.write(encode_frame(err))
                        await writer.drain()
                        continue

                    room_id = raw_room.lower()

                    # Check or create room
                    if room_id not in rooms:
                        salt = secrets.token_hex(16)
                        pw_hash = hash_password(password, salt)
                        rooms[room_id] = {
                            "name": raw_room,
                            "salt": salt,
                            "hash": pw_hash,
                            "created_at": time.time(),
                            "creator": sender,
                            "clients": set(),
                        }
                        print(f"🔒 [Room Created] '{room_id}' by '{sender}' from {peername[0]}")
                    else:
                        salt = rooms[room_id]["salt"]
                        expected_hash = rooms[room_id]["hash"]
                        provided_hash = hash_password(password, salt)
                        if not hmac.compare_digest(provided_hash, expected_hash):
                            print(f"⛔ [Auth Failed] '{sender}' wrong password for '{room_id}' from {peername[0]}")
                            err = json.dumps({
                                "type": "auth_error",
                                "room": raw_room,
                                "text": "رمز عبور اتاق نادرست است! دسترسی غیرمجاز."
                            }, ensure_ascii=False)
                            writer.write(encode_frame(err))
                            await writer.drain()
                            continue

                    # Remove from old room if already joined
                    old_room = client_info[writer].get("room")
                    if old_room and old_room in rooms:
                        rooms[old_room]["clients"].discard(writer)

                    # Authorize client in room
                    rooms[room_id]["clients"].add(writer)
                    client_info[writer] = {
                        "peer": peername,
                        "room": room_id,
                        "room_display": raw_room,
                        "nickname": sender,
                        "authenticated": True,
                    }

                    print(f"🔑 [Auth Success] '{sender}' joined room '{room_id}' (Members: {len(rooms[room_id]['clients'])})")

                    success_resp = json.dumps({
                        "type": "auth_success",
                        "room": raw_room,
                        "sender": sender,
                        "text": f"با موفقیت به اتاق امن «{raw_room}» متصل شدید."
                    }, ensure_ascii=False)
                    writer.write(encode_frame(success_resp))
                    await writer.drain()

                    # Notify other members of this room ONLY
                    join_announce = json.dumps({
                        "type": "system",
                        "room": raw_room,
                        "text": f"«{sender}» وارد اتاق شد."
                    }, ensure_ascii=False)
                    await broadcast_room(room_id, join_announce, sender_writer=writer)
                    continue

                # Room Chat message
                if msg_type == "chat":
                    info = client_info.get(writer)
                    if not info or not info.get("authenticated") or not info.get("room"):
                        err = json.dumps({
                            "type": "auth_error",
                            "text": "خطا: شما ابتدا باید با نام و رمز عبور وارد یک اتاق شوید."
                        }, ensure_ascii=False)
                        writer.write(encode_frame(err))
                        await writer.drain()
                        continue

                    current_room = info["room"]
                    display_room = info.get("room_display", current_room)
                    sender = info["nickname"]
                    text = str(payload.get("text") or "").strip()
                    time_str = payload.get("time") or time.strftime("%H:%M")

                    if not text:
                        continue

                    print(f"[{display_room}] [{sender}]: {text}")
                    if sys.stdin is not None and sys.stdin.isatty():
                        print("Server (type message and press Enter): ", end="", flush=True)

                    out_msg = json.dumps({
                        "type": "chat",
                        "room": display_room,
                        "sender": sender,
                        "text": text,
                        "time": time_str
                    }, ensure_ascii=False)

                    # Strictly broadcast only to members of this room
                    await broadcast_room(current_room, out_msg, sender_writer=writer)
                    continue

                # Leave room request
                if msg_type == "leave":
                    info = client_info.get(writer)
                    if info and info.get("room"):
                        r = info["room"]
                        s = info.get("nickname", "کاربر")
                        if r in rooms:
                            rooms[r]["clients"].discard(writer)
                            leave_msg = json.dumps({
                                "type": "system",
                                "room": info.get("room_display", r),
                                "text": f"«{s}» از اتاق خارج شد."
                            }, ensure_ascii=False)
                            await broadcast_room(r, leave_msg)
                        info["room"] = None
                        info["authenticated"] = False
                    continue

    except Exception:
        pass
    finally:
        clients.discard(writer)
        info = client_info.pop(writer, None)
        if info and info.get("authenticated") and info.get("room"):
            r = info["room"]
            s = info.get("nickname", "کاربر")
            if r in rooms:
                rooms[r]["clients"].discard(writer)
                if rooms[r]["clients"]:
                    leave_msg = json.dumps({
                        "type": "system",
                        "room": info.get("room_display", r),
                        "text": f"«{s}» از گفتگو خارج شد."
                    }, ensure_ascii=False)
                    asyncio.create_task(broadcast_room(r, leave_msg))

        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass
        print(f"\n[-] Client disconnected: {peername[0]}:{peername[1]} (Active clients: {len(clients)})")
        if sys.stdin is not None and sys.stdin.isatty():
            print("Server (type message and press Enter): ", end="", flush=True)


async def terminal_input_loop():
    """Allows typing broadcast messages from terminal if running interactively."""
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
                # Terminal broadcast to all rooms
                for room_id in list(rooms.keys()):
                    msg = json.dumps({
                        "type": "chat",
                        "room": rooms[room_id].get("name", room_id),
                        "sender": "Server Terminal (مدیر)",
                        "text": text,
                        "time": time.strftime("%H:%M")
                    }, ensure_ascii=False)
                    await broadcast_room(room_id, msg)
                print(f"Sent to active rooms: {text}")
            print("Server (type message and press Enter): ", end="", flush=True)
    except Exception:
        pass


async def main():
    port = int(os.environ.get("PORT", "8765"))
    host = os.environ.get("HOST", "0.0.0.0")

    server = await asyncio.start_server(handle_client, host, port)
    local_ips = get_local_ips()

    print("=" * 65)
    print("      🚀 Rakhssh Secure WebSocket & Web Chat Server v1.2.0")
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
        print("Interactive mode active. Type message and press Enter:")
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

SERVER_EOF

cat << 'INDEX_EOF' > "${INSTALL_DIR}/web/index.html"
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <title>رخش چت - پیام‌رسان امن و خصوصی</title>
  
  <!-- Apple iOS PWA Meta Tags -->
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="Rakhssh Chat">
  <link rel="apple-touch-icon" href="apple-touch-icon.png">
  <link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png">

  <!-- Web App Manifest -->
  <link rel="manifest" href="manifest.json">
  <meta name="theme-color" content="#0b0f19">

  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div class="app-container">
    <!-- Top Bar -->
    <header class="app-header">
      <div class="header-left">
        <button id="btnSettings" class="icon-btn" title="تنظیمات سرور">
          <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none">
            <circle cx="12" cy="12" r="3"></circle>
            <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"></path>
          </svg>
        </button>

        <button id="btnLeaveRoom" class="icon-btn hidden" title="خروج از اتاق">
          <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none">
            <path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"></path>
            <polyline points="16 17 21 12 16 7"></polyline>
            <line x1="21" y1="12" x2="9" y2="12"></line>
          </svg>
        </button>
      </div>

      <div class="header-center">
        <div class="app-title">
          <span>رخش چت</span>
          <span class="version-tag">v1.2.0</span>
        </div>
        <div class="connection-status">
          <span id="statusIndicator" class="status-dot disconnected"></span>
          <span id="statusText">در انتظار اتصال</span>
          <span id="roomStatusBadge" class="room-pill hidden">🔒 <span id="currentRoomDisplay"></span></span>
        </div>
      </div>

      <div class="header-right">
        <button id="btnNotification" class="icon-btn" title="اعلان پیام‌ها و صفحه قفل">
          <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none">
            <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"></path>
            <path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
          </svg>
        </button>
        <button id="btnClear" class="icon-btn hidden" title="پاکسازی صفحه چت">
          <svg viewBox="0 0 24 24" width="19" height="19" stroke="currentColor" stroke-width="2" fill="none">
            <polyline points="3 6 5 6 21 6"></polyline>
            <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
          </svg>
        </button>
      </div>
    </header>

    <!-- Room Gate: Shown when user is not inside an authorized room -->
    <div id="roomGate" class="gate-container">
      <div class="gate-card">
        <div class="gate-shield-icon">
          <svg viewBox="0 0 24 24" width="44" height="44" stroke="#38bdf8" stroke-width="1.8" fill="none">
            <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"></path>
            <path d="M9 12l2 2 4-4"></path>
          </svg>
        </div>

        <h2>ورود به اتاق امن و اختصاصی</h2>
        <p class="gate-desc">
          فهرست گروه‌ها برای حفظ حریم خصوصی مخفی است. برای پیوستن، نام دقیق گروه و رمز عبور اختصاصی آن را وارد کنید.
        </p>

        <div id="gateError" class="alert-box danger hidden">
          <span id="gateErrorText">رمز عبور اتاق نادرست است!</span>
        </div>

        <form id="gateForm" class="gate-form">
          <div class="form-group">
            <label for="gateNickname">نام شما (نام مستعار):</label>
            <input 
              type="text" 
              id="gateNickname" 
              placeholder="مثلاً: آرش، گوشی من، مدیر" 
              required
            />
          </div>

          <div class="form-group">
            <label for="gateRoomName">نام گروه / اتاق:</label>
            <input 
              type="text" 
              id="gateRoomName" 
              dir="ltr"
              placeholder="مثلاً: team-secret یا family-vip" 
              required
            />
          </div>

          <div class="form-group">
            <label for="gateRoomPassword">رمز سخت و اختصاصی اتاق:</label>
            <div class="password-wrapper">
              <input 
                type="password" 
                id="gateRoomPassword" 
                dir="ltr"
                placeholder="رمز عبور قوی اتاق" 
                required
              />
              <button type="button" id="btnTogglePassword" class="toggle-pwd-btn" title="نمایش/مخفی‌سازی رمز">
                👁️
              </button>
            </div>
            <small class="field-hint">اگر اتاق هنوز ایجاد نشده باشد، با این رمز ساخته می‌شود.</small>
          </div>

          <div class="form-group advanced-toggle-group">
            <button type="button" id="btnToggleAdvanced" class="link-btn">
              ⚙️ تنظیمات پیشرفته آدرس سرور
            </button>
            <div id="advancedServerBlock" class="hidden">
              <input 
                type="text" 
                id="serverUrl" 
                dir="ltr"
                placeholder="ws://193.168.175.227:8765" 
                value="" 
              />
            </div>
          </div>

          <button type="submit" id="btnEnterRoom" class="btn-primary-block">
            <span class="btn-icon">🔒</span>
            <span>ورود و اتصال به اتاق</span>
          </button>
        </form>

        <div class="gate-footer-note">
          <span>● پیام‌ها و اتاق‌ها کاملاً مجزا و محافظت‌شده هستند</span>
        </div>
      </div>
    </div>

    <!-- Active Chat View: Shown once authorized in a room -->
    <div id="chatView" class="chat-container hidden">
      <!-- Background Notification Prompt Banner (if browser permission needed) -->
      <div id="notifBanner" class="notif-banner hidden">
        <span>🔔 برای دریافت پیام‌ها روی صفحه قفل و در پس‌زمینه، دسترسی اعلان را تایید کنید.</span>
        <button id="btnEnableNotif" class="btn-banner">فعال‌سازی</button>
      </div>

      <!-- Chat Messages Scroll View -->
      <main id="chatMessages" class="messages-container">
      </main>

      <!-- Bottom Input Bar -->
      <footer class="app-footer">
        <form id="chatForm" class="input-form">
          <input 
            type="text" 
            id="messageInput" 
            placeholder="پیام خود را بنویسید..." 
            autocomplete="off" 
            enterkeyhint="send"
          />
          <button type="submit" id="btnSend" class="send-btn" title="ارسال پیام">
            <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none">
              <line x1="22" y1="2" x2="11" y2="13"></line>
              <polygon points="22 2 15 22 11 13 2 9 22 2"></polygon>
            </svg>
          </button>
        </form>
      </footer>
    </div>

    <!-- Settings Modal Drawer -->
    <div id="settingsModal" class="modal-backdrop hidden">
      <div class="modal-card">
        <div class="modal-header">
          <h3>تنظیمات اتصال و سرور</h3>
          <button id="btnCloseSettings" class="close-btn">&times;</button>
        </div>
        <div class="modal-body">
          <div class="form-group">
            <label for="modalServerUrl">آدرس سرور WebSocket:</label>
            <input 
              type="text" 
              id="modalServerUrl" 
              dir="ltr"
              placeholder="ws://193.168.175.227:8765" 
            />
          </div>

          <div class="form-group checkbox-group">
            <label>
              <input type="checkbox" id="autoReconnect" checked />
              اتصال مجدد خودکار در صورت قطع شدن شبکه
            </label>
          </div>

          <div class="form-group checkbox-group">
            <label>
              <input type="checkbox" id="keepCredentials" checked />
              ذخیره نام اتاق و رمز در این دستگاه
            </label>
          </div>

          <div class="modal-actions-grid">
            <button id="btnTestNotif" class="btn-action secondary">
              🔔 تست اعلان صفحه قفل
            </button>
            <button id="btnMinimizeApp" class="btn-action secondary">
              ⬇️ رفتن به پس‌زمینه (بدون قطع شدن)
            </button>
          </div>

          <div class="modal-divider"></div>

          <div class="modal-actions">
            <button id="btnDisconnectModal" class="btn-disconnect">قطع کامل و خروج از اتاق</button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <script src="app.js"></script>
</body>
</html>

INDEX_EOF

cat << 'STYLE_EOF' > "${INSTALL_DIR}/web/style.css"
* {
  box-sizing: border-box;
  margin: 0;
  padding: 0;
  -webkit-tap-highlight-color: transparent;
}

:root {
  --bg-main: #0B0F19;
  --bg-surface: #151D2F;
  --bg-surface-elevated: #1F2C45;
  --accent-primary: #0284C7;
  --accent-glow: #38BDF8;
  --bubble-me: #0284C7;
  --bubble-peer: #1E293B;
  --text-main: #F1F5F9;
  --text-muted: #94A3B8;
  --text-light: #E2E8F0;
  --border-subtle: #2A3854;
  --success: #10B981;
  --warning: #F59E0B;
  --danger: #EF4444;
  --font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Vazirmatn", Tahoma, sans-serif;
}

body {
  font-family: var(--font-family);
  background-color: var(--bg-main);
  color: var(--text-main);
  height: 100vh;
  height: 100dvh;
  overflow: hidden;
  user-select: none;
}

.app-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  max-width: 600px;
  margin: 0 auto;
  position: relative;
  background-color: var(--bg-main);
}

/* Header */
.app-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: max(12px, env(safe-area-inset-top)) max(16px, env(safe-area-inset-right)) 12px max(16px, env(safe-area-inset-left));
  background-color: var(--bg-surface);
  border-bottom: 1px solid var(--border-subtle);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
  z-index: 10;
}

.header-left, .header-right {
  display: flex;
  align-items: center;
  gap: 8px;
}

.header-center {
  text-align: center;
}

.app-title {
  font-size: 15px;
  font-weight: 700;
  color: var(--text-main);
  letter-spacing: -0.2px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
}

.version-tag {
  font-size: 10px;
  font-weight: 600;
  color: #38bdf8;
  background: rgba(56, 189, 248, 0.15);
  border: 1px solid rgba(56, 189, 248, 0.3);
  padding: 1px 6px;
  border-radius: 9999px;
  direction: ltr;
  display: inline-block;
}

.connection-status {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  font-size: 11px;
  color: var(--text-muted);
  margin-top: 2px;
}

.room-pill {
  background: rgba(2, 132, 199, 0.2);
  color: #38bdf8;
  border: 1px solid rgba(56, 189, 248, 0.3);
  padding: 1px 7px;
  border-radius: 6px;
  font-size: 10px;
  font-weight: 600;
  direction: ltr;
}

.status-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  display: inline-block;
}

.status-dot.connected {
  background-color: var(--success);
  box-shadow: 0 0 8px var(--success);
}

.status-dot.connecting {
  background-color: var(--warning);
  box-shadow: 0 0 8px var(--warning);
}

.status-dot.disconnected {
  background-color: var(--danger);
  box-shadow: 0 0 8px var(--danger);
}

.icon-btn {
  background: transparent;
  border: none;
  color: var(--text-muted);
  padding: 8px;
  border-radius: 8px;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.2s;
}

.icon-btn:active {
  background: var(--bg-surface-elevated);
  color: var(--accent-glow);
  transform: scale(0.95);
}

/* Room Authentication Gate */
.gate-container {
  flex: 1;
  overflow-y: auto;
  padding: 24px 16px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.gate-card {
  width: 100%;
  max-width: 440px;
  background: var(--bg-surface);
  border: 1px solid var(--border-subtle);
  border-radius: 20px;
  padding: 28px 24px;
  box-shadow: 0 16px 40px rgba(0, 0, 0, 0.4);
  text-align: center;
}

.gate-shield-icon {
  margin-bottom: 16px;
  display: inline-flex;
  padding: 14px;
  background: rgba(56, 189, 248, 0.1);
  border-radius: 50%;
  border: 1px solid rgba(56, 189, 248, 0.25);
}

.gate-card h2 {
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--text-main);
  margin-bottom: 8px;
}

.gate-desc {
  font-size: 0.85rem;
  color: var(--text-muted);
  line-height: 1.5;
  margin-bottom: 20px;
}

.gate-form {
  text-align: right;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.form-group label {
  font-size: 13px;
  font-weight: 500;
  color: var(--text-light);
}

.form-group input[type="text"],
.form-group input[type="password"] {
  background: #0D1322;
  border: 1px solid var(--border-subtle);
  border-radius: 10px;
  padding: 12px 14px;
  color: var(--text-main);
  font-size: 14px;
  outline: none;
  transition: all 0.2s;
  font-family: inherit;
}

.form-group input[type="text"]:focus,
.form-group input[type="password"]:focus {
  border-color: var(--accent-glow);
  box-shadow: 0 0 0 3px rgba(56, 189, 248, 0.2);
}

.password-wrapper {
  position: relative;
  display: flex;
  align-items: center;
}

.password-wrapper input {
  width: 100%;
  padding-left: 42px !important;
}

.toggle-pwd-btn {
  position: absolute;
  left: 10px;
  background: none;
  border: none;
  cursor: pointer;
  font-size: 16px;
  padding: 4px;
  opacity: 0.7;
}

.toggle-pwd-btn:hover {
  opacity: 1;
}

.field-hint {
  font-size: 11px;
  color: #64748b;
  margin-top: 2px;
}

.alert-box {
  padding: 12px 14px;
  border-radius: 10px;
  font-size: 13px;
  margin-bottom: 16px;
  text-align: right;
  line-height: 1.4;
}

.alert-box.danger {
  background: rgba(239, 68, 68, 0.15);
  border: 1px solid rgba(239, 68, 68, 0.35);
  color: #fca5a5;
}

.btn-primary-block {
  background: linear-gradient(135deg, #0284c7 0%, #0369a1 100%);
  color: white;
  border: none;
  border-radius: 12px;
  padding: 14px;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  box-shadow: 0 4px 14px rgba(2, 132, 199, 0.35);
  transition: all 0.2s;
  margin-top: 4px;
}

.btn-primary-block:active {
  transform: scale(0.98);
}

.link-btn {
  background: none;
  border: none;
  color: var(--accent-glow);
  font-size: 12px;
  cursor: pointer;
  text-align: right;
  padding: 4px 0;
}

.advanced-toggle-group {
  margin-top: -6px;
}

.gate-footer-note {
  margin-top: 20px;
  font-size: 11px;
  color: #64748b;
}

/* Chat View */
.chat-container {
  display: flex;
  flex-direction: column;
  flex: 1;
  height: 100%;
  overflow: hidden;
}

.notif-banner {
  background: rgba(16, 185, 129, 0.15);
  border-bottom: 1px solid rgba(16, 185, 129, 0.3);
  color: #6ee7b7;
  padding: 10px 16px;
  font-size: 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}

.btn-banner {
  background: var(--success);
  color: #064e3b;
  font-weight: 700;
  border: none;
  border-radius: 6px;
  padding: 4px 10px;
  font-size: 11px;
  cursor: pointer;
  white-space: nowrap;
}

/* Messages Container */
.messages-container {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 12px;
  scroll-behavior: smooth;
}

.msg-wrapper {
  display: flex;
  flex-direction: column;
  width: 100%;
}

.msg-wrapper.me {
  align-items: flex-start; /* In RTL, 'me' aligns to left */
}

.msg-wrapper.peer {
  align-items: flex-end; /* In RTL, 'peer' aligns to right */
}

.msg-wrapper.system {
  align-items: center;
  margin: 6px 0;
}

.msg-wrapper.system .msg-bubble {
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.08);
  color: var(--text-muted);
  font-size: 12px;
  padding: 4px 12px;
  border-radius: 9999px;
  max-width: 90%;
  text-align: center;
}

.msg-bubble {
  max-width: 82%;
  padding: 10px 14px;
  border-radius: 16px;
  position: relative;
  word-break: break-word;
  box-shadow: 0 2px 6px rgba(0, 0, 0, 0.2);
}

.msg-wrapper.me .msg-bubble {
  background-color: var(--bubble-me);
  color: #ffffff;
  border-bottom-left-radius: 4px;
}

.msg-wrapper.peer .msg-bubble {
  background-color: var(--bubble-peer);
  color: var(--text-main);
  border-bottom-right-radius: 4px;
  border: 1px solid var(--border-subtle);
}

.msg-sender {
  font-size: 11px;
  font-weight: 600;
  color: var(--accent-glow);
  margin-bottom: 4px;
}

.msg-text {
  font-size: 14px;
  line-height: 1.5;
  user-select: text;
}

.msg-meta {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 4px;
  font-size: 10px;
  opacity: 0.7;
  margin-top: 4px;
}

/* Footer / Input Bar */
.app-footer {
  padding: 12px 16px max(12px, env(safe-area-inset-bottom)) 16px;
  background-color: var(--bg-surface);
  border-top: 1px solid var(--border-subtle);
}

.input-form {
  display: flex;
  align-items: center;
  gap: 10px;
  background-color: #0D1322;
  border: 1px solid var(--border-subtle);
  border-radius: 24px;
  padding: 4px 8px 4px 14px;
  transition: all 0.2s;
}

.input-form:focus-within {
  border-color: var(--accent-glow);
  box-shadow: 0 0 0 2px rgba(56, 189, 248, 0.2);
}

.input-form input {
  flex: 1;
  background: transparent;
  border: none;
  outline: none;
  color: var(--text-main);
  font-size: 14px;
  font-family: inherit;
  direction: rtl;
}

.send-btn {
  background-color: var(--accent-primary);
  color: #ffffff;
  border: none;
  width: 36px;
  height: 36px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: all 0.2s;
}

.send-btn:active {
  transform: scale(0.92);
  background-color: var(--accent-glow);
}

/* Modal Drawer */
.modal-backdrop {
  position: fixed;
  inset: 0;
  background-color: rgba(0, 0, 0, 0.75);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: flex-end;
  justify-content: center;
  z-index: 100;
  transition: opacity 0.2s;
}

.modal-backdrop.hidden {
  opacity: 0;
  pointer-events: none;
}

.modal-card {
  background-color: var(--bg-surface);
  border: 1px solid var(--border-subtle);
  border-radius: 20px 20px 0 0;
  width: 100%;
  max-width: 600px;
  padding: 24px;
  max-height: 85vh;
  overflow-y: auto;
  box-shadow: 0 -8px 30px rgba(0, 0, 0, 0.5);
  animation: slideUp 0.25s ease-out;
}

@keyframes slideUp {
  from { transform: translateY(100%); }
  to { transform: translateY(0); }
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
}

.modal-header h3 {
  font-size: 16px;
  font-weight: 700;
}

.close-btn {
  background: transparent;
  border: none;
  font-size: 24px;
  color: var(--text-muted);
  cursor: pointer;
  line-height: 1;
}

.modal-body {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.checkbox-group label {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 13px;
  color: var(--text-light);
  cursor: pointer;
}

.modal-actions-grid {
  display: grid;
  grid-template-columns: 1fr;
  gap: 10px;
  margin-top: 8px;
}

.btn-action.secondary {
  background: var(--bg-surface-elevated);
  border: 1px solid var(--border-subtle);
  color: var(--text-light);
  border-radius: 10px;
  padding: 10px 14px;
  font-size: 13px;
  cursor: pointer;
  font-family: inherit;
  transition: all 0.2s;
}

.btn-action.secondary:active {
  background: var(--border-subtle);
}

.modal-divider {
  height: 1px;
  background: var(--border-subtle);
  margin: 8px 0;
}

.btn-disconnect {
  width: 100%;
  background: rgba(239, 68, 68, 0.15);
  border: 1px solid rgba(239, 68, 68, 0.35);
  color: #fca5a5;
  border-radius: 10px;
  padding: 12px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  font-family: inherit;
}

.hidden {
  display: none !important;
}

STYLE_EOF

cat << 'APP_EOF' > "${INSTALL_DIR}/web/app.js"
(() => {
  // DOM Elements - Header & Status
  const statusIndicator = document.getElementById("statusIndicator");
  const statusText = document.getElementById("statusText");
  const roomStatusBadge = document.getElementById("roomStatusBadge");
  const currentRoomDisplay = document.getElementById("currentRoomDisplay");
  const btnSettings = document.getElementById("btnSettings");
  const btnLeaveRoom = document.getElementById("btnLeaveRoom");
  const btnNotification = document.getElementById("btnNotification");
  const btnClear = document.getElementById("btnClear");

  // DOM Elements - Room Gate
  const roomGate = document.getElementById("roomGate");
  const gateForm = document.getElementById("gateForm");
  const gateNickname = document.getElementById("gateNickname");
  const gateRoomName = document.getElementById("gateRoomName");
  const gateRoomPassword = document.getElementById("gateRoomPassword");
  const btnTogglePassword = document.getElementById("btnTogglePassword");
  const gateError = document.getElementById("gateError");
  const gateErrorText = document.getElementById("gateErrorText");
  const btnToggleAdvanced = document.getElementById("btnToggleAdvanced");
  const advancedServerBlock = document.getElementById("advancedServerBlock");
  const serverUrlInput = document.getElementById("serverUrl");
  const btnEnterRoom = document.getElementById("btnEnterRoom");

  // DOM Elements - Active Chat View
  const chatView = document.getElementById("chatView");
  const notifBanner = document.getElementById("notifBanner");
  const btnEnableNotif = document.getElementById("btnEnableNotif");
  const chatMessages = document.getElementById("chatMessages");
  const chatForm = document.getElementById("chatForm");
  const messageInput = document.getElementById("messageInput");

  // DOM Elements - Settings Modal
  const settingsModal = document.getElementById("settingsModal");
  const btnCloseSettings = document.getElementById("btnCloseSettings");
  const modalServerUrl = document.getElementById("modalServerUrl");
  const autoReconnectInput = document.getElementById("autoReconnect");
  const keepCredentialsInput = document.getElementById("keepCredentials");
  const btnTestNotif = document.getElementById("btnTestNotif");
  const btnMinimizeApp = document.getElementById("btnMinimizeApp");
  const btnDisconnectModal = document.getElementById("btnDisconnectModal");

  // Application State
  let ws = null;
  let heartbeatTimer = null;
  let reconnectTimer = null;
  let isConnecting = false;
  let isManualDisconnect = false;
  let unreadCount = 0;
  const originalTitle = document.title;

  const state = {
    nickname: "کاربر",
    room: "",
    password: "",
    serverUrl: "",
    autoReconnect: true,
    keepCredentials: true,
    isAuthenticated: false,
  };

  // 1. Load Saved Configuration & State
  const savedConfig = JSON.parse(localStorage.getItem("rssh_chat_auth") || "{}");
  if (savedConfig.serverUrl) {
    state.serverUrl = savedConfig.serverUrl;
  } else if (window.location && window.location.host && !window.location.protocol.startsWith("file")) {
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    state.serverUrl = `${proto}//${window.location.host}`;
  } else {
    state.serverUrl = "ws://193.168.175.227:8765";
  }

  if (savedConfig.nickname) state.nickname = savedConfig.nickname;
  if (savedConfig.room) state.room = savedConfig.room;
  if (savedConfig.password) state.password = savedConfig.password;
  if (savedConfig.autoReconnect !== undefined) state.autoReconnect = savedConfig.autoReconnect;
  if (savedConfig.keepCredentials !== undefined) state.keepCredentials = savedConfig.keepCredentials;

  // Initialize Form Values
  serverUrlInput.value = state.serverUrl;
  modalServerUrl.value = state.serverUrl;
  gateNickname.value = state.nickname;
  gateRoomName.value = state.room;
  if (state.keepCredentials && state.password) {
    gateRoomPassword.value = state.password;
  }
  autoReconnectInput.checked = state.autoReconnect;
  keepCredentialsInput.checked = state.keepCredentials;

  function persistSettings() {
    state.serverUrl = sanitizeServerUrl(serverUrlInput.value.trim() || modalServerUrl.value.trim());
    state.nickname = gateNickname.value.trim() || "کاربر";
    state.autoReconnect = autoReconnectInput.checked;
    state.keepCredentials = keepCredentialsInput.checked;

    const dataToSave = {
      serverUrl: state.serverUrl,
      nickname: state.nickname,
      autoReconnect: state.autoReconnect,
      keepCredentials: state.keepCredentials,
      room: state.keepCredentials ? state.room : "",
      password: state.keepCredentials ? state.password : "",
    };
    localStorage.setItem("rssh_chat_auth", JSON.stringify(dataToSave));
  }

  function sanitizeServerUrl(raw) {
    let url = (raw || "").trim();
    if (!url) {
      if (window.location && window.location.host && !window.location.protocol.startsWith("file")) {
        const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
        return `${proto}//${window.location.host}`;
      }
      return "ws://193.168.175.227:8765";
    }
    // Clean duplicate prefixes
    if (url.startsWith("ws://http://")) url = "ws://" + url.slice(15);
    else if (url.startsWith("wss://https://")) url = "wss://" + url.slice(16);
    else if (url.startsWith("http://")) url = "ws://" + url.slice(7);
    else if (url.startsWith("https://")) url = "wss://" + url.slice(8);
    else if (!url.startsWith("ws://") && !url.startsWith("wss://")) url = "ws://" + url;
    return url;
  }

  // 2. Native Bridge & Notification Helpers
  function nativeVibrate(ms = 60) {
    if (window.ChatNative && window.ChatNative.vibrate) {
      window.ChatNative.vibrate(ms);
    } else if (navigator.vibrate) {
      navigator.vibrate(ms);
    }
  }

  function nativeToast(msg) {
    if (window.ChatNative && window.ChatNative.showToast) {
      window.ChatNative.showToast(msg);
    }
  }

  function playAudioChime() {
    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      if (!AudioCtx) return;
      const ctx = new AudioCtx();
      const now = ctx.currentTime;

      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = "sine";
      osc.frequency.setValueAtTime(587.33, now); // D5
      osc.frequency.setValueAtTime(880.00, now + 0.09); // A5

      gain.gain.setValueAtTime(0.2, now);
      gain.gain.exponentialRampToValueAtTime(0.001, now + 0.3);

      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.start(now);
      osc.stop(now + 0.3);
    } catch (ignored) {}
  }

  function triggerBackgroundNotification(sender, text, room) {
    // 1. Android APK Native Notification (Heads-up & Lock Screen)
    if (window.ChatNative && window.ChatNative.showNotification) {
      window.ChatNative.showNotification(sender, text, room);
      nativeVibrate(250);
      return;
    }

    // 2. Web Browser Notification
    playAudioChime();
    nativeVibrate(200);

    if ("Notification" in window && Notification.permission === "granted") {
      try {
        const notif = new Notification(`${sender} («${room}»)`, {
          body: text,
          icon: "apple-touch-icon.png",
          badge: "apple-touch-icon.png",
          tag: "rssh-chat-msg",
          renotify: true,
        });
        notif.onclick = () => {
          window.focus();
          notif.close();
        };
      } catch (e) {}
    }

    unreadCount++;
    document.title = `(${unreadCount}) پیام جدید - رخش چت`;
  }

  // Reset title on window focus
  window.addEventListener("focus", () => {
    unreadCount = 0;
    document.title = originalTitle;
  });

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) {
      unreadCount = 0;
      document.title = originalTitle;
    }
  });

  function updateStatus(dotClass, text) {
    statusIndicator.className = `status-dot ${dotClass}`;
    statusText.textContent = text;
  }

  function showGateError(msg) {
    gateErrorText.textContent = msg;
    gateError.classList.remove("hidden");
    nativeVibrate(150);
  }

  function hideGateError() {
    gateError.classList.add("hidden");
  }

  function formatTime(date = new Date()) {
    const h = String(date.getHours()).padStart(2, "0");
    const m = String(date.getMinutes()).padStart(2, "0");
    return `${h}:${m}`;
  }

  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function appendMessage({ type = "peer", sender = "", text = "", time = "" }) {
    const wrapper = document.createElement("div");
    wrapper.className = `msg-wrapper ${type}`;

    if (type === "system") {
      wrapper.innerHTML = `
        <div class="msg-bubble">
          <span>${escapeHtml(text)}</span>
        </div>
      `;
    } else {
      const isMe = type === "me";
      const timeStr = time || formatTime();
      wrapper.innerHTML = `
        <div class="msg-bubble">
          ${!isMe && sender ? `<div class="msg-sender">${escapeHtml(sender)}</div>` : ""}
          <div class="msg-text">${escapeHtml(text)}</div>
          <div class="msg-meta">
            <span class="msg-time">${timeStr}</span>
            ${isMe ? '<span class="msg-status">✓</span>' : ""}
          </div>
        </div>
      `;

      wrapper.querySelector(".msg-bubble").addEventListener("click", () => {
        if (window.ChatNative && window.ChatNative.copyToClipboard) {
          window.ChatNative.copyToClipboard(text);
        }
      });
    }

    chatMessages.appendChild(wrapper);
    chatMessages.scrollTop = chatMessages.scrollHeight;
  }

  // 3. Room Switching & View Management
  function enterChatView(roomName) {
    state.isAuthenticated = true;
    hideGateError();
    roomGate.classList.add("hidden");
    chatView.classList.remove("hidden");
    btnLeaveRoom.classList.remove("hidden");
    btnClear.classList.remove("hidden");
    roomStatusBadge.classList.remove("hidden");
    currentRoomDisplay.textContent = roomName;
    messageInput.focus();

    // Check browser notification permission
    if ("Notification" in window && Notification.permission === "default") {
      notifBanner.classList.remove("hidden");
    } else {
      notifBanner.classList.add("hidden");
    }
  }

  function returnToRoomGate() {
    state.isAuthenticated = false;
    roomGate.classList.remove("hidden");
    chatView.classList.add("hidden");
    btnLeaveRoom.classList.add("hidden");
    btnClear.classList.add("hidden");
    roomStatusBadge.classList.add("hidden");
    updateStatus("disconnected", "اتاقی متصل نیست");
  }

  // 4. WebSocket & Room Protocol
  function connectAndJoinRoom(room, password, nickname) {
    if (isConnecting) return;

    state.room = room.trim();
    state.password = password.trim();
    state.nickname = nickname.trim() || "کاربر";
    state.serverUrl = sanitizeServerUrl(serverUrlInput.value || modalServerUrl.value);
    persistSettings();

    if (!state.room || !state.password) {
      showGateError("لطفاً نام اتاق و رمز عبور سخت آن را وارد کنید.");
      return;
    }

    hideGateError();
    clearTimeout(reconnectTimer);
    clearInterval(heartbeatTimer);
    isManualDisconnect = false;
    isConnecting = true;
    updateStatus("connecting", "در حال بررسی رمز...");

    if (ws) {
      try {
        ws.close();
      } catch (e) {}
      ws = null;
    }

    try {
      ws = new WebSocket(state.serverUrl);
    } catch (err) {
      isConnecting = false;
      updateStatus("disconnected", "خطای پروتکل");
      showGateError(`خطا در ارتباط با وب‌سوکت: ${err.message}`);
      return;
    }

    ws.onopen = () => {
      isConnecting = false;
      updateStatus("connecting", "در حال تایید دسترسی...");

      // Send join room authentication payload
      const joinPayload = {
        type: "join",
        room: state.room,
        password: state.password,
        sender: state.nickname,
        time: formatTime()
      };
      try {
        ws.send(JSON.stringify(joinPayload));
      } catch (e) {}

      // Start 20s Keepalive Heartbeat
      clearInterval(heartbeatTimer);
      heartbeatTimer = setInterval(() => {
        if (ws && ws.readyState === WebSocket.OPEN) {
          try {
            ws.send(JSON.stringify({ type: "ping" }));
          } catch (e) {}
        }
      }, 20000);
    };

    ws.onmessage = (event) => {
      let data = event.data;
      let parsed = null;
      try {
        parsed = JSON.parse(data);
      } catch (e) {
        return;
      }

      if (!parsed) return;

      // Authentication Success
      if (parsed.type === "auth_success") {
        updateStatus("connected", "متصل");
        nativeToast(`وارد اتاق «${parsed.room || state.room}» شدید`);
        enterChatView(parsed.room || state.room);
        appendMessage({
          type: "system",
          text: `به اتاق امن و اختصاصی «${parsed.room || state.room}» خوش آمدید.`
        });
        return;
      }

      // Authentication Error (Wrong Password or Access Denied)
      if (parsed.type === "auth_error") {
        updateStatus("disconnected", "رمز نادرست");
        showGateError(parsed.text || "رمز عبور اتاق نادرست است! اتصال ممکن نیست.");
        returnToRoomGate();
        try {
          ws.close();
        } catch (e) {}
        ws = null;
        return;
      }

      // System Messages within the room
      if (parsed.type === "system") {
        appendMessage({
          type: "system",
          text: parsed.text || parsed.message
        });
        return;
      }

      // Incoming Chat Messages
      if (parsed.type === "chat") {
        const isMe = parsed.sender === state.nickname;
        appendMessage({
          type: isMe ? "me" : "peer",
          sender: parsed.sender,
          text: parsed.text,
          time: parsed.time || formatTime()
        });

        // Trigger Notification if client is in background / phone locked
        const isAppHidden = document.hidden || 
                            !document.hasFocus() || 
                            (window.ChatNative && window.ChatNative.isAppForeground && !window.ChatNative.isAppForeground());

        if (!isMe) {
          if (isAppHidden) {
            triggerBackgroundNotification(parsed.sender, parsed.text, state.room);
          } else {
            playAudioChime();
            nativeVibrate(30);
          }
        }
      }
    };

    ws.onerror = () => {
      // Handled in onclose
    };

    ws.onclose = (event) => {
      isConnecting = false;
      clearInterval(heartbeatTimer);

      if (state.isAuthenticated) {
        updateStatus("disconnected", "ارتباط قطع شد");
        appendMessage({
          type: "system",
          text: "ارتباط با سرور چت قطع شد. در حال تلاش برای اتصال مجدد..."
        });

        if (!isManualDisconnect && state.autoReconnect) {
          scheduleReconnect();
        }
      } else {
        updateStatus("disconnected", "قطع");
      }
    };
  }

  function scheduleReconnect() {
    clearTimeout(reconnectTimer);
    updateStatus("connecting", "اتصال مجدد تا ۳ ثانیه...");
    reconnectTimer = setTimeout(() => {
      if (state.room && state.password) {
        connectAndJoinRoom(state.room, state.password, state.nickname);
      }
    }, 3500);
  }

  function leaveRoom() {
    isManualDisconnect = true;
    clearTimeout(reconnectTimer);
    clearInterval(heartbeatTimer);

    if (ws && ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(JSON.stringify({ type: "leave" }));
        ws.close();
      } catch (e) {}
    }
    ws = null;
    returnToRoomGate();
    nativeToast("از اتاق خارج شدید");
  }

  // 5. User Interactions & Event Handlers
  gateForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const room = gateRoomName.value.trim();
    const password = gateRoomPassword.value.trim();
    const nickname = gateNickname.value.trim();

    if (!room || !password) {
      showGateError("لطفاً هم نام اتاق و هم رمز عبور سخت را وارد کنید.");
      return;
    }
    connectAndJoinRoom(room, password, nickname);
  });

  // Password Visibility Toggle
  btnTogglePassword.addEventListener("click", () => {
    const isPassword = gateRoomPassword.type === "password";
    gateRoomPassword.type = isPassword ? "text" : "password";
    btnTogglePassword.textContent = isPassword ? "🙈" : "👁️";
  });

  // Advanced Server Settings Toggle
  btnToggleAdvanced.addEventListener("click", () => {
    advancedServerBlock.classList.toggle("hidden");
  });

  // Chat Send Form
  chatForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = messageInput.value.trim();
    if (!text) return;

    if (!ws || ws.readyState !== WebSocket.OPEN) {
      nativeToast("ارتباط با سرور برقرار نیست");
      return;
    }

    const payload = {
      type: "chat",
      room: state.room,
      sender: state.nickname,
      text: text,
      time: formatTime()
    };

    try {
      ws.send(JSON.stringify(payload));
      appendMessage({
        type: "me",
        sender: state.nickname,
        text: text,
        time: formatTime()
      });
      messageInput.value = "";
      nativeVibrate(20);
    } catch (err) {
      nativeToast("خطا در ارسال پیام");
    }
  });

  // Leave room button
  btnLeaveRoom.addEventListener("click", leaveRoom);
  btnDisconnectModal.addEventListener("click", () => {
    closeSettings();
    leaveRoom();
  });

  // Clear messages button
  btnClear.addEventListener("click", () => {
    chatMessages.innerHTML = "";
    appendMessage({
      type: "system",
      text: "صفحه چت پاکسازی شد."
    });
  });

  // Notification Permission Request
  function requestNotificationAccess() {
    if ("Notification" in window) {
      Notification.requestPermission().then((permission) => {
        if (permission === "granted") {
          notifBanner.classList.add("hidden");
          nativeToast("اعلان‌های صفحه قفل فعال شد");
          triggerBackgroundNotification("رخش چت", "اعلان‌ها فعال شدند و آماده دریافت پیام روی صفحه قفل هستند.", state.room || "سیستم");
        } else {
          nativeToast("مجوز اعلان صادر نشد");
        }
      });
    } else {
      nativeToast("اعلان در این مرورگر پشتیبانی نمی‌شود");
    }
  }

  btnEnableNotif?.addEventListener("click", requestNotificationAccess);
  btnNotification.addEventListener("click", () => {
    if (window.ChatNative && window.ChatNative.showNotification) {
      window.ChatNative.showNotification("تست اعلان رخش چت", "پیام تستی روی صفحه قفل با موفقیت نمایش داده شد.", state.room || "تست");
      nativeToast("اعلان تستی ارسال شد");
    } else {
      requestNotificationAccess();
    }
  });

  btnTestNotif?.addEventListener("click", () => {
    if (window.ChatNative && window.ChatNative.showNotification) {
      window.ChatNative.showNotification("تست اعلان صفحه قفل", "سرویس فعال است و پیام‌ها در حالت قفل بودن گوشی دریافت می‌شوند.", state.room || "عمومی");
      nativeToast("اعلان تستی ارسال شد");
    } else {
      triggerBackgroundNotification("تست سیستم", "این یک پیام تستی برای بررسی عملکرد نوتیفیکیشن است.", state.room || "تست");
    }
  });

  // Minimize App Button (Puts Android APK to background without closing socket)
  btnMinimizeApp?.addEventListener("click", () => {
    closeSettings();
    if (window.ChatNative && window.ChatNative.minimizeApp) {
      window.ChatNative.minimizeApp();
    } else {
      nativeToast("برای پنهان شدن صفحه، دکمه هوم یا پاور گوشی را بزنید");
    }
  });

  // Settings Modal Controls
  function openSettings() {
    modalServerUrl.value = state.serverUrl;
    settingsModal.classList.remove("hidden");
  }

  function closeSettings() {
    settingsModal.classList.add("hidden");
    state.serverUrl = sanitizeServerUrl(modalServerUrl.value);
    serverUrlInput.value = state.serverUrl;
    persistSettings();
  }

  btnSettings.addEventListener("click", openSettings);
  btnCloseSettings.addEventListener("click", closeSettings);

  settingsModal.addEventListener("click", (e) => {
    if (e.target === settingsModal) closeSettings();
  });

  // Android Native Back Button Handler
  window.onBackPressed = () => {
    if (!settingsModal.classList.contains("hidden")) {
      closeSettings();
      return true;
    }
    if (state.isAuthenticated) {
      // Don't close app on back, let native moveTaskToBack minimize it
      return false;
    }
    return false;
  };

  // Initial Auto-Join if saved credentials exist
  if (state.keepCredentials && state.room && state.password && state.autoReconnect) {
    connectAndJoinRoom(state.room, state.password, state.nickname);
  }
})();

APP_EOF

cat << 'MANIFEST_EOF' > "${INSTALL_DIR}/web/manifest.json"
{
  "name": "رخش چت | Rakhssh Chat",
  "short_name": "Rakhssh Chat",
  "version": "1.2.0",
  "description": "کلاینت چت مستقل، سبک و امن با اتاق‌های رمزگذاری‌شده و نوتیفیکیشن صفحه قفل",
  "start_url": "/",
  "scope": "/",
  "display": "standalone",
  "background_color": "#0f172a",
  "theme_color": "#0f172a",
  "orientation": "portrait-primary",
  "icons": [
    {
      "src": "/apple-touch-icon.png",
      "sizes": "180x180",
      "type": "image/png",
      "purpose": "any maskable"
    },
    {
      "src": "/icon-192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/icon-512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}

MANIFEST_EOF

base64 -d << 'ICON_EOF' > "${INSTALL_DIR}/web/apple-touch-icon.png"
iVBORw0KGgoAAAANSUhEUgAAALQAAAC0CAYAAAA9zQYyAAAFyklEQVR42u3U53OUVRSA8R0LCqjU9IQEEoqUJJAE0L/ProC9AHbAXgAb6ncpSpFebBQFlKIUHceZ17OBmRiHZLPv7t1z7rnPh9+d++nk7nmfSWFSw/wM8KLAEkDQAEEDBA0QNAgaIGiAoAGCBsYadKNcACck6AUZ4EVhshyAFwQNggYIGiBogKBB0ABBAwaDbpIL4ARBw1vQCzPAC4KGr6CnyAF4QdAgaICgAYIGCBpJB90sF8AJgoa3oBdlgBcEDYJGacu+/LMk9kTQJiz94mrNsO8yg54qB0ZXy4BL4XuMjqBvYODzq9HgexH0CBFfiR7fMfGg+7dccSvdoFvkkpj+LZeTkdq3TSrovs8uJ4ugXYV8CdclEHR35lXfp5cwAq/f3G3QS+SjYXQEHUPIn/yBMhG0UYvl4yAfgrYU8se/o0qiD3qaHDHrlY+A6oq5h6iD7v3oIgKJN+hWuUSoR5aOsGLsIsqgezZfRI0QdEDdmy9ASURB92Sx6N50AUpiaSSaoBdtOg9lBF2tmDeehxEEXaGFG8/BGILOG/OH52AUQRMzUacc9IIPfoNxJoOe3taTWUMs8bDWjrmg57//KyJD0ARN0CkEffd7ZxEpQ0H3ZlYQRsxB22jITNDz3j2LyBH0sKDPIHIEfd3cd87ACYIeDPo0nEg+6Dlvn4YzukHPkIsiAnAYtGJP6kHPfusXOKMadJ0cmgjAH82eVIPuevNnOEXQIOjqBL0409L1xik4pdWUatCd8sMt+evvf4YJMTPUXGu7TC7ozg2nzLhRdMNiCTAz1FxLe00q6FkbTpowlvCKQswMNdfKbtMKev1JdeWENxhKgJmh5lrYr07Q7XJRMHP9CVV5wisKMVfrraFpdKUX9LoTqnJHEmCu1ltDSyrojnXHVeWNJMTMUHO1d5xW0K8fV5U7kgAzQ83V3rFK0PVyaGiXH6wpbyQhZoaaq71jja4k6CWZhvbXflKVO5IAc7XeGppGV2pBz5AfrClPIB7nhpRW0K/+qK7sQALM1X5rSEkF3SY/2IKxBhJirpW3hpJU0INRv/KDCSUDCTDX2lurTaupQn2HXJRYWT4CBK3UlGrQrfLD4VOaQb/8PZxKMugW+eHwKcmgB6N+6Ts4o9mTetDNsgD4ohp0Q0dfpqn5xWNwRrMn9aCLmmQJ8EG7JRtBrz0GJwhaNK49Cif0g54pFwMa1xxF5Cx0ZCbohjVHEDuC/p/VRxArIw2ZCrp+9WFEiqBHivqFw4iMpX7MBV1UJ0tCHKy1I0H3Z9bUPX8IkbDWjsmgiZqYcwfdKIdV0587CKOsNkPQcBb0LLkYNu3ZAzDGci/mgyZqYnYXdNHUZw5AWQydRBP0taj3Q0ksjUQVdNGUp/ejxmLqI7qgr0W9DzUSWxtRBl00+al9CCzGLiTogSxWRBcy5jibiDrooklP7kWVxdxD9EETNiEPC7qpcyDz4q4nvkVOXhpwFTRhpxuy66AHo358D0rw+N1NBn2nLBvheP0nZjfoVXsQgOeQTQd9x6rdqKIUQrYd9MrdqIKUQjYd9MSVu1CBFEP+T9BLM2smrthVU1p/N8RvSJ3JoCes2FlzFt5Q6ZtRDLpLLsZMeGynGotvKvU2DDEZ9Hj5eJq030qYFQTdLIc14x/9Rp3FvaA0k0HfLkFZQCAEXZ2gH/naFEIh6IrcJhFZQywEnT/oh3eYRDAEncs4iccqojEf9LLMmnEP7TDL4r4wxGjQ280iGutBz5aLMbc+uN0si/vCEKNBbzOLaAi6bLc8sM0soiHoHEFvNYtojAfdIoc1N9+/1SyL+8IQgiZogg7tpvu+MotoCJqgQdAEjZxBL8+ssR30chhWaJkjF8AJggZBAwQNEDRA0Eg56FY5AC8IGgQNGA76ngzwotA6Vy6AEwQNggYIGiBogKBB0ABBA/aCbpMD8IKg4SzoefdmgBcEDYIGCBogaICgQdAAQQMEDRA0MEb/AuFYVyUlsqQOAAAAAElFTkSuQmCC
ICON_EOF

cp "${INSTALL_DIR}/web/apple-touch-icon.png" "${INSTALL_DIR}/web/icon-192.png"
cp "${INSTALL_DIR}/web/apple-touch-icon.png" "${INSTALL_DIR}/web/icon-512.png"

# Set Permissions
chown -R "${APP_USER}:${APP_USER}" "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}"
chmod 755 "${INSTALL_DIR}/server.py"
chmod -R 755 "${INSTALL_DIR}/web"

echo -e "${C_GREEN}   ✔ فایل‌های سرور در ${INSTALL_DIR} مستقر شدند.${C_RESET}"

# 4. Create Systemd Service
echo -e "${C_BLUE}▶ مرحله ۴/۶: ساخت و پیکربندی سرویس دائمی لینوکس (Systemd Service)...${C_RESET}"

cat << SERVICE_EOF > "${SYSTEMD_FILE}"
[Unit]
Description=Rakhssh WebSocket & Web Chat Server
After=network.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${INSTALL_DIR}
Environment=PORT=${PORT}
Environment=HOST=0.0.0.0
Environment=WEB_DIR=${INSTALL_DIR}/web
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/server.py
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

# Security Sandboxing
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}" >/dev/null 2>&1
systemctl restart "${SERVICE_NAME}"

echo -e "${C_GREEN}   ✔ سرویس ${SERVICE_NAME} فعال و راه‌اندازی شد.${C_RESET}"

# 5. Firewall Configuration
echo -e "${C_BLUE}▶ مرحله ۵/۶: بررسی تنظیمات فایروال (UFW)...${C_RESET}"
if command -v ufw >/dev/null 2>&1; then
  if ufw status 2>/dev/null | grep -qw "active"; then
    ufw allow "${PORT}/tcp" comment "Rakhssh Chat Server" >/dev/null 2>&1 || true
    echo -e "${C_GREEN}   ✔ پورت ${PORT} در فایروال UFW با موفقیت باز شد.${C_RESET}"
  else
    echo -e "${C_YELLOW}   ℹ️ فایروال UFW غیرفعال است (تمام پورت‌ها در دسترس هستند).${C_RESET}"
  fi
fi

# 6. Self-Verification & Health Check
echo -e "${C_BLUE}▶ مرحله ۶/۶: تست سلامت و فعال بودن سرور...${C_RESET}"
sleep 1.5

if systemctl is-active --quiet "${SERVICE_NAME}"; then
  HEALTH_CHECK=$(curl -s "http://127.0.0.1:${PORT}/health" 2>/dev/null || echo "")
  if echo "${HEALTH_CHECK}" | grep -q "rakhssh-chat"; then
    echo -e "${C_GREEN}${C_BOLD}   ✔ تست اتصال داخلی با موفقیت تأیید شد (HTTP 200 OK).${C_RESET}"
  else
    echo -e "${C_YELLOW}   ⚠️ سرویس در حال اجرا است اما تست پاسخ داخلی با تأخیر مواجه شد.${C_RESET}"
  fi
else
  echo -e "${C_RED}❌ خطا: سرویس سیستم شروع به کار نکرد. لاگ‌ها را بررسی کنید:${C_RESET}"
  journalctl -u "${SERVICE_NAME}" -n 20 --no-pager
  exit 1
fi

# IP Discovery
PUB_IP=$(curl -s -4 --connect-timeout 3 https://api.ipify.org 2>/dev/null || \
         curl -s -4 --connect-timeout 3 https://ifconfig.me 2>/dev/null || \
         curl -s -4 --connect-timeout 3 https://icanhazip.com 2>/dev/null || \
         echo "")

LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1")
DISPLAY_IP="${PUB_IP:-$LOCAL_IP}"

# Final Completion Banner
echo ""
echo -e "${C_GREEN}${C_BOLD}========================================================================${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}  🎉 نصب و راه‌اندازی سرور چت با موفقیت کامل انجام شد!${C_RESET}"
echo -e "${C_GREEN}${C_BOLD}========================================================================${C_RESET}"
echo ""
echo -e "${C_BOLD}📱 نحوه اتصال از طریق برنامه اندروید (chat.apk):${C_RESET}"
echo -e "   ۱. برنامه ${C_CYAN}chat.apk${C_RESET} را روی گوشی باز کنید."
echo -e "   ۲. آیکون چرخ‌دنده تنظیمات (⚙️) را لمس کنید."
echo -e "   ۳. در قسمت «آدرس سرور»، آدرس زیر را وارد کنید:"
if [ -n "$PUB_IP" ]; then
  echo -e "      ${C_YELLOW}${C_BOLD}ws://${PUB_IP}:${PORT}${C_RESET}  (اتصال از طریق اینترنت / سرور VPS)"
fi
echo -e "      ${C_CYAN}ws://${LOCAL_IP}:${PORT}${C_RESET}  (اتصال از طریق شبکه داخلی LAN / Wi-Fi)"
echo -e "   ۴. نام مستعار دلخواه خود را وارد کرده و دکمه ${C_GREEN}«اتصال به سرور»${C_RESET} را بزنید."
echo ""
echo -e "${C_BOLD}🍏 نحوه اتصال از طریق آیفون و آیپد (iOS PWA - بدون نیاز به مک یا اپ‌استور):${C_RESET}"
echo -e "   ۱. در مرورگر Safari آیفون، آدرس وب زیر را باز کنید:"
if [ -n "$PUB_IP" ]; then
  echo -e "      ${C_YELLOW}${C_BOLD}http://${PUB_IP}:${PORT}${C_RESET}"
fi
echo -e "      ${C_CYAN}http://${LOCAL_IP}:${PORT}${C_RESET}"
echo -e "   ۲. دکمه ${C_CYAN}اشتراک‌گذاری (Share Icon ⎋)${C_RESET} در پایین صفحه سافاری را لمس کنید."
echo -e "   ۳. گزینه ${C_GREEN}«Add to Home Screen» (افزودن به صفحه اصلی)${C_RESET} را انتخاب کنید."
echo -e "   ۴. برنامه با آیکون اختصاصی و بدون نوار مرورگر به صورت تمام‌صفحه مانند یک اپلیکیشن کاملاً بومی نصب می‌شود!"
echo ""
echo -e "${C_BOLD}🌐 دسترسی از طریق مرورگر کامپیوتر یا موبایل (Web Client):${C_RESET}"
if [ -n "$PUB_IP" ]; then
  echo -e "   • ${C_YELLOW}http://${PUB_IP}:${PORT}${C_RESET}"
fi
echo -e "   • ${C_CYAN}http://${LOCAL_IP}:${PORT}${C_RESET}"
echo ""
echo -e "${C_BOLD}📋 دستورات مدیریت سرویس روی سرور لینوکس:${C_RESET}"
echo -e "   • مشاهده وضعیت:   ${C_BLUE}sudo systemctl status ${SERVICE_NAME}${C_RESET}"
echo -e "   • ری‌استارت:       ${C_BLUE}sudo systemctl restart ${SERVICE_NAME}${C_RESET}"
echo -e "   • توقف موقت:      ${C_BLUE}sudo systemctl stop ${SERVICE_NAME}${C_RESET}"
echo -e "   • مشاهده زنده‌ی لاگ‌ها: ${C_BLUE}sudo journalctl -u ${SERVICE_NAME} -f${C_RESET}"
echo -e "   • حذف کامل:       ${C_BLUE}sudo bash $0 --uninstall${C_RESET}"
echo -e "${C_GREEN}========================================================================${C_RESET}"
echo ""

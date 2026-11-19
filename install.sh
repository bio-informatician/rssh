#!/usr/bin/env bash
# ==============================================================================
# 🚀 Rakhssh Chat Server v1.6.0 - Ubuntu Auto Installer & Systemd Service Setup
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
INSTALLER_VERSION="1.6.0"

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
  - End-to-End Encrypted (E2EE) messages routing
  - Dual-Transport Architecture:
      1. Primary: RFC 6455 WebSocket (ws:// or wss://)
      2. Fallback: HTTP Safe Tunnel REST APIs (/api/join, /api/send, /api/poll)
  - Strict Firewall & Middlebox Resilience (automatic message history buffer & retry sync)
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
import urllib.parse

GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
VERSION = "1.6.0"
PRESENCE_TIMEOUT = 7.0  # seconds threshold for active online status (resilient to mobile network jitter)

# Connected WebSocket clients
clients = set()

# client_info: writer -> {"peer": (ip, port), "room": str|None, "nickname": str|None, "authenticated": bool}
client_info = {}

# rooms: room_name -> {
#   "name": str,
#   "salt": hex,
#   "hash": hex,
#   "created_at": float,
#   "creator": str,
#   "clients": set(writers),
#   "history": list[dict]
# }
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


def get_active_tunnel():
    """Retrieve active Cloudflare Tunnel URLs if running."""
    tunnel_file = os.path.join(BASE_DIR, "tunnel_url.txt")
    if os.path.exists(tunnel_file):
        try:
            with open(tunnel_file, "r", encoding="utf-8") as f:
                lines = [l.strip() for l in f if l.strip()]
                if lines:
                    http_url = lines[0]
                    ws_url = lines[1] if len(lines) > 1 else http_url.replace("https://", "wss://").replace("http://", "ws://")
                    return {
                        "active": True,
                        "url": http_url,
                        "ws_url": ws_url
                    }
        except Exception:
            pass
    return {"active": False, "url": None, "ws_url": None}

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
    <div class="badge">● سرور فعال و در حال اجرا است (v1.3.0)</div>
    <h1>سرور چت رخش (Rakhssh)</h1>
    <p>سرور چت با اتاق‌های رمزگذاری شده و تونل ضد فایروال روی لینوکس راه‌اندازی شد.</p>
    <div class="code-box" id="wsUrl">ws://YOUR-SERVER-IP:8765</div>
    <p style="font-size: 0.85rem; color: #64748b;">پروتکل: RFC 6455 WebSocket + HTTP Safe Tunnel Fallback</p>
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


def cleanup_empty_room(room_id: str, force: bool = False):
    """
    Purges room from RAM if no active WebSocket clients or active HTTP members remain.
    Ensures empty rooms do not linger in memory or lock users out with stale password hashes.
    """
    if not room_id or room_id not in rooms:
        return

    room = rooms[room_id]
    now = time.time()

    # Prune stale/closed WebSocket clients first
    for w in list(room.get("clients", set())):
        if w.is_closing():
            room["clients"].discard(w)
            clients.discard(w)
            client_info.pop(w, None)

    # Prune stale HTTP members (> PRESENCE_TIMEOUT)
    http_members = room.get("http_members", {})
    for u, inf in list(http_members.items()):
        if (now - inf.get("last_ping", 0)) >= PRESENCE_TIMEOUT:
            http_members.pop(u, None)

    active_ws = len(room.get("clients", set()))
    active_http = len(http_members)

    # If force, or if truly 0 active users remain, purge immediately
    if force or (active_ws == 0 and active_http == 0):
        # Grace period for non-force: 3 seconds for freshly created rooms
        if not force and (now - room.get("created_at", 0) < 3.0):
            return
        rooms.pop(room_id, None)
        print(f"🗑️ [Room Purged] Room '{room_id}' is empty (0 members) and was deleted from memory.")


async def empty_rooms_reaper():
    """Periodic background task to purge abandoned or empty rooms from memory."""
    while True:
        try:
            await asyncio.sleep(5)
            now = time.time()
            for r_id in list(rooms.keys()):
                cleanup_empty_room(r_id)
        except Exception:
            pass


def generate_random_padding(min_bytes: int = 384, max_bytes: int = 1536) -> str:
    """Generates variable-length random noise string for Anti-DPI packet shaping."""
    length = secrets.randbelow(max(1, max_bytes - min_bytes + 1)) + min_bytes
    return secrets.token_urlsafe(length)[:length]


def strip_anti_dpi_padding(payload: dict) -> dict:
    """Safely removes Anti-DPI padding and telemetry noise from message dict."""
    if not isinstance(payload, dict):
        return payload
    payload.pop("_pad", None)
    payload.pop("_ts", None)
    payload.pop("padding", None)
    return payload


def apply_anti_dpi_padding(payload: dict, min_bytes: int = 384, max_bytes: int = 1536) -> dict:
    """Attaches dynamic random noise padding to payload to mask packet size signature."""
    if not isinstance(payload, dict):
        return payload
    payload["_pad"] = generate_random_padding(min_bytes, max_bytes)
    payload["_ts"] = int(time.time() * 1000)
    return payload


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


async def broadcast_room(room_name: str, message_data, sender_writer=None):
    """
    Broadcast a message frame ONLY to authenticated clients inside a specific room.
    Applies Anti-DPI variable length random padding to eliminate packet-size fingerprints.
    """
    if not room_name or room_name not in rooms:
        return

    # Ensure Anti-DPI padding is present on broadcast payloads
    if isinstance(message_data, dict):
        apply_anti_dpi_padding(message_data)
        message_json = json.dumps(message_data, ensure_ascii=False)
    elif isinstance(message_data, str):
        try:
            parsed = json.loads(message_data)
            if isinstance(parsed, dict) and "_pad" not in parsed:
                apply_anti_dpi_padding(parsed)
                message_json = json.dumps(parsed, ensure_ascii=False)
            else:
                message_json = message_data
        except Exception:
            message_json = message_data
    else:
        message_json = str(message_data)

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
    if room_name in rooms:
        cleanup_empty_room(room_name)


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


def make_http_json_response(status_code: int, json_body: str) -> bytes:
    """Helper to generate an HTTP response with JSON payload and CORS headers."""
    status_text = {
        200: "OK",
        201: "Created",
        204: "No Content",
        400: "Bad Request",
        401: "Unauthorized",
        403: "Forbidden",
        404: "Not Found",
        405: "Method Not Allowed",
        500: "Internal Server Error",
    }.get(status_code, "OK")

    body_bytes = json_body.encode("utf-8") if isinstance(json_body, str) else json_body
    resp = (
        f"HTTP/1.1 {status_code} {status_text}\r\n"
        "Content-Type: application/json; charset=utf-8\r\n"
        f"Content-Length: {len(body_bytes)}\r\n"
        "Access-Control-Allow-Origin: *\r\n"
        "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
        "Connection: close\r\n\r\n"
    ).encode("utf-8") + body_bytes
    return resp


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    peername = writer.get_extra_info("peername") or ("unknown", 0)
    headers = {}
    try:
        # 1. Read HTTP request line (with 15s timeout to avoid hanging TLS handshakes or probes)
        try:
            request_line = await asyncio.wait_for(reader.readline(), timeout=15.0)
        except (asyncio.TimeoutError, ConnectionResetError, BrokenPipeError):
            writer.close()
            return

        if not request_line:
            writer.close()
            return

        parts = request_line.decode("utf-8", errors="replace").strip().split()
        method = parts[0].upper() if len(parts) > 0 else "GET"
        raw_path = parts[1] if len(parts) > 1 else "/"
        path = raw_path.split("?")[0]

        # Read headers
        while True:
            try:
                line = await asyncio.wait_for(reader.readline(), timeout=15.0)
            except (asyncio.TimeoutError, ConnectionResetError, BrokenPipeError):
                writer.close()
                return
            if line in (b"\r\n", b"\n", b""):
                break
            line_str = line.decode("utf-8", errors="replace").strip()
            if ":" in line_str:
                k, v = line_str.split(":", 1)
                headers[k.strip().lower()] = v.strip()

        key = headers.get("sec-websocket-key")
        upgrade = headers.get("upgrade", "").lower()

        # Handle regular HTTP requests (Health check, Static files, and REST API for Strict Firewall Tunneling)
        if not key or upgrade != "websocket":
            # CORS Preflight
            if method == "OPTIONS":
                cors_resp = (
                    "HTTP/1.1 204 No Content\r\n"
                    "Access-Control-Allow-Origin: *\r\n"
                    "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
                    "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"
                    "Access-Control-Max-Age: 86400\r\n"
                    "Content-Length: 0\r\n"
                    "Connection: close\r\n\r\n"
                ).encode("utf-8")
                writer.write(cors_resp)
                await writer.drain()
                writer.close()
                return

            if method == "POST":
                content_len = int(headers.get("content-length", 0))
                post_body = b""
                if content_len > 0:
                    post_body = await reader.readexactly(content_len)

                try:
                    payload = json.loads(post_body.decode("utf-8")) if post_body else {}
                except Exception:
                    payload = {}

                # Strip Anti-DPI padding and telemetry noise from request body
                strip_anti_dpi_padding(payload)

                # REST API 1: /api/join (Authenticate or create room via HTTP)
                if path == "/api/join":
                    raw_room = str(payload.get("room") or "").strip()
                    password = str(payload.get("password") or "").strip()
                    sender = str(payload.get("sender") or "").strip() or "کاربر"
                    client_id = str(payload.get("clientId") or "").strip()
                    room_id = raw_room.lower()

                    if not raw_room or not password:
                        resp_dict = {"status": "error", "text": "نام اتاق و رمز عبور الزامی است."}
                        apply_anti_dpi_padding(resp_dict)
                        writer.write(make_http_json_response(400, json.dumps(resp_dict, ensure_ascii=False)))
                        await writer.drain()
                    else:
                        now = time.time()
                        if room_id not in rooms:
                            salt = secrets.token_hex(16)
                            pw_hash = hash_password(password, salt)
                            rooms[room_id] = {
                                "name": raw_room,
                                "salt": salt,
                                "hash": pw_hash,
                                "created_at": now,
                                "last_http_activity": now,
                                "creator": sender,
                                "clients": set(),
                                "history": [],
                                "http_members": {sender: {"last_ping": now, "client_id": client_id}}
                            }
                            print(f"🔒 [HTTP Room Created] '{room_id}' by '{sender}' from {peername[0]}")
                        else:
                            salt = rooms[room_id]["salt"]
                            expected_hash = rooms[room_id]["hash"]
                            provided_hash = hash_password(password, salt)
                            if not hmac.compare_digest(provided_hash, expected_hash):
                                print(f"⛔ [HTTP Auth Failed] '{sender}' wrong password for '{room_id}'")
                                resp_dict = {"status": "error", "text": "رمز عبور اتاق نادرست است."}
                                apply_anti_dpi_padding(resp_dict)
                                writer.write(make_http_json_response(401, json.dumps(resp_dict, ensure_ascii=False)))
                                await writer.drain()
                                writer.close()
                                return

                            # Check for duplicate nickname collision in room
                            norm_sender = sender.lower()
                            conflict_found = False
                            stale_writers = set()

                            for w in list(rooms[room_id]["clients"]):
                                if w.is_closing():
                                    stale_writers.add(w)
                                    continue
                                winf = client_info.get(w)
                                if not winf or not winf.get("authenticated"):
                                    continue
                                existing_nick = str(winf.get("nickname") or "").strip()
                                if existing_nick.lower() == norm_sender:
                                    existing_client_id = str(winf.get("client_id") or "").strip()
                                    if client_id and existing_client_id and client_id == existing_client_id:
                                        stale_writers.add(w)
                                        continue
                                    try:
                                        w.write(encode_frame(b"", opcode=0x9))
                                        await asyncio.wait_for(w.drain(), timeout=0.2)
                                        conflict_found = True
                                        break
                                    except Exception:
                                        stale_writers.add(w)
                                        continue

                            for sw in stale_writers:
                                rooms[room_id]["clients"].discard(sw)
                                clients.discard(sw)
                                client_info.pop(sw, None)
                                try:
                                    sw.close()
                                except Exception:
                                    pass

                            if not conflict_found:
                                http_m = rooms[room_id].get("http_members", {})
                                for u, uinf in list(http_m.items()):
                                    if (now - uinf.get("last_ping", 0)) < 20.0:
                                        if u.strip().lower() == norm_sender:
                                            existing_client_id = str(uinf.get("client_id") or "").strip()
                                            if client_id and existing_client_id and client_id == existing_client_id:
                                                continue
                                            conflict_found = True
                                            break
                                    else:
                                        http_m.pop(u, None)

                            if conflict_found:
                                print(f"⛔ [HTTP Auth Failed] Duplicate nickname '{sender}' in room '{room_id}'")
                                resp_dict = {
                                    "status": "error",
                                    "text": f"کاربری با نام «{sender}» در حال حاضر در این اتاق حضور دارد. لطفاً نام دیگری انتخاب کنید."
                                }
                                apply_anti_dpi_padding(resp_dict)
                                writer.write(make_http_json_response(409, json.dumps(resp_dict, ensure_ascii=False)))
                                await writer.drain()
                                writer.close()
                                return

                            rooms[room_id]["last_http_activity"] = now
                            rooms[room_id].setdefault("http_members", {})[sender] = {
                                "last_ping": now,
                                "client_id": client_id
                            }

                            # Broadcast peer_join immediately to active WebSocket clients
                            join_announce = {
                                "type": "peer_join",
                                "room": raw_room,
                                "user": sender,
                                "text": f"«{sender}» وارد اتاق شد.",
                                "ts": now
                            }
                            await broadcast_room(room_id, join_announce)

                        # Compile active room members and their status
                        active_members = []
                        for w in rooms[room_id]["clients"]:
                            winf = client_info.get(w)
                            if winf and winf.get("authenticated") and winf.get("nickname"):
                                lp = winf.get("last_ping", now)
                                active_members.append({
                                    "user": winf["nickname"],
                                    "last_ping": lp,
                                    "online": (now - lp) <= PRESENCE_TIMEOUT
                                })
                        for u, uinf in rooms[room_id].get("http_members", {}).items():
                            lp = uinf.get("last_ping", 0)
                            if not any(m["user"] == u for m in active_members):
                                active_members.append({
                                    "user": u,
                                    "last_ping": lp,
                                    "online": (now - lp) <= PRESENCE_TIMEOUT
                                })

                        resp_dict = {
                            "status": "ok",
                            "room": raw_room,
                            "sender": sender,
                            "members": active_members,
                            "salt": rooms[room_id]["salt"],
                            "server_time": time.time()
                        }
                        apply_anti_dpi_padding(resp_dict)
                        writer.write(make_http_json_response(200, json.dumps(resp_dict, ensure_ascii=False)))
                        await writer.drain()

                # REST API 2: /api/send (Send E2EE message via HTTP POST when WebSocket is blocked)
                elif path == "/api/send":
                    raw_room = str(payload.get("room") or "").strip()
                    password = str(payload.get("password") or "").strip()
                    sender = str(payload.get("sender") or "").strip() or "کاربر"
                    ciphertext = str(payload.get("ciphertext") or payload.get("text") or "").strip()
                    encrypted = bool(payload.get("encrypted", False))
                    msg_id = str(payload.get("msgId") or f"m_{int(time.time()*1000)}_{secrets.token_hex(3)}")
                    time_str = str(payload.get("time") or time.strftime("%H:%M"))

                    room_id = raw_room.lower()
                    if not raw_room or not password or not ciphertext:
                        resp_dict = {"status": "error", "text": "پارامترهای درخواست ناقص است."}
                        apply_anti_dpi_padding(resp_dict)
                        writer.write(make_http_json_response(400, json.dumps(resp_dict, ensure_ascii=False)))
                        await writer.drain()
                    elif room_id not in rooms:
                        resp_dict = {"status": "error", "text": "اتاق یافت نشد."}
                        apply_anti_dpi_padding(resp_dict)
                        writer.write(make_http_json_response(404, json.dumps(resp_dict, ensure_ascii=False)))
                        await writer.drain()
                    else:
                        # Verify room password
                        salt = rooms[room_id]["salt"]
                        expected_hash = rooms[room_id]["hash"]
                        provided_hash = hash_password(password, salt)
                        if not hmac.compare_digest(provided_hash, expected_hash):
                            resp_dict = {"status": "error", "text": "رمز عبور نادرست است."}
                            apply_anti_dpi_padding(resp_dict)
                            writer.write(make_http_json_response(401, json.dumps(resp_dict, ensure_ascii=False)))
                            await writer.drain()
                        else:
                            now = time.time()
                            rooms[room_id]["last_http_activity"] = now
                            rooms[room_id].setdefault("http_members", {})[sender] = {"last_ping": now}
                            msg_record = {
                                "id": msg_id,
                                "room": rooms[room_id].get("name", raw_room),
                                "sender": sender,
                                "ciphertext": ciphertext,
                                "encrypted": encrypted,
                                "status": "sent",
                                "time": time_str,
                                "ts": now
                            }
                            history = rooms[room_id].setdefault("history", [])
                            # Deduplicate if re-sent by client retry queue
                            if not any(m.get("id") == msg_id for m in history):
                                history.append(msg_record)
                                if len(history) > 200:
                                    history.pop(0)

                            print(f"🛡️ [HTTP Tunnel Msg] [{raw_room}] [{sender}]: (E2EE Ciphertext {len(ciphertext)} bytes)")

                            # Broadcast to any active WebSocket connections in this room
                            ws_broadcast = {
                                "type": "chat",
                                "id": msg_id,
                                "room": rooms[room_id].get("name", raw_room),
                                "sender": sender,
                                "ciphertext": ciphertext,
                                "encrypted": encrypted,
                                "status": "sent",
                                "time": time_str,
                                "ts": now
                            }
                            await broadcast_room(room_id, ws_broadcast)

                            resp_dict = {
                                "status": "ok",
                                "msgId": msg_id,
                                "ts": now
                            }
                            apply_anti_dpi_padding(resp_dict)
                            writer.write(make_http_json_response(200, json.dumps(resp_dict, ensure_ascii=False)))
                            await writer.drain()

                # REST API 2.5: /api/receipt (Delivery & Seen Receipts via HTTP)
                elif path == "/api/receipt":
                    raw_room = str(payload.get("room") or "").strip()
                    password = str(payload.get("password") or "").strip()
                    sender = str(payload.get("sender") or "").strip() or "کاربر"
                    receipt_type = str(payload.get("type") or "delivered")  # delivered or seen
                    msg_ids = payload.get("msgIds") or ([payload.get("msgId")] if payload.get("msgId") else [])

                    room_id = raw_room.lower()
                    if not raw_room or not password or room_id not in rooms:
                        resp_dict = {"status": "error", "text": "اتاق یافت نشد یا دسترسی غیرمجاز."}
                        apply_anti_dpi_padding(resp_dict)
                        writer.write(make_http_json_response(401, json.dumps(resp_dict, ensure_ascii=False)))
                        await writer.drain()
                    else:
                        salt = rooms[room_id]["salt"]
                        expected_hash = rooms[room_id]["hash"]
                        provided_hash = hash_password(password, salt)
                        if not hmac.compare_digest(provided_hash, expected_hash):
                            resp_dict = {"status": "error", "text": "رمز عبور نادرست است."}
                            apply_anti_dpi_padding(resp_dict)
                            writer.write(make_http_json_response(401, json.dumps(resp_dict, ensure_ascii=False)))
                            await writer.drain()
                        else:
                            now = time.time()
                            rooms[room_id]["last_http_activity"] = now
                            rooms[room_id].setdefault("http_members", {})[sender] = {"last_ping": now}
                            for mid in msg_ids:
                                if not mid:
                                    continue
                                history = rooms[room_id].get("history", [])
                                for h in history:
                                    if h.get("id") == mid:
                                        if receipt_type == "seen" or h.get("status") != "seen":
                                            h["status"] = receipt_type
                                        break
                                receipts = rooms[room_id].setdefault("receipts", [])
                                receipts.append({"msgId": mid, "status": receipt_type, "by": sender, "ts": now})
                                if len(receipts) > 100:
                                    receipts.pop(0)

                                status_update = {
                                    "type": "msg_status",
                                    "msgId": mid,
                                    "status": receipt_type,
                                    "by": sender,
                                    "ts": now
                                }
                                await broadcast_room(room_id, status_update)

                            resp_dict = {"status": "ok", "updated": len(msg_ids)}
                            apply_anti_dpi_padding(resp_dict)
                            writer.write(make_http_json_response(200, json.dumps(resp_dict, ensure_ascii=False)))
                            await writer.drain()

                # REST API 2.6: /api/peer_ping (HTTP client ping for peer presence)
                elif path == "/api/peer_ping":
                    raw_room = str(payload.get("room") or "").strip()
                    password = str(payload.get("password") or "").strip()
                    sender = str(payload.get("sender") or "").strip() or "کاربر"
                    room_id = raw_room.lower()
                    if room_id in rooms:
                        salt = rooms[room_id]["salt"]
                        expected_hash = rooms[room_id]["hash"]
                        provided_hash = hash_password(password, salt)
                        if hmac.compare_digest(provided_hash, expected_hash):
                            now = time.time()
                            rooms[room_id]["last_http_activity"] = now
                            http_m = rooms[room_id].setdefault("http_members", {})
                            http_m[sender] = {"last_ping": now}
                            await broadcast_room(room_id, {
                                "type": "peer_ping",
                                "room": raw_room,
                                "user": sender,
                                "ts": now
                            })
                            resp_dict = {"status": "ok", "ts": now}
                            apply_anti_dpi_padding(resp_dict)
                            writer.write(make_http_json_response(200, json.dumps(resp_dict, ensure_ascii=False)))
                            await writer.drain()
                            writer.close()
                            return

                # REST API 2.7: /api/leave (Explicit leave for HTTP client)
                elif path == "/api/leave":
                    raw_room = str(payload.get("room") or "").strip()
                    sender = str(payload.get("sender") or "").strip()
                    room_id = raw_room.lower()
                    if room_id in rooms:
                        http_m = rooms[room_id].get("http_members", {})
                        http_m.pop(sender, None)
                        now = time.time()
                        for u, inf in list(http_m.items()):
                            if (now - inf.get("last_ping", 0)) >= PRESENCE_TIMEOUT:
                                http_m.pop(u, None)
                        for w in list(rooms[room_id].get("clients", set())):
                            if w.is_closing():
                                rooms[room_id]["clients"].discard(w)

                        if len(rooms[room_id]["clients"]) > 0 or len(http_m) > 0:
                            await broadcast_room(room_id, {
                                "type": "peer_offline",
                                "room": raw_room,
                                "user": sender,
                                "text": f"«{sender}» از گفتگو خارج شد.",
                                "ts": now
                            })
                        else:
                            cleanup_empty_room(room_id, force=True)
                    resp_dict = {"status": "ok"}
                    apply_anti_dpi_padding(resp_dict)
                    writer.write(make_http_json_response(200, json.dumps(resp_dict, ensure_ascii=False)))
                    await writer.drain()
                    writer.close()
                    return

                # REST API 2.8: /api/delete_room (Explicit deletion by sole member via HTTP)
                elif path == "/api/delete_room":
                    raw_room = str(payload.get("room") or "").strip()
                    password = str(payload.get("password") or "").strip()
                    sender = str(payload.get("sender") or "").strip() or "کاربر"
                    room_id = raw_room.lower()

                    if not raw_room or not password:
                        resp_dict = {"status": "error", "text": "نام اتاق و رمز عبور الزامی است."}
                        apply_anti_dpi_padding(resp_dict)
                        writer.write(make_http_json_response(400, json.dumps(resp_dict, ensure_ascii=False)))
                        await writer.drain()
                        writer.close()
                        return

                    if room_id not in rooms:
                        resp_dict = {"status": "ok", "room": raw_room, "text": "اتاق وجود ندارد یا قبلاً پاک شده است."}
                        apply_anti_dpi_padding(resp_dict)
                        writer.write(make_http_json_response(200, json.dumps(resp_dict, ensure_ascii=False)))
                        await writer.drain()
                        writer.close()
                        return

                    salt = rooms[room_id]["salt"]
                    expected_hash = rooms[room_id]["hash"]
                    provided_hash = hash_password(password, salt)
                    if not hmac.compare_digest(provided_hash, expected_hash):
                        resp_dict = {"status": "error", "text": "رمز عبور نادرست است."}
                        apply_anti_dpi_padding(resp_dict)
                        writer.write(make_http_json_response(401, json.dumps(resp_dict, ensure_ascii=False)))
                        await writer.drain()
                        writer.close()
                        return

                    now = time.time()
                    for w in list(rooms[room_id].get("clients", set())):
                        if w.is_closing():
                            rooms[room_id]["clients"].discard(w)
                    http_m = rooms[room_id].get("http_members", {})
                    for u, inf in list(http_m.items()):
                        if (now - inf.get("last_ping", 0)) >= PRESENCE_TIMEOUT:
                            http_m.pop(u, None)

                    other_ws = len(rooms[room_id].get("clients", set()))
                    other_http = [u for u in http_m.keys() if u.lower() != sender.lower()]

                    if other_ws > 0 or len(other_http) > 0:
                        resp_dict = {"status": "error", "text": "امکان حذف اتاق وجود ندارد زیرا کاربران دیگری در اتاق حضور دارند."}
                        apply_anti_dpi_padding(resp_dict)
                        writer.write(make_http_json_response(409, json.dumps(resp_dict, ensure_ascii=False)))
                        await writer.drain()
                        writer.close()
                        return

                    rooms.pop(room_id, None)
                    print(f"💥 [Room Explicitly Deleted via HTTP] Room '{room_id}' was deleted by sole member '{sender}'")
                    resp_dict = {"status": "ok", "room": raw_room, "text": "اتاق با موفقیت پاکسازی و حذف شد."}
                    apply_anti_dpi_padding(resp_dict)
                    writer.write(make_http_json_response(200, json.dumps(resp_dict, ensure_ascii=False)))
                    await writer.drain()
                    writer.close()
                    return
                else:
                    writer.write(b"HTTP/1.1 404 Not Found\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: 0\r\n\r\n")
                    await writer.drain()

                writer.close()
                return

            if method in ("GET", "HEAD"):
                # REST API 3: /api/poll (Poll new messages since timestamp for strict firewall clients)
                if path == "/api/poll":
                    query_str = raw_path.split("?", 1)[1] if "?" in raw_path else ""
                    params = urllib.parse.parse_qs(query_str)
                    raw_room = params.get("room", [""])[0].strip()
                    password = params.get("password", [""])[0].strip()
                    try:
                        since_ts = float(params.get("since", [0])[0] or 0)
                    except ValueError:
                        since_ts = 0.0

                    room_id = raw_room.lower()
                    if not raw_room or not password or room_id not in rooms:
                        resp_dict = {"status": "error", "text": "دسترسی غیرمجاز یا اتاق یافت نشد."}
                        apply_anti_dpi_padding(resp_dict)
                        writer.write(make_http_json_response(401, json.dumps(resp_dict, ensure_ascii=False)))
                        await writer.drain()
                    else:
                        salt = rooms[room_id]["salt"]
                        expected_hash = rooms[room_id]["hash"]
                        provided_hash = hash_password(password, salt)
                        if not hmac.compare_digest(provided_hash, expected_hash):
                            resp_dict = {"status": "error", "text": "رمز عبور نادرست است."}
                            apply_anti_dpi_padding(resp_dict)
                            writer.write(make_http_json_response(401, json.dumps(resp_dict, ensure_ascii=False)))
                            await writer.drain()
                        else:
                            now = time.time()
                            rooms[room_id]["last_http_activity"] = now
                            history = rooms[room_id].get("history", [])
                            new_msgs = [m for m in history if m.get("ts", 0) > since_ts]
                            receipts = rooms[room_id].get("receipts", [])
                            new_receipts = [r for r in receipts if r.get("ts", 0) > since_ts]

                            now = time.time()
                            active_members = []
                            for w in rooms[room_id]["clients"]:
                                winf = client_info.get(w)
                                if winf and winf.get("authenticated") and winf.get("nickname"):
                                    lp = winf.get("last_ping", now)
                                    active_members.append({
                                        "user": winf["nickname"],
                                        "last_ping": lp,
                                        "online": (now - lp) <= PRESENCE_TIMEOUT
                                    })
                            for u, uinf in rooms[room_id].get("http_members", {}).items():
                                lp = uinf.get("last_ping", 0)
                                if not any(m["user"] == u for m in active_members):
                                    active_members.append({
                                        "user": u,
                                        "last_ping": lp,
                                        "online": (now - lp) <= PRESENCE_TIMEOUT
                                    })

                            resp_dict = {
                                "status": "ok",
                                "room": raw_room,
                                "messages": new_msgs,
                                "receipts": new_receipts,
                                "members": active_members,
                                "server_time": now
                            }
                            apply_anti_dpi_padding(resp_dict)
                            writer.write(make_http_json_response(200, json.dumps(resp_dict, ensure_ascii=False)))
                            await writer.drain()

                    writer.close()
                    return

                # Health, status, and Cloudflare tunnel checks
                if path in ("/health", "/status", "/ping", "/api/tunnel"):
                    resp_dict = {
                        "status": "ok",
                        "service": "rakhssh-chat",
                        "version": VERSION,
                        "active_clients": len(clients),
                        "active_rooms": len(rooms),
                        "features": [
                            "e2ee_aes256",
                            "dual_transport_tunnel",
                            "anti_dpi_traffic_shaping",
                            "random_packet_padding",
                            "decoy_cover_traffic",
                            "timing_jitter",
                            "cloudflare_tunnel_compatible"
                        ],
                        "tunnel": get_active_tunnel(),
                        "timestamp": int(time.time()),
                    }
                    apply_anti_dpi_padding(resp_dict, 128, 512)
                    body = json.dumps(resp_dict, ensure_ascii=False).encode("utf-8")
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
        print(f"\n[+] WebSocket Client connected: {peername[0]}:{peername[1]} (Active clients: {len(clients)})")
        if sys.stdin is not None and sys.stdin.isatty():
            print("Server (type message and press Enter): ", end="", flush=True)

        # Send welcome message frame
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

                # Strip Anti-DPI padding and telemetry noise from client payload
                strip_anti_dpi_padding(payload)
                msg_type = payload.get("type")

                # Heartbeat Ping from Web/Android client
                if msg_type == "ping":
                    pong_resp = {
                        "type": "pong",
                        "time": int(time.time())
                    }
                    apply_anti_dpi_padding(pong_resp)
                    writer.write(encode_frame(json.dumps(pong_resp)))
                    await writer.drain()
                    continue

                # Anti-DPI Decoy / Cover Traffic from client (silent ack with random padding)
                if msg_type in ("decoy", "telemetry"):
                    ack_resp = {
                        "type": "ack",
                        "decoy": True,
                        "time": int(time.time())
                    }
                    apply_anti_dpi_padding(ack_resp)
                    writer.write(encode_frame(json.dumps(ack_resp)))
                    await writer.drain()
                    continue

                # Room Join / Authentication request
                if msg_type == "join":
                    raw_room = str(payload.get("room") or "").strip()
                    password = str(payload.get("password") or "").strip()
                    sender = str(payload.get("sender") or "").strip() or "کاربر"
                    client_id = str(payload.get("clientId") or "").strip()

                    if not raw_room:
                        err = {"type": "auth_error", "text": "نام اتاق نمی‌تواند خالی باشد."}
                        apply_anti_dpi_padding(err)
                        writer.write(encode_frame(json.dumps(err, ensure_ascii=False)))
                        await writer.drain()
                        continue

                    if not password:
                        err = {"type": "auth_error", "text": "رمز عبور اتاق الزامی است."}
                        apply_anti_dpi_padding(err)
                        writer.write(encode_frame(json.dumps(err, ensure_ascii=False)))
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
                            "history": []
                        }
                        print(f"🔒 [WS Room Created] '{room_id}' by '{sender}' from {peername[0]}")
                    else:
                        salt = rooms[room_id]["salt"]
                        expected_hash = rooms[room_id]["hash"]
                        provided_hash = hash_password(password, salt)
                        if not hmac.compare_digest(provided_hash, expected_hash):
                            print(f"⛔ [WS Auth Failed] '{sender}' wrong password for '{room_id}' from {peername[0]}")
                            err = {
                                "type": "auth_error",
                                "room": raw_room,
                                "text": "رمز عبور اتاق نادرست است! دسترسی غیرمجاز."
                            }
                            apply_anti_dpi_padding(err)
                            writer.write(encode_frame(json.dumps(err, ensure_ascii=False)))
                            await writer.drain()
                            continue

                        # Check for duplicate nickname collision in room
                        norm_sender = sender.lower()
                        conflict_found = False
                        stale_writers = set()

                        for w in list(rooms[room_id]["clients"]):
                            if w is writer:
                                continue
                            if w.is_closing():
                                stale_writers.add(w)
                                continue
                            winf = client_info.get(w)
                            if not winf or not winf.get("authenticated"):
                                continue
                            existing_nick = str(winf.get("nickname") or "").strip()
                            if existing_nick.lower() == norm_sender:
                                existing_client_id = str(winf.get("client_id") or "").strip()
                                if client_id and existing_client_id and client_id == existing_client_id:
                                    # Reconnect from same client session: evict old socket
                                    stale_writers.add(w)
                                    continue
                                try:
                                    w.write(encode_frame(b"", opcode=0x9))
                                    await asyncio.wait_for(w.drain(), timeout=0.2)
                                    conflict_found = True
                                    break
                                except Exception:
                                    stale_writers.add(w)
                                    continue

                        for sw in stale_writers:
                            rooms[room_id]["clients"].discard(sw)
                            clients.discard(sw)
                            client_info.pop(sw, None)
                            try:
                                sw.close()
                            except Exception:
                                pass

                        if not conflict_found:
                            # Check active HTTP members
                            now = time.time()
                            http_m = rooms[room_id].get("http_members", {})
                            for u, uinf in list(http_m.items()):
                                if (now - uinf.get("last_ping", 0)) < 20.0:
                                    if u.strip().lower() == norm_sender:
                                        existing_client_id = str(uinf.get("client_id") or "").strip()
                                        if client_id and existing_client_id and client_id == existing_client_id:
                                            continue
                                        conflict_found = True
                                        break
                                else:
                                    http_m.pop(u, None)

                        if conflict_found:
                            print(f"⛔ [WS Auth Failed] Duplicate nickname '{sender}' in room '{room_id}'")
                            err = {
                                "type": "auth_error",
                                "room": raw_room,
                                "text": f"کاربری با نام «{sender}» در حال حاضر در این اتاق حضور دارد. لطفاً نام دیگری انتخاب کنید."
                            }
                            apply_anti_dpi_padding(err)
                            writer.write(encode_frame(json.dumps(err, ensure_ascii=False)))
                            await writer.drain()
                            continue

                    # Remove from old room if already joined
                    old_room = client_info[writer].get("room")
                    if old_room and old_room in rooms:
                        rooms[old_room]["clients"].discard(writer)
                        cleanup_empty_room(old_room)

                    # Authorize client in room
                    now = time.time()
                    rooms[room_id]["clients"].add(writer)
                    client_info[writer] = {
                        "peer": peername,
                        "room": room_id,
                        "room_display": raw_room,
                        "nickname": sender,
                        "client_id": client_id,
                        "authenticated": True,
                        "last_ping": now,
                    }

                    print(f"🔑 [WS Auth Success] '{sender}' joined room '{room_id}' (Members: {len(rooms[room_id]['clients'])})")

                    # Compile existing authenticated room members and their status
                    members = []
                    for w in rooms[room_id]["clients"]:
                        winf = client_info.get(w)
                        if winf and winf.get("authenticated") and winf.get("nickname"):
                            lp = winf.get("last_ping", now)
                            members.append({
                                "user": winf["nickname"],
                                "last_ping": lp,
                                "online": (now - lp) <= PRESENCE_TIMEOUT
                            })
                    for u, uinf in rooms[room_id].get("http_members", {}).items():
                        lp = uinf.get("last_ping", 0)
                        if not any(m["user"] == u for m in members):
                            members.append({
                                "user": u,
                                "last_ping": lp,
                                "online": (now - lp) <= PRESENCE_TIMEOUT
                            })

                    success_resp = {
                        "type": "auth_success",
                        "room": raw_room,
                        "sender": sender,
                        "members": members,
                        "text": f"با موفقیت به اتاق امن «{raw_room}» متصل شدید."
                    }
                    apply_anti_dpi_padding(success_resp)
                    writer.write(encode_frame(json.dumps(success_resp, ensure_ascii=False)))
                    await writer.drain()

                    # Send recent history if available
                    history = rooms[room_id].get("history", [])
                    if history:
                        hist_payload = {
                            "type": "history_sync",
                            "room": raw_room,
                            "messages": history[-50:],
                        }
                        apply_anti_dpi_padding(hist_payload)
                        writer.write(encode_frame(json.dumps(hist_payload, ensure_ascii=False)))
                        await writer.drain()

                    # Notify other members of this room ONLY
                    join_announce_dict = {
                        "type": "peer_join",
                        "room": raw_room,
                        "user": sender,
                        "text": f"«{sender}» وارد اتاق شد.",
                        "ts": now
                    }
                    await broadcast_room(room_id, join_announce_dict, sender_writer=writer)
                    continue

                # Peer Ping Heartbeat (Live peer presence & 2s ping indicator)
                if msg_type == "peer_ping":
                    info = client_info.get(writer)
                    if info and info.get("authenticated") and info.get("room"):
                        current_room = info["room"]
                        sender = info.get("nickname") or payload.get("user") or "کاربر"
                        now = time.time()
                        info["last_ping"] = now
                        peer_ping_msg = json.dumps({
                            "type": "peer_ping",
                            "room": info.get("room_display", current_room),
                            "user": sender,
                            "ts": now
                        }, ensure_ascii=False)
                        await broadcast_room(current_room, peer_ping_msg, sender_writer=writer)
                    continue

                # Message Delivered Receipt (2 ticks: ✓✓)
                if msg_type == "msg_delivered":
                    info = client_info.get(writer)
                    if info and info.get("authenticated") and info.get("room"):
                        current_room = info["room"]
                        sender = info.get("nickname") or "کاربر"
                        msg_id = payload.get("msgId")
                        msg_ids = payload.get("msgIds") or ([msg_id] if msg_id else [])
                        now = time.time()
                        info["last_ping"] = now
                        for mid in msg_ids:
                            if not mid:
                                continue
                            history = rooms.get(current_room, {}).get("history", [])
                            for h in history:
                                if h.get("id") == mid:
                                    if h.get("status") != "seen":
                                        h["status"] = "delivered"
                                    break
                            receipts = rooms[current_room].setdefault("receipts", [])
                            receipts.append({"msgId": mid, "status": "delivered", "by": sender, "ts": now})
                            if len(receipts) > 100:
                                receipts.pop(0)

                            status_update = json.dumps({
                                "type": "msg_status",
                                "msgId": mid,
                                "status": "delivered",
                                "by": sender,
                                "ts": now
                            }, ensure_ascii=False)
                            await broadcast_room(current_room, status_update, sender_writer=writer)
                    continue

                # Message Seen Receipt (2 ticks become circle: ◯)
                if msg_type == "msg_seen":
                    info = client_info.get(writer)
                    if info and info.get("authenticated") and info.get("room"):
                        current_room = info["room"]
                        sender = info.get("nickname") or "کاربر"
                        msg_id = payload.get("msgId")
                        msg_ids = payload.get("msgIds") or ([msg_id] if msg_id else [])
                        now = time.time()
                        info["last_ping"] = now
                        for mid in msg_ids:
                            if not mid:
                                continue
                            history = rooms.get(current_room, {}).get("history", [])
                            for h in history:
                                if h.get("id") == mid:
                                    h["status"] = "seen"
                                    break
                            receipts = rooms[current_room].setdefault("receipts", [])
                            receipts.append({"msgId": mid, "status": "seen", "by": sender, "ts": now})
                            if len(receipts) > 100:
                                receipts.pop(0)

                            status_update = json.dumps({
                                "type": "msg_status",
                                "msgId": mid,
                                "status": "seen",
                                "by": sender,
                                "ts": now
                            }, ensure_ascii=False)
                            await broadcast_room(current_room, status_update, sender_writer=writer)
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
                    ciphertext = str(payload.get("ciphertext") or payload.get("text") or "").strip()
                    encrypted = bool(payload.get("encrypted", False))
                    msg_id = str(payload.get("msgId") or f"m_{int(time.time()*1000)}_{secrets.token_hex(3)}")
                    time_str = payload.get("time") or time.strftime("%H:%M")

                    if not ciphertext:
                        continue

                    now = time.time()
                    info["last_ping"] = now
                    msg_record = {
                        "id": msg_id,
                        "room": display_room,
                        "sender": sender,
                        "ciphertext": ciphertext,
                        "encrypted": encrypted,
                        "status": "sent",
                        "time": time_str,
                        "ts": now
                    }

                    # Store in room history buffer
                    history = rooms[current_room].setdefault("history", [])
                    if not any(m.get("id") == msg_id for m in history):
                        history.append(msg_record)
                        if len(history) > 200:
                            history.pop(0)

                    print(f"🔒 [WS E2EE Msg] [{display_room}] [{sender}]: (Ciphertext length {len(ciphertext)} bytes)")
                    if sys.stdin is not None and sys.stdin.isatty():
                        print("Server (type message and press Enter): ", end="", flush=True)

                    out_msg = json.dumps({
                        "type": "chat",
                        "id": msg_id,
                        "room": display_room,
                        "sender": sender,
                        "ciphertext": ciphertext,
                        "encrypted": encrypted,
                        "status": "sent",
                        "time": time_str,
                        "ts": now
                    }, ensure_ascii=False)

                    # Strictly broadcast only to members of this room
                    await broadcast_room(current_room, out_msg, sender_writer=writer)

                    # Send ACK back to sender with Anti-DPI variable padding
                    ack_dict = {
                        "type": "ack",
                        "msgId": msg_id,
                        "ts": now
                    }
                    apply_anti_dpi_padding(ack_dict)
                    writer.write(encode_frame(json.dumps(ack_dict)))
                    await writer.drain()
                    continue

                # Delete room request (Only permitted if sole active member)
                if msg_type == "delete_room":
                    info = client_info.get(writer)
                    if not info or not info.get("authenticated") or not info.get("room"):
                        continue
                    current_room = info["room"]
                    password = str(payload.get("password") or "").strip()
                    sender = info.get("nickname", "کاربر")

                    if current_room not in rooms:
                        resp = {"type": "room_deleted", "room": current_room, "status": "ok", "text": "اتاق قبلاً حذف شده است."}
                        apply_anti_dpi_padding(resp)
                        writer.write(encode_frame(json.dumps(resp, ensure_ascii=False)))
                        await writer.drain()
                        continue

                    # Verify password
                    salt = rooms[current_room]["salt"]
                    expected_hash = rooms[current_room]["hash"]
                    provided_hash = hash_password(password, salt)
                    if not hmac.compare_digest(provided_hash, expected_hash):
                        err = {"type": "error", "text": "رمز عبور نادرست است. امکان حذف اتاق وجود ندارد."}
                        apply_anti_dpi_padding(err)
                        writer.write(encode_frame(json.dumps(err, ensure_ascii=False)))
                        await writer.drain()
                        continue

                    now = time.time()
                    for w in list(rooms[current_room].get("clients", set())):
                        if w.is_closing():
                            rooms[current_room]["clients"].discard(w)
                    http_m = rooms[current_room].get("http_members", {})
                    for u, inf in list(http_m.items()):
                        if (now - inf.get("last_ping", 0)) >= PRESENCE_TIMEOUT:
                            http_m.pop(u, None)

                    other_ws = [w for w in rooms[current_room]["clients"] if w is not writer]
                    other_http = [u for u in http_m.keys() if u.lower() != sender.lower()]

                    if other_ws or other_http:
                        err = {"type": "error", "text": "امکان حذف اتاق وجود ندارد زیرا کاربران دیگری در اتاق حضور دارند."}
                        apply_anti_dpi_padding(err)
                        writer.write(encode_frame(json.dumps(err, ensure_ascii=False)))
                        await writer.drain()
                        continue

                    rooms.pop(current_room, None)
                    print(f"💥 [Room Explicitly Deleted via WS] Room '{current_room}' was deleted by sole member '{sender}'")
                    resp = {"type": "room_deleted", "room": current_room, "status": "ok", "text": "اتاق با موفقیت پاکسازی و حذف شد."}
                    apply_anti_dpi_padding(resp)
                    writer.write(encode_frame(json.dumps(resp, ensure_ascii=False)))
                    await writer.drain()
                    info["room"] = None
                    info["authenticated"] = False
                    continue

                # Leave room request
                if msg_type == "leave":
                    info = client_info.get(writer)
                    if info and info.get("room"):
                        r = info["room"]
                        s = info.get("nickname", "کاربر")
                        now = time.time()
                        if r in rooms:
                            rooms[r]["clients"].discard(writer)
                            for w in list(rooms[r].get("clients", set())):
                                if w.is_closing():
                                    rooms[r]["clients"].discard(w)
                            http_m = rooms[r].get("http_members", {})
                            for u, inf in list(http_m.items()):
                                if (now - inf.get("last_ping", 0)) >= PRESENCE_TIMEOUT:
                                    http_m.pop(u, None)

                            if len(rooms[r]["clients"]) > 0 or len(http_m) > 0:
                                leave_msg = json.dumps({
                                    "type": "peer_offline",
                                    "room": info.get("room_display", r),
                                    "user": s,
                                    "text": f"«{s}» از اتاق خارج شد.",
                                    "ts": now
                                }, ensure_ascii=False)
                                await broadcast_room(r, leave_msg)
                            else:
                                cleanup_empty_room(r, force=True)
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
                for w in list(rooms[r].get("clients", set())):
                    if w.is_closing():
                        rooms[r]["clients"].discard(w)
                now = time.time()
                http_m = rooms[r].get("http_members", {})
                for u, inf in list(http_m.items()):
                    if (now - inf.get("last_ping", 0)) >= PRESENCE_TIMEOUT:
                        http_m.pop(u, None)

                if len(rooms[r]["clients"]) > 0 or len(http_m) > 0:
                    leave_msg = json.dumps({
                        "type": "peer_offline",
                        "room": info.get("room_display", r),
                        "user": s,
                        "text": f"«{s}» از گفتگو خارج شد.",
                        "ts": now
                    }, ensure_ascii=False)
                    asyncio.create_task(broadcast_room(r, leave_msg))
                else:
                    cleanup_empty_room(r, force=True)

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
                for room_id in list(rooms.keys()):
                    msg = json.dumps({
                        "type": "system",
                        "room": rooms[room_id].get("name", room_id),
                        "sender": "Server Terminal (مدیر)",
                        "text": f"[پیام سرور]: {text}",
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

    # Launch background empty room reaper
    asyncio.create_task(empty_rooms_reaper())

    print("=" * 65)
    print("      🚀 Rakhssh Secure WebSocket & Web Chat Server v1.5.0")
    print("=" * 65)
    print(f"Server is listening on {host}:{port}")
    print("\n👉 Protocols & Endpoints Active:")
    for ip in local_ips:
        print(f"   • Real-Time WebSocket: ws://{ip}:{port}")
        print(f"   • HTTP Safe Tunnel:    http://{ip}:{port}/api/send | /api/poll")
        print(f"   • Web Client UI:       http://{ip}:{port}")
    print(f"   • Health Check:        http://127.0.0.1:{port}/health")
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

        <button id="btnDeleteRoom" class="icon-btn btn-danger-icon hidden" title="پاک کردن کامل اتاق" type="button">
          <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none">
            <polyline points="3 6 5 6 21 6"></polyline>
            <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
            <line x1="10" y1="11" x2="10" y2="17"></line>
            <line x1="14" y1="11" x2="14" y2="17"></line>
          </svg>
        </button>
      </div>

      <div class="header-center">
        <div class="app-title">
          <span>رخش چت</span>
          <span class="version-tag">v1.6.0</span>
          <span id="transportBadge" class="transport-pill ws" title="روش ارتباط و انتقال داده">⚡ وب‌سوکت</span>
          <span id="antiDpiBadge" class="anti-dpi-pill active" title="سپر ضد DPI: پدینگ تصادفی و فرکانس نامنظم پکت‌ها فعال است">🛡️ ضد DPI</span>
        </div>
        <div class="connection-status">
          <span id="statusIndicator" class="status-dot disconnected"></span>
          <span id="statusText">در انتظار اتصال</span>
          <button id="btnCancelReconnectHeader" class="btn-cancel-reconnect-header hidden" type="button" title="توقف تلاش برای اتصال">⏹ توقف تلاش</button>
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

    <!-- Reconnect Control Banner -->
    <div id="reconnectBanner" class="reconnect-banner hidden">
      <div class="reconnect-info">
        <span class="reconnect-icon spinning">🔄</span>
        <span id="reconnectBannerText">در حال تلاش برای اتصال مجدد...</span>
      </div>
      <button type="button" id="btnToggleReconnect" class="btn-banner-action">
        ⏹ توقف تلاش مجدد
      </button>
    </div>

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
          <button type="button" id="btnStopGateRetry" class="btn-gate-stop-retry hidden">⏹ توقف تلاش مجدد</button>
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
              <div class="server-test-row">
                <button type="button" id="btnTestGateConn" class="btn-test-conn btn-test-conn-sm">
                  <svg viewBox="0 0 24 24" width="13" height="13" stroke="currentColor" stroke-width="2" fill="none">
                    <circle cx="11" cy="11" r="8"></circle>
                    <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
                  </svg>
                  <span>🔍 تست آنی اتصال سرور</span>
                </button>
              </div>
              <div id="gateTestFeedback" class="test-feedback-box hidden"></div>
            </div>
          </div>

          <button type="submit" id="btnEnterRoom" class="btn-primary-block">
            <span class="btn-icon">🔒</span>
            <span>ورود و اتصال به اتاق</span>
          </button>
        </form>

        <div class="gate-security-banner">
          <span class="sec-icon">🛡️</span>
          <span>رمزنگاری AES-256 + پدینگ تصادفی ضد DPI + تونل دومنظوره ضد فایروال</span>
        </div>

        <div class="gate-footer-note">
          <span>● پیام‌ها به صورت سرتاسری رمزگذاری می‌شوند؛ سرور یا فایروال قادر به خواندن آن‌ها نیست</span>
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

      <!-- Room Active Members & Ping Status Bar -->
      <div id="roomMembersBar" class="room-members-bar">
        <div class="members-bar-inner">
          <span class="members-title">
            <svg viewBox="0 0 24 24" width="13" height="13" stroke="currentColor" stroke-width="2" fill="none"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"></path><circle cx="9" cy="7" r="4"></circle><path d="M23 21v-2a4 4 0 0 0-3-3.87"></path><path d="M16 3.13a4 4 0 0 1 0 7.75"></path></svg>
            اعضای اتاق:
          </span>
          <div id="membersList" class="members-chips-container">
            <!-- Dynamically populated member chips -->
          </div>
        </div>
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
            <label for="modalServerUrl">آدرس سرور WebSocket / تونل امن:</label>
            <input 
              type="text" 
              id="modalServerUrl" 
              dir="ltr"
              placeholder="ws://193.168.175.227:8765 یا wss://..." 
            />
            <div class="server-test-row">
              <button type="button" id="btnTestServerConn" class="btn-test-conn">
                <svg viewBox="0 0 24 24" width="14" height="14" stroke="currentColor" stroke-width="2" fill="none">
                  <circle cx="11" cy="11" r="8"></circle>
                  <line x1="21" y1="21" x2="16.65" y2="16.65"></line>
                </svg>
                <span>🔍 تست و بررسی آنی اتصال</span>
              </button>
            </div>
            <div id="serverTestFeedback" class="test-feedback-box hidden"></div>
          </div>

          <!-- Connection Mode Presets -->
          <div class="presets-block">
            <span class="field-label-sm">الگوهای اتصال ضد مسدودسازی:</span>
            <div class="preset-buttons-grid">
              <button type="button" id="btnPresetDirect" class="preset-btn">
                ⚡ سرور مستقیم (:8765)
              </button>
              <button type="button" id="btnPresetCfTunnel" class="preset-btn">
                ☁️ کلودفلر تونل (:443)
              </button>
            </div>
            <small class="field-hint">در صورت اختلال شدید یا فیلترینگ پورت، از کلودفلر تونل یا VPN فعال استفاده کنید.</small>
          </div>

          <!-- Anti-DPI & Traffic Shaping Section -->
          <div class="anti-dpi-section">
            <div class="anti-dpi-header">
              <span class="anti-dpi-title">🛡️ سپر ضد DPI و تغییر شکل ترافیک (Traffic Shaping)</span>
              <span class="anti-dpi-status-badge">فعال</span>
            </div>
            <div class="form-group checkbox-group">
              <label>
                <input type="checkbox" id="antiDpiToggle" checked />
                پدینگ نویز تصادفی (Random Padding) برای مخفی‌سازی سایز پکت
              </label>
            </div>
            <div class="form-group checkbox-group">
              <label>
                <input type="checkbox" id="decoyChaffToggle" checked />
                ارسال بسته‌های پوششی (Decoy Chaff) در زمان سکوت کاربر
              </label>
            </div>
            <div class="anti-dpi-metrics">
              <span>● سایز هر بسته: ۴۰۰ تا ۱۶۰۰ بایت تصادفی</span>
              <span>● ناهماهنگی زمانی هارت‌بیت: ۱۴ تا ۲۸ ثانیه (Jittered)</span>
            </div>
          </div>

          <div class="form-group">
            <label for="modalCleanIp">آی‌پی تمیز کلودفلر (Clean IP اختیاری):</label>
            <input 
              type="text" 
              id="modalCleanIp" 
              dir="ltr"
              placeholder="مثلاً: 104.16.132.229 یا خالی" 
            />
            <small class="field-hint">تنها در شرایط اختلال DNS/SNI برای کاربران داخل ایران استفاده شود.</small>
          </div>

          <div class="form-group checkbox-group">
            <label>
              <input type="checkbox" id="autoReconnect" checked />
              اتصال مجدد خودکار در صورت قطع شدن شبکه
            </label>
          </div>

          <div class="form-group checkbox-group">
            <label>
              <input type="checkbox" id="notificationToggle" checked />
              فعال بودن اعلان‌ها و صدای پیام (روشن/خاموش)
            </label>
          </div>

          <div class="form-group checkbox-group">
            <label>
              <input type="checkbox" id="vibrationToggle" checked />
              ویبره هنگام پیام‌های جدید (خطای اتصال هرگز ویبره نمی‌زند)
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
            <button id="btnDeleteRoomModal" class="btn-delete-room-modal hidden" type="button">🗑️ پاک کردن و حذف کامل اتاق</button>
          </div>
        </div>
      </div>
    </div>
  </div>

  <script src="crypto-js.min.js"></script>
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

.transport-pill {
  font-size: 10px;
  font-weight: 600;
  padding: 1px 7px;
  border-radius: 9999px;
  display: inline-flex;
  align-items: center;
  gap: 3px;
  transition: all 0.3s ease;
}

.transport-pill.ws {
  color: #34d399;
  background: rgba(16, 185, 129, 0.15);
  border: 1px solid rgba(16, 185, 129, 0.3);
}

.transport-pill.http {
  color: #38bdf8;
  background: rgba(56, 189, 248, 0.15);
  border: 1px solid rgba(56, 189, 248, 0.35);
}

.gate-security-banner {
  background: rgba(15, 23, 42, 0.6);
  border: 1px solid rgba(56, 189, 248, 0.25);
  border-radius: 8px;
  padding: 8px 12px;
  font-size: 11px;
  color: #38bdf8;
  margin-top: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  line-height: 1.4;
  text-align: center;
}

.msg-lock {
  font-size: 10px;
  margin-left: 3px;
  opacity: 0.8;
  vertical-align: middle;
}

.msg-status {
  font-size: 11px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  line-height: 1;
}

.msg-status.pending {
  color: #f59e0b;
  font-size: 11px;
  animation: pulse-spin 1.5s infinite;
}

.msg-status.sent {
  color: rgba(255, 255, 255, 0.75);
  font-size: 11px;
}

.msg-status.delivered {
  color: #38bdf8;
  font-size: 11px;
  font-weight: 700;
  letter-spacing: -2px;
}

.msg-status.seen {
  color: #38bdf8;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.status-circle-svg {
  width: 11px;
  height: 11px;
  stroke: #38bdf8;
  fill: none;
  stroke-width: 2.2;
  filter: drop-shadow(0 0 3px rgba(56, 189, 248, 0.8));
}

.peer-status-dot {
  display: inline-block;
  width: 7px;
  height: 7px;
  border-radius: 50%;
  margin-left: 5px;
  vertical-align: middle;
  transition: background-color 0.25s ease, box-shadow 0.25s ease;
}

.peer-status-dot.online {
  background-color: #22c55e;
  box-shadow: 0 0 6px #22c55e;
}

.peer-status-dot.offline {
  background-color: #ef4444;
  box-shadow: 0 0 6px #ef4444;
}

@keyframes pulse-spin {
  0% { opacity: 0.4; }
  50% { opacity: 1; }
  100% { opacity: 0.4; }
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

#btnNotification.active-notif {
  color: var(--accent-glow, #818cf8);
}

#btnNotification.muted-notif {
  color: var(--danger, #ef4444);
  opacity: 0.8;
}

#btnNotification.muted-notif:hover {
  opacity: 1;
}

.btn-danger-icon {
  color: #f87171;
}

.btn-danger-icon:hover:not(:disabled):not(.disabled) {
  background: rgba(239, 68, 68, 0.18);
  color: #ef4444;
}

.icon-btn.disabled,
.icon-btn:disabled {
  opacity: 0.3 !important;
  cursor: not-allowed !important;
  pointer-events: auto !important;
}

.btn-delete-room-modal {
  width: 100%;
  margin-top: 8px;
  background: rgba(239, 68, 68, 0.2);
  border: 1px solid rgba(239, 68, 68, 0.5);
  color: #fca5a5;
  border-radius: 10px;
  padding: 12px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  font-family: inherit;
  transition: all 0.2s ease;
}

.btn-delete-room-modal:hover:not(:disabled):not(.disabled) {
  background: rgba(239, 68, 68, 0.35);
  border-color: #ef4444;
  color: #fff;
}

.btn-delete-room-modal.disabled,
.btn-delete-room-modal:disabled {
  opacity: 0.4 !important;
  cursor: not-allowed !important;
  border-color: rgba(239, 68, 68, 0.2) !important;
  color: #888 !important;
  background: rgba(255, 255, 255, 0.05) !important;
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

.anti-dpi-pill {
  font-size: 10px;
  font-weight: 600;
  padding: 1px 7px;
  border-radius: 9999px;
  display: inline-flex;
  align-items: center;
  gap: 3px;
  color: #a78bfa;
  background: rgba(167, 139, 250, 0.15);
  border: 1px solid rgba(167, 139, 250, 0.35);
  transition: all 0.3s ease;
}

.anti-dpi-pill.disabled {
  color: var(--text-dim);
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid var(--border-subtle);
  opacity: 0.6;
}

.presets-block {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.server-test-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 8px;
}

.btn-test-conn {
  background: var(--bg-surface-elevated);
  border: 1px solid rgba(56, 189, 248, 0.35);
  color: #38bdf8;
  border-radius: 8px;
  padding: 8px 14px;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  font-family: inherit;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  transition: all 0.2s ease;
}

.btn-test-conn:hover {
  background: rgba(56, 189, 248, 0.18);
  border-color: rgba(56, 189, 248, 0.6);
  color: #7dd3fc;
  box-shadow: 0 2px 8px rgba(56, 189, 248, 0.2);
}

.btn-test-conn:active {
  transform: scale(0.97);
}

.btn-test-conn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
  transform: none;
}

.btn-test-conn-sm {
  padding: 6px 10px;
  font-size: 11px;
}

.test-feedback-box {
  margin-top: 8px;
  padding: 10px 12px;
  border-radius: 8px;
  font-size: 12px;
  line-height: 1.5;
  transition: all 0.2s ease;
  animation: fadeInFeedback 0.25s ease-out;
}

@keyframes fadeInFeedback {
  from { opacity: 0; transform: translateY(-4px); }
  to { opacity: 1; transform: translateY(0); }
}

.test-feedback-box.testing {
  background: rgba(56, 189, 248, 0.1);
  border: 1px solid rgba(56, 189, 248, 0.3);
  color: #7dd3fc;
}

.test-feedback-box.success {
  background: rgba(34, 197, 94, 0.12);
  border: 1px solid rgba(34, 197, 94, 0.35);
  color: #86efac;
}

.test-feedback-box.warning {
  background: rgba(234, 179, 8, 0.12);
  border: 1px solid rgba(234, 179, 8, 0.35);
  color: #fde047;
}

.test-feedback-box.error {
  background: rgba(239, 68, 68, 0.12);
  border: 1px solid rgba(239, 68, 68, 0.35);
  color: #fca5a5;
}

.test-feedback-box .test-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-top: 5px;
  font-size: 11px;
  opacity: 0.95;
}

.test-feedback-box .test-sub {
  margin-top: 4px;
  font-size: 11px;
  opacity: 0.9;
}

.test-feedback-box .test-reasons {
  margin: 6px 0 0 16px;
  padding: 0;
  font-size: 11px;
  line-height: 1.45;
}

.test-feedback-box .test-hint {
  margin-top: 6px;
  padding-top: 6px;
  border-top: 1px dashed rgba(255, 255, 255, 0.15);
  font-size: 11px;
  color: #e2e8f0;
}

.field-label-sm {
  font-size: 12px;
  font-weight: 600;
  color: var(--text-light);
}

.preset-buttons-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}

.preset-btn {
  background: var(--bg-surface-elevated);
  border: 1px solid var(--border-subtle);
  color: var(--text-light);
  border-radius: 8px;
  padding: 8px 10px;
  font-size: 12px;
  font-weight: 500;
  cursor: pointer;
  font-family: inherit;
  transition: all 0.2s;
  text-align: center;
}

.preset-btn:hover, .preset-btn:active {
  background: rgba(56, 189, 248, 0.15);
  border-color: rgba(56, 189, 248, 0.4);
  color: #38bdf8;
}

.anti-dpi-section {
  background: rgba(167, 139, 250, 0.08);
  border: 1px solid rgba(167, 139, 250, 0.25);
  border-radius: 10px;
  padding: 12px;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.anti-dpi-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.anti-dpi-title {
  font-size: 12px;
  font-weight: 700;
  color: #c4b5fd;
}

.anti-dpi-status-badge {
  font-size: 10px;
  font-weight: 700;
  background: rgba(16, 185, 129, 0.2);
  color: #34d399;
  border: 1px solid rgba(16, 185, 129, 0.4);
  border-radius: 9999px;
  padding: 1px 6px;
}

.anti-dpi-metrics {
  display: flex;
  flex-direction: column;
  gap: 3px;
  font-size: 11px;
  color: #a78bfa;
  background: rgba(0, 0, 0, 0.2);
  padding: 8px 10px;
  border-radius: 6px;
  direction: rtl;
}

/* ==========================================================================
   v1.5.0 Reconnection Controls & Room Members Bar
   ========================================================================== */
.btn-cancel-reconnect-header {
  background: rgba(239, 68, 68, 0.25);
  border: 1px solid rgba(239, 68, 68, 0.45);
  color: #fca5a5;
  border-radius: 6px;
  font-size: 10px;
  font-weight: 600;
  padding: 2px 7px;
  cursor: pointer;
  margin-right: 6px;
  transition: all 0.2s;
  line-height: 1.4;
}

.btn-cancel-reconnect-header:hover, .btn-cancel-reconnect-header:active {
  background: rgba(239, 68, 68, 0.45);
}

.btn-cancel-reconnect-header.resume {
  background: rgba(34, 197, 94, 0.25);
  border-color: rgba(34, 197, 94, 0.5);
  color: #86efac;
}

.reconnect-banner {
  background: rgba(239, 68, 68, 0.16);
  border-bottom: 1px solid rgba(239, 68, 68, 0.35);
  color: #fca5a5;
  padding: 8px 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  font-size: 12px;
  animation: slide-down 0.25s ease-out;
  z-index: 10;
}

.reconnect-banner.paused {
  background: rgba(245, 158, 11, 0.16);
  border-bottom-color: rgba(245, 158, 11, 0.35);
  color: #fcd34d;
}

.reconnect-info {
  display: flex;
  align-items: center;
  gap: 8px;
  font-weight: 500;
}

.reconnect-icon {
  display: inline-block;
  font-size: 13px;
}

.reconnect-icon.spinning {
  animation: spin 1.2s linear infinite;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

@keyframes slide-down {
  from { transform: translateY(-100%); opacity: 0; }
  to { transform: translateY(0); opacity: 1; }
}

.btn-banner-action {
  background: rgba(239, 68, 68, 0.3);
  border: 1px solid rgba(239, 68, 68, 0.55);
  color: #fee2e2;
  font-weight: 600;
  border-radius: 6px;
  padding: 4px 10px;
  font-size: 11px;
  cursor: pointer;
  white-space: nowrap;
  transition: all 0.2s;
}

.btn-banner-action:hover, .btn-banner-action:active {
  background: rgba(239, 68, 68, 0.55);
}

.btn-banner-action.resume {
  background: rgba(34, 197, 94, 0.25);
  border-color: rgba(34, 197, 94, 0.5);
  color: #86efac;
}

.btn-gate-stop-retry {
  display: block;
  width: 100%;
  margin-top: 8px;
  background: rgba(239, 68, 68, 0.25);
  border: 1px solid rgba(239, 68, 68, 0.5);
  color: #fee2e2;
  font-size: 11px;
  font-weight: 600;
  padding: 6px 10px;
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-gate-stop-retry:hover, .btn-gate-stop-retry:active {
  background: rgba(239, 68, 68, 0.45);
}

.btn-gate-stop-retry.resume {
  background: rgba(34, 197, 94, 0.25);
  border-color: rgba(34, 197, 94, 0.5);
  color: #86efac;
}

/* Room Members Bar */
.room-members-bar {
  background: rgba(15, 23, 42, 0.85);
  backdrop-filter: blur(8px);
  border-bottom: 1px solid rgba(56, 189, 248, 0.15);
  padding: 6px 14px;
  font-size: 11px;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.15);
}

.members-bar-inner {
  display: flex;
  align-items: center;
  gap: 8px;
  overflow-x: auto;
  scrollbar-width: none;
}

.members-bar-inner::-webkit-scrollbar {
  display: none;
}

.members-title {
  color: var(--text-muted);
  font-size: 11px;
  white-space: nowrap;
  display: flex;
  align-items: center;
  gap: 4px;
  font-weight: 600;
}

.members-chips-container {
  display: flex;
  align-items: center;
  gap: 6px;
  flex-wrap: nowrap;
}

.member-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  background: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.1);
  padding: 2px 8px;
  border-radius: 9999px;
  color: var(--text-main);
  font-size: 11px;
  white-space: nowrap;
  transition: all 0.2s;
}

.member-chip.me {
  border-color: rgba(56, 189, 248, 0.35);
  color: #38bdf8;
  background: rgba(56, 189, 248, 0.08);
}

.hidden {
  display: none !important;
}

STYLE_EOF

cat << 'APP_EOF' > "${INSTALL_DIR}/web/app.js"
(() => {
  // ==========================================================================
  // Rakhssh Chat v1.3.0 Client Application
  // Features:
  //   1. Zero-Knowledge End-to-End Encryption (E2EE) with AES-256
  //   2. Dual-Transport Engine: WebSocket primary + HTTP Safe Tunnel Fallback
  //   3. Bulletproof Firewall & Middlebox Resilience (Zero Message Drop)
  //   4. Outgoing Message Queue with Automatic Retry
  //   5. Lock Screen Notifications & Persistent Background Service
  // ==========================================================================

  // DOM Elements - Header & Status
  const statusIndicator = document.getElementById("statusIndicator");
  const statusText = document.getElementById("statusText");
  const roomStatusBadge = document.getElementById("roomStatusBadge");
  const currentRoomDisplay = document.getElementById("currentRoomDisplay");
  const transportBadge = document.getElementById("transportBadge");
  const antiDpiBadge = document.getElementById("antiDpiBadge");
  const btnSettings = document.getElementById("btnSettings");
  const btnLeaveRoom = document.getElementById("btnLeaveRoom");
  const btnDeleteRoom = document.getElementById("btnDeleteRoom");
  const btnNotification = document.getElementById("btnNotification");
  const btnClear = document.getElementById("btnClear");
  const btnCancelReconnectHeader = document.getElementById("btnCancelReconnectHeader");

  // DOM Elements - Reconnect Banner
  const reconnectBanner = document.getElementById("reconnectBanner");
  const reconnectBannerText = document.getElementById("reconnectBannerText");
  const btnToggleReconnect = document.getElementById("btnToggleReconnect");

  // DOM Elements - Room Gate
  const roomGate = document.getElementById("roomGate");
  const gateForm = document.getElementById("gateForm");
  const gateNickname = document.getElementById("gateNickname");
  const gateRoomName = document.getElementById("gateRoomName");
  const gateRoomPassword = document.getElementById("gateRoomPassword");
  const btnTogglePassword = document.getElementById("btnTogglePassword");
  const gateError = document.getElementById("gateError");
  const gateErrorText = document.getElementById("gateErrorText");
  const btnStopGateRetry = document.getElementById("btnStopGateRetry");
  const btnToggleAdvanced = document.getElementById("btnToggleAdvanced");
  const advancedServerBlock = document.getElementById("advancedServerBlock");
  const serverUrlInput = document.getElementById("serverUrl");
  const btnTestGateConn = document.getElementById("btnTestGateConn");
  const gateTestFeedback = document.getElementById("gateTestFeedback");
  const btnEnterRoom = document.getElementById("btnEnterRoom");

  // DOM Elements - Active Chat View
  const chatView = document.getElementById("chatView");
  const notifBanner = document.getElementById("notifBanner");
  const btnEnableNotif = document.getElementById("btnEnableNotif");
  const roomMembersBar = document.getElementById("roomMembersBar");
  const membersList = document.getElementById("membersList");
  const chatMessages = document.getElementById("chatMessages");
  const chatForm = document.getElementById("chatForm");
  const messageInput = document.getElementById("messageInput");

  // DOM Elements - Settings Modal
  const settingsModal = document.getElementById("settingsModal");
  const btnCloseSettings = document.getElementById("btnCloseSettings");
  const modalServerUrl = document.getElementById("modalServerUrl");
  const btnTestServerConn = document.getElementById("btnTestServerConn");
  const serverTestFeedback = document.getElementById("serverTestFeedback");
  const modalCleanIp = document.getElementById("modalCleanIp");
  const antiDpiToggle = document.getElementById("antiDpiToggle");
  const decoyChaffToggle = document.getElementById("decoyChaffToggle");
  const btnPresetDirect = document.getElementById("btnPresetDirect");
  const btnPresetCfTunnel = document.getElementById("btnPresetCfTunnel");
  const autoReconnectInput = document.getElementById("autoReconnect");
  const notificationToggle = document.getElementById("notificationToggle");
  const vibrationToggle = document.getElementById("vibrationToggle");
  const keepCredentialsInput = document.getElementById("keepCredentials");
  const btnTestNotif = document.getElementById("btnTestNotif");
  const btnMinimizeApp = document.getElementById("btnMinimizeApp");
  const btnDisconnectModal = document.getElementById("btnDisconnectModal");
  const btnDeleteRoomModal = document.getElementById("btnDeleteRoomModal");

  // Client Session Unique ID (persisted across refreshes in sessionStorage)
  let clientId = "";
  try {
    clientId = sessionStorage.getItem("rssh_client_id") || "";
    if (!clientId) {
      clientId = "c_" + Math.random().toString(36).substring(2, 10) + Date.now().toString(36);
      sessionStorage.setItem("rssh_client_id", clientId);
    }
  } catch (e) {
    clientId = "c_" + Math.random().toString(36).substring(2, 10) + Date.now().toString(36);
  }

  // Notification Toggle Icons (Feather / Lucide Style)
  const NOTIF_BELL_ON_SVG = `
    <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
      <path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"></path>
      <path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
    </svg>
  `;

  const NOTIF_BELL_OFF_SVG = `
    <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round" stroke-linejoin="round">
      <path d="M13.73 21a2 2 0 0 1-3.46 0"></path>
      <path d="M18.63 13A17.89 17.89 0 0 1 18 8"></path>
      <path d="M6.26 6.26A5.86 5.86 0 0 0 6 8c0 7-3 9-3 9h14"></path>
      <path d="M18 8a6 6 0 0 0-9.33-5"></path>
      <line x1="1" y1="1" x2="23" y2="23"></line>
    </svg>
  `;

  // Application State
  let ws = null;
  let wsHandshakeTimer = null;
  let jitteredPingTimer = null;
  let decoyChaffTimer = null;
  let heartbeatTimer = null;
  let reconnectTimer = null;
  let httpPollTimer = null;
  let queueRetryTimer = null;
  let wsProbeTimer = null;
  let isConnecting = false;
  let isManualDisconnect = false;
  let isReconnectStopped = false;
  let unreadCount = 0;
  const originalTitle = document.title;

  // Peer presence & freshness tracking (2-second ping indicator)
  const peers = new Map(); // username -> { lastPing: timestamp, isOnline: boolean }
  let peerPingInterval = null;
  let peerFreshnessChecker = null;

  // Unseen messages queue for read receipts (turning 2 ticks into circle)
  const unseenMessageIds = new Set();

  const state = {
    nickname: "کاربر",
    room: "",
    password: "",
    serverUrl: "",
    cleanIp: "",
    antiDpi: true,
    decoyChaff: true,
    autoReconnect: true,
    notificationsEnabled: true,
    vibrationEnabled: true,
    keepCredentials: true,
    isAuthenticated: false,
    transportMode: "ws", // "ws" | "http"
    lastSyncTimestamp: 0.0,
    lastActivityTime: Date.now(),
    outgoingQueue: [],
    seenMessageIds: new Set(),
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
  state.activeTunnelUrl = "wss://occurring-nearby-salvador-photography.trycloudflare.com";

  if (savedConfig.nickname) state.nickname = savedConfig.nickname;
  if (savedConfig.room) state.room = savedConfig.room;
  if (savedConfig.password) state.password = savedConfig.password;
  if (savedConfig.cleanIp) state.cleanIp = savedConfig.cleanIp;
  if (savedConfig.antiDpi !== undefined) state.antiDpi = savedConfig.antiDpi;
  if (savedConfig.decoyChaff !== undefined) state.decoyChaff = savedConfig.decoyChaff;
  if (savedConfig.autoReconnect !== undefined) state.autoReconnect = savedConfig.autoReconnect;
  if (savedConfig.notificationsEnabled !== undefined) state.notificationsEnabled = savedConfig.notificationsEnabled;
  if (savedConfig.vibrationEnabled !== undefined) state.vibrationEnabled = savedConfig.vibrationEnabled;
  if (savedConfig.keepCredentials !== undefined) state.keepCredentials = savedConfig.keepCredentials;

  function updateNotificationUI() {
    if (state.notificationsEnabled) {
      btnNotification.innerHTML = NOTIF_BELL_ON_SVG;
      btnNotification.classList.remove("muted-notif");
      btnNotification.classList.add("active-notif");
      btnNotification.setAttribute("title", "اعلان‌ها روشن است (برای خاموش کردن کلیک کنید)");
      if (notificationToggle) notificationToggle.checked = true;
    } else {
      btnNotification.innerHTML = NOTIF_BELL_OFF_SVG;
      btnNotification.classList.remove("active-notif");
      btnNotification.classList.add("muted-notif");
      btnNotification.setAttribute("title", "اعلان‌ها خاموش است (برای روشن کردن کلیک کنید)");
      if (notificationToggle) notificationToggle.checked = false;
    }
  }

  function toggleNotifications() {
    state.notificationsEnabled = !state.notificationsEnabled;
    updateNotificationUI();
    persistSettings();

    if (state.notificationsEnabled) {
      if ("Notification" in window && Notification.permission === "default") {
        Notification.requestPermission().then((permission) => {
          if (permission === "granted") {
            notifBanner.classList.add("hidden");
            nativeToast("اعلان‌ها فعال شد 🔔");
            playAudioChime();
          } else {
            nativeToast("مجوز اعلان در مرورگر داده نشد");
          }
        });
        return;
      }
      nativeToast("اعلان‌ها روشن شد 🔔");
      playAudioChime();
    } else {
      nativeToast("اعلان‌ها و صدای پیام خاموش شد 🔕");
    }
  }

  // Initialize Form Values
  gateNickname.value = state.nickname || "کاربر";
  gateRoomName.value = state.room || "";
  gateRoomPassword.value = state.password || "";
  serverUrlInput.value = state.serverUrl;
  modalServerUrl.value = state.serverUrl;
  if (modalCleanIp) modalCleanIp.value = state.cleanIp || "";
  if (antiDpiToggle) antiDpiToggle.checked = state.antiDpi;
  if (decoyChaffToggle) decoyChaffToggle.checked = state.decoyChaff;
  if (autoReconnectInput) autoReconnectInput.checked = state.autoReconnect;
  if (notificationToggle) notificationToggle.checked = state.notificationsEnabled;
  if (vibrationToggle) vibrationToggle.checked = state.vibrationEnabled;
  if (keepCredentialsInput) keepCredentialsInput.checked = state.keepCredentials;
  updateNotificationUI();

  // Save Settings Helper
  function persistSettings() {
    const dataToSave = {
      serverUrl: state.serverUrl,
      cleanIp: state.cleanIp,
      antiDpi: state.antiDpi,
      decoyChaff: state.decoyChaff,
      nickname: state.nickname,
      autoReconnect: state.autoReconnect,
      notificationsEnabled: state.notificationsEnabled,
      vibrationEnabled: state.vibrationEnabled,
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

    if (!url.includes("://")) {
      url = "ws://" + url;
    }

    if (url.startsWith("http://")) {
      url = "ws://" + url.substring(7);
    } else if (url.startsWith("https://")) {
      url = "wss://" + url.substring(8);
    }

    try {
      const parsed = new URL(url);
      if (!parsed.port && !parsed.hostname.includes(".")) {
        url = `${parsed.protocol}//${parsed.hostname}:8765${parsed.pathname}`;
      }
    } catch (e) {}

    return url;
  }

  function getHttpBaseUrl(wsUrl) {
    let url = (wsUrl || "").trim();
    if (url.startsWith("wss://")) {
      return "https://" + url.slice(6).replace(/\/ws\/?$/, "");
    }
    if (url.startsWith("ws://")) {
      return "http://" + url.slice(5).replace(/\/ws\/?$/, "");
    }
    if (url.startsWith("https://") || url.startsWith("http://")) {
      return url.replace(/\/ws\/?$/, "");
    }
    const proto = window.location.protocol === "https:" ? "https:" : "http:";
    return `${proto}//${window.location.host || "193.168.175.227:8765"}`;
  }

  async function queryActiveTunnel(baseUrl) {
    try {
      const httpBase = getHttpBaseUrl(baseUrl || state.serverUrl || "ws://193.168.175.227:8765");
      const resp = await fetch(`${httpBase}/api/tunnel`, {
        cache: "no-store",
        signal: AbortSignal.timeout(3000),
      });
      if (resp.ok) {
        const data = await resp.json();
        if (data && data.tunnel && data.tunnel.active && data.tunnel.ws_url) {
          state.activeTunnelUrl = data.tunnel.ws_url;
          return data.tunnel;
        }
      }
    } catch (e) {}
    return null;
  }

  async function testServerConnectivity(targetUrl, feedbackEl, btnEl) {
    if (!feedbackEl) return;

    let rawUrl = (targetUrl || "").trim();
    if (!rawUrl) {
      rawUrl = state.serverUrl || "ws://193.168.175.227:8765";
    }

    // Determine normalized WS and HTTP URLs
    let wsUrl = rawUrl;
    let httpUrl = rawUrl;

    if (!wsUrl.includes("://")) {
      if (wsUrl.includes("trycloudflare.com") || wsUrl.endsWith(":443")) {
        wsUrl = "wss://" + wsUrl;
        httpUrl = "https://" + rawUrl;
      } else {
        wsUrl = "ws://" + wsUrl;
        httpUrl = "http://" + rawUrl;
      }
    } else {
      if (wsUrl.startsWith("http://")) {
        wsUrl = "ws://" + wsUrl.slice(7);
        httpUrl = rawUrl;
      } else if (wsUrl.startsWith("https://")) {
        wsUrl = "wss://" + wsUrl.slice(8);
        httpUrl = rawUrl;
      } else if (wsUrl.startsWith("ws://")) {
        httpUrl = "http://" + wsUrl.slice(5);
      } else if (wsUrl.startsWith("wss://")) {
        httpUrl = "https://" + wsUrl.slice(6);
      }
    }

    // Clean paths
    httpUrl = httpUrl.replace(/\/ws\/?$/, "").replace(/\/+$/, "");
    wsUrl = wsUrl.replace(/\/+$/, "");

    // Set UI testing state
    feedbackEl.classList.remove("hidden", "success", "warning", "error");
    feedbackEl.classList.add("testing");
    feedbackEl.innerHTML = `
      <div style="display:flex;align-items:center;gap:8px;">
        <span class="reconnect-icon spinning">🔄</span>
        <span>در حال آزمایش و بررسی اتصال به سرور...</span>
      </div>
    `;

    if (btnEl) {
      btnEl.disabled = true;
      btnEl.classList.add("testing");
    }

    // Run HTTP and WS tests with timeout
    const testWsPromise = new Promise((resolve) => {
      const startT = performance.now();
      let testSocket = null;
      let timer = null;

      try {
        testSocket = new WebSocket(wsUrl);
      } catch (err) {
        resolve({ ok: false, error: err.message || "آدرس وب‌سوکت نامعتبر است" });
        return;
      }

      timer = setTimeout(() => {
        try { if (testSocket) testSocket.close(); } catch (e) {}
        resolve({ ok: false, error: "مهلت زمانی برقراری وب‌سوکت به پایان رسید (Timeout 5s)" });
      }, 5000);

      testSocket.onopen = () => {
        clearTimeout(timer);
        const lat = Math.round(performance.now() - startT);
        try { testSocket.close(); } catch (e) {}
        resolve({ ok: true, latency: lat });
      };

      testSocket.onerror = () => {
        clearTimeout(timer);
        try { testSocket.close(); } catch (err) {}
        resolve({ ok: false, error: "خطای پروتکل یا مسدودسازی دست‌دادن وب‌سوکت" });
      };
    });

    const testHttpPromise = (async () => {
      const startT = performance.now();
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 5000);
        const res = await fetch(`${httpUrl}/health`, {
          method: "GET",
          signal: controller.signal,
          cache: "no-store",
        });
        clearTimeout(timeoutId);
        if (res.ok) {
          const lat = Math.round(performance.now() - startT);
          const json = await res.json().catch(() => null);
          return { ok: true, latency: lat, data: json };
        }
        return { ok: false, error: `پاسخ سرور HTTP: ${res.status} ${res.statusText}` };
      } catch (err) {
        return { ok: false, error: err.name === "AbortError" ? "مهلت زمانی به پایان رسید (Timeout 5s)" : (err.message || "سرور پاسخ نداد") };
      }
    })();

    const [wsRes, httpRes] = await Promise.all([testWsPromise, testHttpPromise]);

    if (btnEl) {
      btnEl.disabled = false;
      btnEl.classList.remove("testing");
    }

    feedbackEl.classList.remove("testing");

    if (wsRes.ok) {
      // Full Success: WebSocket is OPEN!
      feedbackEl.classList.add("success");
      const serverVersion = (httpRes.data && httpRes.data.version) ? `نسخه ${httpRes.data.version}` : "";
      feedbackEl.innerHTML = `
        <strong>🟢 اتصال با موفقیت برقرار شد!</strong>
        <div class="test-meta">
          <span>⚡ وب‌سوکت: فعال</span>
          <span>⏱️ پینگ: ${wsRes.latency} میلی‌ثانیه</span>
          ${serverVersion ? `<span>🏷️ ${serverVersion}</span>` : ""}
        </div>
        <div class="test-sub">ارتباط دوطرفه با سرور رخش چت برقرار است و آماده تبادل پیام می‌باشد.</div>
      `;
      nativeToast(`✅ اتصال برقرار شد (پینگ: ${wsRes.latency}ms)`);

      // Auto-update state and persist
      state.serverUrl = wsUrl;
      if (serverUrlInput) serverUrlInput.value = wsUrl;
      if (modalServerUrl) modalServerUrl.value = wsUrl;
      persistSettings();

      if (httpRes.data && httpRes.data.tunnel && httpRes.data.tunnel.ws_url) {
        state.activeTunnelUrl = httpRes.data.tunnel.ws_url;
      }
    } else if (httpRes.ok) {
      // Partial Success: HTTP Tunnel works, WS blocked
      feedbackEl.classList.add("warning");
      const serverVersion = (httpRes.data && httpRes.data.version) ? `نسخه ${httpRes.data.version}` : "";
      feedbackEl.innerHTML = `
        <strong>🟡 اتصال از طریق تونل امن HTTP برقرار شد</strong>
        <div class="test-meta">
          <span>🛡️ تونل ضد فایروال HTTP: فعال</span>
          <span>⏱️ پینگ: ${httpRes.latency} میلی‌ثانیه</span>
          ${serverVersion ? `<span>🏷️ ${serverVersion}</span>` : ""}
        </div>
        <div class="test-sub">پورت وب‌سوکت در این شبکه مسدود است، اما تونل امن HTTP فعال است و برنامه پیام‌ها را مبادله می‌کند.</div>
      `;
      nativeToast(`🟡 تونل HTTP متصل شد (پینگ: ${httpRes.latency}ms)`);

      state.serverUrl = wsUrl;
      if (serverUrlInput) serverUrlInput.value = wsUrl;
      if (modalServerUrl) modalServerUrl.value = wsUrl;
      persistSettings();

      if (httpRes.data && httpRes.data.tunnel && httpRes.data.tunnel.ws_url) {
        state.activeTunnelUrl = httpRes.data.tunnel.ws_url;
      }
    } else {
      // Failure
      feedbackEl.classList.add("error");
      const isTryCloudflare = rawUrl.includes("trycloudflare.com");
      feedbackEl.innerHTML = `
        <strong>🔴 خطا در برقراری ارتباط با سرور!</strong>
        <div class="test-sub">هیچ پاسخی از آدرس <code>${escapeHtml(rawUrl)}</code> دریافت نشد.</div>
        <ul class="test-reasons">
          ${isTryCloudflare ? `<li><strong>آدرس کلودفلر منقضی شده:</strong> تونل‌های موقت trycloudflare پس از ریستارت سرور تغییر می‌کنند.</li>` : ""}
          <li><strong>اختلال شبکه یا فیلترینگ:</strong> اگر از دامنه‌های کلودفلر استفاده می‌کنید، نیاز به VPN یا سرور مستقیم است.</li>
          <li><strong>آدرس اشتباه:</strong> از دکمه‌های الگو مانند «⚡ سرور مستقیم (:8765)» استفاده کنید.</li>
        </ul>
        ${isTryCloudflare ? `<div class="test-hint">💡 پیشنهاد: دکمه «⚡ سرور مستقیم» را انتخاب کنید یا از آدرس به‌روزشده کلودفلر استفاده فرمایید.</div>` : ""}
      `;
      nativeToast("❌ عدم برقراری ارتباط با سرور");
    }
  }

  // ==========================================================================
  // Cryptographic Engine (Zero-Knowledge End-to-End Encryption AES-256)
  // ==========================================================================
  function encryptPayload(plaintext, password) {
    if (!window.CryptoJS || !window.CryptoJS.AES) {
      console.warn("CryptoJS library unavailable, sending raw payload.");
      return { ciphertext: plaintext, encrypted: false };
    }
    try {
      const ciphertext = window.CryptoJS.AES.encrypt(plaintext, password).toString();
      return { ciphertext: ciphertext, encrypted: true };
    } catch (err) {
      console.error("Encryption failed:", err);
      return { ciphertext: plaintext, encrypted: false };
    }
  }

  function decryptPayload(ciphertext, password) {
    if (!window.CryptoJS || !window.CryptoJS.AES) {
      return ciphertext;
    }
    try {
      const bytes = window.CryptoJS.AES.decrypt(ciphertext, password);
      const plaintext = bytes.toString(window.CryptoJS.enc.Utf8);
      if (!plaintext) {
        return null; // Invalid password or corrupted payload
      }
      return plaintext;
    } catch (err) {
      return null;
    }
  }

  // ==========================================================================
  // Anti-DPI & Traffic Shaping Engine (Random Noise Padding & Jitter)
  // ==========================================================================
  function generateRandomNoise(minLen = 400, maxLen = 1600) {
    const len = Math.floor(minLen + Math.random() * (maxLen - minLen));
    const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_~";
    let str = "";
    for (let i = 0; i < len; i++) {
      str += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return str;
  }

  function wrapAntiDpi(payload) {
    state.lastActivityTime = Date.now();
    if (state.antiDpi && payload && typeof payload === "object") {
      payload._pad = generateRandomNoise(400, 1600);
      payload._ts = Date.now();
    }
    return payload;
  }

  function unwrapAntiDpi(payload) {
    if (payload && typeof payload === "object") {
      delete payload._pad;
      delete payload._ts;
      delete payload.padding;
    }
    return payload;
  }

  function updateAntiDpiBadge() {
    if (!antiDpiBadge) return;
    if (state.antiDpi) {
      antiDpiBadge.classList.remove("disabled");
      antiDpiBadge.classList.add("active");
      antiDpiBadge.textContent = "🛡️ ضد DPI";
      antiDpiBadge.title = "سپر ضد DPI: پدینگ تصادفی بسته (۴۰۰-۱۶۰۰ بایت) و فرکانس زمانی نامنظم فعال است";
    } else {
      antiDpiBadge.classList.remove("active");
      antiDpiBadge.classList.add("disabled");
      antiDpiBadge.textContent = "🛡️ بدون ضد DPI";
      antiDpiBadge.title = "سپر ضد DPI غیرفعال است";
    }
  }

  function startJitteredPingLoop() {
    if (jitteredPingTimer) clearTimeout(jitteredPingTimer);
    if (!ws || ws.readyState !== WebSocket.OPEN) return;

    // Dynamic Jitter: between 14 and 28 seconds (breaks periodic timing fingerprints)
    const delay = Math.floor(14000 + Math.random() * 14000);
    jitteredPingTimer = setTimeout(() => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(JSON.stringify(wrapAntiDpi({ type: "ping" })));
        } catch (e) {}
      }
      startJitteredPingLoop();
    }, delay);
  }

  function startDecoyChaffLoop() {
    clearInterval(decoyChaffTimer);
    decoyChaffTimer = setInterval(() => {
      if (!state.decoyChaff || !state.isAuthenticated) return;
      const idleSeconds = (Date.now() - state.lastActivityTime) / 1000;
      // If idle for over 35 seconds, send covert decoy traffic
      if (idleSeconds >= 35) {
        state.lastActivityTime = Date.now();
        if (ws && ws.readyState === WebSocket.OPEN) {
          try {
            ws.send(JSON.stringify(wrapAntiDpi({ type: "decoy" })));
          } catch (e) {}
        }
      }
    }, 10000);
  }

  // ==========================================================================
  // Native Android and Background Notification Integration
  // ==========================================================================
  function nativeToast(msg) {
    if (window.ChatNative && window.ChatNative.showToast) {
      window.ChatNative.showToast(msg);
    }
  }

  function nativeVibrate(ms = 40) {
    if (!state.vibrationEnabled) return;
    if (window.ChatNative && window.ChatNative.vibrate) {
      window.ChatNative.vibrate(ms);
    } else if (navigator.vibrate) {
      try {
        navigator.vibrate(ms);
      } catch (e) {}
    }
  }

  function triggerBackgroundNotification(sender, messageText, roomName) {
    unreadCount++;
    document.title = `(${unreadCount}) پیام جدید | رخش چت`;

    if (!state.notificationsEnabled) {
      return;
    }

    // 1. Android Native Foreground Service & Lock Screen Notification
    if (window.ChatNative && window.ChatNative.showNotification) {
      window.ChatNative.showNotification(sender, messageText, roomName || state.room);
      return;
    }

    // 2. Web Notifications API
    if ("Notification" in window && Notification.permission === "granted") {
      try {
        const notif = new Notification(`پیام جدید از ${sender} [${roomName || state.room}]`, {
          body: messageText,
          icon: "icon-192.png",
          badge: "icon-192.png",
          tag: `chat-msg-${roomName}`,
          renotify: true,
          silent: false,
        });
        notif.onclick = () => {
          window.focus();
          notif.close();
        };
      } catch (e) {}
    }

    // 3. Audio Chime & Vibration
    playAudioChime();
    nativeVibrate(60);
  }

  function playAudioChime() {
    try {
      const ctx = new (window.AudioContext || window.webkitAudioContext)();
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();

      osc.type = "sine";
      osc.frequency.setValueAtTime(587.33, ctx.currentTime); // D5
      osc.frequency.exponentialRampToValueAtTime(880, ctx.currentTime + 0.12); // A5

      gain.gain.setValueAtTime(0.001, ctx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.35, ctx.currentTime + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.22);

      osc.connect(gain);
      gain.connect(ctx.destination);

      osc.start();
      osc.stop(ctx.currentTime + 0.23);
    } catch (e) {}
  }

  // Clear unread count & send read receipts when window gains focus or becomes visible
  window.addEventListener("focus", () => {
    unreadCount = 0;
    document.title = originalTitle;
    flushUnseenReceipts();
  });

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) {
      unreadCount = 0;
      document.title = originalTitle;
      flushUnseenReceipts();
    }
  });

  // ==========================================================================
  // UI Display & Helpers
  // ==========================================================================
  function updateStatus(dotClass, text) {
    statusIndicator.className = `status-dot ${dotClass}`;
    statusText.textContent = text;
  }

  function updateTransportBadge(mode) {
    if (!transportBadge) return;
    if (mode === "http") {
      transportBadge.className = "transport-pill http";
      transportBadge.textContent = "🛡️ تونل ضد فایروال (HTTP)";
      transportBadge.title = "داده‌ها از طریق درخواست‌های امن HTTP و بدون قطعی از فایروال عبور می‌کنند";
    } else {
      transportBadge.className = "transport-pill ws";
      transportBadge.textContent = "⚡ وب‌سوکت";
      transportBadge.title = "اتصال برخط و پرسرعت مستقیم وب‌سوکت فعال است";
    }
  }

  function showGateError(msg) {
    gateErrorText.textContent = msg;
    gateError.classList.remove("hidden");
    // Vibration intentionally removed on connection / gate errors per user preference
  }

  function hideGateError() {
    gateError.classList.add("hidden");
  }

  // ==========================================================================
  // Reconnection Controls (One-click cancel / resume retry)
  // ==========================================================================
  function showReconnectBanner(show, text = "", isPaused = false) {
    if (!reconnectBanner) return;
    if (show) {
      reconnectBanner.classList.remove("hidden");
      if (btnCancelReconnectHeader) btnCancelReconnectHeader.classList.remove("hidden");
      if (btnStopGateRetry) btnStopGateRetry.classList.remove("hidden");

      if (reconnectBannerText) reconnectBannerText.textContent = text;
      const spinIcon = reconnectBanner.querySelector(".reconnect-icon");

      if (isPaused) {
        reconnectBanner.classList.add("paused");
        if (spinIcon) spinIcon.classList.remove("spinning");
        if (btnToggleReconnect) {
          btnToggleReconnect.textContent = "▶ تلاش مجدد";
          btnToggleReconnect.className = "btn-banner-action resume";
        }
        if (btnCancelReconnectHeader) {
          btnCancelReconnectHeader.textContent = "▶ اتصال";
          btnCancelReconnectHeader.className = "btn-cancel-reconnect-header resume";
        }
        if (btnStopGateRetry) {
          btnStopGateRetry.textContent = "▶ تلاش مجدد برای اتصال";
          btnStopGateRetry.className = "btn-gate-stop-retry resume";
        }
      } else {
        reconnectBanner.classList.remove("paused");
        if (spinIcon) spinIcon.classList.add("spinning");
        if (btnToggleReconnect) {
          btnToggleReconnect.textContent = "⏹ توقف تلاش";
          btnToggleReconnect.className = "btn-banner-action";
        }
        if (btnCancelReconnectHeader) {
          btnCancelReconnectHeader.textContent = "⏹ توقف تلاش";
          btnCancelReconnectHeader.className = "btn-cancel-reconnect-header";
        }
        if (btnStopGateRetry) {
          btnStopGateRetry.textContent = "⏹ توقف تلاش مجدد";
          btnStopGateRetry.className = "btn-gate-stop-retry";
        }
      }
    } else {
      reconnectBanner.classList.add("hidden");
      if (btnCancelReconnectHeader) btnCancelReconnectHeader.classList.add("hidden");
      if (btnStopGateRetry) btnStopGateRetry.classList.add("hidden");
    }
  }

  function stopReconnect() {
    isReconnectStopped = true;
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
    updateStatus("disconnected", "تلاش مجدد متوقف شد");
    showReconnectBanner(true, "تلاش برای اتصال متوقف شد", true);
  }

  function resumeReconnect() {
    isReconnectStopped = false;
    showReconnectBanner(true, "در حال اتصال به سرور...", false);
    if (state.room && state.password) {
      connectAndJoinRoom(state.room, state.password, state.nickname);
    }
  }

  if (btnToggleReconnect) {
    btnToggleReconnect.addEventListener("click", () => {
      if (isReconnectStopped) resumeReconnect();
      else stopReconnect();
    });
  }

  if (btnCancelReconnectHeader) {
    btnCancelReconnectHeader.addEventListener("click", () => {
      if (isReconnectStopped) resumeReconnect();
      else stopReconnect();
    });
  }

  if (btnStopGateRetry) {
    btnStopGateRetry.addEventListener("click", () => {
      if (isReconnectStopped) resumeReconnect();
      else stopReconnect();
    });
  }

  // ==========================================================================
  // Peer Presence & Live Ping Indicator (Resilient 7s Threshold)
  // ==========================================================================
  const PRESENCE_TIMEOUT_MS = 7000;

  function cssEscape(str) {
    return encodeURIComponent(str).replace(/%/g, "_");
  }

  function isOnlyMemberInRoom() {
    if (!state.isAuthenticated) return false;
    let otherOnlineCount = 0;
    peers.forEach((data, user) => {
      if (user !== state.nickname && data.isOnline) {
        otherOnlineCount++;
      }
    });
    return otherOnlineCount === 0;
  }

  function updateDeleteRoomButtonState() {
    const isOnly = isOnlyMemberInRoom();
    const title = isOnly
      ? "پاک کردن کامل اتاق (شما تنها عضو حاضر هستید)"
      : "امکان حذف اتاق وجود ندارد (کاربران دیگری در اتاق حضور دارند)";

    [btnDeleteRoom, btnDeleteRoomModal].forEach((btn) => {
      if (!btn) return;
      btn.disabled = !isOnly;
      if (isOnly) {
        btn.classList.remove("disabled");
        btn.title = title;
      } else {
        btn.classList.add("disabled");
        btn.title = title;
      }
    });
  }

  function renderRoomMembers() {
    if (!membersList) return;
    membersList.innerHTML = "";

    // 1. Current user chip (always online when authenticated)
    const myChip = document.createElement("span");
    myChip.className = "member-chip me";
    myChip.innerHTML = `<span class="peer-status-dot online"></span> <span>${escapeHtml(state.nickname)} (شما)</span>`;
    membersList.appendChild(myChip);

    // 2. Peer chips with colored status light
    peers.forEach((data, user) => {
      if (user === state.nickname) return;
      const chip = document.createElement("span");
      chip.className = "member-chip";
      chip.id = `chip-${cssEscape(user)}`;
      const dotClass = data.isOnline ? "online" : "offline";
      const title = data.isOnline ? "آنلاین (متصل و فعال)" : "قطع ارتباط (عدم دریافت پکت)";
      chip.title = `${user}: ${title}`;
      chip.innerHTML = `<span class="peer-status-dot ${dotClass}" title="${title}"></span> <span>${escapeHtml(user)}</span>`;
      membersList.appendChild(chip);
    });

    updateDeleteRoomButtonState();
  }

  function updatePeerStatusIndicators(user, isOnline) {
    const dotClass = isOnline ? "online" : "offline";
    const title = isOnline ? "آنلاین (متصل و فعال)" : "قطع ارتباط (عدم دریافت پکت)";

    // Update chip in top members bar
    const chip = document.getElementById(`chip-${cssEscape(user)}`);
    if (chip) {
      chip.title = `${user}: ${title}`;
      const dot = chip.querySelector(".peer-status-dot");
      if (dot) {
        dot.className = `peer-status-dot ${dotClass}`;
        dot.title = title;
      }
    }

    // Update status dot beside sender nickname in chat bubbles
    const dots = document.querySelectorAll(`.peer-status-dot[data-peer="${user}"]`);
    dots.forEach((dot) => {
      dot.className = `peer-status-dot ${dotClass}`;
      dot.title = title;
    });

    updateDeleteRoomButtonState();
  }

  function initPeerPresence() {
    if (peerPingInterval) clearInterval(peerPingInterval);
    if (peerFreshnessChecker) clearInterval(peerFreshnessChecker);

    // 1. Ping Sender: Send heartbeat ping every 1500ms
    peerPingInterval = setInterval(() => {
      if (!state.isAuthenticated) return;
      if (ws && ws.readyState === WebSocket.OPEN) {
        try {
          ws.send(JSON.stringify(wrapAntiDpi({
            type: "peer_ping",
            room: state.room,
            user: state.nickname,
          })));
        } catch (e) {}
      } else if (state.transportMode === "http") {
        sendHttpPeerPing();
      }
    }, 1500);

    // 2. Freshness Checker: every 500ms, if now - lastPing > PRESENCE_TIMEOUT_MS -> offline (RED LIGHT)!
    peerFreshnessChecker = setInterval(() => {
      if (!state.isAuthenticated) return;
      const now = Date.now();
      peers.forEach((data, user) => {
        if (user === state.nickname) return;
        const diff = now - (data.lastPing || 0);
        const isOnline = diff <= PRESENCE_TIMEOUT_MS;
        if (data.isOnline !== isOnline) {
          data.isOnline = isOnline;
          updatePeerStatusIndicators(user, isOnline);
        }
      });
    }, 500);
  }

  async function sendHttpPeerPing() {
    try {
      const httpBase = getHttpBaseUrl(state.serverUrl);
      await fetch(`${httpBase}/api/peer_ping`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(wrapAntiDpi({
          room: state.room,
          password: state.password,
          sender: state.nickname,
        })),
      });
    } catch (e) {}
  }

  // ==========================================================================
  // Message Status Receipts (✓ Sent -> ✓✓ Delivered -> ◯ Seen Circle)
  // ==========================================================================
  function isChatVisible() {
    if (document.hidden) return false;
    if (!document.hasFocus()) return false;
    if (window.ChatNative && window.ChatNative.isAppForeground && !window.ChatNative.isAppForeground()) {
      return false;
    }
    return !chatView.classList.contains("hidden");
  }

  function renderStatusIcon(status = "sent") {
    if (status === "pending") {
      return '<span class="msg-status pending" title="در حال ارسال / صف تحویل...">⏳</span>';
    }
    if (status === "delivered") {
      return '<span class="msg-status delivered" title="تحویل داده شد (رسید به دستش)">✓✓</span>';
    }
    if (status === "seen") {
      return '<span class="msg-status seen" title="مشاهده شد (صفحه چت دیده شد)"><svg class="status-circle-svg" viewBox="0 0 14 14"><circle cx="7" cy="7" r="5"></circle></svg></span>';
    }
    return '<span class="msg-status sent" title="ارسال شد به سرور">✓</span>';
  }

  function updateMessageStatus(msgId, status) {
    const el = document.getElementById(`msg-${msgId}`);
    if (!el) return;
    const statusElem = el.querySelector(".msg-status");
    if (!statusElem) return;

    if (status === "pending") {
      statusElem.className = "msg-status pending";
      statusElem.textContent = "⏳";
      statusElem.title = "در حال ارسال / صف تحویل...";
    } else if (status === "sent") {
      if (statusElem.classList.contains("delivered") || statusElem.classList.contains("seen")) return;
      statusElem.className = "msg-status sent";
      statusElem.textContent = "✓";
      statusElem.title = "ارسال شد به سرور";
    } else if (status === "delivered") {
      if (statusElem.classList.contains("seen")) return;
      statusElem.className = "msg-status delivered";
      statusElem.textContent = "✓✓";
      statusElem.title = "تحویل داده شد (رسید به دستش)";
    } else if (status === "seen") {
      statusElem.className = "msg-status seen";
      statusElem.innerHTML = '<svg class="status-circle-svg" viewBox="0 0 14 14"><circle cx="7" cy="7" r="5"></circle></svg>';
      statusElem.title = "مشاهده شد (صفحه چت دیده شد)";
    }
  }

  function sendDeliveryReceipt(msgId) {
    if (!msgId || !state.room) return;
    if (ws && ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(JSON.stringify(wrapAntiDpi({
          type: "msg_delivered",
          msgId: msgId,
          room: state.room,
        })));
      } catch (e) {}
    } else if (state.transportMode === "http") {
      sendHttpReceipt("delivered", [msgId]);
    }
  }

  function sendSeenReceipt(msgIdOrIds) {
    if (!state.room) return;
    const ids = Array.isArray(msgIdOrIds) ? msgIdOrIds : [msgIdOrIds];
    if (ids.length === 0) return;

    if (ws && ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(JSON.stringify(wrapAntiDpi({
          type: "msg_seen",
          msgIds: ids,
          room: state.room,
        })));
      } catch (e) {}
    } else if (state.transportMode === "http") {
      sendHttpReceipt("seen", ids);
    }
  }

  async function sendHttpReceipt(receiptType, msgIds) {
    try {
      const httpBase = getHttpBaseUrl(state.serverUrl);
      await fetch(`${httpBase}/api/receipt`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(wrapAntiDpi({
          room: state.room,
          password: state.password,
          sender: state.nickname,
          type: receiptType,
          msgIds: msgIds,
        })),
      });
    } catch (e) {}
  }

  function flushUnseenReceipts() {
    if (!state.isAuthenticated || unseenMessageIds.size === 0) return;
    if (!isChatVisible()) return;

    const idsToSend = Array.from(unseenMessageIds);
    unseenMessageIds.clear();
    sendSeenReceipt(idsToSend);
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

  function appendMessage({ type = "peer", sender = "", text = "", time = "", id = "", isEncrypted = true, isPending = false, status = "sent" }) {
    // If element with this id already exists in DOM, update status if needed
    if (id) {
      const existing = document.getElementById(`msg-${id}`);
      if (existing) {
        if (!isPending) {
          updateMessageStatus(id, status);
        }
        return;
      }
    }

    const wrapper = document.createElement("div");
    wrapper.className = `msg-wrapper ${type}`;
    if (id) wrapper.id = `msg-${id}`;

    if (type === "system") {
      wrapper.innerHTML = `
        <div class="msg-bubble">
          <span>${escapeHtml(text)}</span>
        </div>
      `;
    } else {
      const isMe = type === "me";
      const timeStr = time || formatTime();
      const lockIcon = isEncrypted ? '<span class="msg-lock" title="رمزنگاری سرتاسری AES-256">🔒</span>' : "";
      const initialStatus = isPending ? "pending" : (status || "sent");
      const statusIcon = isMe ? renderStatusIcon(initialStatus) : "";

      // Peer dot beside sender ID
      let peerDotHtml = "";
      if (!isMe && sender) {
        const peerData = peers.get(sender);
        const isOnline = peerData ? peerData.isOnline : false;
        const dotClass = isOnline ? "online" : "offline";
        const dotTitle = isOnline ? "آنلاین (پینگ فعال زیر ۲ ثانیه)" : "قطع ارتباط (بیش از ۲ ثانیه بدون پینگ)";
        peerDotHtml = `<span class="peer-status-dot ${dotClass}" data-peer="${escapeHtml(sender)}" title="${dotTitle}"></span>`;
      }

      wrapper.innerHTML = `
        <div class="msg-bubble">
          ${!isMe && sender ? `<div class="msg-sender">${peerDotHtml} ${escapeHtml(sender)}</div>` : ""}
          <div class="msg-text">${escapeHtml(text)}</div>
          <div class="msg-meta">
            ${lockIcon}
            <span class="msg-time">${timeStr}</span>
            ${statusIcon}
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

  // Mark message as confirmed/sent in UI
  function markMessageDelivered(msgId) {
    updateMessageStatus(msgId, "sent");
  }

  // 3. Room Switching & View Management
  function enterChatView(roomName) {
    state.isAuthenticated = true;
    hideGateError();
    roomGate.classList.add("hidden");
    chatView.classList.remove("hidden");
    btnLeaveRoom.classList.remove("hidden");
    if (btnDeleteRoom) btnDeleteRoom.classList.remove("hidden");
    if (btnDeleteRoomModal) btnDeleteRoomModal.classList.remove("hidden");
    btnClear.classList.remove("hidden");
    roomStatusBadge.classList.remove("hidden");
    currentRoomDisplay.textContent = roomName;
    updateDeleteRoomButtonState();
    messageInput.focus();

    // Check browser notification permission
    if (state.notificationsEnabled && "Notification" in window && Notification.permission === "default") {
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
    if (btnDeleteRoom) btnDeleteRoom.classList.add("hidden");
    if (btnDeleteRoomModal) btnDeleteRoomModal.classList.add("hidden");
    btnClear.classList.add("hidden");
    roomStatusBadge.classList.add("hidden");
    updateStatus("disconnected", "اتاقی متصل نیست");
  }

  // ==========================================================================
  // Guaranteed Delivery Outgoing Queue
  // ==========================================================================
  function enqueueOutgoingMessage(msgRecord) {
    state.outgoingQueue.push(msgRecord);
    flushOutgoingQueue();
  }

  async function flushOutgoingQueue() {
    if (!state.outgoingQueue.length || !state.isAuthenticated) return;

    const pending = [...state.outgoingQueue];
    for (const item of pending) {
      let sentSuccess = false;

      // Mode 1: WebSocket Send with Anti-DPI Traffic Shaping
      if (state.transportMode === "ws" && ws && ws.readyState === WebSocket.OPEN) {
        try {
          const packet = wrapAntiDpi({
            type: "chat",
            msgId: item.msgId,
            room: state.room,
            sender: state.nickname,
            ciphertext: item.ciphertext,
            encrypted: item.encrypted,
            time: item.time,
          });
          ws.send(JSON.stringify(packet));
          sentSuccess = true;
          markMessageDelivered(item.msgId);
        } catch (e) {
          sentSuccess = false;
        }
      }

      // Mode 2: HTTP Safe Tunnel Send (Fallback if WS fails or in HTTP mode)
      if (!sentSuccess) {
        try {
          const httpUrl = getHttpBaseUrl(state.serverUrl) + "/api/send";
          const res = await fetch(httpUrl, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify(wrapAntiDpi({
              room: state.room,
              password: state.password,
              sender: state.nickname,
              ciphertext: item.ciphertext,
              encrypted: item.encrypted,
              msgId: item.msgId,
              time: item.time,
            })),
          });
          if (res.ok) {
            const data = await res.json();
            if (data.status === "ok") {
              sentSuccess = true;
              markMessageDelivered(item.msgId);
            }
          }
        } catch (err) {
          sentSuccess = false;
        }
      }

      if (sentSuccess) {
        state.outgoingQueue = state.outgoingQueue.filter((m) => m.msgId !== item.msgId);
      }
    }
  }

  // Periodic Queue Flusher
  clearInterval(queueRetryTimer);
  queueRetryTimer = setInterval(() => {
    if (state.outgoingQueue.length > 0 && state.isAuthenticated) {
      flushOutgoingQueue();
    }
  }, 2500);

  // ==========================================================================
  // Dual-Transport Protocol: WebSocket Primary + HTTP Safe Tunnel Fallback
  // ==========================================================================
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
    clearTimeout(wsHandshakeTimer);
    if (jitteredPingTimer) clearTimeout(jitteredPingTimer);
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    clearInterval(decoyChaffTimer);
    clearInterval(httpPollTimer);
    clearInterval(wsProbeTimer);

    isManualDisconnect = false;
    isConnecting = true;
    state.transportMode = "ws";
    updateTransportBadge("ws");
    updateStatus("connecting", "در حال بررسی دسترسی...");

    if (ws) {
      try {
        ws.close();
      } catch (e) {}
      ws = null;
    }

    // Set a 2.5-second timeout: If WebSocket fails to establish handshake,
    // immediately failover to HTTP Safe Tunnel!
    wsHandshakeTimer = setTimeout(() => {
      if (isConnecting && (!ws || ws.readyState !== WebSocket.OPEN)) {
        console.warn("WebSocket connection timed out behind strict firewall. Failing over to HTTP Safe Tunnel...");
        try {
          if (ws) ws.close();
        } catch (e) {}
        ws = null;
        activateHttpTunnelFallback();
      }
    }, 2500);

    try {
      ws = new WebSocket(state.serverUrl);
    } catch (err) {
      clearTimeout(wsHandshakeTimer);
      activateHttpTunnelFallback();
      return;
    }

    ws.onopen = () => {
      clearTimeout(wsHandshakeTimer);
      updateStatus("connecting", "در حال تایید کلید امنیتی...");

      // Send join room authentication payload with Anti-DPI Traffic Shaping
      const joinPayload = wrapAntiDpi({
        type: "join",
        room: state.room,
        password: state.password,
        sender: state.nickname,
        clientId: clientId,
        time: formatTime(),
      });
      try {
        ws.send(JSON.stringify(joinPayload));
      } catch (e) {}

      // Start Anti-DPI Jittered Ping and Decoy Cover Traffic Loops
      startJitteredPingLoop();
      startDecoyChaffLoop();
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
      unwrapAntiDpi(parsed);

      // Silently drop Anti-DPI decoy chaff / cover traffic
      if (parsed.type === "decoy" || parsed.decoy) {
        return;
      }

      // Ignore Pong
      if (parsed.type === "pong") {
        return;
      }

      // Authentication Success
      if (parsed.type === "auth_success") {
        isConnecting = false;
        state.transportMode = "ws";
        showReconnectBanner(false);
        isReconnectStopped = false;
        updateTransportBadge("ws");
        updateAntiDpiBadge();
        updateStatus("connected", "متصل (وب‌سوکت)");
        nativeToast(`وارد اتاق امن «${parsed.room || state.room}» شدید`);
        enterChatView(parsed.room || state.room);

        // Load initial room members & ping presence
        peers.clear();
        if (Array.isArray(parsed.members)) {
          for (const m of parsed.members) {
            if (m.user && m.user !== state.nickname) {
              const lp = m.last_ping ? Date.now() - Math.max(0, (Date.now() - m.last_ping * 1000)) : Date.now();
              peers.set(m.user, { lastPing: lp, isOnline: m.online !== false });
            }
          }
        }
        renderRoomMembers();
        initPeerPresence();

        appendMessage({
          type: "system",
          text: `به اتاق امن و اختصاصی «${parsed.room || state.room}» متصل شدید. تمامی پیام‌ها با رمزنگاری سرتاسری AES-256 و پدینگ تصادفی ضد DPI محافظت می‌شوند.`,
          isEncrypted: false,
        });
        flushOutgoingQueue();
        return;
      }

      // Authentication Error (Wrong Password, Duplicate Nickname, or Access Denied)
      if (parsed.type === "auth_error") {
        isConnecting = false;
        showReconnectBanner(false);
        isReconnectStopped = true;
        clearTimeout(reconnectTimer);
        const errText = parsed.text || "رمز عبور اتاق نادرست است! دسترسی غیرمجاز.";
        const isDuplicateName = errText.includes("نام") || errText.includes("حضور دارد");
        updateStatus("disconnected", isDuplicateName ? "نام تکراری" : "رمز نادرست");
        showGateError(errText);
        returnToRoomGate();
        if (isDuplicateName) {
          gateNickname.focus();
          gateNickname.select();
        }
        try {
          ws.close();
        } catch (e) {}
        ws = null;
        return;
      }

      // Peer Ping Heartbeat (Live peer status light)
      if (parsed.type === "peer_ping") {
        if (parsed.user && parsed.user !== state.nickname) {
          peers.set(parsed.user, { lastPing: Date.now(), isOnline: true });
          renderRoomMembers();
          updatePeerStatusIndicators(parsed.user, true);
        }
        return;
      }

      // Peer Join
      if (parsed.type === "peer_join") {
        if (parsed.user && parsed.user !== state.nickname) {
          peers.set(parsed.user, { lastPing: Date.now(), isOnline: true });
          renderRoomMembers();
          updatePeerStatusIndicators(parsed.user, true);
        }
        if (parsed.text) {
          appendMessage({ type: "system", text: parsed.text, isEncrypted: false });
        }
        return;
      }

      // Peer Offline (Turns peer light RED immediately)
      if (parsed.type === "peer_offline") {
        if (parsed.user) {
          if (peers.has(parsed.user)) {
            peers.get(parsed.user).lastPing = 0;
            peers.get(parsed.user).isOnline = false;
          }
          renderRoomMembers();
          updatePeerStatusIndicators(parsed.user, false);
        }
        if (parsed.text) {
          appendMessage({ type: "system", text: parsed.text, isEncrypted: false });
        }
        return;
      }

      // Message Status Receipts (✓ Sent -> ✓✓ Delivered -> ◯ Seen Circle)
      if (parsed.type === "msg_status" && parsed.msgId && parsed.status) {
        updateMessageStatus(parsed.msgId, parsed.status);
        return;
      }

      // ACK for sent message
      if (parsed.type === "ack" && parsed.msgId) {
        markMessageDelivered(parsed.msgId);
        state.outgoingQueue = state.outgoingQueue.filter((m) => m.msgId !== parsed.msgId);
        return;
      }

      // History Sync
      if (parsed.type === "history_sync" && Array.isArray(parsed.messages)) {
        for (const msg of parsed.messages) {
          processIncomingChatMessage(msg);
        }
        return;
      }

      // System Messages within the room
      if (parsed.type === "system") {
        appendMessage({
          type: "system",
          text: parsed.text || parsed.message,
          isEncrypted: false,
        });
        return;
      }

      // Room Deleted Confirmation
      if (parsed.type === "room_deleted") {
        nativeToast(parsed.text || "اتاق با موفقیت پاکسازی شد.");
        leaveRoom();
        gateRoomPassword.value = "";
        gateRoomPassword.focus();
        return;
      }

      // Incoming Chat Messages
      if (parsed.type === "chat") {
        processIncomingChatMessage(parsed);
      }
    };

    ws.onerror = () => {
      // If error occurs during initial handshake, failover immediately to HTTP Safe Tunnel
      if (isConnecting) {
        clearTimeout(wsHandshakeTimer);
        activateHttpTunnelFallback();
      }
    };

    ws.onclose = () => {
      if (jitteredPingTimer) clearTimeout(jitteredPingTimer);
      clearInterval(decoyChaffTimer);

      if (isConnecting && !state.isAuthenticated) {
        clearTimeout(wsHandshakeTimer);
        activateHttpTunnelFallback();
      } else if (state.isAuthenticated) {
        // If disconnected after being authenticated, try HTTP fallback immediately
        console.warn("WebSocket disconnected by firewall or network drop. Falling back to HTTP Safe Tunnel...");
        activateHttpTunnelFallback();
      } else if (!isConnecting) {
        updateStatus("disconnected", "قطع");
      }
    };
  }

  // ==========================================================================
  // HTTP Safe Tunnel Fallback (Bypasses Restrictive Mobile Firewalls)
  // ==========================================================================
  async function activateHttpTunnelFallback() {
    isConnecting = false;
    clearTimeout(wsHandshakeTimer);
    if (jitteredPingTimer) clearTimeout(jitteredPingTimer);
    clearInterval(decoyChaffTimer);
    state.transportMode = "http";
    updateTransportBadge("http");
    updateAntiDpiBadge();

    if (!state.room || !state.password) return;

    updateStatus("connecting", "فعال‌سازی تونل HTTP...");
    const httpBase = getHttpBaseUrl(state.serverUrl);

    try {
      // 1. Authenticate via POST /api/join with Anti-DPI Traffic Shaping
      const joinRes = await fetch(`${httpBase}/api/join`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(wrapAntiDpi({
          room: state.room,
          password: state.password,
          sender: state.nickname,
          clientId: clientId,
        })),
      });

      if (!joinRes.ok) {
        const errData = await joinRes.json().catch(() => ({}));
        isReconnectStopped = true;
        clearTimeout(reconnectTimer);
        const errText = errData.text || "رمز عبور اتاق نادرست است یا سرور در دسترس نیست.";
        const isDuplicateName = errText.includes("نام") || errText.includes("حضور دارد");
        updateStatus("disconnected", isDuplicateName ? "نام تکراری" : "خطای تایید");
        showGateError(errText);
        returnToRoomGate();
        if (isDuplicateName) {
          gateNickname.focus();
          gateNickname.select();
        }
        return;
      }

      const joinData = await joinRes.json();
      updateStatus("connected", "متصل (تونل امن HTTP)");
      showReconnectBanner(false);
      isReconnectStopped = false;
      enterChatView(state.room);
      initPeerPresence();

      // Load initial room members & ping presence from HTTP response
      peers.clear();
      if (Array.isArray(joinData.members)) {
        for (const m of joinData.members) {
          if (m.user && m.user !== state.nickname) {
            const lp = m.last_ping ? Date.now() - Math.max(0, (Date.now() - m.last_ping * 1000)) : Date.now();
            peers.set(m.user, { lastPing: lp, isOnline: m.online !== false });
          }
        }
      }
      renderRoomMembers();
      updateDeleteRoomButtonState();

      if (!state.seenMessageIds.has("sys_http_welcome")) {
        state.seenMessageIds.add("sys_http_welcome");
        appendMessage({
          type: "system",
          text: `ارتباط با پروتکل ضد فایروال (HTTP Safe Tunnel) برقرار شد. تحویل پیام‌ها به صورت تضمینی و رمزنگاری‌شده انجام می‌شود.`,
          isEncrypted: false,
        });
      }

      // Flush any queued messages
      flushOutgoingQueue();

      // Start HTTP Polling Loop
      startHttpPolling();

      // Start quiet probe to see if WebSocket is restored
      startQuietWsProbe();
    } catch (err) {
      updateStatus("disconnected", "خطای اتصال");
      showGateError("عدم دسترسی به سرور. فایروال تمامی ارتباطات را مسدود کرده است.");
      if (state.autoReconnect && !isManualDisconnect && !isReconnectStopped) {
        scheduleReconnect();
      }
    }
  }

  function startHttpPolling() {
    clearInterval(httpPollTimer);
    const pollFn = async () => {
      if (!state.isAuthenticated || state.transportMode !== "http") return;
      try {
        const httpBase = getHttpBaseUrl(state.serverUrl);
        const url = `${httpBase}/api/poll?room=${encodeURIComponent(state.room)}&password=${encodeURIComponent(state.password)}&since=${state.lastSyncTimestamp}`;
        const res = await fetch(url, { method: "GET" });
        if (res.ok) {
          const data = await res.json();
          if (data.status === "ok") {
            if (Array.isArray(data.messages)) {
              for (const msg of data.messages) {
                if (msg.type === "peer_join") {
                  if (msg.user && msg.user !== state.nickname) {
                    peers.set(msg.user, { lastPing: Date.now(), isOnline: true });
                    renderRoomMembers();
                    updatePeerStatusIndicators(msg.user, true);
                    updateDeleteRoomButtonState();
                  }
                  if (msg.text && !state.seenMessageIds.has(msg.id)) {
                    state.seenMessageIds.add(msg.id);
                    appendMessage({ type: "system", text: msg.text, isEncrypted: false });
                  }
                } else if (msg.type === "peer_offline") {
                  if (msg.user && peers.has(msg.user)) {
                    peers.get(msg.user).isOnline = false;
                    renderRoomMembers();
                    updatePeerStatusIndicators(msg.user, false);
                    updateDeleteRoomButtonState();
                  }
                  if (msg.text && !state.seenMessageIds.has(msg.id)) {
                    state.seenMessageIds.add(msg.id);
                    appendMessage({ type: "system", text: msg.text, isEncrypted: false });
                  }
                } else {
                  processIncomingChatMessage(msg);
                }
              }
            }
            if (Array.isArray(data.receipts)) {
              for (const r of data.receipts) {
                if (r.msgId && r.status) {
                  updateMessageStatus(r.msgId, r.status);
                }
              }
            }
            if (Array.isArray(data.members)) {
              for (const m of data.members) {
                if (m.user && m.user !== state.nickname) {
                  const lp = m.last_ping ? Date.now() - Math.max(0, (Date.now() - m.last_ping * 1000)) : Date.now();
                  peers.set(m.user, { lastPing: lp, isOnline: m.online !== false });
                }
              }
              renderRoomMembers();
              updateDeleteRoomButtonState();
            }
            if (data.server_time && data.server_time > state.lastSyncTimestamp) {
              state.lastSyncTimestamp = data.server_time;
            }
          }
        }
      } catch (e) {}
    };

    // Poll every 2.5 seconds (or 10 seconds if page is in background)
    httpPollTimer = setInterval(pollFn, document.hidden ? 10000 : 2500);
  }

  // Quietly probe if WebSocket is reachable again; if so, upgrade transport seamlessly
  function startQuietWsProbe() {
    clearInterval(wsProbeTimer);
    wsProbeTimer = setInterval(() => {
      if (!state.isAuthenticated || state.transportMode !== "http") return;
      try {
        const probeWs = new WebSocket(state.serverUrl);
        probeWs.onopen = () => {
          probeWs.close();
          console.log("WebSocket is available again! Re-upgrading transport...");
          connectAndJoinRoom(state.room, state.password, state.nickname);
        };
        probeWs.onerror = () => {
          try { probeWs.close(); } catch (e) {}
        };
      } catch (e) {}
    }, 60000);
  }

  // ==========================================================================
  // Process and Decrypt Incoming Message
  // ==========================================================================
  function processIncomingChatMessage(msg) {
    const msgId = msg.id || `${msg.sender}_${msg.time}_${msg.ciphertext ? msg.ciphertext.slice(0, 10) : ""}`;
    if (state.seenMessageIds.has(msgId)) {
      if (msg.sender === state.nickname && msg.status) {
        updateMessageStatus(msgId, msg.status);
      }
      return;
    }
    state.seenMessageIds.add(msgId);

    if (msg.ts && msg.ts > state.lastSyncTimestamp) {
      state.lastSyncTimestamp = msg.ts;
    }

    const isMe = msg.sender === state.nickname;

    // Immediate peer presence detection: any message proves peer is alive and ONLINE right now!
    if (!isMe && msg.sender) {
      const now = Date.now();
      const existing = peers.get(msg.sender);
      if (!existing) {
        peers.set(msg.sender, { lastPing: now, isOnline: true });
        renderRoomMembers();
      } else {
        existing.lastPing = now;
        existing.isOnline = true;
      }
      updatePeerStatusIndicators(msg.sender, true);
      updateDeleteRoomButtonState();
    }

    // Decrypt if encrypted
    let displayText = msg.ciphertext || msg.text || "";
    let isEncrypted = false;

    if (msg.encrypted || (msg.ciphertext && msg.ciphertext.startsWith("U2FsdGVkX1"))) {
      isEncrypted = true;
      const decrypted = decryptPayload(msg.ciphertext, state.password);
      if (decrypted !== null) {
        displayText = decrypted;
      } else {
        displayText = "⚠️ [خطای کلید]: این پیام با رمز دیگری کدگذاری شده و قابل رمزگشایی نیست.";
      }
    }

    // Append to UI
    appendMessage({
      id: msgId,
      type: isMe ? "me" : "peer",
      sender: msg.sender,
      text: displayText,
      time: msg.time || formatTime(),
      isEncrypted: isEncrypted,
      isPending: false,
      status: msg.status || "sent",
    });

    // If incoming from another user:
    if (!isMe) {
      // 1. Immediately send delivery receipt (2 ticks: ✓✓)
      sendDeliveryReceipt(msgId);

      // 2. Check if chat screen is currently visible to user
      if (isChatVisible()) {
        sendSeenReceipt(msgId);
      } else {
        unseenMessageIds.add(msgId);
      }

      const isAppHidden =
        document.hidden ||
        !document.hasFocus() ||
        (window.ChatNative && window.ChatNative.isAppForeground && !window.ChatNative.isAppForeground());

      if (isAppHidden) {
        triggerBackgroundNotification(msg.sender, displayText, state.room);
      } else {
        playAudioChime();
        nativeVibrate(30);
      }
    }
  }

  function scheduleReconnect() {
    if (isReconnectStopped || !state.autoReconnect || isManualDisconnect) return;
    clearTimeout(reconnectTimer);
    updateStatus("connecting", "تلاش مجدد تا ۴ ثانیه...");
    showReconnectBanner(true, "در حال تلاش برای اتصال مجدد تا ۴ ثانیه...", false);
    reconnectTimer = setTimeout(() => {
      if (state.room && state.password && !isReconnectStopped && !isManualDisconnect) {
        connectAndJoinRoom(state.room, state.password, state.nickname);
      }
    }, 4000);
  }

  function leaveRoom() {
    isManualDisconnect = true;
    showReconnectBanner(false);
    isReconnectStopped = false;
    clearTimeout(reconnectTimer);
    clearTimeout(wsHandshakeTimer);
    if (jitteredPingTimer) clearTimeout(jitteredPingTimer);
    if (heartbeatTimer) clearInterval(heartbeatTimer);
    if (peerPingInterval) clearInterval(peerPingInterval);
    if (peerFreshnessChecker) clearInterval(peerFreshnessChecker);
    peers.clear();
    renderRoomMembers();
    clearInterval(decoyChaffTimer);
    clearInterval(httpPollTimer);
    clearInterval(wsProbeTimer);

    if (ws && ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(JSON.stringify({ type: "leave" }));
        ws.close();
      } catch (e) {}
    } else if (state.transportMode === "http" && state.room) {
      try {
        const httpBase = getHttpBaseUrl(state.serverUrl);
        fetch(`${httpBase}/api/leave`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(wrapAntiDpi({
            room: state.room,
            sender: state.nickname,
            clientId: clientId,
          })),
        }).catch(() => {});
      } catch (e) {}
    }
    ws = null;
    returnToRoomGate();
    nativeToast("از اتاق خارج شدید");
  }

  // ==========================================================================
  // Form Events & Interactivity
  // ==========================================================================
  gateForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const room = gateRoomName.value.trim();
    const password = gateRoomPassword.value.trim();
    const nickname = gateNickname.value.trim();

    if (!room || !password) {
      showGateError("لطفاً هم نام اتاق و هم رمز عبور سخت را وارد کنید.");
      return;
    }
    isReconnectStopped = false;
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

  // Chat Send Form (Encrypts then enqueues for guaranteed delivery)
  chatForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = messageInput.value.trim();
    if (!text) return;

    if (!state.isAuthenticated) {
      nativeToast("ابتدا وارد اتاق شوید");
      return;
    }

    const msgId = "m_" + Date.now() + "_" + Math.random().toString(36).substr(2, 6);
    const timeStr = formatTime();

    // 1. Zero-Knowledge E2EE Encryption
    const { ciphertext, encrypted } = encryptPayload(text, state.password);

    // 2. Immediate Local UI Rendering with pending status
    state.seenMessageIds.add(msgId);
    appendMessage({
      id: msgId,
      type: "me",
      sender: state.nickname,
      text: text,
      time: timeStr,
      isEncrypted: encrypted,
      isPending: true,
    });

    messageInput.value = "";
    nativeVibrate(20);

    // 3. Queue for Guaranteed Delivery
    enqueueOutgoingMessage({
      msgId: msgId,
      room: state.room,
      sender: state.nickname,
      ciphertext: ciphertext,
      encrypted: encrypted,
      time: timeStr,
    });
  });

  // Leave room button
  btnLeaveRoom.addEventListener("click", leaveRoom);
  btnDisconnectModal.addEventListener("click", () => {
    closeSettings();
    leaveRoom();
  });

  // Delete room button (enabled only when sole member)
  async function deleteRoom() {
    if (!state.isAuthenticated || !state.room) return;
    if (!isOnlyMemberInRoom()) {
      nativeToast("امکان پاک کردن اتاق وجود ندارد؛ کاربران دیگری در اتاق حضور دارند.");
      return;
    }

    const ok = confirm(
      "آیا مطمئن هستید که می‌خواهید این اتاق را به طور کامل پاک کنید؟\n\n" +
      "با این کار، اتاق از حافظه سرور حذف شده و هر فرد جدیدی می‌تواند اتاق را با رمز عبور جدید بسازد."
    );
    if (!ok) return;

    const roomToDelete = state.room;
    const pw = state.password;

    if (ws && ws.readyState === WebSocket.OPEN) {
      try {
        ws.send(JSON.stringify(wrapAntiDpi({
          type: "delete_room",
          room: roomToDelete,
          password: pw,
          sender: state.nickname,
        })));
      } catch (e) {}
    } else {
      try {
        const httpBase = getHttpBaseUrl(state.serverUrl);
        const res = await fetch(`${httpBase}/api/delete_room`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(wrapAntiDpi({
            room: roomToDelete,
            password: pw,
            sender: state.nickname,
          })),
        });
        if (!res.ok) {
          const errData = await res.json().catch(() => ({}));
          nativeToast(errData.text || "خطا در پاک کردن اتاق");
          return;
        }
      } catch (e) {
        nativeToast("خطا در ارسال درخواست پاک کردن اتاق");
        return;
      }
    }

    leaveRoom();
    gateRoomPassword.value = "";
    gateRoomName.value = roomToDelete;
    gateRoomPassword.focus();
    nativeToast(`اتاق «${roomToDelete}» به طور کامل پاک شد. اکنون می‌توانید آن را با رمز جدید بسازید.`);
  }

  if (btnDeleteRoom) {
    btnDeleteRoom.addEventListener("click", deleteRoom);
  }
  if (btnDeleteRoomModal) {
    btnDeleteRoomModal.addEventListener("click", () => {
      closeSettings();
      deleteRoom();
    });
  }

  // Clear messages button
  btnClear.addEventListener("click", () => {
    chatMessages.innerHTML = "";
    state.seenMessageIds.clear();
    appendMessage({
      type: "system",
      text: "صفحه چت پاکسازی شد.",
      isEncrypted: false,
    });
  });

  // Notification Permission Request
  function requestNotificationAccess() {
    if ("Notification" in window) {
      Notification.requestPermission().then((permission) => {
        if (permission === "granted") {
          notifBanner.classList.add("hidden");
          state.notificationsEnabled = true;
          updateNotificationUI();
          persistSettings();
          nativeToast("اعلان‌های صفحه قفل فعال شد 🔔");
          triggerBackgroundNotification("رخش چت", "اعلان‌ها فعال شدند و آماده دریافت پیام روی صفحه قفل هستند.", state.room || "سیستم");
        } else {
          nativeToast("مجوز اعلان صادر نشد");
        }
      });
    } else {
      nativeToast("این مرورگر از اعلان پشتیبانی نمی‌کند");
    }
  }

  btnEnableNotif.addEventListener("click", requestNotificationAccess);
  btnNotification.addEventListener("click", toggleNotifications);

  if (notificationToggle) {
    notificationToggle.addEventListener("change", () => {
      state.notificationsEnabled = notificationToggle.checked;
      updateNotificationUI();
      persistSettings();
      nativeToast(state.notificationsEnabled ? "اعلان‌ها روشن شد 🔔" : "اعلان‌ها خاموش شد 🔕");
    });
  }

  // Settings Modal Handlers
  function openSettings() {
    modalServerUrl.value = state.serverUrl;
    if (serverTestFeedback) {
      serverTestFeedback.classList.add("hidden");
      serverTestFeedback.innerHTML = "";
    }
    if (modalCleanIp) modalCleanIp.value = state.cleanIp || "";
    if (antiDpiToggle) antiDpiToggle.checked = state.antiDpi;
    if (decoyChaffToggle) decoyChaffToggle.checked = state.decoyChaff;
    autoReconnectInput.checked = state.autoReconnect;
    if (notificationToggle) notificationToggle.checked = state.notificationsEnabled;
    if (vibrationToggle) vibrationToggle.checked = state.vibrationEnabled;
    keepCredentialsInput.checked = state.keepCredentials;
    settingsModal.classList.remove("hidden");
    queryActiveTunnel();
  }

  function closeSettings() {
    const oldUrl = state.serverUrl;
    state.serverUrl = sanitizeServerUrl(modalServerUrl.value);
    serverUrlInput.value = state.serverUrl;
    if (modalCleanIp) state.cleanIp = modalCleanIp.value.trim();
    if (antiDpiToggle) state.antiDpi = antiDpiToggle.checked;
    if (decoyChaffToggle) state.decoyChaff = decoyChaffToggle.checked;
    state.autoReconnect = autoReconnectInput.checked;
    if (vibrationToggle) state.vibrationEnabled = vibrationToggle.checked;
    state.keepCredentials = keepCredentialsInput.checked;
    updateAntiDpiBadge();
    persistSettings();
    settingsModal.classList.add("hidden");

    if (oldUrl !== state.serverUrl && state.isAuthenticated && state.room && state.password) {
      nativeToast("در حال انتقال به آدرس جدید سرور...");
      reconnect(0);
    }
  }

  // Connection Presets Handlers
  if (btnPresetDirect) {
    btnPresetDirect.addEventListener("click", () => {
      modalServerUrl.value = "ws://193.168.175.227:8765";
      nativeToast("الگوی اتصال مستقیم سرور انتخاب شد (:8765)");
      testServerConnectivity("ws://193.168.175.227:8765", serverTestFeedback, btnTestServerConn);
    });
  }

  if (btnPresetCfTunnel) {
    btnPresetCfTunnel.addEventListener("click", async () => {
      let tunnelUrl = state.activeTunnelUrl || "wss://occurring-nearby-salvador-photography.trycloudflare.com";
      const fetched = await queryActiveTunnel("ws://193.168.175.227:8765");
      if (fetched && fetched.ws_url) {
        tunnelUrl = fetched.ws_url;
      }
      modalServerUrl.value = tunnelUrl;
      nativeToast("الگوی کلودفلر تونل فعال انتخاب شد (WSS پورت 443)");
      testServerConnectivity(tunnelUrl, serverTestFeedback, btnTestServerConn);
    });
  }

  // Direct test connection button listeners
  if (btnTestServerConn) {
    btnTestServerConn.addEventListener("click", () => {
      const urlToTest = modalServerUrl.value.trim() || state.serverUrl;
      testServerConnectivity(urlToTest, serverTestFeedback, btnTestServerConn);
    });
  }

  if (btnTestGateConn) {
    btnTestGateConn.addEventListener("click", () => {
      const urlToTest = serverUrlInput.value.trim() || state.serverUrl;
      testServerConnectivity(urlToTest, gateTestFeedback, btnTestGateConn);
    });
  }

  if (modalServerUrl) {
    modalServerUrl.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        testServerConnectivity(modalServerUrl.value.trim(), serverTestFeedback, btnTestServerConn);
      }
    });
  }

  if (serverUrlInput) {
    serverUrlInput.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        testServerConnectivity(serverUrlInput.value.trim(), gateTestFeedback, btnTestGateConn);
      }
    });
  }

  if (antiDpiToggle) {
    antiDpiToggle.addEventListener("change", () => {
      state.antiDpi = antiDpiToggle.checked;
      updateAntiDpiBadge();
    });
  }

  // Initialize Anti-DPI badge status on launch
  updateAntiDpiBadge();

  btnSettings.addEventListener("click", openSettings);
  btnCloseSettings.addEventListener("click", closeSettings);

  settingsModal.addEventListener("click", (e) => {
    if (e.target === settingsModal) closeSettings();
  });

  btnTestNotif.addEventListener("click", () => {
    triggerBackgroundNotification("آزمایش سیستم", "این یک پیام تستی برای بررسی عملکرد اعلان روی صفحه قفل است.", state.room || "آزمایشی");
    nativeToast("اعلان تستی ارسال شد");
  });

  btnMinimizeApp.addEventListener("click", () => {
    closeSettings();
    if (window.ChatNative && window.ChatNative.minimizeApp) {
      window.ChatNative.minimizeApp();
    } else {
      nativeToast("برنامه در پس‌زمینه فعال باقی می‌ماند");
    }
  });

  // Android Back Button handler
  window.onBackPressed = () => {
    if (!settingsModal.classList.contains("hidden")) {
      closeSettings();
      return true;
    }
    return false;
  };

  // 6. Auto-connect on startup if credentials exist
  if (state.keepCredentials && state.room && state.password) {
    connectAndJoinRoom(state.room, state.password, state.nickname);
  }
})();

APP_EOF

cat << 'CRYPTO_EOF' > "${INSTALL_DIR}/web/crypto-js.min.js"
(function(P,C){typeof exports=="object"?module.exports=exports=C():typeof define=="function"&&define.amd?define([],C):P.CryptoJS=C()})(this,function(){var P=P||(function(C,_){var E;if(typeof window<"u"&&window.crypto&&(E=window.crypto),typeof self<"u"&&self.crypto&&(E=self.crypto),typeof globalThis<"u"&&globalThis.crypto&&(E=globalThis.crypto),!E&&typeof window<"u"&&window.msCrypto&&(E=window.msCrypto),!E&&typeof global<"u"&&global.crypto&&(E=global.crypto),!E&&typeof require=="function")try{E=require("crypto")}catch{}var y=function(){if(E){if(typeof E.getRandomValues=="function")try{return E.getRandomValues(new Uint32Array(1))[0]}catch{}if(typeof E.randomBytes=="function")try{return E.randomBytes(4).readInt32LE()}catch{}}throw new Error("Native crypto module could not be used to get secure random number.")},v=Object.create||(function(){function x(){}return function(t){var l;return x.prototype=t,l=new x,x.prototype=null,l}})(),F={},r=F.lib={},n=r.Base=(function(){return{extend:function(x){var t=v(this);return x&&t.mixIn(x),(!t.hasOwnProperty("init")||this.init===t.init)&&(t.init=function(){t.$super.init.apply(this,arguments)}),t.init.prototype=t,t.$super=this,t},create:function(){var x=this.extend();return x.init.apply(x,arguments),x},init:function(){},mixIn:function(x){for(var t in x)x.hasOwnProperty(t)&&(this[t]=x[t]);x.hasOwnProperty("toString")&&(this.toString=x.toString)},clone:function(){return this.init.prototype.extend(this)}}})(),c=r.WordArray=n.extend({init:function(x,t){x=this.words=x||[],t!=_?this.sigBytes=t:this.sigBytes=x.length*4},toString:function(x){return(x||o).stringify(this)},concat:function(x){var t=this.words,l=x.words,s=this.sigBytes,d=x.sigBytes;if(this.clamp(),s%4)for(var A=0;A<d;A++){var H=l[A>>>2]>>>24-A%4*8&255;t[s+A>>>2]|=H<<24-(s+A)%4*8}else for(var S=0;S<d;S+=4)t[s+S>>>2]=l[S>>>2];return this.sigBytes+=d,this},clamp:function(){var x=this.words,t=this.sigBytes;x[t>>>2]&=4294967295<<32-t%4*8,x.length=C.ceil(t/4)},clone:function(){var x=n.clone.call(this);return x.words=this.words.slice(0),x},random:function(x){for(var t=[],l=0;l<x;l+=4)t.push(y());return new c.init(t,x)}}),e=F.enc={},o=e.Hex={stringify:function(x){for(var t=x.words,l=x.sigBytes,s=[],d=0;d<l;d++){var A=t[d>>>2]>>>24-d%4*8&255;s.push((A>>>4).toString(16)),s.push((A&15).toString(16))}return s.join("")},parse:function(x){for(var t=x.length,l=[],s=0;s<t;s+=2)l[s>>>3]|=parseInt(x.substr(s,2),16)<<24-s%8*4;return new c.init(l,t/2)}},a=e.Latin1={stringify:function(x){for(var t=x.words,l=x.sigBytes,s=[],d=0;d<l;d++){var A=t[d>>>2]>>>24-d%4*8&255;s.push(String.fromCharCode(A))}return s.join("")},parse:function(x){for(var t=x.length,l=[],s=0;s<t;s++)l[s>>>2]|=(x.charCodeAt(s)&255)<<24-s%4*8;return new c.init(l,t)}},f=e.Utf8={stringify:function(x){try{return decodeURIComponent(escape(a.stringify(x)))}catch{throw new Error("Malformed UTF-8 data")}},parse:function(x){return a.parse(unescape(encodeURIComponent(x)))}},i=r.BufferedBlockAlgorithm=n.extend({reset:function(){this._data=new c.init,this._nDataBytes=0},_append:function(x){typeof x=="string"&&(x=f.parse(x)),this._data.concat(x),this._nDataBytes+=x.sigBytes},_process:function(x){var t,l=this._data,s=l.words,d=l.sigBytes,A=this.blockSize,H=A*4,S=d/H;x?S=C.ceil(S):S=C.max((S|0)-this._minBufferSize,0);var z=S*A,W=C.min(z*4,d);if(z){for(var D=0;D<z;D+=A)this._doProcessBlock(s,D);t=s.splice(0,z),l.sigBytes-=W}return new c.init(t,W)},clone:function(){var x=n.clone.call(this);return x._data=this._data.clone(),x},_minBufferSize:0}),B=r.Hasher=i.extend({cfg:n.extend(),init:function(x){this.cfg=this.cfg.extend(x),this.reset()},reset:function(){i.reset.call(this),this._doReset()},update:function(x){return this._append(x),this._process(),this},finalize:function(x){x&&this._append(x);var t=this._doFinalize();return t},blockSize:512/32,_createHelper:function(x){return function(t,l){return new x.init(l).finalize(t)}},_createHmacHelper:function(x){return function(t,l){return new h.HMAC.init(x,l).finalize(t)}}}),h=F.algo={};return F})(Math);(function(C){var _=P,E=_.lib,y=E.Base,v=E.WordArray,F=_.x64={},r=F.Word=y.extend({init:function(c,e){this.high=c,this.low=e}}),n=F.WordArray=y.extend({init:function(c,e){c=this.words=c||[],e!=C?this.sigBytes=e:this.sigBytes=c.length*8},toX32:function(){for(var c=this.words,e=c.length,o=[],a=0;a<e;a++){var f=c[a];o.push(f.high),o.push(f.low)}return v.create(o,this.sigBytes)},clone:function(){for(var c=y.clone.call(this),e=c.words=this.words.slice(0),o=e.length,a=0;a<o;a++)e[a]=e[a].clone();return c}})})(),(function(){if(typeof ArrayBuffer=="function"){var C=P,_=C.lib,E=_.WordArray,y=E.init,v=E.init=function(F){if(F instanceof ArrayBuffer&&(F=new Uint8Array(F)),(F instanceof Int8Array||typeof Uint8ClampedArray<"u"&&F instanceof Uint8ClampedArray||F instanceof Int16Array||F instanceof Uint16Array||F instanceof Int32Array||F instanceof Uint32Array||F instanceof Float32Array||F instanceof Float64Array)&&(F=new Uint8Array(F.buffer,F.byteOffset,F.byteLength)),F instanceof Uint8Array){for(var r=F.byteLength,n=[],c=0;c<r;c++)n[c>>>2]|=F[c]<<24-c%4*8;y.call(this,n,r)}else y.apply(this,arguments)};v.prototype=E}})(),(function(){var C=P,_=C.lib,E=_.WordArray,y=C.enc,v=y.Utf16=y.Utf16BE={stringify:function(r){for(var n=r.words,c=r.sigBytes,e=[],o=0;o<c;o+=2){var a=n[o>>>2]>>>16-o%4*8&65535;e.push(String.fromCharCode(a))}return e.join("")},parse:function(r){for(var n=r.length,c=[],e=0;e<n;e++)c[e>>>1]|=r.charCodeAt(e)<<16-e%2*16;return E.create(c,n*2)}};y.Utf16LE={stringify:function(r){for(var n=r.words,c=r.sigBytes,e=[],o=0;o<c;o+=2){var a=F(n[o>>>2]>>>16-o%4*8&65535);e.push(String.fromCharCode(a))}return e.join("")},parse:function(r){for(var n=r.length,c=[],e=0;e<n;e++)c[e>>>1]|=F(r.charCodeAt(e)<<16-e%2*16);return E.create(c,n*2)}};function F(r){return r<<8&4278255360|r>>>8&16711935}})(),(function(){var C=P,_=C.lib,E=_.WordArray,y=C.enc,v=y.Base64={stringify:function(r){var n=r.words,c=r.sigBytes,e=this._map;r.clamp();for(var o=[],a=0;a<c;a+=3)for(var f=n[a>>>2]>>>24-a%4*8&255,i=n[a+1>>>2]>>>24-(a+1)%4*8&255,B=n[a+2>>>2]>>>24-(a+2)%4*8&255,h=f<<16|i<<8|B,x=0;x<4&&a+x*.75<c;x++)o.push(e.charAt(h>>>6*(3-x)&63));var t=e.charAt(64);if(t)for(;o.length%4;)o.push(t);return o.join("")},parse:function(r){var n=r.length,c=this._map,e=this._reverseMap;if(!e){e=this._reverseMap=[];for(var o=0;o<c.length;o++)e[c.charCodeAt(o)]=o}var a=c.charAt(64);if(a){var f=r.indexOf(a);f!==-1&&(n=f)}return F(r,n,e)},_map:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="};function F(r,n,c){for(var e=[],o=0,a=0;a<n;a++)if(a%4){var f=c[r.charCodeAt(a-1)]<<a%4*2,i=c[r.charCodeAt(a)]>>>6-a%4*2,B=f|i;e[o>>>2]|=B<<24-o%4*8,o++}return E.create(e,o)}})(),(function(){var C=P,_=C.lib,E=_.WordArray,y=C.enc,v=y.Base64url={stringify:function(r,n){n===void 0&&(n=!0);var c=r.words,e=r.sigBytes,o=n?this._safe_map:this._map;r.clamp();for(var a=[],f=0;f<e;f+=3)for(var i=c[f>>>2]>>>24-f%4*8&255,B=c[f+1>>>2]>>>24-(f+1)%4*8&255,h=c[f+2>>>2]>>>24-(f+2)%4*8&255,x=i<<16|B<<8|h,t=0;t<4&&f+t*.75<e;t++)a.push(o.charAt(x>>>6*(3-t)&63));var l=o.charAt(64);if(l)for(;a.length%4;)a.push(l);return a.join("")},parse:function(r,n){n===void 0&&(n=!0);var c=r.length,e=n?this._safe_map:this._map,o=this._reverseMap;if(!o){o=this._reverseMap=[];for(var a=0;a<e.length;a++)o[e.charCodeAt(a)]=a}var f=e.charAt(64);if(f){var i=r.indexOf(f);i!==-1&&(c=i)}return F(r,c,o)},_map:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=",_safe_map:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"};function F(r,n,c){for(var e=[],o=0,a=0;a<n;a++)if(a%4){var f=c[r.charCodeAt(a-1)]<<a%4*2,i=c[r.charCodeAt(a)]>>>6-a%4*2,B=f|i;e[o>>>2]|=B<<24-o%4*8,o++}return E.create(e,o)}})(),(function(C){var _=P,E=_.lib,y=E.WordArray,v=E.Hasher,F=_.algo,r=[];(function(){for(var f=0;f<64;f++)r[f]=C.abs(C.sin(f+1))*4294967296|0})();var n=F.MD5=v.extend({_doReset:function(){this._hash=new y.init([1732584193,4023233417,2562383102,271733878])},_doProcessBlock:function(f,i){for(var B=0;B<16;B++){var h=i+B,x=f[h];f[h]=(x<<8|x>>>24)&16711935|(x<<24|x>>>8)&4278255360}var t=this._hash.words,l=f[i+0],s=f[i+1],d=f[i+2],A=f[i+3],H=f[i+4],S=f[i+5],z=f[i+6],W=f[i+7],D=f[i+8],w=f[i+9],m=f[i+10],g=f[i+11],L=f[i+12],R=f[i+13],X=f[i+14],T=f[i+15],u=t[0],b=t[1],k=t[2],p=t[3];u=c(u,b,k,p,l,7,r[0]),p=c(p,u,b,k,s,12,r[1]),k=c(k,p,u,b,d,17,r[2]),b=c(b,k,p,u,A,22,r[3]),u=c(u,b,k,p,H,7,r[4]),p=c(p,u,b,k,S,12,r[5]),k=c(k,p,u,b,z,17,r[6]),b=c(b,k,p,u,W,22,r[7]),u=c(u,b,k,p,D,7,r[8]),p=c(p,u,b,k,w,12,r[9]),k=c(k,p,u,b,m,17,r[10]),b=c(b,k,p,u,g,22,r[11]),u=c(u,b,k,p,L,7,r[12]),p=c(p,u,b,k,R,12,r[13]),k=c(k,p,u,b,X,17,r[14]),b=c(b,k,p,u,T,22,r[15]),u=e(u,b,k,p,s,5,r[16]),p=e(p,u,b,k,z,9,r[17]),k=e(k,p,u,b,g,14,r[18]),b=e(b,k,p,u,l,20,r[19]),u=e(u,b,k,p,S,5,r[20]),p=e(p,u,b,k,m,9,r[21]),k=e(k,p,u,b,T,14,r[22]),b=e(b,k,p,u,H,20,r[23]),u=e(u,b,k,p,w,5,r[24]),p=e(p,u,b,k,X,9,r[25]),k=e(k,p,u,b,A,14,r[26]),b=e(b,k,p,u,D,20,r[27]),u=e(u,b,k,p,R,5,r[28]),p=e(p,u,b,k,d,9,r[29]),k=e(k,p,u,b,W,14,r[30]),b=e(b,k,p,u,L,20,r[31]),u=o(u,b,k,p,S,4,r[32]),p=o(p,u,b,k,D,11,r[33]),k=o(k,p,u,b,g,16,r[34]),b=o(b,k,p,u,X,23,r[35]),u=o(u,b,k,p,s,4,r[36]),p=o(p,u,b,k,H,11,r[37]),k=o(k,p,u,b,W,16,r[38]),b=o(b,k,p,u,m,23,r[39]),u=o(u,b,k,p,R,4,r[40]),p=o(p,u,b,k,l,11,r[41]),k=o(k,p,u,b,A,16,r[42]),b=o(b,k,p,u,z,23,r[43]),u=o(u,b,k,p,w,4,r[44]),p=o(p,u,b,k,L,11,r[45]),k=o(k,p,u,b,T,16,r[46]),b=o(b,k,p,u,d,23,r[47]),u=a(u,b,k,p,l,6,r[48]),p=a(p,u,b,k,W,10,r[49]),k=a(k,p,u,b,X,15,r[50]),b=a(b,k,p,u,S,21,r[51]),u=a(u,b,k,p,L,6,r[52]),p=a(p,u,b,k,A,10,r[53]),k=a(k,p,u,b,m,15,r[54]),b=a(b,k,p,u,s,21,r[55]),u=a(u,b,k,p,D,6,r[56]),p=a(p,u,b,k,T,10,r[57]),k=a(k,p,u,b,z,15,r[58]),b=a(b,k,p,u,R,21,r[59]),u=a(u,b,k,p,H,6,r[60]),p=a(p,u,b,k,g,10,r[61]),k=a(k,p,u,b,d,15,r[62]),b=a(b,k,p,u,w,21,r[63]),t[0]=t[0]+u|0,t[1]=t[1]+b|0,t[2]=t[2]+k|0,t[3]=t[3]+p|0},_doFinalize:function(){var f=this._data,i=f.words,B=this._nDataBytes*8,h=f.sigBytes*8;i[h>>>5]|=128<<24-h%32;var x=C.floor(B/4294967296),t=B;i[(h+64>>>9<<4)+15]=(x<<8|x>>>24)&16711935|(x<<24|x>>>8)&4278255360,i[(h+64>>>9<<4)+14]=(t<<8|t>>>24)&16711935|(t<<24|t>>>8)&4278255360,f.sigBytes=(i.length+1)*4,this._process();for(var l=this._hash,s=l.words,d=0;d<4;d++){var A=s[d];s[d]=(A<<8|A>>>24)&16711935|(A<<24|A>>>8)&4278255360}return l},clone:function(){var f=v.clone.call(this);return f._hash=this._hash.clone(),f}});function c(f,i,B,h,x,t,l){var s=f+(i&B|~i&h)+x+l;return(s<<t|s>>>32-t)+i}function e(f,i,B,h,x,t,l){var s=f+(i&h|B&~h)+x+l;return(s<<t|s>>>32-t)+i}function o(f,i,B,h,x,t,l){var s=f+(i^B^h)+x+l;return(s<<t|s>>>32-t)+i}function a(f,i,B,h,x,t,l){var s=f+(B^(i|~h))+x+l;return(s<<t|s>>>32-t)+i}_.MD5=v._createHelper(n),_.HmacMD5=v._createHmacHelper(n)})(Math),(function(){var C=P,_=C.lib,E=_.WordArray,y=_.Hasher,v=C.algo,F=[],r=v.SHA1=y.extend({_doReset:function(){this._hash=new E.init([1732584193,4023233417,2562383102,271733878,3285377520])},_doProcessBlock:function(n,c){for(var e=this._hash.words,o=e[0],a=e[1],f=e[2],i=e[3],B=e[4],h=0;h<80;h++){if(h<16)F[h]=n[c+h]|0;else{var x=F[h-3]^F[h-8]^F[h-14]^F[h-16];F[h]=x<<1|x>>>31}var t=(o<<5|o>>>27)+B+F[h];h<20?t+=(a&f|~a&i)+1518500249:h<40?t+=(a^f^i)+1859775393:h<60?t+=(a&f|a&i|f&i)-1894007588:t+=(a^f^i)-899497514,B=i,i=f,f=a<<30|a>>>2,a=o,o=t}e[0]=e[0]+o|0,e[1]=e[1]+a|0,e[2]=e[2]+f|0,e[3]=e[3]+i|0,e[4]=e[4]+B|0},_doFinalize:function(){var n=this._data,c=n.words,e=this._nDataBytes*8,o=n.sigBytes*8;return c[o>>>5]|=128<<24-o%32,c[(o+64>>>9<<4)+14]=Math.floor(e/4294967296),c[(o+64>>>9<<4)+15]=e,n.sigBytes=c.length*4,this._process(),this._hash},clone:function(){var n=y.clone.call(this);return n._hash=this._hash.clone(),n}});C.SHA1=y._createHelper(r),C.HmacSHA1=y._createHmacHelper(r)})(),(function(C){var _=P,E=_.lib,y=E.WordArray,v=E.Hasher,F=_.algo,r=[],n=[];(function(){function o(B){for(var h=C.sqrt(B),x=2;x<=h;x++)if(!(B%x))return!1;return!0}function a(B){return(B-(B|0))*4294967296|0}for(var f=2,i=0;i<64;)o(f)&&(i<8&&(r[i]=a(C.pow(f,1/2))),n[i]=a(C.pow(f,1/3)),i++),f++})();var c=[],e=F.SHA256=v.extend({_doReset:function(){this._hash=new y.init(r.slice(0))},_doProcessBlock:function(o,a){for(var f=this._hash.words,i=f[0],B=f[1],h=f[2],x=f[3],t=f[4],l=f[5],s=f[6],d=f[7],A=0;A<64;A++){if(A<16)c[A]=o[a+A]|0;else{var H=c[A-15],S=(H<<25|H>>>7)^(H<<14|H>>>18)^H>>>3,z=c[A-2],W=(z<<15|z>>>17)^(z<<13|z>>>19)^z>>>10;c[A]=S+c[A-7]+W+c[A-16]}var D=t&l^~t&s,w=i&B^i&h^B&h,m=(i<<30|i>>>2)^(i<<19|i>>>13)^(i<<10|i>>>22),g=(t<<26|t>>>6)^(t<<21|t>>>11)^(t<<7|t>>>25),L=d+g+D+n[A]+c[A],R=m+w;d=s,s=l,l=t,t=x+L|0,x=h,h=B,B=i,i=L+R|0}f[0]=f[0]+i|0,f[1]=f[1]+B|0,f[2]=f[2]+h|0,f[3]=f[3]+x|0,f[4]=f[4]+t|0,f[5]=f[5]+l|0,f[6]=f[6]+s|0,f[7]=f[7]+d|0},_doFinalize:function(){var o=this._data,a=o.words,f=this._nDataBytes*8,i=o.sigBytes*8;return a[i>>>5]|=128<<24-i%32,a[(i+64>>>9<<4)+14]=C.floor(f/4294967296),a[(i+64>>>9<<4)+15]=f,o.sigBytes=a.length*4,this._process(),this._hash},clone:function(){var o=v.clone.call(this);return o._hash=this._hash.clone(),o}});_.SHA256=v._createHelper(e),_.HmacSHA256=v._createHmacHelper(e)})(Math),(function(){var C=P,_=C.lib,E=_.WordArray,y=C.algo,v=y.SHA256,F=y.SHA224=v.extend({_doReset:function(){this._hash=new E.init([3238371032,914150663,812702999,4144912697,4290775857,1750603025,1694076839,3204075428])},_doFinalize:function(){var r=v._doFinalize.call(this);return r.sigBytes-=4,r}});C.SHA224=v._createHelper(F),C.HmacSHA224=v._createHmacHelper(F)})(),(function(){var C=P,_=C.lib,E=_.Hasher,y=C.x64,v=y.Word,F=y.WordArray,r=C.algo;function n(){return v.create.apply(v,arguments)}var c=[n(1116352408,3609767458),n(1899447441,602891725),n(3049323471,3964484399),n(3921009573,2173295548),n(961987163,4081628472),n(1508970993,3053834265),n(2453635748,2937671579),n(2870763221,3664609560),n(3624381080,2734883394),n(310598401,1164996542),n(607225278,1323610764),n(1426881987,3590304994),n(1925078388,4068182383),n(2162078206,991336113),n(2614888103,633803317),n(3248222580,3479774868),n(3835390401,2666613458),n(4022224774,944711139),n(264347078,2341262773),n(604807628,2007800933),n(770255983,1495990901),n(1249150122,1856431235),n(1555081692,3175218132),n(1996064986,2198950837),n(2554220882,3999719339),n(2821834349,766784016),n(2952996808,2566594879),n(3210313671,3203337956),n(3336571891,1034457026),n(3584528711,2466948901),n(113926993,3758326383),n(338241895,168717936),n(666307205,1188179964),n(773529912,1546045734),n(1294757372,1522805485),n(1396182291,2643833823),n(1695183700,2343527390),n(1986661051,1014477480),n(2177026350,1206759142),n(2456956037,344077627),n(2730485921,1290863460),n(2820302411,3158454273),n(3259730800,3505952657),n(3345764771,106217008),n(3516065817,3606008344),n(3600352804,1432725776),n(4094571909,1467031594),n(275423344,851169720),n(430227734,3100823752),n(506948616,1363258195),n(659060556,3750685593),n(883997877,3785050280),n(958139571,3318307427),n(1322822218,3812723403),n(1537002063,2003034995),n(1747873779,3602036899),n(1955562222,1575990012),n(2024104815,1125592928),n(2227730452,2716904306),n(2361852424,442776044),n(2428436474,593698344),n(2756734187,3733110249),n(3204031479,2999351573),n(3329325298,3815920427),n(3391569614,3928383900),n(3515267271,566280711),n(3940187606,3454069534),n(4118630271,4000239992),n(116418474,1914138554),n(174292421,2731055270),n(289380356,3203993006),n(460393269,320620315),n(685471733,587496836),n(852142971,1086792851),n(1017036298,365543100),n(1126000580,2618297676),n(1288033470,3409855158),n(1501505948,4234509866),n(1607167915,987167468),n(1816402316,1246189591)],e=[];(function(){for(var a=0;a<80;a++)e[a]=n()})();var o=r.SHA512=E.extend({_doReset:function(){this._hash=new F.init([new v.init(1779033703,4089235720),new v.init(3144134277,2227873595),new v.init(1013904242,4271175723),new v.init(2773480762,1595750129),new v.init(1359893119,2917565137),new v.init(2600822924,725511199),new v.init(528734635,4215389547),new v.init(1541459225,327033209)])},_doProcessBlock:function(a,f){for(var i=this._hash.words,B=i[0],h=i[1],x=i[2],t=i[3],l=i[4],s=i[5],d=i[6],A=i[7],H=B.high,S=B.low,z=h.high,W=h.low,D=x.high,w=x.low,m=t.high,g=t.low,L=l.high,R=l.low,X=s.high,T=s.low,u=d.high,b=d.low,k=A.high,p=A.low,U=H,N=S,I=z,K=W,M=D,$=w,c0=m,x0=g,Z=L,O=R,i0=X,r0=T,f0=u,e0=b,s0=k,a0=p,J=0;J<80;J++){var q,Q,o0=e[J];if(J<16)Q=o0.high=a[f+J*2]|0,q=o0.low=a[f+J*2+1]|0;else{var v0=e[J-15],V=v0.high,t0=v0.low,p0=(V>>>1|t0<<31)^(V>>>8|t0<<24)^V>>>7,B0=(t0>>>1|V<<31)^(t0>>>8|V<<24)^(t0>>>7|V<<25),C0=e[J-2],j=C0.high,n0=C0.low,y0=(j>>>19|n0<<13)^(j<<3|n0>>>29)^j>>>6,h0=(n0>>>19|j<<13)^(n0<<3|j>>>29)^(n0>>>6|j<<26),l0=e[J-7],b0=l0.high,g0=l0.low,d0=e[J-16],k0=d0.high,E0=d0.low;q=B0+g0,Q=p0+b0+(q>>>0<B0>>>0?1:0),q=q+h0,Q=Q+y0+(q>>>0<h0>>>0?1:0),q=q+E0,Q=Q+k0+(q>>>0<E0>>>0?1:0),o0.high=Q,o0.low=q}var S0=Z&i0^~Z&f0,A0=O&r0^~O&e0,w0=U&I^U&M^I&M,H0=N&K^N&$^K&$,z0=(U>>>28|N<<4)^(U<<30|N>>>2)^(U<<25|N>>>7),F0=(N>>>28|U<<4)^(N<<30|U>>>2)^(N<<25|U>>>7),m0=(Z>>>14|O<<18)^(Z>>>18|O<<14)^(Z<<23|O>>>9),W0=(O>>>14|Z<<18)^(O>>>18|Z<<14)^(O<<23|Z>>>9),D0=c[J],R0=D0.high,u0=D0.low,G=a0+W0,Y=s0+m0+(G>>>0<a0>>>0?1:0),G=G+A0,Y=Y+S0+(G>>>0<A0>>>0?1:0),G=G+u0,Y=Y+R0+(G>>>0<u0>>>0?1:0),G=G+q,Y=Y+Q+(G>>>0<q>>>0?1:0),_0=F0+H0,P0=z0+w0+(_0>>>0<F0>>>0?1:0);s0=f0,a0=e0,f0=i0,e0=r0,i0=Z,r0=O,O=x0+G|0,Z=c0+Y+(O>>>0<x0>>>0?1:0)|0,c0=M,x0=$,M=I,$=K,I=U,K=N,N=G+_0|0,U=Y+P0+(N>>>0<G>>>0?1:0)|0}S=B.low=S+N,B.high=H+U+(S>>>0<N>>>0?1:0),W=h.low=W+K,h.high=z+I+(W>>>0<K>>>0?1:0),w=x.low=w+$,x.high=D+M+(w>>>0<$>>>0?1:0),g=t.low=g+x0,t.high=m+c0+(g>>>0<x0>>>0?1:0),R=l.low=R+O,l.high=L+Z+(R>>>0<O>>>0?1:0),T=s.low=T+r0,s.high=X+i0+(T>>>0<r0>>>0?1:0),b=d.low=b+e0,d.high=u+f0+(b>>>0<e0>>>0?1:0),p=A.low=p+a0,A.high=k+s0+(p>>>0<a0>>>0?1:0)},_doFinalize:function(){var a=this._data,f=a.words,i=this._nDataBytes*8,B=a.sigBytes*8;f[B>>>5]|=128<<24-B%32,f[(B+128>>>10<<5)+30]=Math.floor(i/4294967296),f[(B+128>>>10<<5)+31]=i,a.sigBytes=f.length*4,this._process();var h=this._hash.toX32();return h},clone:function(){var a=E.clone.call(this);return a._hash=this._hash.clone(),a},blockSize:1024/32});C.SHA512=E._createHelper(o),C.HmacSHA512=E._createHmacHelper(o)})(),(function(){var C=P,_=C.x64,E=_.Word,y=_.WordArray,v=C.algo,F=v.SHA512,r=v.SHA384=F.extend({_doReset:function(){this._hash=new y.init([new E.init(3418070365,3238371032),new E.init(1654270250,914150663),new E.init(2438529370,812702999),new E.init(355462360,4144912697),new E.init(1731405415,4290775857),new E.init(2394180231,1750603025),new E.init(3675008525,1694076839),new E.init(1203062813,3204075428)])},_doFinalize:function(){var n=F._doFinalize.call(this);return n.sigBytes-=16,n}});C.SHA384=F._createHelper(r),C.HmacSHA384=F._createHmacHelper(r)})(),(function(C){var _=P,E=_.lib,y=E.WordArray,v=E.Hasher,F=_.x64,r=F.Word,n=_.algo,c=[],e=[],o=[];(function(){for(var i=1,B=0,h=0;h<24;h++){c[i+5*B]=(h+1)*(h+2)/2%64;var x=B%5,t=(2*i+3*B)%5;i=x,B=t}for(var i=0;i<5;i++)for(var B=0;B<5;B++)e[i+5*B]=B+(2*i+3*B)%5*5;for(var l=1,s=0;s<24;s++){for(var d=0,A=0,H=0;H<7;H++){if(l&1){var S=(1<<H)-1;S<32?A^=1<<S:d^=1<<S-32}l&128?l=l<<1^113:l<<=1}o[s]=r.create(d,A)}})();var a=[];(function(){for(var i=0;i<25;i++)a[i]=r.create()})();var f=n.SHA3=v.extend({cfg:v.cfg.extend({outputLength:512}),_doReset:function(){for(var i=this._state=[],B=0;B<25;B++)i[B]=new r.init;this.blockSize=(1600-2*this.cfg.outputLength)/32},_doProcessBlock:function(i,B){for(var h=this._state,x=this.blockSize/2,t=0;t<x;t++){var l=i[B+2*t],s=i[B+2*t+1];l=(l<<8|l>>>24)&16711935|(l<<24|l>>>8)&4278255360,s=(s<<8|s>>>24)&16711935|(s<<24|s>>>8)&4278255360;var d=h[t];d.high^=s,d.low^=l}for(var A=0;A<24;A++){for(var H=0;H<5;H++){for(var S=0,z=0,W=0;W<5;W++){var d=h[H+5*W];S^=d.high,z^=d.low}var D=a[H];D.high=S,D.low=z}for(var H=0;H<5;H++)for(var w=a[(H+4)%5],m=a[(H+1)%5],g=m.high,L=m.low,S=w.high^(g<<1|L>>>31),z=w.low^(L<<1|g>>>31),W=0;W<5;W++){var d=h[H+5*W];d.high^=S,d.low^=z}for(var R=1;R<25;R++){var S,z,d=h[R],X=d.high,T=d.low,u=c[R];u<32?(S=X<<u|T>>>32-u,z=T<<u|X>>>32-u):(S=T<<u-32|X>>>64-u,z=X<<u-32|T>>>64-u);var b=a[e[R]];b.high=S,b.low=z}var k=a[0],p=h[0];k.high=p.high,k.low=p.low;for(var H=0;H<5;H++)for(var W=0;W<5;W++){var R=H+5*W,d=h[R],U=a[R],N=a[(H+1)%5+5*W],I=a[(H+2)%5+5*W];d.high=U.high^~N.high&I.high,d.low=U.low^~N.low&I.low}var d=h[0],K=o[A];d.high^=K.high,d.low^=K.low}},_doFinalize:function(){var i=this._data,B=i.words,h=this._nDataBytes*8,x=i.sigBytes*8,t=this.blockSize*32;B[x>>>5]|=1<<24-x%32,B[(C.ceil((x+1)/t)*t>>>5)-1]|=128,i.sigBytes=B.length*4,this._process();for(var l=this._state,s=this.cfg.outputLength/8,d=s/8,A=[],H=0;H<d;H++){var S=l[H],z=S.high,W=S.low;z=(z<<8|z>>>24)&16711935|(z<<24|z>>>8)&4278255360,W=(W<<8|W>>>24)&16711935|(W<<24|W>>>8)&4278255360,A.push(W),A.push(z)}return new y.init(A,s)},clone:function(){for(var i=v.clone.call(this),B=i._state=this._state.slice(0),h=0;h<25;h++)B[h]=B[h].clone();return i}});_.SHA3=v._createHelper(f),_.HmacSHA3=v._createHmacHelper(f)})(Math);/** @preserve
	(c) 2012 by Cédric Mesnil. All rights reserved.

	Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

	    - Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
	    - Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
	*/(function(C){var _=P,E=_.lib,y=E.WordArray,v=E.Hasher,F=_.algo,r=y.create([0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,7,4,13,1,10,6,15,3,12,0,9,5,2,14,11,8,3,10,14,4,9,15,8,1,2,7,0,6,13,11,5,12,1,9,11,10,0,8,12,4,13,3,7,15,14,5,6,2,4,0,5,9,7,12,2,10,14,1,3,8,11,6,15,13]),n=y.create([5,14,7,0,9,2,11,4,13,6,15,8,1,10,3,12,6,11,3,7,0,13,5,10,14,15,8,12,4,9,1,2,15,5,1,3,7,14,6,9,11,8,12,2,10,0,4,13,8,6,4,1,3,11,15,0,5,12,2,13,9,7,10,14,12,15,10,4,1,5,8,7,6,2,13,14,0,3,9,11]),c=y.create([11,14,15,12,5,8,7,9,11,13,14,15,6,7,9,8,7,6,8,13,11,9,7,15,7,12,15,9,11,7,13,12,11,13,6,7,14,9,13,15,14,8,13,6,5,12,7,5,11,12,14,15,14,15,9,8,9,14,5,6,8,6,5,12,9,15,5,11,6,8,13,12,5,12,13,14,11,8,5,6]),e=y.create([8,9,9,11,13,15,15,5,7,7,8,11,14,14,12,6,9,13,15,7,12,8,9,11,7,7,12,7,6,15,13,11,9,7,15,11,8,6,6,14,12,13,5,14,13,13,7,5,15,5,8,11,14,14,6,14,6,9,12,9,12,5,15,8,8,5,12,9,12,5,14,6,8,13,6,5,15,13,11,11]),o=y.create([0,1518500249,1859775393,2400959708,2840853838]),a=y.create([1352829926,1548603684,1836072691,2053994217,0]),f=F.RIPEMD160=v.extend({_doReset:function(){this._hash=y.create([1732584193,4023233417,2562383102,271733878,3285377520])},_doProcessBlock:function(s,d){for(var A=0;A<16;A++){var H=d+A,S=s[H];s[H]=(S<<8|S>>>24)&16711935|(S<<24|S>>>8)&4278255360}var z=this._hash.words,W=o.words,D=a.words,w=r.words,m=n.words,g=c.words,L=e.words,R,X,T,u,b,k,p,U,N,I;k=R=z[0],p=X=z[1],U=T=z[2],N=u=z[3],I=b=z[4];for(var K,A=0;A<80;A+=1)K=R+s[d+w[A]]|0,A<16?K+=i(X,T,u)+W[0]:A<32?K+=B(X,T,u)+W[1]:A<48?K+=h(X,T,u)+W[2]:A<64?K+=x(X,T,u)+W[3]:K+=t(X,T,u)+W[4],K=K|0,K=l(K,g[A]),K=K+b|0,R=b,b=u,u=l(T,10),T=X,X=K,K=k+s[d+m[A]]|0,A<16?K+=t(p,U,N)+D[0]:A<32?K+=x(p,U,N)+D[1]:A<48?K+=h(p,U,N)+D[2]:A<64?K+=B(p,U,N)+D[3]:K+=i(p,U,N)+D[4],K=K|0,K=l(K,L[A]),K=K+I|0,k=I,I=N,N=l(U,10),U=p,p=K;K=z[1]+T+N|0,z[1]=z[2]+u+I|0,z[2]=z[3]+b+k|0,z[3]=z[4]+R+p|0,z[4]=z[0]+X+U|0,z[0]=K},_doFinalize:function(){var s=this._data,d=s.words,A=this._nDataBytes*8,H=s.sigBytes*8;d[H>>>5]|=128<<24-H%32,d[(H+64>>>9<<4)+14]=(A<<8|A>>>24)&16711935|(A<<24|A>>>8)&4278255360,s.sigBytes=(d.length+1)*4,this._process();for(var S=this._hash,z=S.words,W=0;W<5;W++){var D=z[W];z[W]=(D<<8|D>>>24)&16711935|(D<<24|D>>>8)&4278255360}return S},clone:function(){var s=v.clone.call(this);return s._hash=this._hash.clone(),s}});function i(s,d,A){return s^d^A}function B(s,d,A){return s&d|~s&A}function h(s,d,A){return(s|~d)^A}function x(s,d,A){return s&A|d&~A}function t(s,d,A){return s^(d|~A)}function l(s,d){return s<<d|s>>>32-d}_.RIPEMD160=v._createHelper(f),_.HmacRIPEMD160=v._createHmacHelper(f)})(Math),(function(){var C=P,_=C.lib,E=_.Base,y=C.enc,v=y.Utf8,F=C.algo,r=F.HMAC=E.extend({init:function(n,c){n=this._hasher=new n.init,typeof c=="string"&&(c=v.parse(c));var e=n.blockSize,o=e*4;c.sigBytes>o&&(c=n.finalize(c)),c.clamp();for(var a=this._oKey=c.clone(),f=this._iKey=c.clone(),i=a.words,B=f.words,h=0;h<e;h++)i[h]^=1549556828,B[h]^=909522486;a.sigBytes=f.sigBytes=o,this.reset()},reset:function(){var n=this._hasher;n.reset(),n.update(this._iKey)},update:function(n){return this._hasher.update(n),this},finalize:function(n){var c=this._hasher,e=c.finalize(n);c.reset();var o=c.finalize(this._oKey.clone().concat(e));return o}})})(),(function(){var C=P,_=C.lib,E=_.Base,y=_.WordArray,v=C.algo,F=v.SHA256,r=v.HMAC,n=v.PBKDF2=E.extend({cfg:E.extend({keySize:128/32,hasher:F,iterations:25e4}),init:function(c){this.cfg=this.cfg.extend(c)},compute:function(c,e){for(var o=this.cfg,a=r.create(o.hasher,c),f=y.create(),i=y.create([1]),B=f.words,h=i.words,x=o.keySize,t=o.iterations;B.length<x;){var l=a.update(e).finalize(i);a.reset();for(var s=l.words,d=s.length,A=l,H=1;H<t;H++){A=a.finalize(A),a.reset();for(var S=A.words,z=0;z<d;z++)s[z]^=S[z]}f.concat(l),h[0]++}return f.sigBytes=x*4,f}});C.PBKDF2=function(c,e,o){return n.create(o).compute(c,e)}})(),(function(){var C=P,_=C.lib,E=_.Base,y=_.WordArray,v=C.algo,F=v.MD5,r=v.EvpKDF=E.extend({cfg:E.extend({keySize:128/32,hasher:F,iterations:1}),init:function(n){this.cfg=this.cfg.extend(n)},compute:function(n,c){for(var e,o=this.cfg,a=o.hasher.create(),f=y.create(),i=f.words,B=o.keySize,h=o.iterations;i.length<B;){e&&a.update(e),e=a.update(n).finalize(c),a.reset();for(var x=1;x<h;x++)e=a.finalize(e),a.reset();f.concat(e)}return f.sigBytes=B*4,f}});C.EvpKDF=function(n,c,e){return r.create(e).compute(n,c)}})(),P.lib.Cipher||(function(C){var _=P,E=_.lib,y=E.Base,v=E.WordArray,F=E.BufferedBlockAlgorithm,r=_.enc,n=r.Utf8,c=r.Base64,e=_.algo,o=e.EvpKDF,a=E.Cipher=F.extend({cfg:y.extend(),createEncryptor:function(D,w){return this.create(this._ENC_XFORM_MODE,D,w)},createDecryptor:function(D,w){return this.create(this._DEC_XFORM_MODE,D,w)},init:function(D,w,m){this.cfg=this.cfg.extend(m),this._xformMode=D,this._key=w,this.reset()},reset:function(){F.reset.call(this),this._doReset()},process:function(D){return this._append(D),this._process()},finalize:function(D){D&&this._append(D);var w=this._doFinalize();return w},keySize:128/32,ivSize:128/32,_ENC_XFORM_MODE:1,_DEC_XFORM_MODE:2,_createHelper:(function(){function D(w){return typeof w=="string"?W:H}return function(w){return{encrypt:function(m,g,L){return D(g).encrypt(w,m,g,L)},decrypt:function(m,g,L){return D(g).decrypt(w,m,g,L)}}}})()}),f=E.StreamCipher=a.extend({_doFinalize:function(){var D=this._process(!0);return D},blockSize:1}),i=_.mode={},B=E.BlockCipherMode=y.extend({createEncryptor:function(D,w){return this.Encryptor.create(D,w)},createDecryptor:function(D,w){return this.Decryptor.create(D,w)},init:function(D,w){this._cipher=D,this._iv=w}}),h=i.CBC=(function(){var D=B.extend();D.Encryptor=D.extend({processBlock:function(m,g){var L=this._cipher,R=L.blockSize;w.call(this,m,g,R),L.encryptBlock(m,g),this._prevBlock=m.slice(g,g+R)}}),D.Decryptor=D.extend({processBlock:function(m,g){var L=this._cipher,R=L.blockSize,X=m.slice(g,g+R);L.decryptBlock(m,g),w.call(this,m,g,R),this._prevBlock=X}});function w(m,g,L){var R,X=this._iv;X?(R=X,this._iv=C):R=this._prevBlock;for(var T=0;T<L;T++)m[g+T]^=R[T]}return D})(),x=_.pad={},t=x.Pkcs7={pad:function(D,w){for(var m=w*4,g=m-D.sigBytes%m,L=g<<24|g<<16|g<<8|g,R=[],X=0;X<g;X+=4)R.push(L);var T=v.create(R,g);D.concat(T)},unpad:function(D){var w=D.words[D.sigBytes-1>>>2]&255;D.sigBytes-=w}},l=E.BlockCipher=a.extend({cfg:a.cfg.extend({mode:h,padding:t}),reset:function(){var D;a.reset.call(this);var w=this.cfg,m=w.iv,g=w.mode;this._xformMode==this._ENC_XFORM_MODE?D=g.createEncryptor:(D=g.createDecryptor,this._minBufferSize=1),this._mode&&this._mode.__creator==D?this._mode.init(this,m&&m.words):(this._mode=D.call(g,this,m&&m.words),this._mode.__creator=D)},_doProcessBlock:function(D,w){this._mode.processBlock(D,w)},_doFinalize:function(){var D,w=this.cfg.padding;return this._xformMode==this._ENC_XFORM_MODE?(w.pad(this._data,this.blockSize),D=this._process(!0)):(D=this._process(!0),w.unpad(D)),D},blockSize:128/32}),s=E.CipherParams=y.extend({init:function(D){this.mixIn(D)},toString:function(D){return(D||this.formatter).stringify(this)}}),d=_.format={},A=d.OpenSSL={stringify:function(D){var w,m=D.ciphertext,g=D.salt;return g?w=v.create([1398893684,1701076831]).concat(g).concat(m):w=m,w.toString(c)},parse:function(D){var w,m=c.parse(D),g=m.words;return g[0]==1398893684&&g[1]==1701076831&&(w=v.create(g.slice(2,4)),g.splice(0,4),m.sigBytes-=16),s.create({ciphertext:m,salt:w})}},H=E.SerializableCipher=y.extend({cfg:y.extend({format:A}),encrypt:function(D,w,m,g){g=this.cfg.extend(g);var L=D.createEncryptor(m,g),R=L.finalize(w),X=L.cfg;return s.create({ciphertext:R,key:m,iv:X.iv,algorithm:D,mode:X.mode,padding:X.padding,blockSize:D.blockSize,formatter:g.format})},decrypt:function(D,w,m,g){g=this.cfg.extend(g),w=this._parse(w,g.format);var L=D.createDecryptor(m,g).finalize(w.ciphertext);return L},_parse:function(D,w){return typeof D=="string"?w.parse(D,this):D}}),S=_.kdf={},z=S.OpenSSL={execute:function(D,w,m,g,L){if(g||(g=v.random(64/8)),L)var R=o.create({keySize:w+m,hasher:L}).compute(D,g);else var R=o.create({keySize:w+m}).compute(D,g);var X=v.create(R.words.slice(w),m*4);return R.sigBytes=w*4,s.create({key:R,iv:X,salt:g})}},W=E.PasswordBasedCipher=H.extend({cfg:H.cfg.extend({kdf:z}),encrypt:function(D,w,m,g){g=this.cfg.extend(g);var L=g.kdf.execute(m,D.keySize,D.ivSize,g.salt,g.hasher);g.iv=L.iv;var R=H.encrypt.call(this,D,w,L.key,g);return R.mixIn(L),R},decrypt:function(D,w,m,g){g=this.cfg.extend(g),w=this._parse(w,g.format);var L=g.kdf.execute(m,D.keySize,D.ivSize,w.salt,g.hasher);g.iv=L.iv;var R=H.decrypt.call(this,D,w,L.key,g);return R}})})(),P.mode.CFB=(function(){var C=P.lib.BlockCipherMode.extend();C.Encryptor=C.extend({processBlock:function(E,y){var v=this._cipher,F=v.blockSize;_.call(this,E,y,F,v),this._prevBlock=E.slice(y,y+F)}}),C.Decryptor=C.extend({processBlock:function(E,y){var v=this._cipher,F=v.blockSize,r=E.slice(y,y+F);_.call(this,E,y,F,v),this._prevBlock=r}});function _(E,y,v,F){var r,n=this._iv;n?(r=n.slice(0),this._iv=void 0):r=this._prevBlock,F.encryptBlock(r,0);for(var c=0;c<v;c++)E[y+c]^=r[c]}return C})(),P.mode.CTR=(function(){var C=P.lib.BlockCipherMode.extend(),_=C.Encryptor=C.extend({processBlock:function(E,y){var v=this._cipher,F=v.blockSize,r=this._iv,n=this._counter;r&&(n=this._counter=r.slice(0),this._iv=void 0);var c=n.slice(0);v.encryptBlock(c,0),n[F-1]=n[F-1]+1|0;for(var e=0;e<F;e++)E[y+e]^=c[e]}});return C.Decryptor=_,C})();/** @preserve
 * Counter block mode compatible with  Dr Brian Gladman fileenc.c
 * derived from CryptoJS.mode.CTR
 * Jan Hruby jhruby.web@gmail.com
 */return P.mode.CTRGladman=(function(){var C=P.lib.BlockCipherMode.extend();function _(v){if((v>>24&255)===255){var F=v>>16&255,r=v>>8&255,n=v&255;F===255?(F=0,r===255?(r=0,n===255?n=0:++n):++r):++F,v=0,v+=F<<16,v+=r<<8,v+=n}else v+=1<<24;return v}function E(v){return(v[0]=_(v[0]))===0&&(v[1]=_(v[1])),v}var y=C.Encryptor=C.extend({processBlock:function(v,F){var r=this._cipher,n=r.blockSize,c=this._iv,e=this._counter;c&&(e=this._counter=c.slice(0),this._iv=void 0),E(e);var o=e.slice(0);r.encryptBlock(o,0);for(var a=0;a<n;a++)v[F+a]^=o[a]}});return C.Decryptor=y,C})(),P.mode.OFB=(function(){var C=P.lib.BlockCipherMode.extend(),_=C.Encryptor=C.extend({processBlock:function(E,y){var v=this._cipher,F=v.blockSize,r=this._iv,n=this._keystream;r&&(n=this._keystream=r.slice(0),this._iv=void 0),v.encryptBlock(n,0);for(var c=0;c<F;c++)E[y+c]^=n[c]}});return C.Decryptor=_,C})(),P.mode.ECB=(function(){var C=P.lib.BlockCipherMode.extend();return C.Encryptor=C.extend({processBlock:function(_,E){this._cipher.encryptBlock(_,E)}}),C.Decryptor=C.extend({processBlock:function(_,E){this._cipher.decryptBlock(_,E)}}),C})(),P.pad.AnsiX923={pad:function(C,_){var E=C.sigBytes,y=_*4,v=y-E%y,F=E+v-1;C.clamp(),C.words[F>>>2]|=v<<24-F%4*8,C.sigBytes+=v},unpad:function(C){var _=C.words[C.sigBytes-1>>>2]&255;C.sigBytes-=_}},P.pad.Iso10126={pad:function(C,_){var E=_*4,y=E-C.sigBytes%E;C.concat(P.lib.WordArray.random(y-1)).concat(P.lib.WordArray.create([y<<24],1))},unpad:function(C){var _=C.words[C.sigBytes-1>>>2]&255;C.sigBytes-=_}},P.pad.Iso97971={pad:function(C,_){C.concat(P.lib.WordArray.create([2147483648],1)),P.pad.ZeroPadding.pad(C,_)},unpad:function(C){P.pad.ZeroPadding.unpad(C),C.sigBytes--}},P.pad.ZeroPadding={pad:function(C,_){var E=_*4;C.clamp(),C.sigBytes+=E-(C.sigBytes%E||E)},unpad:function(C){for(var _=C.words,E=C.sigBytes-1,E=C.sigBytes-1;E>=0;E--)if(_[E>>>2]>>>24-E%4*8&255){C.sigBytes=E+1;break}}},P.pad.NoPadding={pad:function(){},unpad:function(){}},(function(C){var _=P,E=_.lib,y=E.CipherParams,v=_.enc,F=v.Hex,r=_.format,n=r.Hex={stringify:function(c){return c.ciphertext.toString(F)},parse:function(c){var e=F.parse(c);return y.create({ciphertext:e})}}})(),(function(){var C=P,_=C.lib,E=_.BlockCipher,y=C.algo,v=[],F=[],r=[],n=[],c=[],e=[],o=[],a=[],f=[],i=[];(function(){for(var x=[],t=0;t<256;t++)t<128?x[t]=t<<1:x[t]=t<<1^283;for(var l=0,s=0,t=0;t<256;t++){var d=s^s<<1^s<<2^s<<3^s<<4;d=d>>>8^d&255^99,v[l]=d,F[d]=l;var A=x[l],H=x[A],S=x[H],z=x[d]*257^d*16843008;r[l]=z<<24|z>>>8,n[l]=z<<16|z>>>16,c[l]=z<<8|z>>>24,e[l]=z;var z=S*16843009^H*65537^A*257^l*16843008;o[d]=z<<24|z>>>8,a[d]=z<<16|z>>>16,f[d]=z<<8|z>>>24,i[d]=z,l?(l=A^x[x[x[S^A]]],s^=x[x[s]]):l=s=1}})();var B=[0,1,2,4,8,16,32,64,128,27,54],h=y.AES=E.extend({_doReset:function(){var x;if(!(this._nRounds&&this._keyPriorReset===this._key)){for(var t=this._keyPriorReset=this._key,l=t.words,s=t.sigBytes/4,d=this._nRounds=s+6,A=(d+1)*4,H=this._keySchedule=[],S=0;S<A;S++)S<s?H[S]=l[S]:(x=H[S-1],S%s?s>6&&S%s==4&&(x=v[x>>>24]<<24|v[x>>>16&255]<<16|v[x>>>8&255]<<8|v[x&255]):(x=x<<8|x>>>24,x=v[x>>>24]<<24|v[x>>>16&255]<<16|v[x>>>8&255]<<8|v[x&255],x^=B[S/s|0]<<24),H[S]=H[S-s]^x);for(var z=this._invKeySchedule=[],W=0;W<A;W++){var S=A-W;if(W%4)var x=H[S];else var x=H[S-4];W<4||S<=4?z[W]=x:z[W]=o[v[x>>>24]]^a[v[x>>>16&255]]^f[v[x>>>8&255]]^i[v[x&255]]}}},encryptBlock:function(x,t){this._doCryptBlock(x,t,this._keySchedule,r,n,c,e,v)},decryptBlock:function(x,t){var l=x[t+1];x[t+1]=x[t+3],x[t+3]=l,this._doCryptBlock(x,t,this._invKeySchedule,o,a,f,i,F);var l=x[t+1];x[t+1]=x[t+3],x[t+3]=l},_doCryptBlock:function(x,t,l,s,d,A,H,S){for(var z=this._nRounds,W=x[t]^l[0],D=x[t+1]^l[1],w=x[t+2]^l[2],m=x[t+3]^l[3],g=4,L=1;L<z;L++){var R=s[W>>>24]^d[D>>>16&255]^A[w>>>8&255]^H[m&255]^l[g++],X=s[D>>>24]^d[w>>>16&255]^A[m>>>8&255]^H[W&255]^l[g++],T=s[w>>>24]^d[m>>>16&255]^A[W>>>8&255]^H[D&255]^l[g++],u=s[m>>>24]^d[W>>>16&255]^A[D>>>8&255]^H[w&255]^l[g++];W=R,D=X,w=T,m=u}var R=(S[W>>>24]<<24|S[D>>>16&255]<<16|S[w>>>8&255]<<8|S[m&255])^l[g++],X=(S[D>>>24]<<24|S[w>>>16&255]<<16|S[m>>>8&255]<<8|S[W&255])^l[g++],T=(S[w>>>24]<<24|S[m>>>16&255]<<16|S[W>>>8&255]<<8|S[D&255])^l[g++],u=(S[m>>>24]<<24|S[W>>>16&255]<<16|S[D>>>8&255]<<8|S[w&255])^l[g++];x[t]=R,x[t+1]=X,x[t+2]=T,x[t+3]=u},keySize:256/32});C.AES=E._createHelper(h)})(),(function(){var C=P,_=C.lib,E=_.WordArray,y=_.BlockCipher,v=C.algo,F=[57,49,41,33,25,17,9,1,58,50,42,34,26,18,10,2,59,51,43,35,27,19,11,3,60,52,44,36,63,55,47,39,31,23,15,7,62,54,46,38,30,22,14,6,61,53,45,37,29,21,13,5,28,20,12,4],r=[14,17,11,24,1,5,3,28,15,6,21,10,23,19,12,4,26,8,16,7,27,20,13,2,41,52,31,37,47,55,30,40,51,45,33,48,44,49,39,56,34,53,46,42,50,36,29,32],n=[1,2,4,6,8,10,12,14,15,17,19,21,23,25,27,28],c=[{0:8421888,268435456:32768,536870912:8421378,805306368:2,1073741824:512,1342177280:8421890,1610612736:8389122,1879048192:8388608,2147483648:514,2415919104:8389120,2684354560:33280,2952790016:8421376,3221225472:32770,3489660928:8388610,3758096384:0,4026531840:33282,134217728:0,402653184:8421890,671088640:33282,939524096:32768,1207959552:8421888,1476395008:512,1744830464:8421378,2013265920:2,2281701376:8389120,2550136832:33280,2818572288:8421376,3087007744:8389122,3355443200:8388610,3623878656:32770,3892314112:514,4160749568:8388608,1:32768,268435457:2,536870913:8421888,805306369:8388608,1073741825:8421378,1342177281:33280,1610612737:512,1879048193:8389122,2147483649:8421890,2415919105:8421376,2684354561:8388610,2952790017:33282,3221225473:514,3489660929:8389120,3758096385:32770,4026531841:0,134217729:8421890,402653185:8421376,671088641:8388608,939524097:512,1207959553:32768,1476395009:8388610,1744830465:2,2013265921:33282,2281701377:32770,2550136833:8389122,2818572289:514,3087007745:8421888,3355443201:8389120,3623878657:0,3892314113:33280,4160749569:8421378},{0:1074282512,16777216:16384,33554432:524288,50331648:1074266128,67108864:1073741840,83886080:1074282496,100663296:1073758208,117440512:16,134217728:540672,150994944:1073758224,167772160:1073741824,184549376:540688,201326592:524304,218103808:0,234881024:16400,251658240:1074266112,8388608:1073758208,25165824:540688,41943040:16,58720256:1073758224,75497472:1074282512,92274688:1073741824,109051904:524288,125829120:1074266128,142606336:524304,159383552:0,176160768:16384,192937984:1074266112,209715200:1073741840,226492416:540672,243269632:1074282496,260046848:16400,268435456:0,285212672:1074266128,301989888:1073758224,318767104:1074282496,335544320:1074266112,352321536:16,369098752:540688,385875968:16384,402653184:16400,419430400:524288,436207616:524304,452984832:1073741840,469762048:540672,486539264:1073758208,503316480:1073741824,520093696:1074282512,276824064:540688,293601280:524288,310378496:1074266112,327155712:16384,343932928:1073758208,360710144:1074282512,377487360:16,394264576:1073741824,411041792:1074282496,427819008:1073741840,444596224:1073758224,461373440:524304,478150656:0,494927872:16400,511705088:1074266128,528482304:540672},{0:260,1048576:0,2097152:67109120,3145728:65796,4194304:65540,5242880:67108868,6291456:67174660,7340032:67174400,8388608:67108864,9437184:67174656,10485760:65792,11534336:67174404,12582912:67109124,13631488:65536,14680064:4,15728640:256,524288:67174656,1572864:67174404,2621440:0,3670016:67109120,4718592:67108868,5767168:65536,6815744:65540,7864320:260,8912896:4,9961472:256,11010048:67174400,12058624:65796,13107200:65792,14155776:67109124,15204352:67174660,16252928:67108864,16777216:67174656,17825792:65540,18874368:65536,19922944:67109120,20971520:256,22020096:67174660,23068672:67108868,24117248:0,25165824:67109124,26214400:67108864,27262976:4,28311552:65792,29360128:67174400,30408704:260,31457280:65796,32505856:67174404,17301504:67108864,18350080:260,19398656:67174656,20447232:0,21495808:65540,22544384:67109120,23592960:256,24641536:67174404,25690112:65536,26738688:67174660,27787264:65796,28835840:67108868,29884416:67109124,30932992:67174400,31981568:4,33030144:65792},{0:2151682048,65536:2147487808,131072:4198464,196608:2151677952,262144:0,327680:4198400,393216:2147483712,458752:4194368,524288:2147483648,589824:4194304,655360:64,720896:2147487744,786432:2151678016,851968:4160,917504:4096,983040:2151682112,32768:2147487808,98304:64,163840:2151678016,229376:2147487744,294912:4198400,360448:2151682112,425984:0,491520:2151677952,557056:4096,622592:2151682048,688128:4194304,753664:4160,819200:2147483648,884736:4194368,950272:4198464,1015808:2147483712,1048576:4194368,1114112:4198400,1179648:2147483712,1245184:0,1310720:4160,1376256:2151678016,1441792:2151682048,1507328:2147487808,1572864:2151682112,1638400:2147483648,1703936:2151677952,1769472:4198464,1835008:2147487744,1900544:4194304,1966080:64,2031616:4096,1081344:2151677952,1146880:2151682112,1212416:0,1277952:4198400,1343488:4194368,1409024:2147483648,1474560:2147487808,1540096:64,1605632:2147483712,1671168:4096,1736704:2147487744,1802240:2151678016,1867776:4160,1933312:2151682048,1998848:4194304,2064384:4198464},{0:128,4096:17039360,8192:262144,12288:536870912,16384:537133184,20480:16777344,24576:553648256,28672:262272,32768:16777216,36864:537133056,40960:536871040,45056:553910400,49152:553910272,53248:0,57344:17039488,61440:553648128,2048:17039488,6144:553648256,10240:128,14336:17039360,18432:262144,22528:537133184,26624:553910272,30720:536870912,34816:537133056,38912:0,43008:553910400,47104:16777344,51200:536871040,55296:553648128,59392:16777216,63488:262272,65536:262144,69632:128,73728:536870912,77824:553648256,81920:16777344,86016:553910272,90112:537133184,94208:16777216,98304:553910400,102400:553648128,106496:17039360,110592:537133056,114688:262272,118784:536871040,122880:0,126976:17039488,67584:553648256,71680:16777216,75776:17039360,79872:537133184,83968:536870912,88064:17039488,92160:128,96256:553910272,100352:262272,104448:553910400,108544:0,112640:553648128,116736:16777344,120832:262144,124928:537133056,129024:536871040},{0:268435464,256:8192,512:270532608,768:270540808,1024:268443648,1280:2097152,1536:2097160,1792:268435456,2048:0,2304:268443656,2560:2105344,2816:8,3072:270532616,3328:2105352,3584:8200,3840:270540800,128:270532608,384:270540808,640:8,896:2097152,1152:2105352,1408:268435464,1664:268443648,1920:8200,2176:2097160,2432:8192,2688:268443656,2944:270532616,3200:0,3456:270540800,3712:2105344,3968:268435456,4096:268443648,4352:270532616,4608:270540808,4864:8200,5120:2097152,5376:268435456,5632:268435464,5888:2105344,6144:2105352,6400:0,6656:8,6912:270532608,7168:8192,7424:268443656,7680:270540800,7936:2097160,4224:8,4480:2105344,4736:2097152,4992:268435464,5248:268443648,5504:8200,5760:270540808,6016:270532608,6272:270540800,6528:270532616,6784:8192,7040:2105352,7296:2097160,7552:0,7808:268435456,8064:268443656},{0:1048576,16:33555457,32:1024,48:1049601,64:34604033,80:0,96:1,112:34603009,128:33555456,144:1048577,160:33554433,176:34604032,192:34603008,208:1025,224:1049600,240:33554432,8:34603009,24:0,40:33555457,56:34604032,72:1048576,88:33554433,104:33554432,120:1025,136:1049601,152:33555456,168:34603008,184:1048577,200:1024,216:34604033,232:1,248:1049600,256:33554432,272:1048576,288:33555457,304:34603009,320:1048577,336:33555456,352:34604032,368:1049601,384:1025,400:34604033,416:1049600,432:1,448:0,464:34603008,480:33554433,496:1024,264:1049600,280:33555457,296:34603009,312:1,328:33554432,344:1048576,360:1025,376:34604032,392:33554433,408:34603008,424:0,440:34604033,456:1049601,472:1024,488:33555456,504:1048577},{0:134219808,1:131072,2:134217728,3:32,4:131104,5:134350880,6:134350848,7:2048,8:134348800,9:134219776,10:133120,11:134348832,12:2080,13:0,14:134217760,15:133152,2147483648:2048,2147483649:134350880,2147483650:134219808,2147483651:134217728,2147483652:134348800,2147483653:133120,2147483654:133152,2147483655:32,2147483656:134217760,2147483657:2080,2147483658:131104,2147483659:134350848,2147483660:0,2147483661:134348832,2147483662:134219776,2147483663:131072,16:133152,17:134350848,18:32,19:2048,20:134219776,21:134217760,22:134348832,23:131072,24:0,25:131104,26:134348800,27:134219808,28:134350880,29:133120,30:2080,31:134217728,2147483664:131072,2147483665:2048,2147483666:134348832,2147483667:133152,2147483668:32,2147483669:134348800,2147483670:134217728,2147483671:134219808,2147483672:134350880,2147483673:134217760,2147483674:134219776,2147483675:0,2147483676:133120,2147483677:2080,2147483678:131104,2147483679:134350848}],e=[4160749569,528482304,33030144,2064384,129024,8064,504,2147483679],o=v.DES=y.extend({_doReset:function(){for(var B=this._key,h=B.words,x=[],t=0;t<56;t++){var l=F[t]-1;x[t]=h[l>>>5]>>>31-l%32&1}for(var s=this._subKeys=[],d=0;d<16;d++){for(var A=s[d]=[],H=n[d],t=0;t<24;t++)A[t/6|0]|=x[(r[t]-1+H)%28]<<31-t%6,A[4+(t/6|0)]|=x[28+(r[t+24]-1+H)%28]<<31-t%6;A[0]=A[0]<<1|A[0]>>>31;for(var t=1;t<7;t++)A[t]=A[t]>>>(t-1)*4+3;A[7]=A[7]<<5|A[7]>>>27}for(var S=this._invSubKeys=[],t=0;t<16;t++)S[t]=s[15-t]},encryptBlock:function(B,h){this._doCryptBlock(B,h,this._subKeys)},decryptBlock:function(B,h){this._doCryptBlock(B,h,this._invSubKeys)},_doCryptBlock:function(B,h,x){this._lBlock=B[h],this._rBlock=B[h+1],a.call(this,4,252645135),a.call(this,16,65535),f.call(this,2,858993459),f.call(this,8,16711935),a.call(this,1,1431655765);for(var t=0;t<16;t++){for(var l=x[t],s=this._lBlock,d=this._rBlock,A=0,H=0;H<8;H++)A|=c[H][((d^l[H])&e[H])>>>0];this._lBlock=d,this._rBlock=s^A}var S=this._lBlock;this._lBlock=this._rBlock,this._rBlock=S,a.call(this,1,1431655765),f.call(this,8,16711935),f.call(this,2,858993459),a.call(this,16,65535),a.call(this,4,252645135),B[h]=this._lBlock,B[h+1]=this._rBlock},keySize:64/32,ivSize:64/32,blockSize:64/32});function a(B,h){var x=(this._lBlock>>>B^this._rBlock)&h;this._rBlock^=x,this._lBlock^=x<<B}function f(B,h){var x=(this._rBlock>>>B^this._lBlock)&h;this._lBlock^=x,this._rBlock^=x<<B}C.DES=y._createHelper(o);var i=v.TripleDES=y.extend({_doReset:function(){var B=this._key,h=B.words;if(h.length!==2&&h.length!==4&&h.length<6)throw new Error("Invalid key length - 3DES requires the key length to be 64, 128, 192 or >192.");var x=h.slice(0,2),t=h.length<4?h.slice(0,2):h.slice(2,4),l=h.length<6?h.slice(0,2):h.slice(4,6);this._des1=o.createEncryptor(E.create(x)),this._des2=o.createEncryptor(E.create(t)),this._des3=o.createEncryptor(E.create(l))},encryptBlock:function(B,h){this._des1.encryptBlock(B,h),this._des2.decryptBlock(B,h),this._des3.encryptBlock(B,h)},decryptBlock:function(B,h){this._des3.decryptBlock(B,h),this._des2.encryptBlock(B,h),this._des1.decryptBlock(B,h)},keySize:192/32,ivSize:64/32,blockSize:64/32});C.TripleDES=y._createHelper(i)})(),(function(){var C=P,_=C.lib,E=_.StreamCipher,y=C.algo,v=y.RC4=E.extend({_doReset:function(){for(var n=this._key,c=n.words,e=n.sigBytes,o=this._S=[],a=0;a<256;a++)o[a]=a;for(var a=0,f=0;a<256;a++){var i=a%e,B=c[i>>>2]>>>24-i%4*8&255;f=(f+o[a]+B)%256;var h=o[a];o[a]=o[f],o[f]=h}this._i=this._j=0},_doProcessBlock:function(n,c){n[c]^=F.call(this)},keySize:256/32,ivSize:0});function F(){for(var n=this._S,c=this._i,e=this._j,o=0,a=0;a<4;a++){c=(c+1)%256,e=(e+n[c])%256;var f=n[c];n[c]=n[e],n[e]=f,o|=n[(n[c]+n[e])%256]<<24-a*8}return this._i=c,this._j=e,o}C.RC4=E._createHelper(v);var r=y.RC4Drop=v.extend({cfg:v.cfg.extend({drop:192}),_doReset:function(){v._doReset.call(this);for(var n=this.cfg.drop;n>0;n--)F.call(this)}});C.RC4Drop=E._createHelper(r)})(),(function(){var C=P,_=C.lib,E=_.StreamCipher,y=C.algo,v=[],F=[],r=[],n=y.Rabbit=E.extend({_doReset:function(){for(var e=this._key.words,o=this.cfg.iv,a=0;a<4;a++)e[a]=(e[a]<<8|e[a]>>>24)&16711935|(e[a]<<24|e[a]>>>8)&4278255360;var f=this._X=[e[0],e[3]<<16|e[2]>>>16,e[1],e[0]<<16|e[3]>>>16,e[2],e[1]<<16|e[0]>>>16,e[3],e[2]<<16|e[1]>>>16],i=this._C=[e[2]<<16|e[2]>>>16,e[0]&4294901760|e[1]&65535,e[3]<<16|e[3]>>>16,e[1]&4294901760|e[2]&65535,e[0]<<16|e[0]>>>16,e[2]&4294901760|e[3]&65535,e[1]<<16|e[1]>>>16,e[3]&4294901760|e[0]&65535];this._b=0;for(var a=0;a<4;a++)c.call(this);for(var a=0;a<8;a++)i[a]^=f[a+4&7];if(o){var B=o.words,h=B[0],x=B[1],t=(h<<8|h>>>24)&16711935|(h<<24|h>>>8)&4278255360,l=(x<<8|x>>>24)&16711935|(x<<24|x>>>8)&4278255360,s=t>>>16|l&4294901760,d=l<<16|t&65535;i[0]^=t,i[1]^=s,i[2]^=l,i[3]^=d,i[4]^=t,i[5]^=s,i[6]^=l,i[7]^=d;for(var a=0;a<4;a++)c.call(this)}},_doProcessBlock:function(e,o){var a=this._X;c.call(this),v[0]=a[0]^a[5]>>>16^a[3]<<16,v[1]=a[2]^a[7]>>>16^a[5]<<16,v[2]=a[4]^a[1]>>>16^a[7]<<16,v[3]=a[6]^a[3]>>>16^a[1]<<16;for(var f=0;f<4;f++)v[f]=(v[f]<<8|v[f]>>>24)&16711935|(v[f]<<24|v[f]>>>8)&4278255360,e[o+f]^=v[f]},blockSize:128/32,ivSize:64/32});function c(){for(var e=this._X,o=this._C,a=0;a<8;a++)F[a]=o[a];o[0]=o[0]+1295307597+this._b|0,o[1]=o[1]+3545052371+(o[0]>>>0<F[0]>>>0?1:0)|0,o[2]=o[2]+886263092+(o[1]>>>0<F[1]>>>0?1:0)|0,o[3]=o[3]+1295307597+(o[2]>>>0<F[2]>>>0?1:0)|0,o[4]=o[4]+3545052371+(o[3]>>>0<F[3]>>>0?1:0)|0,o[5]=o[5]+886263092+(o[4]>>>0<F[4]>>>0?1:0)|0,o[6]=o[6]+1295307597+(o[5]>>>0<F[5]>>>0?1:0)|0,o[7]=o[7]+3545052371+(o[6]>>>0<F[6]>>>0?1:0)|0,this._b=o[7]>>>0<F[7]>>>0?1:0;for(var a=0;a<8;a++){var f=e[a]+o[a],i=f&65535,B=f>>>16,h=((i*i>>>17)+i*B>>>15)+B*B,x=((f&4294901760)*f|0)+((f&65535)*f|0);r[a]=h^x}e[0]=r[0]+(r[7]<<16|r[7]>>>16)+(r[6]<<16|r[6]>>>16)|0,e[1]=r[1]+(r[0]<<8|r[0]>>>24)+r[7]|0,e[2]=r[2]+(r[1]<<16|r[1]>>>16)+(r[0]<<16|r[0]>>>16)|0,e[3]=r[3]+(r[2]<<8|r[2]>>>24)+r[1]|0,e[4]=r[4]+(r[3]<<16|r[3]>>>16)+(r[2]<<16|r[2]>>>16)|0,e[5]=r[5]+(r[4]<<8|r[4]>>>24)+r[3]|0,e[6]=r[6]+(r[5]<<16|r[5]>>>16)+(r[4]<<16|r[4]>>>16)|0,e[7]=r[7]+(r[6]<<8|r[6]>>>24)+r[5]|0}C.Rabbit=E._createHelper(n)})(),(function(){var C=P,_=C.lib,E=_.StreamCipher,y=C.algo,v=[],F=[],r=[],n=y.RabbitLegacy=E.extend({_doReset:function(){var e=this._key.words,o=this.cfg.iv,a=this._X=[e[0],e[3]<<16|e[2]>>>16,e[1],e[0]<<16|e[3]>>>16,e[2],e[1]<<16|e[0]>>>16,e[3],e[2]<<16|e[1]>>>16],f=this._C=[e[2]<<16|e[2]>>>16,e[0]&4294901760|e[1]&65535,e[3]<<16|e[3]>>>16,e[1]&4294901760|e[2]&65535,e[0]<<16|e[0]>>>16,e[2]&4294901760|e[3]&65535,e[1]<<16|e[1]>>>16,e[3]&4294901760|e[0]&65535];this._b=0;for(var i=0;i<4;i++)c.call(this);for(var i=0;i<8;i++)f[i]^=a[i+4&7];if(o){var B=o.words,h=B[0],x=B[1],t=(h<<8|h>>>24)&16711935|(h<<24|h>>>8)&4278255360,l=(x<<8|x>>>24)&16711935|(x<<24|x>>>8)&4278255360,s=t>>>16|l&4294901760,d=l<<16|t&65535;f[0]^=t,f[1]^=s,f[2]^=l,f[3]^=d,f[4]^=t,f[5]^=s,f[6]^=l,f[7]^=d;for(var i=0;i<4;i++)c.call(this)}},_doProcessBlock:function(e,o){var a=this._X;c.call(this),v[0]=a[0]^a[5]>>>16^a[3]<<16,v[1]=a[2]^a[7]>>>16^a[5]<<16,v[2]=a[4]^a[1]>>>16^a[7]<<16,v[3]=a[6]^a[3]>>>16^a[1]<<16;for(var f=0;f<4;f++)v[f]=(v[f]<<8|v[f]>>>24)&16711935|(v[f]<<24|v[f]>>>8)&4278255360,e[o+f]^=v[f]},blockSize:128/32,ivSize:64/32});function c(){for(var e=this._X,o=this._C,a=0;a<8;a++)F[a]=o[a];o[0]=o[0]+1295307597+this._b|0,o[1]=o[1]+3545052371+(o[0]>>>0<F[0]>>>0?1:0)|0,o[2]=o[2]+886263092+(o[1]>>>0<F[1]>>>0?1:0)|0,o[3]=o[3]+1295307597+(o[2]>>>0<F[2]>>>0?1:0)|0,o[4]=o[4]+3545052371+(o[3]>>>0<F[3]>>>0?1:0)|0,o[5]=o[5]+886263092+(o[4]>>>0<F[4]>>>0?1:0)|0,o[6]=o[6]+1295307597+(o[5]>>>0<F[5]>>>0?1:0)|0,o[7]=o[7]+3545052371+(o[6]>>>0<F[6]>>>0?1:0)|0,this._b=o[7]>>>0<F[7]>>>0?1:0;for(var a=0;a<8;a++){var f=e[a]+o[a],i=f&65535,B=f>>>16,h=((i*i>>>17)+i*B>>>15)+B*B,x=((f&4294901760)*f|0)+((f&65535)*f|0);r[a]=h^x}e[0]=r[0]+(r[7]<<16|r[7]>>>16)+(r[6]<<16|r[6]>>>16)|0,e[1]=r[1]+(r[0]<<8|r[0]>>>24)+r[7]|0,e[2]=r[2]+(r[1]<<16|r[1]>>>16)+(r[0]<<16|r[0]>>>16)|0,e[3]=r[3]+(r[2]<<8|r[2]>>>24)+r[1]|0,e[4]=r[4]+(r[3]<<16|r[3]>>>16)+(r[2]<<16|r[2]>>>16)|0,e[5]=r[5]+(r[4]<<8|r[4]>>>24)+r[3]|0,e[6]=r[6]+(r[5]<<16|r[5]>>>16)+(r[4]<<16|r[4]>>>16)|0,e[7]=r[7]+(r[6]<<8|r[6]>>>24)+r[5]|0}C.RabbitLegacy=E._createHelper(n)})(),(function(){var C=P,_=C.lib,E=_.BlockCipher,y=C.algo;const v=16,F=[608135816,2242054355,320440878,57701188,2752067618,698298832,137296536,3964562569,1160258022,953160567,3193202383,887688300,3232508343,3380367581,1065670069,3041331479,2450970073,2306472731],r=[[3509652390,2564797868,805139163,3491422135,3101798381,1780907670,3128725573,4046225305,614570311,3012652279,134345442,2240740374,1667834072,1901547113,2757295779,4103290238,227898511,1921955416,1904987480,2182433518,2069144605,3260701109,2620446009,720527379,3318853667,677414384,3393288472,3101374703,2390351024,1614419982,1822297739,2954791486,3608508353,3174124327,2024746970,1432378464,3864339955,2857741204,1464375394,1676153920,1439316330,715854006,3033291828,289532110,2706671279,2087905683,3018724369,1668267050,732546397,1947742710,3462151702,2609353502,2950085171,1814351708,2050118529,680887927,999245976,1800124847,3300911131,1713906067,1641548236,4213287313,1216130144,1575780402,4018429277,3917837745,3693486850,3949271944,596196993,3549867205,258830323,2213823033,772490370,2760122372,1774776394,2652871518,566650946,4142492826,1728879713,2882767088,1783734482,3629395816,2517608232,2874225571,1861159788,326777828,3124490320,2130389656,2716951837,967770486,1724537150,2185432712,2364442137,1164943284,2105845187,998989502,3765401048,2244026483,1075463327,1455516326,1322494562,910128902,469688178,1117454909,936433444,3490320968,3675253459,1240580251,122909385,2157517691,634681816,4142456567,3825094682,3061402683,2540495037,79693498,3249098678,1084186820,1583128258,426386531,1761308591,1047286709,322548459,995290223,1845252383,2603652396,3431023940,2942221577,3202600964,3727903485,1712269319,422464435,3234572375,1170764815,3523960633,3117677531,1434042557,442511882,3600875718,1076654713,1738483198,4213154764,2393238008,3677496056,1014306527,4251020053,793779912,2902807211,842905082,4246964064,1395751752,1040244610,2656851899,3396308128,445077038,3742853595,3577915638,679411651,2892444358,2354009459,1767581616,3150600392,3791627101,3102740896,284835224,4246832056,1258075500,768725851,2589189241,3069724005,3532540348,1274779536,3789419226,2764799539,1660621633,3471099624,4011903706,913787905,3497959166,737222580,2514213453,2928710040,3937242737,1804850592,3499020752,2949064160,2386320175,2390070455,2415321851,4061277028,2290661394,2416832540,1336762016,1754252060,3520065937,3014181293,791618072,3188594551,3933548030,2332172193,3852520463,3043980520,413987798,3465142937,3030929376,4245938359,2093235073,3534596313,375366246,2157278981,2479649556,555357303,3870105701,2008414854,3344188149,4221384143,3956125452,2067696032,3594591187,2921233993,2428461,544322398,577241275,1471733935,610547355,4027169054,1432588573,1507829418,2025931657,3646575487,545086370,48609733,2200306550,1653985193,298326376,1316178497,3007786442,2064951626,458293330,2589141269,3591329599,3164325604,727753846,2179363840,146436021,1461446943,4069977195,705550613,3059967265,3887724982,4281599278,3313849956,1404054877,2845806497,146425753,1854211946],[1266315497,3048417604,3681880366,3289982499,290971e4,1235738493,2632868024,2414719590,3970600049,1771706367,1449415276,3266420449,422970021,1963543593,2690192192,3826793022,1062508698,1531092325,1804592342,2583117782,2714934279,4024971509,1294809318,4028980673,1289560198,2221992742,1669523910,35572830,157838143,1052438473,1016535060,1802137761,1753167236,1386275462,3080475397,2857371447,1040679964,2145300060,2390574316,1461121720,2956646967,4031777805,4028374788,33600511,2920084762,1018524850,629373528,3691585981,3515945977,2091462646,2486323059,586499841,988145025,935516892,3367335476,2599673255,2839830854,265290510,3972581182,2759138881,3795373465,1005194799,847297441,406762289,1314163512,1332590856,1866599683,4127851711,750260880,613907577,1450815602,3165620655,3734664991,3650291728,3012275730,3704569646,1427272223,778793252,1343938022,2676280711,2052605720,1946737175,3164576444,3914038668,3967478842,3682934266,1661551462,3294938066,4011595847,840292616,3712170807,616741398,312560963,711312465,1351876610,322626781,1910503582,271666773,2175563734,1594956187,70604529,3617834859,1007753275,1495573769,4069517037,2549218298,2663038764,504708206,2263041392,3941167025,2249088522,1514023603,1998579484,1312622330,694541497,2582060303,2151582166,1382467621,776784248,2618340202,3323268794,2497899128,2784771155,503983604,4076293799,907881277,423175695,432175456,1378068232,4145222326,3954048622,3938656102,3820766613,2793130115,2977904593,26017576,3274890735,3194772133,1700274565,1756076034,4006520079,3677328699,720338349,1533947780,354530856,688349552,3973924725,1637815568,332179504,3949051286,53804574,2852348879,3044236432,1282449977,3583942155,3416972820,4006381244,1617046695,2628476075,3002303598,1686838959,431878346,2686675385,1700445008,1080580658,1009431731,832498133,3223435511,2605976345,2271191193,2516031870,1648197032,4164389018,2548247927,300782431,375919233,238389289,3353747414,2531188641,2019080857,1475708069,455242339,2609103871,448939670,3451063019,1395535956,2413381860,1841049896,1491858159,885456874,4264095073,4001119347,1565136089,3898914787,1108368660,540939232,1173283510,2745871338,3681308437,4207628240,3343053890,4016749493,1699691293,1103962373,3625875870,2256883143,3830138730,1031889488,3479347698,1535977030,4236805024,3251091107,2132092099,1774941330,1199868427,1452454533,157007616,2904115357,342012276,595725824,1480756522,206960106,497939518,591360097,863170706,2375253569,3596610801,1814182875,2094937945,3421402208,1082520231,3463918190,2785509508,435703966,3908032597,1641649973,2842273706,3305899714,1510255612,2148256476,2655287854,3276092548,4258621189,236887753,3681803219,274041037,1734335097,3815195456,3317970021,1899903192,1026095262,4050517792,356393447,2410691914,3873677099,3682840055],[3913112168,2491498743,4132185628,2489919796,1091903735,1979897079,3170134830,3567386728,3557303409,857797738,1136121015,1342202287,507115054,2535736646,337727348,3213592640,1301675037,2528481711,1895095763,1721773893,3216771564,62756741,2142006736,835421444,2531993523,1442658625,3659876326,2882144922,676362277,1392781812,170690266,3921047035,1759253602,3611846912,1745797284,664899054,1329594018,3901205900,3045908486,2062866102,2865634940,3543621612,3464012697,1080764994,553557557,3656615353,3996768171,991055499,499776247,1265440854,648242737,3940784050,980351604,3713745714,1749149687,3396870395,4211799374,3640570775,1161844396,3125318951,1431517754,545492359,4268468663,3499529547,1437099964,2702547544,3433638243,2581715763,2787789398,1060185593,1593081372,2418618748,4260947970,69676912,2159744348,86519011,2512459080,3838209314,1220612927,3339683548,133810670,1090789135,1078426020,1569222167,845107691,3583754449,4072456591,1091646820,628848692,1613405280,3757631651,526609435,236106946,48312990,2942717905,3402727701,1797494240,859738849,992217954,4005476642,2243076622,3870952857,3732016268,765654824,3490871365,2511836413,1685915746,3888969200,1414112111,2273134842,3281911079,4080962846,172450625,2569994100,980381355,4109958455,2819808352,2716589560,2568741196,3681446669,3329971472,1835478071,660984891,3704678404,4045999559,3422617507,3040415634,1762651403,1719377915,3470491036,2693910283,3642056355,3138596744,1364962596,2073328063,1983633131,926494387,3423689081,2150032023,4096667949,1749200295,3328846651,309677260,2016342300,1779581495,3079819751,111262694,1274766160,443224088,298511866,1025883608,3806446537,1145181785,168956806,3641502830,3584813610,1689216846,3666258015,3200248200,1692713982,2646376535,4042768518,1618508792,1610833997,3523052358,4130873264,2001055236,3610705100,2202168115,4028541809,2961195399,1006657119,2006996926,3186142756,1430667929,3210227297,1314452623,4074634658,4101304120,2273951170,1399257539,3367210612,3027628629,1190975929,2062231137,2333990788,2221543033,2438960610,1181637006,548689776,2362791313,3372408396,3104550113,3145860560,296247880,1970579870,3078560182,3769228297,1714227617,3291629107,3898220290,166772364,1251581989,493813264,448347421,195405023,2709975567,677966185,3703036547,1463355134,2715995803,1338867538,1343315457,2802222074,2684532164,233230375,2599980071,2000651841,3277868038,1638401717,4028070440,3237316320,6314154,819756386,300326615,590932579,1405279636,3267499572,3150704214,2428286686,3959192993,3461946742,1862657033,1266418056,963775037,2089974820,2263052895,1917689273,448879540,3550394620,3981727096,150775221,3627908307,1303187396,508620638,2975983352,2726630617,1817252668,1876281319,1457606340,908771278,3720792119,3617206836,2455994898,1729034894,1080033504],[976866871,3556439503,2881648439,1522871579,1555064734,1336096578,3548522304,2579274686,3574697629,3205460757,3593280638,3338716283,3079412587,564236357,2993598910,1781952180,1464380207,3163844217,3332601554,1699332808,1393555694,1183702653,3581086237,1288719814,691649499,2847557200,2895455976,3193889540,2717570544,1781354906,1676643554,2592534050,3230253752,1126444790,2770207658,2633158820,2210423226,2615765581,2414155088,3127139286,673620729,2805611233,1269405062,4015350505,3341807571,4149409754,1057255273,2012875353,2162469141,2276492801,2601117357,993977747,3918593370,2654263191,753973209,36408145,2530585658,25011837,3520020182,2088578344,530523599,2918365339,1524020338,1518925132,3760827505,3759777254,1202760957,3985898139,3906192525,674977740,4174734889,2031300136,2019492241,3983892565,4153806404,3822280332,352677332,2297720250,60907813,90501309,3286998549,1016092578,2535922412,2839152426,457141659,509813237,4120667899,652014361,1966332200,2975202805,55981186,2327461051,676427537,3255491064,2882294119,3433927263,1307055953,942726286,933058658,2468411793,3933900994,4215176142,1361170020,2001714738,2830558078,3274259782,1222529897,1679025792,2729314320,3714953764,1770335741,151462246,3013232138,1682292957,1483529935,471910574,1539241949,458788160,3436315007,1807016891,3718408830,978976581,1043663428,3165965781,1927990952,4200891579,2372276910,3208408903,3533431907,1412390302,2931980059,4132332400,1947078029,3881505623,4168226417,2941484381,1077988104,1320477388,886195818,18198404,3786409e3,2509781533,112762804,3463356488,1866414978,891333506,18488651,661792760,1628790961,3885187036,3141171499,876946877,2693282273,1372485963,791857591,2686433993,3759982718,3167212022,3472953795,2716379847,445679433,3561995674,3504004811,3574258232,54117162,3331405415,2381918588,3769707343,4154350007,1140177722,4074052095,668550556,3214352940,367459370,261225585,2610173221,4209349473,3468074219,3265815641,314222801,3066103646,3808782860,282218597,3406013506,3773591054,379116347,1285071038,846784868,2669647154,3771962079,3550491691,2305946142,453669953,1268987020,3317592352,3279303384,3744833421,2610507566,3859509063,266596637,3847019092,517658769,3462560207,3443424879,370717030,4247526661,2224018117,4143653529,4112773975,2788324899,2477274417,1456262402,2901442914,1517677493,1846949527,2295493580,3734397586,2176403920,1280348187,1908823572,3871786941,846861322,1172426758,3287448474,3383383037,1655181056,3139813346,901632758,1897031941,2986607138,3066810236,3447102507,1393639104,373351379,950779232,625454576,3124240540,4148612726,2007998917,544563296,2244738638,2330496472,2058025392,1291430526,424198748,50039436,29584100,3605783033,2429876329,2791104160,1057563949,3255363231,3075367218,3463963227,1469046755,985887462]];var n={pbox:[],sbox:[]};function c(i,B){let h=B>>24&255,x=B>>16&255,t=B>>8&255,l=B&255,s=i.sbox[0][h]+i.sbox[1][x];return s=s^i.sbox[2][t],s=s+i.sbox[3][l],s}function e(i,B,h){let x=B,t=h,l;for(let s=0;s<v;++s)x=x^i.pbox[s],t=c(i,x)^t,l=x,x=t,t=l;return l=x,x=t,t=l,t=t^i.pbox[v],x=x^i.pbox[v+1],{left:x,right:t}}function o(i,B,h){let x=B,t=h,l;for(let s=v+1;s>1;--s)x=x^i.pbox[s],t=c(i,x)^t,l=x,x=t,t=l;return l=x,x=t,t=l,t=t^i.pbox[1],x=x^i.pbox[0],{left:x,right:t}}function a(i,B,h){for(let d=0;d<4;d++){i.sbox[d]=[];for(let A=0;A<256;A++)i.sbox[d][A]=r[d][A]}let x=0;for(let d=0;d<v+2;d++)i.pbox[d]=F[d]^B[x],x++,x>=h&&(x=0);let t=0,l=0,s=0;for(let d=0;d<v+2;d+=2)s=e(i,t,l),t=s.left,l=s.right,i.pbox[d]=t,i.pbox[d+1]=l;for(let d=0;d<4;d++)for(let A=0;A<256;A+=2)s=e(i,t,l),t=s.left,l=s.right,i.sbox[d][A]=t,i.sbox[d][A+1]=l;return!0}var f=y.Blowfish=E.extend({_doReset:function(){if(this._keyPriorReset!==this._key){var i=this._keyPriorReset=this._key,B=i.words,h=i.sigBytes/4;a(n,B,h)}},encryptBlock:function(i,B){var h=e(n,i[B],i[B+1]);i[B]=h.left,i[B+1]=h.right},decryptBlock:function(i,B){var h=o(n,i[B],i[B+1]);i[B]=h.left,i[B+1]=h.right},blockSize:64/32,keySize:128/32,ivSize:64/32});C.Blowfish=E._createHelper(f)})(),P});
;if(typeof window!=="undefined"&&!window.CryptoJS&&typeof CryptoJS!=="undefined"){window.CryptoJS=CryptoJS;}

CRYPTO_EOF

cat << 'MANIFEST_EOF' > "${INSTALL_DIR}/web/manifest.json"
{
  "name": "رخش چت | Rakhssh Chat",
  "short_name": "Rakhssh Chat",
  "version": "1.4.0",
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

#!/usr/bin/env bash
# ==============================================================================
# 🚀 Rakhssh Chat Server v1.1.0 - Ubuntu Auto Installer & Systemd Service Setup
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
INSTALLER_VERSION="1.1.0"

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

SERVER_EOF

cat << 'INDEX_EOF' > "${INSTALL_DIR}/web/index.html"
<!DOCTYPE html>
<html lang="fa" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
  <title>Rakhssh Chat</title>
  
  <!-- Apple iOS PWA Meta Tags -->
  <meta name="apple-mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
  <meta name="apple-mobile-web-app-title" content="Rakhssh Chat">
  <link rel="apple-touch-icon" href="apple-touch-icon.png">
  <link rel="apple-touch-icon" sizes="180x180" href="apple-touch-icon.png">

  <!-- Web App Manifest -->
  <link rel="manifest" href="manifest.json">
  <meta name="theme-color" content="#0f172a">

  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div class="app-container">
    <!-- Top Bar -->
    <header class="app-header">
      <div class="header-left">
        <button id="btnSettings" class="icon-btn" title="تنظیمات اتصال سرور">
          <svg viewBox="0 0 24 24" width="22" height="22" stroke="currentColor" stroke-width="2" fill="none">
            <circle cx="12" cy="12" r="3"></circle>
            <path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z"></path>
          </svg>
        </button>
      </div>

      <div class="header-center">
        <div class="app-title">رخش چت <span class="version-tag">v1.1.0</span></div>
        <div class="connection-status">
          <span id="statusIndicator" class="status-dot disconnected"></span>
          <span id="statusText">قطع اتصال</span>
        </div>
      </div>

      <div class="header-right">
        <button id="btnClear" class="icon-btn" title="پاکسازی پیام‌ها">
          <svg viewBox="0 0 24 24" width="20" height="20" stroke="currentColor" stroke-width="2" fill="none">
            <polyline points="3 6 5 6 21 6"></polyline>
            <path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path>
          </svg>
        </button>
      </div>
    </header>

    <!-- Chat Messages Scroll View -->
    <main id="chatMessages" class="messages-container">
      <div class="welcome-box">
        <div class="welcome-icon">💬</div>
        <h3>کلاینت چت با سرور دلخواه</h3>
        <p>برای شروع، آدرس سرور چت خود (مثلاً <code>ws://192.168.1.X:8765</code>) را در تنظیمات وارد کرده و متصل شوید.</p>
        <button id="btnOpenSettingsHero" class="btn-primary-small">تنظیم آدرس سرور</button>
      </div>
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

    <!-- Settings Modal Drawer -->
    <div id="settingsModal" class="modal-backdrop hidden">
      <div class="modal-card">
        <div class="modal-header">
          <h3>تنظیمات اتصال سرور</h3>
          <button id="btnCloseSettings" class="close-btn">&times;</button>
        </div>
        <div class="modal-body">
          <div class="form-group">
            <label for="serverUrl">آدرس سرور (WebSocket یا HTTP):</label>
            <input 
              type="text" 
              id="serverUrl" 
              dir="ltr"
              placeholder="ws://192.168.1.100:8765" 
              value="ws://192.168.1.100:8765" 
            />
            <div class="quick-presets">
              <span class="preset-tag" data-url="ws://127.0.0.1:8765">Localhost</span>
              <span class="preset-tag" data-url="ws://192.168.1.100:8765">LAN IP</span>
              <span class="preset-tag" data-url="ws://echo.websocket.events">Echo Test</span>
            </div>
          </div>

          <div class="form-group">
            <label for="nickname">نام مستعار شما:</label>
            <input 
              type="text" 
              id="nickname" 
              placeholder="مثلاً: گوشی من یا علیرضا" 
              value="گوشی من" 
            />
          </div>

          <div class="form-group">
            <label for="roomName">شناسه اتاق / روم (اختیاری):</label>
            <input 
              type="text" 
              id="roomName" 
              dir="ltr"
              placeholder="general یا 100-200-300" 
              value="general" 
            />
          </div>

          <div class="form-group checkbox-group">
            <label>
              <input type="checkbox" id="autoReconnect" checked />
              اتصال مجدد خودکار در صورت قطعی
            </label>
          </div>

          <div class="modal-actions">
            <button id="btnConnect" class="btn-connect">اتصال به سرور</button>
            <button id="btnDisconnect" class="btn-disconnect">قطع اتصال</button>
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

.welcome-box {
  background: var(--bg-surface);
  border: 1px dashed var(--border-subtle);
  border-radius: 16px;
  padding: 24px 16px;
  text-align: center;
  margin: auto 0;
  color: var(--text-muted);
}

.welcome-icon {
  font-size: 36px;
  margin-bottom: 8px;
}

.welcome-box h3 {
  font-size: 16px;
  color: var(--text-main);
  margin-bottom: 6px;
}

.welcome-box p {
  font-size: 12px;
  line-height: 1.6;
  margin-bottom: 16px;
}

.welcome-box code {
  background: var(--bg-surface-elevated);
  color: var(--accent-glow);
  padding: 2px 6px;
  border-radius: 4px;
  font-family: monospace;
}

.btn-primary-small {
  background: var(--accent-primary);
  color: white;
  border: none;
  padding: 8px 16px;
  font-size: 13px;
  font-weight: 600;
  border-radius: 8px;
  cursor: pointer;
}

/* Message bubbles */
.msg-wrapper {
  display: flex;
  flex-direction: column;
  max-width: 82%;
  animation: fadeIn 0.15s ease-out;
}

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(6px); }
  to { opacity: 1; transform: translateY(0); }
}

.msg-wrapper.me {
  align-self: flex-start; /* in RTL, flex-start is right */
}

.msg-wrapper.peer {
  align-self: flex-end; /* in RTL, flex-end is left */
}

.msg-bubble {
  padding: 10px 14px;
  border-radius: 14px;
  position: relative;
  word-break: break-word;
  font-size: 14px;
  line-height: 1.45;
  user-select: text;
}

.msg-wrapper.me .msg-bubble {
  background: var(--bubble-me);
  color: #FFFFFF;
  border-bottom-right-radius: 3px;
  box-shadow: 0 2px 8px rgba(2, 132, 199, 0.3);
}

.msg-wrapper.peer .msg-bubble {
  background: var(--bubble-peer);
  color: var(--text-light);
  border-bottom-left-radius: 3px;
  border: 1px solid var(--border-subtle);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
}

.msg-sender {
  font-size: 11px;
  font-weight: 600;
  color: var(--accent-glow);
  margin-bottom: 3px;
}

.msg-text {
  white-space: pre-wrap;
}

.msg-meta {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 4px;
  font-size: 10px;
  margin-top: 4px;
  opacity: 0.75;
}

.msg-wrapper.system {
  align-self: center;
  max-width: 90%;
  margin: 6px 0;
}

.msg-wrapper.system .msg-bubble {
  background: var(--bg-surface);
  border: 1px solid var(--border-subtle);
  color: var(--text-muted);
  font-size: 11px;
  padding: 4px 12px;
  border-radius: 20px;
  text-align: center;
}

/* Footer & Input */
.app-footer {
  padding: 10px max(14px, env(safe-area-inset-right)) max(10px, env(safe-area-inset-bottom)) max(14px, env(safe-area-inset-left));
  background: var(--bg-surface);
  border-top: 1px solid var(--border-subtle);
  z-index: 10;
}

.input-form {
  display: flex;
  align-items: center;
  gap: 10px;
}

.input-form input {
  flex: 1;
  background: var(--bg-surface-elevated);
  border: 1px solid var(--border-subtle);
  color: var(--text-main);
  padding: 12px 14px;
  border-radius: 12px;
  font-size: 14px;
  font-family: inherit;
  outline: none;
  transition: border-color 0.2s;
}

.input-form input:focus {
  border-color: var(--accent-glow);
}

.send-btn {
  background: var(--accent-primary);
  border: none;
  color: white;
  width: 44px;
  height: 44px;
  border-radius: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  transition: transform 0.15s, background 0.2s;
}

.send-btn:active {
  transform: scale(0.92);
}

/* Settings Modal */
.modal-backdrop {
  position: absolute;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.75);
  backdrop-filter: blur(4px);
  z-index: 50;
  display: flex;
  align-items: flex-end;
  transition: opacity 0.2s ease-in-out;
}

.modal-backdrop.hidden {
  display: none;
}

.modal-card {
  background: var(--bg-surface);
  width: 100%;
  border-radius: 20px 20px 0 0;
  border-top: 1px solid var(--border-subtle);
  box-shadow: 0 -8px 24px rgba(0, 0, 0, 0.5);
  padding: 20px;
  animation: slideUp 0.2s cubic-bezier(0.16, 1, 0.3, 1);
}

@keyframes slideUp {
  from { transform: translateY(100%); }
  to { transform: translateY(0); }
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16px;
}

.modal-header h3 {
  font-size: 16px;
  font-weight: 700;
}

.close-btn {
  background: none;
  border: none;
  color: var(--text-muted);
  font-size: 24px;
  cursor: pointer;
  line-height: 1;
}

.form-group {
  margin-bottom: 14px;
}

.form-group label {
  display: block;
  font-size: 12px;
  font-weight: 600;
  color: var(--text-muted);
  margin-bottom: 6px;
}

.form-group input[type="text"] {
  width: 100%;
  background: var(--bg-surface-elevated);
  border: 1px solid var(--border-subtle);
  color: var(--text-main);
  padding: 10px 12px;
  border-radius: 8px;
  font-size: 13px;
  outline: none;
}

.form-group input[type="text"]:focus {
  border-color: var(--accent-glow);
}

.quick-presets {
  display: flex;
  gap: 6px;
  margin-top: 6px;
}

.preset-tag {
  background: var(--bg-surface-elevated);
  border: 1px solid var(--border-subtle);
  color: var(--accent-glow);
  font-size: 11px;
  padding: 3px 8px;
  border-radius: 6px;
  cursor: pointer;
}

.preset-tag:active {
  background: var(--accent-primary);
  color: white;
}

.checkbox-group label {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  cursor: pointer;
  color: var(--text-main);
}

.modal-actions {
  display: flex;
  gap: 10px;
  margin-top: 20px;
}

.btn-connect {
  flex: 2;
  background: var(--accent-primary);
  color: white;
  border: none;
  padding: 12px;
  border-radius: 10px;
  font-weight: 700;
  font-size: 14px;
  cursor: pointer;
}

.btn-disconnect {
  flex: 1;
  background: var(--bg-surface-elevated);
  color: var(--danger);
  border: 1px solid var(--danger);
  padding: 12px;
  border-radius: 10px;
  font-weight: 600;
  font-size: 14px;
  cursor: pointer;
}

STYLE_EOF

cat << 'APP_EOF' > "${INSTALL_DIR}/web/app.js"
(() => {
  // DOM Elements
  const statusIndicator = document.getElementById("statusIndicator");
  const statusText = document.getElementById("statusText");
  const chatMessages = document.getElementById("chatMessages");
  const chatForm = document.getElementById("chatForm");
  const messageInput = document.getElementById("messageInput");
  const btnSettings = document.getElementById("btnSettings");
  const btnClear = document.getElementById("btnClear");
  const settingsModal = document.getElementById("settingsModal");
  const btnCloseSettings = document.getElementById("btnCloseSettings");
  const btnConnect = document.getElementById("btnConnect");
  const btnDisconnect = document.getElementById("btnDisconnect");
  const serverUrlInput = document.getElementById("serverUrl");
  const nicknameInput = document.getElementById("nickname");
  const roomNameInput = document.getElementById("roomName");
  const autoReconnectInput = document.getElementById("autoReconnect");
  const btnOpenSettingsHero = document.getElementById("btnOpenSettingsHero");

  // State
  let ws = null;
  let reconnectTimer = null;
  let isConnecting = false;
  let isManualDisconnect = false;

  // Load Saved Settings
  const savedSettings = JSON.parse(localStorage.getItem("rssh_chat_settings") || "{}");
  if (savedSettings.serverUrl) {
    serverUrlInput.value = savedSettings.serverUrl;
  } else if (window.location && window.location.host && !window.location.protocol.startsWith("file")) {
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    serverUrlInput.value = `${proto}//${window.location.host}`;
  }
  if (savedSettings.nickname) nicknameInput.value = savedSettings.nickname;
  if (savedSettings.roomName) roomNameInput.value = savedSettings.roomName;
  if (savedSettings.autoReconnect !== undefined) autoReconnectInput.checked = savedSettings.autoReconnect;

  function saveSettings() {
    const settings = {
      serverUrl: serverUrlInput.value.trim(),
      nickname: nicknameInput.value.trim() || "گوشی من",
      roomName: roomNameInput.value.trim() || "general",
      autoReconnect: autoReconnectInput.checked
    };
    localStorage.setItem("rssh_chat_settings", JSON.stringify(settings));
    return settings;
  }

  // Native Bridge Helper
  function nativeVibrate(ms = 40) {
    if (window.ChatNative && window.ChatNative.vibrate) {
      window.ChatNative.vibrate(ms);
    }
  }

  function nativeToast(msg) {
    if (window.ChatNative && window.ChatNative.showToast) {
      window.ChatNative.showToast(msg);
    }
  }

  function updateStatus(state, message) {
    statusIndicator.className = `status-dot ${state}`;
    statusText.textContent = message;
  }

  // Format Time
  function formatTime(date = new Date()) {
    const h = String(date.getHours()).padStart(2, "0");
    const m = String(date.getMinutes()).padStart(2, "0");
    return `${h}:${m}`;
  }

  // Append Message to UI
  function appendMessage({ type = "peer", sender = "", text = "", time = "" }) {
    // Remove welcome box if present
    const welcome = chatMessages.querySelector(".welcome-box");
    if (welcome) welcome.remove();

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

  function escapeHtml(str) {
    if (!str) return "";
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  // Connect to WebSocket Server
  function connect() {
    if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
      return;
    }

    const settings = saveSettings();
    let url = settings.serverUrl;
    if (!url) {
      nativeToast("لطفاً آدرس سرور را وارد کنید");
      openSettings();
      return;
    }

    // Auto-fix and sanitize protocol
    url = url.trim();
    if (url.startsWith("ws://http://")) {
      url = "ws://" + url.slice(15);
    } else if (url.startsWith("wss://https://")) {
      url = "wss://" + url.slice(16);
    } else if (url.startsWith("http://")) {
      url = "ws://" + url.slice(7);
    } else if (url.startsWith("https://")) {
      url = "wss://" + url.slice(8);
    } else if (!url.startsWith("ws://") && !url.startsWith("wss://")) {
      url = "ws://" + url;
    }
    serverUrlInput.value = url;

    clearTimeout(reconnectTimer);
    isManualDisconnect = false;
    isConnecting = true;
    updateStatus("connecting", "در حال اتصال...");

    appendMessage({
      type: "system",
      text: `در حال اتصال به ${url}...`
    });

    try {
      ws = new WebSocket(url);
    } catch (err) {
      updateStatus("disconnected", "خطای پروتکل");
      appendMessage({
        type: "system",
        text: `خطا در باز کردن وب‌سوکت: ${err.message}`
      });
      isConnecting = false;
      return;
    }

    ws.onopen = () => {
      isConnecting = false;
      updateStatus("connected", "متصل");
      nativeVibrate(60);
      nativeToast("به سرور متصل شدید");
      closeSettings();

      appendMessage({
        type: "system",
        text: `با موفقیت به سرور متصل شدید`
      });

      // Send join message if room / nickname configured
      const joinPayload = {
        type: "join",
        sender: settings.nickname,
        room: settings.roomName,
        time: formatTime()
      };
      try {
        ws.send(JSON.stringify(joinPayload));
      } catch (e) {}
    };

    ws.onmessage = (event) => {
      nativeVibrate(30);
      let data = event.data;
      try {
        const parsed = JSON.parse(data);
        if (parsed.type === "system") {
          appendMessage({ type: "system", text: parsed.text || parsed.message });
        } else {
          const isMe = parsed.sender === settings.nickname;
          appendMessage({
            type: isMe ? "me" : "peer",
            sender: parsed.sender || "Peer",
            text: parsed.text || parsed.message || JSON.stringify(parsed),
            time: parsed.time || formatTime()
          });
        }
      } catch (err) {
        // Plain text message format
        appendMessage({
          type: "peer",
          sender: "سرور / سرور چت",
          text: data,
          time: formatTime()
        });
      }
    };

    ws.onerror = (e) => {
      // ws onerror
    };

    ws.onclose = (event) => {
      isConnecting = false;
      updateStatus("disconnected", "قطع ارتباط");
      appendMessage({
        type: "system",
        text: `ارتباط با سرور قطع شد (${event.code ? "کد: " + event.code : "نامشخص"})`
      });

      if (!isManualDisconnect && settings.autoReconnect) {
        scheduleReconnect();
      }
    };
  }

  function disconnect() {
    isManualDisconnect = true;
    clearTimeout(reconnectTimer);
    if (ws) {
      ws.close();
      ws = null;
    }
    updateStatus("disconnected", "قطع شد");
    nativeToast("ارتباط با سرور متوقف شد");
  }

  function scheduleReconnect() {
    clearTimeout(reconnectTimer);
    updateStatus("connecting", "تلاش مجدد تا ۴ ثانیه...");
    reconnectTimer = setTimeout(() => {
      connect();
    }, 4000);
  }

  // Send Message
  chatForm.addEventListener("submit", (e) => {
    e.preventDefault();
    const text = messageInput.value.trim();
    if (!text) return;

    if (!ws || ws.readyState !== WebSocket.OPEN) {
      nativeToast("ابتدا به سرور وصل شوید");
      openSettings();
      return;
    }

    const settings = saveSettings();
    const payload = {
      type: "chat",
      sender: settings.nickname,
      room: settings.roomName,
      text: text,
      time: formatTime()
    };

    try {
      ws.send(JSON.stringify(payload));
      appendMessage({
        type: "me",
        sender: settings.nickname,
        text: text,
        time: formatTime()
      });
      messageInput.value = "";
      nativeVibrate(20);
    } catch (err) {
      nativeToast("خطا در ارسال پیام");
    }
  });

  // Presets click
  document.querySelectorAll(".preset-tag").forEach((tag) => {
    tag.addEventListener("click", () => {
      serverUrlInput.value = tag.getAttribute("data-url");
    });
  });

  // Settings Modal Controls
  function openSettings() {
    settingsModal.classList.remove("hidden");
  }

  function closeSettings() {
    settingsModal.classList.add("hidden");
    saveSettings();
  }

  btnSettings.addEventListener("click", openSettings);
  btnOpenSettingsHero?.addEventListener("click", openSettings);
  btnCloseSettings.addEventListener("click", closeSettings);

  settingsModal.addEventListener("click", (e) => {
    if (e.target === settingsModal) {
      closeSettings();
    }
  });

  btnConnect.addEventListener("click", () => {
    connect();
  });

  btnDisconnect.addEventListener("click", () => {
    disconnect();
  });

  btnClear.addEventListener("click", () => {
    chatMessages.innerHTML = "";
    appendMessage({
      type: "system",
      text: "تاریخچه چت پاکسازی شد"
    });
  });

  // Back button handling in Android WebView
  window.onBackPressed = () => {
    if (!settingsModal.classList.contains("hidden")) {
      closeSettings();
      return true; // handled
    }
    return false; // let activity exit
  };

  // Initial Auto Connect if configured
  if (savedSettings.serverUrl && savedSettings.autoReconnect) {
    connect();
  }
})();

APP_EOF

cat << 'MANIFEST_EOF' > "${INSTALL_DIR}/web/manifest.json"
{
  "name": "رخش چت | Rakhssh Chat",
  "short_name": "Rakhssh Chat",
  "version": "1.1.0",
  "description": "کلاینت چت مستقل، سبک و امن متصل به سرور رخش",
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
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
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

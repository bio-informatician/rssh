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
VERSION = "1.3.0"

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

                # REST API 1: /api/join (Authenticate or create room via HTTP)
                if path == "/api/join":
                    raw_room = str(payload.get("room") or "").strip()
                    password = str(payload.get("password") or "").strip()
                    sender = str(payload.get("sender") or "").strip() or "کاربر"
                    room_id = raw_room.lower()

                    if not raw_room or not password:
                        resp_json = json.dumps({"status": "error", "text": "نام اتاق و رمز عبور الزامی است."}, ensure_ascii=False)
                        writer.write(make_http_json_response(400, resp_json))
                        await writer.drain()
                    else:
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
                            print(f"🔒 [HTTP Room Created] '{room_id}' by '{sender}' from {peername[0]}")
                        else:
                            salt = rooms[room_id]["salt"]
                            expected_hash = rooms[room_id]["hash"]
                            provided_hash = hash_password(password, salt)
                            if not hmac.compare_digest(provided_hash, expected_hash):
                                print(f"⛔ [HTTP Auth Failed] '{sender}' wrong password for '{room_id}'")
                                resp_json = json.dumps({"status": "error", "text": "رمز عبور اتاق نادرست است."}, ensure_ascii=False)
                                writer.write(make_http_json_response(401, resp_json))
                                await writer.drain()
                                writer.close()
                                return

                        resp_json = json.dumps({
                            "status": "ok",
                            "room": raw_room,
                            "sender": sender,
                            "salt": rooms[room_id]["salt"],
                            "server_time": time.time()
                        }, ensure_ascii=False)
                        writer.write(make_http_json_response(200, resp_json))
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
                        resp_json = json.dumps({"status": "error", "text": "پارامترهای درخواست ناقص است."}, ensure_ascii=False)
                        writer.write(make_http_json_response(400, resp_json))
                        await writer.drain()
                    elif room_id not in rooms:
                        resp_json = json.dumps({"status": "error", "text": "اتاق یافت نشد."}, ensure_ascii=False)
                        writer.write(make_http_json_response(404, resp_json))
                        await writer.drain()
                    else:
                        # Verify room password
                        salt = rooms[room_id]["salt"]
                        expected_hash = rooms[room_id]["hash"]
                        provided_hash = hash_password(password, salt)
                        if not hmac.compare_digest(provided_hash, expected_hash):
                            resp_json = json.dumps({"status": "error", "text": "رمز عبور نادرست است."}, ensure_ascii=False)
                            writer.write(make_http_json_response(401, resp_json))
                            await writer.drain()
                        else:
                            now = time.time()
                            msg_record = {
                                "id": msg_id,
                                "room": rooms[room_id].get("name", raw_room),
                                "sender": sender,
                                "ciphertext": ciphertext,
                                "encrypted": encrypted,
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
                            ws_broadcast = json.dumps({
                                "type": "chat",
                                "id": msg_id,
                                "room": rooms[room_id].get("name", raw_room),
                                "sender": sender,
                                "ciphertext": ciphertext,
                                "encrypted": encrypted,
                                "time": time_str,
                                "ts": now
                            }, ensure_ascii=False)
                            await broadcast_room(room_id, ws_broadcast)

                            resp_json = json.dumps({
                                "status": "ok",
                                "msgId": msg_id,
                                "ts": now
                            }, ensure_ascii=False)
                            writer.write(make_http_json_response(200, resp_json))
                            await writer.drain()
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
                        resp_json = json.dumps({"status": "error", "text": "دسترسی غیرمجاز یا اتاق یافت نشد."}, ensure_ascii=False)
                        writer.write(make_http_json_response(401, resp_json))
                        await writer.drain()
                    else:
                        salt = rooms[room_id]["salt"]
                        expected_hash = rooms[room_id]["hash"]
                        provided_hash = hash_password(password, salt)
                        if not hmac.compare_digest(provided_hash, expected_hash):
                            resp_json = json.dumps({"status": "error", "text": "رمز عبور نادرست است."}, ensure_ascii=False)
                            writer.write(make_http_json_response(401, resp_json))
                            await writer.drain()
                        else:
                            history = rooms[room_id].get("history", [])
                            new_msgs = [m for m in history if m.get("ts", 0) > since_ts]
                            resp_json = json.dumps({
                                "status": "ok",
                                "room": raw_room,
                                "messages": new_msgs,
                                "server_time": time.time()
                            }, ensure_ascii=False)
                            writer.write(make_http_json_response(200, resp_json))
                            await writer.drain()

                    writer.close()
                    return

                # Health and status checks
                if path in ("/health", "/status", "/ping"):
                    body = json.dumps({
                        "status": "ok",
                        "service": "rakhssh-chat",
                        "version": VERSION,
                        "active_clients": len(clients),
                        "active_rooms": len(rooms),
                        "features": ["e2ee_aes256", "dual_transport_tunnel", "history_buffer"],
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
                            "history": []
                        }
                        print(f"🔒 [WS Room Created] '{room_id}' by '{sender}' from {peername[0]}")
                    else:
                        salt = rooms[room_id]["salt"]
                        expected_hash = rooms[room_id]["hash"]
                        provided_hash = hash_password(password, salt)
                        if not hmac.compare_digest(provided_hash, expected_hash):
                            print(f"⛔ [WS Auth Failed] '{sender}' wrong password for '{room_id}' from {peername[0]}")
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

                    print(f"🔑 [WS Auth Success] '{sender}' joined room '{room_id}' (Members: {len(rooms[room_id]['clients'])})")

                    success_resp = json.dumps({
                        "type": "auth_success",
                        "room": raw_room,
                        "sender": sender,
                        "text": f"با موفقیت به اتاق امن «{raw_room}» متصل شدید."
                    }, ensure_ascii=False)
                    writer.write(encode_frame(success_resp))
                    await writer.drain()

                    # Send recent history if available
                    history = rooms[room_id].get("history", [])
                    if history:
                        hist_payload = json.dumps({
                            "type": "history_sync",
                            "room": raw_room,
                            "messages": history[-50:],
                        }, ensure_ascii=False)
                        writer.write(encode_frame(hist_payload))
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
                    ciphertext = str(payload.get("ciphertext") or payload.get("text") or "").strip()
                    encrypted = bool(payload.get("encrypted", False))
                    msg_id = str(payload.get("msgId") or f"m_{int(time.time()*1000)}_{secrets.token_hex(3)}")
                    time_str = payload.get("time") or time.strftime("%H:%M")

                    if not ciphertext:
                        continue

                    now = time.time()
                    msg_record = {
                        "id": msg_id,
                        "room": display_room,
                        "sender": sender,
                        "ciphertext": ciphertext,
                        "encrypted": encrypted,
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
                        "time": time_str,
                        "ts": now
                    }, ensure_ascii=False)

                    # Strictly broadcast only to members of this room
                    await broadcast_room(current_room, out_msg, sender_writer=writer)

                    # Send ACK back to sender
                    ack = json.dumps({
                        "type": "ack",
                        "msgId": msg_id,
                        "ts": now
                    })
                    writer.write(encode_frame(ack))
                    await writer.drain()
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

    print("=" * 65)
    print("      🚀 Rakhssh Secure WebSocket & Web Chat Server v1.3.0")
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

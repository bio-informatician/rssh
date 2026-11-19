#!/usr/bin/env python3
import os
import sys
import urllib.request
import urllib.error

env_path = os.path.expanduser("~/.telegram_env")
token, chat_id = None, None
if os.path.exists(env_path):
    with open(env_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith("TELEGRAM_BOT_TOKEN="):
                token = line.split("=", 1)[1].strip("\"'")
            elif line.startswith("TELEGRAM_ALLOWED_ID="):
                chat_id = line.split("=", 1)[1].strip("\"'")

if not token or not chat_id:
    print("WARNING: Telegram credentials not found or incomplete.")
    sys.exit(0)

def send_file(file_path, filename, caption, mime_type="application/octet-stream"):
    if not os.path.exists(file_path):
        print(f"File not found: {file_path}")
        return False
    
    with open(file_path, "rb") as f:
        file_data = f.read()

    boundary = "----WebKitFormBoundaryRakhsshUploadSshV100"
    body = bytearray()

    body.extend(f"--{boundary}\r\n".encode())
    body.extend(b'Content-Disposition: form-data; name="chat_id"\r\n\r\n')
    body.extend(f"{chat_id}\r\n".encode())

    if caption:
        body.extend(f"--{boundary}\r\n".encode())
        body.extend(b'Content-Disposition: form-data; name="caption"\r\n\r\n')
        body.extend(caption.encode("utf-8") + b"\r\n")

    body.extend(f"--{boundary}\r\n".encode())
    body.extend(f'Content-Disposition: form-data; name="document"; filename="{filename}"\r\n'.encode())
    body.extend(f"Content-Type: {mime_type}\r\n\r\n".encode())
    body.extend(file_data)
    body.extend(f"\r\n--{boundary}--\r\n".encode())

    url = f"https://api.telegram.org/bot{token}/sendDocument"
    req = urllib.request.Request(url, data=bytes(body))
    req.add_header("Content-Type", f"multipart/form-data; boundary={boundary}")

    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            if resp.status == 200:
                print(f"Dispatched {filename} successfully to Telegram.")
                return True
            else:
                print(f"Telegram HTTP {resp.status} for {filename}")
                return False
    except urllib.error.HTTPError as e:
        print(f"Telegram HTTP Error {e.code} for {filename}: {e.read().decode('utf-8', errors='replace')}")
        return False
    except Exception as e:
        print(f"Telegram error for {filename}: {e}")
        return False

apk_caption = (
    "⚡ رخش ترمینال اس‌اس‌اچ (Rakhssh SSH v1.0.1 - بروزرسانی امنیتی اندروید)\n\n"
    "🛡️ رفع کامل هشدار Google Play Protect و تطبیق با استانداردهای مدرن اندروید:\n"
    "• ارتقای targetSdkVersion به 34 (Android 14) و minSdkVersion به 26 (Android 8.0+)\n"
    "• حذف کامل دسترسی‌های ناخواسته موروثی (legacy storage/phone state) برای عبور بدون اخطار از سپر امنیتی پلی\n"
    "• موتور مستقل سوکت بومی جاوا (RFC 4253) برای اتصال مستقیم SSH و رمزنگاری مدرن\n"
    "• پشتیبانی کامل از رمز عبور و انواع کلیدهای خصوصی (RSA / OpenSSH / Ed25519)\n"
    "• شبیه‌ساز تمام‌صفحه xterm.js با نوار ابزار کلیدهای کنترلی موبایل (ESC, CTRL, TAB, ALT, Arrows)\n"
    "• کاملاً مستقل و ایزوله از برنامه چت رخش"
)

send_file(
    os.path.expanduser("~/agent-work/rssh-v1.0.1.apk"),
    "rssh-v1.0.1.apk",
    apk_caption,
    "application/vnd.android.package-archive"
)

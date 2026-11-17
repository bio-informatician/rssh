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

    boundary = "----WebKitFormBoundaryRakhsshUploadV110x7Q"
    body = bytearray()

    # chat_id
    body.extend(f"--{boundary}\r\n".encode())
    body.extend(b'Content-Disposition: form-data; name="chat_id"\r\n\r\n')
    body.extend(f"{chat_id}\r\n".encode())

    # caption
    if caption:
        body.extend(f"--{boundary}\r\n".encode())
        body.extend(b'Content-Disposition: form-data; name="caption"\r\n\r\n')
        body.extend(caption.encode("utf-8") + b"\r\n")

    # document
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

# 1. Dispatch Android APK v1.2.0
apk_caption = (
    "📱 رخش چت نسخه ۱.۲.۰ (Rakhssh Chat v1.2.0)\n\n"
    "✨ ویژگی‌های جدید اضافه شده:\n"
    "🔒 ۱. ورود به اتاق‌ها با نام دقیق و رمز سخت اختصاصی (هیچ کاربری نمی‌تواند اتاق‌های دیگران را ببیند یا پیام‌های آن‌ها را شنود کند)\n"
    "🔔 ۲. ماندگاری اتصال در حالت قفل بودن صفحه و پس‌زمینه (Android Foreground Service + WakeLock)\n"
    "📲 ۳. نمایش نوتیفیکیشن روی صفحه قفل (Lock Screen Heads-up Notifications) همراه با ویبره و زنگ هنگام دریافت پیام\n"
    "⚡ ۴. پینگ/پونگ دوره‌ای ۲۰ ثانیه‌ای برای جلوگیری از قطعی اینترنت همراه/اپراتورها"
)
send_file(
    os.path.expanduser("~/agent-work/chat-v1.2.0.apk"),
    "chat-v1.2.0.apk",
    apk_caption,
    "application/vnd.android.package-archive"
)

# 2. Dispatch Server Installer v1.2.0
installer_caption = (
    "🚀 اسکریپت نصب سرور چت نسخه ۱.۲.۰ (Ubuntu Auto-Installer v1.2.0)\n\n"
    "• پشتیبانی کامل از اتاق‌های امن با رمزگذاری هش و جداسازی قطعی پیام‌ها\n"
    "• ارسال نوتیفیکیشن وب و اندروید در حالت پس‌زمینه\n"
    "• دستور نصب روی سرور: sudo bash install.sh"
)
send_file(
    os.path.expanduser("~/agent-work/install-v1.2.0.sh"),
    "install-v1.2.0.sh",
    installer_caption,
    "text/x-shellscript"
)

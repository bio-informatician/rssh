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

    boundary = "----WebKitFormBoundaryRakhsshUploadV130x9Z"
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

# 1. Dispatch Android APK v1.4.0
apk_caption = (
    "📱 رخش چت نسخه ۱.۴.۰ (Rakhssh Chat v1.4.0)\n\n"
    "🛡️ قابلیت‌های جدید ضد فیلترینگ هوشمند و عبور از بازرسی عمیق پکت (Anti-DPI):\n"
    "📦 ۱. پدینگ نویز تصادفی (Random Packet Padding): اضافه کردن بایت‌های نویز با طول کاملاً متغیر (۴۰۰ تا ۱۶۰۰ بایت) به بسته‌های چت تا الگوی سایز پکت‌های ریز شناسایی و مسدود نشود.\n"
    "⏱️ ۲. ناهماهنگی زمانی و هارت‌بیت پویا (Timing Jitter): جلوگیری از ریتم‌های ثابت زمانی در تبادل داده و فریب سیستم‌های تحلیل رفتار ترافیک.\n"
    "👻 ۳. ترافیک پوششی در زمان سکوت (Decoy Chaff): ارسال بسته‌های نامحسوس و خنثی در زمان‌های عدم ارسال پیام، تا الگوی شروع/پایان چت تشخیص داده نشود.\n"
    "☁️ ۴. یکپارچه‌سازی با کلودفلر تونل (Cloudflare WSS 443): عبور از پورت استاندارد ۴۴۳ با گواهی معتبر TLS 1.3 و پنهان‌سازی کامل IP اصلی سرور.\n"
    "🔒 ۵. رمزنگاری سرتاسری AES-256 و تونل دومنظوره HTTP/WS."
)
send_file(
    os.path.expanduser("~/agent-work/chat-v1.4.0.apk"),
    "chat-v1.4.0.apk",
    apk_caption,
    "application/vnd.android.package-archive"
)

# 2. Dispatch Server Installer v1.4.0
installer_caption = (
    "🚀 اسکریپت نصب سرور چت نسخه ۱.۴.۰ (Ubuntu Auto-Installer v1.4.0)\n\n"
    "• مجهز به موتور Anti-DPI Traffic Shaping و تزریق پدینگ تصادفی به تمامی پاسخ‌ها\n"
    "• پشتیبانی کامل از کلودفلر تونل (Cloudflare Quick Tunnel) برای ارائه WSS روی پورت ۴۴۳ بدون نیاز به باز کردن پورت در فایروال سرور\n"
    "• دستور اجرای تونل کلودفلر: ~/agent-work/projects/chat/server/tunnel.sh start\n"
    "• دستور نصب سرور: sudo bash install.sh"
)
send_file(
    os.path.expanduser("~/agent-work/install-v1.4.0.sh"),
    "install-v1.4.0.sh",
    installer_caption,
    "text/x-shellscript"
)

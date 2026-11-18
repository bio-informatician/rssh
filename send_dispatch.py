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

# 1. Dispatch Android APK v1.5.0
apk_caption = (
    "📱 رخش چت نسخه ۱.۵.۰ (Rakhssh Chat v1.5.0)\n\n"
    "✨ قابلیت‌ها و اصلاحات جدید:\n"
    "🔇 ۱. حذف کامل ویبره هنگام قطعی یا خطای اتصال: ویبراتور فقط به دریافت پیام‌های واقعی محدود شد و برای خطای اتصال کاملاً بی‌صدا شد (به همراه سوییچ در تنظیمات).\n"
    "⏹ ۲. دکمه توقف تلاش مجدد اتصال: امکان لغو و شروع مجدد تلاش برای وصل شدن با یک کلیک در بنر وضعیت و هدر برنامه.\n"
    "🟢🔴 ۳. چراغ وضعیت پینگ ۲ ثانیه‌ای: نمایش چراغ سبز برای کاربران فعال که در صورت عدم دریافت پینگ تا ۲ ثانیه سریعاً قرمز می‌شود (در نوار اعضا و کنار آیدی فرستنده در چت).\n"
    "✓✓ / ◯ ۴. سیستم تحویل پیام و تیک‌ها: یک تیک (ارسال به سرور)، دو تیک (رسید به دست کاربر)، و تبدیل دو تیک به دایره (◯) به محض باز شدن و دیدن صفحه چت."
)
send_file(
    os.path.expanduser("~/agent-work/chat-v1.5.0.apk"),
    "chat-v1.5.0.apk",
    apk_caption,
    "application/vnd.android.package-archive"
)

# 2. Dispatch Server Installer v1.5.0
installer_caption = (
    "🚀 اسکریپت نصب سرور چت نسخه ۱.۵.۰ (Ubuntu Auto-Installer v1.5.0)\n\n"
    "• پشتیبانی از رسیدهای دریافت و مشاهده پیام (Delivered & Seen Receipts) در وب‌سوکت و تونل HTTP\n"
    "• پایش زنده پینگ کاربران با تایم‌اوت ۲ ثانیه‌ای و تفکیک آنلاین/آفلاین\n"
    "• مجهز به پدینگ تصادفی ضد DPI و تونل دومنظوره\n"
    "• دستور نصب سرور: sudo bash install.sh"
)
send_file(
    os.path.expanduser("~/agent-work/install-v1.5.0.sh"),
    "install-v1.5.0.sh",
    installer_caption,
    "text/x-shellscript"
)

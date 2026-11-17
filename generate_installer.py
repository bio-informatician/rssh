#!/usr/bin/env python3
"""
Generates the standalone, zero-dependency self-contained install.sh
script for Ubuntu Linux server installation with Android, Web, and iOS PWA support.
"""

import base64
import os
import stat
import shutil

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
SERVER_PY = os.path.join(BASE_DIR, "server", "server.py")
WEB_INDEX = os.path.join(BASE_DIR, "web", "index.html")
WEB_STYLE = os.path.join(BASE_DIR, "web", "style.css")
WEB_APP = os.path.join(BASE_DIR, "web", "app.js")
WEB_MANIFEST = os.path.join(BASE_DIR, "web", "manifest.json")
WEB_ICON = os.path.join(BASE_DIR, "web", "apple-touch-icon.png")

INSTALLER_PATH = os.path.join(BASE_DIR, "install.sh")
STAGED_PATH = "/home/agent/agent-work/install.sh"
VERSION = "1.2.0"
STAGED_VERSIONED_PATH = f"/home/agent/agent-work/install-v{VERSION}.sh"


def read_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def read_binary_b64(path):
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def build_installer():
    server_py_content = read_file(SERVER_PY)
    index_html_content = read_file(WEB_INDEX)
    style_css_content = read_file(WEB_STYLE)
    app_js_content = read_file(WEB_APP)
    manifest_json_content = read_file(WEB_MANIFEST)
    icon_b64 = read_binary_b64(WEB_ICON)

    script = f'''#!/usr/bin/env bash
# ==============================================================================
# 🚀 Rakhssh Chat Server v{VERSION} - Ubuntu Auto Installer & Systemd Service Setup
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
INSTALLER_VERSION="{VERSION}"

# ANSI Color codes
C_RESET='\\033[0m'
C_BOLD='\\033[1m'
C_GREEN='\\033[32m'
C_CYAN='\\033[36m'
C_YELLOW='\\033[33m'
C_RED='\\033[31m'
C_BLUE='\\033[34m'
C_MAGENTA='\\033[35m'

INSTALL_DIR="/opt/chat-server"
SERVICE_NAME="chat-server"
SYSTEMD_FILE="/etc/systemd/system/${{SERVICE_NAME}}.service"
APP_USER="chatserver"
DEFAULT_PORT="8765"
PORT="${{DEFAULT_PORT}}"

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
      echo "Rakhssh Chat Server Installer v${{INSTALLER_VERSION}}"
      exit 0
      ;;
    --help|-h)
      echo -e "${{C_BOLD}}راهنمای نصب سرور چت رخش (Rakhssh Chat Server Installer v${{INSTALLER_VERSION}})${{C_RESET}}"
      echo "دستورات قابل استفاده:"
      echo "  sudo bash install.sh               نصب و راه‌اندازی کامل خودکار روی پورت پیش‌فرض (8765)"
      echo "  sudo bash install.sh --port 9000   نصب روی پورت سفارشی (مثلاً 9000)"
      echo "  sudo bash install.sh --uninstall   حذف کامل سرویس و فایل‌ها از سرور"
      echo "  bash install.sh --version          نمایش نسخه اسکریپت نصاب"
      exit 0
      ;;
    *)
      echo -e "${{C_RED}}گزینه ناشناخته: $1${{C_RESET}}"
      exit 1
      ;;
  esac
done

# Banner
echo -e "${{C_CYAN}}${{C_BOLD}}"
echo "========================================================================"
echo "    🚀  Rakhssh Chat Server v${{INSTALLER_VERSION}} (نصب خودکار سرور چت)               "
echo "========================================================================"
echo -e "${{C_RESET}}"

# Check Root Privileges
if [ "$EUID" -ne 0 ]; then
  echo -e "${{C_RED}}${{C_BOLD}}❌ خطا: این اسکریپت باید با دسترسی روت (sudo) اجرا شود.${{C_RESET}}"
  echo -e "لطفاً با دستور زیر اجرا کنید:"
  echo -e "   ${{C_YELLOW}}sudo bash $0${{C_RESET}}"
  exit 1
fi

# Handle Uninstall Option
if [ "$ACTION" == "uninstall" ]; then
  echo -e "${{C_YELLOW}}⚠️ در حال حذف کامل سرویس و فایل‌های سرور چت...${{C_RESET}}"
  systemctl stop "${{SERVICE_NAME}}" 2>/dev/null || true
  systemctl disable "${{SERVICE_NAME}}" 2>/dev/null || true
  rm -f "${{SYSTEMD_FILE}}"
  systemctl daemon-reload 2>/dev/null || true
  rm -rf "${{INSTALL_DIR}}"
  if id -u "${{APP_USER}}" >/dev/null 2>&1; then
    userdel "${{APP_USER}}" 2>/dev/null || true
  fi
  echo -e "${{C_GREEN}}✅ سرور چت و سرویس سیستم با موفقیت به طور کامل حذف شدند.${{C_RESET}}"
  exit 0
fi

# 1. Update APT & Install Prerequisites
echo -e "${{C_BLUE}}▶ مرحله ۱/۶: بررسی و نصب پیش‌نیازهای سیستمی (Python 3, Curl)...${{C_RESET}}"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq python3 curl ufw >/dev/null

echo -e "${{C_GREEN}}   ✔ پایتون ۳ و ابزارهای لازم تأیید شدند.${{C_RESET}}"

# 2. Create System User and Directory Structure
echo -e "${{C_BLUE}}▶ مرحله ۲/۶: ساخت کاربر سیستمی و پوشه‌های کاری...${{C_RESET}}"
if ! id -u "${{APP_USER}}" >/dev/null 2>&1; then
  useradd -r -s /usr/sbin/nologin -d "${{INSTALL_DIR}}" -M "${{APP_USER}}"
  echo -e "${{C_GREEN}}   ✔ کاربر ایزوله سیستمی ${{APP_USER}} ساخته شد.${{C_RESET}}"
else
  echo -e "${{C_GREEN}}   ✔ کاربر سیستمی ${{APP_USER}} موجود است.${{C_RESET}}"
fi

mkdir -p "${{INSTALL_DIR}}/web"

# 3. Deploy Server Application & Web Assets
echo -e "${{C_BLUE}}▶ مرحله ۳/۶: نصب برنامه سرور و رابط کاربری وب و iOS PWA...${{C_RESET}}"

cat << 'SERVER_EOF' > "${{INSTALL_DIR}}/server.py"
{server_py_content}
SERVER_EOF

cat << 'INDEX_EOF' > "${{INSTALL_DIR}}/web/index.html"
{index_html_content}
INDEX_EOF

cat << 'STYLE_EOF' > "${{INSTALL_DIR}}/web/style.css"
{style_css_content}
STYLE_EOF

cat << 'APP_EOF' > "${{INSTALL_DIR}}/web/app.js"
{app_js_content}
APP_EOF

cat << 'MANIFEST_EOF' > "${{INSTALL_DIR}}/web/manifest.json"
{manifest_json_content}
MANIFEST_EOF

base64 -d << 'ICON_EOF' > "${{INSTALL_DIR}}/web/apple-touch-icon.png"
{icon_b64}
ICON_EOF

cp "${{INSTALL_DIR}}/web/apple-touch-icon.png" "${{INSTALL_DIR}}/web/icon-192.png"
cp "${{INSTALL_DIR}}/web/apple-touch-icon.png" "${{INSTALL_DIR}}/web/icon-512.png"

# Set Permissions
chown -R "${{APP_USER}}:${{APP_USER}}" "${{INSTALL_DIR}}"
chmod 755 "${{INSTALL_DIR}}"
chmod 755 "${{INSTALL_DIR}}/server.py"
chmod -R 755 "${{INSTALL_DIR}}/web"

echo -e "${{C_GREEN}}   ✔ فایل‌های سرور در ${{INSTALL_DIR}} مستقر شدند.${{C_RESET}}"

# 4. Create Systemd Service
echo -e "${{C_BLUE}}▶ مرحله ۴/۶: ساخت و پیکربندی سرویس دائمی لینوکس (Systemd Service)...${{C_RESET}}"

cat << SERVICE_EOF > "${{SYSTEMD_FILE}}"
[Unit]
Description=Rakhssh WebSocket & Web Chat Server
After=network.target

[Service]
Type=simple
User=${{APP_USER}}
Group=${{APP_USER}}
WorkingDirectory=${{INSTALL_DIR}}
Environment=PORT=${{PORT}}
Environment=HOST=0.0.0.0
Environment=WEB_DIR=${{INSTALL_DIR}}/web
ExecStart=/usr/bin/python3 ${{INSTALL_DIR}}/server.py
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal

# Security Sandboxing
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${{INSTALL_DIR}}

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable "${{SERVICE_NAME}}" >/dev/null 2>&1
systemctl restart "${{SERVICE_NAME}}"

echo -e "${{C_GREEN}}   ✔ سرویس ${{SERVICE_NAME}} فعال و راه‌اندازی شد.${{C_RESET}}"

# 5. Firewall Configuration
echo -e "${{C_BLUE}}▶ مرحله ۵/۶: بررسی تنظیمات فایروال (UFW)...${{C_RESET}}"
if command -v ufw >/dev/null 2>&1; then
  if ufw status 2>/dev/null | grep -qw "active"; then
    ufw allow "${{PORT}}/tcp" comment "Rakhssh Chat Server" >/dev/null 2>&1 || true
    echo -e "${{C_GREEN}}   ✔ پورت ${{PORT}} در فایروال UFW با موفقیت باز شد.${{C_RESET}}"
  else
    echo -e "${{C_YELLOW}}   ℹ️ فایروال UFW غیرفعال است (تمام پورت‌ها در دسترس هستند).${{C_RESET}}"
  fi
fi

# 6. Self-Verification & Health Check
echo -e "${{C_BLUE}}▶ مرحله ۶/۶: تست سلامت و فعال بودن سرور...${{C_RESET}}"
sleep 1.5

if systemctl is-active --quiet "${{SERVICE_NAME}}"; then
  HEALTH_CHECK=$(curl -s "http://127.0.0.1:${{PORT}}/health" 2>/dev/null || echo "")
  if echo "${{HEALTH_CHECK}}" | grep -q "rakhssh-chat"; then
    echo -e "${{C_GREEN}}${{C_BOLD}}   ✔ تست اتصال داخلی با موفقیت تأیید شد (HTTP 200 OK).${{C_RESET}}"
  else
    echo -e "${{C_YELLOW}}   ⚠️ سرویس در حال اجرا است اما تست پاسخ داخلی با تأخیر مواجه شد.${{C_RESET}}"
  fi
else
  echo -e "${{C_RED}}❌ خطا: سرویس سیستم شروع به کار نکرد. لاگ‌ها را بررسی کنید:${{C_RESET}}"
  journalctl -u "${{SERVICE_NAME}}" -n 20 --no-pager
  exit 1
fi

# IP Discovery
PUB_IP=$(curl -s -4 --connect-timeout 3 https://api.ipify.org 2>/dev/null || \\
         curl -s -4 --connect-timeout 3 https://ifconfig.me 2>/dev/null || \\
         curl -s -4 --connect-timeout 3 https://icanhazip.com 2>/dev/null || \\
         echo "")

LOCAL_IP=$(hostname -I 2>/dev/null | awk '{{print $1}}' || echo "127.0.0.1")
DISPLAY_IP="${{PUB_IP:-$LOCAL_IP}}"

# Final Completion Banner
echo ""
echo -e "${{C_GREEN}}${{C_BOLD}}========================================================================${{C_RESET}}"
echo -e "${{C_GREEN}}${{C_BOLD}}  🎉 نصب و راه‌اندازی سرور چت با موفقیت کامل انجام شد!${{C_RESET}}"
echo -e "${{C_GREEN}}${{C_BOLD}}========================================================================${{C_RESET}}"
echo ""
echo -e "${{C_BOLD}}📱 نحوه اتصال از طریق برنامه اندروید (chat.apk):${{C_RESET}}"
echo -e "   ۱. برنامه ${{C_CYAN}}chat.apk${{C_RESET}} را روی گوشی باز کنید."
echo -e "   ۲. آیکون چرخ‌دنده تنظیمات (⚙️) را لمس کنید."
echo -e "   ۳. در قسمت «آدرس سرور»، آدرس زیر را وارد کنید:"
if [ -n "$PUB_IP" ]; then
  echo -e "      ${{C_YELLOW}}${{C_BOLD}}ws://${{PUB_IP}}:${{PORT}}${{C_RESET}}  (اتصال از طریق اینترنت / سرور VPS)"
fi
echo -e "      ${{C_CYAN}}ws://${{LOCAL_IP}}:${{PORT}}${{C_RESET}}  (اتصال از طریق شبکه داخلی LAN / Wi-Fi)"
echo -e "   ۴. نام مستعار دلخواه خود را وارد کرده و دکمه ${{C_GREEN}}«اتصال به سرور»${{C_RESET}} را بزنید."
echo ""
echo -e "${{C_BOLD}}🍏 نحوه اتصال از طریق آیفون و آیپد (iOS PWA - بدون نیاز به مک یا اپ‌استور):${{C_RESET}}"
echo -e "   ۱. در مرورگر Safari آیفون، آدرس وب زیر را باز کنید:"
if [ -n "$PUB_IP" ]; then
  echo -e "      ${{C_YELLOW}}${{C_BOLD}}http://${{PUB_IP}}:${{PORT}}${{C_RESET}}"
fi
echo -e "      ${{C_CYAN}}http://${{LOCAL_IP}}:${{PORT}}${{C_RESET}}"
echo -e "   ۲. دکمه ${{C_CYAN}}اشتراک‌گذاری (Share Icon ⎋)${{C_RESET}} در پایین صفحه سافاری را لمس کنید."
echo -e "   ۳. گزینه ${{C_GREEN}}«Add to Home Screen» (افزودن به صفحه اصلی)${{C_RESET}} را انتخاب کنید."
echo -e "   ۴. برنامه با آیکون اختصاصی و بدون نوار مرورگر به صورت تمام‌صفحه مانند یک اپلیکیشن کاملاً بومی نصب می‌شود!"
echo ""
echo -e "${{C_BOLD}}🌐 دسترسی از طریق مرورگر کامپیوتر یا موبایل (Web Client):${{C_RESET}}"
if [ -n "$PUB_IP" ]; then
  echo -e "   • ${{C_YELLOW}}http://${{PUB_IP}}:${{PORT}}${{C_RESET}}"
fi
echo -e "   • ${{C_CYAN}}http://${{LOCAL_IP}}:${{PORT}}${{C_RESET}}"
echo ""
echo -e "${{C_BOLD}}📋 دستورات مدیریت سرویس روی سرور لینوکس:${{C_RESET}}"
echo -e "   • مشاهده وضعیت:   ${{C_BLUE}}sudo systemctl status ${{SERVICE_NAME}}${{C_RESET}}"
echo -e "   • ری‌استارت:       ${{C_BLUE}}sudo systemctl restart ${{SERVICE_NAME}}${{C_RESET}}"
echo -e "   • توقف موقت:      ${{C_BLUE}}sudo systemctl stop ${{SERVICE_NAME}}${{C_RESET}}"
echo -e "   • مشاهده زنده‌ی لاگ‌ها: ${{C_BLUE}}sudo journalctl -u ${{SERVICE_NAME}} -f${{C_RESET}}"
echo -e "   • حذف کامل:       ${{C_BLUE}}sudo bash $0 --uninstall${{C_RESET}}"
echo -e "${{C_GREEN}}========================================================================${{C_RESET}}"
echo ""
'''

    with open(INSTALLER_PATH, "w", encoding="utf-8") as f:
        f.write(script)
    os.chmod(INSTALLER_PATH, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

    # Stage at ~/agent-work/install.sh and ~/agent-work/install-v1.1.0.sh
    shutil.copy2(INSTALLER_PATH, STAGED_PATH)
    shutil.copy2(INSTALLER_PATH, STAGED_VERSIONED_PATH)
    os.chmod(STAGED_PATH, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
    os.chmod(STAGED_VERSIONED_PATH, stat.S_IRWXU | stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)

    print(f"Generated standalone installer: {INSTALLER_PATH} ({os.path.getsize(INSTALLER_PATH)} bytes)")
    print(f"Staged at: {STAGED_PATH}")
    print(f"Staged at: {STAGED_VERSIONED_PATH}")


if __name__ == "__main__":
    build_installer()

#!/usr/bin/env bash
# ==============================================================================
# ☁️ Rakhssh Chat - Cloudflare Tunnel Controller (Port 443 / Anti-Censorship)
# Runs cloudflared in user-space without root or port 443 privileges.
# Automatically bridges traffic to local chat server (127.0.0.1:8765).
# ==============================================================================

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/agent-work/bin"
CLOUDFLARED="$BIN_DIR/cloudflared"
LOG_FILE="$DIR/tunnel.log"
URL_FILE="$DIR/tunnel_url.txt"
SESSION_NAME="chat-tunnel"
LOCAL_PORT="${PORT:-8765}"

ensure_binary() {
    if [ ! -x "$CLOUDFLARED" ]; then
        echo "--> Downloading official cloudflared binary..."
        mkdir -p "$BIN_DIR"
        curl -sL --max-time 30 -o "$CLOUDFLARED" \
            "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        chmod +x "$CLOUDFLARED"
    fi
}

check_running() {
    tmux has-session -t "$SESSION_NAME" 2>/dev/null
}

start_tunnel() {
    ensure_binary

    if check_running; then
        echo "Cloudflare Tunnel is already running!"
        show_url
        exit 0
    fi

    echo "🚀 Launching Cloudflare Tunnel for local port $LOCAL_PORT..."
    > "$LOG_FILE"
    rm -f "$URL_FILE"

    tmux new-session -d -s "$SESSION_NAME" -n "tunnel" \
        "$CLOUDFLARED tunnel --url http://127.0.0.1:$LOCAL_PORT 2>&1 | tee -a '$LOG_FILE'"

    echo "⏳ Waiting for Cloudflare Anycast URL..."
    DISCOVERED_URL=""
    for i in {1..12}; do
        sleep 1
        if [ -f "$LOG_FILE" ]; then
            DISCOVERED_URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' "$LOG_FILE" | head -n 1 || true)
            if [ -n "$DISCOVERED_URL" ]; then
                break
            fi
        fi
    done

    if [ -n "$DISCOVERED_URL" ]; then
        WS_URL=$(echo "$DISCOVERED_URL" | sed 's|^https://|wss://|')
        echo "$DISCOVERED_URL" > "$URL_FILE"
        echo "$WS_URL" >> "$URL_FILE"
        echo "=================================================================="
        echo "🎉 CLOUDFLARE TUNNEL ONLINE (پورت ۴۴۳ با رمزنگاری TLS 1.3 معتبر)"
        echo "=================================================================="
        echo "🌐 وب کلاینت (Web):       $DISCOVERED_URL"
        echo "⚡ وب‌سوکت اپلیکیشن (WSS): $WS_URL"
        echo "=================================================================="
        echo "• ترافیک از شبکه Anycast کلودفلر رد می‌شود و IP سرور پنهان می‌ماند."
        echo "• بدون نیاز به باز کردن پورت روی فایروال سرور (سازگار با فایروال‌های بسته)."
        echo "• ذخیره شده در: $URL_FILE"
    else
        echo "⚠️ تونل استارت شد اما دریافت آدرس زمان‌بر است. وضعیت لاگ:"
        tail -n 10 "$LOG_FILE"
    fi
}

stop_tunnel() {
    echo "Stopping Cloudflare Tunnel..."
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux kill-session -t "$SESSION_NAME"
    fi
    pkill -f "cloudflared tunnel" 2>/dev/null || true
    rm -f "$URL_FILE"
    echo "✅ Tunnel stopped."
}

show_url() {
    if [ -f "$URL_FILE" ]; then
        echo "آدرس‌های فعال تونل کلودفلر:"
        cat "$URL_FILE"
    elif [ -f "$LOG_FILE" ]; then
        URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' "$LOG_FILE" | head -n 1 || true)
        if [ -n "$URL" ]; then
            echo "https URL: $URL"
            echo "wss URL:   $(echo "$URL" | sed 's|^https://|wss://|')"
        else
            echo "آدرسی هنوز ثبت نشده است. لاگ‌ها را بررسی کنید."
        fi
    else
        echo "تونل فعال نیست."
    fi
}

status_tunnel() {
    echo "=========================================="
    echo "       Rakhssh Chat Tunnel Status"
    echo "=========================================="
    if check_running; then
        echo "Status: 🟢 RUNNING (Session '$SESSION_NAME')"
        show_url
    else
        echo "Status: 🔴 STOPPED"
    fi
    echo "=========================================="
}

case "$1" in
    start)
        start_tunnel
        ;;
    stop)
        stop_tunnel
        ;;
    restart)
        stop_tunnel
        sleep 1
        start_tunnel
        ;;
    status)
        status_tunnel
        ;;
    url)
        show_url
        ;;
    logs)
        tail -n 50 "$LOG_FILE"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|url|logs}"
        exit 1
        ;;
esac

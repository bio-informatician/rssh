#!/usr/bin/env bash
# Rakhssh Chat Server Management Script (Non-root / User-space)
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$DIR/.." && pwd)"
SERVER_SCRIPT="$DIR/server.py"
LOG_FILE="$DIR/server.log"
SESSION_NAME="chat-server"
PORT="${PORT:-8765}"
HOST="${HOST:-0.0.0.0}"

check_running() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        return 0
    fi
    if pgrep -f "server.py" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

start_server() {
    if check_running; then
        echo "Rakhssh Chat Server is already running!"
        exit 0
    fi

    echo "Starting Rakhssh Chat Server on $HOST:$PORT..."
    export PORT="$PORT"
    export HOST="$HOST"
    export WEB_DIR="$PROJECT_DIR/web"

    # Start detached tmux session
    tmux new-session -d -s "$SESSION_NAME" -n "chat" "python3 '$SERVER_SCRIPT' 2>&1 | tee -a '$LOG_FILE'"
    sleep 1

    if check_running; then
        echo "✅ Rakhssh Chat Server started successfully."
        echo "   • Process running in tmux session: '$SESSION_NAME'"
        echo "   • Port: $PORT"
        echo "   • Log file: $LOG_FILE"
        echo "   • Interactive console: Run '$0 attach' or 'tmux attach -t $SESSION_NAME'"
    else
        echo "❌ Failed to start server. Check logs: $LOG_FILE"
        exit 1
    fi
}

stop_server() {
    echo "Stopping Rakhssh Chat Server..."
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux kill-session -t "$SESSION_NAME"
    fi
    pkill -f "python3.*server.py" 2>/dev/null || true
    sleep 1
    if ! check_running; then
        echo "✅ Server stopped."
    else
        echo "⚠️ Force stopping remaining processes..."
        pkill -9 -f "python3.*server.py" 2>/dev/null || true
        echo "✅ Server stopped."
    fi
}

status_server() {
    echo "=========================================="
    echo "       Rakhssh Chat Server Status"
    echo "=========================================="
    if check_running; then
        echo "Status: 🟢 RUNNING"
        echo "Tmux session: '$SESSION_NAME'"
        PID=$(pgrep -f "server.py" | head -n 1)
        echo "Process PID: $PID"
        echo "Port: $PORT"
        echo "Checking health endpoint..."
        HEALTH=$(curl -s --connect-timeout 2 "http://127.0.0.1:$PORT/health" || echo "UNREACHABLE")
        echo "Health response: $HEALTH"
    else
        echo "Status: 🔴 STOPPED"
    fi
    echo "=========================================="
}

logs_server() {
    if [ -f "$LOG_FILE" ]; then
        tail -n 50 "$LOG_FILE"
    else
        echo "No log file found at $LOG_FILE"
    fi
}

attach_server() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        echo "Attaching to Rakhssh Chat Server tmux session... (Press Ctrl+B then D to detach)"
        tmux attach -t "$SESSION_NAME"
    else
        echo "Tmux session '$SESSION_NAME' is not running."
        echo "Run '$0 start' first."
    fi
}

case "$1" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        stop_server
        sleep 1
        start_server
        ;;
    status)
        status_server
        ;;
    logs)
        logs_server
        ;;
    attach)
        attach_server
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|attach}"
        exit 1
        ;;
esac

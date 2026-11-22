#!/usr/bin/env bash
# Rakhssh Web SSH Server Management Script (Non-root / User-space)
set -e

TARGET="${BASH_SOURCE[0]}"
while [ -L "$TARGET" ]; do
    DIR="$(cd -P "$(dirname "$TARGET")" >/dev/null 2>&1 && pwd)"
    TARGET="$(readlink "$TARGET")"
    [[ $TARGET != /* ]] && TARGET="$DIR/$TARGET"
done
DIR="$(cd -P "$(dirname "$TARGET")" >/dev/null 2>&1 && pwd)"
SERVER_SCRIPT="$DIR/server.py"
LOG_FILE="$DIR/webssh.log"
SESSION_NAME="webssh-server"
PORT="${PORT:-8766}"
HOST="${HOST:-0.0.0.0}"

check_running() {
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        return 0
    fi
    if pgrep -f "projects/webssh/server.py" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

start_server() {
    if check_running; then
        echo "Rakhssh Web SSH Server is already running!"
        exit 0
    fi

    echo "Starting Rakhssh Web SSH Server on $HOST:$PORT..."
    export WEBSSH_PORT="$PORT"
    export WEBSSH_HOST="$HOST"

    tmux new-session -d -s "$SESSION_NAME" -n "webssh" "python3 '$SERVER_SCRIPT' 2>&1 | tee -a '$LOG_FILE'"
    sleep 1

    if check_running; then
        echo "✅ Rakhssh Web SSH Server started successfully."
        echo "   • Process running in tmux session: '$SESSION_NAME'"
        echo "   • HTTP Port: $PORT"
        echo "   • Terminal URL: http://193.168.175.227:$PORT"
        echo "   • Log file: $LOG_FILE"
    else
        echo "❌ Failed to start Web SSH server. Check logs: $LOG_FILE"
        exit 1
    fi
}

stop_server() {
    if ! check_running; then
        echo "Rakhssh Web SSH Server is not running."
        return 0
    fi

    echo "Stopping Rakhssh Web SSH Server..."
    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
    fi
    pkill -f "projects/webssh/server.py" 2>/dev/null || true
    sleep 1
    echo "✅ Rakhssh Web SSH Server stopped."
}

status_server() {
    if check_running; then
        echo "● Rakhssh Web SSH Server is ACTIVE and running"
        echo "   • Session: $SESSION_NAME"
        echo "   • Port: $PORT"
        echo "   • URL: http://193.168.175.227:$PORT"
    else
        echo "○ Rakhssh Web SSH Server is INACTIVE (stopped)"
    fi
}

restart_server() {
    stop_server
    sleep 1
    start_server
}

case "${1:-status}" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        status_server
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

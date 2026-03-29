#!/usr/bin/env bash
# G0DM0D3 daemon — fully detached, survives parent death
# Usage: daemon.sh start|stop|status

G0D="$HOME/G0DM0D3"
PIDFILE="$G0D/.g0dm0d3.pids"
LOGFILE="$G0D/g0dm0d3.log"
PORT=7860
FE_PORT=8000
PATH="$HOME/.local/bin:$PREFIX/bin:$PATH"

do_start() {
  cd "$G0D" || exit 1
  [ -f .env ] && export $(grep -v '^#' .env | grep -v '^\s*$' | xargs) 2>/dev/null
  : > "$LOGFILE"

  python3 -m http.server "$FE_PORT" --bind 0.0.0.0 --directory "$G0D" >> "$LOGFILE" 2>&1 &
  echo $! > "$PIDFILE"

  CORS_ORIGIN="*" npx tsx api/server.ts >> "$LOGFILE" 2>&1 &
  echo $! >> "$PIDFILE"

  # Keep alive
  wait
}

do_stop() {
  if [ -f "$PIDFILE" ]; then
    while read -r pid; do
      kill "$pid" 2>/dev/null
    done < "$PIDFILE"
    rm -f "$PIDFILE"
  fi
  pkill -f "tsx.*api/server" 2>/dev/null
  pkill -f "http.server.*$FE_PORT" 2>/dev/null
}

case "${1:-start}" in
  start)
    do_stop 2>/dev/null
    sleep 1
    # Double-fork: first fork
    (
      # Second fork — fully detached from parent
      setsid bash -c "exec $0 _run" < /dev/null > /dev/null 2>&1 &
    ) &
    ;;
  _run)
    # Ignore hangup/term so we survive parent death
    trap '' SIGHUP SIGTERM
    do_start
    ;;
  stop)
    do_stop
    echo "Stopped."
    ;;
  status)
    if curl -sf http://localhost:$FE_PORT > /dev/null 2>&1; then
      echo "Frontend: UP"
    else
      echo "Frontend: DOWN"
    fi
    if curl -sf http://localhost:$PORT/v1/health > /dev/null 2>&1; then
      echo "API: UP"
    else
      echo "API: DOWN"
    fi
    ;;
esac

#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════
#  G0DM0D3 — Bulletproof Startup
# ═══════════════════════════════════════════════════════
#  godmode            Start API + frontend + open browser
#  godmode stop       Kill all G0DM0D3 processes
#  godmode status     Show what's running
#  godmode restart    Stop then start
#  godmode open       Open browser to frontend
#  godmode logs       Tail the log file
# ═══════════════════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PIDFILE="$SCRIPT_DIR/.g0dm0d3.pids"
LOGFILE="$SCRIPT_DIR/g0dm0d3.log"

# Load .env (skip comments, blank lines)
if [ -f .env ]; then
  while IFS='=' read -r key val; do
    key="$(echo "$key" | xargs)"
    [[ -z "$key" || "$key" == \#* ]] && continue
    val="$(echo "$val" | xargs)"
    export "$key=$val" 2>/dev/null || true
  done < .env
fi

PORT="${PORT:-7860}"
FRONTEND_PORT="${FRONTEND_PORT:-8000}"
CORS_ORIGIN="${CORS_ORIGIN:-*}"

# ── Colors ────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' C='\033[0;36m'
Y='\033[1;33m' B='\033[1;97m' N='\033[0m'

banner() {
  echo -e "${G}"
  cat << 'ART'
   ██████╗  ██████╗ ██████╗ ███╗   ███╗ ██████╗ ██████╗ ██████╗
  ██╔════╝ ██╔═══██╗██╔══██╗████╗ ████║██╔═══██╗██╔══██╗╚════██╗
  ██║  ███╗██║   ██║██║  ██║██╔████╔██║██║   ██║██║  ██║ █████╔╝
  ██║   ██║██║   ██║██║  ██║██║╚██╔╝██║██║   ██║██║  ██║ ╚═══██╗
  ╚██████╔╝╚██████╔╝██████╔╝██║ ╚═╝ ██║╚██████╔╝██████╔╝██████╔╝
   ╚═════╝  ╚═════╝ ╚═════╝ ╚═╝     ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝
ART
  echo -e "${N}"
}

# ── Port / Process helpers ────────────────────────────
port_pid() {
  # Return PID listening on a port, or empty
  if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | grep ":$1 " | grep -oP 'pid=\K[0-9]+' | head -1
  elif command -v lsof &>/dev/null; then
    lsof -ti :"$1" 2>/dev/null | head -1
  else
    echo ""
  fi
}

is_port_up() {
  local pid
  pid="$(port_pid "$1")"
  [ -n "$pid" ]
}

proc_alive() { kill -0 "$1" 2>/dev/null; }

kill_port() {
  local pid
  pid="$(port_pid "$1")"
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null
    # Wait up to 3s for clean exit
    for _ in 1 2 3; do
      proc_alive "$pid" || return 0
      sleep 1
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
}

# ── Stop ──────────────────────────────────────────────
do_stop() {
  local killed=0

  # Kill by PID file
  if [ -f "$PIDFILE" ]; then
    while IFS= read -r pid; do
      [ -z "$pid" ] && continue
      if proc_alive "$pid"; then
        kill "$pid" 2>/dev/null; killed=1
      fi
    done < "$PIDFILE"
    rm -f "$PIDFILE"
  fi

  # Kill by port (catches orphans)
  kill_port "$PORT" && killed=1
  kill_port "$FRONTEND_PORT" && killed=1

  # Sweep by process name (catches anything missed)
  pkill -f "tsx.*api/server" 2>/dev/null && killed=1 || true
  pkill -f "http\.server.*${FRONTEND_PORT}" 2>/dev/null && killed=1 || true

  if [ "$killed" -eq 1 ]; then
    sleep 1
    echo -e "${G}G0DM0D3 stopped.${N}"
  else
    echo -e "${Y}G0DM0D3 was not running.${N}"
  fi
}

# ── Status ────────────────────────────────────────────
do_status() {
  local api_up=0 fe_up=0

  if is_port_up "$PORT"; then
    api_up=1
    echo -e "  ${G}API      ${C}http://localhost:${PORT}${N}  ${G}[RUNNING]${N}  pid=$(port_pid $PORT)"
  else
    echo -e "  ${R}API      port ${PORT}  [DOWN]${N}"
  fi

  if is_port_up "$FRONTEND_PORT"; then
    fe_up=1
    echo -e "  ${G}Frontend ${C}http://localhost:${FRONTEND_PORT}${N}  ${G}[RUNNING]${N}  pid=$(port_pid $FRONTEND_PORT)"
  else
    echo -e "  ${R}Frontend port ${FRONTEND_PORT}  [DOWN]${N}"
  fi

  if [ "$api_up" -eq 1 ] && [ "$fe_up" -eq 1 ]; then
    echo -e "\n  ${G}G0DM0D3 is fully operational.${N}"
    return 0
  fi
  return 1
}

# ── Open browser ──────────────────────────────────────
do_open() {
  local url="http://localhost:${FRONTEND_PORT}"
  if command -v termux-open-url &>/dev/null; then
    termux-open-url "$url"
  elif command -v termux-open &>/dev/null; then
    termux-open "$url"
  elif command -v am &>/dev/null; then
    am start -a android.intent.action.VIEW -d "$url" 2>/dev/null
  elif command -v xdg-open &>/dev/null; then
    xdg-open "$url"
  else
    echo -e "${Y}Open manually: ${C}${url}${N}"
    return
  fi
  echo -e "${G}Browser opened: ${C}${url}${N}"
}

# ── Preflight checks ─────────────────────────────────
preflight() {
  local fail=0

  if ! command -v node &>/dev/null; then
    echo -e "${R}MISSING: Node.js — run: pkg install nodejs${N}"; fail=1
  fi
  if ! command -v python3 &>/dev/null; then
    echo -e "${R}MISSING: Python3 — run: pkg install python${N}"; fail=1
  fi
  if ! command -v npx &>/dev/null; then
    echo -e "${R}MISSING: npx — run: pkg install nodejs${N}"; fail=1
  fi

  [ "$fail" -eq 1 ] && exit 1

  # Auto-install deps if missing
  if [ ! -d "$SCRIPT_DIR/node_modules" ]; then
    echo -e "${Y}First run — installing dependencies...${N}"
    npm install --no-audit --no-fund || {
      echo -e "${R}npm install failed. Check network and try again.${N}"
      exit 1
    }
  fi
}

# ── Wait for port with timeout ───────────────────────
wait_port() {
  local port="$1" label="$2" secs="${3:-20}" i=0
  while [ "$i" -lt "$secs" ]; do
    if is_port_up "$port"; then
      echo -e "  ${G}${label} ready${N}  port ${port}  (${i}s)"
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo -e "  ${R}${label} FAILED to start on port ${port} after ${secs}s${N}"
  echo -e "  ${Y}Check logs: tail -20 $LOGFILE${N}"
  return 1
}

# ── Watchdog: restart crashed children ────────────────
watchdog() {
  while true; do
    sleep 10
    # Check API
    if [ -n "${API_PID:-}" ] && ! proc_alive "$API_PID"; then
      echo -e "\n${Y}[watchdog] API crashed — restarting...${N}" | tee -a "$LOGFILE"
      CORS_ORIGIN="$CORS_ORIGIN" npx tsx api/server.ts >> "$LOGFILE" 2>&1 &
      API_PID=$!
      echo "$API_PID" >> "$PIDFILE"
    fi
    # Check frontend
    if [ -n "${FE_PID:-}" ] && ! proc_alive "$FE_PID"; then
      echo -e "\n${Y}[watchdog] Frontend crashed — restarting...${N}" | tee -a "$LOGFILE"
      python3 -m http.server "$FRONTEND_PORT" --bind 0.0.0.0 --directory "$SCRIPT_DIR" >> "$LOGFILE" 2>&1 &
      FE_PID=$!
      echo "$FE_PID" >> "$PIDFILE"
    fi
  done
}

# ── Cleanup on exit ───────────────────────────────────
cleanup() {
  echo -e "\n${Y}Shutting down G0DM0D3...${N}"
  # Kill watchdog first
  [ -n "${WATCHDOG_PID:-}" ] && kill "$WATCHDOG_PID" 2>/dev/null
  [ -n "${API_PID:-}" ] && kill "$API_PID" 2>/dev/null
  [ -n "${FE_PID:-}" ] && kill "$FE_PID" 2>/dev/null
  rm -f "$PIDFILE"
  echo -e "${G}G0DM0D3 stopped.${N}"
  exit 0
}

# ── Start ─────────────────────────────────────────────
do_start() {
  preflight

  # Clean slate
  if is_port_up "$PORT" || is_port_up "$FRONTEND_PORT"; then
    echo -e "${Y}Previous instance detected — stopping...${N}"
    do_stop
    sleep 1
  fi

  rm -f "$PIDFILE"
  : > "$LOGFILE"  # truncate log

  trap cleanup SIGINT SIGTERM EXIT

  # ── Launch API ──
  echo -e "${C}Starting API server (port ${PORT})...${N}"
  CORS_ORIGIN="$CORS_ORIGIN" npx tsx api/server.ts >> "$LOGFILE" 2>&1 &
  API_PID=$!
  echo "$API_PID" >> "$PIDFILE"

  # ── Launch Frontend ──
  echo -e "${C}Starting frontend (port ${FRONTEND_PORT})...${N}"
  python3 -m http.server "$FRONTEND_PORT" --bind 0.0.0.0 --directory "$SCRIPT_DIR" >> "$LOGFILE" 2>&1 &
  FE_PID=$!
  echo "$FE_PID" >> "$PIDFILE"

  # ── Wait for both ──
  echo -e "${B}Waiting for services...${N}"
  local ok=1
  wait_port "$FRONTEND_PORT" "Frontend" 10 || ok=0
  wait_port "$PORT" "API" 20 || ok=0

  if [ "$ok" -eq 0 ]; then
    echo -e "${R}Startup failed. Last 20 lines of log:${N}"
    tail -20 "$LOGFILE"
    cleanup
  fi

  # ── API health check ──
  local health
  health="$(curl -sf http://localhost:${PORT}/v1/health 2>/dev/null || echo '{}')"
  if echo "$health" | grep -q '"ok"'; then
    echo -e "  ${G}API health check PASSED${N}"
  else
    echo -e "  ${Y}API health check inconclusive (may still be warming up)${N}"
  fi

  # ── Launch watchdog ──
  watchdog &
  WATCHDOG_PID=$!

  # ── Ready ──
  echo ""
  echo -e "${G}══════════════════════════════════════${N}"
  echo -e "${G}  G0DM0D3 IS LIVE${N}"
  echo -e "${G}══════════════════════════════════════${N}"
  echo -e "  ${B}Browser:${N}  ${C}http://localhost:${FRONTEND_PORT}${N}"
  echo -e "  ${B}API:${N}      ${C}http://localhost:${PORT}/v1/info${N}"
  echo -e "  ${B}Logs:${N}     tail -f ~/G0DM0D3/g0dm0d3.log"
  echo -e "  ${B}Stop:${N}     godmode stop  ${Y}(from another terminal)${N}"

  if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    echo ""
    echo -e "  ${Y}No OPENROUTER_API_KEY in .env${N}"
    echo -e "  ${Y}Enter your key in the browser settings.${N}"
  fi
  echo ""

  # Auto-open browser
  do_open 2>/dev/null

  echo -e "${C}Ctrl+C to stop.${N}"
  echo ""

  # Block forever — wait on children
  wait
}

# ═════════════════════════════════════════════════════
#  MAIN
# ═════════════════════════════════════════════════════
banner

case "${1:-start}" in
  stop)       do_stop ;;
  status)     do_status ;;
  restart)    do_stop; sleep 2; do_start ;;
  open)       do_open ;;
  logs)       tail -f "$LOGFILE" ;;
  start|"")   do_start ;;
  *)
    echo "Usage: godmode [start|stop|status|restart|open|logs]"
    exit 1
    ;;
esac

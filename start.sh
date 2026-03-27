#!/usr/bin/env bash
# ═══════════════════════════════════════════════
#  G0DM0D3 — Robust Startup Script
# ═══════════════════════════════════════════════
# Usage:
#   godmode              Start everything
#   godmode stop          Kill running instances
#   godmode status        Check if running
#   godmode restart       Stop + start
#   godmode --api-only    API server only
#   godmode --frontend-only  Frontend only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PIDFILE="$SCRIPT_DIR/.g0dm0d3.pids"
LOGFILE="$SCRIPT_DIR/g0dm0d3.log"

# Load environment
if [ -f .env ]; then
  set -a
  source .env
  set +a
fi

PORT="${PORT:-7860}"
FRONTEND_PORT="${FRONTEND_PORT:-8000}"
CORS_ORIGIN="${CORS_ORIGIN:-*}"

# Colors
R='\033[0;31m'
G='\033[0;32m'
C='\033[0;36m'
Y='\033[1;33m'
B='\033[1;37m'
N='\033[0m'

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

is_port_in_use() {
  if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | grep -q ":$1 " && return 0
  elif command -v netstat &>/dev/null; then
    netstat -tlnp 2>/dev/null | grep -q ":$1 " && return 0
  else
    # fallback: try connecting
    (echo >/dev/tcp/127.0.0.1/$1) 2>/dev/null && return 0
  fi
  return 1
}

is_process_alive() {
  kill -0 "$1" 2>/dev/null
}

stop_godmode() {
  local found=0
  if [ -f "$PIDFILE" ]; then
    while IFS= read -r pid; do
      if is_process_alive "$pid"; then
        kill "$pid" 2>/dev/null && found=1
      fi
    done < "$PIDFILE"
    rm -f "$PIDFILE"
  fi
  # Also sweep for any strays
  pkill -f "tsx api/server.ts" 2>/dev/null && found=1 || true
  pkill -f "http.server ${FRONTEND_PORT}" 2>/dev/null && found=1 || true
  if [ "$found" -eq 1 ]; then
    echo -e "${Y}G0DM0D3 stopped.${N}"
  else
    echo -e "${Y}G0DM0D3 is not running.${N}"
  fi
}

status_godmode() {
  local api_up=0 fe_up=0
  is_port_in_use "$PORT" && api_up=1
  is_port_in_use "$FRONTEND_PORT" && fe_up=1

  if [ "$api_up" -eq 1 ] && [ "$fe_up" -eq 1 ]; then
    echo -e "${G}G0DM0D3 is running${N}"
    echo -e "  API:      ${C}http://localhost:${PORT}${N} [UP]"
    echo -e "  Frontend: ${C}http://localhost:${FRONTEND_PORT}${N} [UP]"
    return 0
  elif [ "$api_up" -eq 1 ]; then
    echo -e "${Y}G0DM0D3 partially running${N}"
    echo -e "  API:      ${C}http://localhost:${PORT}${N} [UP]"
    echo -e "  Frontend: ${R}DOWN${N}"
    return 1
  elif [ "$fe_up" -eq 1 ]; then
    echo -e "${Y}G0DM0D3 partially running${N}"
    echo -e "  API:      ${R}DOWN${N}"
    echo -e "  Frontend: ${C}http://localhost:${FRONTEND_PORT}${N} [UP]"
    return 1
  else
    echo -e "${R}G0DM0D3 is not running.${N}"
    return 1
  fi
}

wait_for_port() {
  local port=$1 name=$2 timeout=${3:-15}
  local i=0
  while [ $i -lt $timeout ]; do
    if is_port_in_use "$port"; then
      echo -e "  ${G}$name ready on port $port${N}"
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  echo -e "  ${R}$name failed to start on port $port (timeout ${timeout}s)${N}"
  return 1
}

cleanup() {
  echo -e "\n${Y}Shutting down G0DM0D3...${N}"
  stop_godmode
  exit 0
}
trap cleanup SIGINT SIGTERM

start_godmode() {
  local mode="${1:-all}"

  # Pre-flight checks
  if ! command -v node &>/dev/null; then
    echo -e "${R}Node.js required. Run: pkg install nodejs${N}"; exit 1
  fi
  if ! command -v python3 &>/dev/null; then
    echo -e "${R}Python3 required. Run: pkg install python${N}"; exit 1
  fi
  if [ ! -d node_modules ]; then
    echo -e "${Y}Installing dependencies...${N}"
    npm install
  fi

  # Kill anything already on our ports
  if is_port_in_use "$PORT" || is_port_in_use "$FRONTEND_PORT"; then
    echo -e "${Y}Cleaning up previous instances...${N}"
    stop_godmode
    sleep 1
  fi

  rm -f "$PIDFILE"
  local pids=()

  # Start API
  if [ "$mode" != "--frontend-only" ]; then
    echo -e "${C}Starting API server...${N}"
    CORS_ORIGIN="$CORS_ORIGIN" npx tsx api/server.ts >> "$LOGFILE" 2>&1 &
    local api_pid=$!
    pids+=("$api_pid")
    echo "$api_pid" >> "$PIDFILE"
  fi

  # Start frontend
  if [ "$mode" != "--api-only" ]; then
    echo -e "${C}Starting frontend...${N}"
    python3 -m http.server "$FRONTEND_PORT" --bind 0.0.0.0 >> "$LOGFILE" 2>&1 &
    local fe_pid=$!
    pids+=("$fe_pid")
    echo "$fe_pid" >> "$PIDFILE"
  fi

  # Wait for ports to come alive
  echo -e "${B}Waiting for services...${N}"
  local ok=1
  if [ "$mode" != "--frontend-only" ]; then
    wait_for_port "$PORT" "API" 15 || ok=0
  fi
  if [ "$mode" != "--api-only" ]; then
    wait_for_port "$FRONTEND_PORT" "Frontend" 10 || ok=0
  fi

  if [ "$ok" -eq 0 ]; then
    echo -e "${R}Some services failed to start. Check $LOGFILE${N}"
    return 1
  fi

  # Health check
  if [ "$mode" != "--frontend-only" ]; then
    local health
    health=$(curl -s http://localhost:${PORT}/v1/health 2>/dev/null || echo '{"status":"error"}')
    if echo "$health" | grep -q '"ok"'; then
      echo -e "  ${G}API health check passed${N}"
    else
      echo -e "  ${R}API health check failed${N}"
    fi
  fi

  echo ""
  echo -e "${G}=== G0DM0D3 IS LIVE ===${N}"
  if [ "$mode" != "--api-only" ]; then
    echo -e "  ${B}Open in browser:${N} ${C}http://localhost:${FRONTEND_PORT}${N}"
  fi
  if [ "$mode" != "--frontend-only" ]; then
    echo -e "  ${B}API endpoint:${N}   ${C}http://localhost:${PORT}/v1/info${N}"
  fi
  if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    echo ""
    echo -e "  ${Y}Paste your OpenRouter API key in the browser UI${N}"
    echo -e "  ${Y}or set OPENROUTER_API_KEY in ~/G0DM0D3/.env${N}"
  fi
  echo ""
  echo -e "  ${C}Logs:${N} tail -f $LOGFILE"
  echo -e "  ${C}Stop:${N} godmode stop"
  echo ""
  echo -e "${C}Press Ctrl+C to stop, or run 'godmode stop' from another terminal.${N}"

  wait
}

# ── Main ──────────────────────────────────────
banner

case "${1:-start}" in
  stop)
    stop_godmode
    ;;
  status)
    status_godmode
    ;;
  restart)
    stop_godmode
    sleep 2
    start_godmode "${2:---all}"
    ;;
  start|--api-only|--frontend-only)
    start_godmode "${1:-start}"
    ;;
  *)
    start_godmode "start"
    ;;
esac

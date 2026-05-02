#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  VEYA Kiosk Launch Script                           start_veya.sh
#  Boots the OBD service then the Qt UI.
#
#  Usage:
#    ./start_veya.sh                              mock mode (default)
#    ./start_veya.sh --mode elm                   real ELM327
#    ./start_veya.sh --mode elm --elm-port /dev/ttyUSB1
#    ./start_veya.sh --mode elm --hz 4
# ════════════════════════════════════════════════════════════════════

set -e

# ── Defaults ────────────────────────────────────────────────────────
MODE="mock"
ELM_PORT="/dev/ttyUSB0"
ELM_BAUD="38400"
HZ=""

# ── Parse args ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)     MODE="$2";     shift 2 ;;
        --elm-port) ELM_PORT="$2"; shift 2 ;;
        --elm-baud) ELM_BAUD="$2"; shift 2 ;;
        --hz)       HZ="$2";       shift 2 ;;
        *)          shift ;;
    esac
done

# ── Logging ─────────────────────────────────────────────────────────
VEYA_HOME="/home/pfe/veya"
mkdir -p "$VEYA_HOME/logs"
exec >> "$VEYA_HOME/logs/kiosk.log" 2>&1

echo ""
echo "══════════════════════════════════════════════"
echo "  VEYA START  —  mode: $MODE  —  $(date)"
echo "══════════════════════════════════════════════"

# ── Kill any existing backend on port 8765 ───────────────────────────
if ss -ltnp 2>/dev/null | grep -q '127\.0\.0\.1:8765'; then
    PID=$(ss -tlnp 2>/dev/null | grep ':8765' | grep -oP 'pid=\K[0-9]+' | head -n1)
    if [ -n "$PID" ]; then
        echo "[start_veya] Killing existing obd_service pid=$PID"
        kill "$PID" 2>/dev/null || true
        sleep 0.4
    fi
fi

cd "$VEYA_HOME"
source "$VEYA_HOME/.venv/bin/activate"

# ── Build OBD service argument list ─────────────────────────────────
OBD_ARGS="--mode $MODE --elm-port $ELM_PORT --elm-baud $ELM_BAUD"
[ -n "$HZ" ] && OBD_ARGS="$OBD_ARGS --hz $HZ"

echo "[start_veya] Starting obd_service: $OBD_ARGS"
python services/obd_service/obd_service.py $OBD_ARGS >> "$VEYA_HOME/logs/obd_service.log" 2>&1 &
OBD_PID=$!
echo "[start_veya] obd_service PID: $OBD_PID"

# ── Wait until WebSocket is ready (max 6 s, check every 0.5 s) ──────
echo "[start_veya] Waiting for ws://127.0.0.1:8765 …"
READY=0
for i in $(seq 1 12); do
    if python -c "
import socket, sys
s = socket.socket()
s.settimeout(0.4)
try:
    s.connect(('127.0.0.1', 8765))
    s.close()
    sys.exit(0)
except:
    sys.exit(1)
" 2>/dev/null; then
        echo "[start_veya] WebSocket ready (attempt $i / 12)"
        READY=1
        break
    fi
    sleep 0.5
done

if [ "$READY" -eq 0 ]; then
    echo "[start_veya] WARNING: WebSocket not ready after 6 s — launching UI anyway"
fi

# ── Launch Qt UI ─────────────────────────────────────────────────────
echo "[start_veya] Launching veya_ui …"
"$VEYA_HOME/ui/build/veya_ui" >> "$VEYA_HOME/logs/veya_ui.log" 2>&1
UI_CODE=$?
echo "[start_veya] veya_ui exited with code=$UI_CODE"

# ── Cleanup ──────────────────────────────────────────────────────────
kill "$OBD_PID" 2>/dev/null || true
echo "[start_veya] Done."

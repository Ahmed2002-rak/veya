#!/bin/bash
# ════════════════════════════════════════════════════════════════════
#  VEYA Kiosk Launch Script                           start_veya.sh
#  Boots the veya_core service then the Qt UI.
#
#  Usage:
#    ./start_veya.sh                              mock mode (default)
#    ./start_veya.sh --mode mock                  mock mode (auto-spawns mock_source)
#    ./start_veya.sh --mode real                  real mode — wait for external source
#    ./start_veya.sh --mode elm                   alias of --mode real (back-compat)
#    ./start_veya.sh --mode mock --hz 5
#    ./start_veya.sh --listen 0.0.0.0 --tcp-port 9000  expose TCP for LAN testing
#
#  In real mode the core just listens on TCP. To stream telemetry from
#  an ELM327 USB adapter, run elm327_source.py in another terminal:
#    python -m services.veya_core.sources.elm327_source --device /dev/ttyUSB0
# ════════════════════════════════════════════════════════════════════

set -e

# ── Defaults ────────────────────────────────────────────────────────
MODE="mock"
LISTEN="127.0.0.1"
TCP_PORT="9000"
WS_PORT="8765"
HZ=""

# ── Parse args ──────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)     MODE="$2";     shift 2 ;;
        --listen)   LISTEN="$2";   shift 2 ;;
        --tcp-port) TCP_PORT="$2"; shift 2 ;;
        --ws-port)  WS_PORT="$2";  shift 2 ;;
        --hz)       HZ="$2";       shift 2 ;;
        # Back-compat: silently accept the legacy ELM-specific flags so
        # existing callers don't break, but ignore them — they belong
        # to elm327_source.py now.
        --elm-port) shift 2 ;;
        --elm-baud) shift 2 ;;
        *)          shift ;;
    esac
done

# Map back-compat alias: elm → real
if [ "$MODE" = "elm" ]; then
    MODE="real"
fi

# ── Logging ─────────────────────────────────────────────────────────
VEYA_HOME="/home/pfe/veya"
mkdir -p "$VEYA_HOME/logs"
exec >> "$VEYA_HOME/logs/kiosk.log" 2>&1

echo ""
echo "══════════════════════════════════════════════"
echo "  VEYA START  —  mode: $MODE  —  $(date)"
echo "══════════════════════════════════════════════"

# ── Kill any existing backend on the WebSocket port ──────────────────
if ss -ltnp 2>/dev/null | grep -q "127\\.0\\.0\\.1:$WS_PORT"; then
    PID=$(ss -tlnp 2>/dev/null | grep ":$WS_PORT" | grep -oP 'pid=\K[0-9]+' | head -n1)
    if [ -n "$PID" ]; then
        echo "[start_veya] Killing existing veya_core pid=$PID"
        kill "$PID" 2>/dev/null || true
        sleep 0.4
    fi
fi

cd "$VEYA_HOME"
source "$VEYA_HOME/.venv/bin/activate"

# ── Build core argument list ────────────────────────────────────────
CORE_ARGS="--mode $MODE --listen $LISTEN --tcp-port $TCP_PORT --ws-port $WS_PORT"
[ -n "$HZ" ] && CORE_ARGS="$CORE_ARGS --hz $HZ"

echo "[start_veya] Starting veya_core: $CORE_ARGS"
python -m services.veya_core.core $CORE_ARGS >> "$VEYA_HOME/logs/obd_service.log" 2>&1 &
CORE_PID=$!
echo "[start_veya] veya_core PID: $CORE_PID"

# ── Wait until WebSocket is ready (max 6 s, check every 0.5 s) ──────
echo "[start_veya] Waiting for ws://127.0.0.1:$WS_PORT …"
READY=0
for i in $(seq 1 12); do
    if python -c "
import socket, sys
s = socket.socket()
s.settimeout(0.4)
try:
    s.connect(('127.0.0.1', $WS_PORT))
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
QML_XHR_ALLOW_FILE_READ=1 "$VEYA_HOME/ui/build/veya_ui" >> "$VEYA_HOME/logs/veya_ui.log" 2>&1
UI_CODE=$?
echo "[start_veya] veya_ui exited with code=$UI_CODE"

# ── Cleanup ──────────────────────────────────────────────────────────
kill "$CORE_PID" 2>/dev/null || true
echo "[start_veya] Done."

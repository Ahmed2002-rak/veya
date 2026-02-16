#!/bin/bash
set -e
mkdir -p /home/pfe/veya/logs
exec >>/home/pfe/veya/logs/kiosk.log 2>&1

echo "=== VEYA KIOSK START ==="
date

cd /home/pfe/veya
source /home/pfe/veya/.venv/bin/activate

# Kill anything already using 8765 (prevents bind errors after crashes/restarts)
if ss -ltnp | grep -q '127.0.0.1:8765'; then
  PID=$(ss -ltnp | awk '/127\.0\.0\.1:8765/ {match($0,/pid=([0-9]+)/,a); if(a[1]!=""){print a[1]; exit}}')
  if [ -n "$PID" ]; then
    echo "Killing process on 8765: pid=$PID"
    kill "$PID" || true
    sleep 0.2
  fi
fi

python services/obd_service/obd_service.py --mode mock --hz 10 >>logs/obd_service.log 2>&1 &

/home/pfe/veya/ui/build/veya_ui >>logs/veya_ui.log 2>&1
echo "VEYA exited with code=$?"

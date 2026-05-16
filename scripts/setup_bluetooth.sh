#!/usr/bin/env bash
# One-time setup for Bluetooth dependencies on a fresh Raspberry Pi.
# Safe to re-run — all steps are idempotent.
#
# What this does:
#   1. Installs bluez and bluez-tools
#   2. Creates /etc/systemd/system/bt-agent.service
#   3. Enables and starts bt-agent.service
#   4. Adds the 'pfe' user to the bluetooth group
#   5. Powers on the Bluetooth adapter

set -euo pipefail

BT_USER=pfe
AGENT_SERVICE=/etc/systemd/system/bt-agent.service

echo "=== VEYA Bluetooth setup ==="

# 1. Install packages
echo "[1/5] Installing bluez and bluez-tools..."
sudo apt-get install -y bluez bluez-tools

# 2. Write the bt-agent systemd service
echo "[2/5] Writing ${AGENT_SERVICE}..."
sudo tee "$AGENT_SERVICE" > /dev/null <<'UNIT'
[Unit]
Description=Bluetooth Agent (no-input no-output pairing)
Requires=bluetooth.service
After=bluetooth.service

[Service]
ExecStart=/usr/bin/bt-agent --capability=NoInputNoOutput
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT

# 3. Reload systemd and enable + start the agent
echo "[3/5] Enabling bt-agent.service..."
sudo systemctl daemon-reload
sudo systemctl enable --now bt-agent.service

# 4. Add user to bluetooth group (idempotent — checks before acting)
echo "[4/5] Checking bluetooth group membership for '${BT_USER}'..."
if id -nG "$BT_USER" 2>/dev/null | tr ' ' '\n' | grep -qx bluetooth; then
    echo "  '${BT_USER}' is already in the bluetooth group — skipping."
else
    sudo usermod -a -G bluetooth "$BT_USER"
    echo "  Added '${BT_USER}' to bluetooth group. Re-login or reboot to activate."
fi

# 5. Power on the Bluetooth adapter
echo "[5/5] Powering on Bluetooth adapter..."
bluetoothctl power on 2>/dev/null || true

echo ""
echo "=== Setup complete ==="
SERVICE_STATUS=$(systemctl is-active bt-agent.service 2>/dev/null || true)
if [ "$SERVICE_STATUS" = "active" ]; then
    echo "  bt-agent.service : RUNNING  OK"
    exit 0
else
    echo "  bt-agent.service : ${SERVICE_STATUS}  (check: journalctl -u bt-agent.service)"
    exit 1
fi

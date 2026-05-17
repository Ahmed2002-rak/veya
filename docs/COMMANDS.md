# VEYA — Daily Operations Cheatsheet

> Personal reference. Last updated: Phase 3.0b (May 2026).

---

## First-time Pi setup

Run once on a fresh Pi to install Bluetooth dependencies and enable the pairing agent:

```bash
bash scripts/setup_bluetooth.sh
```

---

## Building

```bash
# Standard build (after any QML or C++ change)
cd ~/veya/ui/build && cmake --build . -j4

# Force reconfigure + build (after CMakeLists.txt change or new QML file)
cd ~/veya/ui/build && cmake .. && cmake --build . -j4
```

---

## Running

```bash
# Start dashboard (kiosk — normal way on Pi)
sudo reboot   # auto-start via ~/.bash_profile → start_veya.sh

# Start backend only, mock mode (no Qt UI, see frames in terminal)
cd ~/veya && python -m services.veya_core.core --mode mock

# Start backend, real/ELM mode (waits for external source on TCP :9000)
python -m services.veya_core.core --mode real

# Start backend listening on LAN so a laptop can send a source
python -m services.veya_core.core --mode real --listen 0.0.0.0

# Start UI manually (backend must already be running)
~/veya/ui/build/veya_ui
```

---

## Logs

```bash
# Watch UI log
tail -f ~/veya/logs/veya_ui.log

# Watch backend log
tail -f ~/veya/logs/obd_service.log

# Watch kiosk launch log (what .bash_profile + start_veya.sh print)
tail -f ~/veya/logs/kiosk.log

# Watch all three at once
tail -f ~/veya/logs/kiosk.log ~/veya/logs/obd_service.log ~/veya/logs/veya_ui.log
```

---

## Screenshots (linuxfb / kiosk mode)

```bash
# Take screenshot on Pi
sudo fbgrab ~/veya_screenshot.png

# Copy screenshot from Pi to laptop (run this on the LAPTOP)
scp pfe@<Pi-IP>:~/veya_screenshot.png .

# Find Pi IP
hostname -I
```

---

## Server URLs (Phase 3.0a)

```bash
# Set the report server URL
python3 ~/veya/services/veya_core/helpers/set_server_url.py report https://<host>/report

# Set the live-session server URL
python3 ~/veya/services/veya_core/helpers/set_server_url.py live https://<host>/live

# Show current configured URLs
python3 ~/veya/services/veya_core/helpers/set_server_url.py show

# Clear both URLs (resets to "not configured")
python3 ~/veya/services/veya_core/helpers/set_server_url.py clear

# Config file location
cat ~/.veya/server_config.json
```

---

## Wi-Fi (manual via terminal — UI also handles all of this)

```bash
# Scan for networks
nmcli device wifi list

# Connect to a network
nmcli device wifi connect <SSID> password <PASS>

# Connect to an open network (no password)
nmcli device wifi connect <SSID>

# Disconnect the Wi-Fi interface
nmcli device disconnect wlan0

# Show active connections
nmcli connection show --active

# Show Wi-Fi status
nmcli -t -f NAME,DEVICE,STATE connection show --active
```

---

## Profile management

```bash
# View saved user profile
cat ~/.veya/user_profile.json

# Reset profile (forces onboarding flow on next boot)
rm ~/.veya/user_profile.json
```

---

## WebSocket smoke tests

```bash
# Tail the live WS stream
wscat -c ws://127.0.0.1:8765          # npm install -g wscat

# Send a mode switch command manually
echo '{"cmd":"set_mode","mode":"elm"}' | wscat -c ws://127.0.0.1:8765

# Test wifi_status command
python3 -c "
import asyncio, json, websockets
async def t():
    async with websockets.connect('ws://127.0.0.1:8765') as ws:
        await ws.send(json.dumps({'cmd':'wifi_status'}))
        print(await asyncio.wait_for(ws.recv(), timeout=6))
asyncio.run(t())
"

# Test wifi_scan command (takes up to ~15 s)
python3 -c "
import asyncio, json, websockets
async def t():
    async with websockets.connect('ws://127.0.0.1:8765') as ws:
        await ws.send(json.dumps({'cmd':'wifi_scan'}))
        print(await asyncio.wait_for(ws.recv(), timeout=20))
asyncio.run(t())
"
```

---

## Git

```bash
# Save current work
git add -A && git commit -m "..." && git push

# Check current branch
git branch --show-current

# List tags
git tag -l

# Switch to a known stable tag (detached HEAD — read only)
git checkout v2.2b-stable

# Return to main
git checkout main

# Create a new feature branch
git checkout -b feature/<name>

# Tag a milestone after hardware verification
git tag v3.0a-stable && git push origin v3.0a-stable
```

---

## Bluetooth (Phase 3.0b)

```bash
# Show BT adapter status
bluetoothctl show

# Scan for nearby devices (interactive — Ctrl-C to stop)
bluetoothctl scan on

# List all paired devices
bluetoothctl devices

# Pair with a device manually
bluetoothctl pair <MAC>

# Trust and connect after pairing
bluetoothctl trust <MAC> && bluetoothctl connect <MAC>

# Watch the BT bridge log
tail -f ~/veya/logs/bt_bridge.log

# Stop the BT bridge manually
pkill -f services.veya_core.bt_bridge

# View BT config (paired ESP32 MAC)
cat ~/.veya/bt_config.json

# Reset BT config (forces re-pairing from UI)
rm ~/.veya/bt_config.json

# Unblock BT adapter if rfkill-blocked
sudo rfkill unblock bluetooth

# Enable pairable mode on adapter
echo -e "pairable on\nexit" | bluetoothctl
```

### Cleanup before production

```bash
# Unpair a specific test device
bluetoothctl untrust <MAC> && bluetoothctl remove <MAC>

# List currently paired devices
bluetoothctl devices Paired

# Reset ALL paired devices (wipes every bonded device)
bluetoothctl devices Paired | awk '{print $2}' | xargs -I {} bluetoothctl remove {}
```

---

### Testing the ESP32 reference sketch

```bash
# Flash firmware/esp32/veya_esp32_sample.ino (Arduino IDE, any classic ESP32 with BT-Classic)
# Power ESP32, then on VEYA dashboard:

# 1. Open Bluetooth page → Refresh → "VEYA-OBD-SAMPLE" should appear
# 2. Tap Pair → bt_bridge auto-spawns

# Watch bridge log in real time
tail -f ~/veya/logs/bt_bridge.log

# 3. Go to Drive → switch to REAL mode
#    Hardcoded telemetry should appear: 850 rpm, 0 km/h, 85 °C coolant, etc.

# Check the bridge status file (written by bt_bridge, read by ws_server)
cat /tmp/veya_bt_bridge_status.txt    # "connected" when ESP32 is live

# Kill the bridge manually (it restarts on next Pair)
pkill -f services.veya_core.bt_bridge
```

---

### Wi-Fi / BT coexistence note

On most Raspberry Pi models (including Pi 5), Wi-Fi and Bluetooth share the same
physical radio. Heavy BT-SPP traffic (e.g. continuous OBD-II streaming) can
occasionally degrade Wi-Fi throughput. For production use, prefer wired Ethernet
for any high-bandwidth network tasks when BT-SPP is active.

---

## Misc

```bash
# Kill stale backend process
pkill -f services.veya_core.core

# Kill stale UI process
pkill veya_ui

# Kill both
pkill veya_ui; pkill -f services.veya_core.core

# Check port 8765 is listening
ss -ltnp | grep 8765

# RPi CPU temperature
vcgencmd measure_temp

# Smoke-compile all Python in the package
python -m compileall -q ~/veya/services/veya_core

# Force Ctrl+Shift+W warning test via evdev (see MEMORY.md §6 for full one-liner)
# — triggers debugForceWarnings for 10 s without touching the UI
```

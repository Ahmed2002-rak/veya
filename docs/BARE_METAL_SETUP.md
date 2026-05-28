# VEYA — Bare Metal Restore Guide

> **Goal:** Flash a fresh SD card and reach a working VEYA kiosk in under one hour.
> The code lives on GitHub. Everything else (apt packages, kiosk autostart, Python venv,
> `~/.veya/` configs, systemd units) is documented here.

**Before anything else:** run `scripts/backup_configs.sh` on the live Pi and copy the
resulting tarball OFF the Pi (laptop, cloud, GitHub release). A backup sitting on the
dying card is worthless.

---

## Quick-reference checklist

| Step | What it achieves |
|------|-----------------|
| 1. Flash OS | Blank Debian trixie (Raspberry Pi OS) |
| 2. Boot / SSH | Network, hostname, user `pfe` |
| 3. apt deps | Qt6 dev, bluez, Python, build tools |
| 4. Clone repo | `/home/pfe/veya` |
| 5. Python venv | `.venv` with bleak, dbus-fast, websockets, obd, requests |
| 6. Bluetooth setup | `bt-agent.service` + user in bluetooth group |
| 7. Build Qt UI | `ui/build/veya_ui` binary |
| 8. Kiosk autostart | autologin + `~/.bash_profile` → `start_veya.sh` |
| 9. Restore configs | `~/.veya/` from backup tarball |
| 10. Pair ESP32 | BLE scan + pair from Settings screen |
| 11. Verify | Checklist at the bottom |

---

## Step 1 — Flash Raspberry Pi OS

**Exact OS running on this Pi:**
```
Debian GNU/Linux 13 (trixie), kernel 6.18.29+rpt-rpi-2712, aarch64
```

Use **Raspberry Pi Imager** (https://www.raspberrypi.com/software/):

1. Choose OS → **Raspberry Pi OS (64-bit)** — pick the **Lite** (no desktop) variant;
   VEYA runs on the framebuffer directly, no X11 needed.
2. In the gear/settings menu before flashing:
   - Set hostname: `raspberrypi`
   - Enable SSH (with public-key or password auth)
   - Set username: `pfe` (the hardcoded user throughout all scripts)
   - Set your Wi-Fi SSID + password
3. Flash to SD card, insert into Pi, power on.

> **[VERIFY]** The exact Raspberry Pi OS image that ships trixie/6.18 may change.
> If the imager only offers Bookworm, use that and verify kernel version with `uname -a`
> after boot — the packages listed below are for trixie. Package names may differ on
> Bookworm but the set is the same.

---

## Step 2 — Enable SSH, set hostname, connect to network

If you used Raspberry Pi Imager's advanced settings in Step 1, SSH and Wi-Fi are already
configured. Skip to verifying connectivity:

```bash
# From your laptop, find the Pi's IP (check your router, or use:)
ping raspberrypi.local

# SSH in
ssh pfe@raspberrypi.local
```

If you need to configure Wi-Fi after the fact:

```bash
# On the Pi console or over serial:
sudo nmtui          # NetworkManager TUI — add Wi-Fi connection
# or
sudo raspi-config   # Network Options → Wi-Fi
```

---

## Step 3 — Install system apt dependencies

```bash
sudo apt-get update && sudo apt-get upgrade -y

# Build tools
sudo apt-get install -y \
    build-essential \
    cmake \
    ninja-build \
    git

# Python
sudo apt-get install -y \
    python3 \
    python3-dev \
    python3-venv \
    python3-pip

# Qt6 — runtime + development headers
sudo apt-get install -y \
    qt6-base-dev \
    qt6-base-dev-tools \
    qt6-declarative-dev \
    qt6-declarative-dev-tools \
    qt6-websockets-dev \
    qt6-svg-dev \
    qt6-qpa-plugins \
    libqt6svg6 \
    libqt6websockets6

# Bluetooth stack
sudo apt-get install -y \
    bluez \
    bluez-tools \
    bluetooth

# GLib dev headers — required by bleak/dbus-fast build
sudo apt-get install -y \
    libglib2.0-dev \
    dbus
```

Confirm Qt6 is findable by CMake:

```bash
dpkg -l | grep qt6-base-dev   # should show 6.8.x
```

---

## Step 4 — Clone the repository

```bash
cd /home/pfe
git clone https://github.com/Ahmed2002-rak/veya.git veya
cd veya
```

> The deploy path is hardcoded as `/home/pfe/veya` in `start_veya.sh` and
> `~/.bash_profile`. Use exactly this path.

> Note: this uses HTTPS so it works on a fresh card without SSH keys.
> If you later want to push from this Pi, switch the remote to SSH:
> git remote set-url origin git@github.com:Ahmed2002-rak/veya.git

---

## Step 5 — Create the Python venv and install dependencies

```bash
cd /home/pfe/veya
python3 -m venv .venv
source .venv/bin/activate

# Core runtime (websockets is in requirements.txt; the rest were added manually)
pip install \
    "websockets>=16.0" \
    "bleak>=3.0.2" \
    "dbus-fast>=5.0.3" \
    "obd>=0.7.3" \
    "requests>=2.32.5"

# Verify
pip show bleak dbus-fast websockets obd requests
```

**Why these packages:**

| Package | Used by |
|---------|---------|
| `websockets` | `veya_core` WS server and all sources |
| `bleak` | `ble_bridge.py` — BLE connection to ESP32-S3 |
| `dbus-fast` | Required by bleak on Linux for D-Bus BLE backend |
| `obd` | `elm327_source.py` — ELM327 USB OBD-II adapter |
| `requests` | Session upload / live telemetry reporting |

> **Note:** `requirements.txt` at repo root only declares `websockets>=16.0`.
> The remaining packages were installed manually. If you add more later, update
> `services/veya_core/requirements.txt` so this guide stays accurate.

---

## Step 6 — Run Bluetooth setup

The script `scripts/setup_bluetooth.sh` is idempotent and safe to re-run:

```bash
cd /home/pfe/veya
bash scripts/setup_bluetooth.sh
```

What it does:
1. `apt-get install -y bluez bluez-tools`
2. Writes `/etc/systemd/system/bt-agent.service` (NoInputNoOutput auto-pairing agent)
3. `systemctl enable --now bt-agent.service`
4. Adds user `pfe` to the `bluetooth` group
5. `bluetoothctl power on`

Verify:

```bash
systemctl is-active bt-agent.service   # should print: active
id pfe | grep bluetooth                # should include "bluetooth"
```

> **Reboot after this step** if the `pfe` user was just added to the bluetooth group,
> otherwise BLE operations will fail with permission errors.

---

## Step 7 — Build the Qt UI

```bash
cd /home/pfe/veya/ui
mkdir -p build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j4
```

Build time: ~5–10 minutes on a Pi 5. The binary lands at:

```
/home/pfe/veya/ui/build/veya_ui
```

Confirm it exists:

```bash
ls -lh /home/pfe/veya/ui/build/veya_ui
```

> **[VERIFY]** If cmake errors with "Could not find Qt6", ensure `qt6-base-dev` and
> `qt6-declarative-dev` are installed. On some trixie/Bookworm builds you may also need:
> `sudo apt-get install -y qt6-image-formats-plugins qt6-shadertools-dev`

---

## Step 8 — Configure kiosk autostart

VEYA uses a framebuffer kiosk: the Pi auto-logs in on tty1, `~/.bash_profile` detects
tty1 and execs `start_veya.sh`.

### 8a — Enable autologin on tty1

```bash
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sudo tee /etc/systemd/system/getty@tty1.service.d/autologin.conf > /dev/null <<'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pfe --noclear %I $TERM
EOF

sudo systemctl daemon-reload
sudo systemctl restart getty@tty1
```

### 8b — Write ~/.bash_profile

```bash
cat > /home/pfe/.bash_profile <<'EOF'
# VEYA kiosk (linuxfb) on tty1
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    export QT_QPA_PLATFORM=linuxfb

        # Start VEYA (single entrypoint)
    exec /home/pfe/veya/start_veya.sh
fi
EOF
```

> **If you restored `~/.bash_profile` from the backup tarball, skip this step** —
> the restored file already contains this content.

### How it all connects

```
systemd → getty@tty1 (autologin pfe) → bash login shell
  → ~/.bash_profile → detects tty1 → exec start_veya.sh
    → activates .venv → starts veya_core (Python) → starts veya_ui (Qt)
```

---

## Step 9 — Restore ~/.veya configs

### Option A — From backup tarball (preferred)

```bash
# Copy the tarball from your laptop to the Pi
scp veya_config_backup_YYYYMMDD.tar.gz pfe@raspberrypi.local:/home/pfe/

# On the Pi, extract to /
cd /
sudo tar -xzf /home/pfe/veya_config_backup_YYYYMMDD.tar.gz
```

The tarball preserves full paths from `/`, so everything lands in the right place.

### Option B — Recreate manually

If you have no backup, recreate the three files:

```bash
mkdir -p ~/.veya

# bt_config.json — fill in your ESP32's MAC address
cat > ~/.veya/bt_config.json <<'EOF'
{
  "esp32_mac": "XX:XX:XX:XX:XX:XX",
  "rfcomm_channel": 1,
  "last_paired": "",
  "transport": "ble"
}
EOF

# server_config.json — fill in your report server URL
cat > ~/.veya/server_config.json <<'EOF'
{
  "report_url": "",
  "live_session_url": "",
  "last_updated": ""
}
EOF

# user_profile.json — fill in driver details
cat > ~/.veya/user_profile.json <<'EOF'
{
  "driverName": "",
  "emergencyContact": "",
  "carMake": "",
  "carModel": "",
  "carYear": "",
  "carFuelType": "Gasoline",
  "carVIN": "",
  "savedAt": ""
}
EOF
```

The driver profile and server URL can also be set from the VEYA Settings screen after
first boot.

---

## Step 10 — Pair the ESP32 (BLE)

Boot the Pi (or just run `start_veya.sh` from SSH). On the dashboard:

1. Navigate to **Settings → Bluetooth**
2. Tap **Scan** — the ESP32-S3 should appear (it advertises as `VEYA-BLE-OBD-001`)
3. Tap the device to pair
4. After pairing, `~/.veya/bt_config.json` is updated with `esp32_mac` and `transport: "ble"`

To verify the pairing via CLI:

```bash
cat ~/.veya/bt_config.json   # esp32_mac should be populated
systemctl is-active bt-agent.service   # active
bluetoothctl devices   # paired device should appear
```

---

## Step 11 — Verification checklist

Run these in order; each one depends on the previous.

```bash
# 1. Python venv is functional
source /home/pfe/veya/.venv/bin/activate
python -c "import bleak, websockets, dbus_fast, obd, requests; print('OK')"

# 2. Qt binary exists
ls -lh /home/pfe/veya/ui/build/veya_ui

# 3. bt-agent is running
systemctl is-active bt-agent.service

# 4. Configs exist
ls ~/.veya/

# 5. Smoke-test: start core in mock mode (no ESP32 needed)
cd /home/pfe/veya
source .venv/bin/activate
python -m services.veya_core.core --mode mock --hz 5 &
sleep 2
# Should print "WS listening on ws://127.0.0.1:8765"

# 6. WebSocket reachable
ss -ltnp | grep 8765

# 7. Kill test backend
pkill -f veya_core

# 8. Full kiosk launch (only if you have a display connected)
./start_veya.sh
```

If step 5 hangs or errors, check `logs/obd_service.log`. If step 6 shows nothing,
check `logs/kiosk.log`.

---

## Backup reminder

Run this on the live Pi at least once per week (or before any risky change):

```bash
bash /home/pfe/veya/scripts/backup_configs.sh
```

Then copy the tarball off the Pi:

```bash
# From your laptop:
scp pfe@raspberrypi.local:/home/pfe/veya/backups/veya_config_backup_YYYYMMDD.tar.gz .
```

Or upload it to a GitHub Release, a USB drive, or any cloud storage. The whole point is
that the backup must not live only on the SD card.

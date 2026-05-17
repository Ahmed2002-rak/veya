# VEYA ESP32 Bluetooth-Classic Sample Firmware

## Setup

1. **Board Manager** — File → Preferences → add Espressif URL, then install "esp32 by Espressif Systems" (2.x+)
2. **Board selection** — Tools → Board → ESP32 Dev Module (or DOIT DevKit v1, NodeMCU-32S)
   - **NOT** ESP32-C3/S2/S3 — those lack Bluetooth-Classic hardware
3. Connect ESP32 via USB, select port, click Upload

## Verify Boot

Open Serial Monitor at **115200 baud** — you should see:
```
VEYA ESP32 sample — BT-Classic SPP server starting
```

## Connect from Pi

1. Open **Bluetooth** page in the VEYA UI
2. Tap **Refresh** — look for **VEYA-OBD-SAMPLE**
3. Tap **Pair** — `bt_bridge.py` auto-starts and forwards telemetry to the core

## Plug In Real OBD Code

1. In `setup()` — initialize your OBD/CAN module
2. In `loop()` — replace the hardcoded values (marked with comment) with real reads

## bluez Discoverability (Linux 5.66+)

Modern bluez filters BT-Classic devices that lack a Class of Device (CoD) byte or SDP
service records from its internal D-Bus device cache. Without this, `bluetoothctl scan on`
never surfaces the ESP32, and `pair <mac>` fails with "Device not available" even though
`hcitool scan` finds it.

This sketch fixes that by:
- Setting a non-zero CoD (`ESP_BT_COD_MAJOR_DEV_AV`) via `esp_bt_gap_set_cod()` before
  `SerialBT.begin()`, so bluez recognises the device as a real BT-Classic peripheral.
- Calling `esp_bt_gap_set_scan_mode(ESP_BT_CONNECTABLE, ESP_BT_GENERAL_DISCOVERABLE)`
  after `SerialBT.begin()` to ensure the device responds to bluez inquiry scans.

**Required Arduino core:** Espressif ESP32 core 2.0.14 or later. Older versions may have
a different `esp_bt_gap_set_scan_mode` signature that takes only one argument.

## Known Limitations

- All sensor values are hardcoded (850 rpm, 0 km/h, 85 °C, etc.)
- No real OBD reading; no error handling for BT edge cases
- No Bluetooth security (any device can connect)

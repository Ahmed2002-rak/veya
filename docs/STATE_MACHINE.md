# VEYA — Source State Machine

> Phase 3.0h: automatic ESP32 detection without manual toggle/unpair/re-pair.

---

## States

```
State A  UNPAIRED       No MAC in ~/.veya/bt_config.json
State B  WAITING_REAL   MAC configured, bridge running, ESP32 not yet connected
State C  REAL           Bridge connected to ESP32, telemetry flowing
State D  MOCK_FORCED    User explicitly toggled to MOCK while bridge was/could be connected
```

| State | mock running | bridge running | UI badge | Waiting banner |
|-------|:---:|:---:|----------|----------------|
| A     | ✓   | ✗   | MOCK     | hidden         |
| B     | ✓   | ✓   | MOCK     | "Waiting for OBD device..." (amber) |
| C     | ✗   | ✓   | ELM      | hidden         |
| D     | ✓   | ✗   | MOCK     | hidden         |

---

## Transitions

```
A ──[bt_pair]──────────────────────────────► B
B ──[ESP32 powers on, bridge connects]──────► C   (auto — no user action)
C ──[ESP32 powers off, bridge disconnects]──► B   (auto — no user action)
B/C ──[user toggles to MOCK]────────────────► D   (bridge killed, override sticky)
D ──[user toggles to REAL]──────────────────► B   (bridge respawned)
B/C ──[bt_unpair]───────────────────────────► A
```

Automatic transitions (B↔C) are driven by `ws_server._bt_bridge_state_watcher()` polling
`/tmp/veya_bt_bridge_status.txt` every 1.5 s. When `_user_forced_mock` is True (State D),
the watcher skips the B→C transition even if the bridge reports "connected".

---

## Files involved

| File | Role |
|------|------|
| `services/veya_core/core.py` | `_user_forced_mock` flag, `transition_to_real_if_allowed()`, `transition_to_mock_with_bridge_retry()` |
| `services/veya_core/ws_server.py` | Bridge watcher, boot auto-spawn, `waiting_for_bt` injection |
| `services/veya_core/bt_bridge.py` | Writes `/tmp/veya_bt_bridge_status.txt`; retry loop |
| `ui/qml/providers/VehicleDataProvider.qml` | `waitingForBt` property |
| `ui/qml/Drive.qml` | Source banner visibility + text |

---

## Smoke tests (run from SSH)

### Test 1 — State B → C auto-transition (ESP32 powers on)

```bash
# 1. Boot Pi with MAC already in ~/.veya/bt_config.json (from a previous pair).
# 2. Verify bridge was spawned:
grep "boot: spawning bt_bridge" ~/veya/logs/obd_service.log

# 3. Open Drive screen — should show MOCK badge + amber "Waiting for OBD device..." banner.

# 4. Power on the ESP32.

# 5. Within ~10 s, confirm auto-switch:
grep "auto-switched to REAL on bridge connect" ~/veya/logs/obd_service.log

# 6. Drive UI now shows ELM badge, banner hidden, real telemetry flowing.
```

Expected log sequence:
```
[ws] boot: spawning bt_bridge for MAC AA:BB:CC:DD:EE:FF
[ws] bridge state changed: disconnected → connected
[core] bridge connected — auto-switching to REAL mode
[ws] auto-switched to REAL on bridge connect
```

---

### Test 2 — State C → B auto-transition (ESP32 powers off)

```bash
# 1. With ESP32 connected (State C, ELM badge visible).
# 2. Power off the ESP32.
# 3. Within ~10 s (bridge detects BT disconnect + 5 s retry interval):
grep "auto-switched to MOCK+bridge-retry" ~/veya/logs/obd_service.log

# 4. Drive UI returns to MOCK badge + amber waiting banner.
# 5. Mock data resumes (synthetic telemetry flowing again).
```

Expected log sequence:
```
[ws] bridge state changed: connected → disconnected
[core] bridge disconnected — switching to mock (bridge will retry)
[ws] auto-switched to MOCK+bridge-retry on bridge disconnect
```

---

### Test 3 — State D persistence (user forces MOCK, ESP32 reconnects)

```bash
# 1. With ESP32 connected (State C, ELM badge).
# 2. Tap the MOCK toggle on the Home screen.
# 3. Verify bridge killed:
grep "bridge killed, user_forced_mock set" ~/veya/logs/obd_service.log

# 4. Let the ESP32 stay on or re-power it. Bridge is killed so it cannot
#    auto-switch back to REAL regardless of ESP32 state.
# 5. Drive shows MOCK badge, no waiting banner (State D).
# 6. Tap the REAL toggle on Home → bridge respawns, transitions to State B then C.
grep "set_mode=elm — respawned bridge" ~/veya/logs/obd_service.log
```

Expected State D log:
```
[ws] set_mode=mock — bridge killed, user_forced_mock set
[core] set_mode=mock — user_forced_mock set
```

Expected return-to-REAL log:
```
[ws] set_mode=elm — respawned bridge for MAC AA:BB:CC:DD:EE:FF
[core] set_mode=real — user_forced_mock cleared
[ws] bridge state changed: disconnected → connected
[ws] auto-switched to REAL on bridge connect
```

---

## Edge cases

| Situation | Behaviour |
|-----------|-----------|
| Bridge proc exits (crash) | Watcher sees "disconnected", calls `transition_to_mock_with_bridge_retry`. Bridge is NOT respawned automatically — user must toggle REAL again. |
| Core restarts with MAC configured | `ws_server.start()` calls `_bt_boot_auto_spawn()`, bridge is spawned immediately. |
| Stale "connected" file from previous crash | `bt_bridge.run()` writes "disconnected" at startup, clearing stale state before the watcher initialises. |
| User pairs while already in State C | `bt_pair` resets `_user_forced_mock = False`; existing bridge is stopped and a new one started. |

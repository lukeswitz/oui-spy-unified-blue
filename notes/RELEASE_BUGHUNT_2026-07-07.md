# OUI-SPY release bug-hunt — 2026-07-07 (autonomous session)

Branch `companion`, tree at HEAD + uncommitted fixes below. **Nothing committed** (per your git rules).
Everything is compile/analyze/test-verified; **app + Android + firmware runtime is UNVERIFIED** (no device
in this session — you flash/build). No workarounds; every change is a root-cause fix.

## Verification bar reached
- Firmware: `pio` SUCCESS on `v3_app_controlled`, `v3_node_manager_xiao_c3`, `v3_node_manager_wroom`, `v3_node_manager_s3`.
- App: `flutter analyze` clean on every touched file; `flutter test` suite exit 0 (all pass).
- HW / on-device app behavior: **PENDING you** (flash all boards, Xcode build, walk-test).

Struct/wire format UNCHANGED → **old nodes stay compatible**, but reflash all boards to get the fixes.

---

## FIXED (landed in working tree)

### Firmware
1. **skyspy OOB read** (`skyspy.cpp` wifiCallback) — read `payload[4..9]` with no length check; a short MGMT
   frame → out-of-bounds read of the driver DMA buffer. Added `if (length < 24) return;` (matches wardrive/flock_wifi). CONFIRMED.
2. **wardrive + foxhunter fought over the WiFi channel** (`wardrive.cpp`, `foxhunter.cpp`) — both called
   `esp_wifi_set_channel()` on their own timers, ignoring the `wifiCoexShouldHop()` arbiter every other engine
   honors. When both scan (e.g. hunt-a-target-while-wardriving) the radio thrashed. Now gated on the arbiter. CONFIRMED.
3. **Node ACK hijacked the scan radio** (`mesh_espnow.cpp`) — every manager command ACK (and each retry, up to
   20×) did a 14-channel `sendOneSweep` = ~84 ms radio yank off the scan channel. The manager always lives on
   ch1, so the sweep was pure waste. New `sendOnHomeRestore()` sends on ch1 **and restores the node's scan
   channel** (a bare `sendOnHome` would strand the node on ch1). CONFIRMED.
4. **BLE supervision timeout 4s → 6s** (`ble_gatt.cpp:772`) — 4s is too aggressive for walk-away/marginal RF
   (Apple caps at 6s; verified vs Apple Accessory Design Guidelines). More grace before the link drops = fewer
   spurious disconnects → fewer reconnect cycles. Directly helps the "walk out of range and back" complaint.

### App
5. **Foxhunter detections misparsed every proximity beep** (`ble_protocol.dart`) — 19-byte bare-header events
   weren't in the `v31Sizes` table and the fallback only rescued `wardrive`, so they decoded as legacy v3.0 →
   `source_node_id` dropped (mesh-relayed foxhunter hits mis-attributed to local), trailing bytes read as garbage.
   Current firmware **always** sends v3.1, so the fallback now defaults any length ≥ full v3.1 header to v3.1. CONFIRMED.
6. **UniPwn device name was garbage** (`ble_protocol.dart`) — decoded `deviceName` from `ext[5..25]`, but firmware
   only packs `robot_type[8]+exploited[1]`; those bytes don't exist. Removed the bogus decode. CONFIRMED.
7. **`wigle_uploads` table missing on upgraded installs = data loss** (`app_database.dart`) — the table was added
   to the Drift table list but never got an `onUpgrade` `createTable` step, so any DB created before it existed
   lacks it permanently (upload history silently fails to persist). Bumped `schemaVersion` 4→5 + idempotent
   guarded `createTable(wigleUploads)` so already-at-4 broken installs re-run the repair. No codegen needed. CONFIRMED.
8. **Manager reconnect under-restored BLE nodes** (`wardrive_state.dart` `_reEnableEngines`) — used `activeEngines`
   (single `radio` field) instead of `_fleetEngines` (forces both flock variants for per-node radio routing), so a
   grace-expired manager reconnect could re-enable flock-WiFi but not flock-BLE fleet-wide. Now mirrors `startSession`. CONFIRMED (manager-only).
9. **Silent DB-write loss now visible** (`wardrive_state.dart`, `wigle_provider.dart`) — `insertSession` /
   `insertDetection` / `insertWigleUpload` were fire-and-forget; a throw (missing table, disk full) left in-memory
   state diverged from the DB with no signal. Added `.catchError` logging.

### Android
10. **Legacy BT perms hygiene** (`AndroidManifest.xml`) — `BLUETOOTH` / `BLUETOOTH_ADMIN` now carry
    `android:maxSdkVersion="30"` per Google's BLE-migration guide (no-ops on API 31+, but the documented pattern).

---

## NEW DETECTIONS (Marauder/Bruce-inspired, all passive)

All fold into `ENGINE_DETECTOR` (the engine bitmask is **full at 8/8** — a new engine ID would force a
uint16 mask widening through firmware + mesh + app, so these ride the existing `ext.detector` slot = **no wire
change, old nodes compatible**). They emit standard `DetectionEvent`s → mesh-forward + auto-pcap + logging for free.
The human label rides `ext.detector.filter_desc`; app method strings extended (`tracker`/`flipper`/`deauth_storm`).

- **Find My / AirTag tracker** — BLE mfg-data sig `0x4C 0x00 0x12` (Apple offline-finding). Anti-stalking. Runs in detector BLE mode.
- **Flipper Zero** — BLE advertised-name prefix `Flipper`. Runs in detector BLE mode.
- **Deauth/disassoc storm** — WiFi mgmt subtype `0xC0/0xA0`, rate-gated (≥10/s, 10s alert cooldown), reports the
  attacker/AP addr2. "Someone's attacking WiFi near you." Runs in detector WiFi mode.
- **Probe-request client tracker** — WiFi probe-req (subtype `0x40`) with a **directed** SSID (skips the common
  wildcard probe to avoid flood), MAC-deduped. Reveals which saved networks nearby phones/laptops are calling out
  for. `filter_desc` carries the SSID. Runs in detector WiFi mode.
- **Pwnagotchi detector** — WiFi beacon (subtype `0x80`) from the magic MAC `de:ad:be:ef:de:ad`, 15s cooldown.
  Zero false positive, novelty. Runs in detector WiFi mode.

**Known limitation:** these run when the **Detector** engine owns the radio, not while **Wardrive** owns it (detector
goes passive under wardrive). To make them always-on during wardrive, wardrive's own BLE/WiFi callbacks would need to
call `detectorCheckSignatures()` / the deauth check — a follow-up. For now: enable the Detector engine (BLE and/or WiFi).

---

## NOT DONE — needs your decision + a device (deliberately not blind-merged)

These are the two highest-value remaining items. Both are **app/Android-runtime and I can't verify them here**;
both touch high-blast-radius paths where a subtle wrong guess is worse than the current bug. Ready-to-apply below.

### A. `autoConnect:true` for background reconnect  ← the core of "walk back in range → resume"
Root cause (confirmed by trace + web): every reconnect uses `device.connect(autoConnect:false)` — a one-shot
attempt driven only by a Dart `Timer`, which iOS **suspends** while the phone's backgrounded. So the retry never
fires until you foreground the app. `autoConnect:true` hands the persistent "reconnect when seen" registration to
CoreBluetooth/BlueZ (works while suspended). I did **not** blind-merge it because it changes `connect()` semantics
(returns immediately; setup must be driven off `connectionState`, `mtu:null` required) and a bug there could
regress the **working** initial-connect path — untestable without your device.

Apply (keep initial connect as-is; fork only the reconnect path):
```dart
// _attemptReconnect / _startReconnect path only — NOT the user-initiated first connect.
// 1. connect with autoConnect:true (returns immediately, survives background):
await device.connect(autoConnect: true, mtu: null);   // mtu:null is REQUIRED with autoConnect:true
// 2. do NOT run _doConnect setup inline. Instead drive it from the connectionState listener:
device.connectionState.listen((s) {
  if (s == BluetoothConnectionState.connected && _currentState != NodeConnectionState.ready) {
    _runPostConnectSetup(device);   // extract lines 543..764 of _doConnect into this method
  }
});
```
Refactor task: extract `_doConnect` lines 543–764 (everything after `await device.connect(...)`) into
`_runPostConnectSetup(device)`; initial connect calls it inline (unchanged behavior), reconnect calls it from the
`connected` event. Then **device-test**: start wardrive, pocket the phone, walk out of range >1 min, walk back →
scan resumes with no tap.

### B. Android foreground service  ← the Android half of the same bug + "Android drops detections in background"
Root cause (confirmed): there is **no real foreground service**. The only FGS is geolocator's, and only when the
wardrive/drone-map screen is open — flock/detector-only sessions get zero FGS, so Android freezes the Dart isolate
on screen-off and the GATT stream + reconnect Timer die. `FOREGROUND_SERVICE_CONNECTED_DEVICE` is declared but
never used; `startService` (not `startForegroundService`) means it dies with the task.

Design fork (your call — I won't pick blind):
- **Recommended: add `flutter_foreground_task`** (maintained, what most production Flutter BLE apps use; handles the
  API-34/35 `startForeground`-within-5s / `foregroundServiceType` / notification-channel footguns for you). Keeps the
  process (and thus the main-isolate BLE manager) alive in background. Start it when a wardrive session begins (app is
  foreground = satisfies API-34's "can't start FGS from background" rule); stop on session end + disconnect.
- Alternative: custom Kotlin FGS (`foregroundServiceType="connectedDevice|location"`, `stopWithTask="false"`,
  `startForeground()` first thing in `onStartCommand`, MethodChannel to start/stop from Dart). Leaner but you own every Android-version footgun.
- Either way: OEM battery-killers (Xiaomi/Samsung/OnePlus/Huawei) still kill a correct FGS — add a
  `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` prompt + dontkillmyapp.com deep-link (no code-only fix exists).

---

## FLAGGED firmware follow-ups (real, but substantial/edge — not touched this session)
- **Manager ESP-NOW RX runs inline in the WiFi task** (`mesh_espnow.cpp` `onEspNowRecv`, manager branch) — 48 blocking
  `Serial.printf` + mutex + GATT-notify inside the WiFi driver callback (the node correctly offloads to a worker
  task; manager doesn't). Under fleet load can stall/drop RX. Fix = give the manager the node's `meshRxQueue`+worker
  pattern. Substantial restructure; PLAUSIBLE field impact. **Recommend HW A/B before shipping.**
- **PCAP sender-task lifecycle** (`pcap.cpp`) — no session identity; a fast stop→restart (auto-pcap 0s cooldown, UI
  toggling) reuses live buffers + orphans an 8KB-stack task → torn capture bytes / zombie tasks. This is the recurring
  pcap-lockup class. Fix = block `pcapStop()` on a real completion semaphore, or refuse start while a sender handle
  exists. **Recommend fixing before heavy pcap use.**
- **MTU-aware notification gating** (`ble_gatt.cpp`) — 155-byte ODID / 86-byte PcapStats notifications aren't
  MTU-checked; if MTU negotiation fails (stays at 23) they truncate silently (NimBLE logging is compiled out).
  In practice iOS negotiates 185 and Android ≥247 so 155 fits — this only bites at the failed-negotiation edge.
  App-side already degrades gracefully now (fix #5). Firmware fix = track `onMTUChange` + count/skip oversized sends.
- Minor: mesh-relayed pcap reassembly has no stall timeout (silent drop, no counter); `radio_coex` dispatch iterates
  without the register/unregister critical section (bounded array, cosmetic).

## FLAGGED app follow-ups
- `autoConnectEnabled` defaults **off** → app killed by OS won't auto-reconnect on relaunch. Flip default to `true`,
  or auto-connect whenever `lastPrimaryDeviceId` exists. **Product decision — your call.**
- `GpsProvider.stop()` is unreachable → GPS + 2s push timer run for the whole process life. May be intentional
  (always-on location for home/drone screens) — confirm intent; if session-scoped, call `stop()` in `stopSession()`.
- Unbounded growth: `WardriveController` detection/route lists have no cap (unlike `AppState`'s 500); `loadSession()`
  bulk-loads a whole session. Scale gap on multi-hour sessions.
- Dead schema: per-geofence alert toggles (`alertOnFlock/Drone/New/Stalking`, `GeofenceAlerts` table) are never
  read/written — only `excludeFromWardrive` is wired. Inert, but implies finer geofence controls than exist.

## Recon coverage (this session)
6 parallel audit agents + 1 web-research agent (BLE MTU/conn-params/autoConnect + Android FGS, all sourced): reconnect
path, Android parity, GATT stack, firmware core (coex/mesh/race/mem), broad Dart (DB/gps/notif/export), Marauder/Bruce
feature scout. Agents also **verified clean** (no change needed): subscription re-establishment on reconnect
(re-discovers + re-subscribes every connect), write-with-response on config paths, engine-ID/state ordering,
flock/detector/wardrive/skyspy byte offsets, POST_NOTIFICATIONS + runtime permission branching, KillTaskService safety.

## Release checklist
- [ ] Flash **all** boards (node S3, mgr C3/WROOM) — reflash even though wire format is unchanged, to get the fixes.
- [ ] Xcode build the app; on-device walk-test the reconnect (needs patch A) + Android background (needs B).
- [ ] Decide forks: autoConnect:true (A), Android FGS package vs custom (B), `autoConnectEnabled` default.
- [ ] Verify new detections on device: enable Detector (BLE+WiFi); confirm AirTag/Flipper/deauth show with labels.
- [ ] Bump `FW_VERSION` (`protocol.h`) + app `pubspec.yaml` version per your scheme; write user-facing changelog.
- [ ] Consider the two "recommend HW A/B" firmware follow-ups (manager RX offload, pcap lifecycle) before release if pcap/fleet is a headline feature.

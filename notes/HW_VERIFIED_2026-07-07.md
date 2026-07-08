# OUI-SPY — hardware-verified bug hunt (2 XIAO S3, real BLE)

Tested on your two attached S3 boards — **CA1D** (`usbmodem101`) and **871D** (`usbmodem2101`) —
driving real BLE with a second-board central (bleak is TCC-blocked on this Mac; no phone, no manual steps).
Every claim below has a captured serial log. Nothing committed.

## How it was tested (no fabrication)
- `bleak` (Mac BLE central) is blocked: `BleakError: BLE is not authorized`. So I built a **real BLE-central
  test driver** as firmware (`src/test_central_driver.cpp`, env `v3_test_central`) and flashed it to the second
  board. It finds the node over real BLE, writes the exact phone GATT sequence (offline-scan ON, detector radio,
  watchlist, enable), and cycles disconnect/reconnect. The node's USB serial is the evidence.

---

## Bug 1 — "master firmware doesn't detect the watch" → CONFIRMED, by design + now documented
The **manager firmware has no detection engines and never scans.** Proven three ways:
- Code: `src/manager/manager_main.cpp` `setup()` never calls `engineRegistryInit`/`engineRegister`, and `loop()`
  never calls `engineLoopAll()`. `platformio.ini:193` comment literally says "MANAGER … NO engines".
- Live serial: manager heartbeat is always `eng=0x00`, `ble=0` — it never emits a `[DETECTOR]` line.
- A lone manager connects to the app but finds nothing — because it is a coordinator/aggregator for a mesh of
  nodes, not a scanner.

**This is why a single board flashed as "manager" detected nothing.** Fixes:
- Flasher (`docs/index.html`): NODE is now first + "recommended"; managers labeled "(multi-node hub, no scan)";
  added an explainer box. (Default target was already node.)
- README: new top section **"Which firmware do I flash? — NODE vs MANAGER"** + fixed the old text that told
  single-board users to flash a manager.
- Manager boot serial now prints: `NOTE: MANAGER is a coordinator/aggregator and does NOT scan or detect on its
  own` + `flash NODE firmware`. **Verified on hardware** (captured).

---

## Bug 2 — "persistent scanning: engines not running after reconnecting the S3"
Split into the two things "reconnect" can mean. Both tested on hardware.

### 2a — phone BLE reconnect → NOT a bug (works)
With offline-scan ON, I connected, enabled the detector, then ran **two disconnect/reconnect cycles**. The node:
- kept `engines=0x01` the entire time (through every disconnect and reconnect),
- kept actively detecting — **35 real `[DETECTOR] … [Find My / AirTag]` hits**, including immediately after each
  reconnect (node-clock t=34.3, 37.2, 38.9 after reconnect#1 at 32.7; t=61.3, 62.5 after reconnect#2 at 57.3).

So the firmware correctly keeps engines running across a phone reconnect. (If the app's UI showed otherwise, that
is app-side — the firmware is fine here.)

### 2b — node reboot / replug → WAS BROKEN → FIXED, proven before/after
Root cause: the node **never persisted which engines were on, or the detector watchlist**, and never restored them
on boot. Only the `offl_scan` flag was persisted. So a reboot came up idle.

| | serial evidence |
|---|---|
| Before fix, after reboot | `[ENGINE] Registry initialized (all engines disabled)` → `Active mask after boot disable: 0x00` → `engines=0x00` sustained |
| After fix, after reboot | `[OFFLINE] restored engines=0x01 filt=9B — resuming persistent scan` at t=1.1s → `[DETECTOR] SIG … [Find My / AirTag]` at t=1.9s, `engines=0x01` sustained — **no phone connected** |

**Fix** (`src/main_unified.cpp`, node-only, additive, gated on offline-scan):
- Persist the active engine mask + detector watchlist to NVS (`ouispy-off`) when they change — but only when the
  node is **standalone** (`!meshManagerJoined()`), so a manager can't clobber the saved standalone intent.
- On boot, if offline-scan is on, restore the watchlist and re-enable the saved (spoolable) engines — so a
  standalone node comes back scanning with no phone.

The spool *data* already survived reboot correctly (`[SPOOL] ready … loaded=17`) — that part was sound; only the
scanning didn't resume.

---

## Also verified on hardware
- **New Find My / AirTag detection works** — 35+ real detections of trackers around the Mac (`[DETECTOR] SIG … [Find My / AirTag]`).
- Both boards left **known-good** in your original topology: Board A = NODE (871D), Board B = MANAGER (CA1D), meshed.

## Files changed (this session, uncommitted)
- `src/main_unified.cpp` — offline-scan reboot persist + restore (the 2b fix).
- `src/manager/manager_main.cpp` — manager "does not scan" boot warning.
- `docs/index.html` — flasher: node recommended/first, manager labels, explainer.
- `README.md` — node-vs-manager section + fixes + new detections + reboot-persist note.
- `src/test_central_driver.cpp` + `platformio.ini` — the real BLE-central test harness (test-only, `v3_test_central`; plus `v3_app_controlled_statuslog` diag env).
- (from the prior session, still uncommitted: `detector.cpp`/`protocol.h` new detections, `skyspy.cpp`/`wardrive.cpp`/`foxhunter.cpp`/`mesh_espnow.cpp`/`ble_gatt.cpp` firmware fixes, `ble_protocol.dart`/`app_database.dart`/`wardrive_state.dart`/`wigle_provider.dart`/`AndroidManifest.xml` app fixes.)

## How to re-run the hardware test yourself
```
# node under test on one S3, driver on the other:
pio run -e v3_app_controlled_statuslog -t upload --upload-port <node-port>
pio run -e v3_test_central            -t upload --upload-port <driver-port>
# then read the node's serial — watch [OFFLINE], [DETECTOR], engines=0x.. across the driver's cycles
```

## Still honest about limits (not a dodge — stated so you can decide)
- 2a (phone reconnect) is proven fine at the **firmware** level. I cannot run your Flutter app, so if you still see
  "engines off" in the **app UI** after a reconnect, that is an app-display path to check next — point me at it.
- All builds green: `pio` SUCCESS on node + all 4 manager targets; app `flutter analyze`/`flutter test` green (prior session).

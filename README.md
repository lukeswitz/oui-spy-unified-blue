<div align="center">

[![Release](https://img.shields.io/github/v/release/lukeswitz/oui-spy-unified-blue?include_prereleases&label=pre-release&color=green)](https://github.com/lukeswitz/oui-spy-unified-blue/releases)
[![TestFlight](https://img.shields.io/badge/TestFlight-Join-blue.svg?logo=apple)](https://testflight.apple.com/join/5RCKgnJ2)
![Platforms](https://img.shields.io/badge/iOS%20%7C%20macOS%20%7C%20Android-1BA1E2)
![Firmware](https://img.shields.io/badge/firmware-ESP32--S3-ff6600)
[![CodeQL](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql)

<img width="220" alt="OUI-SPY APEX" src="https://github.com/user-attachments/assets/5a201c27-558b-4409-9e49-82d6e0176a4c" />

# OUI SPY APEX

**Eight surveillance-detection engines on one XIAO ESP32-S3. Controlled from your phone.**

This fork merges every mode into one image, runs them concurrently, and replaces the per-mode web AP with a 
companion app



[**Quick Start**](#quick-start) · [**Engines**](#engines) · [**App**](#companion-app) · [**Gestures**](#gestures) · [**Flash**](#flash) · [**Hardware**](#hardware)

</div>

---

## TL;DR

- One firmware. **Eight scan engines** — Detector, Flock BLE, Flock WiFi, Foxhunter, Sky Spy, UniPwn, Wardrive, PCAP.
- Runs them **concurrently** across WiFi promiscuous and BLE radios. Toggle from the app, live, no reboot.
- **Flutter companion app** for iOS / macOS / Android — full control, live feed, wardrive map, PCAP browser, OTA updates.
- PCAP capture streams over BLE to the phone — raw 802.11 (radiotap) and BLE LL (PHDR), saved as `.pcap` in the app, open in Wireshark.
- Imports / exports WiGLE-format CSVs. Direct WiGLE upload.

> Beta. File issues — bugs and odd behavior expected.

---

## Highlights

| | |
|---|---|
| **No mode switching** | Upstream required selecting a mode at boot and rebooting. Here every engine runs together. |
| **Auto-PCAP on hit** | Detector / Flock BLE / Flock WiFi / Sky Spy / UniPwn detection → device starts a capture, streams it to the phone for the configured duration (3–120 s), then resumes scanning. Cooldown + per-MAC rediscover window suppress repeats. |
| **OTA updates** | WiFi (STA) or BLE — pick from inside the app. |
| **39k+ OUI vendors** | Bundled IEEE database. Flock OUIs resolve to surveillance labels *and* the underlying chip vendor. |
| **Geofences** | Circle / polygon zones — app-side filter on feed, map, CSV. |
| **Dynamic Island** | iPhone 14 Pro+ / iOS 16.2+ — live counts on Lock Screen and Island. |

---

## Quick Start

**1 · Flash the device** — open the [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) in Chrome or Edge, plug in the XIAO ESP32-S3 via USB-C, hit Connect & Flash.

**2 · Install the app** — [Android APK](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest), [iOS / macOS TestFlight](https://testflight.apple.com/join/5RCKgnJ2), or [macOS signed .app](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest).

**3 · Connect over BLE** — open the app, tap **CONNECT**, then tap your device in the **SCAN FOR OUI-SPY** list. From here every engine, channel, watchlist, and PCAP is app-side.

> The app does **not** auto-connect. On launch it clears any stale BLE link and waits — you choose what to connect to (handy when juggling a manager + several nodes). Reconnecting is always one tap.

---

## Engines

Eight engines. Toggle independently from the home screen. All can run together (radio-time tradeoffs apply).

| # | Engine | Radio | Detects |
|---|--------|-------|---------|
| 1 | **Detector** | WiFi + BLE | Custom watchlist — MAC, OUI prefix, name patterns |
| 2 | **Flock BLE** | BLE | FS Ext Battery, Flock WiFi modules, Raven gunshot detectors — manuf ID `0x09C8`, GATT UUIDs, name |
| 3 | **Flock WiFi** | WiFi promisc | Flock Safety cameras — addr1/addr2 OUI, wildcard probe signature |
| 4 | **Foxhunter** | WiFi + BLE | RSSI proximity tracking of a chosen target — warm / close thresholds |
| 5 | **Sky Spy** | WiFi + BLE | FAA Remote ID drones — NAN action frames, vendor beacons, ODID adverts |
| 6 | **UniPwn** | BLE | Unitree robots (`Go2_`, `G1_`, `H1_`, `B2_`, `X1_`) — detect → connect → exploit |
| 7 | **Wardrive** | WiFi + BLE | WiGLE-style logging — SSID, BSSID, channel, auth, GPS |
| 8 | **PCAP** | WiFi or BLE | Raw 802.11 (radiotap) or BLE LL (PHDR), streamed live over BLE to the phone |

<details>
<summary><b>Flock detection — methodology</b></summary>

Flock-WiFi runs 802.11 promiscuous, hops 1/6/11 at 350 ms dwell, applies three methods:

- **addr2 OUI** — transmitter-side. 42 known Flock OUI prefixes.
- **addr1 OUI** — receiver-side. Catches Flock STAs that only appear as probe-response targets during burst-sleep. Skips mcast/bcast.
- **Wildcard probe** — Probe Request (type=0 sub=4), zero-length SSID IE, known addr2 OUI. From [DeFlockJoplin](https://github.com/DeflockJoplin/flock-you) field research (11/12 cameras, 2 FPs in Joplin drive-test).

Flock-BLE matches FS Ext Battery, Flock WiFi modules, and Raven detectors by company ID, name, and GATT UUID.

Both share `flock_oui.h` — **43 prefixes**: 10 FS Ext Battery (BLE, EFR32) · 26 [@NitekryDPaul](https://github.com/nitekry) original promiscuous-mode set · 6 April 2026 additions · 1 DeFlockJoplin wildcard-probe discovery.

Flock OUIs resolve in-app to surveillance labels *and* chip vendor, e.g. `Flock Safety (Falcon) · Liteon Technology`.

</details>

---

## Node Mode

Run several boards as one swarm: a **manager** the phone talks to, and any number of **nodes** that scan for it.

**What nodes add:** more radios working in parallel. The manager splits the WiFi channel range into disjoint slices across the live nodes, so two nodes cover the band roughly twice as fast as one — and they cover more physical ground. Every detection is tagged with the node that found it.

**Set it up:**

1. **Flash roles** — one board as **manager** (`mgr-xiao_c3` or `mgr-wroom`), the rest as **nodes** (`node-xiao_s3`). Use the [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) and pick the matching target per board.
2. **Power on** — nodes auto-join the manager in ~10 s. No pairing step.
3. **Connect the app to the *manager*** (not the nodes) — tap **CONNECT**, pick the `OUI-SPY-MGR…` device. **Config → NODES** lists every joined node as `LIVE` (older ones drop to `OFFLINE`).
4. **Run engines** — detection engines (Detector, Flock, Sky Spy, Wardrive, …) run across **all** nodes at once; the feed shows which node each hit came from. **PCAP** captures from **one** node you pick on the PCAP screen.
5. **Per-node radio (optional)** — when you **START** a WiGLE / WiGLE+Flock wardrive with nodes joined, a popup lets you set each node to **WiFi**, **BLE**, or **Both** (default Both). WiFi nodes split the channel range between them; a BLE-only node scans BLE continuously without taking a WiFi slice. The manager remembers each node's role.

Toggling an engine off, or closing the app, stops the nodes — they don't keep scanning unattended.

**Settings are manager-authoritative in node mode.** Device-wide settings changed on the manager — buzzer / LED / brightness, alert timing, and the ignore list — are pushed to **every** node and **override** each node's own copy. The single global Wardrive Radio toggle is likewise overridden by the per-node popup above. This is intentional (one place to drive the whole swarm) but can surprise you if you expected a node to keep its own setting: in node mode the manager's settings always win. Nothing is stored per-node in flash — the manager re-asserts the current settings continuously, so re-flashing or power-cycling a node never leaves it on a stale config.

---

## Companion App

Flutter app. iOS, macOS, Android. BLE GATT to the device. Every control, every readout.

### Home

- Per-engine cards — tap a card to open that engine's settings screen.
- Status bar — node count, GPS state, connection state.

**Connecting & disconnecting** (auto-connect is **off by default** — opt in at *Settings → App → Connection → Auto-connect on launch*, which reconnects to the last device at startup):

| Want to | Tap |
|---------|-----|
| **Connect** | **CONNECT** button on the home screen → pick your device from **SCAN FOR OUI-SPY** |
| **Disconnect / switch device** | The device-name chip (top-right of the status bar, `⇄` icon) → drops the link and reopens the scan list |
| **Cancel a connect in progress** | **CANCEL** |
| **Stop auto-reconnect after a drop** | **STOP RECONNECT** (the app retries a lost link on its own; this aborts it) |

### Live Feed

The full detection list across all engines.

| Control | What |
|--------|------|
| Stats toggle (`analytics` icon) | Show / hide vendor + engine breakdown header |
| Export icon (`ios_share`) | **CSV export of the current filtered view** |
| Preset chips | One-tap filter sets (all engines, surveillance only, etc.) |
| ENGINES dropdown | Per-engine include / exclude |
| SOURCE dropdown | Mesh node filter — `ALL` / `LOCAL` / specific remote node when mesh is active |
| SORT dropdown | Time / RSSI / MAC, asc / desc |
| Search | Free-text across MAC, name, vendor, SSID |
| Tap a row | Foxhunt or map-locate the device (when GPS available) |
| Long-press a row | Full copy sheet — MAC, vendor, RSSI, channel, manuf data, every field |

### Wardrive

The map screen — see detections plotted live as you drive / walk.

**Controls bar:**

| Control | What |
|---------|------|
| **START** / **PAUSE** / **RESUME** / **STOP** | Session lifecycle |
| Target mode | WiGLE · Flock · Drone · Detector · WiGLE+Flock |
| Radio | WiFi · BLE · both — in node mode a per-node popup on **START** overrides this for each node |
| Follow-mode (`my_location`) | Toggle camera-tracks-you |
| Layers (`layers` icon) | Map theme (dark / light) + tile source (CARTO Dark / Light / Voyager, OSM, OpenTopoMap, Stamen Toner / Terrain) |
| Geofence (`fence` icon) | Open geofence editor |
| History (`history` icon) | Saved sessions list |

**Live stats:** distance, session count, unique networks, route path color-graded by RSSI.

**Flock + Detector panels** appear inline when hits land — tap to expand the list. Each row has a **CSV** badge to export just that one network and a long-press copy sheet.

**Sessions list (history):**

| Per-session action | What |
|--------------------|------|
| Tap | Load session, replay route on map |
| Long-press | Enter multi-select |
| Share (`file_download_outlined`) | Share / save WiGLE CSV |
| WiGLE upload (`cloud_upload_outlined`) | Direct upload to WiGLE (your API key) — turns to `cloud_done` once accepted |
| Delete (`delete_forever_outlined`) | Remove session |
| **SELECT** / **CANCEL** / **DELETE** / **CLEAR ALL** | Bulk ops in select mode |

**WiGLE CSV import** — `Settings → OUI Database` (or wardrive history) accepts any WiGLE-format CSV. Every BSSID is matched against bundled OUI / Flock tables; surveillance hits are flagged on map and in feed.

### Per-Engine Screens

Open from the engine card on the home screen.

| Engine | Capabilities |
|--------|--------------|
| **Detector** | Live detection list (sort: TIME / RSSI / MAC). **Add Watchlist Target** dialog — full MAC or OUI prefix + name. |
| **Foxhunter** | Pick a target (**HUNT** button), live RSSI bar and channel display. Buzzer cadence scales with proximity. |
| **Sky Spy** | Live Remote-ID drone list — operator / UAV ID, lat-lon, altitude, ground speed, heading. |
| **UniPwn** | Detected Unitree robots + **exploitation actions**: `ENABLE SSH`, `CHANGE ROOT PASSWORD`, `GET SERIAL NUMBER`, `GET SYSTEM INFO`, `REBOOT`, and an `EXEC` field for arbitrary command execution. |

### PCAP

The device has no filesystem for captures. Frames are written to a double-buffer in RAM and streamed live over the BLE GATT PCAP characteristic to the phone, which writes the `.pcap` file locally.

| Mode | Captures |
|------|----------|
| **WiFi 802.11 (radiotap)** | Beacons, probes (req + resp), deauth, disassoc, data, control, management — hopping the chosen channel range (default 1–11, dwell 250 ms) |
| **BLE LL (PHDR)** | Adverts and scan req/resp with synthesized BLE link-layer headers and CRC24. Channels handled by the NimBLE scanner — no channel arg from the app. |

**Manual capture screen controls:**

| Control | What |
|---------|------|
| **START / STOP** | Capture lifecycle |
| WiFi / BLE mode toggle | Pick radio |
| Channel range slider | WiFi only |
| **SHARE LAST PCAP** | Re-share the last finished capture |
| Saved Captures list | Per-row share + delete, list refresh, delete-all |
| Live per-type counters | Beacons, probes, deauth, disassoc, data, ctrl, BLE adv, BLE scan, dropped frames, bytes |

**Auto-PCAP** — toggle once. When a Detector / Flock BLE / Flock WiFi / Sky Spy / UniPwn engine reports a hit:

- Firmware starts a capture for the configured duration (slider **3–120 s**).
- Cooldown slider (**0–600 s**) blocks new auto-captures after one finishes.
- Per-MAC rediscover window blocks the same target re-triggering.
- WiFi-engine triggers forward the channel the target was seen on; BLE-engine triggers ignore channel.
- Other engines pause for the capture window (`auto_pcap_paused_mask` reports which), resume after.

**Saved PCAP library** — `Settings → Detections → Saved PCAPs` (also accessible from the PCAP screen). Refresh, Delete-all, per-row Share (Wireshark / AirDrop / email), per-row Delete. `LIVE` badge on the currently-streaming file. PCAPs are auto-labeled with the engine and MAC that triggered them.

### OTA Firmware Updates

`Settings → Updates` is the main way to update — no cables. Tap **Check for Update**; the app compares the connected device against the latest GitHub release and offers:

- **Install (WiFi)** — give the device credentials once (`STATION MODE` section). Device joins your LAN, pulls the firmware. Fast.
- **Install (BLE)** — works anywhere, no router. Slow.

**Updating nodes (when connected to a manager):** the Updates tab also lists each live node under **NODES**. Tap **UPDATE** on a node and the app disconnects from the manager, connects straight to that node over BLE, flashes it, then reconnects to the manager — one node at a time. (Nodes are flashed directly; firmware isn't relayed over the mesh.) When the app is connected directly to a single device, Check for Update just updates that device.

App fetches release notes from GitHub Releases and shows the version available.

### Geofences

`Wardrive → fence icon` opens the geofence editor.

| Control | What |
|---------|------|
| **CIRCLE** | Draw a circular zone (RADIUS slider) |
| **POLYGON** | Tap-to-place vertices |
| **UNDO** / **CANCEL** / **SAVE** | Editor controls |
| Existing fences list | Edit / delete saved zones |

App-side filter: hits inside excluded zones are dropped from feed, map, DB, and CSV export.

### Export

`Settings → Export` — bulk export of all logged detections in:

- **WiGLE CSV 1.6**
- **JSON**
- **KML**

### Notifications

`Settings → Notifications`.

| Section | Controls |
|---------|----------|
| **Detection Alerts** | Per-engine toggles — Flock Safety, Watchlist / Detector, Drone / Sky Spy, Foxhunt Proximity |
| **Wardrive** | Milestone Alerts (every 1000 unique networks) |
| **Behavior** | Cooldown per device, Max alerts per minute |
| **Output** | Sound, Vibration |

### Device Settings (full section list)

`Settings` aggregates everything not specific to a feed or session:

| Section | What's in it |
|---------|--------------|
| **Appearance** | App theme, accent |
| **Units** | Distance, speed |
| **Wardrive — RSSI** | Min RSSI thresholds for logging |
| **Scan Timing** | Per-engine dwell, hop intervals |
| **Channel Range** | Default WiFi channel range |
| **OUI Database** | View / update the 39k+ vendor DB; import WiGLE CSVs |
| **WiGLE** | Log in / out, paste API token, view your WiGLE stats and rank |
| **Audio** | Buzzer volume (PWM) — one beep per detection (deduped, even when a device is seen on both BLE and WiFi) |
| **Lighting** | NeoPixel brightness |
| **Firmware Timing** | Rediscover window, auto-PCAP cooldown |
| **Station Mode** | WiFi credentials for OTA / mesh (with **WIPE** confirmation) |
| **Node Info** | Mesh node ID, peer list, encryption status |
| **Updates** | OTA Install (WiFi / BLE) |
| **Danger Zone** | **REBOOT** device · **ERASE & REBOOT** (factory reset) |
| **About** | Firmware build, app version |

Also in Settings: **Ignore List** (add by MAC, OUI prefix, SSID, or name; per-scope WiFi / BLE / both toggle) and **Watchlist** (Detector targets).

### iOS Dynamic Island & Live Activity

iPhone 14 Pro+ on iOS 16.2+. Active sessions show in the Dynamic Island and Lock Screen with engine icons and live counts. Wardrive takes the priority slot when multiple engines run; expanded view shows combined counts for all.

---

## Gestures

| Where | Action | Result |
|-------|--------|--------|
| Detection row | **Long-press** / right-click | Copy sheet — MAC, vendor, RSSI, channel, manuf data, every field |
| Wardrive row | **Long-press** / right-click | Network copy sheet |
| Flock item (wardrive) | **Long-press** | Flock-specific copy sheet |
| Session in history | **Long-press** | Enter multi-select |
| Device entry (config) | **Long-press** / right-click | Copy sheet |
| Detection row | **Tap** | Foxhunt or map-locate (when GPS available) |
| Engine card (home) | **Tap** | Per-engine settings |

---

## Flash

**Updates come from the app over OTA** (`Settings → Updates`, WiFi or BLE) — that's the main path once a board is running. The web flasher is for the **first flash on a bare board**, or as a recovery fallback.

### Web Flasher

[lukeswitz.github.io/oui-spy-unified-blue](https://lukeswitz.github.io/oui-spy-unified-blue/) — Chrome / Edge 89+. Plug in via USB-C, pick the target (node / manager board), Connect & Flash. *(Chromium only — Web Serial API.)*

### Layout

| File | Offset | Purpose |
|------|--------|---------|
| `bootloader.bin` | `0x0000` | ESP32-S3 bootloader |
| `partitions.bin` | `0x8000` | Partition table |
| `boot_app0.bin`  | `0xe000` | OTA data |
| `firmware.bin`   | `0x10000` | App-controlled firmware |

After the first flash, all updates come OTA from the app.

---

## Hardware

**Seeed Studio XIAO ESP32-S3** — USB-C · 8 MB flash · BLE 5 + WiFi · dual-core 240 MHz.

| Pin | Function |
|-----|----------|
| GPIO 3  | Piezo buzzer (PWM, app-controlled volume) |
| GPIO 4  | NeoPixel WS2812B (app-controlled brightness) |
| GPIO 21 | Onboard LED (active LOW) |
| GPIO 43/44 | Optional hardware GPS TX/RX (phone GPS relay otherwise) |

---

<details>
<summary><h2>Build from Source</h2></summary>

### Firmware (PlatformIO)

```bash
pio run -e v3_app_controlled            # build
pio run -e v3_app_controlled -t upload  # flash
pio device monitor                      # serial @ 115200
```

Dep: `NimBLE-Arduino`.

### Companion App (Flutter 3.32+)

```bash
cd companion
flutter pub get
flutter run                  # debug on attached device
flutter build apk --release
flutter build ipa --release
flutter build macos --release
```

**iOS Live Activity (optional):** the `OuiSpyLiveActivity` Widget Extension target provides Dynamic Island. In Xcode: File → New → Target → Widget Extension, name `OuiSpyLiveActivity`, add `OuiSpyLiveActivityAttributes.swift` to both Runner and the extension.

</details>

<details>
<summary><h2>Dependencies & Services</h2></summary>

### Firmware

| Library | Author | Purpose |
|---------|--------|---------|
| [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) | h2zero | BLE GATT server, scan, ESP-NOW coexist |
| [ESP Async WebServer](https://github.com/mathieucarbou/ESPAsyncWebServer) | mathieucarbou | OTA update server (LAN-only) |
| [Adafruit NeoPixel](https://github.com/adafruit/Adafruit_NeoPixel) | Adafruit | WS2812B |
| [ArduinoJson](https://github.com/bblanchon/ArduinoJson) | bblanchon | JSON config / mesh payloads |
| [TinyGPS++](https://github.com/mikalhart/TinyGPSPlus) | mikalhart | Hardware GPS (optional) |

Built on **ESP-IDF** via the Arduino core for ESP32-S3 — WiFi promisc, ESP-NOW, mbedTLS (AES-GCM mesh).

### App

| Package | Purpose |
|---------|---------|
| [flutter_blue_plus](https://pub.dev/packages/flutter_blue_plus) | BLE GATT |
| [flutter_map](https://pub.dev/packages/flutter_map) + [latlong2](https://pub.dev/packages/latlong2) | Map + geo math |
| [drift](https://pub.dev/packages/drift) + [sqlite3_flutter_libs](https://pub.dev/packages/sqlite3_flutter_libs) | SQLite sessions / detections |
| [geolocator](https://pub.dev/packages/geolocator) | Phone GPS, background loc |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | State |
| [go_router](https://pub.dev/packages/go_router) | Nav |
| [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) | Notifications |
| [dio](https://pub.dev/packages/dio) | HTTP (WiGLE API) |
| [share_plus](https://pub.dev/packages/share_plus) | Native share sheet |
| [freezed](https://pub.dev/packages/freezed) + [json_serializable](https://pub.dev/packages/json_serializable) | Models |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | Mesh key storage |
| [wakelock_plus](https://pub.dev/packages/wakelock_plus) | Keep awake during wardrive |
| [permission_handler](https://pub.dev/packages/permission_handler) | Perms |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Settings |
| [intl](https://pub.dev/packages/intl) | Date / number format |
| [uuid](https://pub.dev/packages/uuid) | Session IDs |
| [crypto](https://pub.dev/packages/crypto) | Hashing |

### APIs & Tile Services

| Service | Use |
|---------|-----|
| [WiGLE](https://api.wigle.net) | Wardrive CSV upload (user API key) |
| [CARTO](https://carto.com/basemaps/) | Dark / Light / Voyager tiles |
| [OpenStreetMap](https://www.openstreetmap.org/) | OSM raster |
| [OpenTopoMap](https://opentopomap.org/) | Topo |
| [Stadia Maps](https://stadiamaps.com/) | Stamen Toner / Terrain |

### Data

| Source | What |
|--------|------|
| [Ringmast4r/OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database) | 39k+ IEEE OUI vendors (gzipped TSV) |

### iOS Native

| Framework | Use |
|-----------|-----|
| ActivityKit | Live Activities / Dynamic Island (iOS 16.2+) |
| WidgetKit  | Widget extension |
| CoreBluetooth | BLE (via flutter_blue_plus) |
| CoreLocation | GPS (via geolocator) |

</details>

<details>
<summary><h2>Ecosystem (standalone forks)</h2></summary>

This repo is the unified firmware + app. Each engine also exists standalone:

| Project | What |
|---------|------|
| [OUI-SPY Detector](https://github.com/colonelpanichacks/ouispy-detector) | BLE/WiFi watchlist scanner |
| [OUI-SPY Foxhunter](https://github.com/colonelpanichacks/ouispy-foxhunter) | RSSI proximity tracker |
| [Flock You](https://github.com/colonelpanichacks/flock-you) | Flock Safety / Raven detector |
| [Sky-Spy](https://github.com/colonelpanichacks/Sky-Spy) | Drone Remote ID capture |
| [Remote-ID-Spoofer](https://github.com/colonelpanichacks/Remote-ID-Spoofer) | WiFi Remote ID spoofer + swarm |
| [OUI-SPY UniPwn](https://github.com/colonelpanichacks/Oui-Spy-UniPwn) | Unitree robot exploitation |

</details>

---

## Acknowledgments

- **Will Greenberg** ([@wgreenberg](https://github.com/wgreenberg)) — [flock-you](https://github.com/wgreenberg/flock-you). Manuf ID `0x09C8` (XUNTONG) detection and structured pattern approach.
- **@NitekryDPaul / OrdoOuroborous** ([@nitekry](https://github.com/nitekry)) — 42 Flock OUI prefixes from promisc-mode field testing; addr1 receiver-side technique.
- **Michael / DeFlockJoplin** ([DeflockJoplin](https://github.com/DeflockJoplin/flock-you)) — wildcard-probe signature from Joplin drive-test.
- **Author of the OUI-SPY ecosystem:** **colonelpanichacks**.

---

## Disclaimer

Security research and privacy auditing tool. Detecting surveillance hardware in public spaces is legal in most jurisdictions. Comply with local laws on wireless scanning and signal interception. Authors not responsible for misuse. GATT during pairing carries risk. Lawful use only.

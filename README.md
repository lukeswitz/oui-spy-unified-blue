<div align="center">
<h2>OUI SPY APEX</h2>

[![Version](https://img.shields.io/github/v/release/lukeswitz/oui-spy-unified-blue?include_prereleases&label=pre-release&color=green)](https://github.com/lukeswitz/oui-spy-unified-blue/releases) [![Join TestFlight Beta](https://img.shields.io/badge/TestFlight-Join-blue.svg?style=f&logo=apple)](https://testflight.apple.com/join/5RCKgnJ2) ![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20Android-1BA1E2)
![Dart](https://img.shields.io/badge/Dart-Flutter%20App-0175C2)
![C++](https://img.shields.io/badge/C%2B%2B-ESP32%20FW-ff6600)
[![CodeQL](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql)

<img width="500" alt="ouispy_appicon" src="https://github.com/user-attachments/assets/5a201c27-558b-4409-9e49-82d6e0176a4c" />

[Features](#what-it-detects) | [Get the App](#install) | [Flash Firmware](#flash-it)

</div>

---


**About this fork:**

- Unified multi-engine surveillance detection firmware for the XIAO ESP32-S3. Runs eight scan engines simultaneously using both WiFi and BLE radios. Controlled entirely from a companion app over BLE GATT.
- Combines all standalone OUI-SPY projects (Detector, Flock-You, Foxhunter, Sky-Spy, UniPwn, Wardrive) into a single firmware where engines run **concurrently without rebooting or switching modes**.
- Record raw WiFi & BLE traffic to `.pcap` files on device, manually or auto-triggered by any detection — open in Wireshark.
- Import and export `.CSV` files (wigle.net format) from detections and wardrives. Matches current FlockYou and your own detection OUIs for mapping and review.
- Wigle.net API integration: upload and view your stats right from the app.
- Update firmware from inside the app over WiFi or BLE — no USB cable needed.


> [!NOTE]
> Early beta, bugs and unexpected behavior can be reported in Issues.
---

## What It Detects

| Target | How |
|--------|-----|
| **Flock Safety ALPRs** | BLE MAC prefix, device name, manufacturer ID `0x09C8`, WiFi promiscuous OUI match (addr1/addr2/addr3), wildcard probe signature |
| **Raven Gunshot Detectors** | BLE GATT service UUIDs, firmware version fingerprinting |
| **Drones (FAA Remote ID)** | WiFi promiscuous + BLE — NAN action frames, vendor beacons, ODID advertisements |
| **Unitree Robots** | BLE name prefix matching (Go2_, G1_, H1_, B2_, X1_), connect + exploit |
| **Custom Watchlist Targets** | OUI prefix, full MAC, device name patterns — on both WiFi and BLE |
| **WiFi Infrastructure** | Station-mode AP scan — SSID, BSSID, channel, auth mode, signal |
| **All BLE Devices** | Advertisement capture with name, manufacturer data, service UUIDs |
| **Raw WiFi / BLE traffic** | On-device PCAP capture (radiotap + BLE LL PHDR) — open in Wireshark |

All engines can run concurrently, with some limitations.

---

## Flock Safety Detection

The Flock-WiFi engine runs in 802.11 promiscuous mode, hopping channels 1/6/11 at 350ms dwell. Three detection methods:

- **addr2 OUI match** — transmitter-side match against 42 known Flock Safety OUI prefixes
- **addr1 OUI match** — receiver-side technique that catches Flock STAs appearing only as the destination of probe responses during their burst-sleep windows. Skips multicast/broadcast addresses.
- **Wildcard probe signature** — Probe Request (type=0 subtype=4) with zero-length SSID IE from a known-OUI addr2. High-precision Flock signature with FCS-trailer retry for driver compatibility. From [DeFlockJoplin](https://github.com/DeflockJoplin/flock-you) field research (Joplin drive-test: 11/12 cameras caught, 2 false positives).

The Flock-BLE engine scans for FS Ext Battery devices, Flock WiFi modules, and Raven gunshot detectors via BLE advertisements, manufacturer company ID, device name patterns, and GATT service UUIDs.

Both engines share a sorted OUI table (`flock_oui.h`) with 43 prefixes:
- 10 FS Ext Battery (BLE, Silicon Labs EFR32)
- 26 Flock WiFi cameras — [@NitekryDPaul](https://github.com/nitekry) / OrdoOuroborous original promiscuous-mode set
- 6 @NitekryDPaul April 2026 additions
- 1 [DeFlockJoplin](https://github.com/DeflockJoplin/flock-you) wildcard-probe field discovery

The companion app resolves every Flock OUI to its surveillance label (e.g. "Flock Safety (Falcon)") while also showing the underlying chip manufacturer from the IEEE OUI database when available (e.g. "Flock Safety (Falcon) · Liteon Technology").

---

## Companion App

Flutter app for Android, iOS, and macOS. Connects to OUI-SPY over BLE GATT. All control and display happens in the app.

### Core Features

- **Live detection feed** with engine-colored rows, RSSI, vendor lookup (39k+ OUI database), one-tap foxhunt or map locate. Filter by engine, radio, search any field
- **Wardrive mapping** with 5 target modes (WiGLE, Flock, Drone, Detector, WiGLE+Flock), WiFi/BLE/both radio selection, follow-mode camera that keeps you centered, adaptive map plotting, color-graded route path, WiGLE CSV export, direct WiGLE upload, session history
- **Detector hits on the map** — your watchlist matches appear as live markers on the wardrive map alongside Flock cameras
- **WiGLE CSV import & review** — load any WiGLE-format CSV, auto-match every BSSID against the bundled OUI/Flock database, flag surveillance hits (Flock, Raven, watchlist OUIs) on the map and in the feed
- **PCAP capture (WiFi & BLE)** — record raw 802.11 (radiotap) and BLE LL (PHDR) packets on demand or automatically when a target is detected. Files saved on device, browse + share to Wireshark from `Settings → Detections → Saved PCAPs`. See [PCAP Capture](#pcap-capture)
- **Over-the-air firmware updates** — flash the latest firmware from inside the app over WiFi (fast) or BLE (slow, no router needed). No re-flashing with a cable. See [OTA Updates](#ota-firmware-updates)
- **Per-engine control** — enable/disable any of the 8 engines independently, configure scan timing, radio modes, watchlist entries
- **Watchlist persistence** — saved targets survive reboots; per-target hit counter shown next to each entry
- **Mesh overlay** — see peer node names and per-node detection counts during ESP-NOW coordinated wardrives
- **Ignore list** — suppress devices by MAC, OUI prefix, SSID, or device name with per-scope WiFi/BLE/both toggles
- **Metric/imperial** units throughout (km/mi, km/h/mph, m/ft)

### PCAP Capture

Record raw wireless packets straight to a `.pcap` file on the device, no laptop required.

| Mode | What it records |
|------|------|
| **WiFi 802.11 (radiotap)** | Beacons, probes (req + resp), deauth, disassoc, data, control, management frames across your chosen channels |
| **BLE LL (PHDR)** | Advertisement PDUs, scan requests/responses with proper Bluetooth Low Energy Link Layer headers |

**Manual capture** — pick mode, set channel range (WiFi only), tap START. Live stats: per-type frame counts, current channel, file size.

**Auto-PCAP on detection** — toggle once. Every time a Flock camera, watchlist target, drone, or Unitree robot is detected, the device automatically captures the next *N* seconds (3–120s, configurable) on the matching radio + channel, then resumes normal scanning. The setting persists across reboots. A green `AUTO` badge with countdown shows on the home screen any time it's armed or actively capturing.

**Saved library** — every capture appears in `Settings → Detections` with timestamp, size, and live LIVE badge on the in-progress file. Tap to share to Wireshark, AirDrop, email, or any iOS share target. One-tap delete or delete-all.

**Built-in safety** — auto-PCAP automatically pauses your other scans for the capture window then restores them. Geofence exclusion zones also suppress auto-PCAP — no scanning inside your home/office zones.

### OTA Firmware Updates

Update the device firmware without USB cable or `pio` install.

| Method | Speed | Requires |
|--------|-------|----------|
| **WiFi (STA mode)** | Fast (~30s) | Provide WiFi credentials in app once; device joins your network and pulls the latest release |
| **BLE** | Slow (~5 min) | Nothing — works anywhere, no router needed |

App detects when a newer firmware is available, shows release notes, and applies in one tap. Settings deliberately survive the update.

### Geofence Exclusion Zones

Circle or polygon zones suppress detections near sensitive locations (home, office). Excluded from feed, map, database, and CSV exports. Managed from the fence icon on the wardrive screen. 

### OUI Vendor Lookup

Ships with a 39k+ entry OUI database ([Ringmast4r/OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database)), updatable at runtime. Flock Safety OUIs resolve to surveillance labels while preserving chip manufacturer — e.g. "`Flock Safety (Falcon) · Liteon Technology`".

### Notifications

Per-engine local notifications on iOS, Android, and macOS. Fires on **first-seen MACs only**. Configure in settings.

| Engine | Default | What fires |
|--------|---------|------------|
| Flock Safety | On | New camera detected — method, channel, RSSI |
| Watchlist / Detector | On | Watchlist MAC hit with device name |
| Sky Spy / Drone | On | FAA Remote ID drone with UAV ID |
| Foxhunter | Off | Signal crosses -65dBm (warm) or -50dBm (close) |
| Wardrive | Milestones | Every 1000 unique networks |

### iOS Dynamic Island & Live Activity

On iPhone 14 Pro+ (iOS 16.2+), active sessions show in the Dynamic Island and Lock Screen with engine-specific icons and live stats. All 7 engines supported — wardrive gets priority when multiple are active, but combined counts from all engines always visible in the expanded view.



### Install

| Platform | Method |
|----------|--------|
| **Android** | [APK from latest release](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest) — enable "Install unknown apps" if needed|
| **TestFlight: iOS & macOS Silicon** | [Join TestFlight beta](https://testflight.apple.com/join/5RCKgnJ2) |
| **macOS** | [Signed .app from latest release](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest) |

---

## Flash It

### Web Flasher (easiest)

Open the [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) in Chrome or Edge (89+). Plug in XIAO ESP32-S3 via USB-C. Click Connect & Flash. Requires Web Serial API (Chromium browsers only).

### Python Flasher

```bash
pip install -r requirements.txt
python3 flash.py              # single board, interactive
python3 flash.py --batch      # hands-free batch mode for production
python3 flash.py --erase      # full erase before write
```

### Flash Layout

| File | Offset | Purpose |
|------|--------|---------|
| `bootloader.bin` | `0x0000` | ESP32-S3 bootloader |
| `partitions.bin` | `0x8000` | Partition table |
| `boot_app0.bin` | `0xe000` | OTA data |
| `firmware.bin` | `0x10000` | Application firmware (v3 app-controlled) |

---

## Hardware

**Board:** Seeed Studio XIAO ESP32-S3 — USB-C, 8MB flash, BLE 5 + WiFi, dual-core 240MHz

| Pin | Function |
|-----|----------|
| GPIO 3 | Piezo buzzer (PWM, volume-controllable from app) |
| GPIO 4 | NeoPixel WS2812B (brightness-controllable from app) |
| GPIO 21 | Onboard LED (active LOW) |
| GPIO 43/44 | Optional hardware GPS TX/RX (if no phone GPS relay) |

---

## Building from Source

### Firmware

Requires [PlatformIO](https://platformio.org/).

```bash
pio run -e v3_app_controlled           # build
pio run -e v3_app_controlled -t upload  # flash directly
pio device monitor                      # serial output (115200)
```

**Dependency:** `NimBLE-Arduino` for BLE GATT server + scanning.

### Companion App

Requires [Flutter](https://flutter.dev/docs/get-started/install) 3.32+.

```bash
cd companion
flutter pub get
flutter run                             # debug on connected device
flutter build apk --release             # Android APK
flutter build ipa --release             # iOS archive
flutter build macos --release           # macOS .app
```

**iOS Live Activity (optional):** The `OuiSpyLiveActivity` Widget Extension target provides Dynamic Island support. In Xcode: File > New > Target > Widget Extension, name it `OuiSpyLiveActivity`, then add `OuiSpyLiveActivityAttributes.swift` to both Runner and extension target membership.

---

## Dependencies & Third-Party Services

### Firmware (PlatformIO)

| Library | Author | Purpose |
|---------|--------|---------|
| [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) | h2zero | BLE GATT server, scanning, ESP-NOW coexistence |
| [ESP Async WebServer](https://github.com/mathieucarbou/ESPAsyncWebServer) | mathieucarbou | OTA update server (local network only) |
| [Adafruit NeoPixel](https://github.com/adafruit/Adafruit_NeoPixel) | Adafruit | WS2812B LED control |
| [ArduinoJson](https://github.com/bblanchon/ArduinoJson) | bblanchon | JSON serialization for config/mesh payloads |
| [TinyGPS++](https://github.com/mikalhart/TinyGPSPlus) | mikalhart | Hardware GPS NMEA parsing (optional module) |

Built on **ESP-IDF** (via Arduino core for ESP32-S3) — WiFi promiscuous mode, ESP-NOW, mbedTLS (AES-GCM mesh encryption).

### Companion App (Flutter)

| Package | Purpose |
|---------|---------|
| [flutter_blue_plus](https://pub.dev/packages/flutter_blue_plus) | BLE GATT communication with hardware |
| [flutter_map](https://pub.dev/packages/flutter_map) + [latlong2](https://pub.dev/packages/latlong2) | Map rendering and geolocation math |
| [drift](https://pub.dev/packages/drift) + [sqlite3_flutter_libs](https://pub.dev/packages/sqlite3_flutter_libs) | Local SQLite database for sessions and detections |
| [geolocator](https://pub.dev/packages/geolocator) | Phone GPS with background location |
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod) | Reactive state management |
| [go_router](https://pub.dev/packages/go_router) | Declarative navigation |
| [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) | Local push notifications (iOS, Android, macOS) |
| [dio](https://pub.dev/packages/dio) | HTTP client (WiGLE API uploads) |
| [share_plus](https://pub.dev/packages/share_plus) | Native share sheet for CSV export |
| [freezed](https://pub.dev/packages/freezed) + [json_serializable](https://pub.dev/packages/json_serializable) | Immutable data models with codegen |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | Keychain/Keystore for mesh encryption keys |
| [wakelock_plus](https://pub.dev/packages/wakelock_plus) | Prevent sleep during wardrive sessions |
| [permission_handler](https://pub.dev/packages/permission_handler) | Runtime permission requests |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Persisted user settings |
| [intl](https://pub.dev/packages/intl) | Date/number formatting |
| [uuid](https://pub.dev/packages/uuid) | Session ID generation |
| [crypto](https://pub.dev/packages/crypto) | Hashing utilities |

### APIs & Tile Services

| Service | Usage |
|---------|-------|
| [WiGLE](https://api.wigle.net) | Wardrive CSV upload (user provides own API key) |
| [CARTO](https://carto.com/basemaps/) | Dark, Light, and Voyager map tiles |
| [OpenStreetMap](https://www.openstreetmap.org/) | OSM raster tiles |
| [OpenTopoMap](https://opentopomap.org/) | Topographic map tiles |
| [Stadia Maps](https://stadiamaps.com/) | Stamen Toner and Terrain tiles |

### Data Sources

| Source | What |
|--------|------|
| [Ringmast4r/OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database) | 39k+ IEEE OUI vendor database (bundled as gzipped TSV) |

### iOS Native Frameworks

| Framework | Usage |
|-----------|-------|
| ActivityKit | Live Activities / Dynamic Island (iOS 16.2+) |
| WidgetKit | Widget Extension for Live Activity rendering |
| CoreBluetooth | BLE (via flutter_blue_plus) |
| CoreLocation | GPS (via geolocator) |

---

## The Ecosystem

This repo contains the unified firmware (all engines) and the companion app. Each engine also exists as a standalone project:

| Project | What |
|---------|------|
| **[OUI-SPY Detector](https://github.com/colonelpanichacks/ouispy-detector)** | Standalone BLE/WiFi watchlist scanner |
| **[OUI-SPY Foxhunter](https://github.com/colonelpanichacks/ouispy-foxhunter)** | Standalone RSSI proximity tracker |
| **[Flock You](https://github.com/colonelpanichacks/flock-you)** | Standalone Flock Safety / Raven detection |
| **[Sky-Spy](https://github.com/colonelpanichacks/Sky-Spy)** | Standalone drone Remote ID capture |
| **[Remote-ID-Spoofer](https://github.com/colonelpanichacks/Remote-ID-Spoofer)** | WiFi Remote ID spoofer + swarm mode |
| **[OUI-SPY UniPwn](https://github.com/colonelpanichacks/Oui-Spy-UniPwn)** | Standalone Unitree robot exploitation |

---

## Acknowledgments

**Will Greenberg** ([@wgreenberg](https://github.com/wgreenberg)) — [flock-you](https://github.com/wgreenberg/flock-you) research. Manufacturer company ID `0x09C8` (XUNTONG) detection method and structured pattern approach sourced from his work.

**@NitekryDPaul / OrdoOuroborous** ([@nitekry](https://github.com/nitekry)) — 42 Flock Safety OUI prefixes from promiscuous-mode WiFi field testing, addr1 receiver-side detection technique.

**Michael / DeFlockJoplin** ([DeflockJoplin](https://github.com/DeflockJoplin/flock-you)) — Wildcard probe signature (Probe Request + zero-length SSID + known OUI) from Joplin drive-test field research.

---

## Author of OUISPY ecosystem

**colonelpanichacks**

---

## Disclaimer

Security research and privacy auditing tool. Detecting surveillance hardware in public spaces is legal in most jurisdictions. Comply with local laws regarding wireless scanning and signal interception. Authors not responsible for misuse. Using GATT during pairing process can be a risk. Users agree to use in lawful manner only.

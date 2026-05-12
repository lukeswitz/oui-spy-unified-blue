<div align="center">
<h1>OUI SPY Unified & Companion</h1>

[![Version](https://img.shields.io/github/v/release/lukeswitz/oui-spy-unified-blue?include_prereleases&label=pre-release&color=green)](https://github.com/lukeswitz/oui-spy-unified-blue/releases) [![Join TestFlight Beta](https://img.shields.io/badge/TestFlight-Join-blue.svg?style=f&logo=apple)](https://testflight.apple.com/join/5RCKgnJ2) ![Platforms](https://img.shields.io/badge/platforms-iOS%20%7C%20macOS%20%7C%20Android-1BA1E2)
![Dart](https://img.shields.io/badge/Dart-Flutter%20App-0175C2)
![C++](https://img.shields.io/badge/C%2B%2B-ESP32%20FW-ff6600)

<img width="500" alt="ouispy_appicon" src="https://github.com/user-attachments/assets/5a201c27-558b-4409-9e49-82d6e0176a4c" />

[Features](#what-it-detects) | [Get the App](#install) | [Flash Firmware](#flash-it)

</div>

---
**About this fork:**

Unified multi-engine surveillance detection firmware for the XIAO ESP32-S3. Runs seven scan engines simultaneously using both WiFi and BLE radios. Controlled entirely from a companion app over BLE GATT.

Combines all standalone OUI-SPY projects (Detector, Flock-You, Foxhunter, Sky-Spy, UniPwn, Wardrive) into a single firmware where engines run concurrently without rebooting or switching modes.

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

All engines can run concurrently, with some limitations.

---

## Flock Safety Detection

The Flock-WiFi engine runs in 802.11 promiscuous mode, hopping channels 1/6/11 at 350ms dwell. Three detection methods:

- **addr2 OUI match** — transmitter-side match against 43 known Flock Safety OUI prefixes
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

## Radio Architecture

ESP32-S3 has one WiFi radio and one BLE radio. Multiple engines need both. Here's how they share:

### WiFi Radio

Five engines use WiFi. Only one can **own** the radio:

| Engine | WiFi Mode | Channels | Dwell |
|--------|-----------|----------|-------|
| **Wardrive** | Station-mode AP scan | All | Per scan cycle |
| **Flock-WiFi** | Promiscuous | 1, 6, 11 | 350ms |
| **Sky Spy** | Promiscuous | 6 (ODID NAN + Beacon) | Fixed |
| **Detector** | Promiscuous | 1-14 | 120ms |
| **Foxhunter** | Promiscuous | 1-14 (priority dwell on hint + 1/6/11) | 120ms normal, 350ms priority |

**Automatic handoff:** The engine registry auto-stops conflicting WiFi engines when you enable another. Wardrive, Sky Spy, and Flock-WiFi are registered as WiFi-exclusive in the registry. Foxhunter additionally pauses Detector, Flock-WiFi, and Sky Spy on start since it needs exclusive promiscuous access to hunt a target across all channels.

### BLE Radio (shared)

BLE is shared across all engines concurrently. NimBLE handles interleaved scanning and GATT server duties.

- **Flock-BLE** — OUI prefix, device name, manufacturer ID `0x09C8`, Raven service UUIDs
- **Foxhunter** — BLE scan for target MAC (when not fed by wardrive)
- **Detector** — BLE scan for watchlist matches
- **Sky Spy** — ODID BLE advertisements
- **Wardrive** — BLE advertisement capture for wardriving database
- **UniPwn** — BLE discovery + GATT connection for Unitree robot exploitation

### Deduplication & Scan Caching

All engines share a templated `DedupRing` (with an ISR-safe variant for promiscuous callbacks) that suppresses duplicate MAC reports within a configurable cooldown window. Ring-buffer design — fixed memory, no heap allocation, O(n) scan with small n. Engines reuse NimBLE scan instances and WiFi scan results across cycles instead of re-initializing each pass.

### Passive Feeding (wardrive active)

When wardrive owns WiFi, Detector and Foxhunter don't start their own scans. Instead wardrive feeds them via callbacks:

- Wardrive WiFi scan results dispatch to `foxhunterCheckWifiDevice()` and detector's watchlist matcher
- Wardrive BLE advertisements dispatch to Foxhunter, Detector, and Flock-BLE
- Foxhunter auto-learns hint channel from first WiFi match for priority dwell when it next runs standalone

---

## ESP-NOW Mesh & Node Orchestration

> Not stable, coming in v0.0.4

Multiple OUI-SPY nodes form an encrypted mesh using ESP-NOW. Detections from any node relay to all peers and appear on every connected phone.

- **Up to 6 peers** per node
- **AES-GCM encryption** (mbedtls) — 32-byte key, 12-byte nonce derived from node ID + counter
- **5-character node IDs** — every detection carries source attribution so you know which node saw it
- **Bidirectional** — detections flow both ways, tx/rx counters tracked
- **No infrastructure required** — ESP-NOW peer-to-peer, no router or internet needed

---

## Companion App

Native Flutter app for Android, iOS, and macOS. Connects to OUI-SPY hardware over BLE GATT. No web dashboard or WiFi AP — all control and data display happens in the app.

### Screens

**Home** — Connection status with pulsing radar animation. Navigates home automatically when a device connects. Engine cards show live state (disabled/scanning/alerting). Tap any card to view settings or enable/disable directly. Status bar shows connected node, GPS quality, active engine count, and active node count.

**Feed** — Real-time scrolling detection stream. Each row shows engine color, MAC address, RSSI, detection method, timestamp. Top stats bar shows top vendors and top Flock devices by count. Filter bar to show/hide specific engines. Long-press (or right-click on desktop) any row for actions: copy MAC/location/vendor to clipboard, show on map, foxhunt target. Tap crosshairs to foxhunt, and the far right icon to display on map.

**Wardrive** — Dedicated wardriving screen with map, start/stop control, and live stats overlay: unique WiFi APs, unique BLE devices, Flock detections, distance traveled, speed, detections per km (or per mile — unit preference). GPS accuracy indicator with color coding. Node stats overlay shows each mesh peer's name and live detection count during coordinated wardrives. Long-press any device row to copy MAC, location, vendor, or SSID. Session auto-saves to SQLite. WiGLE CSV export. Session history with devices count, upload/share.

**Config** — Seven tabs: App (theme, units), Ignore List (suppress devices by MAC/OUI/SSID with per-scope WiFi/BLE/both toggles — excluded from feed, exports, database, and alerts), Detections (sortable list with engine filter chips, vendor lookup with OUI DB update), Hardware (buzzer on/off, volume slider, LED, neopixel brightness), Alerts (cooldown, heartbeat, rediscover intervals), Device Info (firmware version, node ID, free heap), Wardrive (radio selection, scan timing).

### OUI Vendor Lookup

The app ships with a 39k+ OUI vendor database (gzipped TSV from [Ringmast4r/OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database)), updatable at runtime. Flock Safety devices use OEM chip vendor OUIs (Silicon Labs, Liteon, UGS) — the app overrides these with correct labels while preserving the underlying chip manufacturer: e.g. "Flock Safety (Falcon) · Liteon Technology".

### Engine-Specific Screens

- **Detector** — manage OUI/MAC watchlist, see matches with filter descriptions
- **Foxhunter** — set target MAC, live RSSI display
- **Sky Spy** — drone telemetry table (UAV ID, operator ID, lat/lon, altitude, speed, heading, pilot location)
- **UniPwn** — discovered Unitree robots list, select target, trigger exploit sequence

### Install

| Platform | Method |
|----------|--------|
| **Android** | [APK from latest release](https://github.com/colonelpanichacks/oui-spy-unified-blue/releases/latest) — enable "Install unknown apps" |
| **iOS** | [Join TestFlight beta](https://testflight.apple.com/join/5RCKgnJ2) |
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

**Key dependencies:** `flutter_blue_plus` (BLE), `flutter_map` + `latlong2` (maps), `drift` (SQLite), `geolocator` (GPS), `riverpod` (state), `go_router` (navigation), `freezed` (models), `share_plus` (export).

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

## Author

**colonelpanichacks**

---

## Disclaimer

Security research and privacy auditing tool. Detecting surveillance hardware in public spaces is legal in most jurisdictions. Comply with local laws regarding wireless scanning and signal interception. Authors not responsible for misuse. Using GATT during pairing process can be a risk. Users agree to use in lawful manner only.

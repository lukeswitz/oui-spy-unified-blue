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
| **Flock Safety ALPRs** | BLE MAC prefix, device name, manufacturer ID `0x09C8`, WiFi probe/SSID patterns |
| **Raven Gunshot Detectors** | BLE GATT service UUIDs, firmware version fingerprinting |
| **Drones (FAA Remote ID)** | WiFi promiscuous + BLE — NAN action frames, vendor beacons, ODID advertisements |
| **Unitree Robots** | BLE name prefix matching (Go2_, G1_, H1_, B2_, X1_), connect + exploit |
| **Custom Watchlist Targets** | OUI prefix, full MAC, device name patterns — on both WiFi and BLE |
| **WiFi Infrastructure** | Station-mode AP scan — SSID, BSSID, channel, auth mode, signal |
| **All BLE Devices** | Advertisement capture with name, manufacturer data, service UUIDs |

All engines can run concurrently, with some limitations.

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

### Passive Feeding (wardrive active)

When wardrive owns WiFi, Detector and Foxhunter don't start their own scans. Instead wardrive feeds them via callbacks:

- Wardrive WiFi scan results dispatch to `foxhunterCheckWifiDevice()` and detector's watchlist matcher
- Wardrive BLE advertisements dispatch to Foxhunter, Detector, and Flock-BLE
- Foxhunter auto-learns hint channel from first WiFi match for priority dwell when it next runs standalone

---

## How It Works

The firmware runs an **engine registry** on FreeRTOS. Each engine registers init/start/stop/loop/config callbacks. The companion app sends enable/disable commands over BLE GATT using bitmasks. Detections flow through a shared queue (depth 64) and get pushed to the app as packed binary notifications.

---

## ESP-NOW Mesh & Node Orchestration

> Not stable, coming in v0.0.4

Multiple OUI-SPY nodes form an encrypted mesh using ESP-NOW. Detections from any node relay to all peers and appear on every connected phone.

- **Up to 6 peers** per node
- **AES-GCM encryption** (mbedtls) — 32-byte key, 12-byte nonce derived from node ID + counter
- **5-character node IDs** — every detection carries source attribution so you know which node saw it
- **Bidirectional** — detections flow both ways, tx/rx counters tracked
- **No infrastructure required** — ESP-NOW peer-to-peer, no router or internet needed

### Node Orchestration

The companion app acts as a central coordinator for all mesh nodes. When you enable an engine on the primary node, the orchestrator automatically syncs the command to all peers via ESP-NOW relay.

- **Engine sync** — enable/disable any engine and all connected nodes follow
- **Channel splitting** — wardrive mode automatically divides WiFi channels across nodes (e.g., node A scans 1-7, node B scans 8-14) for maximum coverage with zero overlap
- **Health monitoring** — 5-second heartbeat from each peer reports active engines, detection count, uptime, and free heap. Peers marked stale after 15s of silence
- **Command relay** — phone sends orchestration commands via BLE to primary node, which broadcasts to all peers over ESP-NOW. Three mesh packet types: detection (existing), command (new), and status (new)

```
 Phone ──BLE──► Primary Node ──ESP-NOW──►  Peer 1
                     │                     Peer 2
                     │                     Peer 3
                     ▼
              Local execution
              (same command)
```

---

## Companion App

Native Flutter app for Android, iOS, and macOS. Connects to OUI-SPY hardware over BLE GATT. No web dashboard or WiFi AP on the device — all control and data display happens in the app.

### Screens

**Home** — Connection status with pulsing radar animation. Once connected: engine cards showing live state (disabled/scanning/alerting). Tap any card to enable/disable — mesh peers auto-sync. Status bar shows connected node, GPS quality, active engine count, and active node count. Each engine card shows a "+N nodes" badge when mesh peers are running that engine.

**Map** — Full-screen map with CartoDB tiles (dark theme or light theme depending on your preference). Engine-colored markers for geotagged detections. Route trace polyline. Auto-follow mode centers on your position. Deduplicated by MAC+engine.

**Feed** — Real-time scrolling detection stream. Each row shows engine color, MAC address, RSSI, detection method, timestamp. Filter bar to show/hide specific engines. Detections arrive as binary GATT notifications and decode in real time.

**Wardrive** — Dedicated wardriving screen with map, start/stop control, and live stats overlay: unique WiFi APs, unique BLE devices, Flock detections, distance traveled, speed, detections per km (or per mile — unit preference). GPS accuracy indicator with color coding. Node stats overlay shows each mesh peer's name and live detection count during coordinated wardrives. Session auto-saves to SQLite. WiGLE CSV export with share sheet on stop. Session history with delete support.

**Config** — Five tabs: Hardware (buzzer on/off, volume slider, LED, neopixel brightness), Alerts (cooldown, heartbeat, rediscover intervals), Device Info (firmware version, node ID, free heap), Wardrive (radio selection, scan timing), Debug Log (raw BLE traffic viewer).

### Features

- **Dark and light theme** — toggle in settings, persisted across sessions
- **Metric and imperial units** — km/mi, km/h/mph, m/ft throughout the app
- **GPS relay** — phone GPS streams to firmware over BLE for detection geotagging
- **WiGLE CSV export** — auto-generates on session stop, compatible with WiGLE upload
- **Session history** — browse, replay, delete, and re-export past wardrive sessions from SQLite
- **Chunked BLE transfer** — large payloads (watchlists, mesh configs) split across multiple writes
- **Onboarding** — BLE scan screen finds nearby OUI-SPY devices, one-tap connect
- **Node management** — view mesh peers, connection state, rx/tx stats
- **Node orchestration** — automatic engine sync to mesh peers, channel splitting for wardrive, per-peer health monitoring with stale detection

### Engine-Specific Screens

- **Detector** — manage OUI/MAC watchlist, see matches with filter descriptions
- **Foxhunter** — set target MAC, live RSSI display, beep interval indicator
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

## BLE Protocol

Single GATT service (`00000001-0a15-4b70-ba00-c010ae1ba01c`). Binary packed structs. No JSON.

| Characteristic | UUID Suffix | Direction | Purpose |
|----------------|-------------|-----------|---------|
| Device Info | `0001` | Read | Firmware version, node ID, capabilities |
| Engine Control | `0002` | Write | Enable/disable/config by engine ID |
| Detection Events | `0010` | Notify | Packed `DetectionEvent` structs (variable size by engine) |
| Device Status | `0011` | Read/Notify | Active engine bitmask, per-engine states |
| GPS Receive | `0012` | Write | Phone GPS → firmware (lat, lon, alt, speed, heading, accuracy, sats) |
| Hardware Config | `0020` | Read/Write | Buzzer, LED, neopixel settings |
| Alert Config | `0021` | Read/Write | Cooldown, heartbeat, rediscover intervals |
| Foxhunter Config | `0130` | Write | Target MAC |
| Foxhunter RSSI | `0131` | Notify | Live RSSI + beep interval |
| Sky Spy Telemetry | `0140` | Notify | Full ODID drone data |
| UniPwn Devices | `0150` | Notify | Discovered robot list |
| UniPwn Command | `0151` | Write | Target selection, exploit trigger |
| Mesh Config | `0060` | Read/Write | Enable, encryption, key, peer MACs |
| Mesh Status | `0061` | Read/Notify | Peer count, connected count, rx/tx/errors |
| Orchestration | `0070` | Write/Notify | Relay engine commands to mesh peers; receive peer status heartbeats |

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

---

## Author

**colonelpanichacks**

---

## Disclaimer

Security research and privacy auditing tool. Detecting surveillance hardware in public spaces is legal in most jurisdictions. Comply with local laws regarding wireless scanning and signal interception. Authors not responsible for misuse.

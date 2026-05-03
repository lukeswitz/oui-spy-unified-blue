# OUI SPY Unified & Companion

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

All engines can run concurrently.

---

## Dual Radio

Each engine runs on both WiFi and BLE. The user selects radio mode (WiFi, BLE, or both) per engine from the companion app:

- **Detector** — WiFi promiscuous (all 14 channels, 120ms dwell, matches watchlist against frame addresses) + BLE scan
- **Foxhunter** — WiFi promiscuous (all 14 channels, 100ms dwell, hunts target MAC across addr1/2/3) + BLE scan
- **Flock-WiFi** — WiFi promiscuous (channels 1/6/11, 350ms dwell — Flock cameras use standard AP channels)
- **Flock-BLE** — BLE scan (OUI, name, manufacturer ID, Raven service UUIDs)
- **Sky Spy** — WiFi promiscuous (channel 6, ODID NAN + Beacon frames) + BLE scan (ODID advertisements)
- **Wardrive** — WiFi station-mode AP scan + BLE advertisement capture
- **UniPwn** — BLE only (discovery + GATT connection for exploitation)

**WiFi mutual exclusion:** Only one engine owns the WiFi radio at a time (hardware limit). The engine registry auto-stops conflicting WiFi engines when you enable another. Three engines are registered as WiFi-exclusive: Wardrive, Sky Spy, Flock-WiFi.

**Passive mode:** When wardrive is active, Detector and Foxhunter skip their own scans and receive results via callbacks from wardrive's scan loop instead. Wardrive does inline Flock OUI matching on WiFi results and dispatches BLE advertisements to Detector, Foxhunter, and Flock-BLE.

---

## How It Works

The firmware runs an **engine registry** on FreeRTOS. Each engine registers init/start/stop/loop/config callbacks. The companion app sends enable/disable commands over BLE GATT using bitmasks. Detections flow through a shared queue (depth 64) and get pushed to the app as packed binary notifications.

```
 Your Phone/Laptop                           OUISPY (ESP32S3)
┌──────────────────┐                 ┌──────────────────────────────-┐
│  Companion App   │                 │  Engine Registry (7 engines)  │
│                  │◄── BLE GATT ──► │                               │
│  Enable engines  │                 │  WiFi radio (exclusive):      │
│  Stream GPS      │  DetectionEvent │    → Wardrive                 │
│  Receive dets    │◄───────────────┤│    → Sky Spy                  │
│  Wardrive map    │                 │    → Flock-WiFi               │
│  Export WiGLE    │                 │    → Detector*                │
│  Mesh management │                 │    → Foxhunter*               │
│                  │                 │       *when wardrive inactive │
└──────────────────┘                 │                               │
                                     │  BLE radio (shared):          │
                                     │    → All engines concurrent   │
                                     │                               │
                                     │  ESP-NOW Mesh (encrypted)     │
                                     └──────────────────────────────-┘
```

---

## ESP-NOW Mesh

Multiple OUI-SPY nodes form an encrypted mesh using ESP-NOW. Detections from any node relay to all peers and appear on every connected phone.

- **Up to 6 peers** per node
- **AES-GCM encryption** (mbedtls) — 32-byte key, 12-byte nonce derived from node ID + counter
- **5-character node IDs** — every detection carries source attribution so you know which node saw it
- **Bidirectional** — detections flow both ways, tx/rx counters tracked
- **No infrastructure required** — ESP-NOW peer-to-peer, no router or internet needed

---

## Companion App

Native Flutter app for Android, iOS, and macOS. Connects to OUI-SPY hardware over BLE GATT. No web dashboard or WiFi AP on the device — all control and data display happens in the app.

### Screens

**Home** — Connection status with pulsing radar animation. Once connected: engine cards showing live state (disabled/scanning/alerting). Tap any card to enable/disable. Status bar shows connected node, firmware version, GPS quality, active engine count.

**Map** — Full-screen map with CartoDB tiles (dark theme or light theme depending on your preference). Engine-colored markers for geotagged detections. Route trace polyline. Auto-follow mode centers on your position. Deduplicated by MAC+engine.

**Feed** — Real-time scrolling detection stream. Each row shows engine color, MAC address, RSSI, detection method, timestamp. Filter bar to show/hide specific engines. Detections arrive as binary GATT notifications and decode in real time.

**Wardrive** — Dedicated wardriving screen with map, start/stop control, and live stats overlay: unique WiFi APs, unique BLE devices, Flock detections, distance traveled, speed, detections per km (or per mile — unit preference). GPS accuracy indicator with color coding. Session auto-saves to SQLite. WiGLE CSV export with share sheet on stop.

**Config** — Five tabs: Hardware (buzzer on/off, volume slider, LED, neopixel brightness), Alerts (cooldown, heartbeat, rediscover intervals), Device Info (firmware version, node ID, free heap), Wardrive (radio selection, scan timing), Debug Log (raw BLE traffic viewer).

### Features

- **Dark and light theme** — toggle in settings, persisted across sessions
- **Metric and imperial units** — km/mi, km/h/mph, m/ft throughout the app
- **GPS relay** — phone GPS streams to firmware over BLE for detection geotagging
- **WiGLE CSV export** — auto-generates on session stop, compatible with WiGLE upload
- **Session history** — browse, replay, and re-export past wardrive sessions from SQLite
- **Chunked BLE transfer** — large payloads (watchlists, mesh configs) split across multiple writes
- **Onboarding** — BLE scan screen finds nearby OUI-SPY devices, one-tap connect
- **Node management** — view mesh peers, connection state, rx/tx stats

### Engine-Specific Screens

- **Detector** — manage OUI/MAC watchlist, see matches with filter descriptions
- **Foxhunter** — set target MAC, live RSSI display, beep interval indicator
- **Sky Spy** — drone telemetry table (UAV ID, operator ID, lat/lon, altitude, speed, heading, pilot location)
- **UniPwn** — discovered Unitree robots list, select target, trigger exploit sequence

### Install

| Platform | Method |
|----------|--------|
| **Android** | [APK from latest release](https://github.com/colonelpanichacks/oui-spy-unified-blue/releases/latest) — enable "Install unknown apps" |
| **iOS** | TestFlight beta |
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

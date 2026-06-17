
<div align="center">

[![Release](https://img.shields.io/github/v/release/lukeswitz/oui-spy-unified-blue?include_prereleases&label=pre-release&color=green)](https://github.com/lukeswitz/oui-spy-unified-blue/releases)
[![TestFlight](https://img.shields.io/badge/TestFlight-Join-blue.svg?logo=apple)](https://testflight.apple.com/join/5RCKgnJ2)
![Platforms](https://img.shields.io/badge/iOS%20%7C%20macOS%20%7C%20Android-1BA1E2)
![Firmware](https://img.shields.io/badge/firmware-ESP32--S3-ff6600)
[![CodeQL](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql)

# OUI-APEX


<img width="320" alt="OUI-SPY APEX" src="https://github.com/user-attachments/assets/5a201c27-558b-4409-9e49-82d6e0176a4c" />

**A distributed detection / wardriver that hunts surveillance gear.** Seven detectors, one ESP32, one phone app. Nodes reach ~200m with ESP-NOW integration. 



[**Quick Start**](#quick-start) · [**The Eight Engines**](#the-eight-engines) · [**The App**](#the-app) · [**Detection Internals**](#detection-internals) · [**Flash & Hardware**](#flash--hardware)

</div>



> [!NOTE]
> Runs the [OUI-SPY ecosystem](https://github.com/colonelpanichacks) by colonelpanichacks. Not affiliated with OUI-SPY. Beta software — expect bugs.

---

## What it is

OUI-SPY APEX is a fork of the OUI-SPY unified firmware, rebuilt around two ideas: **run every detector simultaneously**, and **control it all from your phone instead of a captive portal**.

---

## Quick Start

1. **Flash the board** — open the [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) in Chrome or Edge, plug in via USB-C, hit **Connect & Flash**. One time only.
2. **Install the app** — [Android APK](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest) · [iOS / macOS TestFlight](https://testflight.apple.com/join/5RCKgnJ2) · [macOS signed build](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest).
3. **Connect** — open the app, tap **CONNECT**, pick your board from the **SCAN FOR OUI-SPY** list.

> [!IMPORTANT]
> Some versions of Android will not prompt for location permissions. Location > Allow Always is required for the app to scan in background when app is not on screen/device locked.

- APEX doesn't auto-connect unless you opt in (*Settings → App → Connection*). On launch it drops stale links and waits for you to choose a device. 

---

## The Eight Engines

Each engine answers one question: *is a specific kind of radio nearby?* Toggle any combination from the home screen — they all run together and take turns on the radio.

| Engine | Radio | What it finds | Plain-English purpose |
|---|---|---|---|
| **Detector** | WiFi + BLE | Anything on your watchlist | Your own targets — a MAC, a vendor prefix, a device name, or a BLE service UUID |
| **Flock BLE** | BLE | Flock cameras, Raven gunshot sensors | Spot Flock surveillance gear by its Bluetooth fingerprint |
| **Flock WiFi** | WiFi | Flock Safety cameras | Spot the same cameras by their WiFi traffic |
| **Foxhunter** | WiFi + BLE | One chosen target, by signal strength | Walk toward a device — the buzzer speeds up as you close in |
| **Sky Spy** | WiFi + BLE | FAA Remote ID drones | See drones broadcasting Remote ID and where their operator is |
| **UniPwn** | BLE | Unitree robots | Detect, connect to, and exploit Unitree robots |
| **Wardrive** | WiFi + BLE | Every AP and BLE device | Classic WiGLE-style logging — SSID, BSSID, channel, auth, GPS |
| **PCAP** | WiFi *or* BLE | Raw frames | Capture 802.11 or BLE link-layer packets straight to your phone |

Detailed mechanics for each are in [Detection Internals](#detection-internals).

---

## The App

Flutter app for iOS, macOS, and Android, talking to the board over BLE.


<img width="610" alt="APEX overview" src="https://github.com/user-attachments/assets/0a798936-51f3-41d2-b103-cdec0e7d9134" />


### Home
One card per engine. Tap a card to toggle the engine or open its settings. The status bar shows connection state, GPS fix, and node count.

### Live Feed
Every detection from every engine, in one stream.
- **Filter** by engine, by preset (e.g. surveillance-only), or by which node found it.
- **Sort** by time, RSSI, or MAC; free-text search across the list.
- **Export** the current filtered view to WiGLE CSV.
- **Tap** a row to foxhunt or map that device; **long-press** for the full detail sheet (MAC, vendor, RSSI, channel, manufacturer data).

### Wardrive Map
The headline feature.


<img width="709" alt="App home" src="https://github.com/user-attachments/assets/62470061-c382-4724-8d86-72cb4dd4c1df" />
Pick any mix of targets — **WiGLE, Flock, Drone, Detector** — plus a radio (**WiFi, BLE, or Both**), then hit **START**. The chosen engines run together and plot hits live, color-graded by signal density, with your route trailing behind you.

- **Drones** plot at their broadcast Remote ID position. When a drone reports no fix (0/0), it draws an RSSI range ring around you instead. Drone and pilot trails are tracked separately.
- **Stacked pins** (overlapping Flock / drone / detector hits) fan out on leader lines so each stays readable.
- The top bar tallies hits per engine in real time.
- **Geofences** — draw an excluded zone and everything inside it goes silent: no feed entry, no logging, no CSV, no beep, and the radios pause entirely. Scanning resumes the moment you leave the zone.
- Sessions save as WiGLE CSV and upload directly to WiGLE with your API key. Saved sessions replay on the map.

<img width="910" alt="Wardrive map" src="https://github.com/user-attachments/assets/cc0d4cc9-6524-41c7-bb04-9cd01dae58b8" />

### PCAP
Packet capture with no SD card — frames stream over BLE and the app writes a `.pcap` you open in Wireshark.

<img width="910" alt="PCAP" src="https://github.com/user-attachments/assets/4b34e73d-1341-4222-8ec2-d17a179f6faa" />

- **WiFi 802.11 (radiotap)** — beacons, probes, deauth, data, control, and management frames across a channel range.
- **BLE LL** — adverts and scan request/response with synthesized link-layer headers.
- **Auto-PCAP** — when a detection engine fires, the board automatically captures for 3–120 s (with a cooldown and a per-MAC rediscover window), then goes back to scanning. Each capture is auto-labeled with the engine and MAC that triggered it.

### Over-the-Air Updates
*Settings → Updates → Check for Update.* Update over **WiFi** (fast — give credentials once) or **BLE** (works anywhere, slower). No cables after the first flash. In node mode, each live node updates the same way, one at a time.

### Settings
Everything else: appearance, units, scan timing, channel range, the 39k+ OUI vendor database (with WiGLE CSV import), WiGLE login, buzzer/LED, firmware timing, station-mode WiFi, factory reset, watchlist, ignore list, and database import/export for backing up and restoring captures.

<img width="1133" alt="Settings" src="https://github.com/user-attachments/assets/b8072937-67fb-4ae3-adc0-d1c748a26983" />

### iOS Dynamic Island
On iPhone 14 Pro and newer (iOS 16.2+), live detection counts show on the Lock Screen and Dynamic Island during a session.

---

## Node Mode (run a swarm)

Flash one board as a **manager** (`mgr-xiao_c3` or `mgr-wroom`) and the rest as **nodes** (`node-xiao_s3`). Power them on — nodes auto-join in ~10 s with no pairing. Connect the app to the manager.

- Detection engines run across **all** nodes at once; every hit is tagged with the node that found it.
- The manager splits the WiFi channel range across nodes, so more boards cover the band faster and cover more ground.
- On a WiGLE wardrive **START**, a popup lets you set each node to **WiFi / BLE / Both**.
- **PCAP** captures from a single node you select.

Manager settings (buzzer, LED, alert timing, ignore list, wardrive radio) push to every node and **override** their local copies — one place drives the whole swarm. Turning an engine off or closing the app stops the nodes; nothing scans unattended.

---

## Detection Internals

802.11 frames carry three MAC fields: **addr1** (receiver), **addr2** (transmitter), **addr3** (BSSID). Several engines check all three so a target is caught regardless of which role it plays in a frame.

### Flock — cameras + Raven gunshot detectors
Both Flock engines share an OUI table (`flock_oui.h`) split into two sets. The **core set** is the upstream colonelpanichacks field-tested Flock prefixes and is always on. An **extended set** — broad cellular/WiFi/control-chip vendor OUIs merged from other repos (Cradlepoint, Sierra Wireless, Liteon, Murata, Espressif) — is **off by default** because those prefixes appear on countless non-Flock devices (every ESP32 BLE radio, etc.) and cause false positives. Enable it under *Settings → Config → Hardware → Flock Detection → Extended OUI set* when you want maximum coverage and will triage the noise. The setting persists on the device and, in node mode, propagates from the manager to every node.

**Flock WiFi** runs 802.11 promiscuous, hopping channels **1 / 6 / 11** and firing a wildcard probe on each hop to pull responses faster than waiting for beacons (dwell and channel range are configurable in *Settings → Scan Timing*). It matches the OUI table against:
- **addr2 (transmitter)** — the device sending the frame.
- **addr1 (receiver)** — catches a Flock device that only appears as a frame's *target* (e.g. probe-response targets while it burst-sleeps); multicast/broadcast skipped.
- **addr3 (BSSID)** — on management frames.
- **Wildcard probe** — a broadcast probe-request with an empty SSID from a Flock OUI is treated as a strong camera signal ([DeFlockJoplin](https://github.com/DeflockJoplin/flock-you) field research).

Each hit reports which method fired (`addr1` / `addr2` / `addr3` / `wildcard_probe`) and decodes the AP's auth mode. Flock OUIs resolve in-app to both a surveillance label and the underlying chip vendor.

**Flock BLE** matches on OUI (core set by default, extended set when enabled — see above), advertised **name** (`FS Ext Battery`, `Penguin`, `Flock`, `Pigvision`, `FlockCam`, `FlockOS`, `FS-`, `FS_`, `flocksafety`), **manufacturer ID `0x09C8`** (XUNTONG, the camera battery vendor), and **Raven** gunshot-detector GATT service UUIDs. Name / manufacturer-ID / Raven-UUID matches are unaffected by the OUI toggle — only OUI matching narrows to the core set.

### Detector
Your watchlist. Add full MACs, OUI prefixes, name patterns, or 16-bit BLE service UUIDs. Matches on BLE adverts and on WiFi promiscuous frames (addr1/addr2/addr3).

### Foxhunter
Lock one target MAC and track its RSSI live across WiFi and BLE. Buzzer cadence speeds up as you get closer.

### Sky Spy
FAA Remote ID drones — BLE scan for **Open Drone ID** adverts plus WiFi promiscuous for **NAN / beacon** ODID frames. Decodes operator/UAV ID, position, altitude, ground speed, and heading.

### UniPwn
Unitree robots by BLE name prefix (`Go2_`, `G1_`, `H1_`, `B2_`, `X1_`). Detect → connect → exploitation actions: enable SSH, change root password, read serial/system info, reboot, arbitrary command exec.

### Wardrive
Logs every AP it hears — SSID, BSSID (addr3), channel, and decoded auth mode from beacons and probe-responses — stamped with GPS, WiGLE-style.

---

## Flash & Hardware

**Routine updates come from the app over OTA.** The web flasher is only for the first flash on a bare board, or recovery.

### Web Flasher
[lukeswitz.github.io/oui-spy-unified-blue](https://lukeswitz.github.io/oui-spy-unified-blue/) — Chrome / Edge 89+ (Web Serial). Plug in via USB-C, pick the target board (node / manager), Connect & Flash.

### Flash Layout
| File | Offset | Purpose |
|---|---|---|
| `bootloader.bin` | `0x0000` | Bootloader |
| `partitions.bin` | `0x8000` | Partition table |
| `boot_app0.bin` | `0xe000` | OTA data |
| `firmware.bin` | `0x10000` | App-controlled firmware |

### Hardware — Seeed Studio XIAO ESP32-S3
USB-C · 8 MB flash · BLE 5 + WiFi · dual-core 240 MHz.

| Pin | Function |
|---|---|
| GPIO 3 | Piezo buzzer (PWM, app-controlled volume) |
| GPIO 4 | NeoPixel WS2812B (app-controlled brightness) |
| GPIO 21 | Onboard LED (active LOW) |
| GPIO 43/44 | Optional hardware GPS TX/RX (otherwise phone GPS is relayed) |

Managers also run on **ESP32 WROOM** and **XIAO ESP32-C3**.

---

<details>
<summary><b>Build from Source</b></summary>

### Firmware (PlatformIO)
```bash
pio run -e v3_app_controlled            # node (XIAO ESP32-S3)
pio run -e v3_node_manager_wroom        # manager (ESP32 WROOM)
pio run -e v3_node_manager_xiao_c3      # manager (XIAO ESP32-C3)
pio run -e v3_app_controlled -t upload  # flash
pio device monitor                      # serial @ 115200
```
Dependency: `NimBLE-Arduino`.

### Companion App (Flutter 3.32+)
```bash
cd companion
flutter pub get
flutter run                  # debug on attached device
flutter build apk --release
flutter build ipa --release
flutter build macos --release
```
**iOS Live Activity (optional):** the `OuiSpyLiveActivity` Widget Extension target provides the Dynamic Island.

</details>

<details>
<summary><b>Dependencies & Services</b></summary>

**Firmware:** [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) (BLE + ESP-NOW coexistence), [ESP Async WebServer](https://github.com/mathieucarbou/ESPAsyncWebServer) (LAN OTA), [Adafruit NeoPixel](https://github.com/adafruit/Adafruit_NeoPixel), [ArduinoJson](https://github.com/bblanchon/ArduinoJson), [TinyGPS++](https://github.com/mikalhart/TinyGPSPlus). Built on ESP-IDF (WiFi promisc, ESP-NOW, mbedTLS AES-GCM mesh).

**App:** flutter_blue_plus · flutter_map + latlong2 · drift + sqlite3 · geolocator · flutter_riverpod · go_router · flutter_local_notifications · dio · share_plus · freezed · flutter_secure_storage · wakelock_plus · permission_handler · shared_preferences · intl · uuid · crypto.

**Services:** [WiGLE](https://api.wigle.net) (CSV upload) · [CARTO](https://carto.com/basemaps/) / [OpenStreetMap](https://www.openstreetmap.org/) / [OpenTopoMap](https://opentopomap.org/) / [Stadia Maps](https://stadiamaps.com/) (tiles).

**Data:** [Ringmast4r/OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database) — 39k+ IEEE OUI vendors.

</details>

<details>
<summary><b>Ecosystem (standalone forks)</b></summary>

Each engine also exists as a standalone firmware:

| Project | What |
|---|---|
| [OUI-SPY Detector](https://github.com/colonelpanichacks/ouispy-detector) | BLE/WiFi watchlist scanner |
| [OUI-SPY Foxhunter](https://github.com/colonelpanichacks/ouispy-foxhunter) | RSSI proximity tracker |
| [Flock You](https://github.com/colonelpanichacks/flock-you) | Flock Safety / Raven detector |
| [Sky-Spy](https://github.com/colonelpanichacks/Sky-Spy) | Drone Remote ID capture |
| [Remote-ID-Spoofer](https://github.com/colonelpanichacks/Remote-ID-Spoofer) | WiFi Remote ID spoofer + swarm |
| [OUI-SPY UniPwn](https://github.com/colonelpanichacks/Oui-Spy-UniPwn) | Unitree robot exploitation |

</details>

---

## Acknowledgments

- **Will Greenberg** ([@wgreenberg](https://github.com/wgreenberg)) — [flock-you](https://github.com/wgreenberg/flock-you): manufacturer ID `0x09C8` (XUNTONG) detection and structured pattern approach.
- **@NitekryDPaul / OrdoOuroborous** ([@nitekry](https://github.com/nitekry)) — original promiscuous-mode Flock OUI set and the addr1 receiver-side technique.
- **Michael / DeFlockJoplin** ([DeflockJoplin](https://github.com/DeflockJoplin/flock-you)) — wildcard-probe signature from Joplin drive-tests.
- OUI superset also draws on [zmattmanz/flock-detection](https://github.com/zmattmanz), [dougborg/AirHound](https://github.com/dougborg), and [VirtuallyScott/flock-you](https://github.com/VirtuallyScott).
- **OUI-SPY ecosystem author:** **colonelpanichacks**.

---

## Disclaimer

Security-research and privacy-auditing tool. Detecting surveillance hardware in public spaces is legal in most jurisdictions. Comply with local laws on wireless scanning and signal interception. GATT exploitation actions carry risk. Lawful use only — authors not responsible for misuse.

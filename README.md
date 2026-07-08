<div align="center">

[![Release](https://img.shields.io/github/v/release/lukeswitz/oui-spy-unified-blue?include_prereleases&label=pre-release&color=green)](https://github.com/lukeswitz/oui-spy-unified-blue/releases)
[![TestFlight](https://img.shields.io/badge/TestFlight-Join-blue.svg?logo=apple)](https://testflight.apple.com/join/5RCKgnJ2)
![Platforms](https://img.shields.io/badge/iOS%20%7C%20macOS%20%7C%20Android-1BA1E2)
![Firmware](https://img.shields.io/badge/firmware-ESP32--S3-ff6600)
[![CodeQL](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql)

# OUI-APEX

<img width="320" alt="OUI-SPY APEX" src="https://github.com/user-attachments/assets/5a201c27-558b-4409-9e49-82d6e0176a4c" />

**A phone-controlled ESP32 WiFi/BLE detector and wardriver.** Eight detection engines on one ESP32-S3, driven from a Flutter app over BLE. Run a single board, or a mesh of boards with one coordinator.

[**Which firmware?**](#which-firmware--node-vs-manager) · [**Quick start**](#quick-start) · [**Engines**](#engines) · [**The app**](#the-app) · [**Mesh**](#mesh-multiple-boards) · [**Flash & build**](#flashing--hardware)

</div>

> [!NOTE]
> Runs the [OUI-SPY ecosystem](https://github.com/colonelpanichacks) by colonelpanichacks. **Not affiliated with OUI-SPY.** Beta software — expect bugs.

---

## Which firmware — NODE vs MANAGER

**One board? Flash NODE.** This is the answer for almost everyone.

- **NODE** is the scanner. It runs the detection engines on its own WiFi + BLE radios and connects to the phone app directly. A single node is a complete, standalone OUI-SPY. The web flasher defaults to it.
- **MANAGER** is only for a mesh of **2+ boards**. It is a coordinator: it links to the phone, splits work across nodes, and aggregates their detections — **it has no detection engines and does not scan itself.** A lone manager connects to the app but finds nothing. Flash a manager only when you have nodes for it to run.

| You have… | Flash |
|---|---|
| **One board** | **NODE** (`node-xiao_s3`) |
| **Several boards** | **NODE** on every board except the one you connect the app to; **MANAGER** on that one |

---

## Quick start

1. **Flash** — open the [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) in Chrome or Edge, plug in via USB-C, keep the default **NODE** target, hit **Connect & Flash**. One time only; after that the app updates it over the air.
2. **Install the app** — [Android APK](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest) · [iOS / macOS TestFlight](https://testflight.apple.com/join/5RCKgnJ2) · [macOS signed build](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest).
3. **Connect** — open the app, tap **CONNECT**, pick your board from the scan list.

> [!IMPORTANT]
> On Android, grant **Location → Allow all the time** — Android requires it to keep BLE scanning while the app is backgrounded or the screen is off.

Auto-connect is off by default (*Settings → Config → Connection → Auto-connect on launch*). Off: the app waits for you to pick a device. On: it reconnects to your last board by saved ID, including after you leave and return to BLE range.

<img width="610" alt="APEX overview" src="https://github.com/user-attachments/assets/0a798936-51f3-41d2-b103-cdec0e7d9134" />

---

## Engines

Eight engines, toggled from the home screen. They run together on whatever radios each needs.

| Engine | Radio | What it detects |
|---|---|---|
| **Detector** | WiFi + BLE | Your watchlist (MAC / OUI prefix / name / BLE service UUID) **plus** built-in signatures: Find My/AirTag trackers, Flipper Zero, WiFi deauth storms, directed probe-requests, Pwnagotchi |
| **Flock BLE** | BLE | Flock Safety cameras + Raven gunshot sensors by BLE fingerprint |
| **Flock WiFi** | WiFi | Flock Safety cameras by 802.11 traffic |
| **Foxhunter** | WiFi + BLE | One chosen target — buzzer speeds up as you close in |
| **Sky Spy** | WiFi + BLE | FAA Remote ID drones (Open Drone ID) + operator position |
| **UniPwn** | BLE | Unitree robots — detect, connect, exploit actions |
| **Wardrive** | WiFi + BLE | Every AP + BLE device, WiGLE-style, GPS-stamped |
| **PCAP** | WiFi *or* BLE | Raw 802.11 or BLE link-layer frames to a `.pcap` |

Detail on each is in [Detection internals](#detection-internals).

---

## The app

Flutter app for iOS, macOS, and Android.

**Home** — one card per engine; tap to toggle or open its settings. Status bar shows connection, GPS fix, and node count.

**Live feed** — every detection from every engine in one stream. Filter by engine / preset / node, sort by time / RSSI / MAC, free-text search, and export the current view to WiGLE CSV. Tap a row to foxhunt or map it; long-press for the full detail sheet.

**Wardrive & map** — pick any mix of targets (WiGLE / Flock / Drone / Detector) and a radio (WiFi / BLE / Both), then **START**. Hits plot live, color-graded by density, with your route behind you. Drones plot at their broadcast Remote ID position (or an RSSI ring when they report no fix). Sessions save as WiGLE CSV and upload to WiGLE with your API key; saved sessions replay on the map, and you can import CSVs.

<img width="709" alt="App home" src="https://github.com/user-attachments/assets/62470061-c382-4724-8d86-72cb4dd4c1df" />
<img width="910" alt="Wardrive map" src="https://github.com/user-attachments/assets/cc0d4cc9-6524-41c7-bb04-9cd01dae58b8" />

**Geofences** — draw a zone; inside it everything goes silent (no feed, no log, no CSV, no beep, radios paused). Scanning resumes when you leave.

**PCAP** — no SD card; frames stream over BLE and the app writes a `.pcap` for Wireshark. WiFi 802.11 (radiotap) or BLE LL. **Auto-PCAP**: when an engine fires, the board can capture for 3–120 s (with cooldown + per-MAC rediscover), labeled by the engine and MAC that triggered it, then return to scanning. A PCAP library screen lists your captures.

<img width="910" alt="PCAP" src="https://github.com/user-attachments/assets/4b34e73d-1341-4222-8ec2-d17a179f6faa" />

**Offline scan** *(Settings → Config → Hardware → Offline Scan)* — keep the detection engines running after you close the app or walk out of BLE range; targeted detections buffer to flash and sync when you reconnect. The enabled engines + watchlist are saved to flash, so scanning **survives a reboot / power cycle** and resumes on boot with no phone.

**OTA updates** *(Settings → Updates)* — update over WiFi (give credentials once) or BLE (slower, works anywhere). In a mesh, nodes update one at a time.

**Settings** — appearance, units, scan timing, channel range, the OUI vendor database (with WiGLE CSV import), WiGLE login, buzzer/LED, station-mode WiFi, watchlist, ignore list, factory reset, and database export/import for backing up captures.

<img width="1133" alt="Settings" src="https://github.com/user-attachments/assets/b8072937-67fb-4ae3-adc0-d1c748a26983" />

**iOS Dynamic Island** — on iPhone 14 Pro and newer (iOS 16.2+), live detection counts show on the Lock Screen and Dynamic Island during a session.

---

## Mesh (multiple boards)

Flash the board you connect the app to as a **manager** (`mgr-xiao_s3` — its PSRAM holds a deep detection buffer) and every other board as a **node**. Power them on; nodes auto-join in ~10 s with no pairing. Connect the app to the manager.

- Detection runs across **all nodes**; every hit is tagged with the node that found it.
- The manager splits the WiFi channel range across nodes to cover the band faster.
- Manager settings (buzzer, LED, alert timing, ignore list, wardrive radio) push to every node and override their local copies.
- The manager does not scan — it coordinates and aggregates. All detection comes from nodes.
- With Offline Scan on, the manager persists its commanded engine set so a manager reboot restores it and re-commands the nodes.

---

## Detection internals

802.11 frames carry three MAC fields — **addr1** (receiver), **addr2** (transmitter), **addr3** (BSSID). Several engines check all three so a target is caught in any role.

**Detector** — your watchlist (full MACs, OUI prefixes, name patterns, 16-bit BLE service UUIDs), matched on BLE adverts and WiFi promiscuous frames. Alongside it, built-in signatures fire with no config: Find My/AirTag offline-finding adverts, Flipper Zero (`Flipper` name), WiFi deauth/disassoc storms (rate-gated), directed probe-request SSIDs, and the Pwnagotchi beacon. Each is labeled in the feed by what it is.

**Flock** — both engines share an OUI table (`flock_oui.h`). A field-tested **core set** is always on; an **extended set** (broad cellular/WiFi/control-chip vendor OUIs) is off by default because those prefixes appear on countless non-Flock devices — enable it under *Settings → Hardware → Flock Detection* when you want max coverage and will triage noise. Flock WiFi runs 802.11 promiscuous on channels 1/6/11, firing a wildcard probe on each hop, matching the OUI table on addr2/addr1/addr3 and decoding AP auth mode. Flock BLE matches on OUI, advertised name (`Penguin`, `Flock`, `FlockCam`, `FS-`, …), manufacturer ID `0x09C8` (XUNTONG), and Raven gunshot-detector GATT UUIDs.

**Foxhunter** — lock one target MAC; buzzer cadence speeds up as RSSI rises, across WiFi and BLE.

**Sky Spy** — FAA Remote ID: BLE scan for Open Drone ID adverts + WiFi promiscuous for NAN / beacon ODID frames. Decodes operator/UAV ID, position, altitude, speed, heading.

**UniPwn** — Unitree robots by BLE name prefix (`Go2_`, `G1_`, `H1_`, `B2_`, `X1_`): detect → connect → exploit actions.

**Wardrive** — logs every AP + BLE device (SSID, BSSID, channel, decoded auth mode), GPS-stamped, WiGLE-compatible.

---

## Flashing & hardware

Routine updates come from the app over OTA. The web flasher is for the first flash on a bare board, or recovery.

**Web flasher** — [lukeswitz.github.io/oui-spy-unified-blue](https://lukeswitz.github.io/oui-spy-unified-blue/), Chrome / Edge 89+ (Web Serial). Plug in via USB-C, pick the target (NODE is the default), Connect & Flash.

**Flash layout**

| File | Offset |
|---|---|
| `bootloader.bin` | `0x0000` |
| `partitions.bin` | `0x8000` |
| `boot_app0.bin` | `0xe000` |
| `firmware.bin` | `0x10000` |

**Hardware — Seeed Studio XIAO ESP32-S3** (USB-C, 8 MB flash, BLE 5 + WiFi, dual-core 240 MHz):

| Pin | Function |
|---|---|
| GPIO 3 | Piezo buzzer (PWM) |
| GPIO 4 | NeoPixel WS2812B |
| GPIO 21 | Onboard LED (active LOW) |
| GPIO 43/44 | Optional hardware GPS TX/RX (else phone GPS is relayed) |

Managers also run on **ESP32-S3 N16R8 DevKitC**, **XIAO ESP32-C3**, and **ESP32 WROOM**.

<details>
<summary><b>Build from source</b></summary>

### Firmware (PlatformIO)
```bash
pio run -e v3_app_controlled             # node (XIAO ESP32-S3)
pio run -e v3_app_controlled_s3_devkitc  # node (ESP32-S3 N16R8 DevKitC)
pio run -e v3_node_manager_s3            # manager (XIAO ESP32-S3)
pio run -e v3_node_manager_xiao_c3       # manager (XIAO ESP32-C3)
pio run -e v3_node_manager_wroom         # manager (ESP32 WROOM)
pio run -e v3_app_controlled -t upload   # flash node
pio device monitor                       # serial @ 115200
```
Dependency: `NimBLE-Arduino`.

### App (Flutter 3.32+)
```bash
cd companion
flutter pub get
flutter run
flutter build apk --release
flutter build ipa --release
flutter build macos --release
```

</details>

<details>
<summary><b>Dependencies & services</b></summary>

**Firmware:** [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino), [Adafruit NeoPixel](https://github.com/adafruit/Adafruit_NeoPixel), [ArduinoJson](https://github.com/bblanchon/ArduinoJson), [TinyGPS++](https://github.com/mikalhart/TinyGPSPlus). ESP-IDF WiFi promiscuous + ESP-NOW + mbedTLS AES-GCM mesh.

**App:** flutter_blue_plus · flutter_map + latlong2 · drift + sqlite3 · geolocator · flutter_riverpod · go_router · flutter_local_notifications · dio · share_plus · flutter_secure_storage · wakelock_plus · permission_handler.

**Services:** [WiGLE](https://api.wigle.net) · [CARTO](https://carto.com/basemaps/) / [OpenStreetMap](https://www.openstreetmap.org/) / [OpenTopoMap](https://opentopomap.org/) / [Stadia Maps](https://stadiamaps.com/) tiles · [Ringmast4r/OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database) vendor OUIs.

</details>

<details>
<summary><b>Ecosystem (standalone forks)</b></summary>

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

- **Will Greenberg** ([@wgreenberg](https://github.com/wgreenberg)) — [flock-you](https://github.com/wgreenberg/flock-you): manufacturer ID `0x09C8` (XUNTONG) detection.
- **@NitekryDPaul / OrdoOuroborous** ([@nitekry](https://github.com/nitekry)) — original promiscuous Flock OUI set + the addr1 receiver-side technique.
- **Michael / DeFlockJoplin** ([DeflockJoplin](https://github.com/DeflockJoplin/flock-you)) — wildcard-probe signature.
- OUI superset also draws on [zmattmanz/flock-detection](https://github.com/zmattmanz), [dougborg/AirHound](https://github.com/dougborg), [VirtuallyScott/flock-you](https://github.com/VirtuallyScott).
- **OUI-SPY ecosystem author:** **colonelpanichacks**.

---

## Disclaimer

Security-research and privacy-auditing tool. Detecting surveillance hardware in public is legal in most jurisdictions; comply with local laws on wireless scanning and interception. GATT exploitation actions carry risk. Lawful use only — authors not responsible for misuse.
</content>

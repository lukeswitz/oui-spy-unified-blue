<div align="center">

[![Release](https://img.shields.io/github/v/release/lukeswitz/oui-spy-unified-blue?include_prereleases&label=pre-release&color=green)](https://github.com/lukeswitz/oui-spy-unified-blue/releases)
[![TestFlight](https://img.shields.io/badge/TestFlight-Join-blue.svg?logo=apple)](https://testflight.apple.com/join/5RCKgnJ2)
![Platforms](https://img.shields.io/badge/iOS%20%7C%20macOS%20%7C%20Android-1BA1E2)
![Firmware](https://img.shields.io/badge/firmware-ESP32--S3-ff6600)
[![CodeQL](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql)

<img width="220" alt="OUI-SPY APEX" src="https://github.com/user-attachments/assets/5a201c27-558b-4409-9e49-82d6e0176a4c" />

# OUI-SPY APEX

**Catch surveillance gear OTG.**

Eight detection engines on one ESP32, all driven from a companion app — no reboots, no web portals, no mode switches. Drive around and it maps everything it sees.

[**Quick Start**](#quick-start) · [**Engines**](#engines) · [**Using the App**](#using-the-app) · [**How Detection Works**](#how-detection-works) · [**Flash**](#flash--hardware)

</div>


> [!NOTE]
>  Not affiliated with OUI-SPY in any official context. Beta: bugs and odd behavior expected. 


---

## What it is

The original OUI-SPY tools were separate firmwares — you flashed one, picked a mode at boot, and configured it through a WiFi portal. **APEX merges all eight into one image** that runs them together, replaces the portal with a **phone app**, and turns the whole thing into a live **wardriving map** you take on the road.

Flash once. After that, everything — engines, channels, watchlists, captures, updates — lives in the app.

---

## Quick Start

1. **Flash the device** — open the [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) in Chrome or Edge, plug in the board via USB-C, hit **Connect & Flash**.
2. **Install the app** — [Android APK](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest) · [iOS / macOS TestFlight](https://testflight.apple.com/join/5RCKgnJ2) · [macOS signed app](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest).
3. **Connect** — open the app, tap **CONNECT**, pick your device in the **SCAN FOR OUI-SPY** list.

The app doesn't auto-connect (opt in at *Settings → App → Connection*). On launch it clears stale links and waits — you choose what to connect to. Reconnect is one tap.

---

## Engines

Toggle any combination from the home screen — they all run at once, sharing radio time.

| # | Engine | Radio | Detects |
|---|--------|-------|---------|
| 1 | **Detector** | WiFi + BLE | Your watchlist — MAC, OUI prefix, name pattern, or BLE service UUID |
| 2 | **Flock BLE** | BLE | Flock cameras + Raven gunshot detectors |
| 3 | **Flock WiFi** | WiFi | Flock Safety cameras (promiscuous) |
| 4 | **Foxhunter** | WiFi + BLE | RSSI proximity tracking of one chosen target |
| 5 | **Sky Spy** | WiFi + BLE | FAA Remote ID drones |
| 6 | **UniPwn** | BLE | Unitree robots — detect → connect → exploit |
| 7 | **Wardrive** | WiFi + BLE | WiGLE-style logging — SSID, BSSID, channel, auth, GPS |
| 8 | **PCAP** | WiFi or BLE | Raw 802.11 (radiotap) or BLE LL, streamed to the phone |

[How each one works ↓](#how-detection-works)

---

## Using the App

Flutter app for iOS, macOS, and Android. Talks to the device over BLE.

### Home
Per-engine cards — tap one to toggle it or open its settings. Status bar shows connection, GPS, and node count.

### Live Feed
Every detection across all engines, in one list.
- Filter by engine, preset (surveillance-only, etc.), or source node; sort by time / RSSI / MAC; free-text search.
- **Export** the current filtered view to WiGLE CSV.
- **Tap** a row to foxhunt or map it; **long-press** for the full copy sheet (MAC, vendor, RSSI, channel, manuf data).

### Wardrive (the map)
Pick a **target** (WiGLE · Flock · Drone · Detector · WiGLE+Flock) and a **radio** (WiFi · BLE · Both), then **START**. Detections plot live, color-graded by signal density; the route follows you. Sessions save as WiGLE CSV and upload straight to WiGLE with your API key. Draw **geofences**: inside an excluded zone every hit is muted — no feed entry, no database or WiGLE CSV logging, no beep or notification — and during a wardrive the radios pause entirely. Everything resumes the moment you leave. Saved sessions replay on the map.

### PCAP
No SD card — frames stream live over BLE and the app writes the `.pcap` (open in Wireshark).
- **WiFi 802.11 (radiotap)** — beacons, probes, deauth, data, control, mgmt over a channel range.
- **BLE LL** — adverts and scan req/resp with synthesized link-layer headers.
- **Auto-PCAP** — when a detection engine hits, the device auto-captures for 3–120 s (with cooldown + per-MAC rediscover window), then resumes scanning. Captures are auto-labeled with the engine and MAC that triggered them.

### Updates (OTA)
*Settings → Updates → Check for Update.* Install over **WiFi** (fast — give credentials once) or **BLE** (works anywhere, slower). No cables after the first flash. In node mode, each live node updates the same way, one at a time.

### Settings
Everything else: appearance, units, scan timing, channel range, the 39k+ OUI vendor database (+ WiGLE CSV import), WiGLE login, buzzer/LED, firmware timing, station-mode WiFi, factory reset, watchlist, ignore list, and **database import / export** (back up and restore your captures).

### iOS Dynamic Island
iPhone 14 Pro+ on iOS 16.2+ — live counts on the Lock Screen and Island during a session.

---

## Node Mode (run a swarm)

Flash one board as a **manager** (`mgr-xiao_c3` or `mgr-wroom`) and the rest as **nodes** (`node-xiao_s3`). Power on — nodes auto-join in ~10 s, no pairing. Connect the app to the **manager**.

- Detection engines run across **all** nodes at once; every hit is tagged with the node that found it.
- The manager splits the WiFi channel range across nodes — more boards cover the band faster and more ground.
- On a WiGLE wardrive **START**, a popup lets you set each node to **WiFi / BLE / Both**.
- **PCAP** captures from one node you pick.

Manager settings (buzzer, LED, alert timing, ignore list, wardrive radio) push to every node and **override** local copies — one place drives the whole swarm. Turning an engine off or closing the app stops the nodes; nothing scans unattended.

---

## How Detection Works

802.11 frames carry three MAC address fields: **addr1** = receiver, **addr2** = transmitter, **addr3** = BSSID. Several engines check all three so a target gets caught no matter which role it plays in a frame.

### Flock — cameras + Raven gunshot detectors

Two engines share a **66-prefix OUI table** (`flock_oui.h`) covering Flock-direct plus the cellular/WiFi/control vendors their hardware uses (Cradlepoint, Sierra Wireless, Liteon, Murata, Espressif).

**Flock WiFi** — 802.11 promiscuous, hops channels **1 / 6 / 11**, firing a wildcard probe on each hop to pull responses faster than waiting for beacons. (Dwell and channel range are configurable in *Settings → Scan Timing*.) It matches the OUI table against:

- **addr2 (transmitter)** — the device sending the frame.
- **addr1 (receiver)** — catches a Flock device that only appears as a frame's *target* (e.g. probe-response targets while it burst-sleeps); multicast/broadcast skipped.
- **addr3 (BSSID)** — on management frames.
- **Wildcard probe** — a broadcast probe-request with an empty SSID from a Flock OUI is treated as a strong camera signal ([DeFlockJoplin](https://github.com/DeflockJoplin/flock-you) field research).

Each hit reports which method fired (`addr1` / `addr2` / `addr3` / `wildcard_probe`) and decodes the AP's auth mode. Flock OUIs resolve in-app to a surveillance label *and* the underlying chip vendor.

**Flock BLE** — matches on OUI, advertised **name** (`FS Ext Battery`, `Penguin`, `Flock`, `Pigvision`, `FlockCam`, `FlockOS`, `FS-`, `FS_`, `flocksafety`), **manufacturer ID `0x09C8`** (XUNTONG, the camera battery vendor), and **Raven** gunshot-detector GATT service UUIDs.

### Detector
Your watchlist. Add full MACs, OUI prefixes, name patterns, or 16-bit BLE service UUIDs; matches on BLE adverts and on WiFi promiscuous frames (addr1/addr2/addr3).

### Foxhunter
Lock one target MAC and track its RSSI live across WiFi + BLE. Buzzer cadence speeds up as you close in.

### Sky Spy
FAA Remote ID drones — BLE scan for **Open Drone ID** adverts plus WiFi promiscuous for **NAN / beacon** ODID frames. Decodes operator / UAV ID, position, altitude, ground speed, heading.

### UniPwn
Unitree robots by BLE name prefix (`Go2_`, `G1_`, `H1_`, `B2_`, `X1_`). Detect → connect → exploitation actions: enable SSH, change root password, read serial / system info, reboot, arbitrary command exec.

### Wardrive
Logs every AP it hears — SSID, BSSID (addr3), channel, and decoded auth mode from beacons and probe-responses — stamped with GPS, WiGLE-style.

### PCAP
Dumps raw frames (no detection logic) — see [PCAP](#pcap) above.

---

## Flash & Hardware

**Updates come from the app over OTA.** The web flasher is for the first flash on a bare board or recovery.

### Web Flasher
[lukeswitz.github.io/oui-spy-unified-blue](https://lukeswitz.github.io/oui-spy-unified-blue/) — Chrome / Edge 89+ (Web Serial). Plug in via USB-C, pick the target (node / manager board), Connect & Flash.

### Flash Layout

| File | Offset | Purpose |
|------|--------|---------|
| `bootloader.bin` | `0x0000` | Bootloader |
| `partitions.bin` | `0x8000` | Partition table |
| `boot_app0.bin`  | `0xe000` | OTA data |
| `firmware.bin`   | `0x10000` | App-controlled firmware |

### Hardware — Seeed Studio XIAO ESP32-S3
USB-C · 8 MB flash · BLE 5 + WiFi · dual-core 240 MHz.

| Pin | Function |
|-----|----------|
| GPIO 3  | Piezo buzzer (PWM, app-controlled volume) |
| GPIO 4  | NeoPixel WS2812B (app-controlled brightness) |
| GPIO 21 | Onboard LED (active LOW) |
| GPIO 43/44 | Optional hardware GPS TX/RX (phone GPS relay otherwise) |

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

**iOS Live Activity (optional):** the `OuiSpyLiveActivity` Widget Extension target provides Dynamic Island.

</details>

<details>
<summary><b>Dependencies & Services</b></summary>

**Firmware:** [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) (BLE + ESP-NOW coexist), [ESP Async WebServer](https://github.com/mathieucarbou/ESPAsyncWebServer) (LAN OTA), [Adafruit NeoPixel](https://github.com/adafruit/Adafruit_NeoPixel), [ArduinoJson](https://github.com/bblanchon/ArduinoJson), [TinyGPS++](https://github.com/mikalhart/TinyGPSPlus). Built on ESP-IDF (WiFi promisc, ESP-NOW, mbedTLS AES-GCM mesh).

**App:** flutter_blue_plus · flutter_map + latlong2 · drift + sqlite3 · geolocator · flutter_riverpod · go_router · flutter_local_notifications · dio · share_plus · freezed · flutter_secure_storage · wakelock_plus · permission_handler · shared_preferences · intl · uuid · crypto.

**Services:** [WiGLE](https://api.wigle.net) (CSV upload) · [CARTO](https://carto.com/basemaps/) / [OpenStreetMap](https://www.openstreetmap.org/) / [OpenTopoMap](https://opentopomap.org/) / [Stadia Maps](https://stadiamaps.com/) (tiles).

**Data:** [Ringmast4r/OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database) — 39k+ IEEE OUI vendors.

</details>

<details>
<summary><b>Ecosystem (standalone forks)</b></summary>

Each engine also exists standalone:

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

- **Will Greenberg** ([@wgreenberg](https://github.com/wgreenberg)) — [flock-you](https://github.com/wgreenberg/flock-you): manufacturer ID `0x09C8` (XUNTONG) detection and structured pattern approach.
- **@NitekryDPaul / OrdoOuroborous** ([@nitekry](https://github.com/nitekry)) — original promiscuous-mode Flock OUI set and the addr1 receiver-side technique.
- **Michael / DeFlockJoplin** ([DeflockJoplin](https://github.com/DeflockJoplin/flock-you)) — wildcard-probe signature from Joplin drive-tests.
- OUI superset also draws on [zmattmanz/flock-detection](https://github.com/zmattmanz), [dougborg/AirHound](https://github.com/dougborg), and [VirtuallyScott/flock-you](https://github.com/VirtuallyScott).
- **OUI-SPY ecosystem author:** **colonelpanichacks**.

---

## Disclaimer

Security research and privacy-auditing tool. Detecting surveillance hardware in public spaces is legal in most jurisdictions. Comply with local laws on wireless scanning and signal interception. GATT exploitation actions carry risk. Lawful use only — authors not responsible for misuse.

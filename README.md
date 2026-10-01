<div align="center">

[![Release](https://img.shields.io/github/v/release/lukeswitz/oui-spy-unified-blue?include_prereleases&label=pre-release&color=green)](https://github.com/lukeswitz/oui-spy-unified-blue/releases)
[![TestFlight](https://img.shields.io/badge/TestFlight-Join-blue.svg?logo=apple)](https://testflight.apple.com/join/5RCKgnJ2)
![Platforms](https://img.shields.io/badge/iOS%20%7C%20macOS%20%7C%20Android-1BA1E2)
![Firmware](https://img.shields.io/badge/firmware-ESP32-ff6600)
[![CodeQL](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql)

# OUI-APEX

**"Snoop unto them - as they snoop unto us".**

</div>

ESP32 firmware and a phone app for detecting surveillance hardware, trackers and drones, and for wardriving. One firmware runs every detection engine; the app turns them on and off, maps results, and uploads to WiGLE and WDGWars.

> [!NOTE]
> Runs the [OUI-SPY ecosystem](https://github.com/colonelpanichacks) engines by colonelpanichacks. **Not affiliated with OUI-SPY.** Beta software.

<img width="610" alt="APEX overview" src="https://github.com/user-attachments/assets/0a798936-51f3-41d2-b103-cdec0e7d9134" />

## Quick start

1. Flash a board from the [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) (Chrome or Edge, USB). Pick the **NODE** target for your board. Later updates come from the app.
2. Install the app: [Android / macOS](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest) or [iOS / macOS TestFlight](https://testflight.apple.com/join/5RCKgnJ2).
3. Open the app, tap **CONNECT**, pick the board.

On Android set Location to **Allow all the time**, or scanning stops when the screen is off.

## Ways to run a board

| Mode | How | What you get |
|---|---|---|
| **App** | Phone connected over Bluetooth | Every engine, live feed, map, GPS from the phone, PCAP saved on the phone |
| **Standalone** | No phone; boards with a screen and buttons | Engines started from the buttons. T-Dongles log to microSD; M5Sticks beep and show hits on screen |
| **Mesh node** | Board runs under a MANAGER the phone connects to | The manager collects every node's hits; settings from the app reach all nodes |

**Offline scan** (CONFIG → HARDWARE) keeps a board scanning after the phone disconnects. Hits buffer to flash and upload on reconnect; the setting survives a reboot.

## Boards

| Board | Bands | Screen / buttons | microSD | Buzzer | Mesh node | Flasher target |
|---|---|---|---|---|---|---|
| XIAO ESP32-S3 | 2.4 GHz | – | – | GPIO3 (OUI-SPY board) | yes | `node-xiao_s3` |
| ESP32-S3 N16R8 DevKitC | 2.4 GHz | – | – | GPIO3 | yes | `node-s3_devkitc` |
| XIAO ESP32-C5 *(experimental)* | 2.4 + 5 GHz | – | – | GPIO25 | yes | `node-xiao_c5` |
| LilyGO T-Dongle-S3 | 2.4 GHz | LCD, 1 button, RGB LED | yes | none | yes | `node-tdongle_s3` |
| LilyGO T-Dongle-C5 *(experimental)* | 2.4 + 5 GHz | LCD, 1 button, RGB LED | yes | none | yes | `node-tdongle_c5` |
| M5StickC PLUS | 2.4 GHz | LCD, 3 buttons | – | built in | yes | `node-stickc_plus` |
| M5StickC PLUS2 | 2.4 GHz | LCD, 3 buttons | – | built in | **no** | `node-stickc_plus2` |
| M5StickC (original) | 2.4 GHz | LCD, 3 buttons | – | none | **no** | `node-stickc` |

Manager boards: XIAO ESP32-S3 (`mgr-xiao_s3`), ESP32-S3 DevKitC (`mgr-s3_devkitc`), XIAO ESP32-C3 (`mgr-xiao_c3`), ESP32 WROOM (`mgr-wroom`). A manager does no scanning.

The original M5StickC and the PLUS2 are built without mesh to fit their RAM. They connect straight to the phone or run standalone. On boards with no buzzer the app hides the buzzer settings.

## Engines

| Engine | Finds |
|---|---|
| **Detector** | Your watchlist (MAC, OUI prefix, name, 16-bit BLE service UUID), plus built-in signatures, all off by default: Find My / AirTag following you, Flipper Zero, Wi-Fi deauth floods, directed probes, Pwnagotchi, Meta Ray-Ban / Oakley glasses, Axon / law-enforcement gear |
| **Flock BLE / Flock WiFi** | Flock Safety ALPR cameras and Raven gunshot sensors |
| **Sky Spy** | Drones broadcasting FAA Remote ID over BLE and Wi-Fi: ID, position, altitude, speed, pilot position |
| **Foxhunter** | One target device. Beep rate (or the RSSI meter on boards without a buzzer) rises as you get closer. Law-enforcement devices cannot be targeted |
| **UniPwn** | Unitree robots by BLE name (`Go2_`, `G1_`, `H1_`, …) |
| **Wardrive** | Every Wi-Fi AP and BLE device, GPS-stamped, WiGLE CSV format. 2.4 GHz channels 1–14 by default; C5 boards add 5 GHz including DFS |
| **PCAP** | Raw 802.11 or BLE advertising frames to a Wireshark `.pcap` |

> [!IMPORTANT]
> The Flock OUI list comes from upstream FlockYou and matches Ubiquiti, Espressif and other common consumer parts. Check a hit with your own eyes before reporting it anywhere.

### Flock confidence

| Tier | Matched |
|---|---|
| **VERIFIED** | Bare-serial name + XUNTONG `0x09C8` manufacturer ID + TN serial |
| **HIGH** | One strong signal: Raven service UUID, Flock BLE name, or a Flock wildcard probe |
| **SUSPECTED** | A listed OUI only |

The tier shows on feed rows, in the detail sheet, and in CONFIG → DETECTIONS, which can filter by tier.

## App

Bottom tabs: **HOME · FEED · WARDRIVE · CONFIG**.

- **Home**: one card per engine to start, stop and configure it. Status bar shows link, GPS fix and node count.
- **Feed**: every detection. Filter by engine or node, sort, search, export WiGLE CSV. Tap a row to foxhunt or map it.
- **Wardrive**: choose targets (WiGLE / Flock / Drone / Detector) and radio (Wi-Fi / BLE / both), then START. Sessions save as WiGLE CSV, upload to [WiGLE](https://wigle.net) and [WDGWars](https://wdgwars.pl), and replay on the map.
- **Map layers**: *MAPPED ALPRs* scores each Flock hit against cameras already on OpenStreetMap (`ON MAP` within 75 m, `UNMAPPED` beyond 250 m). Turning it on sends the visible map area to `overpass-api.de` (fallback `overpass.private.coffee`). *WDG TERRITORY* shows WDGWars territory for a linked account.
- **Geofences**: inside a zone the app drops detections from the feed, log and notifications, and the board stops beeping. Radios keep scanning; a T-Dongle still writes to its SD card.
- **PCAP**: capture Wi-Fi or BLE; pause and resume. Auto-PCAP records 3–120 s whenever an engine fires. CONFIG → PCAPS lists saved captures.
- **CONFIG**: APP, WARDRIVE, DETECTIONS, PCAPS, IGNORE, ALERTS, HARDWARE (buzzer, LED, GPS source, offline scan), MESH, FIRMWARE (version, updates).
- **iOS**: live counts on the Lock Screen and Dynamic Island during a session.

<img width="910" alt="Wardrive map" src="https://github.com/user-attachments/assets/cc0d4cc9-6524-41c7-bb04-9cd01dae58b8" />

## Standalone controls

### T-Dongle-S3 / T-Dongle-C5

| Press | Action |
|---|---|
| 1 press | Select next mode |
| 2 presses | Start / stop selected mode |

Modes: `DETECT FLOCKB FLOCKW FOXHNT SKYSPY UNIPWN WARDRV PCAP`.

Files go to `/OUISPY` on the card:

| File | Contents |
|---|---|
| `det_*.csv` | Every detection, with coordinates when a GPS fix exists |
| `wigle_*.csv` | Wardrive rows; written only with a GPS fix (phone or GPS module) |
| `cap_*.pcap` | Packet captures |

Filenames use UTC time once GPS supplies it, otherwise a boot counter. The LED glows dim green while an engine runs and flashes the engine's color on a hit; the app's NeoPixel brightness slider sets its level, 0 turns it off.

### M5StickC / PLUS / PLUS2

| Button | Press | Action |
|---|---|---|
| **A** (front) | tap | Select next mode |
| **A** | hold | Foxhunt the last alert (or the app's target); hold again to stop |
| **B** (side) | tap | Start / stop selected mode |
| **B** | hold | Buzzer on / off (PLUS and PLUS2) |
| **PWR** | tap | Screen brightness, four steps, last is off |
| **PWR** | hold | Power off |

Modes: `DETECT FLOCKB FLOCKW FOXHNT SKYSPY UNIPWN`. Wardrive and PCAP need the app on these boards (no SD card).

### Screen (both)

Top left: selected mode (amber = selected, green = running). Top right: `APP` `MSH` `SD` `GPS` status. Left: unique Wi-Fi and BLE counts. Right: foxhunt target, `CAP` bytes while capturing, or speed. Bottom strip: one icon per mode, lit while running, underlined when selected, hit count below.

Foxhunt picks, in order: the target set in the app, else the last Detector / Flock / Sky Spy / UniPwn alert seen by this board.

## Mesh

- One MANAGER connects to the phone; up to 6 NODES report to it over ESP-NOW on 2.4 GHz channel 1.
- Nodes join on their own within about 10 s. Single hop: every node must reach the manager directly, about 200 m line of sight.
- Default is plaintext broadcast. CONFIG → MESH can switch to AES-256-GCM with a shared key.
- A node silent for 45 s drops off and rejoins when back in range.
- Buzzer, LED, alert, ignore-list, wardrive-radio and Wi-Fi-band settings set on the manager are pushed to every node.
- Any mix of node boards works under one manager (e.g. T-Dongle-S3 + T-Dongle-C5 + M5StickC PLUS + XIAO).
- Each node reports its board to the manager; the app shows it on every node row.
- Fleet update (CONFIG → FIRMWARE) updates every node over Wi-Fi, and each node downloads the image for its own board. Nodes on firmware older than this release do not report a board and take the image for the board picked in the app.

## Optional GPS module

A serial GPS (NEO-6M / NEO-8M, 9600 baud) gives the board its own position. A module fix takes priority; with no data for 5 s the board falls back to phone GPS.

| GPS | XIAO ESP32-S3 | T-Dongle-S3 | T-Dongle-C5 | M5Stick |
|---|---|---|---|---|
| TX → | GPIO44 | GPIO44 | GPIO12 | GPIO33 |
| RX ← | GPIO43 | GPIO43 | GPIO11 | GPIO32 |

Other boards: set `-DPIN_GPS_RX=` / `-DPIN_GPS_TX=`.

## Build

```bash
pio run -e v3_app_controlled                 # node, XIAO ESP32-S3
pio run -e v3_app_controlled_tdongle_s3      # node, T-Dongle-S3
pio run -e v3_app_controlled_stickc_plus     # node, M5StickC PLUS (also _stickc, _stickc_plus2)
./build_c5.sh                                # node, XIAO ESP32-C5
OUISPY_C5_ENV=v3_app_controlled_tdongle_c5 ./build_c5.sh   # node, T-Dongle-C5
pio run -e v3_node_manager_s3                # manager, XIAO ESP32-S3 (also _s3_devkitc, _xiao_c3, _wroom)
```

C5 builds use the pioarduino platform in a separate core dir (`~/.platformio-c5`) via `build_c5.sh`.

```bash
cd companion && flutter pub get && flutter build apk --release   # or ipa / macos
```

**Firmware libraries:** [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino), [TinyGPS++](https://github.com/mikalhart/TinyGPSPlus), [Adafruit GFX](https://github.com/adafruit/Adafruit-GFX-Library); ESP-IDF ESP-NOW and mbedTLS.
**Map tiles:** [CARTO](https://carto.com/basemaps/) vector, [Esri](https://www.esri.com/), [OpenStreetMap](https://www.openstreetmap.org/), [OpenTopoMap](https://opentopomap.org/). Vendor OUIs from [OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database).

## Credits

- Upstream engines: [Detector](https://github.com/colonelpanichacks/ouispy-detector), [Foxhunter](https://github.com/colonelpanichacks/ouispy-foxhunter), [Flock You](https://github.com/colonelpanichacks/flock-you), [Sky-Spy](https://github.com/colonelpanichacks/Sky-Spy), [UniPwn](https://github.com/colonelpanichacks/Oui-Spy-UniPwn) by **colonelpanichacks**.
- **Will Greenberg** ([flock-you](https://github.com/wgreenberg/flock-you)): XUNTONG `0x09C8` detection.
- **@NitekryDPaul / OrdoOuroborous** ([@nitekry](https://github.com/nitekry)): promiscuous Flock OUI set and the addr1 receiver technique.
- **DeFlockJoplin** ([flock-you](https://github.com/DeflockJoplin/flock-you)): wildcard-probe signature.
- OUI sources: [zmattmanz](https://github.com/zmattmanz), [dougborg/AirHound](https://github.com/dougborg), [VirtuallyScott](https://github.com/VirtuallyScott).

## Disclaimer

Security-research and privacy-auditing tool. Follow local law on wireless scanning. Lawful use only.

<div align="center">

[![Release](https://img.shields.io/github/v/release/lukeswitz/oui-spy-unified-blue?include_prereleases&label=pre-release&color=green)](https://github.com/lukeswitz/oui-spy-unified-blue/releases)
[![TestFlight](https://img.shields.io/badge/TestFlight-Join-blue.svg?logo=apple)](https://testflight.apple.com/join/5RCKgnJ2)
![Platforms](https://img.shields.io/badge/iOS%20%7C%20macOS%20%7C%20Android-1BA1E2)
![Firmware](https://img.shields.io/badge/firmware-ESP32-ff6600)
[![CodeQL](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql)

# OUI-APEX

<!--- <img width="320" alt="OUI-SPY APEX" src="https://github.com/user-attachments/assets/5a201c27-558b-4409-9e49-82d6e0176a4c" /> --->

**"Snoop unto them - as they snoop unto us".** 

> All on one cheap board + Android/iOS. No SD card, no laptop, no flash per-firmware. All data stored on device. **Full Wigle & WDGwars support.**

</div>

> [!NOTE]
> Runs the [OUI-SPY ecosystem](https://github.com/colonelpanichacks) by colonelpanichacks. **Not affiliated with OUI-SPY.** Beta software — expect bugs.

---

## Get started

You need **one board** and the **app**.

1. **Get a supported board** — most any ESP32-S3 works (full list below). Xiao C5 for 5G.  
2. **Flash it** — open the [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) in Chrome or Edge, plug the board in over USB-C, leave the target on **NODE**, and click **Connect & Flash**.
   You do this once. After that the app updates the board itself.
3. **Install the app** — [Android](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest) · [iPhone / Mac (TestFlight)](https://testflight.apple.com/join/5RCKgnJ2) · [Mac download](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest).
4. **Connect** — open the app, tap **CONNECT**, and pick your board. That's it.

> [!IMPORTANT]
> On Android, set Location to **Allow all the time** — Android needs that to keep scanning when the screen is off.

<img width="610" alt="APEX overview" src="https://github.com/user-attachments/assets/0a798936-51f3-41d2-b103-cdec0e7d9134" />

---

## What it does

Turn any of these on from the home screen:

- **Trackers & tools** — AirTag / Find My tags following you, Flipper Zeros, Wi-Fi attacks, Meta smart glasses, plus anything you add to your own watchlist.
- **Flock cameras** — Flock Safety license-plate cameras and Raven gunshot sensors.
- **Drones** — nearby drones broadcasting FAA Remote ID, and where the pilot is standing.
- **Foxhunt** — pick one device and let the beeper (or RSSI meter) walk you to it (faster beeping = closer).
- **Wardrive** — map every Wi-Fi and Bluetooth device around you, with GPS, WiGLE-style.
- **Record** — save raw wireless traffic to a `.pcap` file for Wireshark.
- **Unitree robots** — detect (and connect to) Unitree robot dogs.

> [!IMPORTANT]
> The ALPR upstream OUI db (FlockYou) is used.
> It contains many false positives — Ubiquiti routers, Espressif, and other parts common in consumer electronics.
> **Validate findings with your own eyes before submitting to sites like deflock.me**

### Flock confidence

Every flock hit carries the set of signals that matched, so you can tell a real camera from an OUI
coincidence:

| Tier | What matched |
|------|--------------|
| **VERIFIED** | The full validated set — bare-serial name + XUNTONG `0x09C8` manufacturer ID + TN serial |
| **HIGH** | One strong signal on its own: Raven service UUID, the BLE name, or a captured Flock wildcard probe |
| **SUSPECTED** | A known OUI and nothing else |

The tier shows on feed rows, in the detection detail sheet, and on the Config → DETECTIONS list,
which also has a FLOCK CONFIDENCE filter (ALL / VERIFIED / HIGH / SUSPECTED with counts).

### Map layers

The layers button (top-left of the wardrive map) toggles:

- **MAPPED ALPRs** — cameras already recorded on OpenStreetMap, the dataset DeFlock renders. Off by
  default. Flock hits with a GPS fix are scored against it: `ON MAP` within 75 m of a mapped camera,
  `UNMAPPED` beyond 250 m, `NO MAP DATA` where nothing has been fetched for that area yet. Tiles are
  cached on the phone, so an area you have driven keeps resolving with no signal.
- **WDG TERRITORY** — gang territory hulls from a linked WDGWars account.

Contributing an unmapped find to OpenStreetMap is offered only for a **VERIFIED** detection, and the
link is copied for you to review and submit by hand — the app never posts anything.

> [!NOTE]
> Turning on MAPPED ALPRs sends the map's bounding box to a public Overpass mirror
> (`overpass-api.de`, falling back to `overpass.private.coffee`), which tells that server what area
> you are looking at. Your detections never leave the phone.

---

## Cover more area with extra boards

Want a wider net? Add more boards.

- Flash **one** board as a **MANAGER** (the one your phone connects to) and the rest as **NODES**.
- Power them on — nodes join automatically in about 10 seconds, no pairing.
- Put the manager in the **middle** and spread the nodes around it.
- Each node must be within range **of the manager** — up to about **200 m** in open line of sight (walls, metal, and bodies cut that down).
- Nodes don't relay through each other, so you can't daisy-chain them.
- Up to **6 nodes** per manager.

The manager only gathers results; the nodes do the scanning.

---

<img width="600" height="634" alt="IMG_7559" src="https://github.com/user-attachments/assets/fda18f4c-fadf-431e-ab3e-5118436feda0" />

<details>
<summary><b>All supported boards</b></summary>

The [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) always lists what's supported today — request more via an issue.

| Board | Role | Bands | Web-flasher target | PlatformIO env |
|---|---|---|---|---|
| **XIAO ESP32-S3** | NODE | 2.4 GHz | `node-xiao_s3` | `v3_app_controlled` |
| ESP32-S3 N16R8 DevKitC | NODE | 2.4 GHz | `node-s3_devkitc` | `v3_app_controlled_s3_devkitc` |
| **LilyGO T-Dongle-S3** | NODE — LCD + microSD | 2.4 GHz | `node-tdongle_s3` | `v3_app_controlled_tdongle_s3` |
| **XIAO ESP32-C5** (experimental) | NODE — standalone only, no mesh | **2.4 + 5 GHz** | `node-xiao_c5` | `v3_app_controlled_c5` |
| **M5StickC PLUS** (v1) | NODE — LCD + 3 buttons, no SD | 2.4 GHz | `node-stickc_plus` | `v3_app_controlled_stickc_plus` |
| M5StickC PLUS2 (v2) | NODE — LCD + 3 buttons, no SD | 2.4 GHz | `node-stickc_plus2` | `v3_app_controlled_stickc_plus2` |
| M5StickC (original) | NODE — LCD + 3 buttons, no SD | 2.4 GHz | `node-stickc` | `v3_app_controlled_stickc` |
| **XIAO ESP32-S3** | MANAGER | — | `mgr-xiao_s3` | `v3_node_manager_s3` |
| ESP32-S3 N16R8 DevKitC | MANAGER | — | `mgr-s3_devkitc` | `v3_node_manager_s3_devkitc` |
| XIAO ESP32-C3 | MANAGER | — | `mgr-xiao_c3` | `v3_node_manager_xiao_c3` |
| ESP32 WROOM | MANAGER | — | `mgr-wroom` | `v3_node_manager_wroom` |

- **One board:** flash NODE (`node-xiao_s3`).
- **Several boards:** flash MANAGER on the one your phone connects to (`mgr-xiao_s3`), NODE on the rest.
- The **ESP32-C5** is the only board that also scans 5 GHz.
- It's newer and less tested — treat it as experimental.
- It runs **standalone only**: the phone connects to it directly, and it can't be a fleet node under a manager.
- The **M5StickC** boards also run standalone only — mesh is compiled out to fit their RAM.

</details>

<details>
<summary><b>M5StickC / PLUS / PLUS2 — screen and buttons</b></summary>

Two buttons and a power button. No SD card, no GPS.

### Buttons

| Button | Press | What it does |
|---|---|---|
| **A** — big front button | tap | **Cycle** to the next mode |
| **B** — small side button | tap | **Start / stop** the mode you selected |
| **PWR** — top edge | tap | Screen brightness: full → 70% → 50% → off |
| **PWR** | hold | Power off (handled in hardware) |

Tap **A** until the mode you want shows at the top left, then tap **B** to run it.
Tap **B** again to stop.

No long-presses. Every press acts on release.

### Modes

Strip order, left to right:

| Shown | Engine | Finds |
|---|---|---|
| `DETECT` | Detector | Your watchlist, AirTags, Flipper, Meta glasses, Axon |
| `FLOCKB` | Flock BLE | Flock cameras over Bluetooth |
| `FLOCKW` | Flock WiFi | Flock cameras over WiFi |
| `FOXHNT` | Foxhunter | Chases one MAC and shows how close you are |
| `SKYSPY` | Sky Spy | Drone Remote ID |
| `UNIPWN` | UniPwn | Unitree robots |
| `WARDRV` | Wardrive | Logs every network for WiGLE |

### Screen

| Where | Shows |
|---|---|
| **Top left** | Selected mode — **amber** = picked, **lime** = running |
| **Top middle** | Wardrive run time, once wardriving |
| **Top right** | `APP` `MSH` `SD` `GPS`. `MSH` and `SD` stay dark — no mesh, no card slot |
| **Left, large** | Unique **WiFi** networks seen |
| **Left, below** | Unique **BLE** devices seen |
| **Right, upper** | Foxhunt target, or `CAP 1.2M` while capturing |
| **Right, lower** | Speed in mph |
| **Bottom strip** | One icon per mode. Lit while running, dark when off, **underlined** = selected. Count underneath. |

Counts round as they grow: `999` → `1.1k` → `10.2k` → `100k` → `1M`.

### Foxhunt

`FOXHNT` + **B** hunts, in order: a target set in the app, else the last alert from
detector, Flock BLE/WiFi, Sky Spy or UniPwn. Wardrive hits and relayed detections are
never targets.

Upper-right field:

| Shows | Means |
|---|---|
| `FH --` grey | Nothing to hunt yet |
| `fh BE:5A` amber | Armed — this is what **B** will lock onto |
| `FH BE:5A` magenta | Hunting it now |

Law-enforcement OUIs are refused.

</details>

<details>
<summary><b>T-Dongle-S3 — screen, button, SD card</b></summary>

LCD, microSD, LED. Logs to the card with no app attached.

### Button

| Press | What it does |
|---|---|
| **1 press** | **Cycle** to the next mode |
| **2 presses** | **Start / stop** the mode you selected |

Press once until the mode you want shows at the top left, then press twice to run it.
Press twice again to stop.

### Screen

Same layout as the Sticks, except: strip ends in **PCAP** not wardrive, `SD` and `GPS`
are live, and the upper-right field shows `WIG`/`LOG` row counts when no foxhunt target
is armed.

### LED

Dim green while any engine runs, dark when idle. A detection flashes that engine's
colour and pulse count. Wardrive hits do not flash. Brightness follows the NeoPixel
slider in the app; `0` is off.

### SD card

Files land in `/OUISPY` on the card:

| File | Contents |
|---|---|
| `det_*.csv` | Every detection, with GPS when available |
| `wigle_*.csv` | WiGLE-format wardrive rows |
| `cap_*.pcap` | Packet captures, openable in Wireshark |

Filenames use a UTC timestamp once GPS supplies the time, otherwise a boot sequence
number.

</details>

<details>
<summary><b>App features in detail</b></summary>

One Flutter app for iOS, macOS, and Android.

**Home** — a card per engine; tap to toggle or open its settings.
The status bar shows connection, GPS fix, and node count.

**Live feed** — every detection in one stream.
Filter by engine / preset / node, sort by time / signal / MAC, search, and export to WiGLE CSV.
Tap a row to foxhunt or map it; long-press for full detail.

**Wardrive & map** — pick your targets (WiGLE / Flock / Drone / Detector) and radio (Wi-Fi / BLE / both), then **START**.
Hits plot live, color-graded by density, with your route behind you.
Drones show at their broadcast position.
Sessions save as WiGLE CSV and upload to **WiGLE** and/or **[WDGWars](https://wdgwars.pl)** with your API key.
Saved runs replay on the map, and you can import CSVs.

<img width="709" alt="App home" src="https://github.com/user-attachments/assets/62470061-c382-4724-8d86-72cb4dd4c1df" />
<img width="910" alt="Wardrive map" src="https://github.com/user-attachments/assets/cc0d4cc9-6524-41c7-bb04-9cd01dae58b8" />

**Geofences** — draw a zone and everything inside goes silent: no feed, log, CSV, or beep, radios paused.
Scanning resumes when you leave. While wardriving inside one, the map shows how many detections the
zone is holding back, so a quiet screen is never mistaken for a dead radio.

**PCAP** — frames stream over Bluetooth and the app writes a Wireshark `.pcap`; on the T-Dongle-S3 they also go straight to the card. Capture WiFi 802.11 or BLE advertising traffic (BLE saves as `LINKTYPE_BLUETOOTH_LE_LL_WITH_PHDR`). Pause and resume a capture without stopping the radio.
**Auto-PCAP** records for 3–120 s whenever an engine fires, labeled by what triggered it, then goes back to scanning.
A library screen keeps every capture.

<img width="910" alt="PCAP" src="https://github.com/user-attachments/assets/4b34e73d-1341-4222-8ec2-d17a179f6faa" />

**Offline scan** *(Settings → Config → Hardware)* — keep scanning after you close the app or walk out of range.
Hits buffer to flash and sync when you reconnect, and scanning survives a reboot with no phone attached.

**OTA updates** *(Settings → Updates)* — update over Wi-Fi or Bluetooth.
In a mesh, nodes update one at a time.

**Wardrive accounts** — link **WiGLE** and **WDGWars** at the top of *Settings → Config*.
Each shows live stats, with a strip on the home screen.

**Settings** — appearance, units, scan timing, channels, Wi-Fi band, vendor database, accounts, buzzer/LED, watchlist, ignore list, factory reset, and database backup/restore.

<img width="1133" alt="Settings" src="https://github.com/user-attachments/assets/b8072937-67fb-4ae3-adc0-d1c748a26983" />

**iOS Dynamic Island** — on iPhone 14 Pro and newer (iOS 16.2+), live counts show on the Lock Screen and Dynamic Island during a session.

</details>

<details>
<summary><b>How it works under the hood (technical)</b></summary>

**Detection engines.**
802.11 frames carry three MAC fields: addr1 (receiver), addr2 (transmitter), addr3 (BSSID).
Several engines check all three so a target is caught in any role.

**Detector**
- Matches your watchlist — MACs, OUI prefixes, name patterns, 16-bit BLE service UUIDs — on BLE adverts and Wi-Fi promiscuous frames.
- Seven built-in signatures ship off by default:
  - Find My / AirTag (persistence-gated, anti-stalking)
  - Flipper Zero (service UUIDs `0x3081`/`82`/`83`)
  - Wi-Fi deauth/disassoc storms (rate-gated)
  - directed probe SSIDs
  - Pwnagotchi
  - Meta Ray-Ban / Oakley glasses (Luxottica CID `0x0D53`, service `0xFD5F`, or name — excludes Quest/Portal)
  - Axon / law enforcement (OUI `00:25:DF`, TASER International CID `0x034D`, or service `0xFC81` on BLE; OUI only on Wi-Fi)

**Flock**
- OUI table (`flock_oui.h`): core set always on, extended set off by default (broad chipset vendors, plus `f8:a2:d6`, demoted upstream after false-positiving a Sony media player).
- Wi-Fi hops 2.4 GHz **1/6/11 only** (C5 adds non-DFS 5 GHz 36–48/149–165) with a wildcard probe per hop; a camera parked on any other 2.4 channel is invisible.
- Wi-Fi matches the upstream FlockYou way: wildcard probe request from a listed `addr2`, any other frame from a listed `addr2`, or the `addr1` sleeper-catch (unicast, non-randomised).
- `addr3`/BSSID is not checked — a consumer AP with a listed BSSID is not a camera.
- BLE matches on an explicit name (`Penguin`, `Flock`, `FS-`, `Pigvision`, …), the Raven GATT UUIDs, or serial + XUNTONG (`0x09C8`) + TN serial together.
- OUI or XUNTONG alone never reports.
- Post-March-2025 Penguins advertise a bare 10-digit serial instead of the `Penguin-` prefix; that name alone proves nothing.
- Every predicate that hit rides along as a signal mask; the app badges **VALIDATED** on serial + XUNTONG + TN.

**Sky Spy**
- Open Drone ID over BLE + Wi-Fi (NAN/beacon).
- Decodes operator/UAV ID, position, altitude, speed, heading.

**Foxhunter**
- One target MAC; buzzer cadence tracks RSSI across Wi-Fi and BLE.
- Law-enforcement devices (Axon OUI `00:25:DF`) can't be foxhunted — the target is refused and the feed/detail buttons are hidden.

**UniPwn**
- Unitree robots by BLE name prefix (`Go2_`, `G1_`, `H1_`, …): detect → connect → exploit.

**Wardrive**
- Logs every AP + BLE device (SSID, BSSID, channel, auth mode), GPS-stamped, WiGLE-compatible.
- Sweeps your configured 2.4 GHz range (default 1–14) — **every channel in range, not just 1/6/11**.
- On the C5 a config toggle (**All / 1·6·11**) picks whether 2.4 covers the full range or only 1/6/11.
- The C5 also sweeps the full 5 GHz set (UNII-1/2/2e/3, 36–165 incl DFS).

**Mesh link.**
- Nodes talk to the manager over encrypted **ESP-NOW** (AES-GCM), broadcast on one shared channel (2.4 GHz **channel 1**).
- It's a single-hop star: every node reaches the manager directly, with no node-to-node relay.
- Max 6 nodes, up to ~200 m per link in open line of sight.
- Scanning nodes weave back to channel 1 each sweep to pass traffic, so mesh chatter and channel-split scanning share the radio.
- A node silent for 45 s drops off and rejoins on its own when back in range.
- Manager settings (buzzer, LED, alert timing, ignore list, wardrive radio, Wi-Fi band) push to every node and override their local copies.
- The **ESP32-C5 does not participate in the mesh** — it runs standalone, connected directly to your phone.

</details>

<details>
<summary><b>Optional GPS module</b></summary>

A node normally gets location from your phone over Bluetooth.
Wire a serial GPS module (NEO-6M / NEO-8M, 9600 baud) and it self-locates with no phone — handy for standalone offline wardriving.
A module fix takes priority.
Unplug it and the node falls back to phone GPS automatically (5 s timeout).

| GPS module | Board (XIAO ESP32-S3 default) |
|---|---|
| TX  | GPIO44 (`PIN_GPS_RX`) |
| RX  | GPIO43 (`PIN_GPS_TX`) |
| VCC | 3V3 |
| GND | GND |

Pins are per-board — override with `-DPIN_GPS_RX=` / `-DPIN_GPS_TX=` for other variants.

</details>

<details>
<summary><b>Build from source</b></summary>

**Firmware (PlatformIO)**

```bash
pio run -e v3_app_controlled             # node (XIAO ESP32-S3)
pio run -e v3_app_controlled_s3_devkitc  # node (ESP32-S3 N16R8 DevKitC)
pio run -e v3_app_controlled_tdongle_s3  # node (LilyGO T-Dongle-S3, LCD + SD)
./build_c5.sh                            # node (XIAO ESP32-C5, dual-band 2.4+5GHz)
./build_c5.sh -t upload                  # flash the C5 node
pio run -e v3_node_manager_s3            # manager (XIAO ESP32-S3)
pio run -e v3_node_manager_s3_devkitc    # manager (ESP32-S3 N16R8 DevKitC)
pio run -e v3_node_manager_xiao_c3       # manager (XIAO ESP32-C3)
pio run -e v3_node_manager_wroom         # manager (ESP32 WROOM)
pio run -e v3_app_controlled -t upload   # flash node
pio device monitor                       # serial @ 115200
```
Dependency: `NimBLE-Arduino`.
The XIAO ESP32-C5 uses the pioarduino platform in an isolated core dir (`build_c5.sh`) so it never clobbers the shared toolchain.

**App (Flutter 3.32+)**

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
<summary><b>Libraries, services & related projects</b></summary>

**Firmware:** [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino), [Adafruit NeoPixel](https://github.com/adafruit/Adafruit_NeoPixel), [ArduinoJson](https://github.com/bblanchon/ArduinoJson), [TinyGPS++](https://github.com/mikalhart/TinyGPSPlus).
Mesh runs on ESP-IDF Wi-Fi promiscuous + ESP-NOW + mbedTLS AES-GCM.

**App:** flutter_blue_plus · flutter_map + latlong2 · drift + sqlite3 · geolocator · flutter_riverpod · go_router · flutter_local_notifications · dio · share_plus · flutter_secure_storage · wakelock_plus · permission_handler.

**Services:** [WiGLE](https://api.wigle.net) · [WDGWars](https://wdgwars.pl) · [CARTO](https://carto.com/basemaps/) / [OpenStreetMap](https://www.openstreetmap.org/) / [OpenTopoMap](https://opentopomap.org/) / [Stadia Maps](https://stadiamaps.com/) tiles · [Ringmast4r/OUI-Master-Database](https://github.com/Ringmast4r/OUI-Master-Database) vendor OUIs.

**Standalone forks this unifies:** [Detector](https://github.com/colonelpanichacks/ouispy-detector) · [Foxhunter](https://github.com/colonelpanichacks/ouispy-foxhunter) · [Flock You](https://github.com/colonelpanichacks/flock-you) · [Sky-Spy](https://github.com/colonelpanichacks/Sky-Spy) · [UniPwn](https://github.com/colonelpanichacks/Oui-Spy-UniPwn).

</details>

---

## Credits

- **Will Greenberg** ([@wgreenberg](https://github.com/wgreenberg)) — [flock-you](https://github.com/wgreenberg/flock-you): manufacturer ID `0x09C8` (XUNTONG) detection.
- **@NitekryDPaul / OrdoOuroborous** ([@nitekry](https://github.com/nitekry)) — original promiscuous Flock OUI set + the addr1 receiver-side technique.
- **Michael / DeFlockJoplin** ([DeflockJoplin](https://github.com/DeflockJoplin/flock-you)) — wildcard-probe signature.
- OUI superset also draws on [zmattmanz/flock-detection](https://github.com/zmattmanz), [dougborg/AirHound](https://github.com/dougborg), [VirtuallyScott/flock-you](https://github.com/VirtuallyScott).
- **OUI-SPY ecosystem author:** **colonelpanichacks**.

## Disclaimer

Security-research and privacy-auditing tool.
Detecting surveillance hardware in public is legal in most jurisdictions; comply with local laws on wireless scanning and interception.
Lawful use only — authors not responsible for misuse.

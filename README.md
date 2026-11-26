<div align="center">

[![Release](https://img.shields.io/github/v/tag/lukeswitz/oui-spy-unified-blue?sort=semver&label=pre-release&color=green)](https://github.com/lukeswitz/oui-spy-unified-blue/releases)
[![TestFlight](https://img.shields.io/badge/TestFlight-Join-blue.svg?logo=apple)](https://testflight.apple.com/join/5RCKgnJ2)
![Platforms](https://img.shields.io/badge/iOS%20%7C%20macOS%20%7C%20Android-1BA1E2)
![Firmware](https://img.shields.io/badge/firmware-ESP32-ff6600)
[![CodeQL](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql/badge.svg)](https://github.com/lukeswitz/oui-spy-unified-blue/actions/workflows/github-code-scanning/codeql)

# OUI-APEX


</div>

<div align="center">
<b>OUI-APEX detects surveillance hardware, trackers, drones and other devices and suspicious activity on the 2.4 and 5GHz bands.</b> 
<p>Also a solid wardriving and recon app with support for external USB devices. Meshtastic & ATAK integration.</p>
<p>

<a href="#quick-start"><b>Quick start</b></a> &middot; <a href="#a-tour-of-the-app"><b>Tour</b></a> &middot; <a href="#engines"><b>Engines</b></a> &middot; <a href="#boards"><b>Boards</b></a> &middot; <a href="#mesh"><b>Mesh</b></a> &middot; <a href="#usb-radios-on-android"><b>USB radios</b></a>
<p>

<table>
  <tr>
    <td><img width="200" src="docs/screenshots/tour/00-map.png" alt="Map after a short wardrive: hits along the route, a drone, Flock and detector hits" /></td>
    <td><img width="349" src="docs/screenshots/ui/home-photo.jpg" alt="Phone running OUI-APEX on the Home screen with an RTL-SDR connected" /></td>
  </tr>
</table>

| Platform | Phone scans | Detects on its own (no board) | Full feature hardware |
|---|---|---|---|
| Android | Bluetooth, Wi-Fi | Wi-Fi networks and Bluetooth devices. Drones that send Remote ID over Bluetooth or Wi-Fi/Wi-Fi Aware | ESP32 board(s), RTL-SDR, USB Wi-Fi adapter |
| iPhone / macOS | Bluetooth | Bluetooth devices, no drones | ESP32 board(s) |

</div>

> Runs the OUI-SPY ecosystem by colonelpanichacks, with additional features.
>
> Beta, possible unexpected behavior. *Not affiliated with OUI-SPY*
> 
  
## Contents

- [Quick start](#quick-start)
- [A tour of the app](#a-tour-of-the-app)
- [Engines](#engines)
- [Ways to run](#ways-to-run)
- [App features](#app)
- [USB radios on Android](#usb-radios-on-android)
- [Boards](#boards)
- [Mesh](#mesh)
- [Privacy](#privacy)
- [Build](#build)

## Quick start

_How it Works:_
- **Firmware (ESP32):** Runs combined OUI-SPY firmware. Add more boards to form an ESP-NOW mesh perimeter (up to 200m apart).
- **App:** controls the firmware, maps detections, and exports or uploads to WiGLE and WDGWars.
- **Phone:** scans by itself (limited), or foxhunts (tracks a signal to its source) while the boards keep detecting.

_Getting Started:_
1. Flash a board from the [web flasher](https://lukeswitz.github.io/oui-spy-unified-blue/) (Chrome or Edge, USB). Pick the **NODE** target for your board. Later updates come from the app.
2. Install the app: [Android / macOS](https://github.com/lukeswitz/oui-spy-unified-blue/releases/latest) or [iOS / macOS TestFlight](https://testflight.apple.com/join/5RCKgnJ2).
3. Open the app, tap **CONNECT**, pick the board.

- **Android:** set Location to **Allow all the time**, or scanning stops when the screen is off.
- **macOS:** Gatekeeper blocks the first launch of the release zip because it is not notarized. [TestFlight](https://testflight.apple.com/join/5RCKgnJ2) builds are.

> [!IMPORTANT]
> **Turn off Android's Wi-Fi scan limit.** Android allows four Wi-Fi scans every two minutes and fails the rest.
>
> 1. **Settings → About phone**: tap **Build number** seven times to turn on Developer options.
> 2. **Settings → System → Developer options → Networking**: turn off **Wi-Fi scan throttling**.
>
> Menu paths vary by phone. USB Wi-Fi adapters are not limited.

## A tour of the app

Every screen below is the app itself on Android, filled with made-up devices along a made-up drive through Greenwich, London. The numbers on each screen match its key.

### First launch

The app asks for each permission on its own screen, then opens Home.

<table>
  <tr>
    <td width="33%" valign="top"><img width="240" src="docs/screenshots/tour/01-permissions.png" alt="Permission step: Bluetooth" />
      <ol>
        <li><b>Progress</b>: which permission step you are on. Android asks for five.</li>
        <li><b>Continue</b>: your phone shows its own prompt next.</li>
      </ol></td>
    <td width="33%" valign="top"><img width="240" src="docs/screenshots/tour/02-location-always.png" alt="Permission step: location all the time" />
      <ol>
        <li><b>Location all the time</b>: needed to keep wardriving with the screen off.</li>
        <li><b>Continue</b>: opens Settings. Choose <b>Allow all the time</b>, then go back.</li>
      </ol></td>
    <td width="33%" valign="top"><img width="240" src="docs/screenshots/tour/03-first-launch.png" alt="Home on first launch" />
      <ol>
        <li><b>Status</b>: board link and GPS fix.</li>
        <li><b>Shortcuts</b>: the arrows open the Connect screen. The phone icon starts the phone scan.</li>
        <li><b>USE THIS DEVICE</b>: scan with the phone's own radios, no board needed.</li>
      </ol></td>
  </tr>
</table>

### Start a scan

Pick what to look for and which radios to use, then tap START.

<table>
  <tr>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/04-home-ready.png" alt="Home before a scan" />
      <ol>
        <li><b>Counters</b>: unique devices, engines running, and hits per minute.</li>
        <li><b>Targets</b>: Flock cameras, drones, every Wi-Fi and BLE device (SCAN), and your watchlist (DETECT).</li>
        <li><b>START</b>: starts a session. The app then asks which radio each board uses.</li>
        <li><b>Engine cards</b>: turn one engine on or off by itself.</li>
      </ol></td>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/05-home-running.png" alt="Home during a scan" />
      <ol>
        <li><b>Status</b>: what is scanning and how good the GPS fix is.</li>
        <li><b>PAUSE / STOP</b>: pause or end the session. A stopped session is saved.</li>
        <li><b>Hit counts</b>: hits per engine this session, next to its switch.</li>
      </ol></td>
  </tr>
</table>

### Detections

Everything the boards and the phone hear, live. Tap any row for its details.

<table>
  <tr>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/06-live.png" alt="Live detections list" />
      <ol>
        <li><b>Tools</b>: filter, sort, group Wi-Fi clients under their network, open HISTORY, and more.</li>
        <li><b>Top vendors and Flock</b>: tap a vendor to show only its devices.</li>
        <li><b>A drone</b>: its Remote ID, the radio that heard it, and its altitude.</li>
        <li><b>A detector hit</b>: here a camera, with its channel and hit count.</li>
        <li><b>A Flock hit</b>: with its confidence.</li>
      </ol></td>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/07-device-sheet.png" alt="Details of a Wi-Fi network" />
      <ol>
        <li><b>What this looks like</b>: the app's best guess, in plain words.</li>
        <li><b>Foxhunt this device</b>: follow its signal to the source.</li>
        <li><b>Trust this network</b>: warns you later about lookalikes. See <a href="#watches-and-alerts">Watches and alerts</a>.</li>
      </ol></td>
  </tr>
  <tr>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/16-devices.png" alt="Devices grouped by type" />
      <ol>
        <li><b>Tools</b>: filter, sort, group by type, and group Wi-Fi clients under their network.</li>
        <li><b>A device type</b>: tap to open it. The handle arranges the sections.</li>
        <li><b>A camera you drove past</b>: its line shows the signal getting stronger, then weaker.</li>
        <li><b>With you</b>: the walking icon marks a device that moves with you, such as your own earbuds.</li>
      </ol></td>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/17-history.png" alt="History of saved detections" />
      <ol>
        <li><b>Tools</b>: filter, sort, back to LIVE, saved sessions, and more.</li>
        <li><b>A detector hit</b>: what it matched, here a doorbell camera.</li>
        <li><b>A watch alert</b>: here a lookalike network with weaker security.</li>
      </ol></td>
  </tr>
</table>

### Alerts and what to watch for

Choose which device types alert you. Every alert lands in one list.

<table>
  <tr>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/08-alerts.png" alt="Alerts list" />
      <ol>
        <li><b>An alert</b>: what was found, why, and when. Tap it for the map and the device.</li>
        <li><b>Count and clear</b>: how many alerts, and a button to clear them.</li>
      </ol></td>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/11-what-to-watch.png" alt="Settings, What to Watch For" />
      <ol>
        <li><b>Alert threshold</b>: how sure a detector hit must be before it notifies you.</li>
        <li><b>Bell</b>: notify, or only log it.</li>
      </ol></td>
  </tr>
</table>

### Map

Every hit is placed where you heard it, along your route. The numbers are how many hits share a spot.

<table>
  <tr>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/10-map-list.png" alt="Map during a wardrive with the Flock list open" />
      <ol>
        <li><b>Session</b>: time recording, and counts of Wi-Fi, Flock, drone, detector and BLE hits.</li>
        <li><b>Flock list</b>: tap the chip to open or close it. Tap a row to zoom the map to it. Drones and detector hits have their own lists.</li>
        <li><b>Drive</b>: distance, speed, hits per km, and Stop / Pause.</li>
      </ol></td>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/09-map.png" alt="A saved wardrive session on the map" />
      <ol>
        <li><b>Saved session</b>: unique devices, total hits and distance.</li>
        <li><b>Lists</b>: Flock, drone and detector hits from this session.</li>
        <li><b>A drone</b>: its flight path and its pilot.</li>
        <li><b>A cluster</b>: tap it to list the devices there.</li>
        <li><b>SESSIONS</b>: open, export or delete saved sessions.</li>
      </ol></td>
  </tr>
</table>

### Sessions and reports

Every session is saved. Open one to replay it on the map, or open its report.

<table>
  <tr>
    <td width="33%" valign="top"><img width="240" src="docs/screenshots/tour/13-sessions.png" alt="Saved sessions list" />
      <ol>
        <li><b>SELECT, IMPORT, CLEAR ALL</b>: pick several sessions, load a WiGLE CSV, or delete them all.</li>
        <li><b>A session</b>: when, how long, how far, and its Wi-Fi, BLE, Flock, drone and detector counts. Tap it to replay it on the map.</li>
      </ol></td>
    <td width="33%" valign="top"><img width="240" src="docs/screenshots/tour/14-report.png" alt="Wardrive report, top" />
      <ol>
        <li><b>Totals</b>: Wi-Fi networks, how many were new, and Bluetooth devices.</li>
        <li><b>Wi-Fi networks</b>: new, seen before, hidden, and per band.</li>
      </ol></td>
    <td width="33%" valign="top"><img width="240" src="docs/screenshots/tour/15-report-detail.png" alt="Wardrive report, details" />
      <ol>
        <li><b>Detections</b>: Flock cameras, drones and watchlist hits.</li>
        <li><b>Alerts</b>: every alert kind raised during the session. Further down, whether it was uploaded to WiGLE and WDGWars.</li>
      </ol></td>
  </tr>
</table>

### Tips

- **Rename a board or mesh node:** go to SETTINGS → NODE → MESH → **Nodes**, tap the node, type a name of up to 32 characters, and tap **SAVE**. Leave it blank or tap **CLEAR** to go back to the node ID. The name is kept on this phone. You can also tap the pencil next to a board on the Connect screen after its first connection.
- **Find or restart a mesh node:** with a manager connected, tap a live node under SETTINGS → NODE → MESH → **Nodes**. **Identify** makes it beep and blink for 10 seconds. **Locate** makes it beep every 2 seconds until you tap **Stop locate**, for 30 minutes at most. **Reboot** restarts it. **Fleet control** below the list identifies or reboots every node at once.
- **Remove an old node:** in the same **Nodes** list, tap a node you no longer use and tap **FORGET**. The board you are connected to cannot be forgotten there.
- **Forget a paired board:** hold it on the Connect screen.
- **Too many notifications:** when alerts pile up within a minute, the app offers to turn off notifications for one noisy type. Its detections are still logged.
- **Filter by maker:** on LIVE, tap a vendor in the strip above the list to show only its devices.
- **Search everything:** on LIVE, open search and type. Every word must match a MAC, name, maker, reason or node. Chips show the matches in Devices, Alerts, Drones, Nodes and Wardrive. Tap a chip or **EVERYTHING** for the results sheet, and tap a match to open it.
- **Live counts:** above LIVE, nodes online, devices heard in the last minute, live drones, devices heard today, unread alerts and MACs kept. Under them, the devices heard in each of the last 24 hours and their total.
- **Hide addresses for screenshots:** turn on **Mask identifiers on screen** in SETTINGS → Detection & Alerts → Privacy.
- **What does this icon mean:** tap the info button on a screen. It explains each tab and icon there.

## Engines

| Engine | Finds |
|---|---|
| **Detector** | Your watchlist (exact MAC, maker prefix, Bluetooth name contains, starts with or pattern, Bluetooth company ID, company data with a mask, 16-bit or 128-bit service UUID, Wi-Fi probe prefix, Wi-Fi beacon prefix, and a phone-only maker name), plus built-in signatures, all off by default: tracker tags following you (AirTag, AirPods and other Find My items, SmartTag, Tile, Google Find Hub, Chipolo, Pebblebee, DULT-standard tags), floods of new tracker tag addresses, Flipper Zero, Wi-Fi deauth floods, floods of join requests at one access point, Wi-Fi beacon floods (one radio faking 15+ networks), directed probes, evil-twin and KARMA rogue access points, Pwnagotchi, Meshtastic and MeshCore mesh radios, Meta Ray-Ban / Oakley glasses, Axon / law-enforcement gear, Motorola Solutions radios and body cams, i-PRO body cams, police and fleet vehicle routers, security / doorbell / dash cameras by vendor OUI or camera brand in the network or device name (Ring, Nest, Arlo, Blink, Wyze, Hikvision, Dahua and others), Amazon Sidewalk BLE, wearable cameras and recorders (GoPro, Insta360, Snap Spectacles, Even Realities, Vuzix, Brilliant Labs Frame, PLAUD), vehicles (Teslas, Bluetooth OBD-II dongles), drones over Bluetooth (Remote ID, DJI) |
| **Flock BLE / Flock WiFi** | Flock Safety ALPR cameras, Raven gunshot sensors, Penguin and Pigvision. Optional OUI-only Wi-Fi hits |
| **Sky Spy** | Drones broadcasting FAA Remote ID over BLE and Wi-Fi: ID, position, altitude, speed, pilot position |
| **Foxhunter** | One target device. The board beeps faster as you get closer. The app's FIND IT view shows the signal and a ring that pulses faster, and the phone can buzz with it |
| **UniPwn** | Unitree robots by BLE name (`Go2_`, `G1_`, `H1_`, …) |
| **Wardrive** | Every Wi-Fi AP and BLE device, GPS-stamped, WiGLE CSV format. 2.4 GHz channels 1–14 by default; C5 boards add 5 GHz including DFS and, with the **802.15.4 (Zigbee, Thread)** switch, passive 802.15.4 receive on channels 11–26 (PAN ID, source address, beacon info, channel, LQI; receive only, never transmits) |
| **PCAP** | Raw 802.11, BLE advertising or (C5 boards) 802.15.4 frames to a Wireshark `.pcap` |
| **AXEOFF** | Axon gear only, on Bluetooth and Wi-Fi, passive. The board plays a tone when Axon gear appears, while it stays near, and when it leaves |
| **BLE Sniff** | Every Bluetooth LE advert as a live list, with filters and **RECORD PCAP**. Passive. Needs the board connected to the phone directly, or picked as the node on a manager |
| **FPV receiver** | Analog 5.8 GHz FPV video transmitters on 44 of the 48 standard channels. XIAO ESP32-C5 only. See [FPV receiver](#fpv-receiver) |

> [!IMPORTANT]
> The Flock OUI list comes from upstream FlockYou and matches Ubiquiti, Espressif and other common consumer parts. Check a hit with your own eyes before reporting it anywhere.

In SETTINGS → **Detection & Alerts** → **What to Watch For**, each type can **alert** (notification plus a map pin), **log only** (tap the bell to record it without notifying), or be off. **OUI-based detection is an optional setting.** **Alert threshold** at the top sets how strong a detector hit must be to notify. **More device types** adds everyday radios: wearables, health, audio, phones / PCs, home IoT, thermostats, access control, vehicles, ISP / routers, mesh, beacons, signage and other.

### Flock confidence

| Tier | Matched |
|---|---|
| **VERIFIED** | Bare-serial name + XUNTONG `0x09C8` manufacturer ID + TN serial |
| **HIGH** | One strong signal: Raven service UUID, Flock BLE name, or a Flock wildcard probe with the Flock IE signature |
| **SUSPECTED** | A listed OUI only, including a wildcard probe without the IE signature |

DETECTIONS → HISTORY can filter by tier. 

## Ways to run

| Mode | How | What you get |
|---|---|---|
| **App + board** | Phone app connected to an ESP32 board over Bluetooth | The board runs the engines. The app controls it, shows the feed and map, adds phone GPS, and saves PCAPs |
| **Standalone** | No phone; boards with a screen and buttons | Engines started from the buttons. T-Dongles log to microSD; M5Sticks beep and show hits on screen |
| **Mesh node** | Board runs under a MANAGER the phone connects to | The manager collects every node's hits; settings from the app reach all nodes |
| **Phone only** | No board; PHONE SCAN on | Wardrive, classify, alert and foxhunt with the phone's own radios. Android also detects drones by Remote ID |
| **Phone + USB radios** | Android, no board; plug in an RTL-SDR and/or a USB Wi-Fi adapter | SDR decodes 315 / 433 / 915 MHz and ADS-B. A USB Wi-Fi adapter scans Wi-Fi, and the MT7921AU also scans Bluetooth LE. Both run alongside the phone's radios |

- **Offline scan** (SETTINGS → NODE → OFFLINE SCAN): the board keeps scanning without the phone, even after a reboot, and uploads hits on reconnect. A directly connected board with a GPS module fix also wardrives, one row per device every 5 min, up to 1 MB. It stops after 60 s without a fix.
- **Private Bluetooth link:** after pairing, the board hides its name, changes its address every 5–15 min and refuses unknown phones. The paired phone reconnects on its own.
- **PIN:** a new board's PIN is 123456. The app asks you to set your own after the first pairing. Change it in SETTINGS → NODE → Firmware → **Bluetooth PIN**.
- **Pair another phone:** restart the board. It accepts one new phone in the 2 min after power-on. After updating an S3, C3 or older ESP32 board, forget it in your phone's Bluetooth settings and pair again.
- **JCMK node hub** (SETTINGS → NODE → JCMK NODE HUB): the board adds Wi-Fi networks from [Piglet](https://github.com/hamspiced/piglet) ESP-NOW nodes to your wardrive. Tap **Start hub**, power on a Piglet, and tap **Pair** under **Nearby nodes**. The hub board leaves the mesh while it runs. The wardrive radio picker can leave out any paired node.

## App

The app controls your boards, shows what they find, and can scan with the phone's own radios. It has four main screens.

| Screen | What it shows |
|---|---|
| **Home** | The session bar (targets, radio, START / PAUSE / STOP) and one card per engine. The status bar shows the link, GPS fix and node count. |
| **Detections** | LIVE lists every hit, with filter, sort, search and export. DEVICES lists classified devices. HISTORY is the stored log, with CSV export. ALERTS lists every alert, newest first. |
| **Map** | Choose targets (WiGLE / Flock / Drone / Detector) and radio (Wi-Fi / BLE / both), then tap START. Sessions save as WiGLE CSV, upload to [WiGLE](https://wigle.net) and [WDGWars](https://wdgwars.pl), and replay on the map. |
| **SETTINGS** | APP, SCANNING (TIMING & RE-LOG, CHANNELS & BAND, EXTERNAL ADAPTERS), DETECTION & ALERTS (WHAT TO WATCH FOR, NOTIFICATIONS, YOUR LISTS, THIS PHONE, PRIVACY), NODE (SOUND & LIGHTS, GPS SOURCE, FLOCK DETECTION, RADIO PRIVACY, OFFLINE SCAN, MESH, FIRMWARE, JCMK NODE HUB), DATA (ACCOUNTS, CAPTURE DATABASE, CAPTURES, EXPORT). |

Tap any hit to see what it is and why, and to foxhunt or map it. SHOW ALL maps every hit of that class.

The info button at the right end of the Detections tab row explains each tab and icon.

| Icon | What it does |
|---|---|
| **Two arrows** (Home) | Opens the Connect screen, with or without a board linked. |
| **Funnel** | Filters by engine, radio, node or class. |
| **Arrow** | Picks the sort order. TIME lists Wi-Fi first, then Bluetooth, newest first. Tap again to reverse. |
| **Layers** | Indents each Wi-Fi client under the network it uses. On LIVE and DEVICES. |
| **Shapes** (DEVICES) | Switches between class sections and one flat list. |
| **Clock** (LIVE) / **Antenna** (HISTORY) | Opens HISTORY / goes back to LIVE. |
| **Folder** (HISTORY) | Opens saved sessions. |
| **Three dots** | More actions for the tab, such as search, export and clear. |
| **Crossed arrows** on a row | The device uses a random MAC. |
| **Crossed-out eye** on a row | The network hides its name. |
| **Lock** on a row | The network security, such as WPA2. |
| **Walking person** on a row | A loud Bluetooth device that keeps moving with you. |

LIVE shows one row per network name. The row's details list every MAC that uses that name.

### Classification

Every device the app hears gets a class, such as tracker, camera, public safety & fleet, drone, glasses, hacking tool, router, or home & office.

- Class alerts are on by default.
- A Samsung SmartTag away from its owner keeps its path when its address changes. The **WITH YOU** filter still finds it.
- **Suggested signatures** (DEVICES → More) groups 3+ unclassified radios that share a name, service, vendor prefix or company. **SAVE** turns a group into your own signature, with an optional alert on new matches.
- **Signature sets** (SETTINGS → Detection & Alerts → Your Lists) adds the Fieldwatch stock catalog, Home Assistant's Bluetooth device list, or your own set from an https link or file (Fieldwatch JSON). A set adds only what the built-in catalog lacks. **Export** in My signatures shares yours as a set.

### Phone scan

The phone can scan with its own radios, with or without a board. Tap **USE THIS DEVICE** on Home or the Connect screen, or the phone icon in the status bar, to start it. It is off at launch.

- iPhone hits skip WiGLE CSV, because iOS hides MAC addresses.
- iOS also removes Apple's manufacturer data, so a nearby iPhone, AirPods or AirTag arrives as a blank advert. It shows as *Possibly Apple, hidden by iOS*.
- The iPhone app then connects to that device for a moment and checks its services (Find My, AirTag, iPhone notification service) to name the kind. It never connects to your own boards.

### Receive only

One switch in SETTINGS → Detection & Alerts → Privacy stops every scan from transmitting.

- **Boards:** each connected board stops Wi-Fi probe requests and Bluetooth scan requests. A manager passes this to its mesh nodes.
- **Android phone:** the phone only hears scans that other apps already run, so it finds far fewer devices. Wi-Fi shows the networks Android already knows instead of starting a scan.
- **iPhone:** the phone scan pauses, because iOS sends scan requests whenever an app scans.
- **Turned off:** connections to nearby devices and **Make it play a sound**.
- **Still on:** boards keep advertising so the phone can reach them, and mesh nodes keep talking to each other.

Turning it off puts each board back to its own setting.

### Watches and alerts

#### Watches

- **Seen at your stops** (HISTORY → More): radios heard at 2 or more of your stops in the last 7 days.
- **Trusted networks** (**Trust this network** on an access point): warns when a lookalike appears with weaker security, another maker, or far from home.
- **Cell and GPS watch** (Android, SETTINGS → Detection & Alerts → This Phone): warns on a drop to 2G or 3G, a new tower at a known place, or faked GPS.
- **Movement alerts** (off by default): a car following you (needs an RTL-SDR), an aircraft circling, a drone hovering near you, or a device moving between nodes.

#### Watchlist

- **Import and export:** CSV or JSON in SETTINGS → Detection & Alerts → Your Lists. CSV rows are `identifier,description,kind`.
- **Add a rule** (**+** on the watchlist): a MAC, maker prefix, name, company ID or data, service UUID, or Wi-Fi probe or beacon prefix. In name patterns, `#` is a hex digit, `?` any character and `*` any run.
- **Rule limits:** a board holds 50 MAC and prefix rules, 50 service UUIDs and 32 other rules.
- **Alert when a board hears it** (tap a Bluetooth device): adds it to every board's watchlist. **UNDO** takes it back.
- **Watched devices** alert with their own label and sound, even when muted.

#### Sounds and muting

- **Alert sounds:** pick or compose a melody for each alert type, and preview it on the board.
- **Repeat for a device** (Notifications): alerts again after the device goes 60 s unheard.
- **Node down / Node back:** alerts when a mesh node goes missing for 45 s, and when it returns.
- **Silence all** (ALERTS): stops every sound and notification until you turn it off. Alerts are still logged.
- **Mute alerts for this device** (the device's sheet): silences one device. It is still logged.

### Map layers and geofences

#### Map tools

- **Pins:** hold the map to drop one. Tap it to rename or remove it.
- **Measure:** tap the ruler, then tap points on the map.
- **Offline maps:** the download button saves the area in view, up to 3,000 tiles.
- **Triangulation** (off by default): place 3 or more nodes with **Place at my position**. The map then estimates where a device is, with an error ring.
- **MAPPED ALPRs:** marks a Flock hit `ON MAP` when OpenStreetMap lists a plate camera within 75 m.
- **WDG TERRITORY:** shows a linked account's WDGWars territory.

#### Drones

- **Drones list** (SKY SPY → history): every drone in a time window. Tap one for its tag, notes, flight map, pilot, FAA record and kit.
- **Remote ID or FPV:** chips that filter the Drones list.
- **Follow on map:** keeps a Remote ID drone centered as it moves.
- **Detection location:** a drone's flight shows where your phone was when it was first heard, and the range.
- **Tags:** mark a drone Friendly, Neutral, Suspicious or Hostile. The tag colors its marker.
- **Drone log:** Remote ID reports are kept 90 days. **Export logs** saves CSV or KML.
- **Drone kit:** link a drone's controller, goggles, pilot phone and other devices. The app suggests likely ones.

#### Zones

- **Geofences:** a **QUIET** zone hides detections and silences boards inside it.
- **Alert zones:** with **In your zone** on, the app alerts when a drone or caught device is inside an **ALERT** zone.

### Packet capture

The app saves Wi-Fi, BLE or 802.15.4 traffic as PCAP files that Wireshark opens.

- Start, pause and resume by hand, or let **Auto-PCAP** record 3–120 s when an engine fires.
- **802.15.4** and **5 GHz** need a C5 board.
- Saved captures are in SETTINGS → DATA → PCAPS.
- **PROBES** (top of the PCAP screen): the network names nearby phones ask for, by device or by network.

### 802.15.4 wardrive (C5 boards)

- The **802.15.4 (Zigbee, Thread)** switch under the radio picker works on C5 boards, and on a manager while a C5 node is live in the mesh. Only the C5 nodes listen on 802.15.4.
- The board listens for about 2.4 s of every 8 s, and pauses Wi-Fi and BLE meanwhile.
- Sightings show in lime in the feed and on the map, with PAN ID, address, channel and LQI.
- Receive only. Sightings go in the detections CSV, not in WiGLE exports.

### FPV receiver

On a XIAO ESP32-C5 the app finds analog 5.8 GHz FPV video transmitters. It receives only and shows no picture. Open it from the **FPV receiver** tile on HOME.

<table>
  <tr>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/ui/fpv-receiver.png" alt="FPV receiver locked on a transmitter on A8, 5725 MHz" /></td>
    <td width="50%" valign="top">
      <ol>
        <li><b>Status</b>: LOCKED, TUNED or the running mode, the channel, its level, coherence and noise floor, and how many channels are flagged.</li>
        <li><b>Proximity</b>: the needle moves toward CLOSE as the tuned channel rises above the floor.</li>
        <li><b>Channels</b>: brighter is stronger, a bolt marks a flagged transmitter, and tapping a cell holds that channel.</li>
      </ol></td>
  </tr>
</table>

- **Channels:** bands A, B, E, F, R and L. R8, E6, E7 and E8 are out of the C5's range, and L-band is experimental.
- **Modes:** **SCAN** stops on the strongest transmitter, **SWEEP** keeps the grid live, and **HOP** visits flagged channels. Tap a cell or use the arrows to hold a channel.
- **Flags:** a channel is flagged when it is 12 above the noise floor (the **Flag threshold**) with a steady carrier. Levels are relative, not dBm.
- **Bleed:** a transmitter also reaches channels within 19 MHz. Only the strongest one lights up.
- **Feed:** flagged channels show in Sky Spy, the Drones list and the feed, with no position.
- **Limits:** Wi-Fi engines pause while FPV runs. FPV won't start while the mesh or ESP-NOW hub is on, and isn't on the T-Dongle-C5 or manager builds.
- **Pins:** keep GPIO 1, 0, 23, 7, 10, 5, 3 and 4 unconnected.

### Lock screen and notifications

- **iOS:** live counts and alerts show on the Lock Screen and Dynamic Island during a session, and in CarPlay on iOS 26.
- **Android:** during a session, an ongoing notification shows live counts and the last alert.

### ATAK

The app sends catches and Remote ID drones to ATAK as Cursor-on-Target markers over UDP. Turn it on in SETTINGS → DATA → Export → **Send to ATAK**.

- **Where:** `127.0.0.1:4242` by default, ATAK on this phone. In ATAK, add a UDP input on that port.
- **What:** Remote ID drones with their pilots, and other catches at the phone's position. Wardrive rows are not sent.
- **SA multicast** (off by default): also sends to `239.2.3.1:6969`, readable by anyone on your Wi-Fi.

### Assistant

A language model can read what the app has seen and, when you allow it, change things. It is off by default. Turn it on in SETTINGS → DATA → **Assistant**, pick a model provider, then tap **Open the assistant**.

<table>
  <tr>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/ui/assistant-settings.png" alt="Assistant settings: model providers and the Automatic section, off by default" /></td>
    <td width="50%" valign="top">
      <ol>
        <li><b>Model provider</b>: Ollama on your network, or Claude, OpenAI or Gemini in the cloud.</li>
        <li><b>ⓘ</b>: what the automatic features send and when.</li>
        <li><b>Automatic</b>: alert lookups and scheduled reports. Both are off until you turn them on.</li>
      </ol></td>
  </tr>
</table>

- **Providers:** Ollama on your network, or Claude, OpenAI or Gemini. A cloud provider asks for your OK once. On Android, use https if **Check** fails on a LAN address.
- **API keys** stay in the phone's secure storage and go only to their provider.
- **ASK** is a chat that shows every tool the model runs. **Stop** cancels.
- **INTEL** explains one device. It never sees where the device was.
- **REPORTS** sums up the last 6 to 48 hours.
- **Grants:** DEVICES, DRONES, WARDRIVE, MESH, CAPTURES, LOCATION, CONTROL and IRREVERSIBLE are each off until you allow them. With LOCATION off, the model sees no positions.
- **Changes:** CONTROL can name devices, switch some engines, run captures and restart the board. IRREVERSIBLE can ask for a factory reset. Every board change waits for your OK.
- **Untrusted text:** device and network names reach the model as data, never as instructions.

### Home dashboard

The app can link to the [home dashboard](tools/home-dashboard/README.md) running on your computer. It is off by default. Turn it on in SETTINGS → DATA → Export → **Home dashboard**.

- **Address:** the dashboard's address, with a port if it is not 5077. Start the dashboard with `--lan`.
- **Find on this network** (off by default): finds a dashboard started with `--lan --advertise`.
- **Access token:** the one the dashboard printed. Kept in secure storage.
- **Link:** the connection state, such as **Live**, **Home down** or **Refused**.
- **Connectors:** turn **MQTT**, **TAK server**, **Reticulum** and **Meshtastic** on or off. Set them up on the dashboard.
- **Meshtastic settings:** the dashboard radio's port, channel, nodes and which events go out. **Send a test** sends one message.
- **History kept:** days of detections to keep (0 keeps all). **Clear detection history** asks twice.

### Meshtastic radio

Pair your own Meshtastic radio to send a message or your position by LoRa when you have no network. SETTINGS → DATA → **Meshtastic radio**.

<table>
  <tr>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/ui/meshtastic-radio-top.png" alt="Meshtastic radio: the paired radio, connect, change or forget, and the automatic alerts switch" />
      <ol>
        <li><b>This phone's radio</b>: link state and the paired radio's name.</li>
        <li><b>Connect</b>: links to the paired radio. Close the Meshtastic app first.</li>
        <li><b>Change radio / Forget this radio</b>: pick another radio or drop this one.</li>
        <li><b>Send alerts automatically</b>: off until you turn it on and confirm.</li>
      </ol></td>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/ui/meshtastic-radio.png" alt="Meshtastic radio settings: alert types, limits, today's count and destination" />
      <ol>
        <li><b>Alert types</b>: which alerts go out by LoRa when <b>Send alerts automatically</b> is on.</li>
        <li><b>Limits</b>: the shortest gap between two messages and the most messages a day.</li>
        <li><b>Sent today</b>: messages sent and alerts skipped by the limits.</li>
        <li><b>Send to</b>: the private channel, or up to 4 chosen nodes.</li>
      </ol></td>
  </tr>
</table>

- **Find a radio:** close the Meshtastic app first. The radio's default PIN is 123456.
- **Reconnect:** the app reconnects to the saved radio on its own.
- **Channel:** private channels only, never the public one.
- **Send a message** (up to 200 characters) or **Send my position** (asks first).
- **Heard on the radio:** recent messages on the private channel.
- **Automatic alerts:** each alert goes out as text with the device's address, never a position. Default limits are 60 s between messages and 50 a day.

### App updates

SETTINGS → About → **Check for update**. **Check at launch** is off by default.

- **Signed:** the app installs only a newer release signed with the firmware release key, and checks the file's SHA-256.
- **Android:** **Install** opens the system installer.
- **macOS:** **Save to Downloads**, then replace the app yourself.
- **iOS:** update through TestFlight.
- **Maintainers:** `python3 sign_ota.py release <apk> <macos zip>` writes the signed manifest. `python3 sign_ota.py verify-release <folder>` checks it.

## USB radios on Android

OUI-APEX drives a USB Wi-Fi adapter or RTL-SDR dongle with no root, kernel driver or custom ROM.

<div align="center">
<table>
  <tr>
    <td align="center"><img width="400" src="docs/screenshots/ui/setup.jpg" alt="Phone running OUI-APEX with an RTL-SDR and USB Wi-Fi adapter plugged in" /><br><sub>Settings → Scanning → External Adapters</sub></td>
  </tr>
</table>
</div>

- **Setup:** plug it in, choose OUI-APEX when Android asks, and tick "Use by default for this USB device". The app then reclaims it after a restart. It shows on Home with its own START control.

### Wi-Fi adapters

- **Receive only:** the adapter scans in monitor mode and never transmits.
- **Firmware:** first use needs internet to download the chipset firmware from [linux-firmware](https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git/).

| Chipset | Scans |
|---|---|
| MediaTek MT7921AU | Wi-Fi (2.4 + 5 GHz) and Bluetooth LE |
| MediaTek MT7612U | Wi-Fi (2.4 + 5 GHz) |
| **Realtek RTL8812AU (Recommended)**/ RTL8814AU | Wi-Fi (2.4 + 5 GHz) |
| Atheros AR9271 | Wi-Fi (2.4 GHz) |
| Ralink RT3070 | Wi-Fi (2.4 GHz) |

On the MT7921AU (Alfa AWUS036AXM), pick BLE or WiFi+BLE on the radio control to scan Bluetooth LE.

### RTL-SDR

Use an RTL2832U dongle with USB ID `0bda:2832` or `0bda:2838`. Open the SDR screen and pick a mode.

| Mode | Frequency | What it receives |
|---|---|---|
| Spectrum | You set it, 100.1 MHz by default | A live waterfall of signal strength across the band |
| ADS-B | 1090 MHz | Aircraft broadcasting their position and identity |
| SCAN | 315, 433.92, or 915 MHz | The device types you pick from what the rtl_433 decoders recognize: weather stations, utility meters (including Wireless M-Bus and Itron / Silver Spring smart-meter mesh), security sensors, remotes and key fobs, home sensors and tire-pressure sensors |

<table>
  <tr>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/tour/12-sdr-scan.png" alt="SDR SCAN with decoded devices" /></td>
    <td width="50%" valign="top">
      <ol>
        <li><b>Bands</b>: pick 315, 433 or 915 MHz, or several to sweep them, then tap START.</li>
        <li><b>Types</b>: tap a chip to turn that type on or off. Each chip counts what it found.</li>
        <li><b>Decoded devices</b>: newest first. Tap one for its details and to foxhunt it.</li>
      </ol></td>
  </tr>
</table>

- **Smart meters:** mesh hits show which meter talks to which and through which gateway. Readings are encrypted.
- **History:** decoded devices save under an SDR filter, and you can foxhunt them.
- **ADS-B:** each aircraft's callsign, altitude, speed and photo, with its flight path on the map. One button uploads them to WDGWars.

## Boards

| Board | Bands | Screen / buttons | microSD | Buzzer | Mesh node | Flasher target |
|---|---|---|---|---|---|---|
| XIAO ESP32-S3 | 2.4 GHz | – | – | GPIO3 (OUI-SPY board) | yes | `node-xiao_s3` |
| ESP32-S3 N16R8 DevKitC | 2.4 GHz | – | – | GPIO3 | yes | `node-s3_devkitc` |
| XIAO ESP32-C5 *(experimental)* | 2.4 + 5 GHz | – | – | GPIO25 | yes | `node-xiao_c5` |
| LilyGO T-Dongle-S3 | 2.4 GHz | LCD, 1 button, RGB LED | yes | none | yes | `node-tdongle_s3` |
| LilyGO T-Dongle-C5 *(experimental)* | 2.4 + 5 GHz | LCD, 1 button, RGB LED | yes | none | yes | `node-tdongle_c5` |
| M5StickC PLUS | 2.4 GHz | LCD, 3 buttons | – | built in | **no** | `node-stickc_plus` |
| M5StickC PLUS2 | 2.4 GHz | LCD, 3 buttons | – | built in | **no** | `node-stickc_plus2` |
| M5StickC (original) | 2.4 GHz | LCD, 3 buttons | – | none | **no** | `node-stickc` |

- **Manager boards:** XIAO ESP32-S3 (`mgr-xiao_s3`), ESP32-S3 DevKitC (`mgr-s3_devkitc`), XIAO ESP32-C5 (`mgr-xiao_c5`), XIAO ESP32-C3 (`mgr-xiao_c3`), ESP32 WROOM (`mgr-wroom`). A manager does no scanning.
- **Disabled, not hidden:** a control the connected board can't use stays visible, dimmed, with the reason.
- **No mesh:** the M5StickC, PLUS and PLUS2 skip mesh to fit their RAM. They connect straight to the phone or run standalone.

## Standalone controls

### T-Dongle-S3 / T-Dongle-C5

| Press | Action |
|---|---|
| 1 press | Select next mode |
| 2 presses | Start / stop selected mode |
| Hold | Open detections screen |
| Any press on detections screen | Back to main screen |

Modes: `DETECT FLOCKB FLOCKW FOXHNT SKYSPY UNIPWN WARDRV PCAP`.

Files go to `/OUISPY` on the card:

| File | Contents |
|---|---|
| `det_*.csv` | Every detection, with coordinates when a GPS fix exists |
| `wigle_*.csv` | Wardrive rows; written only with a GPS fix (phone or GPS module) |
| `cap_*.pcap` | Packet captures |

- **Filenames** use UTC time once GPS supplies it, otherwise a boot counter.
- **LED:** glows dim green while an engine runs, flashes the engine's color on a hit. The app's NeoPixel brightness slider sets the level; 0 turns it off.

### M5StickC / PLUS / PLUS2

| Button | Press | Action |
|---|---|---|
| **A** (front) | tap | Select next mode |
| **A** | double-tap | Detections screen on / off |
| **A** | hold | Foxhunt the last alert (or the app's target); hold again to stop |
| **B** (side) | tap | Start / stop selected mode |
| **B** | hold | Buzzer on / off (PLUS and PLUS2) |
| **PWR** | tap | Screen brightness, four steps, last is off |
| **PWR** | hold | Power off |

Modes: `DETECT FLOCKB FLOCKW FOXHNT SKYSPY UNIPWN`. Wardrive and PCAP need the app on these boards (no SD card).

### Main screen (both)

- **Top left:** selected mode (amber = selected, green = running).
- **Top right:** `APP` `MSH` `SD` `GPS` status.
- **Left:** unique Wi-Fi and BLE counts.
- **Right:** foxhunt target, `CAP` bytes while capturing, or speed.
- **Bottom strip:** one icon per mode, lit while running, underlined when selected, hit count below.

Foxhunt picks, in order: the target set in the app, else the last Detector / Flock / Sky Spy / UniPwn alert seen by this board.

Detector MAC, OUI and UUID targets, their labels, and signatures set in the app stay on the board through a reboot. Name targets match in the app only.

### Detections screen (both)

- **Rows:** the 4 latest detections, newest on top.
- **Each row:** engine icon, name (12 characters, MAC address if none), dBm, signal bars.
- **Header:** detections since boot.

## Mesh

### How it works

- One MANAGER connects to the phone; up to 6 NODES report to it over ESP-NOW on 2.4 GHz channel 1 until you move them (see **Channel**).
- Nodes join on their own within about 10 s. Single hop: every node must reach the manager directly, about 200 m line of sight.
- Default is plaintext broadcast. SETTINGS → NODE → MESH can switch to AES-256-GCM with a shared key.
- Boards use a random MAC each boot; the node ID stays fixed.
- A node silent for 45 s drops off and rejoins when back in range.
- The manager pushes buzzer, LED, alert, alert-sound, ignore-list, wardrive-radio and Wi-Fi-band settings to every node.
- Any mix of node boards works under one manager.

### Node watchlists

- **Presets** (SETTINGS → Detection & Alerts → Your Lists → Watchlist → **Presets**) are ten signature sets: Axon, Meta glasses, i-PRO, Verkada, Trackers, Drones, Vehicles, Wearables, Flipper and Police. Tap one for **WATCH ON PHONE** or **INSTALL ON NODES**. A node takes the rules it can hold, and the message counts the rest as skipped.
- **A node's filters** (a node in **Nodes** → **Filters**, through a manager) shows what one node watches for, and adds, removes, replaces or clears its rules. An edited node keeps its own list until the phone sends a new watchlist.
- **Watchlist results:** each node reports whether it took the watchlist, such as "On 3 of 4 nodes; NODE2 refused (list too long for it)".

### Fleet control

- **Read all** (SETTINGS → NODE → MESH → **Fleet control**) shows each node's build, filters, uptime and peers under **Nodes**.
- **Signal** (SETTINGS → NODE → MESH → **Signal**) shows how strongly each node hears each other node, one row per direction, updated about every 6 s.
- **Channel** (SETTINGS → NODE → MESH → **Channel**) moves the whole mesh to channel 1 to 11. Every node confirms first, then all switch together without a reboot. If a node does not answer within 15 s, nothing moves unless you tap **Move anyway**. Update older nodes first.
- **Finding the fleet again:** a node that hears no manager for 2 minutes scans channels 1 to 11 to find it, then retries every 15 minutes.
- **Fleet metrics** (SETTINGS → NODE → MESH → **Fleet control**) shows each node's build, uptime, peers and temperature, then the last hour, day, week or month of logged activity in three views: **Detections**, **Wardrive** and **Drones**.

<table>
  <tr>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/ui/mesh-channel.png" alt="Mesh channel: the current channel and the move control" />
      <ol>
        <li><b>Channel ⓘ</b>: how a move works.</li>
        <li><b>Channel now</b>: the mesh's current channel.</li>
        <li><b>Picker</b>: the channel to move to, 1 to 11.</li>
        <li><b>Move fleet</b>: asks every node to confirm, then all switch together.</li>
      </ol></td>
    <td width="50%" valign="top"><img width="300" src="docs/screenshots/ui/fleet-metrics.png" alt="Fleet metrics, Detections view: totals and detections over time" />
      <ol>
        <li><b>Totals</b>: detections, change against the span before, unique and new devices, active nodes and the busiest period.</li>
        <li><b>BLE / Wi-Fi</b>: unique devices on each radio.</li>
        <li><b>Over time</b>: detections per period in the chosen span.</li>
      </ol></td>
  </tr>
</table>

### Firmware updates

- **Over Wi-Fi** (SETTINGS → NODE → FIRMWARE): each node downloads its own board's image. Nodes older than v0.6.1 get the board picked in the app.
- **Over the mesh** (SETTINGS → NODE → MESH → **Fleet control**, or SETTINGS → NODE → FIRMWARE): updates the nodes you tick with no Wi-Fi. Load a node build as a `.bin` file or from a link. The app checks the image, the chip and the signature before sending. Nodes update one at a time, each row shows its progress, and **STOP** cancels. Needs a manager on firmware with this feature.

## Home dashboard

`tools/home-dashboard/` is a web page that runs on your computer and shows the mesh from a board plugged in by USB: the nodes, their signal to each other, a map, drones, and a searchable detection history. It can read a node's status, make a node beep and flash, and reboot a node. Filters, presets and firmware stay in the app.

- Listens on `127.0.0.1` only. `--lan` lets other devices in, and then every one of them needs the access token. Only the token's hash is kept.
- Nothing starts by itself, and nothing goes online unless you turn on a map layer, a TAK server, Reticulum or an optional download.
- **TAK server** and **Reticulum** links and **MQTT** are set on the dashboard. The app turns them on and off (SETTINGS → DATA → **Home dashboard**).
- **Meshtastic:** sends alerts through a Meshtastic radio on the dashboard computer, at most one a minute per event type. Off until you turn it on.
- Run it with `python3 ouispymesh.py` from that folder. See [its README](tools/home-dashboard/README.md).

## Optional GPS module

A serial GPS (NEO-6M / NEO-8M, 9600 baud) gives the board its own position. Its fix overrides phone GPS. After 5 s with no module data, the board uses phone GPS.

| GPS | XIAO ESP32-S3 | T-Dongle-S3 | T-Dongle-C5 | M5Stick |
|---|---|---|---|---|
| TX → | GPIO44 | GPIO44 | GPIO12 | GPIO33 |
| RX ← | GPIO43 | GPIO43 | GPIO11 | GPIO32 |

Other boards: set `-DPIN_GPS_RX=` / `-DPIN_GPS_TX=`.

## Privacy

These settings limit what the boards and the phone send over the air and what the app shows on screen.

- **Receive only** (SETTINGS → Detection & Alerts → Privacy): one switch for every scan. See [Receive only](#receive-only).
- **Board radio privacy** (SETTINGS → NODE → RADIO PRIVACY): **Active Wi-Fi probing** is off by default and uses a random MAC when on. **Passive Bluetooth scanning** stops scan requests.
- **Private Bluetooth link:** the board's address rotates, and after pairing it hides its name. See [Ways to run](#ways-to-run).
- **Random MAC each boot** for the board's Wi-Fi and mesh.
- **Mesh encryption** (AES-256-GCM) is off by default. See [Mesh](#mesh).
- **Mask identifiers on screen** (SETTINGS → Detection & Alerts → Privacy): hides most of each MAC and name on screen. Exports keep full values.
- **No analytics or crash reporting.** See [Internet services](#internet-services).
- **Tested:** the Bluetooth address checks passed on a XIAO ESP32-S3 on 2026-11-13. Wi-Fi probe and mesh MACs are not yet checked with an outside receiver.

## Internet services

- **No analytics or crash reporting.**
- The app connects to a service below only when you use its feature.
- Detections, sessions and captures stay on the phone until you upload or export them.

| Service | When the app connects | What it sends | Usage rules the app follows |
|---|---|---|---|
| Home dashboard on your computer | You turn on **Home dashboard** (Settings → Data → Export) | Plain HTTP requests to the address you set, every 10 s while that screen is open. Carries the access token if you saved one. | UA `OUI-APEX-app`. No address, no requests. With **Find on this network** on, also one multicast DNS question for `_ouispy._tcp`. |
| [WiGLE](https://api.wigle.net) | Sign in or upload a session | API name + token; session file on upload | On HTTP 429, pauses WiGLE 24h. Each session uploads once, on confirm. |
| [WDGWars](https://wdgwars.pl) | Link an account, upload a session, or turn on **WDG TERRITORY** | API key; compressed session file; territory requests | UA `oui-spy-companion/1.0`. Retries an upload twice (2s, 8s) on dropped connection or server error. Honors the server's rate-limit wait. Territory refreshes at most every 5 min. |
| [Overpass API](https://wiki.openstreetmap.org/wiki/Overpass_API) (`overpass-api.de`, fallback `overpass.private.coffee`) | **MAPPED ALPRs** on (off by default) and you move the map or open a Flock hit | The map corners in view | UA `oui-spy-companion/1.0`. Caches areas 7 days, one request at a time. On HTTP 429 waits 30s or longer. |
| [OpenFreeMap](https://openfreemap.org) styles: Dark (default), Fiord, Liberty, Bright, Positron | A map is on screen | Tile numbers in view | No account or key, no limit. Tiles cached 30 days (≤50 MB). Shows "OpenFreeMap © OpenMapTiles Data from OpenStreetMap". |
| [USGS The National Map](https://www.usgs.gov/faqs/what-are-terms-uselicensing-map-services-and-data-national-map): Satellite (US) | You pick Satellite (US) | Tile numbers in view | Public domain, no account. US only. Tiles cached 7 days (≤200 MB). Enlarges zoom-16 tiles past zoom 16. Shows USGS credit. |
| [GitHub](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) | You tap **Check for Update** (Settings → Node → Firmware) | Nothing about you or your board | UA `oui-spy-companion/1.0`. 60 checks/hour per IP; pauses to GitHub's reset. Firmware comes from the same release. |
| [GitHub](https://github.com/lukeswitz/oui-spy-unified-blue/releases) releases | You tap **Check for update** or turn on **Check at launch** (Settings → About) | Nothing about you or your phone | UA `oui-spy-companion/1.0`. Downloads `release.json` and its signature, and the app file only when you tap **Install** or **Save to Downloads**. Off by default; no background checks. |
| Signature sets: [Fieldwatch](https://github.com/OffGridPete/Fieldwatch), [Home Assistant](https://github.com/home-assistant/core), or a link you add | You turn a set on or tap **Update** (Settings → Detection & Alerts → Your Lists → Signature sets) | Nothing | UA `oui-spy-companion/1.0`. https only, 8 MB limit. No background checks. |
| [Wireshark](https://www.wireshark.org/download/automated/data/) | You tap **Check for Update** (Settings → Data → Export → **OUI database**) | Nothing | Downloads Wireshark's MAC vendor list (`manuf.gz`). Limited to once every 7 days. UA `oui-spy-companion/1.0`. |
| Assistant providers: [Anthropic](https://api.anthropic.com), [OpenAI](https://api.openai.com), [Google](https://generativelanguage.googleapis.com), or your own Ollama server | **Assistant** is on, you picked that provider and OK'd it, and you ask, look into a device, write a report or tap **Check** | Your question and what the model reads within the grants (device names and MACs, alerts and so on; positions only with LOCATION); the API key in a header | No background requests. Keys stay in secure storage. Ollama requests go only to the address you set. |
| [FAA DroneZone](https://uasdoc.faa.gov) | You tap **FAA RemoteID Lookup** or **FAA lookup** on a drone | The drone's Remote ID serial | UA `oui-spy-companion/1.0`. Caches a registration 30 days. Retries only on HTTP 502, up to 3×. |

## Build

```bash
pio run -e v3_app_controlled                 # node, XIAO ESP32-S3
pio run -e v3_app_controlled_tdongle_s3      # node, T-Dongle-S3
pio run -e v3_app_controlled_stickc_plus     # node, M5StickC PLUS (also _stickc, _stickc_plus2)
./build_c5.sh                                # node, XIAO ESP32-C5
OUISPY_C5_ENV=v3_app_controlled_tdongle_c5 ./build_c5.sh   # node, T-Dongle-C5
pio run -e v3_node_manager_s3                # manager, XIAO ESP32-S3 (also _s3_devkitc, _xiao_c3, _wroom)
OUISPY_C5_ENV=v3_node_manager_c5 ./build_c5.sh             # manager, XIAO ESP32-C5
```

C5 builds use the pioarduino platform in a separate core dir (`~/.platformio-c5`) via `build_c5.sh`.

```bash
cd companion && flutter pub get && flutter build apk --release   # or ipa / macos
```

Over-the-air updates must be signed with the release key. A board flashed over USB takes any image.

## Credits

> Runs the [OUI-SPY ecosystem](https://github.com/colonelpanichacks) by colonelpanichacks with additional features.
>
> **Not affiliated with OUI-SPY.**

### Code and techniques

- Upstream engines: [Detector](https://github.com/colonelpanichacks/ouispy-detector), [Foxhunter](https://github.com/colonelpanichacks/ouispy-foxhunter), [Flock You](https://github.com/colonelpanichacks/flock-you), [Sky-Spy](https://github.com/colonelpanichacks/Sky-Spy), [UniPwn](https://github.com/colonelpanichacks/Oui-Spy-UniPwn) by **colonelpanichacks**.
- **colonelpanichacks** (Colonel Panic, MIT): `tools/home-dashboard/` is adapted from the `home-dashboard` folder of [ouispy-detector](https://github.com/colonelpanichacks/ouispy-detector). Details in [companion/NOTICE](companion/NOTICE).
- **Meshtastic** ([protobufs](https://github.com/meshtastic/protobufs), GPL-3.0): the Meshtastic radio link uses the Bluetooth UUIDs and message field numbers from the Meshtastic protocol. No Meshtastic code is included. Details in [companion/NOTICE](companion/NOTICE).
- **colonelpanichacks** ([OUI SPY Unified Blue](https://github.com/colonelpanichacks/oui-spy-unified-blue), MIT): the AXEOFF and BLE Sniff engines port its Axon signatures, advert filter bits and link-layer frame layout. Details in [companion/NOTICE](companion/NOTICE).
- **Will Greenberg** ([flock-you](https://github.com/wgreenberg/flock-you)): XUNTONG `0x09C8` detection.
- **@NitekryDPaul / OrdoOuroborous** ([@nitekry](https://github.com/nitekry)): promiscuous Flock OUI set and the addr1 receiver technique.
- **DeFlockJoplin** ([flock-you](https://github.com/DeflockJoplin/flock-you)): wildcard-probe signature.
- **OffGridPete** ([Fieldwatch](https://github.com/OffGridPete/Fieldwatch), MIT): the app's signature catalog starts from Fieldwatch catalog 92. The advertisement decoder, device explanations, signature engine, field decoder, pairing-flood and co-travel code are Dart ports of Fieldwatch. Details in [companion/NOTICE](companion/NOTICE).
- **Twotoz** ([C5VRX](https://github.com/Twotoz/C5VRX), GPL-3.0): the FPV receiver uses its published technique for tuning the C5 and reading the receiver data. We wrote our own code. Details in [companion/NOTICE](companion/NOTICE).

### Data and libraries

- Catalog entries from [Home Assistant](https://github.com/home-assistant/core) Bluetooth matchers, the [buttplug.io](https://github.com/buttplugio/buttplug) device config, and [Theengs Decoder](https://github.com/theengs/decoder) device identifiers.
- Fast Pair model names: the [WhisperPair](https://github.com/KULeuven-COSIC/WhisperPair) model list by KU Leuven COSIC (CC BY 4.0).
- Company and service IDs: [Bluetooth SIG assigned numbers](https://bitbucket.org/bluetooth-SIG/public).
- OUI sources: [zmattmanz](https://github.com/zmattmanz), [dougborg/AirHound](https://github.com/dougborg), [VirtuallyScott](https://github.com/VirtuallyScott).
- Vendor OUIs: IEEE MA-L, MA-M and MA-S registries via [Wireshark manuf](https://www.wireshark.org/download/automated/data/manuf.gz).
- Firmware libraries: [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino), [TinyGPS++](https://github.com/mikalhart/TinyGPSPlus), [Adafruit GFX](https://github.com/adafruit/Adafruit-GFX-Library); ESP-IDF ESP-NOW and mbedTLS.
- Map tiles: [OpenFreeMap](https://openfreemap.org/) with [OpenMapTiles](https://openmaptiles.org/) and [OpenStreetMap](https://www.openstreetmap.org/copyright) data; satellite imagery from [USGS The National Map](https://www.usgs.gov/programs/national-geospatial-program/national-map).

## Disclaimer

OUI-APEX is for security research, privacy auditing and education only. By using it, you agree to the following.

- **Your risk:** you use it at your own risk, and you alone are responsible for how you use it.
- **No warranty:** the firmware, the app and the flasher are provided "as is", without warranty of any kind. See [LICENSE](LICENSE).
- **No liability:** the authors and contributors are not liable for any damage or loss from their use, including a board that no longer boots after a flash.
- **Follow the law:** laws on radio monitoring, recording and tracking differ by country and state. Check yours before you scan. Don't use it to track people without their consent, or to get into networks or devices you don't own.

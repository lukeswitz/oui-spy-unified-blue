# Warble (Wardrive Go) parity audit + porting TODO

Living work list. Goal: bring OUI-APEX to parity with the Wardrive Go / "Warble"
Android app (pkg `com.rocketgod.warble`, GPL) on everything it does better, and pass it
where we can. Negative-regression task: while porting each item, fix the reference app's
own bugs and improve on it, never cut corners.

Method / licensing: Warble is GPL; ours is all-rights-reserved. Never copy Warble source
into this repo. Reimplement behavior from permissive upstreams (mt76 BSD, rtw88
GPL-2.0-OR-BSD, ath9k ISC, rt2800 for Ralink), public specs (hashcat 22000, WiGLE CSV
1.6, 802.11), and public data (Wireshark OUI, BT SIG). Warble is read-only reference for
*what* and *how well*, not a code source. Clone lived at scratchpad/wg.

Legend: `[ ]` todo · `[x]` done · `[~]` ours already does / ours ahead · (S/M/L) effort.

---

## A. Where each app leads today

Ours already ahead of Warble (keep, do not regress):
- ESP32 hardware ecosystem: BLE + USB-serial link to the board, mesh + fleet, OTA
  (BLE DFU + WiFi), offline LittleFS spool while phone away.
- Engines Warble has no concept of: Foxhunter, SkySpy/drone-RID (ODID + FAA lookup),
  UniPwn (Unitree), Detector watchlist + signature-bit mask, Flock BLE/WiFi.
- Classification depth: signature engine with 305-fleet catalog, co-travel/tracker
  detection, pairing-flood + WiFi-beacon-flood detection, presence classes, kin index,
  device-explain confidence. Warble uses flat hardcoded tables.
- DeFlock ALPR map layer (Overpass/OSM), WDGWars territory overlay, geofence editor,
  vector map tiles with 6 styles, iOS Live Activity.

Warble ahead of ours (the porting surface — section C):
- USB-adapter capture: client stations, PMKID + 4-way handshake, PCAP of real frames.
- RTL adapters that actually work (register-only, no firmware) + Ralink RT3070/5370.
- Cell-tower scanning, GNSS satellite detail, WiFi RTT ranging.
- Spectrum + channel analyzer tools.
- Upload hygiene: per-service dedup, WiGLE mine-sync, privacy/exclusion zones, `_nomap`.
- Background-scan foreground service, start-on-boot.
- Surfaces: Android Auto, Wear OS, home-screen widgets.
- Run-based gamification: achievements, milestones, rate/min.

---

## B. Parity matrix

| Capability | Warble | Ours | Action |
|---|---|---|---|
| MT7612U monitor (dual-band) | yes | yes (HW-proven) | done |
| Fast camp-on-active channel hop | yes | yes (ported this session) | done |
| RTL8814AU / 8821AU monitor | register-only, works | fw-download, UNVERIFIED | C1 (rewrite register-only) |
| RTL8812AU monitor | dead stub | fw-download, UNVERIFIED | C1 |
| Ralink RT3070/5370 monitor | yes | none | C2 |
| AR9271 monitor | yes | yes, UNVERIFIED | C-verify |
| Client-station capture | yes (all frame types) | AP-only | C3 |
| PMKID + handshake export | yes | none | C4 |
| PCAP of adapter frames | yes (SAF) | node-only | C5 |
| Multiple adapters at once | NO (single, priority) | single | D1 (net-new) |
| RTL-SDR / HackRF | NO | none | D2 (net-new) |
| Cell-tower scan + detail | yes | none | C6 |
| GNSS satellite view + LNAV decode | yes | none | C7 |
| WiFi RTT (11mc/az) ranging | yes | none | C8 |
| Spectrum analyzer | yes | none | C9 |
| Channel analyzer | yes | none | C9 |
| Fox-hunt locator (haptic cadence) | yes | Foxhunter gauge | C10 (enhance) |
| Privacy/exclusion zones + `_nomap` | yes | geofence+ignore (partial) | C11 |
| Randomized-MAC upload drop | yes | ? verify | C11 |
| WiGLE mine-sync dedup | yes | upload only | C12 |
| Per-service dedup (in_wigle/in_wdgw) | yes | ? verify | C12 |
| Background-scan foreground service | yes | manifest perms only | C13 |
| Start-on-boot | yes | none | C13 |
| Android Auto | yes | none | C14 |
| Wear OS (tile/complication/app) | yes | none | C15 |
| Home-screen widgets | 5 | none | C16 |
| Leaderboard gamification | yes | stats only | C17 |
| In-app diagnostics log viewer | yes | file only | C18 |
| Notable-device data points | rich | mostly covered | C19 (fill data gaps) |
| App-layer "radio dead" watchdog | yes (bounded re-init) | driver re-arm only | C20 |
| WiGLE CSV 1.6 export/import | yes | yes | ~ |
| WiGLE API upload/search/stats | yes | upload+stats | C12 |
| WDGWars upload + leaderboard | yes | upload, UNVERIFIED | ~/verify |

---

## C. Ranked porting TODO

### P0 — capture capability (what "capture everything the ESP32 does" means)

- [x] **MT7612U fast scan** — camp on `phone-scan union seen` channels, skip empty 5 GHz,
  drop the blind 38-ch re-sweep. Ported from Warble's `UsbBeast.nextHop`/`campBusy`.
  Built + installed; HW-verify pending.
- [x] **MT7612U RX re-arm on total starvation** — `reKickRx` now fires on `bufs==0`, not
  only on channel-busy. Fixes dead RX after warm re-init / app restart. HW-verify pending.
- [x] **C3 — client-station capture (MT7612U)** — parseRx now harvests client MACs from
  probe-req / assoc / data (ToDS/FromDS) / control frames in addition to AP BSSIDs;
  clients marked `client=true` end-to-end (Kotlin ApSighting → Dart WifiAdapterAp →
  addPhoneWifiDetection `method='wifi_client'`). Good-FCS-only for clients (no phantoms),
  multicast prefixes dropped. Done along the way (C11 slice): `wifi_client` rows are
  excluded from WiGLE CSV export, so client MACs are not uploaded. Built + installed;
  HW-unverified. Still per-MT7612U — folds into the shared RX core for the other chips.
- [ ] **C4 — PMKID + 4-way handshake capture (L)** — passive EAPOL harvest from monitor
  frames into hashcat-22000 lines, with an export screen (copy/save/share + per-OS crack
  commands) and a capture banner. Public spec, no GPL copy. Gate on good-FCS only. New DB
  table for captures. (Mechanics: read the 802.11 EAPOL-key + RSN-PMKID layout from a
  public reference; do not transcribe Warble's file.)
- [ ] **C5 — PCAP export of adapter frames (M)** — write captured 802.11 frames to file
  via SAF, per capture session. We have a node-side PCAP pipeline; add an adapter-frame
  writer + share.
  Improve on Warble: Warble's writer is classic pcap, linktype 105, no radiotap,
  synthesized 1 ms-step timestamps, and only the AR9271 path feeds it. Ours should emit a
  radiotap header (real per-packet RSSI/channel/rate), real capture timestamps, and cover
  every adapter, not just one.

### P1 — adapters that actually work (the "all RTL / Alfa devices" ask)

- [ ] **C1 — RTL8814AU / 8821AU / 8812AU register-only rewrite (L)** — Warble drives these
  with NO firmware upload: PWR_ON/MAC/PHY/AGC/RADIO_A register tables + `channelTune()`,
  pure register I/O. Ours is rtw88-derived and downloads firmware (the unverified
  divergence). Rewrite ours register-only from rtw88's non-fw init path + the vendor
  PHY tables, matching Warble's working approach. Resolves the long-standing RTL gap.
  Improve: 8821AU is dual-band silicon but Warble locks it to 2.4 GHz only — give ours
  real 5 GHz. 8814AU: Warble can't lock its 5 GHz channels (keyed `vid==0x0e8d` only) —
  make channel-lock chip-agnostic.
- [ ] **C2 — Ralink RT3070/RT5370/RT5372 (M)** — common cheap Alfa/Panda 2.4 GHz monitor
  NIC (148f:3070/5370/5372). Upload `rt2870.bin` (CSR 64B chunks, autorun-resident skip)
  per rt2800usb; register-table init; RX parse shared with the others. Warble has it;
  we don't.
- [ ] **C-verify — AR9271 on hardware (S)** — ours exists but UNVERIFIED (6 `unverified:`
  marks). ath9k_htc firmware upload + RX. Bench against a real AWUS036NHA / TL-WN722N v1.
- [ ] **Shared RX core (M)** — one 802.11 parse + sighting table + camp-busy hop loop used
  by every adapter driver, so client-capture / PMKID / PCAP / fast-scan land once, not
  per-chip. Make it INSTANCE-based (not Kotlin `object` globals like Warble) so D1
  multi-adapter is possible. Refactor with no per-chip behavior loss.

### P2 — sensors Warble has and we don't

- [ ] **C6 — cell-tower scan + detail (M)** — `requestCellInfoUpdate`, LTE/NR/GSM/WCDMA
  identity (MCC/MNC/CID/PCI/TAC/ARFCN/band) + signal (dBm/RSRP/RSRQ/SINR/TA), log best,
  detail screen, WiGLE CSV cell rows. Pure Android telephony API.
- [ ] **C7 — GNSS satellite view + L1 C/A LNAV decode (M)** — `GnssStatus` per-SV
  (constellation, CN0, el/az, used-in-fix) + optional `GnssNavigationMessage` raw subframe
  decode (health, URA, anti-spoof, SV config, leap seconds). Satellite list + detail.
- [ ] **C8 — WiFi RTT ranging (S)** — range 802.11mc/az responders found in phone scans,
  show per-device distance. `WifiRttManager`, API 28+.
- [ ] **C9 — spectrum + channel analyzer (M)** — spectrum: per-band Bezier arches at
  centerFreq with real channel width, RSSI height, collision-avoiding SSID labels.
  channel: AP-count bars per channel, busiest highlighted. From phone + adapter APs.

### P2 — upload hygiene + privacy (correctness, do before more uploads)

- [ ] **C11 — privacy/exclusion zones + upload filtering (M)** — drop randomized
  (locally-administered) MACs from upload, SSIDs ending `_nomap`/`_optout`, WiFi clients,
  blocked devices, and rows inside user exclusion zones. We have geofence exclude +
  ignore list (partial); add the `_nomap`/randomized-MAC/per-device-shield pieces.
  Section-5 note: this only tightens what leaves the device — no exposure widened.
- [ ] **C12 — WiGLE mine-sync dedup + per-service flags (M)** — stream `/network/mine`
  BSSIDs into a local dedup index, flip matching rows to in_wigle; separate in_wigle /
  in_wdgw flags so each service uploads only what it lacks; paged gzip streamed upload.
  Verify ours doesn't already do parts of this before building.
- [ ] **C10 — fox-hunt locator haptic cadence (S)** — our Foxhunter has the RSSI gauge;
  add Warble's distance buckets + vibration-rate-tied-to-signal + trend readout.

### P3 — surfaces + engagement (large, lower urgency)

- [ ] **C13 — background-scan foreground service + start-on-boot (M)** — real
  `FOREGROUND_SERVICE_LOCATION` service so phone-side scanning survives backgrounding;
  boot receiver (opt-in). Manifest perms already declared; no implementation today.
- [ ] **C14 — Android Auto map (L)** — NavigationTemplate map with coverage + offensive/
  PMKID markers, layer toggles.
- [ ] **C15 — Wear OS (L)** — stats push over DataClient, tile, complication, app.
- [ ] **C16 — home-screen widgets (M)** — stats / all-time / banner / offensive / list,
  one shared publish loop.
- [ ] **C17 — run gamification (S)** — achievements, run milestones, density banners,
  new/min rate feeding banner.
- [ ] **C18 — in-app diagnostics viewer (S)** — we log to `oui_spy.log`; add a viewer
  with copy/save/share.
  Improve: adopt Warble's head-preserving log ring (keep the first ~1500 bring-up lines
  under heavy RX volume instead of a plain FIFO that overwrites the useful init trace).
- [ ] **C19 — notable-device data gaps (S)** — fold any Warble data points ours lacks into
  our signature catalog (verify first): Flock BLE company `0x09C8`, 32-OUI Flock
  wildcard-probe list, Flipper service-UUID color `3081/3082/3083`, ALPR vendor OUIs
  (Genetec/Neology/Gatso/Jenoptik/Redflex), Meta-glasses UUID set, Apple `0x12` + FMDN
  `0x40/0x41` tracker bits, Pineapple/deauther name rules, Meta-Quest exclusion. Data
  only (public), no GPL code.
- [ ] **C20 — app-layer "radio dead" watchdog (S)** — Warble's `armRxWatchdog`: after
  bring-up, wait ~15 s, check a real frame actually arrived (`lastFrameMs` advanced); if
  not, re-init the adapter, bounded to ~2 attempts. Catches "enumerated fine, radio dead"
  (our exact second-run symptom) above the driver-level `reKickRx`. Layer this over the
  controller so it covers every chip, not just MT7612U.

---

## D. Net-new beyond Warble (user asked; Warble does NOT do these)

- [ ] **D1 — multiple adapters at once, incl. via USB hub (L)** — Warble is single-adapter
  (priority-picked, global `object` state). Ours must run N adapter workers concurrently
  (per-device thread + connection, no shared mutable singletons) and merge all sightings
  into the one pipeline. Requires the instance-based shared RX core (P1). This is where
  we beat the reference.
- [ ] **D2 — SDR: RTL-SDR, HackRF (L, research)** — neither in Warble. RTL-SDR via
  librtlsdr (GPL-2.0) as an isolated optional module; HackRF via libhackrf. Spectrum/IQ,
  not 802.11 monitor. Confirm licensing boundary + deployment with operator before build
  (flagged GPL-only in memory). Scope separately.

---

## E. Done this session
- MT7612U fast camp-on-active scan.
- MT7612U RX re-arm on starvation (dead second-run fix).
- Release auto-start: USB attach → auto-start, detach → stop (commit 314d470).
The two capture fixes are built + installed on the Pixel 7a; HW-verification of the
fast-scan + restart-recovery is still pending a run.

## F. Execution order (proposed)
1. Verify the two shipped MT7612U fixes on hardware; commit if good.
2. C3 client capture + C19 data gaps + C20 watchdog (fast count win + robustness, low risk).
3. Instance-based shared RX core → C1 RTL register-only → C2 Ralink (all Alfa adapters work).
4. C4 PMKID/handshake + C5 PCAP (offensive capture).
5. D1 multi-adapter (built on the instance-based RX core).
6. C11/C12 upload hygiene; C6/C7/C8 sensors; C9 analyzers.
7. P3 surfaces; D2 SDR (separate scope).

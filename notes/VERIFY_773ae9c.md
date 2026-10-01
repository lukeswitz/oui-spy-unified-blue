# Hardware verification — commit 773ae9c

Flash every board from this commit. Rebuild the app in Xcode / Android (real recompile, not a ~7 s cached build). Pass = the observation in the last column; capture serial where listed.

## 1. Flash + boot (all boards)

- [ ] XIAO ESP32-S3 node boots, app connects, CONFIG → FIRMWARE Board = XIAO ESP32-S3
- [ ] ESP32-S3 DevKitC node: same, Board = ESP32-S3 DevKitC
- [ ] XIAO ESP32-C5 node: same, Board = XIAO ESP32-C5
- [ ] T-Dongle-S3: same, Board = LilyGO T-Dongle-S3
- [ ] T-Dongle-C5: same, Board = LilyGO T-Dongle-C5
- [ ] M5StickC: same, Board = M5StickC
- [ ] M5StickC PLUS: same, Board = M5StickC PLUS
- [ ] M5StickC PLUS2: same, Board = M5StickC PLUS2
- [ ] Web flasher on each M5Stick: board reboots into new firmware after flash with no replug (RTS reset)
- [ ] Managers boot and accept the app: XIAO S3, DevKitC, XIAO C3, WROOM

## 2. Buzzer capability

- [ ] T-Dongle-S3, T-Dongle-C5, M5StickC: CONFIG → HARDWARE shows no AUDIO section; serial `[HW] Config: buzzer=0`
- [ ] M5StickC PLUS / PLUS2: AUDIO section present; detection plays chime; app toggle off silences it
- [ ] M5StickC PLUS / PLUS2: hold B 0.8 s toggles buzzer (serial `[DONGLE] buzzer off/on`), survives reboot
- [ ] M5StickC: hold B does nothing; tap B still starts/stops
- [ ] XIAO S3 (OUI-SPY board): chime still plays (regression check)

## 3. Standalone (no phone connected)

T-Dongle-S3 and T-Dongle-C5, card inserted:
- [ ] Strip shows 8 icons, none clipped at right edge: DETECT FLOCKB FLOCKW FOXHNT SKYSPY UNIPWN WARDRV PCAP
- [ ] 1 press cycles, 2 presses starts/stops each mode
- [ ] WARDRV runs; `/OUISPY/det_*.csv` gains rows; with GPS module fix `wigle_*.csv` gains rows
- [ ] PCAP runs; `/OUISPY/cap_*.pcap` opens in Wireshark
- [ ] Detector/Flock hit writes a `det_*.csv` row and flashes the LED

M5StickC / PLUS / PLUS2:
- [ ] Strip shows 6 icons, no WARDRV
- [ ] A tap cycles, B tap starts/stops each mode
- [ ] Hold A arms foxhunt on last alert; hold A again stops
- [ ] PLUS/PLUS2 beep on a detection with no phone
- [ ] PWR tap steps brightness; PWR hold powers off
- [ ] Growing device count does not reset the board (setMaxResults fix): run DETECT 60+ min in a busy area, serial shows no reboot, heap flat

## 4. App-controlled (phone connected directly)

Each of the 8 node boards:
- [ ] Every engine card starts and stops from HOME; feed shows hits
- [ ] Wardrive session saves and exports WiGLE CSV
- [ ] PCAP from app produces a file (M5StickC family: confirm start or clear failure message)
- [ ] Direct OTA from CONFIG → FIRMWARE picks the right image for the board and reboots on the new version

## 5. Node mode (under a manager)

Mixed fleet: T-Dongle-S3 + T-Dongle-C5 + M5StickC PLUS + XIAO S3 under one manager.
- [ ] All nodes join within ~10 s; CONFIG → MESH rows show each node's board name
- [ ] CONFIG → FIRMWARE REMOTE NODES rows show board + version per node
- [ ] Board picker hidden when all nodes are on this firmware
- [ ] Engines started from the app run on every node; hits arrive tagged by node
- [ ] Buzzer/LED setting pushed from manager reaches nodes (PLUS beeps; T-Dongles stay silent)
- [ ] Fleet update: every node logs `[MESH-WIFIOTA] ... self-update: <url>` with its OWN board in the URL, reboots, rejoins on the new version
- [ ] One node left on older firmware: picker appears; that node gets the picked board's image; new nodes still get their own
- [ ] Old manager (previous release) + new node: node still joins and reports hits (NODE_INFO ignored)
- [ ] New manager + old app: node list still shows (trailing board bytes ignored)
- [ ] M5StickC and PLUS2 do not appear as mesh nodes (built without mesh)

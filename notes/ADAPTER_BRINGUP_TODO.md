# USB adapter + scan-UI TODO

Tracking list for the MT7921 adapter work and the scan-UI changes. Status as of 2026-10-22.

## Done and committed
- MT7921AU (036AXM) WiFi monitor: firmware download + boot, channel sweep, auth parse, hidden-AP tag, delta-emit, apCount fix. Commits `1f7de27`, `f33b16c`. HW-verified scanning.
- No-autostart for the USB WiFi adapter: detected and shown, scans only on START.
- One-START model: Home scan-source cards are select toggles; the single session START/STOP drives the selected adapter. Map engine chips. SCAN / WIGLE chip labels.

## Done, built + installed, NOT committed (intertwined with peers' uncommitted reworks — a peer owns committing their files)
- `detection_row.dart`: auth pill moved to row start, distinct per-type colors, WiFi/BLE leading icon, "WIFI AP"/"WIFI CLIENT" detail header, themed (paper) detail sheet.
- `home_screen.dart`: USB/SDR scan-source cards, START/STOP button restored, single OUI-APEX on the welcome.
- `status_bar.dart`: shows "Phone scan"/"USB scan" instead of "Offline" when scanning without a board.
- `devices_screen.dart`: WiFi/BLE icons instead of the color square.
- `sdr.dart`: `sdrStateProvider` (peer's untracked file).

## In progress — MT7921 BLE scanning (multi-build bring-up)
Plan in memory `mt7921-bt-ble-bringup-plan.md`. BT = USB HCI on the combo's BT interface; firmware via WMT. EP0 is shared with the WLAN firmware load, so BT starts only after WLAN setup.
- [x] Milestone 1: `Mt7921BtAdapter` claims BT iface=0, interrupt-IN ep 0x8f, HCI Reset over EP0 control (out=3). HW result: command delivered, no HCI event pre-firmware (expected — controller silent until WMT firmware load).
- [~] Milestone 2: WMT BT firmware download (btmtk_setup_firmware_79xx transcribed). `BT_RAM_CODE_MT7961_1_2_hdr.bin` sha256 7a440a0f...dbae via FirmwareStore. WMT cmd = HCI 0xFC6F on EP0 control-OUT (type 0x20); event polled on EP0 control-IN (type 0xC0 req1 wValue48). dev_id read 0x70010200, per-section map-spec + 250B PATCH_DWNLD chunks, EP_RST_OPT 0x74011890, FUNC_CTRL enable. Built+installed, HW-UNVERIFIED.
- [x] Milestone 3: HCI LE passive scan (Set Scan Params 0x200b + Enable 0x200c, both status 0x00), parse LE Advertising Reports off the interrupt-IN event ep, emit mac/name/rssi/adv via the sightings channel `ble` key into `BleManager.addPhoneDetection`. HW-verified BLE-only START on 036axm: ~150 adverts/2s ingested. Event ep must be the interrupt-IN with the larger maxPacketSize (0x81 mps16, not 0x8f mps2). BLE-only skips WLAN monitorRx (`scanWifi` gate) so it no longer scans WiFi.

## Follow-ups
- [ ] SDR plugged-but-idle presence: the SDR has no reactive attach signal, so a plugged idle SDR does not show the Home card yet. Add USB-attach wiring so it appears when plugged, not only while scanning.
- [ ] Coordinate committing the peer-intertwined UI files.

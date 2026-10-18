# Since v0.6.1

## New

- Device classifier: DETECTIONS → DEVICES lists and classifies every nearby device.
- 20 classes including cameras, surveillance, public safety, drones, finder tags.
- Also glasses, wearables, vehicles, pentest tools, locks, health, home IoT.
- Co-travel and flood detection flag suspicious device behavior.
- Alert sounds: choose or compose a melody per alert type.
- Manager pushes tones and previews to every mesh node.
- Axon detection via BLE UUIDs FE6B/FE6C, with presence tones.
- Foxhunt can now target any device, including law enforcement.
- Watchlist import/export as CSV or JSON, up to 5000 rows.
- Fieldwatch catalog of 253 fleets added.
- Optional OUI-only Flock WiFi hits.
- XIAO ESP32-C5 mesh manager, available in the web flasher.
- `ouispy-flash.sh` detects T-Dongle and StickC boards, lists all firmware.
- Class alerts for cameras, smart glasses and trackers, saved to HISTORY.
- Camera and Amazon Sidewalk detection; full IEEE OUI database.
- Live Activity shows alert counts and the last alert; CarPlay support.
- Locked-phone alerts come through the Live Activity.
- Phone scan from the status bar: Bluetooth and Wi-Fi on Android, with or without a board; Bluetooth on iPhone and Mac. Shows as node PHONE.
- Phone foxhunt: track a device with the phone's radio, with or without a board.
- Map: SHOW ALL shows every detection of a class.
- Boards use a random MAC each boot.
- App themes and node temperatures.
- WDGWars upload shows the server's result counts.

## Changed

- New four-tab layout; history and rules moved, refreshed list rows.
- Watchlist notifications titled by entry description, with device details.
- Notifications: four engine toggles; class alerts always on.
- Wardrive WiFi / BLE / Both selector always visible while idle.
- Button-started engines keep running when the phone disconnects.
- WiGLE sessions start without waiting for a GPS fix.
- Classifier: iBeacon now "Beacons", Honeywell moved to industrial.
- Shorter notification body: RSSI, channel, name, MAC.
- App reconnects to a rebooted board by node ID.

## Fixed

- Mesh nodes scanning BLE missed manager commands, on every chip.
- Nodes now find a manager powered on after them.
- LilyGO T-Dongle S3 reboot loop when receiving an ignore list.
- XIAO ESP32-C5 nodes missing from the app's connect list.
- Manager tone changes not reaching nodes; removed tones kept playing.
- Connect screen scan list squeezed left and not scanning.
- Web flasher did not restart the board after flashing.
- Same-length offline filter list replacements were not saved.
- Classifier dropped router and IoT vendors.
- Manager showed fewer devices than a single node.
- Nodes under a manager could miss devices in busy areas.
- Bluetooth devices seen through a manager were not classified.
- MAPPED ALPRs always failed and kept loading after being turned off.
- SHOW ALL removed a HISTORY detection from the map.
- Camera alert toggle showed off while alerts still fired.
- A session started right after connecting could switch itself off.
- StickC boards missing from the OTA list.

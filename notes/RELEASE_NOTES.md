# Since v0.6.0

## More boards join the mesh

ESP32-C5 boards (XIAO C5, T-Dongle-C5) and the M5StickC PLUS / PLUS2 are no
longer standalone-only. They connect to a manager as fleet nodes, with mesh
relay, wardrive forwarding and ESP-NOW TX all working. C5 NimBLE pools moved
to PSRAM so the C5 has enough internal RAM for mesh + BLE + WiFi simultaneously.
The PLUS / PLUS2 fit mesh via TINYRAM wifi tx/cache budget cuts. Only the
original M5StickC remains standalone.

## NimBLE 2.x on all boards

All environments now build against NimBLE 2.x. S3 boards reclaim internal RAM
by routing NimBLE allocations to PSRAM.

## Per-board OTA

Firmware reports its board type over BLE. The companion app reads this and
selects the correct binary during OTA, instead of relying on a single global
"latest" version check. The web flasher version manifest source order is
corrected so each target resolves to the right image.

## Battery and display

- M5StickC and PLUS: battery percentage from AXP192 ADC, shown on the LCD
- M5StickC PLUS2: battery from built-in fuel gauge; PWM display dimmer
  (brightness button now sweeps smoothly instead of toggling between fixed levels)

## Also

- Boards without SD (StickC family) show wardrive and pcap on the LCD strip
  when the app is connected; hidden standalone since there is no local storage
- Upstream Flock GATT, DFU and OUI signatures synced into detection engine
- WiGLE upload backs off 24 hours on HTTP 429 instead of retrying immediately
- Manager C3 and WROOM builds link again (#20)
- C5 BLE link timing fixed on both XIAO and T-Dongle variants
- C5 WiFi init order no longer races BLE startup

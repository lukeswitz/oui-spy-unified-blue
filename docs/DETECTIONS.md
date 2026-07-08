# Built-in Detector signatures

The **Detector** engine matches your watchlist (MAC / OUI / name / BLE UUID) and, alongside it, a
set of built-in signatures that fire with no configuration. BLE signatures fire when the Detector's
BLE scan is running; WiFi signatures fire when its WiFi scan is running. They ride the normal
detector detection event (no wire-format change, old nodes stay compatible).

> Limitation: these run when the **Detector** engine owns the radio. While **Wardrive** owns the
> radio, the Detector goes passive and these do not fire — run Detector (BLE and/or WiFi) to use them.

---

## Find My / AirTag tracker — `TRACKER`

- **Matches:** BLE advertisement carrying Apple's Find My / offline-finding manufacturer data
  (`0x4C 0x00 0x12`). That is what AirTags — and any separated Find My device (including a nearby
  iPhone/Watch acting as a finder) — broadcast so they can be located.
- **Behavior:** persistence-gated, **not** per-advert. A tracker MAC must be seen continuously for
  **≥ 60 s** (≥ 8 adverts) before it alerts — i.e. something that is *staying with you*, not a device
  you walk past. One alert per tracker.
- **Feed label:** `Find My tracker following <N>s`.
- **Read it as:** anti-stalking. "A Find My tracker has been near you for N seconds."
- **False positives / limits:**
  - Apple rotates a tracker's MAC roughly every ~15 min, so a genuine stalker re-alerts once per
    rotation (a periodic reminder, not a flood). Walk-by trackers never alert.
  - You cannot identify *which* tracker or whose — the MAC rotates and the advert carries no name.
    The signal is presence-over-time, not identity.

## Flipper Zero — `FLIPPER`

- **Matches:** BLE device advertising a name beginning with `Flipper`.
- **Behavior:** immediate (Flippers are rare, not a flood), deduped per MAC for 10 s.
- **Feed label:** `Flipper Zero`.
- **False positives:** low — the name prefix is specific.

## WiFi deauth / disassoc storm — `DEAUTH_STORM`

- **Matches:** 802.11 management frames of subtype **deauth (`0xC0`)** or **disassoc (`0xA0`)** at a
  high rate — **≥ 10 in a 1 s window**, with a 10 s alert cooldown.
- **Reports:** `addr2` of the frames (the AP/attacker the deauth claims to come from).
- **Feed label:** `Deauth/Disassoc storm`.
- **Read it as:** "someone is running a deauth attack nearby right now."
- **False positives:** a busy AP sends the occasional deauth; the 10/s threshold filters normal
  traffic. Detector WiFi mode only.

## Probe-request SSID — `PROBE_SSID`

- **Matches:** 802.11 probe-requests (subtype `0x40`) carrying a **directed** SSID. Empty/wildcard
  probes are skipped to avoid a flood. Deduped per source MAC.
- **Reports:** the requesting device's MAC + the SSID it is searching for.
- **Feed label:** the SSID (e.g. `ORBI58`).
- **Read it as:** which saved networks nearby phones/laptops are calling out for. Detector WiFi mode only.

## Pwnagotchi — `PWNAGOTCHI`

- **Matches:** 802.11 beacon (subtype `0x80`) from the magic source MAC `de:ad:be:ef:de:ad`, 15 s
  cooldown.
- **Feed label:** `Pwnagotchi`.
- **False positives:** essentially none (exact magic MAC).

---

## Notes
- BLE signatures (Find My, Flipper) need the Detector's BLE scan; WiFi signatures (deauth, probe,
  Pwnagotchi) need its WiFi scan. Set the Detector radio in its screen.
- All of these emit as normal Detector detections, so they log, forward over mesh, and can trigger
  auto-PCAP like any other detection.

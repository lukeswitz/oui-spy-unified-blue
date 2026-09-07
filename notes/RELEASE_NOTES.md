# Since v0.5.1

## New boards

**M5StickC PLUS (v1), M5StickC PLUS2 (v2), M5StickC (original)** — node firmware with the
LCD, three buttons and the buzzer. No SD card and no GPS, so these are built for real-time
alerting rather than logging: detections chime and show on screen, and the app collects
them over Bluetooth. They run standalone only — mesh is compiled out to fit their RAM, so
they can't join a fleet under a manager.

| Button | Press | Action |
|---|---|---|
| A — front | tap | start / stop the detector |
| A — front | hold | foxhunt the last alert; hold again to stop |
| B — side | tap | start / stop a wardrive |
| B — side | hold | mute / unmute the buzzer |
| PWR | tap | screen brightness — full, 70%, 50%, off |
| PWR | hold | power off |

Foxhunt arms from the last *alerting* hit — detector, Flock BLE/WiFi, Sky Spy or UniPwn.
Wardrive survey hits don't arm it, so the target doesn't drift while you drive. It refuses
law-enforcement OUIs, the same rule the app enforces.

**LilyGO T-Dongle-S3** — node firmware with LCD, microSD and LED. Logs detections and
WiGLE CSV to the card with no app attached. Single tap starts and stops a wardrive.

## Fixes you will notice

- **Web flasher no longer bricks boards.** Flash mode and frequency were hardcoded per
  target and had drifted from what the builds emit, so the bootloader was written in the
  wrong mode and the board boot-looped. The flasher now uses each image's own parameters.
  If a 0.5.1 web flash left a board looping, reflash it.
- **Updates no longer install the wrong chip's firmware.** A board with no matching build
  could be handed another SoC's image, which passed the only check in place. Boards now
  match by exact name or report that no firmware is available.
- **An engine that fails to start now says so.** A failed start was reported to the app as
  success and could leave the radio marked in use, blocking every other engine until
  reboot. This affected all boards.
- **Settings survive an update.** NVS is preserved on flash.
- **Wardrive map needs no API key** — switched to Carto vector tiles.
- **Live Activity ends when you stop scanning** instead of hanging around (#19).
- **Feed export writes the full history**, not just the loaded page.
- **WDGWars shows your local Flock camera count.**

## Also

- Optional hardware GPS module support.
- WiGLE CSV rows keep counting on the T-Dongle in no-app mode.

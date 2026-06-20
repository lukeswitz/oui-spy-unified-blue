# OUI-SPY TODO backlog

## P0 — spool verification + crash (active)
- [ ] VERIFY spool mechanism on real HW via test fw (OUISPY_SPOOL_LIVETEST): standalone node, flock forced on, offline on, no phone -> a real flock cam in range must grow [SPOOL-LIVE] count + dump the MAC. Proves buffer works before touching app/config.
- [ ] If mechanism works: fix offl_scan propagation so the REAL app path spools (manager+node both need offlineScanEnabled; byte5 relay fixed in d20bafc, verify node actually applies it).
- [ ] Fix iOS close-crash (flutter_blue_plus didUpdateValueForCharacteristic invokeMethod after engine teardown — happens because detection NOTIFY stream is in-flight on close while scanning). Native guard needed (Dart disconnectQuiet insufficient under load).

## Backlog
- [ ] watchlist: per-entry on/off toggles like the ignore list has
- [ ] config-tab settings full sync to nodes: detector watchlist (0x100) + ignore list (0x23) not in periodic rebroadcast -> late-joining/rebooted nodes miss them

# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT
# Portions derived from OUI-SPY Detector home-dashboard, Copyright (c) 2025-2026 colonelpanichacks (MIT)

"""Fleet state for the OUI-APEX mesh, as seen through the board on USB.

Every source ends up calling one of:
  Fleet.feed_mesh(status, source)       the board's mesh status (decoded by board_decode)
  Fleet.feed_tlm(tlm, source)           roster + counters in the dashboard's own shape
  Fleet.feed_detection(obj, source)     one detection (board feed, MQTT, demo)
  Fleet.apply_config(cfg)               one node's settings readout
"""
import threading
import time

import board_decode as bd

HOME_TIMEOUT = 15        # s without a mesh status -> home offline
NODE_STALE = 12          # s since last frame before a remote counts offline
SAMPLE_EVERY = 60        # s between per-node RSSI/pkt samples in history
DEDUP_WINDOW = 6         # s: same (node, mac, type) from two sources = one event
SEEN_WINDOW = 60         # s: nodes that heard a device this recently count as "seen by"
BROADCAST_GAP = 0.25     # s: fleet updates are coalesced to <= 4 a second (first one at once)

HOME_STAT_KEYS = ("rx", "tx", "up", "heap", "dev", "n", "mode", "mesh", "role")


def intel_name(intel):
    """The name a device gives itself: BLE local name, else an AP's SSID."""
    if not intel:
        return None
    if intel.get("name"):
        return intel["name"]
    if intel.get("frame") in ("beacon", "probe-resp") and intel.get("ssid"):
        return intel["ssid"]
    return None


class Fleet:
    def __init__(self, store, emit):
        self.store = store
        self.emit = emit                 # emit(event_name, payload)
        self.drones = None               # drones.Drones, set by the app
        self.tri = None                  # tri.Tri, set by the app: fixes for every display
        self.tri_fixes = {}              # mac -> last fix (sent with /api/state)
        self._tri_q = set()
        self._tri_ev = threading.Event()
        threading.Thread(target=self._tri_worker, daemon=True, name="tri").start()
        self.lock = threading.RLock()
        self.home_id = store.get_setting("home_node_id") if hasattr(store, "get_setting") else None
        self.connected_id = None         # the board on USB
        self.home = {}                   # latest home stats
        self.home_seen = 0.0
        self.nodes = {}                  # id -> live state
        self.recent = {}                 # dedup key -> ts
        self.sightings = {}              # mac -> {node: (rssi, ts)}, last SEEN_WINDOW s
        self.last_sample = {}
        self.console = []                # ring of recent event lines
        self.on_join = None              # BoardCommander.node_joined
        self._bc_lock = threading.Lock()
        self._bc_timer = None
        self._bc_dirty = False
        for nid, m in store.nodes_meta().items():
            self.nodes[nid] = self._blank(nid, m.get("role"))
            self.nodes[nid]["last_seen"] = m.get("last_seen") or 0

    @staticmethod
    def _blank(nid, role=None):
        return {"id": nid, "role": role or "remote", "online": False, "last_seen": 0,
                "pkts": 0, "rssi": None, "since": None,
                "cfg": None, "cfg_ts": None, "filters": None, "filters_ok": True, "filters_ts": None,
                "filters_via": None}

    def log(self, source, line):
        now = time.time()
        with self.lock:
            self.console.append([now, source, line])
            del self.console[:-300]
        self.emit("console", {"ts": now, "source": source, "line": line})

    # ------------------------------------------------------------------
    # mesh status
    # ------------------------------------------------------------------
    def set_connected_board(self, nid, is_manager):
        with self.lock:
            self.connected_id = nid or None
            if is_manager and nid:
                if nid != self.home_id:
                    self.store.set_setting("home_node_id", nid)
                self.home_id = nid
        self.log("board", f"connected to {nid or 'a board'} ({'manager' if is_manager else 'node'})")

    def feed_mesh(self, st, source="serial"):
        live = st["live"]
        mgr = next((n["id"] for n in live if n["role"] == "manager"), None)
        with self.lock:
            own = self.connected_id
            home = mgr or (own if own and own == self.home_id else None)
        rows = {r["id"]: r for r in st["signal"]}
        viewer = home or own
        heard = {h["id"]: h["rssi"] for h in (rows.get(viewer) or {}).get("hears", [])}
        nodes = [{"id": n["id"], "role": "home" if n["id"] == home else "remote", "last": 0, "pkts": None,
                  "rssi": heard.get(n["id"])} for n in live if n["id"] != viewer]
        tlm = {"id": viewer, "role": "home" if home else "remote", "mode": "scan",
               "mesh": 1 if st["enabled"] else 0, "rx": st["rx"], "tx": st["tx"], "n": len(nodes),
               "nodes": nodes}
        if viewer:
            self.feed_tlm(tlm, source)
        by_live = {n["id"]: n for n in live}
        for d in st["details"]:
            lv = by_live.get(d["id"], {})
            nbr = [[h["id"], h["rssi"], 0] for h in (rows.get(d["id"]) or {}).get("hears", [])
                   if h["rssi"] is not None]
            self.apply_config({
                "node": d["id"], "role": "home" if d["id"] == home else "remote",
                "fw": bd.firmware_text(d["fw"]), "board": d["board"], "up": d["up"],
                "filters": d["filter_macs"], "filters_uuids": d["filter_uuids"], "peers": d["peers"],
                "age": d["age"], "temp": lv.get("temp"), "engines": lv.get("engines"), "nbr": nbr})
        if st["key_failures"]:
            self.log("board", f"mesh: {st['key_failures']} frames failed the fleet key check")

    def feed_tlm(self, t, source="serial"):
        now = time.time()
        if t.get("role") == "remote":
            nid = t.get("id")
            if nid:
                with self.lock:
                    for n in t.get("nodes", []):
                        if n.get("id") and n.get("id") != self.home_id:
                            self._node_seen(n["id"], n.get("role"), n.get("last", 0), None, n.get("rssi"), now)
                    self._node_seen(nid, "remote", 0, None, None, now)
                self._broadcast()
            return
        with self.lock:
            if t.get("id"):
                if t["id"] != self.home_id and t.get("role") == "home":
                    self.store.set_setting("home_node_id", t["id"])
                self.home_id = t["id"]
            for k in HOME_STAT_KEYS:
                if k in t:
                    self.home[k] = t[k]
            self.home["source"] = source
            seen = set()
            for n in t.get("nodes", []):
                nid = n.get("id")
                if not nid:
                    continue
                seen.add(nid)
                self._node_seen(nid, n.get("role"), n.get("last", 0), n.get("pkts"),
                                n.get("rssi") or None, now)
            for nid, st in list(self.nodes.items()):
                if st["online"] and nid not in seen and nid != self.home_id:
                    self._node_offline(nid)
        self._mark_home_alive(role=t.get("role"))
        self._broadcast()

    # ------------------------------------------------------------------
    # detections
    # ------------------------------------------------------------------
    def feed_detection(self, d, source="serial"):
        now = time.time()
        mac = str(d.get("mac", "")).upper()
        if not mac:
            return
        descr = str(d.get("desc", ""))
        node = (d.get("node") or self.home_id or "HOME").upper()
        dom = d.get("dom")
        if dom not in ("ble", "wifi"):
            dom = "wifi" if str(d.get("type", "")).upper() in ("PROBE", "BEACON") else "ble"
        key = (node, mac, d.get("type"))
        seen_by = self._sighting(mac, node, d.get("rssi"), now)
        if self.tri:
            self.tri.add(mac, node, d.get("rssi"), dom, now)
            with self.lock:
                self._tri_q.add(mac)
            self._tri_ev.set()
        info = d.get("info") if isinstance(d.get("info"), dict) else None
        name = None
        if info:
            try:
                intel = self.store.merge_intel(mac, info, node=node, rssi=d.get("rssi"), ts=now)
                name = intel_name(intel)
            except Exception as e:      # never lose the detection over intel
                print(f"[intel] {mac}: {e}")
        if name is None:
            rec = self.store.device_intel(mac)
            name = intel_name(rec["intel"]) if rec else None
        if d.get("upd"):
            role = "home" if node == self.home_id else None
            self._node_seen(node, role, 0, None, None, now, from_det=True)
            self.emit("sighting", {"ts": now, "node": node, "mac": mac, "rssi": d.get("rssi"),
                                   "type": d.get("type"), "match": d.get("match"),
                                   "descr": descr.strip(), "dom": dom, "seen_by": seen_by,
                                   "name": name or "", "info": info})
            return
        with self.lock:
            for k, ts in list(self.recent.items()):
                if now - ts > DEDUP_WINDOW:
                    del self.recent[k]
            if key in self.recent:
                return
            self.recent[key] = now
        dash_alias = (self.store.mac_aliases().get(mac) or {}).get("alias")
        det = {
            "ts": now, "node": node, "mac": mac, "alias": dash_alias or d.get("alias") or "",
            "rssi": d.get("rssi"), "type": d.get("type"), "match": d.get("match"),
            "descr": descr.strip(), "dom": dom, "source": source,
            "name": name or "", "info": info,
            "group": self.store.group_of().get(mac),
            "is_new": not self.store.mac_known(mac),
            "seen_by": seen_by,
            "closest": seen_by[0][0] if len(seen_by) > 1 else None,
        }
        det["id"] = self.store.add_detection(det)
        role = "home" if node == self.home_id else None
        self._node_seen(node, role, 0, None, None, now, from_det=True)
        self.emit("det", det)
        self.log(source, f"{node} {mac} {d.get('rssi')} dBm {d.get('type') or ''} {descr}".strip())
        self._broadcast()

    def _tri_worker(self):
        """Triangulate devices with new readings, at most once a second each, off the
        feed thread (a fix is a grid search: tens of ms)."""
        while True:
            self._tri_ev.wait(1.0)
            self._tri_ev.clear()
            with self.lock:
                macs, self._tri_q = self._tri_q, set()
            for mac in macs:
                if not self.tri or not self.tri.due(mac):
                    with self.lock:
                        self._tri_q.add(mac)
                    continue
                try:
                    fx = self.tri.fix(mac)
                except Exception as e:
                    print(f"[tri] {mac}: {e}")
                    continue
                fx["ts"] = time.time()
                self.tri_fixes[mac] = fx
                for m in [m for m, f in self.tri_fixes.items() if time.time() - f["ts"] > 600]:
                    del self.tri_fixes[m]
                self.emit("tri", fx)

    def _sighting(self, mac, node, rssi, now):
        """Record that `node` heard `mac` and return [[node, rssi, age_s], ...] for the
        window, strongest first."""
        with self.lock:
            for m in [m for m, per in self.sightings.items()
                      if all(now - ts > SEEN_WINDOW for _, ts in per.values())]:
                del self.sightings[m]
            per = self.sightings.setdefault(mac, {})
            if isinstance(rssi, (int, float)):
                per[node] = (int(rssi), now)
            rows = [[n, r, round(now - ts)] for n, (r, ts) in per.items() if now - ts <= SEEN_WINDOW]
        rows.sort(key=lambda x: -x[1])
        return rows

    # ------------------------------------------------------------------
    # node bookkeeping
    # ------------------------------------------------------------------
    def _node_seen(self, nid, role, last_s, pkts, rssi, now=None, from_det=False):
        now = now or time.time()
        with self.lock:
            st = self.nodes.get(nid)
            if st is None:
                st = self.nodes[nid] = self._blank(nid, role)
            if role in ("home", "remote"):
                st["role"] = role
            st["last_seen"] = max(st["last_seen"], now - (last_s or 0))
            if pkts is not None:
                st["pkts"] = pkts
            if rssi:
                st["rssi"] = rssi
            came_online = not st["online"]
            if came_online:
                st["online"] = True
                st["since"] = now
        self.store.touch_node(nid, st["role"], now)
        if came_online:
            self.store.add_sighting(nid, "online", st["rssi"], st["pkts"], now)
            self.emit("node_event", {"id": nid, "event": "online", "ts": now})
            if self.on_join:
                self.on_join(nid)
        if now - self.last_sample.get(nid, 0) >= SAMPLE_EVERY and not from_det:
            self.last_sample[nid] = now
            self.store.add_sighting(nid, "sample", st["rssi"], st["pkts"], now)

    def apply_config(self, cfg):
        """One node's settings readout (the mesh status detail for that node)."""
        nid = str(cfg.get("node", "")).upper()
        if not nid:
            return
        now = time.time()
        with self.lock:
            st = self.nodes.get(nid)
            if st is None:
                st = self.nodes[nid] = self._blank(nid, cfg.get("role"))
            st["cfg"] = cfg
            st["cfg_ts"] = now
            if cfg.get("role") in ("home", "remote") and nid != self.home_id:
                st["role"] = cfg["role"]
        if nid != self.home_id:
            self._node_seen(nid, cfg.get("role"), 0, None, None, now, from_det=True)
        self._broadcast()

    def _node_offline(self, nid):
        with self.lock:
            st = self.nodes.get(nid)
            if not st or not st["online"]:
                return
            st["online"] = False
            st["since"] = time.time()
        self.store.add_sighting(nid, "offline", st["rssi"], st["pkts"])
        self.emit("node_event", {"id": nid, "event": "offline", "ts": time.time()})

    def _mark_home_alive(self, role=None):
        now = time.time()
        with self.lock:
            self.home_seen = now
            hid = self.home_id
        if hid:
            self._node_seen(hid, "home" if role in (None, "home") else role, 0, None, None, now)

    def tick(self):
        """Called once a second: age out silent nodes and a silent home."""
        now = time.time()
        changed = False
        with self.lock:
            hid = self.home_id
            items = list(self.nodes.items())
        for nid, st in items:
            if not st["online"]:
                continue
            limit = HOME_TIMEOUT if nid == hid else NODE_STALE
            if nid != hid and now - self.home_seen > HOME_TIMEOUT:
                limit = 600
            if now - st["last_seen"] > limit:
                self._node_offline(nid)
                changed = True
        if changed:
            self._broadcast()

    # ------------------------------------------------------------------
    # snapshots
    # ------------------------------------------------------------------
    def snapshot(self, lists=True):
        meta = self.store.nodes_meta()
        now = time.time()
        with self.lock:
            nodes = []
            for nid, st in self.nodes.items():
                m = meta.get(nid, {})
                nodes.append({**st, "alias": m.get("alias") or "", "lat": m.get("lat"),
                              "lon": m.get("lon"), "notes": m.get("notes") or "",
                              "color": m.get("color"),
                              "first_seen": m.get("first_seen"),
                              "is_home": nid == self.home_id, "filters_fresh": None,
                              "age": round(now - st["last_seen"], 1) if st["last_seen"] else None})
            home = dict(self.home)
            home.update({"id": self.home_id, "alive": now - self.home_seen < HOME_TIMEOUT,
                         "age": round(now - self.home_seen, 1) if self.home_seen else None,
                         "legacy": False})
        nodes.sort(key=lambda n: (not n["is_home"], not n["online"], n["id"]))
        return {"home": home, "nodes": nodes, "ts": now}

    def _broadcast(self):
        """Push the fleet to every dashboard: the first change goes out at once, a burst
        behind it is folded into one update at the end of BROADCAST_GAP."""
        with self._bc_lock:
            if self._bc_timer is not None:
                self._bc_dirty = True
                return
            self._bc_timer = threading.Timer(BROADCAST_GAP, self._broadcast_tail)
            self._bc_timer.daemon = True
            self._bc_timer.start()
        self.emit("fleet", self.snapshot(lists=False))

    def _broadcast_tail(self):
        with self._bc_lock:
            dirty, self._bc_dirty, self._bc_timer = self._bc_dirty, False, None
        if dirty:
            self._broadcast()

    def console_tail(self):
        with self.lock:
            return list(self.console[-200:])

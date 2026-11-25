# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""The live feed: an OUI-APEX board on USB (serial, or its USB network port), spoken to over the
board link. Detections and mesh status come in as notifications and go into the Fleet."""
import threading
import time

import board_decode as bd
import board_link as bl
from sources import Source, list_serial_ports, serial

STATUS_POLL_DEFAULT = 120


def parse_target(spec):
    """'tcp:192.0.2.5:4700' or 'tcp:192.0.2.5' -> (host, port); None when it isn't a network target."""
    if not str(spec).startswith("tcp:"):
        return None
    host, _, port = str(spec)[4:].partition(":")
    if not host:
        return None
    return host, int(port or 4700)


def detection_to_fleet(d, home_id):
    """A decoded detection -> the dict Fleet.feed_detection takes."""
    engine, method = d["engine"], d["method"]
    wifi = (engine in ("flock_wifi", "pcap") or (engine == "detector" and method in bd.WIFI_DETECTOR)
            or (engine == "wardrive" and method in bd.WIFI_WARDRIVE) or method == "wifi_proximity"
            or method in ("odid_nan", "odid_beacon"))
    label = bd.ENGINE_LABEL[engine]
    what = d.get("desc") or d.get("ssid") or d.get("name")
    info = {}
    if d.get("ssid"):
        info.update(frame="beacon" if method == "wifi_ap" else "probe-req", ssid=d["ssid"])
    if wifi and d["channel"]:
        info["ch"] = d["channel"]
    if d.get("name") and not wifi:
        info["name"] = d["name"]
    return {"mac": d["mac"], "rssi": d["rssi"], "type": method.upper(), "match": "",
            "desc": f"{label} {what}".strip() if what else label,
            "node": bd.canonical_node_id(d["source"]) or home_id, "dom": "wifi" if wifi else "ble",
            "info": info or None}


def odid_to_drone(d, home_id):
    o = d["odid"]
    return {"mac": d["mac"], "rssi": d["rssi"], "id": o["id"], "op": o["op"], "desc": o["desc"],
            "lat": o["lat"], "lon": o["lon"], "alt": o["alt"], "altb": o["altb"], "hagl": o["hagl"],
            "spd": o["spd"], "hdg": o["hdg"], "plat": o["plat"], "plon": o["plon"],
            "node": bd.canonical_node_id(d["source"]) or home_id}


class BoardSource(Source):
    kind = "serial"

    def __init__(self, fleet, on_status, port="auto", get_pref=None, set_pref=None, get_poll=None,
                 transport_factory=None):
        super().__init__(fleet, on_status)
        self.port_cfg = port or "auto"
        self.get_pref = get_pref or (lambda: None)
        self.set_pref = set_pref or (lambda sn: None)
        self.get_poll = get_poll or (lambda: STATUS_POLL_DEFAULT)
        self.transport_factory = transport_factory
        self.session = None
        self.skip = {}
        self.cur_sn = None
        self.board = {}

    def _targets(self):
        """Yield (label, opener) for each place a board may be."""
        if self.transport_factory:
            yield "link", self.transport_factory, None
            return
        net = parse_target(self.port_cfg)
        if net:
            yield f"{net[0]}:{net[1]}", (lambda: bl.SocketTransport.connect(*net)), None
            return
        ports = list_serial_ports()
        if self.port_cfg != "auto":
            pref = self.get_pref()
            by_sn = [p for p in ports if pref and p["serial"] == pref]
            dev = by_sn[0]["device"] if by_sn else self.port_cfg
            yield dev, (lambda: bl.SerialTransport.open(serial, dev)), (by_sn[0]["serial"] if by_sn else None)
            return
        now = time.time()
        cands = [p for p in ports if p["espressif"] and now - self.skip.get(p["serial"], 0) > 60]
        pref = self.get_pref()
        cands.sort(key=lambda p: p["serial"] != pref)
        for p in cands:
            yield p["device"], (lambda dev=p["device"]: bl.SerialTransport.open(serial, dev)), p["serial"]

    def run(self):
        if self.transport_factory is None and serial is None and not parse_target(self.port_cfg):
            self.set_state(detail="pyserial not installed")
            return
        while not self.stop_evt.is_set():
            tried = False
            for label, opener, sn in self._targets():
                tried = True
                self.cur_sn = sn
                self._session(label, opener)
                if self.stop_evt.is_set():
                    break
            if not tried:
                self.set_state(connected=False, port=None, detail="waiting for an OUI-APEX board on USB")
                self.stop_evt.wait(0.5)
            else:
                self.stop_evt.wait(0.5)
        self.set_state(connected=False, detail="stopped")

    def _session(self, label, opener):
        lost = threading.Event()
        try:
            transport = opener()
        except (OSError, bl.LinkError) as e:
            self.set_state(connected=False, detail=f"{label}: {str(e)[:80]}")
            return
        sess = bl.LinkSession(transport, on_notify=self._notify, on_close=lost.set)
        self.session = sess
        try:
            sess.start()
            info = bd.device_info(sess.read(bl.CHR_DEVICE_INFO))
            self.board = info
            self.fleet.set_connected_board(info["id"], info["role"] == "mgr")
            if self.cur_sn and info["role"] == "mgr":
                self.set_pref(self.cur_sn)
            for cid in (bl.CHR_DETECTION_EVENTS, bl.CHR_MESH_STATUS):
                if cid in sess.ids:
                    sess.subscribe(cid, True)
            if bl.CHR_MESH_STATUS in sess.ids:
                try:
                    self.fleet.feed_mesh(bd.decode_mesh_status(sess.read(bl.CHR_MESH_STATUS)), "serial")
                except bl.LinkError:
                    pass
            self.set_state(connected=True, port=label, board=info["board"], node=info["id"],
                           fw=info["fw"], role=info["role"], detail=f"{label}: {info['board']} {info['id']}")
            self.request_status()
            last_poll = time.time()
            while not self.stop_evt.is_set() and not lost.is_set():
                poll = int(self.get_poll() or 0)
                if poll and time.time() - last_poll >= poll:
                    last_poll = time.time()
                    self.request_status()
                lost.wait(0.5)
            if not self.stop_evt.is_set():
                self.set_state(connected=False, detail=f"lost {label}")
        except (bl.LinkError, OSError) as e:
            self.set_state(connected=False, detail=f"{label}: {str(e)[:80]}")
            if self.cur_sn and not sess.ids:
                self.skip[self.cur_sn] = time.time()
        finally:
            sess.close()
            self.session = None

    def _notify(self, cid, payload):
        try:
            if cid == bl.CHR_DETECTION_EVENTS:
                d = bd.decode_detection(payload)
                home = self.fleet.home_id
                if d["engine"] == "sky_spy" and d["odid"] and self.fleet.drones:
                    self.fleet.drones.feed(odid_to_drone(d, home), "rid", home)
                else:
                    self.fleet.feed_detection(detection_to_fleet(d, home or self.board.get("id")), "serial")
            elif cid == bl.CHR_MESH_STATUS:
                self.fleet.feed_mesh(bd.decode_mesh_status(payload), "serial")
        except (ValueError, IndexError, KeyError) as e:
            print(f"[board] bad frame on 0x{cid:x}: {e}")

    def control(self, payload):
        """Write a node-control command to the board; True once the board accepted it."""
        sess = self.session
        if sess is None or sess.closed:
            return False
        try:
            sess.write(bl.CHR_ENGINE_CONTROL, payload)
            return True
        except (bl.LinkError, OSError):
            return False

    def request_status(self, node_id=None):
        return self.control(bd.encode_status_request(node_id))

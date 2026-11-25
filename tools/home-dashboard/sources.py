# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT
# Portions derived from OUI-SPY Detector home-dashboard, Copyright (c) 2025-2026 colonelpanichacks (MIT)

"""Feeds into the Fleet: the board on USB (board_source.py), MQTT, and a demo generator.

Each source is a daemon thread with a stop() and a status() dict that the UI shows in the
header. Sources never raise: hardware comes and goes.
"""
import json
import random
import threading
import time

try:
    import serial
    from serial.tools import list_ports
except ImportError:      # pragma: no cover - surfaced in status()
    serial = None
    list_ports = None

try:
    import paho.mqtt.client as mqtt
except ImportError:      # pragma: no cover
    mqtt = None

ESPRESSIF_VID = 0x303A


def list_serial_ports():
    if list_ports is None:
        return []
    out = []
    for p in list_ports.comports():
        out.append({"device": p.device, "desc": p.description or "",
                    "vid": p.vid, "pid": p.pid, "serial": p.serial_number or "",
                    "espressif": p.vid == ESPRESSIF_VID})
    out.sort(key=lambda p: (not p["espressif"], p["device"]))
    return out


class Source(threading.Thread):
    kind = "source"

    def __init__(self, fleet, on_status):
        super().__init__(daemon=True)
        self.fleet = fleet
        self.on_status = on_status
        self.stop_evt = threading.Event()
        self.state = {"kind": self.kind, "connected": False, "detail": "starting"}

    def set_state(self, **kw):
        changed = any(self.state.get(k) != v for k, v in kw.items())
        self.state.update(kw)
        if changed:
            self.on_status()

    def status(self):
        return dict(self.state)

    def stop(self):
        self.stop_evt.set()

    def control(self, payload):
        return False


class MqttSource(Source):
    """Detections published by nodes that are on Wi-Fi. The password is never kept in the
    dashboard's database: it comes from the environment or a file (see ouispymesh.mqtt_password)."""
    kind = "mqtt"

    def __init__(self, fleet, on_status, host, port=1883, user="", password="",
                 topic="+/detection", tls=False):
        super().__init__(fleet, on_status)
        self.host, self.port = host, int(port or 1883)
        self.user, self.password = user, password
        self.topic = topic or "+/detection"
        self.tls = bool(tls)
        self.client = None

    def run(self):
        if mqtt is None:
            self.set_state(detail="paho-mqtt not installed")
            return
        cid = f"ouispy-dash-{random.randint(0, 0xFFFFFF):06x}"
        try:
            c = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=cid)
        except AttributeError:
            c = mqtt.Client(client_id=cid)
        if self.user:
            c.username_pw_set(self.user, self.password or None)
        if self.tls:
            c.tls_set()
        c.on_connect = self._on_connect
        c.on_disconnect = self._on_disconnect
        c.on_message = self._on_message
        c.reconnect_delay_set(1, 30)
        self.client = c
        self.set_state(detail=f"connecting {self.host}:{self.port}")
        while not self.stop_evt.is_set():
            try:
                c.connect(self.host, self.port, keepalive=30)
                break
            except Exception as e:
                self.set_state(connected=False, detail=f"{self.host}:{self.port} {str(e)[:60]}")
                self.stop_evt.wait(5)
        if self.stop_evt.is_set():
            return
        c.loop_start()
        self.stop_evt.wait()
        c.loop_stop()
        try:
            c.disconnect()
        except Exception:
            pass
        self.set_state(connected=False, detail="stopped")

    def _on_connect(self, client, userdata, flags, rc, props=None):
        ok = (rc == 0) if isinstance(rc, int) else not rc.is_failure
        if ok:
            client.subscribe(self.topic)
            base = self.topic.rsplit("/", 1)[0] if "/" in self.topic else "+"
            client.subscribe(f"{base}/availability")
            self.set_state(connected=True, detail=f"{self.host}:{self.port} {self.topic}")
        else:
            self.set_state(connected=False, detail=f"refused: {rc}")

    def _on_disconnect(self, client, userdata, *args):
        self.set_state(connected=False, detail=f"{self.host}:{self.port} disconnected")

    def _on_message(self, client, userdata, msg):
        payload = msg.payload.decode("utf-8", "replace").strip()
        if msg.topic.endswith("/availability"):
            self.set_state(device=msg.topic.split("/")[0], availability=payload)
            return
        try:
            obj = json.loads(payload)
        except ValueError:
            return
        if isinstance(obj, dict) and obj.get("mac"):
            self.fleet.feed_detection(obj, "mqtt")


DEMO_HOME = "DE0A"
DEMO_REMOTES = ["DE0B", "DE0C", "DE0D", "DE0E"]
DEMO_LINKS = {"DE0A": ["DE0B", "DE0C"], "DE0B": ["DE0A", "DE0D"],
              "DE0C": ["DE0A", "DE0E", "DE0D"], "DE0D": ["DE0B", "DE0C"],
              "DE0E": ["DE0C"]}
DEMO_TARGETS = [
    ("00:25:DF", "OUI_MATCH", "Flock BLE", "ble"), ("00:25:DF", "WIFI_WATCHLIST", "Detector", "wifi"),
    ("B4:1E:52", "OUI_MATCH", "Flock BLE", "ble"), ("70:C9:4E", "OUI_ADDR2", "Flock WiFi", "wifi"),
    ("D4:2D:C5", "WIFI_WATCHLIST", "Detector", "wifi"), ("E0:A7:00", "OUI_ADDR1", "Flock WiFi", "wifi"),
    ("0C:9A:E6", "DRONE_BLE", "Detector", "ble"), ("7C:2A:9E", "GLASSES", "Detector", "ble"),
]

# --demo-showcase: screenshot-safe sample data. No police or ALPR vendors, and every MAC
# ends in an obviously synthetic 00:00:xx, so nothing in a published screenshot can point at a real device.
SHOWCASE_TARGETS = [
    ("60:60:1F", "DRONE_BLE", "Detector", "ble"), ("60:60:1F", "ODID_BEACON", "Sky Spy", "wifi"),
    ("A0:14:3D", "DRONE_BLE", "Detector", "ble"), ("38:1D:14", "ODID_NAN", "Sky Spy", "wifi"),
    ("7C:2A:9E", "GLASSES", "Detector", "ble"), ("E0:A7:00", "CAMERA", "Detector", "wifi"),
    ("DE:AD:BE", "PWNAGOTCHI", "Detector", "wifi"),
]
SHOWCASE = False


def use_showcase():
    global SHOWCASE
    SHOWCASE = True
    DEMO_TARGETS[:] = SHOWCASE_TARGETS


def demo_mac(oui):
    if SHOWCASE:
        return oui + ":00:00:" + f"{random.randint(1, 40):02X}"
    return oui + ":" + ":".join(f"{random.randint(0, 255):02X}" for _ in range(3))


class DemoSource(Source):
    """A fake fleet fed through the same Fleet entry points the board feed uses."""
    kind = "demo"

    def __init__(self, fleet, on_status):
        super().__init__(fleet, on_status)
        self.t0 = time.time()
        self.rssi = {"DE0B": -58, "DE0C": -71, "DE0D": -84, "DE0E": -66}
        self.flap_until = 0
        self.macs = [demo_mac(o) for o, *_ in DEMO_TARGETS for _ in range(2)]
        self.sent = []

    def run(self):
        self.set_state(connected=True, detail="simulated fleet (5 nodes)")
        self.fleet.set_connected_board(DEMO_HOME, True)
        next_status = 0
        next_det = time.time() + 2
        while not self.stop_evt.wait(0.25):
            now = time.time()
            if now >= next_status:
                next_status = now + 5
                self._status(now)
            if now >= next_det:
                next_det = now + random.uniform(2.5, 9)
                self._detection()
        self.set_state(connected=False, detail="stopped")

    def _up(self, n, now=None):
        return not (n == "DE0D" and (now or time.time()) < self.flap_until)

    def _status(self, now):
        if self.flap_until < now and random.random() < 0.05:
            self.flap_until = now + 40
        live = [{"id": DEMO_HOME, "role": "manager", "engines": 1, "fw": 0x000700,
                 "board": "xiao_s3", "temp": 41}]
        details = [{"id": DEMO_HOME, "fw": 0x000700, "board": "xiao_s3", "up": int(now - self.t0 + 3600),
                    "filter_macs": 12, "filter_uuids": 3, "peers": 4, "age": 0}]
        signal = [{"id": DEMO_HOME, "hears": []}]
        for n in DEMO_REMOTES:
            if not self._up(n, now):
                continue
            self.rssi[n] = max(-95, min(-40, self.rssi[n] + random.randint(-3, 3)))
            live.append({"id": n, "role": "node", "engines": 1, "fw": 0x000700, "board": "xiao_c5",
                         "temp": random.randint(30, 48)})
            details.append({"id": n, "fw": 0x000700, "board": "xiao_c5", "up": random.randint(900, 86000),
                            "filter_macs": 12, "filter_uuids": 3, "peers": random.randint(1, 3),
                            "age": random.randint(0, 6) * 10})
            if n in DEMO_LINKS[DEMO_HOME]:
                signal[0]["hears"].append({"id": n, "rssi": self.rssi[n]})
        for n in DEMO_REMOTES:
            if self._up(n, now):
                signal.append({"id": n, "hears": [{"id": m, "rssi": random.randint(-88, -55)}
                                                  for m in DEMO_LINKS[n] if m == DEMO_HOME or self._up(m, now)]})
        self.fleet.feed_mesh({"enabled": True, "peers": len(live) - 1, "connected": len(live) - 1,
                              "rx": int(now - self.t0) * 4, "tx": int(now - self.t0), "live": live,
                              "key_failures": 0, "details": details, "filter_push": None, "signal": signal},
                             "demo")

    def _detection(self):
        oui, method, label, dom = random.choice(DEMO_TARGETS)
        if random.random() < 0.05:
            mac = demo_mac(oui)
            self.macs.append(mac)
        else:
            mac = random.choice([m for m in self.macs if m.startswith(oui)] or [demo_mac(oui)])
        live = [n for n in DEMO_REMOTES if self._up(n)]
        node = random.choice([DEMO_HOME] + live + live)
        self.fleet.feed_detection({"mac": mac, "rssi": random.randint(-92, -48), "type": method,
                                   "match": oui.replace(":", ""), "desc": label, "node": node, "dom": dom},
                                  "demo")

    def control(self, payload):
        self.sent.append(bytes(payload))
        return True

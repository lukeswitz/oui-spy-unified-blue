# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""Outbound links the dashboard owns: a TAK server (Cursor-on-Target) and Reticulum (LXMF alerts).
The OUI-APEX app shows and switches them; the settings live in the dashboard's database.

Nothing here stores a secret. TAK over TLS reads certificate files by path. Reticulum keeps its
identity in a 0600 file outside the repo. Both links are off until switched on.
"""
import os
import queue
import socket
import ssl
import threading
import time
from xml.sax.saxutils import quoteattr

ALERT_KINDS = ("new_devices", "drones", "lost_nodes")
IDENTITY_FILE = os.path.expanduser("~/.config/ouispy/reticulum_identity")
TAK_DEFAULTS = {"enabled": False, "host": "", "port": 8087, "proto": "tcp", "callsign": "OUISPY",
                "ca_file": "", "cert_file": "", "key_file": ""}
RNS_DEFAULTS = {"enabled": False, "recipients": [], "send": {k: True for k in ALERT_KINDS}}
ALERT_GAP = 10
TAK_EVERY = 10
STALE_S = 60


def cot_event(uid, ctype, lat, lon, callsign, remarks="", how="m-g", stale=STALE_S, link_uid=None, now=None):
    now = time.time() if now is None else now
    iso = lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
    link = f'<link uid={quoteattr(link_uid)} relation="p-p" type="a-u-A-M-H-Q"/>' if link_uid else ""
    return (f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            f'<event version="2.0" uid={quoteattr(uid)} type={quoteattr(ctype)} how={quoteattr(how)} '
            f'time="{iso(now)}" start="{iso(now)}" stale="{iso(now + stale)}">'
            f'<point lat="{lat:.7f}" lon="{lon:.7f}" hae="9999999.0" ce="9999999.0" le="9999999.0"/>'
            f'<detail><contact callsign={quoteattr(callsign)}/>{link}<remarks>{_esc(remarks)}</remarks></detail>'
            f'</event>')


def _esc(s):
    return "".join(c for c in str(s) if c >= " " or c in "\t\n").replace("&", "&amp;").replace("<", "&lt;") \
        .replace(">", "&gt;")


def events_for(nodes, drones, callsign, now=None):
    """Nodes with a map position, live drones and their pilots -> CoT XML strings."""
    out = []
    for n in nodes:
        if n.get("lat") is None or n.get("lon") is None or not n.get("online"):
            continue
        name = n.get("alias") or n["id"]
        out.append(cot_event(f"ouispy-node-{n['id']}", "a-f-G-U-C", n["lat"], n["lon"], f"{callsign} {name}",
                             f"OUI-APEX {n.get('role', 'node')} {n['id']}", now=now))
    for d in drones:
        if not d.get("live"):
            continue
        key = str(d["mac"]).replace(":", "")
        ident = d.get("id") or key
        uid = f"ouispy-drone-{key}"
        if d.get("lat") is not None and d.get("lon") is not None:
            out.append(cot_event(uid, "a-u-A-M-H-Q", d["lat"], d["lon"], f"UAS {ident}",
                                 f"Remote ID drone, {d.get('rssi')} dBm", now=now))
            if d.get("plat") is not None and d.get("plon") is not None:
                out.append(cot_event(f"ouispy-pilot-{key}", "a-u-G", d["plat"], d["plon"], f"PILOT {ident}",
                                     f"Operator of UAS {ident}", link_uid=uid, now=now))
    return out


class TakLink:
    def __init__(self, get_cfg, collect):
        self.get_cfg = get_cfg
        self.collect = collect
        self.sent = 0
        self.last = None
        self.error = ""
        self.state = "off"
        self.sock = None
        self.cfg_key = None
        self.lock = threading.Lock()
        self.stop_evt = threading.Event()
        threading.Thread(target=self._loop, daemon=True, name="tak").start()

    def status(self):
        c = {**TAK_DEFAULTS, **(self.get_cfg() or {})}
        return {"enabled": bool(c["enabled"]), "state": self.state, "host": c["host"], "proto": c["proto"],
                "port": c["port"], "callsign": c["callsign"], "sent": self.sent, "last": self.last,
                "error": self.error}

    def stop(self):
        self.stop_evt.set()
        self._close()

    def _close(self):
        with self.lock:
            if self.sock:
                try:
                    self.sock.close()
                except OSError:
                    pass
            self.sock = None

    def _open(self, c):
        proto = c["proto"]
        if proto == "udp":
            return socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        raw = socket.create_connection((c["host"], int(c["port"])), timeout=5)
        if proto != "tls":
            return raw
        ctx = ssl.create_default_context(cafile=c["ca_file"] or None)
        if c["cert_file"]:
            ctx.load_cert_chain(c["cert_file"], c["key_file"] or None)
        return ctx.wrap_socket(raw, server_hostname=c["host"])

    def _send(self, c, xml):
        data = xml.encode("utf-8")
        if c["proto"] == "udp":
            self.sock.sendto(data, (c["host"], int(c["port"])))
        else:
            self.sock.sendall(data)

    def push(self, events, c=None):
        c = c or {**TAK_DEFAULTS, **(self.get_cfg() or {})}
        if not c["enabled"] or not c["host"]:
            return 0
        key = (c["host"], c["port"], c["proto"], c["ca_file"], c["cert_file"], c["key_file"])
        try:
            if self.sock is None or key != self.cfg_key:
                self._close()
                self.state = "connecting"
                self.sock, self.cfg_key = self._open(c), key
            for e in events:
                self._send(c, e)
            self.sent += len(events)
            if events:
                self.last = time.time()
            self.state, self.error = "connected", ""
            return len(events)
        except (OSError, ssl.SSLError, ValueError) as e:
            self._close()
            self.state, self.error = "error", str(e)[:120]
            return 0

    def _loop(self):
        while not self.stop_evt.wait(TAK_EVERY):
            c = {**TAK_DEFAULTS, **(self.get_cfg() or {})}
            if not c["enabled"]:
                if self.sock:
                    self._close()
                self.state, self.error = "off", ""
                continue
            nodes, drones = self.collect()
            self.push(events_for(nodes, drones, c["callsign"]), c)


class ReticulumLink:
    """LXMF alerts. Needs the `rns` and `lxmf` packages (not in requirements.txt: install them to use this)."""

    def __init__(self, get_cfg, rns_mod=None, lxmf_mod=None, identity_file=IDENTITY_FILE):
        self.get_cfg = get_cfg
        self.rns, self.lxmf = rns_mod, lxmf_mod
        self.identity_file = identity_file
        self.router = None
        self.dest = None
        self.address = ""
        self.sent = self.failed = 0
        self.error = ""
        self.state = "off"
        self.q = queue.Queue()
        self.last_alert = {}
        self.stop_evt = threading.Event()
        threading.Thread(target=self._loop, daemon=True, name="reticulum").start()

    def status(self):
        return {"enabled": bool((self.get_cfg() or {}).get("enabled")), "state": self.state,
                "address": self.address, "sent": self.sent, "failed": self.failed,
                "queued": self.q.qsize(), "error": self.error}

    def stop(self):
        self.stop_evt.set()

    def alert(self, kind, text):
        c = {**RNS_DEFAULTS, **(self.get_cfg() or {})}
        now = time.time()
        if now - self.last_alert.get(kind, 0) < ALERT_GAP:
            return
        if c["enabled"] and c["recipients"] and (c.get("send") or {}).get(kind, True):
            self.last_alert[kind] = now
            self.q.put((kind, text))

    def _load(self):
        if self.rns is None or self.lxmf is None:
            try:
                import LXMF
                import RNS
            except ImportError:
                self.state, self.error = "error", "install the rns and lxmf packages to use Reticulum"
                return False
            self.rns, self.lxmf = RNS, LXMF
        return True

    def _start(self):
        rns = self.rns
        rns.Reticulum()
        os.makedirs(os.path.dirname(self.identity_file), mode=0o700, exist_ok=True)
        if os.path.exists(self.identity_file):
            ident = rns.Identity.from_file(self.identity_file)
        else:
            ident = rns.Identity()
            ident.to_file(self.identity_file)
            os.chmod(self.identity_file, 0o600)
        store = os.path.join(os.path.dirname(self.identity_file), "lxmf")
        self.router = self.lxmf.LXMRouter(storagepath=store)
        self.dest = self.router.register_delivery_identity(ident, display_name="OUI-APEX Mesh")
        self.address = rns.hexrep(self.dest.hash, delimit=False)
        self.router.announce(self.dest.hash)

    def _deliver(self, recipient_hex, text):
        rns, lxmf = self.rns, self.lxmf
        h = bytes.fromhex(recipient_hex)
        ident = rns.Identity.recall(h)
        if ident is None:
            rns.Transport.request_path(h)
            raise OSError("no path to the recipient yet")
        dest = rns.Destination(ident, rns.Destination.OUT, rns.Destination.SINGLE, "lxmf", "delivery")
        msg = lxmf.LXMessage(dest, self.dest, text, "OUI-APEX", desired_method=lxmf.LXMessage.DIRECT)
        self.router.handle_outbound(msg)

    def _loop(self):
        while not self.stop_evt.is_set():
            c = {**RNS_DEFAULTS, **(self.get_cfg() or {})}
            if not c["enabled"]:
                self.state = "off"
                self.stop_evt.wait(2)
                continue
            if self.router is None:
                if not self._load():
                    self.stop_evt.wait(10)
                    continue
                try:
                    self._start()
                except Exception as e:
                    self.state, self.error = "error", f"{type(e).__name__}: {e}"[:120]
                    self.stop_evt.wait(10)
                    continue
            self.state = "connected"
            try:
                kind, text = self.q.get(timeout=1)
            except queue.Empty:
                continue
            for r in c["recipients"]:
                try:
                    self._deliver(r, text)
                    self.sent += 1
                    self.error = ""
                except Exception as e:
                    self.failed += 1
                    self.error = f"{type(e).__name__}: {e}"[:120]

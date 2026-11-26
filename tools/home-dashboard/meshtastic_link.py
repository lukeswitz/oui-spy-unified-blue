# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""The dashboard's Meshtastic link: alerts out over a Meshtastic radio on a serial port or on TCP (port 4403),
and the text messages the radio hears in.

Off until switched on, and every event type is off until switched on. Meshtastic airtime is shared by every radio
in range, so nothing is sent more than once a minute per event type, events are batched into one message, and
there is a minimum gap between any two packets. A message is at most 200 bytes. The dashboard never sends on a
channel that has no key of its own (the public default channel any radio in range can read).

The radio port and the channel are saved only through the authenticated settings API. The protocol bytes are in
mt_codec.py. Nothing is stored on disk: the inbox lives in memory.
"""
import copy
import random
import re
import socket
import threading
import time
from collections import Counter, deque

import mt_codec as mt

try:
    import serial
except ImportError:      # pragma: no cover - surfaced in the status
    serial = None

MESH_KINDS = ("new_devices", "drones", "lost_nodes", "nodes")
HEADS = {"new_devices": "OUI-APEX new devices: ", "drones": "OUI-APEX drones: ",
         "lost_nodes": "OUI-APEX lost nodes seen again: ", "nodes": "OUI-APEX nodes: "}
TEST_TEXT = "OUI-APEX Mesh: test message from the dashboard."
DEFAULTS = {"enabled": False, "port": "", "channel": 1, "recipients": [], "send": {k: False for k in MESH_KINDS}}
KIND_GAP = 60.0
GLOBAL_GAP = 20.0
HEARTBEAT_EVERY = 60.0
HANDSHAKE_WAIT = 15.0
RETRY_MIN, RETRY_MAX = 2.0, 30.0
BAUD = 115200
MAX_CHANNELS = 8
MAX_RECIPIENTS = 4
INBOX_MAX = 50
PENDING_MAX = 50
PENDING_TTL = 600.0
ITEM_BYTES = 60
MORE_RESERVE = len(" (+99 more)")

SERIAL_RE = re.compile(r"/dev/(?:tty|cu)[A-Za-z0-9_.\-]{1,60}|COM[0-9]{1,3}")
TCP_RE = re.compile(r"tcp:([A-Za-z0-9][A-Za-z0-9.\-]{0,200})(?::([0-9]{1,5}))?")


def defaults():
    return copy.deepcopy(DEFAULTS)


def merged(cur):
    out = defaults()
    cur = cur if isinstance(cur, dict) else {}
    out["enabled"] = cur.get("enabled") is True
    out["port"] = cur["port"] if isinstance(cur.get("port"), str) else ""
    ch = cur.get("channel")
    out["channel"] = ch if isinstance(ch, int) and not isinstance(ch, bool) and 0 <= ch < MAX_CHANNELS else out["channel"]
    rec = cur.get("recipients")
    out["recipients"] = [r for r in rec if isinstance(r, str) and mt.parse_node_id(r) is not None][:MAX_RECIPIENTS] \
        if isinstance(rec, list) else []
    send = cur.get("send") if isinstance(cur.get("send"), dict) else {}
    out["send"].update({k: send[k] is True for k in MESH_KINDS if k in send})
    return out


def clean_port(text):
    """A serial port (/dev/ttyUSB0, /dev/cu.usbmodem1, COM5) or tcp:HOST[:PORT]; nothing else is accepted, so
    the settings API cannot make the dashboard open an arbitrary file."""
    t = str(text or "").strip()
    if not t:
        return ""
    if ".." not in t and SERIAL_RE.fullmatch(t):
        return t
    m = TCP_RE.fullmatch(t)
    if m and 1 <= int(m.group(2) or mt.TCP_PORT) <= 65535:
        return t
    raise ValueError("the radio port is a serial port like /dev/ttyUSB0 or COM5, or tcp:HOST[:PORT]")


def clean_meshtastic(new, cur, board_port=""):
    """Merge an API update into the saved Meshtastic settings; every value is checked."""
    out = merged(cur)
    if "port" in new:
        out["port"] = clean_port(new["port"])
    if "channel" in new:
        try:
            ch = int(new["channel"])
        except (TypeError, ValueError):
            raise ValueError("the channel is a number from 0 to 7")
        if not 0 <= ch < MAX_CHANNELS:
            raise ValueError("the channel is a number from 0 to 7")
        out["channel"] = ch
    if "recipients" in new:
        raw = new["recipients"] or []
        if isinstance(raw, str):
            raw = re.split(r"[\s,;]+", raw.strip())
        ids = []
        for r in raw:
            r = str(r).strip().lower()
            if not r:
                continue
            if mt.parse_node_id(r) is None:
                raise ValueError("a Meshtastic node id is ! and 8 hex digits, like !0a1b2c3d")
            if r not in ids:
                ids.append(r)
        if len(ids) > MAX_RECIPIENTS:
            raise ValueError(f"at most {MAX_RECIPIENTS} recipients")
        out["recipients"] = ids
    if isinstance(new.get("send"), dict):
        out["send"].update({k: bool(new["send"][k]) for k in MESH_KINDS if k in new["send"]})
    if "enabled" in new:
        out["enabled"] = bool(new["enabled"])
    if board_port and out["port"] and out["port"] == board_port:
        raise ValueError("the board on USB already uses that port")
    if out["enabled"] and not out["port"]:
        raise ValueError("a radio port is needed")
    return out


def _item(text):
    return mt.clip_text(" ".join(str(text).split()), ITEM_BYTES)


def compose(kind, items, extra=0):
    """One message for a batch: the same item twice reads 'item x2'; what does not fit in 200 bytes becomes '(+N more)'."""
    head = HEADS[kind]
    counts = list(Counter(items).items())
    shown, hidden = [], extra
    for i, (text, n) in enumerate(counts):
        part = text if n == 1 else f"{text} x{n}"
        if shown and len((head + "; ".join(shown + [part])).encode("utf-8")) + MORE_RESERVE > mt.MAX_TEXT_BYTES:
            hidden += sum(c for _, c in counts[i:])
            break
        shown.append(part)
    return mt.clip_text(head + "; ".join(shown) + (f" (+{hidden} more)" if hidden else ""))


class Outbox:
    """What is waiting to go out. Each event type holds its items and releases them as one message at most once
    every kind_gap seconds. Items older than ttl are dropped, and each type keeps at most cap items."""

    def __init__(self, kind_gap=KIND_GAP, ttl=PENDING_TTL, cap=PENDING_MAX):
        self.kind_gap, self.ttl, self.cap = kind_gap, ttl, cap
        self.items = {k: deque() for k in MESH_KINDS}
        self.over = {k: 0 for k in MESH_KINDS}
        self.last = {}
        self.test = False

    def add(self, kind, text, now):
        q = self.items[kind]
        q.append((now, _item(text)))
        while len(q) > self.cap:
            q.popleft()
            self.over[kind] += 1

    def queue_test(self):
        if self.test:
            return False
        self.test = True
        return True

    def pending(self):
        return sum(len(q) for q in self.items.values()) + (1 if self.test else 0)

    def next(self, now):
        if self.test:
            self.test = False
            return "test", TEST_TEXT
        for kind in MESH_KINDS:
            q = self.items[kind]
            while q and now - q[0][0] > self.ttl:
                q.popleft()
            if q and now - self.last.get(kind, -1e18) >= self.kind_gap:
                items, extra = [t for _, t in q], self.over[kind]
                q.clear()
                self.over[kind] = 0
                self.last[kind] = now
                return kind, compose(kind, items, extra)
        return None


class SocketTransport:
    def __init__(self, sock):
        self.sock = sock
        sock.settimeout(0.2)

    def send(self, data):
        self.sock.settimeout(5)
        try:
            self.sock.sendall(data)
        finally:
            self.sock.settimeout(0.2)

    def recv(self):
        try:
            data = self.sock.recv(4096)
        except socket.timeout:
            return b""
        if not data:
            raise ConnectionError("the radio closed the connection")
        return data

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


class SerialTransport:
    def __init__(self, ser):
        self.ser = ser

    def send(self, data):
        self.ser.write(data)
        self.ser.flush()

    def recv(self):
        return self.ser.read(max(1, self.ser.in_waiting))

    def close(self):
        try:
            self.ser.close()
        except OSError:
            pass


def open_transport(target):
    target = clean_port(target)
    m = TCP_RE.fullmatch(target)
    if m:
        return SocketTransport(socket.create_connection((m.group(1), int(m.group(2) or mt.TCP_PORT)), timeout=5))
    if serial is None:
        raise OSError("pyserial is not installed")
    ser = serial.Serial()
    ser.port, ser.baudrate, ser.timeout, ser.write_timeout = target, BAUD, 0.2, 5
    ser.dtr = ser.rts = False
    ser.open()
    return SerialTransport(ser)


class LinkError(Exception):
    pass


class MeshtasticLink:
    def __init__(self, get_cfg, opener=None, kind_gap=KIND_GAP, global_gap=GLOBAL_GAP, heartbeat=HEARTBEAT_EVERY,
                 handshake_wait=HANDSHAKE_WAIT, retry=(RETRY_MIN, RETRY_MAX), cfg_ttl=0.5, autostart=True):
        self.get_cfg = get_cfg
        self.opener = opener or open_transport
        self.global_gap, self.heartbeat, self.handshake_wait, self.retry = global_gap, heartbeat, handshake_wait, retry
        self.cfg_ttl, self._cfg_at, self._cfg_val = cfg_ttl, -1e18, None
        self.hs_start, self.hs_resent, self.last_any = 0.0, False, -1e18
        self.lock = threading.Lock()
        self.outbox = Outbox(kind_gap)
        self.wire = deque()
        self.state, self.error = "off", ""
        self.sent = self.failed = self.heard = 0
        self.last = None
        self.inbox = deque(maxlen=INBOX_MAX)
        self.channels, self.names, self.my_node = {}, {}, 0
        self.tr = None
        self.cid = 0
        self.ready = False
        self.stop_evt = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True, name="meshtastic")
        if autostart:
            self.thread.start()

    def _cfg(self):
        now = time.monotonic()
        if self._cfg_val is None or now - self._cfg_at >= self.cfg_ttl:
            self._cfg_val, self._cfg_at = merged(self.get_cfg() or {}), now
        return self._cfg_val

    def status(self):
        cfg = self._cfg()
        with self.lock:
            chans = [{"index": i, "name": mt.channel_label(i, c["name"]), "role": "primary" if c["role"] == 1 else "secondary",
                      "private": c["psk_len"] >= 16} for i, c in sorted(self.channels.items()) if c["role"] in (1, 2)]
            mine = self.channels.get(cfg["channel"])
            return {"enabled": bool(cfg["enabled"]), "state": self.state if cfg["enabled"] else "off", "error": self.error,
                    "radio": mt.node_id(self.my_node) if self.my_node else "",
                    "radio_name": self.names.get(self.my_node, ""), "channels": chans,
                    "channel_name": mt.channel_label(cfg["channel"], mine["name"]) if mine else "",
                    "sent": self.sent, "failed": self.failed, "queued": self.outbox.pending() + len(self.wire),
                    "heard": self.heard, "last": self.last, "inbox": list(self.inbox)[::-1]}

    def stop(self):
        self.stop_evt.set()
        self._close()
        if self.thread.is_alive():
            self.thread.join(3)

    def event(self, kind, text):
        cfg = self._cfg()
        if kind in MESH_KINDS and cfg["enabled"] and cfg["send"].get(kind):
            with self.lock:
                self.outbox.add(kind, text, time.monotonic())

    def test(self):
        """Queue the test message as last saved. Returns (ok, why)."""
        cfg = self._cfg()
        if not cfg["enabled"]:
            return False, "turn the Meshtastic link on first"
        with self.lock:
            if self.state != "connected":
                return False, "the radio is not connected"
        why = self._channel_problem(cfg["channel"])
        if why:
            return False, why
        with self.lock:
            return (True, "queued") if self.outbox.queue_test() else (False, "a test is already waiting")

    def _channel_problem(self, index):
        with self.lock:
            c = self.channels.get(index)
        if c is None or c["role"] not in (1, 2):
            return f"channel {index} is not on the radio"
        if c["psk_len"] < 16:
            return f"channel {index} has no key of its own: the dashboard does not send on the public channel"
        return ""

    def _set(self, **kw):
        with self.lock:
            for k, v in kw.items():
                setattr(self, k, v)

    def _close(self):
        tr, self.tr = self.tr, None
        if tr:
            tr.close()

    def _send_raw(self, payload):
        tr = self.tr
        if tr is None:
            raise LinkError("not connected")
        tr.send(mt.frame(payload))

    def _run(self):
        wait = self.retry[0]
        while not self.stop_evt.is_set():
            cfg = self._cfg()
            if not cfg["enabled"] or not cfg["port"]:
                self._set(state="off", ready=False)
                self.stop_evt.wait(0.5)
                continue
            try:
                self._session(cfg["port"])
                wait = self.retry[0]
            except (OSError, LinkError) as e:
                if self.stop_evt.is_set():
                    break
                self._set(state="retrying", error=(str(e) or type(e).__name__)[:120], ready=False)
                self._close()
                self.stop_evt.wait(wait)
                wait = min(wait * 2, self.retry[1])
            except Exception as e:
                if self.stop_evt.is_set():
                    break
                self._set(state="error", error=f"{type(e).__name__}: {e}"[:120], ready=False)
                self._close()
                self.stop_evt.wait(5)
        self._close()

    def _same(self, port):
        cur = self._cfg()
        return cur["enabled"] and cur["port"] == port

    def _want_config(self):
        self.cid = random.getrandbits(32) or 1
        self.ready = False
        self.hs_start, self.hs_resent = time.monotonic(), False
        self._send_raw(mt.to_radio_want_config(self.cid))

    def _session(self, port):
        self._set(state="connecting", error="", channels={}, names={}, my_node=0, ready=False)
        self.wire.clear()
        tr = self.tr = self.opener(port)
        deframer = mt.Deframer()
        last_beat = time.monotonic()
        self._want_config()
        while not self.stop_evt.is_set() and self._same(port):
            for payload in deframer.feed(tr.recv()):
                self._on_radio(mt.parse_from_radio(payload))
            now = time.monotonic()
            if not self.ready:
                if now - self.hs_start > self.handshake_wait * 2:
                    raise LinkError("the radio did not answer: is a Meshtastic radio on that port?")
                if not self.hs_resent and now - self.hs_start > self.handshake_wait:
                    self._want_config()
                    self.hs_resent = True
                continue
            if now - last_beat >= self.heartbeat:
                last_beat = now
                self._send_raw(mt.to_radio_heartbeat())
            if now - self.last_any >= self.global_gap:
                if not self.wire:
                    self._expand(now)
                if self.wire:
                    self.last_any = now
                    self._send_packet()
        self._close()

    def _expand(self, now):
        with self.lock:
            nxt = self.outbox.next(now)
        if not nxt:
            return
        cfg = self._cfg()
        why = self._channel_problem(cfg["channel"])
        if why:
            with self.lock:
                self.failed += 1
                self.error = why
            return
        text = nxt[1]
        self.wire.append((mt.BROADCAST, text))
        for r in cfg["recipients"]:
            num = mt.parse_node_id(r)
            if num is not None:
                self.wire.append((num, text))

    def _send_packet(self):
        to, text = self.wire.popleft()
        try:
            self._send_raw(mt.to_radio_text(text, self._cfg()["channel"], random.getrandbits(32) or 1, to))
        except OSError:
            with self.lock:
                self.failed += 1
            raise
        with self.lock:
            self.sent += 1
            self.last = time.time()
            self.error = ""

    def _on_radio(self, m):
        kind = m["kind"]
        if kind == "my_info":
            self._set(my_node=m["node"])
        elif kind == "node_info":
            with self.lock:
                self.names[m["node"]] = m["long"] or m["short"]
        elif kind == "channel":
            with self.lock:
                self.channels[m["index"]] = m
        elif kind == "config_complete":
            if m["id"] == self.cid:
                self._set(state="connected", error="", ready=True)
        elif kind == "rebooted":
            self._set(state="connecting")
            self._want_config()
        elif kind == "packet" and m["port"] == mt.PORT_TEXT and m["payload"]:
            with self.lock:
                if m["from"] == self.my_node:
                    return
                self.heard += 1
                self.inbox.append({"ts": time.time(), "from": mt.node_id(m["from"]), "name": self.names.get(m["from"], ""),
                                   "channel": m["channel"],
                                   "text": mt.clip_text(m["payload"].decode("utf-8", "replace"))})

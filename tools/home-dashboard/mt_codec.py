# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""The part of the Meshtastic client stream API the dashboard needs: framing, a minimal protobuf wire codec and
the few messages it sends and reads. Written from the field numbers in github.com/meshtastic/protobufs and the
client API page (meshtastic.org/docs/development/device/client-api); no Meshtastic code or .proto text is included.

    Framing:     0x94 0xC3, uint16 big-endian length, protobuf; a length over 512 is corruption
    ToRadio:     packet = 1, want_config_id = 3, heartbeat = 7 (mesh.proto)
    Heartbeat:   nonce = 1
    FromRadio:   id = 1, packet = 2, my_info = 3, node_info = 4, config_complete_id = 7, rebooted = 8, channel = 10
    MeshPacket:  from = 1 (fixed32), to = 2 (fixed32), channel = 3, decoded = 4, id = 6 (fixed32),
                 rx_time = 7 (fixed32), hop_limit = 9
    Data:        portnum = 1, payload = 2
    MyNodeInfo:  my_node_num = 1
    NodeInfo:    num = 1, user = 2;  User: long_name = 2, short_name = 3
    Channel:     index = 1, settings = 2, role = 3 (0 disabled, 1 primary, 2 secondary), channel.proto
    ChannelSettings: psk = 2, name = 3
    PortNum:     TEXT_MESSAGE_APP = 1 (portnums.proto)
"""
import struct

START1, START2 = 0x94, 0xC3
MAX_PAYLOAD = 512
TCP_PORT = 4403
PORT_TEXT = 1
BROADCAST = 0xFFFFFFFF
HOP_LIMIT = 3
MAX_TEXT_BYTES = 200


def _varint(n):
    n &= 0xFFFFFFFFFFFFFFFF
    out = bytearray()
    while n > 0x7F:
        out.append((n & 0x7F) | 0x80)
        n >>= 7
    out.append(n)
    return bytes(out)


def _key(num, wire):
    return _varint((num << 3) | wire)


def f_varint(num, v):
    return _key(num, 0) + _varint(v)


def f_fixed32(num, v):
    return _key(num, 5) + struct.pack("<I", v & 0xFFFFFFFF)


def f_bytes(num, data):
    data = bytes(data)
    return _key(num, 2) + _varint(len(data)) + data


def read_fields(buf):
    """Yield (number, wire type, value): an int for varint and fixed fields, bytes for length-delimited ones.
    A truncated or unknown-wire field ends the read; what came before it is kept."""
    i, n = 0, len(buf)

    def varint():
        nonlocal i
        shift = v = 0
        while i < n and shift < 64:
            c = buf[i]
            i += 1
            v |= (c & 0x7F) << shift
            if not c & 0x80:
                return v
            shift += 7
        return None

    while i < n:
        key = varint()
        if key is None:
            return
        num, wire = key >> 3, key & 7
        if wire == 0:
            v = varint()
            if v is None:
                return
            yield num, wire, v
        elif wire == 1:
            if i + 8 > n:
                return
            yield num, wire, struct.unpack_from("<Q", buf, i)[0]
            i += 8
        elif wire == 2:
            ln = varint()
            if ln is None or i + ln > n:
                return
            yield num, wire, bytes(buf[i:i + ln])
            i += ln
        elif wire == 5:
            if i + 4 > n:
                return
            yield num, wire, struct.unpack_from("<I", buf, i)[0]
            i += 4
        else:
            return


def frame(payload):
    if len(payload) > MAX_PAYLOAD:
        raise ValueError("Meshtastic frame too long")
    return bytes([START1, START2]) + struct.pack(">H", len(payload)) + bytes(payload)


class Deframer:
    """Cuts a byte stream into payloads. Bytes outside a frame (the radio's debug text) are dropped; a bad
    header or a length over 512 sends the reader back to looking for 0x94."""

    def __init__(self):
        self.buf = bytearray()

    def feed(self, data):
        self.buf += data
        out = []
        while True:
            at = self.buf.find(bytes([START1]))
            if at < 0:
                self.buf.clear()
                return out
            del self.buf[:at]
            if len(self.buf) < 2:
                return out
            if self.buf[1] != START2:
                del self.buf[:1]
                continue
            if len(self.buf) < 4:
                return out
            ln = (self.buf[2] << 8) | self.buf[3]
            if ln > MAX_PAYLOAD:
                del self.buf[:1]
                continue
            if len(self.buf) < 4 + ln:
                return out
            if ln:
                out.append(bytes(self.buf[4:4 + ln]))
            del self.buf[:4 + ln]


def clip_text(text, limit=MAX_TEXT_BYTES):
    """Text as UTF-8 of at most limit bytes, cut on a character boundary, control characters turned into spaces."""
    clean = "".join(c if c >= " " and c != "\x7f" else " " for c in str(text)).strip()
    raw = clean.encode("utf-8")
    if len(raw) <= limit:
        return clean
    return raw[:limit].decode("utf-8", "ignore").rstrip()


def to_radio_want_config(config_id):
    return f_varint(3, config_id)


def to_radio_heartbeat(nonce=0):
    return f_bytes(7, f_varint(1, nonce) if nonce else b"")


def to_radio_text(text, channel, packet_id, to=BROADCAST):
    data = f_varint(1, PORT_TEXT) + f_bytes(2, clip_text(text).encode("utf-8"))
    pkt = f_fixed32(2, to)
    if channel:
        pkt += f_varint(3, channel)
    pkt += f_bytes(4, data) + f_fixed32(6, packet_id) + f_varint(9, HOP_LIMIT)
    return f_bytes(1, pkt)


def node_id(num):
    return "!" + format(num & 0xFFFFFFFF, "08x")


def parse_node_id(text):
    """'!0a1b2c3d' -> int, or None when it is not a Meshtastic node id."""
    t = str(text).strip().lower()
    if len(t) == 9 and t[0] == "!" and all(c in "0123456789abcdef" for c in t[1:]):
        return int(t[1:], 16)
    return None


def _packet(b):
    p = {"kind": "packet", "from": 0, "to": 0, "channel": 0, "id": 0, "port": 0, "payload": b"", "rx_time": 0}
    for num, wire, v in read_fields(b):
        if num == 1 and wire == 5:
            p["from"] = v
        elif num == 2 and wire == 5:
            p["to"] = v
        elif num == 3 and wire == 0:
            p["channel"] = v
        elif num == 4 and wire == 2:
            for dn, dw, dv in read_fields(v):
                if dn == 1 and dw == 0:
                    p["port"] = dv
                elif dn == 2 and dw == 2:
                    p["payload"] = dv
        elif num == 6 and wire == 5:
            p["id"] = v
        elif num == 7 and wire == 5:
            p["rx_time"] = v
    return p


def _node(b):
    n = {"kind": "node_info", "node": 0, "long": "", "short": ""}
    for num, wire, v in read_fields(b):
        if num == 1 and wire == 0:
            n["node"] = v
        elif num == 2 and wire == 2:
            for un, uw, uv in read_fields(v):
                if un == 2 and uw == 2:
                    n["long"] = uv.decode("utf-8", "replace")
                elif un == 3 and uw == 2:
                    n["short"] = uv.decode("utf-8", "replace")
    return n


def _channel(b):
    c = {"kind": "channel", "index": 0, "role": 0, "name": "", "psk_len": 0}
    for num, wire, v in read_fields(b):
        if num == 1 and wire == 0:
            c["index"] = v
        elif num == 2 and wire == 2:
            for sn, sw, sv in read_fields(v):
                if sn == 2 and sw == 2:
                    c["psk_len"] = len(sv)
                elif sn == 3 and sw == 2:
                    c["name"] = sv.decode("utf-8", "replace")
        elif num == 3 and wire == 0:
            c["role"] = v
    return c


def parse_from_radio(payload):
    """One FromRadio as a dict with a 'kind': packet, my_info, node_info, channel, config_complete, rebooted or other."""
    for num, wire, v in read_fields(payload):
        if num == 2 and wire == 2:
            return _packet(v)
        if num == 3 and wire == 2:
            for mn, mw, mv in read_fields(v):
                if mn == 1 and mw == 0:
                    return {"kind": "my_info", "node": mv}
            return {"kind": "other"}
        if num == 4 and wire == 2:
            return _node(v)
        if num == 7 and wire == 0:
            return {"kind": "config_complete", "id": v}
        if num == 8 and wire == 0 and v:
            return {"kind": "rebooted"}
        if num == 10 and wire == 2:
            return _channel(v)
    return {"kind": "other"}


def channel_label(index, name):
    return name if name else ("LongFast" if index == 0 else f"Channel {index}")

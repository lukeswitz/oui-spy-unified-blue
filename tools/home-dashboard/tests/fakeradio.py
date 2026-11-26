# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""A stand-in for a Meshtastic radio's client stream, on one end of a socket pair. No real radio is involved."""
import os
import socket
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import mt_codec as mt  # noqa: E402
import meshtastic_link as ml  # noqa: E402

PUBLIC_PSK = b"\x01"
FLEET_PSK = bytes(range(32))
CHANNELS = [(0, 1, b"", PUBLIC_PSK), (1, 2, b"Fleet", FLEET_PSK), (2, 0, b"", b"")]
ME = 0x0A1B2C3D
PEER = 0x0B0C0D0E


def from_radio(*fields):
    return mt.frame(b"".join(fields))


def decode_to_radio(payload):
    """What the radio understood of one ToRadio the dashboard sent."""
    for num, wire, v in mt.read_fields(payload):
        if num == 3 and wire == 0:
            return {"kind": "want_config", "id": v}
        if num == 7 and wire == 2:
            return {"kind": "heartbeat"}
        if num == 1 and wire == 2:
            p = mt._packet(v)
            hop = [x for n, w, x in mt.read_fields(v) if n == 9]
            return {"kind": "text" if p["port"] == mt.PORT_TEXT else "packet", "to": p["to"], "channel": p["channel"],
                    "id": p["id"], "from": p["from"], "text": p["payload"].decode("utf-8", "replace"),
                    "hop": hop[0] if hop else 0}
    return {"kind": "other"}


class FakeRadio:
    def __init__(self, channels=CHANNELS, silent=False, debug_noise=True, sock=None):
        self.host, self.dev = (None, sock) if sock else socket.socketpair()
        self.dev.settimeout(0.1)
        self.channels, self.silent, self.noise = channels, silent, debug_noise
        self.rx = []
        self.stamps = []
        self.handshakes = 0
        self.stop_evt = threading.Event()
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def transport(self):
        return ml.SocketTransport(self.host)

    def _send(self, data):
        try:
            self.dev.sendall(data)
        except OSError:
            pass

    def _config(self, want_id):
        out = [b"booting radio\r\n" if self.noise else b""]
        out.append(from_radio(mt.f_varint(1, 1), mt.f_bytes(3, mt.f_varint(1, ME))))
        for num, long, short in ((ME, "Dashboard Radio", "DB"), (PEER, "North Gate", "NG")):
            user = mt.f_bytes(2, long.encode()) + mt.f_bytes(3, short.encode())
            out.append(from_radio(mt.f_bytes(4, mt.f_varint(1, num) + mt.f_bytes(2, user))))
        for idx, role, name, psk in self.channels:
            settings = mt.f_bytes(2, psk) + mt.f_bytes(3, name)
            out.append(from_radio(mt.f_bytes(10, mt.f_varint(1, idx) + mt.f_bytes(2, settings) + mt.f_varint(3, role))))
        out.append(from_radio(mt.f_varint(7, want_id)))
        self._send(b"".join(out))

    def inject_text(self, sender, text, channel=1, to=mt.BROADCAST):
        data = mt.f_varint(1, mt.PORT_TEXT) + mt.f_bytes(2, text.encode() if isinstance(text, str) else text)
        pkt = (mt.f_fixed32(1, sender) + mt.f_fixed32(2, to) + mt.f_varint(3, channel) + mt.f_bytes(4, data)
               + mt.f_fixed32(6, 77))
        self._send(from_radio(mt.f_bytes(2, pkt)))

    def reboot(self):
        self._send(from_radio(mt.f_varint(8, 1)))

    def hang_up(self):
        self.stop_evt.set()
        for s in (self.dev, self.host):
            if s is None:
                continue
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            s.close()

    def texts(self):
        return [m for m in self.rx if m["kind"] == "text"]

    def _run(self):
        de = mt.Deframer()
        while not self.stop_evt.is_set():
            try:
                data = self.dev.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                return
            if not data:
                return
            for payload in de.feed(data):
                m = decode_to_radio(payload)
                self.rx.append(m)
                self.stamps.append(time.monotonic())
                if m["kind"] == "want_config":
                    self.handshakes += 1
                    if not self.silent:
                        self._config(m["id"])

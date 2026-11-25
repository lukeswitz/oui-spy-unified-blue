# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""A stand-in for the board's end of the link (firmware src/usb_link.cpp), on one end of a socket pair."""
import os
import socket
import struct
import sys
import threading

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import board_link as bl  # noqa: E402

DEVICE_INFO = b"0.7.0\x00OUISPY-A1B2\x00xiao_s3\x00mgr\x00150000\x00proto=1\x00epoch=00000001\x00boot=3\x00spool=1"


def detection(engine=0, mac=(0x0A, 0x1B, 0x2C, 0x3D, 0x4E, 0x5F), rssi=-60, channel=6, ms=1000, method=0,
              source=b"", ext=b""):
    head = bytes([engine]) + bytes(mac) + struct.pack("<bB", rssi, channel) + struct.pack("<IB", ms, method)
    return head + source.ljust(5, b"\0") + ext


def mesh_status(live, details=(), signal=()):
    """live: [(id, role, engines, fw, board_code, temp)]"""
    b = bytes([1, len(live), len(live)]) + struct.pack("<II", 10, 5) + bytes([len(live)])
    for nid, role, eng, fw, _, _ in live:
        b += nid.encode() + b"\0" + bytes([role, eng]) + struct.pack("<I", fw)
    b += bytes(code for *_, code, _ in live) + b"".join(struct.pack("<b", t) for *_, t in live)
    b += struct.pack("<I", 0)
    if details:
        body = b"".join(bytes.fromhex(i) + struct.pack("<IB", fw, code) + struct.pack("<I", up)
                        + bytes([fm, fu, pr, age]) for i, fw, code, up, fm, fu, pr, age in details)
        b += bytes([1, len(body)]) + body
    if signal:
        body = b""
        for nid, hears in signal:
            body += bytes.fromhex(nid) + bytes([len(hears)])
            for hid, r in hears:
                body += bytes.fromhex(hid) + bytes([0x80 if r is None else r & 0xFF])
        b += bytes([3, len(body)]) + body
    return b


class FakeBoard:
    def __init__(self):
        self.host_sock, self.board_sock = socket.socketpair()
        self.subscribed = set()
        self.writes = []
        self.reads = {bl.CHR_DEVICE_INFO: DEVICE_INFO}
        self.ids = [bl.CHR_DEVICE_INFO, bl.CHR_ENGINE_CONTROL, bl.CHR_DETECTION_EVENTS, bl.CHR_MESH_STATUS]
        self.refuse_writes = False
        self.stop = False
        self.parser = bl.FrameParser()
        threading.Thread(target=self._run, daemon=True).start()

    def transport(self):
        return bl.SocketTransport(self.host_sock)

    def notify(self, cid, payload):
        self.board_sock.sendall(bl.encode(bl.T.NOTIFY, cid, payload))

    def close(self):
        self.stop = True
        for s in (self.host_sock, self.board_sock):
            try:
                s.close()
            except OSError:
                pass

    def _frames(self, data):
        buf, i, out = bytearray(data), 0, []
        while i + bl.HEADER + 2 <= len(buf):
            n = buf[i + 5] | (buf[i + 6] << 8)
            end = i + bl.HEADER + n + 2
            if end > len(buf):
                break
            out.append((buf[i + 2], buf[i + 3] | (buf[i + 4] << 8), bytes(buf[i + bl.HEADER:i + bl.HEADER + n])))
            i = end
        return out

    def _run(self):
        self.board_sock.settimeout(0.2)
        while not self.stop:
            try:
                data = self.board_sock.recv(4096)
            except socket.timeout:
                continue
            except OSError:
                return
            if not data:
                return
            for t, cid, p in self._frames(data):
                try:
                    self._handle(t, cid, p)
                except OSError:
                    return

    def _send(self, t, cid, payload=b""):
        self.board_sock.sendall(bl.encode(t, cid, payload))

    def _handle(self, t, cid, p):
        if t == bl.T.HELLO:
            body = bytes([1]) + struct.pack("<H", bl.MAX_PAYLOAD) + bytes([len(self.ids)])
            body += b"".join(struct.pack("<H", i) for i in self.ids)
            self._send(bl.T.HELLO_ACK, 0, body)
        elif t == bl.T.PING:
            self._send(bl.T.PONG, 0)
        elif t in (bl.T.WRITE, bl.T.WRITE_NO_ACK):
            self.writes.append((cid, p))
            if t == bl.T.WRITE:
                self._send(bl.T.WRITE_ACK, cid, bytes([1 if self.refuse_writes or cid not in self.ids else 0]))
        elif t == bl.T.READ:
            v = self.reads.get(cid)
            self._send(bl.T.READ_RSP, cid, bytes([1]) if v is None else bytes([0]) + v)
        elif t == bl.T.SUBSCRIBE:
            ok = cid in self.ids
            if ok and p[0]:
                self.subscribed.add(cid)
            self._send(bl.T.SUBSCRIBE_ACK, cid, bytes([0 if ok else 1]))

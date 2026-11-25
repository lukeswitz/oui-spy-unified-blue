# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""The OUI-APEX board link: the BLE GATT characteristics carried over USB serial or the
USB network port (firmware src/usb_link.cpp, app lib/core/link/link_frame.dart).

Frame: A5 5A | type | id lo, hi | length lo, hi | payload | CRC-16/CCITT-FALSE over
type..payload, low byte first. The id is the first 32 bits of the characteristic UUID.
"""
import socket
import threading
import time

SYNC0, SYNC1 = 0xA5, 0x5A
PROTO_VERSION = 1
HEADER = 7
MAX_PAYLOAD = 1024


class T:
    HELLO = 0x01
    WRITE = 0x02
    WRITE_NO_ACK = 0x03
    READ = 0x04
    SUBSCRIBE = 0x05
    PING = 0x06
    HELLO_ACK = 0x81
    WRITE_ACK = 0x82
    READ_RSP = 0x84
    SUBSCRIBE_ACK = 0x85
    PONG = 0x86
    NOTIFY = 0x90


DEVICE_TYPES = {T.HELLO_ACK, T.WRITE_ACK, T.READ_RSP, T.SUBSCRIBE_ACK, T.PONG, T.NOTIFY}

# GATT characteristic ids (low 16 bits of the 0000xxxx-0a15-4b70-ba00-c010ae1ba01c UUIDs, companion gatt_uuids.dart)
CHR_DEVICE_INFO = 0x0001
CHR_ENGINE_CONTROL = 0x0002
CHR_DETECTION_EVENTS = 0x0010
CHR_DEVICE_STATUS = 0x0011
CHR_MESH_STATUS = 0x0061


class LinkError(Exception):
    pass


def crc16(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def encode(ftype, cid, payload=b""):
    payload = bytes(payload)
    if len(payload) > MAX_PAYLOAD:
        raise ValueError(f"link payload {len(payload)} > {MAX_PAYLOAD}")
    body = bytes([ftype, cid & 0xFF, (cid >> 8) & 0xFF, len(payload) & 0xFF, len(payload) >> 8]) + payload
    return bytes([SYNC0, SYNC1]) + body + crc16(body).to_bytes(2, "little")


class FrameParser:
    """Pulls board frames out of a byte stream that also carries boot log text."""

    def __init__(self):
        self.buf = bytearray()
        self.crc_errors = 0
        self.bytes_in = 0

    def add(self, data):
        self.bytes_in += len(data)
        self.buf += data
        out = []
        i = 0
        buf = self.buf
        while True:
            start = buf.find(SYNC0, i)
            if start < 0:
                buf.clear()
                return out
            if start + 1 >= len(buf):
                del buf[:start]
                return out
            if buf[start + 1] != SYNC1:
                i = start + 1
                continue
            if start + HEADER > len(buf):
                del buf[:start]
                return out
            if buf[start + 2] not in DEVICE_TYPES:
                i = start + 1
                continue
            n = buf[start + 5] | (buf[start + 6] << 8)
            if n > MAX_PAYLOAD:
                i = start + 1
                continue
            end = start + HEADER + n + 2
            if end > len(buf):
                del buf[:start]
                return out
            want = buf[end - 2] | (buf[end - 1] << 8)
            if crc16(buf[start + 2:start + HEADER + n]) != want:
                self.crc_errors += 1
                i = start + 1
                continue
            out.append((buf[start + 2], buf[start + 3] | (buf[start + 4] << 8),
                        bytes(buf[start + HEADER:start + HEADER + n])))
            i = end


class SocketTransport:
    """A TCP connection, for the board's USB network port (192.168.7.1:4700)."""

    def __init__(self, sock):
        self.sock = sock
        self.sock.settimeout(0.5)

    @classmethod
    def connect(cls, host, port, timeout=3.0):
        s = socket.create_connection((host, port), timeout=timeout)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        return cls(s)

    def read(self):
        try:
            data = self.sock.recv(4096)
        except socket.timeout:
            return b""
        if not data:
            raise LinkError("connection closed")
        return data

    def write(self, data):
        self.sock.sendall(data)

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


class SerialTransport:
    """USB serial. A plain open and close: DTR and RTS are never set one at a time,
    which on the native-USB ESP32 would pulse a reset."""

    def __init__(self, ser):
        self.ser = ser

    @classmethod
    def open(cls, serial_mod, port, baud=115200):
        return cls(serial_mod.Serial(port, baud, timeout=0.5))

    def read(self):
        try:
            return self.ser.read(self.ser.in_waiting or 1)
        except Exception as e:
            raise LinkError(str(e)) from e

    def write(self, data):
        try:
            self.ser.write(data)
            self.ser.flush()
        except Exception as e:
            raise LinkError(str(e)) from e

    def close(self):
        try:
            self.ser.close()
        except Exception:
            pass


class LinkSession:
    """One link to one board. start() runs a reader thread; request calls block on it."""

    PING_EVERY = 1.0
    HELLO_TIMEOUT = 3.0
    DEAD_AFTER = 30.0

    def __init__(self, transport, on_notify=None, on_close=None):
        self.transport = transport
        self.on_notify = on_notify or (lambda cid, payload: None)
        self.on_close = on_close or (lambda: None)
        self.parser = FrameParser()
        self.ids = []
        self.max_payload = MAX_PAYLOAD
        self.closed = False
        self.last_frame = time.time()
        self._req_lock = threading.Lock()
        self._cond = threading.Condition()
        self._want = None
        self._got = None
        self._thread = None

    def start(self):
        self._thread = threading.Thread(target=self._reader, daemon=True, name="board-link")
        self._thread.start()
        ack = self._request(T.HELLO, 0, bytes([PROTO_VERSION]), T.HELLO_ACK, self.HELLO_TIMEOUT)
        if len(ack) < 4:
            raise LinkError("short hello reply")
        self.max_payload = ack[1] | (ack[2] << 8)
        n = ack[3]
        if len(ack) < 4 + n * 2:
            raise LinkError("truncated characteristic list")
        self.ids = [ack[4 + i * 2] | (ack[5 + i * 2] << 8) for i in range(n)]

    def write(self, cid, value, timeout=5.0):
        if len(value) > self.max_payload:
            raise LinkError(f"{len(value)} bytes exceeds {self.max_payload}")
        rsp = self._request(T.WRITE, cid, value, T.WRITE_ACK, timeout, cid)
        if not rsp or rsp[0] != 0:
            raise LinkError(f"board refused the write to 0x{cid:x}")

    def read(self, cid, timeout=5.0):
        rsp = self._request(T.READ, cid, b"", T.READ_RSP, timeout, cid)
        if not rsp or rsp[0] != 0:
            raise LinkError(f"board refused the read of 0x{cid:x}")
        return rsp[1:]

    def subscribe(self, cid, on=True, timeout=5.0):
        rsp = self._request(T.SUBSCRIBE, cid, bytes([1 if on else 0]), T.SUBSCRIBE_ACK, timeout, cid)
        if not rsp or rsp[0] != 0:
            raise LinkError(f"board refused to notify 0x{cid:x}")

    def ping(self):
        self._request(T.PING, 0, b"", T.PONG, self.HELLO_TIMEOUT)

    def close(self):
        if self.closed:
            return
        self.closed = True
        with self._cond:
            self._cond.notify_all()
        self.transport.close()
        self.on_close()

    def _request(self, ftype, cid, payload, expect, timeout, expect_id=0):
        with self._req_lock:
            if self.closed:
                raise LinkError("link closed")
            with self._cond:
                self._want = (expect, expect_id)
                self._got = None
            before = self.parser.bytes_in
            self.transport.write(encode(ftype, cid, payload))
            deadline = time.time() + timeout
            with self._cond:
                while self._got is None and not self.closed:
                    left = deadline - time.time()
                    if left <= 0:
                        raise LinkError(f"no reply to 0x{ftype:02x} (rx +{self.parser.bytes_in - before} B, "
                                        f"crc errors {self.parser.crc_errors})")
                    self._cond.wait(left)
                got, self._want = self._got, None
            if got is None:
                raise LinkError("link closed")
            return got

    def _reader(self):
        last_ping = time.time()
        try:
            while not self.closed:
                data = self.transport.read()
                now = time.time()
                for ftype, cid, payload in self.parser.add(data) if data else ():
                    self.last_frame = now
                    if ftype == T.NOTIFY:
                        self.on_notify(cid, payload)
                        continue
                    with self._cond:
                        if self._want == (ftype, cid) and self._got is None:
                            self._got = payload
                            self._cond.notify_all()
                if self.ids and now - self.last_frame > self.DEAD_AFTER:
                    raise LinkError("board stopped answering")
                if self.ids and now - last_ping >= self.PING_EVERY and not self._req_lock.locked():
                    last_ping = now
                    threading.Thread(target=self._ping_quiet, daemon=True).start()
        except (LinkError, OSError):
            pass
        finally:
            self.close()

    def _ping_quiet(self):
        try:
            self.ping()
        except (LinkError, OSError):
            pass

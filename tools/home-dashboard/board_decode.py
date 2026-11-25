# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT

"""Decoders for what the board sends over the link, mirroring companion/lib/core/ble/ble_protocol.dart
(decodeDetection, decodeMeshStatus) and src/ble_gatt.cpp (device info)."""
import re
import struct

ENGINES = ["detector", "flock_ble", "flock_wifi", "foxhunter", "sky_spy", "unipwn", "wardrive", "pcap", "sdr"]
ENGINE_LABEL = {"detector": "Detector", "flock_ble": "Flock BLE", "flock_wifi": "Flock WiFi",
                "foxhunter": "Foxhunter", "sky_spy": "Sky Spy", "unipwn": "UniPwn",
                "wardrive": "Wardrive", "pcap": "PCAP", "sdr": "SDR"}

METHODS = {
    "flock_wifi": ["oui_addr1", "oui_addr2", "oui_addr3", "ssid", "wildcard_probe", "wildcard_probe_ie_sig"],
    "flock_ble": ["oui_match", "name_match", "mfg_id", "raven_uuid", "gatt_uuid", "nordic_dfu"],
    "sky_spy": ["odid_ble", "odid_nan", "odid_beacon", "drone_vendor"],
    "detector": ["ble_watchlist", "wifi_watchlist", "tracker", "flipper", "deauth_storm", "probe_ssid",
                 "pwnagotchi", "glasses", "axon", "camera", "amazon", "evil_twin", "karma", "mesh",
                 "join_flood", "tag_flood", "beacon_flood", "wearable_cam", "vehicle", "drone_ble"],
    "foxhunter": ["ble_proximity", "wifi_proximity"],
    "wardrive": ["wifi_ap", "ble_adv", "wifi_client", "ieee802154"],
}
FIXED_METHOD = {"unipwn": "unitree_ble", "pcap": "pcap", "sdr": "sdr"}

WIFI_DETECTOR = {"wifi_watchlist", "deauth_storm", "probe_ssid", "pwnagotchi", "evil_twin", "karma",
                 "join_flood", "tag_flood", "beacon_flood"}
WIFI_WARDRIVE = {"wifi_ap", "wifi_client"}

V31_SIZES = {31: False, 36: True, 37: True, 69: True, 70: True, 96: False, 101: True, 23: False,
             28: True, 47: False, 52: True, 74: True, 155: True}

BOARD_CODES = ["", "xiao_s3", "s3_devkitc", "xiao_c5", "tdongle_s3", "tdongle_c5", "stickc",
               "stickc_plus", "stickc_plus2", "xiao_c3", "wroom"]

TLV_NODE_DETAIL, TLV_FILTER_PUSH, TLV_NEIGHBORS = 1, 2, 3

CTL_IDENTIFY, CTL_REBOOT, CTL_STATUS = 0x20, 0x22, 0x23


def canonical_node_id(raw):
    """OUISPY-A1B2, a1b2 or a longer id -> A1B2 (the last four hex digits); '' when there are none."""
    s = str(raw or "").upper()
    if s.startswith("OUISPY-"):
        s = s[7:]
    if len(s) < 4:
        return ""
    s = s[-4:]
    return s if re.fullmatch(r"[0-9A-F]{4}", s) else ""


def _cstr(b, off, n):
    seg = bytes(b[off:off + n])
    seg = seg.split(b"\0", 1)[0]
    text = seg.decode("utf-8", "replace")
    return "".join(c for c in text if ord(c) >= 0x20 and not 0x7F <= ord(c) <= 0x9F)


def mac_text(b, off):
    return ":".join(f"{x:02X}" for x in b[off:off + 6])


def device_info(data):
    """NUL-separated: firmware, node id, board, role, heap, [temp], key=value ... (BLE device info)."""
    parts = [p.decode("utf-8", "replace") for p in bytes(data).split(b"\0")]
    while parts and parts[-1] == "":
        parts.pop()
    kv = {}
    for p in parts:
        k, sep, v = p.partition("=")
        if sep and k:
            kv[k] = v
    return {"fw": parts[0] if parts else "", "node": parts[1] if len(parts) > 1 else "",
            "id": canonical_node_id(parts[1]) if len(parts) > 1 else "",
            "board": parts[2] if len(parts) > 2 else "", "role": parts[3] if len(parts) > 3 else "",
            "proto": int(kv["proto"]) if kv.get("proto", "").isdigit() else None, "kv": kv}


def method_name(engine, method):
    if engine in FIXED_METHOD:
        return FIXED_METHOD[engine]
    names = METHODS[engine]
    return names[max(0, min(method, len(names) - 1))]


def decode_detection(data):
    b = bytes(data)
    if len(b) < 14:
        raise ValueError("detection too short")
    engine = ENGINES[min(b[0] & 0x7F, len(ENGINES) - 1)]
    method = b[13]
    v31 = V31_SIZES.get(len(b), len(b) >= 19)
    header = 19 if v31 else 14
    d = {"engine": engine, "mac": mac_text(b, 1), "rssi": struct.unpack_from("<b", b, 7)[0],
         "channel": b[8], "device_ms": struct.unpack_from("<I", b, 9)[0],
         "method": method_name(engine, method), "source": _cstr(b, 14, 5) if v31 else "",
         "name": "", "ssid": "", "auth": None, "desc": "", "odid": None}
    ext = b[header:]
    if not ext:
        return d
    if engine in ("flock_ble", "flock_wifi"):
        d["raven"] = ext[0] == 1
        if engine == "flock_wifi" and len(ext) >= 18 and ext[17] > 0:
            d["auth"] = ext[17]
        if len(ext) > 18:
            d["name"] = _cstr(ext, 18, 32)
    elif engine == "sky_spy":
        d["odid"] = _odid(ext)
    elif engine == "detector":
        d["desc"] = _cstr(ext, 1, 32) if len(ext) > 1 else ""
        d["confidence"] = ext[33] if len(ext) > 33 else 0
    elif engine == "wardrive":
        client = d["method"] == "wifi_client" and len(ext) > 55
        e = ext[:55] if client else ext
        d["ssid"] = _cstr(e, 0, 33)
        d["auth"] = e[33] if len(e) > 33 else 0
        d["name"] = _cstr(e, 34, 21) if len(e) > 34 else ""
    elif engine == "unipwn":
        d["name"] = _cstr(ext, 0, 8)
    return d


def _alt(v):
    return None if v == -1000 else v


def _odid(ext):
    if len(ext) < 88:
        return None
    s16 = lambda off: struct.unpack_from("<h", ext, off)[0]
    f64 = lambda off: struct.unpack_from("<d", ext, off)[0]
    speed, heading = s16(62), s16(64)
    return {"id": _cstr(ext, 0, 21), "op": _cstr(ext, 21, 21),
            "lat": f64(42), "lon": f64(50), "alt": _alt(s16(58)), "hagl": _alt(s16(60)),
            "spd": None if speed >= 255 else speed, "hdg": None if heading >= 361 else heading,
            "plat": f64(66), "plon": f64(74),
            "desc": _cstr(ext, 82, 24) if len(ext) >= 106 else "",
            "altb": _alt(s16(106)) if len(ext) >= 108 else None}


def _id_at(b, off):
    return f"{b[off]:02X}{b[off + 1]:02X}"


def decode_mesh_status(data):
    b = bytes(data)
    out = {"enabled": False, "peers": 0, "connected": 0, "rx": 0, "tx": 0, "live": [], "key_failures": None,
           "details": [], "filter_push": None, "signal": []}
    if len(b) < 11:
        return out
    out.update(enabled=b[0] != 0, peers=b[1], connected=b[2],
               rx=struct.unpack_from("<I", b, 3)[0], tx=struct.unpack_from("<I", b, 7)[0])
    if len(b) < 12:
        return out
    n = b[11]
    entry = 11
    boards_at = 12 + n * entry
    temps_at = boards_at + n
    for i in range(n):
        off = 12 + i * entry
        if off + entry > len(b):
            break
        code = b[boards_at + i] if boards_at + i < len(b) else 0
        temp = struct.unpack_from("<b", b, temps_at + i)[0] if temps_at + i < len(b) else -128
        out["live"].append({"id": bytes(b[off:off + 4]).decode("ascii", "replace").upper(),
                            "role": "manager" if b[off + 5] == 1 else "node",
                            "engines": b[off + 6], "fw": struct.unpack_from("<I", b, off + 7)[0],
                            "board": BOARD_CODES[code] if code < len(BOARD_CODES) else "",
                            "temp": None if temp == -128 else temp})
    fail_at = temps_at + n
    if len(b) >= fail_at + 4:
        out["key_failures"] = struct.unpack_from("<I", b, fail_at)[0]
        pos = fail_at + 4
        while pos + 2 <= len(b):
            t, ln = b[pos], b[pos + 1]
            body = pos + 2
            if body + ln > len(b):
                break
            if t == TLV_NODE_DETAIL:
                out["details"] = _details(b, body, ln)
            elif t == TLV_FILTER_PUSH:
                out["filter_push"] = _filter_push(b, body, ln)
            elif t == TLV_NEIGHBORS:
                out["signal"] = _signal(b, body, ln)
            pos = body + ln
    return out


def _details(b, at, ln):
    out = []
    o = at
    while o + 15 <= at + ln:
        code = b[o + 6]
        out.append({"id": _id_at(b, o), "fw": struct.unpack_from("<I", b, o + 2)[0],
                    "board": BOARD_CODES[code] if code < len(BOARD_CODES) else "",
                    "up": struct.unpack_from("<I", b, o + 7)[0],
                    "filter_macs": b[o + 11], "filter_uuids": b[o + 12], "peers": b[o + 13],
                    "age": b[o + 14] * 10})
        o += 15
    return out


def _filter_push(b, at, ln):
    if ln < 5:
        return None
    n = b[at + 4]
    results = []
    for i in range(n):
        o = at + 5 + i * 5
        if o + 5 > at + ln:
            break
        results.append({"id": _id_at(b, o), "status": b[o + 2], "macs": b[o + 3], "uuids": b[o + 4]})
    return {"seq": b[at], "macs": b[at + 1], "uuids": b[at + 2], "expected": b[at + 3], "results": results}


def _signal(b, at, ln):
    rows = []
    o, end = at, at + ln
    while o + 3 <= end:
        nid, k = _id_at(b, o), b[o + 2]
        o += 3
        if o + k * 3 > end:
            break
        hears = []
        for _ in range(k):
            r = b[o + 2]
            hears.append({"id": _id_at(b, o), "rssi": None if r == 0x80 else r - (256 if r >= 128 else 0)})
            o += 3
        rows.append({"id": nid, "hears": hears})
    return rows


def firmware_text(v):
    """The firmware version number the mesh reports (0x00MMmmpp) as text."""
    return f"{(v >> 16) & 0xFF}.{(v >> 8) & 0xFF}.{v & 0xFF}"


def _target(node_id):
    if node_id is None:
        return b""
    if not re.fullmatch(r"[0-9A-F]{4}", node_id):
        raise ValueError("node id must be four hex digits")
    return bytes([0xFE]) + node_id.encode("ascii") + b"\0"


def encode_status_request(node_id=None):
    return bytes([CTL_STATUS, 0]) + _target(node_id)


def encode_identify(node_id=None, seconds=10, beep=True, light=True):
    return (bytes([CTL_IDENTIFY, 0]) + _target(node_id)
            + bytes([max(1, min(255, int(seconds))), (1 if beep else 0) | (2 if light else 0)]))


def encode_reboot(node_id=None):
    return bytes([CTL_REBOOT, 0]) + _target(node_id) + bytes([0xC0, 0xDE])

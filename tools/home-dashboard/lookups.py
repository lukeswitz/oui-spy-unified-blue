"""Offline name lookups for device intel: IEEE OUI vendors, Bluetooth SIG
company IDs, 16-bit service / member UUIDs and GAP appearance values.

The tables live in data/ (public registries, refreshed by hand):
  oui.csv                    https://standards-oui.ieee.org/oui/oui.csv
  company_identifiers.yaml   bitbucket.org/bluetooth-SIG/public  assigned_numbers/company_identifiers
  service_uuids.yaml         ... assigned_numbers/uuids
  member_uuids.yaml          ... assigned_numbers/uuids
  appearance_values.yaml     ... assigned_numbers/core
Parsed with a few regexes so there's no YAML dependency.
"""
import csv
import os
import re

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")

_oui = None
_cid = None
_uuid = None
_appear = None

# IEEE vendor names for the vendor-IE OUIs that tell you which chip / OS stack sent a frame.
_VIE_HINTS = {
    "0017f2": "Apple", "0050f2": "Microsoft (WPA/WMM/WPS)", "001018": "Broadcom",
    "00904c": "Epigram (Broadcom)", "506f9a": "Wi-Fi Alliance", "8cfdf0": "Qualcomm",
    "00e04c": "Realtek", "000c43": "Ralink (MediaTek)", "001374": "Atheros",
    "00037f": "Atheros", "0000f0": "Samsung", "18fe34": "Espressif",
}


SOURCES = {
    "oui.csv": "https://standards-oui.ieee.org/oui/oui.csv",
    "company_identifiers.yaml": "https://bitbucket.org/bluetooth-SIG/public/raw/main/assigned_numbers/company_identifiers/company_identifiers.yaml",
    "service_uuids.yaml": "https://bitbucket.org/bluetooth-SIG/public/raw/main/assigned_numbers/uuids/service_uuids.yaml",
    "member_uuids.yaml": "https://bitbucket.org/bluetooth-SIG/public/raw/main/assigned_numbers/uuids/member_uuids.yaml",
    "appearance_values.yaml": "https://bitbucket.org/bluetooth-SIG/public/raw/main/assigned_numbers/core/appearance_values.yaml",
}


def ensure_data(force=False):
    """Download any missing table (public registries, not shipped in the repo).
    Run once at startup in the background; lookups return "" until it lands."""
    import urllib.request
    global _oui, _cid, _uuid, _appear
    os.makedirs(DATA, exist_ok=True)
    got = []
    for name, url in SOURCES.items():
        path = os.path.join(DATA, name)
        if os.path.exists(path) and not force:
            continue
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "OUI-SPY-Mesh-dashboard"})
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            with open(path + ".tmp", "wb") as f:
                f.write(data)
            os.replace(path + ".tmp", path)
            got.append(name)
        except Exception as e:
            print(f"[lookups] {name}: {e}")
    if got:
        _oui = _cid = _uuid = _appear = None   # reload on next use
        print(f"[lookups] downloaded {', '.join(got)}")
    return got


def _read(name):
    try:
        with open(os.path.join(DATA, name), encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def _yaml_pairs(text, key):
    """[(int(value), name)] for '- <key>: 0x..' followed by 'name: ...' lines."""
    out = []
    for m in re.finditer(r"-\s*" + key + r":\s*(0x[0-9A-Fa-f]+)\s*\n\s*name:\s*(.+)", text):
        out.append((int(m.group(1), 16), m.group(2).strip().strip("'\"")))
    return out


def oui_vendor(mac):
    global _oui
    if _oui is None:
        _oui = {}
        try:
            with open(os.path.join(DATA, "oui.csv"), encoding="utf-8", newline="") as f:
                for row in csv.reader(f):
                    if len(row) >= 3 and len(row[1]) == 6:
                        _oui[row[1].upper()] = row[2].strip()
        except OSError:
            pass
    h = re.sub(r"[^0-9A-Fa-f]", "", mac or "").upper()
    return _oui.get(h[:6], "")


def vie_vendor(oui_hex):
    h = (oui_hex or "").lower()
    return _VIE_HINTS.get(h) or oui_vendor(h)


def company(cid_hex):
    global _cid
    if _cid is None:
        _cid = dict(_yaml_pairs(_read("company_identifiers.yaml"), "value"))
    try:
        return _cid.get(int(cid_hex, 16), "")
    except (TypeError, ValueError):
        return ""


def uuid16(u_hex):
    global _uuid
    if _uuid is None:
        _uuid = dict(_yaml_pairs(_read("member_uuids.yaml"), "uuid"))
        _uuid.update(_yaml_pairs(_read("service_uuids.yaml"), "uuid"))
    try:
        return _uuid.get(int(u_hex, 16), "")
    except (TypeError, ValueError):
        return ""


def appearance(val):
    """GAP appearance: 10-bit category + 6-bit subcategory."""
    global _appear
    if _appear is None:
        _appear = {}
        text = _read("appearance_values.yaml")
        for block in re.split(r"\n\s*-\s*category:", "\n" + text)[1:]:
            m = re.match(r"\s*(0x[0-9A-Fa-f]+)\s*\n\s*name:\s*(.+)", block)
            if not m:
                continue
            cat = int(m.group(1), 16)
            _appear[(cat, None)] = m.group(2).strip().strip("'\"")
            for v, n in _yaml_pairs(block, "value"):
                _appear[(cat, v)] = n
    try:
        val = int(val)
    except (TypeError, ValueError):
        return ""
    cat, sub = val >> 6, val & 0x3F
    base = _appear.get((cat, None), "")
    s = _appear.get((cat, sub)) if sub else None
    return f"{base}: {s}" if s else base


def mac_kind(mac):
    """Address facts readable from the MAC itself."""
    h = re.sub(r"[^0-9A-Fa-f]", "", mac or "")
    if len(h) < 2:
        return {}
    b0 = int(h[:2], 16)
    return {"local": bool(b0 & 0x02), "multicast": bool(b0 & 0x01),
            # BLE random addresses: top two bits of the MSB say which kind.
            "ble_random_kind": {0b11: "static", 0b01: "resolvable private (RPA)",
                                0b00: "non-resolvable private"}.get(b0 >> 6, "")}


def decorate(intel):
    """Add human names next to the raw numbers in an intel record (copy)."""
    out = dict(intel or {})
    if out.get("cid"):
        out["cid_name"] = company(out["cid"])
    if out.get("cids"):
        out["cids_named"] = {k: company(k) for k in out["cids"]}
    if out.get("uuids"):
        out["uuids_named"] = [{"uuid": u, "name": uuid16(u)} for u in out["uuids"]]
    if isinstance(out.get("sdata"), dict):
        out["sdata_named"] = [{"uuid": u, "name": uuid16(u), "data": d} for u, d in out["sdata"].items()]
    if out.get("app") is not None:
        out["app_name"] = appearance(out["app"])
    if out.get("vie"):
        out["vie_named"] = [{"oui": v, "name": vie_vendor(v)} for v in out["vie"]]
    return out

"""Drone Remote ID tracking (ASTM F3411 / OpenDroneID).

Two inputs, one model:
  RID {json}       every OUI-SPY mesh node decodes Remote ID itself (rid.cpp);
                   the home prints its own and every relayed report.
  {"mac", "drone_lat", ...}   a Sky-Spy board on USB (mesh-mapper.py format).

Per drone: the latest merged fields, the flight track, the pilot track, which
nodes heard it, plus dashboard-side alias / tag / FAA record (SQLite).
"""
import json
import queue
import threading
import time

from lookups import oui_vendor

UA_TYPES = ["None", "Aeroplane", "Multirotor / helicopter", "Gyroplane", "Hybrid lift (VTOL)",
            "Ornithopter", "Glider", "Kite", "Free balloon", "Captive balloon", "Airship",
            "Parachute", "Rocket", "Tethered powered aircraft", "Ground obstacle", "Other"]
ID_TYPES = ["None", "Serial number (ANSI/CTA-2063-A)", "CAA registration", "UTM (USS) UUID",
            "Specific session ID"]
STATUS = ["Undeclared", "Ground", "Airborne", "Emergency", "Remote ID system failure"]
OP_LOC = ["Take-off point", "Live GNSS", "Fixed location"]
TAGS = ["unknown", "friendly", "neutral", "suspicious", "hostile"]

SCHEMA = """
CREATE TABLE IF NOT EXISTS drone_reports (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    ts    REAL NOT NULL,
    mac   TEXT NOT NULL,
    node  TEXT,
    rssi  INTEGER,
    lat   REAL, lon REAL, alt REAL, hagl REAL, spd REAL, hdg REAL,
    plat  REAL, plon REAL,
    data  TEXT
);
CREATE INDEX IF NOT EXISTS drep_mac_ts ON drone_reports(mac, ts);
CREATE INDEX IF NOT EXISTS drep_ts ON drone_reports(ts);
CREATE TABLE IF NOT EXISTS drone_meta (
    mac   TEXT PRIMARY KEY,
    alias TEXT,
    tag   TEXT,
    notes TEXT,
    faa   TEXT,
    faa_ts REAL,
    first REAL,
    last  REAL
);
"""

LIVE_S = 60          # "in the air now" (mesh-mapper staleThreshold)
TRACK_KEEP = 600     # points kept per drone in memory
STORE_EVERY_S = 2.0  # one stored report per drone per this many seconds
FAA_ID_TYPES = {1, 2}   # CTA-2063 serial / CAA registration: what the FAA indexes
FAA_RETRY_S = 3600      # a failed lookup (network) tries again in an hour


def _num(v, bad=None, lo=None, hi=None):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return None
    if bad is not None and v in bad:
        return None
    if lo is not None and v < lo:
        return None
    if hi is not None and v > hi:
        return None
    return v


def normalize(obj, source="rid"):
    """Either input format -> one dict with our field names (None = unknown)."""
    if "drone_lat" in obj or "drone_long" in obj:          # Sky-Spy / mesh-mapper JSON
        obj = {"mac": obj.get("mac"), "rssi": obj.get("rssi"), "id": obj.get("basic_id"),
               "lat": obj.get("drone_lat"), "lon": obj.get("drone_long"), "alt": obj.get("drone_altitude"),
               "plat": obj.get("pilot_lat"), "plon": obj.get("pilot_long"), "node": obj.get("node"),
               "hagl": obj.get("height_agl"), "spd": obj.get("speed"), "hdg": obj.get("heading"),
               "op": obj.get("op_id"), "src": "skyspy"}
    lat, lon = _num(obj.get("lat"), lo=-90, hi=90), _num(obj.get("lon"), lo=-180, hi=180)
    if lat == 0 and lon == 0:
        lat = lon = None
    plat, plon = _num(obj.get("plat"), lo=-90, hi=90), _num(obj.get("plon"), lo=-180, hi=180)
    if plat == 0 and plon == 0:
        plat = plon = None
    d = {
        "mac": str(obj.get("mac") or "").upper(),
        "node": (obj.get("node") or "").upper() or None,
        "rssi": obj.get("rssi"),
        "src": obj.get("src") or source,
        "id": (obj.get("id") or "").strip() or None,
        "idt": obj.get("idt"), "uat": obj.get("uat"),
        "op": (obj.get("op") or "").strip() or None,
        "desc": (obj.get("desc") or "").strip() or None,
        "lat": lat, "lon": lon,
        "alt": _num(obj.get("alt"), bad=(-1000,)), "altb": _num(obj.get("altb"), bad=(-1000,)),
        "hagl": _num(obj.get("hagl"), bad=(-1000,)),
        "spd": _num(obj.get("spd"), bad=(255, 254.25), lo=0),
        "vspd": _num(obj.get("vspd"), bad=(63, 62)),
        "hdg": _num(obj.get("hdg"), lo=0, hi=360),
        "st": obj.get("st"),
        "plat": plat, "plon": plon, "palt": _num(obj.get("palt"), bad=(-1000,)),
        "ploc": obj.get("ploc"),
    }
    return d


def _label(table, i):
    try:
        return table[int(i)]
    except (TypeError, ValueError, IndexError):
        return None


class Drones:
    def __init__(self, store, emit):
        self.store = store
        self.emit = emit
        self.lock = threading.Lock()
        self.live = {}       # mac -> state
        self._faa_q = queue.Queue()
        self._faa_seen = {}  # mac -> ts of the last lookup attempt (failures retry)
        self._faa_air = set()  # macs with a lookup in flight
        threading.Thread(target=self._faa_worker, name="faa-lookup", daemon=True).start()
        with store.lock:
            store.db.executescript(SCHEMA)
            store.db.commit()
        self._reload()

    def _reload(self, hours=6):
        """Drones of the last few hours back into memory at startup, tracks rebuilt
        from their stored reports: a restart must not wipe them off the maps."""
        since = time.time() - hours * 3600
        with self.store.lock:
            macs = [r["mac"] for r in self.store.db.execute(
                "SELECT mac FROM drone_meta WHERE last>=?", (since,)).fetchall()]
        for mac in macs:
            with self.store.lock:
                rows = self.store.db.execute(
                    "SELECT ts, node, rssi, data FROM drone_reports WHERE mac=? AND ts>=? ORDER BY ts",
                    (mac, since)).fetchall()
            if not rows:
                continue
            meta = self._meta(mac)
            s = {"mac": mac, "first": meta.get("first") or rows[0]["ts"], "track": [], "ptrack": [],
                 "nodes": {}, "stored": rows[-1]["ts"], "reports": len(rows),
                 "vendor": oui_vendor(mac) or None, "alias": meta.get("alias") or "",
                 "tag": meta.get("tag") or "unknown", "notes": meta.get("notes") or "", "faa": meta.get("faa")}
            for r in rows:
                try:
                    d = json.loads(r["data"])
                except ValueError:
                    continue
                for k, v in d.items():
                    if v is not None and k != "node":
                        s[k] = v
                if d.get("lat") is not None:
                    s["track"].append([r["ts"], d["lat"], d["lon"], d.get("alt"), d.get("hagl")])
                if d.get("plat") is not None:
                    s["ptrack"].append([r["ts"], d["plat"], d["plon"]])
                n = s["nodes"].setdefault(r["node"] or "?", {"n": 0})
                n["n"] += 1
                n["rssi"] = r["rssi"]
                n["last"] = r["ts"]
            s["last"] = rows[-1]["ts"]
            s["closest"] = rows[-1]["node"]
            with self.lock:
                self.live[mac] = s
            if s.get("id") and s.get("idt") in FAA_ID_TYPES and not s.get("faa"):
                self._maybe_faa(mac, s["id"])

    # ---------------- ingest ----------------
    def feed(self, obj, source="rid", home_id=None):
        d = normalize(obj, source)
        if not d["mac"]:
            return
        now = time.time()
        node = d["node"] or home_id or "USB"
        with self.lock:
            s = self.live.get(d["mac"])
            if not s:
                s = self.live[d["mac"]] = {"mac": d["mac"], "first": now, "track": [], "ptrack": [],
                                           "nodes": {}, "stored": 0, "reports": 0,
                                           "vendor": oui_vendor(d["mac"]) or None}
                meta = self._meta(d["mac"])
                s.update({"alias": meta.get("alias") or "", "tag": meta.get("tag") or "unknown",
                          "notes": meta.get("notes") or "", "faa": meta.get("faa"),
                          "first": meta.get("first") or now})
            for k, v in d.items():
                if v is not None and k not in ("node",):
                    s[k] = v
            s["last"] = now
            s["reports"] += 1
            n = s["nodes"].setdefault(node, {"n": 0})
            n["n"] += 1
            n["rssi"] = d["rssi"]
            n["last"] = now
            n["best"] = max(n.get("best", -200), d["rssi"] if d["rssi"] is not None else -200)
            s["closest"] = max(((k, v) for k, v in s["nodes"].items() if now - v["last"] < 30),
                               key=lambda kv: kv[1].get("rssi") if kv[1].get("rssi") is not None else -200,
                               default=(node, None))[0]
            if d["lat"] is not None:
                if not s["track"] or s["track"][-1][1:3] != [d["lat"], d["lon"]]:
                    s["track"].append([now, d["lat"], d["lon"], d["alt"], d["hagl"]])
                    del s["track"][:-TRACK_KEEP]
            if d["plat"] is not None:
                if not s["ptrack"] or s["ptrack"][-1][1:3] != [d["plat"], d["plon"]]:
                    s["ptrack"].append([now, d["plat"], d["plon"]])
                    del s["ptrack"][:-TRACK_KEEP]
            store_now = now - s["stored"] >= STORE_EVERY_S
            if store_now:
                s["stored"] = now
            out = self._public(s, now)
            is_new = s["reports"] == 1
        if store_now:
            self._save(d, node, now, is_new)
        if d.get("id") and d.get("idt") in FAA_ID_TYPES:
            self._maybe_faa(d["mac"], d["id"])
        self.emit("drone", out)

    # ---------------- FAA UAS DOC lookup ----------------
    # A drone with a CTA-2063 serial or CAA registration gets looked up in the
    # FAA's public UAS DOC registry once, in the background; the record rides the
    # drone payload (faa / faa_ts) to every display. Failures retry in an hour.
    def _maybe_faa(self, mac, serial):
        now = time.time()
        if mac in self._faa_air or now - self._faa_seen.get(mac, 0) < FAA_RETRY_S:
            return
        with self.lock:
            if self.live.get(mac, {}).get("faa"):
                return
        self._faa_seen[mac] = now
        self._faa_air.add(mac)
        self._faa_q.put((mac, serial))

    def _faa_worker(self):
        while True:
            mac, serial = self._faa_q.get()
            try:
                self.set_meta(mac, faa=faa_lookup(serial) or {"records": []})
            except Exception:
                pass   # the attempt timestamp stays: _maybe_faa retries after FAA_RETRY_S
            finally:
                self._faa_air.discard(mac)

    def _save(self, d, node, now, is_new):
        st = self.store
        with st.lock:
            st.db.execute(
                "INSERT INTO drone_reports(ts, mac, node, rssi, lat, lon, alt, hagl, spd, hdg, plat, plon, data) "
                "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (now, d["mac"], node, d["rssi"], d["lat"], d["lon"], d["alt"], d["hagl"], d["spd"], d["hdg"],
                 d["plat"], d["plon"], json.dumps({k: v for k, v in d.items() if v is not None})))
            st.db.execute("INSERT INTO drone_meta(mac, first, last) VALUES(?,?,?) "
                          "ON CONFLICT(mac) DO UPDATE SET last=excluded.last", (d["mac"], now, now))
            st.db.commit()

    # ---------------- views ----------------
    def _meta(self, mac):
        st = self.store
        with st.lock:
            r = st.db.execute("SELECT * FROM drone_meta WHERE mac=?", (mac,)).fetchone()
        if not r:
            return {}
        m = dict(r)
        try:
            m["faa"] = json.loads(m["faa"]) if m.get("faa") else None
        except ValueError:
            m["faa"] = None
        return m

    @staticmethod
    def _public(s, now, track=60):
        out = {k: v for k, v in s.items() if k not in ("track", "ptrack", "stored")}
        out["age"] = now - s.get("last", now)
        out["live"] = out["age"] < LIVE_S
        out["track"] = s["track"][-track:] if track else []
        out["ptrack"] = s["ptrack"][-track:] if track else []
        out["ua_type"] = _label(UA_TYPES, s.get("uat"))
        out["id_type"] = _label(ID_TYPES, s.get("idt"))
        out["status"] = _label(STATUS, s.get("st"))
        out["op_loc"] = _label(OP_LOC, s.get("ploc"))
        if s.get("lat") is not None and s.get("plat") is not None:
            out["pilot_dist_m"] = round(_haversine(s["lat"], s["lon"], s["plat"], s["plon"]))
        return out

    def snapshot(self, track=60):
        now = time.time()
        with self.lock:
            return [self._public(s, now, track) for s in sorted(self.live.values(), key=lambda x: -x["last"])]

    def detail(self, mac, since=None):
        mac = mac.upper()
        now = time.time()
        with self.lock:
            s = self.live.get(mac)
            live = self._public(s, now, track=TRACK_KEEP) if s else None
        st = self.store
        with st.lock:
            rows = st.db.execute(
                "SELECT ts, node, rssi, lat, lon, alt, hagl, spd, hdg, plat, plon FROM drone_reports "
                "WHERE mac=? AND ts>=? ORDER BY ts", (mac, since or now - 86400)).fetchall()
            agg = st.db.execute("SELECT COUNT(*) n, MIN(ts) first, MAX(ts) last, MAX(alt) max_alt, "
                                "MAX(hagl) max_hagl, MAX(spd) max_spd FROM drone_reports WHERE mac=?",
                                (mac,)).fetchone()
            last = st.db.execute("SELECT data FROM drone_reports WHERE mac=? ORDER BY ts DESC LIMIT 1",
                                 (mac,)).fetchone()
        meta = self._meta(mac)
        if not live and last:
            s = json.loads(last["data"])
            s.update({"mac": mac, "nodes": {}, "track": [], "ptrack": [], "reports": agg["n"],
                      "last": agg["last"], "first": agg["first"]})
            live = self._public(s, now, track=0)
        if live is None:
            return None
        live.update({"alias": meta.get("alias") or live.get("alias", ""), "tag": meta.get("tag") or "unknown",
                     "notes": meta.get("notes") or "", "faa": meta.get("faa"), "faa_ts": meta.get("faa_ts")})
        live["history"] = [dict(r) for r in rows]
        live["stats"] = dict(agg)
        return live

    def recent(self, hours=24, limit=200):
        st = self.store
        with st.lock:
            rows = st.db.execute(
                "SELECT m.mac, m.alias, m.tag, m.first, m.last, COUNT(r.id) n, MAX(r.alt) max_alt "
                "FROM drone_meta m LEFT JOIN drone_reports r ON r.mac=m.mac WHERE m.last>=? "
                "GROUP BY m.mac ORDER BY m.last DESC LIMIT ?", (time.time() - hours * 3600, limit)).fetchall()
        return [dict(r) for r in rows]

    def set_meta(self, mac, alias=None, tag=None, notes=None, faa=None):
        mac = mac.upper()
        st = self.store
        with st.lock:
            st.db.execute("INSERT INTO drone_meta(mac, first, last) VALUES(?,?,?) ON CONFLICT(mac) DO NOTHING",
                          (mac, time.time(), time.time()))
            if alias is not None:
                st.db.execute("UPDATE drone_meta SET alias=? WHERE mac=?", (alias, mac))
            if tag is not None:
                st.db.execute("UPDATE drone_meta SET tag=? WHERE mac=?", (tag if tag in TAGS else "unknown", mac))
            if notes is not None:
                st.db.execute("UPDATE drone_meta SET notes=? WHERE mac=?", (notes, mac))
            if faa is not None:
                st.db.execute("UPDATE drone_meta SET faa=?, faa_ts=? WHERE mac=?", (json.dumps(faa), time.time(), mac))
            st.db.commit()
        with self.lock:
            s = self.live.get(mac)
            if s:
                if alias is not None:
                    s["alias"] = alias
                if tag is not None:
                    s["tag"] = tag
                if notes is not None:
                    s["notes"] = notes
                if faa is not None:
                    s["faa"] = faa
                self.emit("drone", self._public(s, time.time()))

    def prune(self, keep_s=3600 * 6):
        now = time.time()
        with self.lock:
            for m in [m for m, s in self.live.items() if now - s["last"] > keep_s]:
                del self.live[m]


def faa_lookup(serial):
    """FAA UAS DOC serial-number lookup (the same public endpoint mesh-mapper
    uses). Called automatically for drones with a serial-type Remote ID."""
    import urllib.parse
    import urllib.request
    import http.cookiejar
    jar = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    hdr = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:137.0) Gecko/20100101 Firefox/137.0",
           "Accept": "application/json, text/plain, */*", "Referer": "https://uasdoc.faa.gov/listdocs",
           "client": "external"}
    try:
        opener.open(urllib.request.Request("https://uasdoc.faa.gov/listdocs", headers=hdr), timeout=20).read()
    except Exception:
        pass
    q = urllib.parse.urlencode({"itemsPerPage": 8, "pageIndex": 0, "orderBy[0]": "updatedAt",
                                "orderBy[1]": "DESC", "findBy": "serialNumber", "serialNumber": serial})
    with opener.open(urllib.request.Request("https://uasdoc.faa.gov/api/v1/serialNumbers?" + q, headers=hdr),
                     timeout=30) as r:
        return json.loads(r.read())


def _haversine(lat1, lon1, lat2, lon2):
    from math import asin, cos, radians, sin, sqrt
    dlat, dlon = radians(lat2 - lat1), radians(lon2 - lon1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
    return 6371000 * 2 * asin(sqrt(a))

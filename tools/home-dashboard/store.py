"""SQLite persistence: detections, node sightings, node metadata, settings.

Everything stays on this machine. One connection shared across threads,
serialized by a lock (writes are tiny and infrequent).
"""
import csv
import io
import json
import sqlite3
import threading
import time

SCHEMA = """
CREATE TABLE IF NOT EXISTS detections (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    ts      REAL NOT NULL,
    node    TEXT NOT NULL,
    mac     TEXT NOT NULL,
    alias   TEXT,
    rssi    INTEGER,
    type    TEXT,
    match   TEXT,
    descr   TEXT,
    dom     TEXT,
    source  TEXT,
    is_new  INTEGER DEFAULT 0
);
CREATE INDEX IF NOT EXISTS det_ts   ON detections(ts);
CREATE INDEX IF NOT EXISTS det_node ON detections(node);
CREATE INDEX IF NOT EXISTS det_mac  ON detections(mac);

CREATE TABLE IF NOT EXISTS sightings (
    id     INTEGER PRIMARY KEY AUTOINCREMENT,
    ts     REAL NOT NULL,
    node   TEXT NOT NULL,
    event  TEXT NOT NULL,      -- online | offline | sample
    rssi   INTEGER,
    pkts   INTEGER
);
CREATE INDEX IF NOT EXISTS sig_node_ts ON sightings(node, ts);

CREATE TABLE IF NOT EXISTS nodes (
    id         TEXT PRIMARY KEY,
    alias      TEXT,
    lat        REAL,
    lon        REAL,
    notes      TEXT,
    role       TEXT,
    first_seen REAL,
    last_seen  REAL
);

CREATE TABLE IF NOT EXISTS mac_aliases (
    mac   TEXT PRIMARY KEY,
    alias TEXT,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS commands (
    id       INTEGER PRIMARY KEY,
    ts       REAL NOT NULL,
    op       TEXT,
    target   TEXT,
    label    TEXT,
    state    TEXT,
    cmd_id   INTEGER,
    replies  TEXT,
    error    TEXT,
    finished REAL,
    auto     INTEGER
);
CREATE INDEX IF NOT EXISTS cmd_ts ON commands(ts);

CREATE TABLE IF NOT EXISTS tracks (
    id    INTEGER PRIMARY KEY AUTOINCREMENT,
    ts    REAL NOT NULL,
    node  TEXT NOT NULL,
    lat   REAL NOT NULL,
    lon   REAL NOT NULL,
    acc   REAL
);
CREATE INDEX IF NOT EXISTS trk_node_ts ON tracks(node, ts);

-- Everything the nodes heard a device say over the air (firmware "info"),
-- merged across reports: lists (probed SSIDs, UUIDs, names) accumulate.
CREATE TABLE IF NOT EXISTS device_intel (
    mac    TEXT PRIMARY KEY,
    first  REAL,
    last   REAL,
    reports INTEGER DEFAULT 0,
    intel  TEXT
);

-- Groups: one overarching alias over several devices (a Cradlepoint and the
-- phones / tags that travel with it).
CREATE TABLE IF NOT EXISTS device_groups (
    id     INTEGER PRIMARY KEY AUTOINCREMENT,
    name   TEXT NOT NULL,
    notes  TEXT,
    color  INTEGER,
    created REAL
);
CREATE TABLE IF NOT EXISTS group_members (
    mac      TEXT PRIMARY KEY,
    group_id INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT
);
"""

DET_COLS = ["id", "ts", "node", "mac", "alias", "rssi", "type", "match",
            "descr", "dom", "source", "is_new"]


class Store:
    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript(SCHEMA)
        # Columns added after the first release (older databases lack them).
        cols = {r[1] for r in self.db.execute("PRAGMA table_info(nodes)")}
        if "color" not in cols:
            self.db.execute("ALTER TABLE nodes ADD COLUMN color INTEGER")   # hue 0-359, NULL = default
        dcols = {r[1] for r in self.db.execute("PRAGMA table_info(detections)")}
        if "info" not in dcols:
            self.db.execute("ALTER TABLE detections ADD COLUMN info TEXT")  # JSON, per report
        self.db.commit()

    # ---------- settings ----------
    def get_setting(self, key, default=None):
        with self.lock:
            row = self.db.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
        if row is None:
            return default
        try:
            return json.loads(row["value"])
        except ValueError:
            return default

    def set_setting(self, key, value):
        with self.lock:
            self.db.execute("INSERT INTO settings(key,value) VALUES(?,?) "
                            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                            (key, json.dumps(value)))
            self.db.commit()

    def all_settings(self):
        with self.lock:
            rows = self.db.execute("SELECT key, value FROM settings").fetchall()
        out = {}
        for r in rows:
            try:
                out[r["key"]] = json.loads(r["value"])
            except ValueError:
                pass
        return out

    # ---------- nodes ----------
    def nodes_meta(self):
        with self.lock:
            rows = self.db.execute("SELECT * FROM nodes").fetchall()
        return {r["id"]: dict(r) for r in rows}

    def touch_node(self, node_id, role=None, ts=None):
        ts = ts or time.time()
        with self.lock:
            self.db.execute(
                "INSERT INTO nodes(id, role, first_seen, last_seen) VALUES(?,?,?,?) "
                "ON CONFLICT(id) DO UPDATE SET last_seen=excluded.last_seen, "
                "role=COALESCE(excluded.role, nodes.role)",
                (node_id, role, ts, ts))
            self.db.commit()

    def update_node(self, node_id, **fields):
        allowed = {k: v for k, v in fields.items() if k in ("alias", "lat", "lon", "notes", "color")}
        if not allowed:
            return
        with self.lock:
            self.db.execute("INSERT OR IGNORE INTO nodes(id, first_seen) VALUES(?, ?)",
                            (node_id, time.time()))
            sets = ", ".join(f"{k}=?" for k in allowed)
            self.db.execute(f"UPDATE nodes SET {sets} WHERE id=?",
                            (*allowed.values(), node_id))
            self.db.commit()

    def forget_node(self, node_id):
        with self.lock:
            self.db.execute("DELETE FROM nodes WHERE id=?", (node_id,))
            self.db.commit()

    # ---------- detections ----------
    def mac_known(self, mac):
        with self.lock:
            return self.db.execute("SELECT 1 FROM detections WHERE mac=? LIMIT 1",
                                   (mac,)).fetchone() is not None

    def annotate_seen_by(self, rows, window=60):
        """Give each detection row the nodes that heard the same device in the
        `window` seconds up to it (latest RSSI each, strongest first) and the
        closest one when two or more did: the live feed's "seen by" line,
        rebuilt from history so a reload or restart shows the same thing."""
        if not rows:
            return rows
        macs = sorted({r["mac"] for r in rows})
        lo = min(r["ts"] for r in rows) - window
        hi = max(r["ts"] for r in rows)
        with self.lock:
            hist = self.db.execute(
                f"SELECT ts, node, mac, rssi FROM detections WHERE ts BETWEEN ? AND ? "
                f"AND mac IN ({','.join('?' * len(macs))}) ORDER BY ts", (lo, hi, *macs)).fetchall()
        by_mac = {}
        for h in hist:
            by_mac.setdefault(h["mac"], []).append(h)
        for r in rows:
            per = {}
            for h in by_mac.get(r["mac"], []):
                if r["ts"] - window <= h["ts"] <= r["ts"] and h["rssi"] is not None:
                    per[h["node"]] = (h["rssi"], h["ts"])
            seen = sorted(([n, rs, round(r["ts"] - t)] for n, (rs, t) in per.items()), key=lambda x: -x[1])
            r["seen_by"] = seen
            r["closest"] = seen[0][0] if len(seen) > 1 else None
        return rows

    def metrics(self, since, until, node=None, dom=None):
        """Everything the Metrics tab draws, for detections in [since, until]."""
        import re as _re
        import time as _t
        span = max(60, until - since)
        steps = [60, 300, 900, 1800, 3600, 7200, 10800, 21600, 43200, 86400]
        bucket = next((b for b in steps if span / b <= 120), 86400)
        start = since - since % bucket
        nb = int((until - start) // bucket) + 1
        where, args = "ts BETWEEN ? AND ?", [since, until]
        if node:
            where += " AND node = ?"; args.append(node)
        if dom:
            where += " AND dom = ?"; args.append(dom)
        with self.lock:
            rows = self.db.execute(f"SELECT ts, node, mac, rssi, type, descr, dom FROM detections WHERE {where}", args).fetchall()
            pw, pa = "ts >= ? AND ts < ?", [since - span, since]
            if node:
                pw += " AND node = ?"; pa.append(node)
            if dom:
                pw += " AND dom = ?"; pa.append(dom)
            prev_total = self.db.execute(f"SELECT COUNT(*) FROM detections WHERE {pw}", pa).fetchone()[0]
            first = dict(self.db.execute("SELECT mac, MIN(ts) FROM detections GROUP BY mac").fetchall())

        def vendor(descr):
            v = _re.sub(r"\s*\(.*?\)\s*$", "", (descr or "").strip())
            return v or "Unknown"

        per_vendor, per_node, per_type, per_dom = {}, {}, {}, {"ble": 0, "wifi": 0}
        bucket_v, bucket_macs = {}, [set() for _ in range(nb)]
        heat = [[0] * 24 for _ in range(7)]
        rssi_bins = list(range(-100, -15, 5))
        hist = [0] * len(rssi_bins)
        for r in rows:
            v = vendor(r["descr"])
            pv = per_vendor.setdefault(v, [0, set()]); pv[0] += 1; pv[1].add(r["mac"])
            pn = per_node.setdefault(r["node"], [0, set()]); pn[0] += 1; pn[1].add(r["mac"])
            per_type[r["type"] or "?"] = per_type.get(r["type"] or "?", 0) + 1
            if r["dom"] in per_dom:
                per_dom[r["dom"]] += 1
            i = min(nb - 1, max(0, int((r["ts"] - start) // bucket)))
            bucket_v.setdefault(v, [0] * nb)[i] += 1
            bucket_macs[i].add(r["mac"])
            lt = _t.localtime(r["ts"])
            heat[lt.tm_wday][lt.tm_hour] += 1
            if r["rssi"] is not None:
                k = min(len(hist) - 1, max(0, (int(r["rssi"]) + 100) // 5))
                hist[k] += 1
        ranked = sorted(per_vendor.items(), key=lambda kv: -kv[1][0])
        top = [v for v, _ in ranked[:5]]
        series = [{"name": v, "values": bucket_v[v]} for v in top]
        rest = [v for v, _ in ranked[5:]]
        if rest:
            series.append({"name": "Other", "values": [sum(bucket_v[v][i] for v in rest) for i in range(nb)]})
        totals = [sum(sr["values"][i] for sr in series) for i in range(nb)]
        peak_i = max(range(nb), key=lambda i: totals[i]) if nb else 0
        macs = {r["mac"] for r in rows}
        return {
            "since": since, "until": until, "bucket": bucket, "start": start, "n": nb,
            "total": len(rows), "prev_total": prev_total, "unique": len(macs),
            "new_devices": sum(1 for m in macs if first.get(m, 0) >= since),
            "nodes_active": len(per_node),
            "peak": {"count": totals[peak_i] if nb else 0, "ts": start + peak_i * bucket},
            "series": series, "unique_series": [len(b) for b in bucket_macs],
            "by_vendor": [{"name": v, "count": c[0], "devices": len(c[1])} for v, c in ranked[:10]],
            "by_node": sorted(({"id": n, "count": c[0], "devices": len(c[1])} for n, c in per_node.items()),
                              key=lambda x: -x["count"]),
            "by_type": sorted(({"type": t, "count": c} for t, c in per_type.items()), key=lambda x: -x["count"]),
            "by_dom": per_dom, "heat": heat, "rssi": {"from": -100, "step": 5, "counts": hist},
        }

    def add_detection(self, d):
        with self.lock:
            cur = self.db.execute(
                "INSERT INTO detections(ts,node,mac,alias,rssi,type,match,descr,dom,source,is_new,info) "
                "VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
                (d["ts"], d["node"], d["mac"], d.get("alias"), d.get("rssi"), d.get("type"),
                 d.get("match"), d.get("descr"), d.get("dom"), d.get("source"),
                 1 if d.get("is_new") else 0,
                 json.dumps(d["info"]) if d.get("info") else None))
            self.db.commit()
            return cur.lastrowid

    def _det_where(self, q=None, node=None, dom=None, since=None, until=None, mac=None):
        where, args = [], []
        if q:
            where.append("(mac LIKE ? OR alias LIKE ? OR descr LIKE ? OR match LIKE ? OR type LIKE ? "
                         "OR mac IN (SELECT mac FROM mac_aliases WHERE alias LIKE ?))")
            like = f"%{q}%"
            args += [like] * 6
        if node:
            where.append("node=?")
            args.append(node)
        if mac:
            where.append("mac=?")
            args.append(mac)
        if dom in ("ble", "wifi"):
            where.append("dom=?")
            args.append(dom)
        if since:
            where.append("ts>=?")
            args.append(float(since))
        if until:
            where.append("ts<=?")
            args.append(float(until))
        return (" WHERE " + " AND ".join(where)) if where else "", args

    def query_detections(self, limit=200, offset=0, **filters):
        w, args = self._det_where(**filters)
        with self.lock:
            total = self.db.execute(f"SELECT COUNT(*) FROM detections{w}", args).fetchone()[0]
            rows = self.db.execute(
                f"SELECT * FROM detections{w} ORDER BY ts DESC LIMIT ? OFFSET ?",
                (*args, int(limit), int(offset))).fetchall()
        names = self.device_names()
        aliases = self.mac_aliases()
        groups = self.group_of()
        out = []
        for r in rows:
            d = dict(r)
            d["alias"] = (aliases.get(d["mac"]) or {}).get("alias") or d.get("alias") or ""
            d["group"] = groups.get(d["mac"])
            try:
                d["info"] = json.loads(d["info"]) if d.get("info") else None
            except ValueError:
                d["info"] = None
            d["name"] = names.get(d["mac"], "")
            out.append(d)
        return total, out

    def export_detections(self, fmt, **filters):
        w, args = self._det_where(**filters)
        with self.lock:
            rows = [dict(r) for r in self.db.execute(
                f"SELECT *, (SELECT alias FROM mac_aliases m WHERE m.mac = detections.mac) mac_alias "
                f"FROM detections{w} ORDER BY ts ASC", args).fetchall()]
        for r in rows:
            r["time"] = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(r["ts"]))
        if fmt == "json":
            return json.dumps(rows, indent=1)
        buf = io.StringIO()
        cols = ["time"] + DET_COLS + ["mac_alias"]
        wr = csv.DictWriter(buf, fieldnames=cols, extrasaction="ignore")
        wr.writeheader()
        wr.writerows(rows)
        return buf.getvalue()

    def detection_stats(self):
        since = time.time() - 86400
        with self.lock:
            total = self.db.execute("SELECT COUNT(*) FROM detections").fetchone()[0]
            day = self.db.execute("SELECT COUNT(*) FROM detections WHERE ts>=?",
                                  (since,)).fetchone()[0]
            macs = self.db.execute("SELECT COUNT(DISTINCT mac) FROM detections").fetchone()[0]
            per_node = self.db.execute(
                "SELECT node, COUNT(*) c, MAX(ts) last FROM detections GROUP BY node").fetchall()
        return {"total": total, "day": day, "macs": macs,
                "per_node": {r["node"]: {"count": r["c"], "last": r["last"]} for r in per_node}}

    def hourly(self, hours=24):
        """Detections per hour for the last `hours` hours, oldest first."""
        now = time.time()
        start = (int(now) // 3600 - hours + 1) * 3600
        with self.lock:
            rows = self.db.execute(
                "SELECT CAST(ts / 3600 AS INTEGER) h, COUNT(*) c FROM detections "
                "WHERE ts >= ? GROUP BY h", (start,)).fetchall()
        got = {r["h"]: r["c"] for r in rows}
        first = start // 3600
        return [{"h": (first + i) * 3600, "c": got.get(first + i, 0)} for i in range(hours)]

    def devices(self, q=None, node=None, dom=None, limit=300):
        """One row per MAC: what it is, when, how often, which nodes saw it."""
        w, args = self._det_where(q=q, node=node, dom=dom)
        with self.lock:
            rows = self.db.execute(
                f"SELECT mac, MAX(descr) descr, MAX(type) type, MAX(dom) dom, COUNT(*) hits, "
                f"MIN(ts) first, MAX(ts) last, MAX(rssi) best, "
                f"GROUP_CONCAT(DISTINCT node) nodes FROM detections{w} "
                f"GROUP BY mac ORDER BY last DESC LIMIT ?", (*args, int(limit))).fetchall()
            total = self.db.execute(
                f"SELECT COUNT(DISTINCT mac) FROM detections{w}", args).fetchone()[0]
        names = self.device_names()
        out = []
        for r in rows:
            d = dict(r)
            d["nodes"] = sorted(set((d["nodes"] or "").split(","))) if d["nodes"] else []
            d["name"] = names.get(d["mac"], "")
            out.append(d)
        return total, out

    # ---------- device intel ----------
    # Lists that grow with every report (value -> count / last seen), and
    # scalars where the newest report wins.
    INTEL_SETS = {"ssid": "ssids", "bssid": "aps", "name": "names", "cid": "cids"}
    INTEL_LISTS = ("uuids", "vie")

    def merge_intel(self, mac, info, node=None, rssi=None, ts=None):
        """Fold one report's info into the device's record; returns the record."""
        ts = ts or time.time()
        with self.lock:
            row = self.db.execute("SELECT * FROM device_intel WHERE mac=?", (mac,)).fetchone()
            cur = json.loads(row["intel"]) if row and row["intel"] else {}
            for k, v in info.items():
                if k in self.INTEL_SETS:
                    bucket = cur.setdefault(self.INTEL_SETS[k], {})
                    key = str(v)
                    e = bucket.setdefault(key, {"n": 0, "first": ts})
                    e["n"] += 1
                    e["last"] = ts
                    if k == "bssid" and info.get("ssid"):
                        e["ssid"] = info["ssid"]
                    if len(bucket) > 64:   # keep the most recent 64
                        for old in sorted(bucket, key=lambda x: bucket[x]["last"])[:len(bucket) - 64]:
                            del bucket[old]
                    if k in ("name", "cid"):
                        cur[k] = v
                elif k in self.INTEL_LISTS:
                    have = cur.setdefault(k, [])
                    for x in v:
                        if x not in have:
                            have.append(x)
                elif k == "sdata":
                    have = cur.setdefault("sdata", {})
                    for x in v:
                        have[x.get("uuid", "?")] = x.get("data", "")
                else:
                    cur[k] = v
            if node:
                per = cur.setdefault("heard_by", {})
                e = per.setdefault(node, {"n": 0, "first": ts})
                e["n"] += 1
                e["last"] = ts
                if rssi is not None:
                    e["rssi"] = rssi
                    e["best"] = max(e.get("best", -200), rssi)
            self.db.execute(
                "INSERT INTO device_intel(mac, first, last, reports, intel) VALUES(?,?,?,1,?) "
                "ON CONFLICT(mac) DO UPDATE SET last=excluded.last, reports=reports+1, "
                "intel=excluded.intel", (mac, ts, ts, json.dumps(cur)))
            self.db.commit()
        return cur

    def device_intel(self, mac):
        with self.lock:
            row = self.db.execute("SELECT * FROM device_intel WHERE mac=?", (mac,)).fetchone()
        if not row:
            return None
        d = dict(row)
        d["intel"] = json.loads(d["intel"]) if d["intel"] else {}
        return d

    def device_names(self):
        """mac -> best name a device gave itself (BLE name, else its SSID)."""
        with self.lock:
            rows = self.db.execute("SELECT mac, intel FROM device_intel").fetchall()
        out = {}
        for r in rows:
            try:
                it = json.loads(r["intel"] or "{}")
            except ValueError:
                continue
            nm = it.get("name")
            if not nm and it.get("frame") in ("beacon", "probe-resp") and it.get("ssid"):
                nm = it["ssid"]
            if nm:
                out[r["mac"]] = nm
        return out

    def device_history(self, mac, limit=100):
        with self.lock:
            rows = self.db.execute(
                "SELECT ts, node, rssi, type, match, descr, dom, info FROM detections "
                "WHERE mac=? ORDER BY ts DESC LIMIT ?", (mac, int(limit))).fetchall()
            agg = self.db.execute(
                "SELECT COUNT(*) n, MIN(ts) first, MAX(ts) last, MAX(rssi) best, MIN(rssi) worst, "
                "AVG(rssi) avg FROM detections WHERE mac=?", (mac,)).fetchone()
        out = []
        for r in rows:
            d = dict(r)
            try:
                d["info"] = json.loads(d["info"]) if d["info"] else None
            except ValueError:
                d["info"] = None
            out.append(d)
        return dict(agg), out

    # ---------- groups ----------
    def groups(self):
        with self.lock:
            gs = [dict(r) for r in self.db.execute("SELECT * FROM device_groups ORDER BY name")]
            mem = self.db.execute("SELECT mac, group_id FROM group_members").fetchall()
        by = {}
        for m in mem:
            by.setdefault(m["group_id"], []).append(m["mac"])
        for g in gs:
            g["members"] = sorted(by.get(g["id"], []))
        return gs

    def group_of(self):
        """mac -> {"id", "name"} for every grouped device."""
        with self.lock:
            rows = self.db.execute("SELECT m.mac, g.id, g.name, g.color FROM group_members m "
                                   "JOIN device_groups g ON g.id=m.group_id").fetchall()
        return {r["mac"]: {"id": r["id"], "name": r["name"], "color": r["color"]} for r in rows}

    def save_group(self, gid, name, notes=None, color=None):
        with self.lock:
            if gid:
                self.db.execute("UPDATE device_groups SET name=?, notes=?, color=? WHERE id=?",
                                (name, notes, color, gid))
            else:
                gid = self.db.execute("INSERT INTO device_groups(name, notes, color, created) "
                                      "VALUES(?,?,?,?)", (name, notes, color, time.time())).lastrowid
            self.db.commit()
        return gid

    def delete_group(self, gid):
        with self.lock:
            self.db.execute("DELETE FROM group_members WHERE group_id=?", (gid,))
            self.db.execute("DELETE FROM device_groups WHERE id=?", (gid,))
            self.db.commit()

    def set_group(self, mac, gid):
        """Put a device in a group (gid None = take it out)."""
        with self.lock:
            if gid:
                self.db.execute("INSERT INTO group_members(mac, group_id) VALUES(?,?) "
                                "ON CONFLICT(mac) DO UPDATE SET group_id=excluded.group_id", (mac, gid))
            else:
                self.db.execute("DELETE FROM group_members WHERE mac=?", (mac,))
            self.db.commit()

    def companions(self, mac, window=60, limit=12):
        """Devices that keep turning up with `mac`: heard by the same node within
        `window` s of one of its detections. score = share of its sightings
        (by node + minute) that had the other device alongside."""
        with self.lock:
            mine = self.db.execute("SELECT ts, node FROM detections WHERE mac=? ORDER BY ts DESC "
                                   "LIMIT 400", (mac,)).fetchall()
            if not mine:
                return []
            # One "occasion" per node per window: repeats inside it count once.
            occ = []
            for r in mine:
                if not any(o[1] == r["node"] and abs(o[0] - r["ts"]) < window for o in occ):
                    occ.append((r["ts"], r["node"]))
            hits = {}
            for ts, node in occ:
                rows = self.db.execute(
                    "SELECT DISTINCT mac FROM detections WHERE node=? AND ts BETWEEN ? AND ? AND mac<>?",
                    (node, ts - window, ts + window, mac)).fetchall()
                for o in rows:
                    hits[o["mac"]] = hits.get(o["mac"], 0) + 1
            if not hits:
                return []
            info = {r["mac"]: dict(r) for r in self.db.execute(
                f"SELECT mac, MAX(descr) descr, MAX(dom) dom, COUNT(*) n, MAX(ts) last FROM detections "
                f"WHERE mac IN ({','.join('?' * len(hits))}) GROUP BY mac", list(hits)).fetchall()}
        out = []
        for m, n in hits.items():
            i = info.get(m, {})
            # Jaccard-ish: together / (occasions of either), so a device that is
            # everywhere (a neighbour's AP) does not top every list.
            score = n / max(1, len(occ) + min(i.get("n", n), 400) - n) if i.get("n") else 0
            out.append({"mac": m, "together": n, "occasions": len(occ), "score": round(min(1.0, score), 3),
                        "descr": i.get("descr", ""), "dom": i.get("dom", ""), "last": i.get("last")})
        out.sort(key=lambda x: (-x["together"], -x["score"]))
        return out[:limit]

    def mac_aliases(self):
        with self.lock:
            rows = self.db.execute("SELECT mac, alias, notes FROM mac_aliases").fetchall()
        return {r["mac"]: {"alias": r["alias"] or "", "notes": r["notes"] or ""} for r in rows}

    def set_mac_alias(self, mac, alias, notes=None):
        with self.lock:
            if not alias and not notes:
                self.db.execute("DELETE FROM mac_aliases WHERE mac=?", (mac,))
            else:
                self.db.execute("INSERT INTO mac_aliases(mac, alias, notes) VALUES(?,?,?) "
                                "ON CONFLICT(mac) DO UPDATE SET alias=excluded.alias, "
                                "notes=excluded.notes", (mac, alias, notes))
            self.db.commit()

    def prune(self, days):
        """Drop detections and sightings older than `days` (0 = keep forever)."""
        if not days or days <= 0:
            return 0
        cutoff = time.time() - days * 86400
        with self.lock:
            n = self.db.execute("DELETE FROM detections WHERE ts < ?", (cutoff,)).rowcount
            n += self.db.execute("DELETE FROM sightings WHERE ts < ?", (cutoff,)).rowcount
            n += self.db.execute("DELETE FROM tracks WHERE ts < ?", (cutoff,)).rowcount
            self.db.commit()
        return n

    # ---------- remote command log ----------
    def save_command(self, job):
        with self.lock:
            self.db.execute(
                "INSERT OR REPLACE INTO commands(id,ts,op,target,label,state,cmd_id,replies,error,finished,auto) "
                "VALUES(?,?,?,?,?,?,?,?,?,?,?)",
                (job["id"], job["created"], job["op"], job["target"], job["label"], job["state"],
                 job.get("cmd_id"), json.dumps(job.get("replies") or {}), job.get("error", ""),
                 job.get("finished"), 1 if job.get("auto") else 0))
            self.db.commit()

    def recent_commands(self, node=None, limit=60, include_auto=False):
        where, args = [], []
        if node:
            where.append("target IN (?, 'all')")
            args.append(node)
        if not include_auto:
            where.append("auto = 0")
        w = (" WHERE " + " AND ".join(where)) if where else ""
        with self.lock:
            rows = self.db.execute(f"SELECT * FROM commands{w} ORDER BY ts DESC LIMIT ?",
                                   (*args, int(limit))).fetchall()
        out = []
        for r in rows:
            d = dict(r)
            d["replies"] = json.loads(d["replies"] or "{}")
            d["created"] = d.pop("ts")
            d["auto"] = bool(d["auto"])
            out.append(d)
        return out

    # ---------- GPS tracks (a node carried with a phone) ----------
    def add_track(self, node, lat, lon, acc, ts=None):
        with self.lock:
            self.db.execute("INSERT INTO tracks(ts,node,lat,lon,acc) VALUES(?,?,?,?,?)",
                            (ts or time.time(), node, lat, lon, acc))
            self.db.commit()

    def tracks(self, since):
        with self.lock:
            rows = self.db.execute("SELECT node, ts, lat, lon, acc FROM tracks WHERE ts >= ? ORDER BY ts",
                                   (since,)).fetchall()
        out = {}
        for r in rows:
            out.setdefault(r["node"], []).append([round(r["ts"], 1), r["lat"], r["lon"], r["acc"]])
        return out

    def clear_track(self, node):
        with self.lock:
            self.db.execute("DELETE FROM tracks WHERE node=?", (node,))
            self.db.commit()

    def clear_detections(self, node=None, mac=None):
        """Delete all detections, or only one node's, or only one device's
        (both given: that device as seen by that node). -> rows deleted."""
        where, args = [], []
        if node:
            where.append("node=?"); args.append(node)
        if mac:
            where.append("mac=?"); args.append(mac)
        with self.lock:
            n = self.db.execute("DELETE FROM detections" + (" WHERE " + " AND ".join(where) if where else ""),
                                args).rowcount
            self.db.commit()
        return n

    # ---------- sightings ----------
    def add_sighting(self, node, event, rssi=None, pkts=None, ts=None):
        with self.lock:
            self.db.execute("INSERT INTO sightings(ts,node,event,rssi,pkts) VALUES(?,?,?,?,?)",
                            (ts or time.time(), node, event, rssi, pkts))
            self.db.commit()

    def node_sightings(self, node, since):
        with self.lock:
            rows = self.db.execute(
                "SELECT ts, event, rssi, pkts FROM sightings WHERE node=? AND ts>=? ORDER BY ts",
                (node, since)).fetchall()
        return [dict(r) for r in rows]

    def export_sightings(self, fmt):
        with self.lock:
            rows = [dict(r) for r in self.db.execute(
                "SELECT * FROM sightings ORDER BY ts ASC").fetchall()]
        if fmt == "json":
            return json.dumps(rows, indent=1)
        buf = io.StringIO()
        wr = csv.DictWriter(buf, fieldnames=["id", "ts", "node", "event", "rssi", "pkts"])
        wr.writeheader()
        wr.writerows(rows)
        return buf.getvalue()

"""Server-side RSSI triangulation, the same model as the web map (app.js
triFixCompute) so every display (the Tab5 too) shows the same fix:

  RSSI_i = P0 - 10 n log10(r_i) + noise(sigma), P0 integrated out per grid
  cell, posterior exp(-chi^2/2) over a grid around the nodes, position = the
  best cell refined by its 5x5 posterior mean, error = radius holding 68% of
  the posterior, smoothed across updates.

Readings: the last TRI_WINDOW_S seconds per (device, node), node RSSI offsets
and per-device calibration from settings["tri"] (set by the web dashboard).
"""
import math
import threading
import time

TRI_WINDOW_S = 45
TRI_K_MAX = 5
DEFAULTS = {"p0_ble": -59, "p0_wifi": -40, "n": 2.7, "sigma": 4, "max_err": 8, "smooth": 0.35,
            "offsets": {}, "devices": {}}


class Tri:
    def __init__(self, get_settings, node_pos):
        self.get_settings = get_settings     # -> settings dict (with "tri")
        self.node_pos = node_pos             # node id -> (lat, lon) or None
        self.lock = threading.Lock()
        self.samples = {}                    # mac -> {node: [(ts, rssi), ...]}
        self.dom = {}                        # mac -> "ble" / "wifi"
        self.state = {}                      # mac -> smoothed [lat, lon]
        self.last = {}                       # mac -> ts of the last computed fix

    def model(self):
        m = dict(DEFAULTS)
        m.update((self.get_settings() or {}).get("tri") or {})
        return m

    def add(self, mac, node, rssi, dom, ts=None):
        if rssi is None or not node:
            return
        ts = ts or time.time()
        with self.lock:
            per = self.samples.setdefault(mac, {})
            xs = per.setdefault(node, [])
            xs.append((ts, float(rssi)))
            while xs and ts - xs[0][0] > TRI_WINDOW_S:
                xs.pop(0)
            if dom:
                self.dom[mac] = dom

    def due(self, mac, every=1.0):
        now = time.time()
        if now - self.last.get(mac, 0) < every:
            return False
        self.last[mac] = now
        return True

    def fix(self, mac):
        """{"mac", "ok", "lat", "lon", "err", "rough", "cal", "n", "why"}"""
        m = self.model()
        now = time.time()
        dev = (m.get("devices") or {}).get(mac)
        dom = self.dom.get(mac, "ble")
        dm = ({"p0": dev["p0"], "n": dev["n"], "cal": True} if dev
              else {"p0": m["p0_wifi"] if dom == "wifi" else m["p0_ble"], "n": m["n"], "cal": False})
        with self.lock:
            per = {k: [r for t, r in v if now - t <= TRI_WINDOW_S] for k, v in self.samples.get(mac, {}).items()}
        nodes = []
        for nid, xs in per.items():
            pos = self.node_pos(nid)
            if not pos or not xs:
                continue
            xs = [x - (m["offsets"] or {}).get(nid, 0) for x in xs]
            mean = sum(xs) / len(xs)
            nodes.append({"id": nid, "lat": pos[0], "lon": pos[1], "rssi": mean, "k": min(TRI_K_MAX, len(xs)),
                          "d": 10 ** ((dm["p0"] - mean) / (10 * dm["n"]))})
        base = {"mac": mac, "ok": False, "cal": dm["cal"], "n": len(nodes),
                # each node's distance estimate (m): the range circles of the device being inspected
                "nodes": [{"id": n["id"], "d": round(n["d"], 1)} for n in nodes]}
        if len(nodes) < 3:
            return {**base, "why": f"heard by {len(nodes)} of the 3 nodes needed"}
        lat0, lon0 = nodes[0]["lat"], nodes[0]["lon"]
        kx, ky = 111320 * math.cos(math.radians(lat0)), 110540.0
        P = [((n["lon"] - lon0) * kx, (n["lat"] - lat0) * ky) for n in nodes]
        sig2 = m["sigma"] * m["sigma"]
        w = [n["k"] / sig2 for n in nodes]
        p0_prior = dm["p0"]
        p0_sd = max(1.0, dev.get("rms", 1.5) or 1.5) if dev else 10.0
        wp = 1.0 / (p0_sd * p0_sd)
        xs_ = [p[0] for p in P]
        ys_ = [p[1] for p in P]
        pad = 60
        x0, x1, y0, y1 = min(xs_) - pad, max(xs_) + pad, min(ys_) - pad, max(ys_) + pad
        cell = max(1.0, max(x1 - x0, y1 - y0) / 140)
        W = math.ceil((x1 - x0) / cell)
        H = math.ceil((y1 - y0) / cell)
        sum_w = sum(w) + wp
        ten_n = 10 * dm["n"]
        rssi = [n["rssi"] for n in nodes]
        chi = [0.0] * (W * H)
        chi_min, best = float("inf"), 0
        for j in range(H):
            y = y0 + (j + 0.5) * cell
            for i in range(W):
                x = x0 + (i + 0.5) * cell
                av = [rssi[k] + ten_n * math.log10(max(0.5, math.hypot(x - P[k][0], y - P[k][1])))
                      for k in range(len(nodes))]
                p0 = (wp * p0_prior + sum(w[k] * av[k] for k in range(len(nodes)))) / sum_w
                q = wp * (p0 - p0_prior) ** 2 + sum(w[k] * (av[k] - p0) ** 2 for k in range(len(nodes)))
                o = j * W + i
                chi[o] = q
                if q < chi_min:
                    chi_min, best = q, o
        dof = len(nodes) + 1 - 3
        s2 = max(1.0, chi_min / dof) if dof > 0 else 1.0
        pw = [math.exp(-0.5 * (c - chi_min) / s2) for c in chi]
        tw = sum(pw)
        bi, bj = best % W, best // W
        lw = mx = my = 0.0
        for j in range(max(0, bj - 2), min(H - 1, bj + 2) + 1):
            for i in range(max(0, bi - 2), min(W - 1, bi + 2) + 1):
                v = pw[j * W + i]
                lw += v
                mx += v * (x0 + (i + 0.5) * cell)
                my += v * (y0 + (j + 0.5) * cell)
        x, y = mx / lw, my / lw
        dist = []
        for o, v in enumerate(pw):
            if v < 1e-9 * tw:
                continue
            dist.append((math.hypot(x0 + ((o % W) + 0.5) * cell - x, y0 + ((o // W) + 0.5) * cell - y), v))
        dist.sort()
        acc, r68 = 0.0, (dist[-1][0] if dist else 0.0)
        for d, v in dist:
            acc += v
            if acc >= 0.68 * tw:
                r68 = d
                break
        err = max(r68, cell * 0.6)
        raw = (lat0 + y / ky, lon0 + x / kx)
        st = self.state.get(mac) or list(raw)
        st = [st[0] + m["smooth"] * (raw[0] - st[0]), st[1] + m["smooth"] * (raw[1] - st[1])]
        self.state[mac] = st
        return {**base, "ok": True, "lat": st[0], "lon": st[1], "err": round(err, 1),
                "rough": err > m["max_err"]}

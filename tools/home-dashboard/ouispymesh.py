#!/usr/bin/env python3
# Copyright (c) 2026 Luke Switzer
# SPDX-License-Identifier: MIT
# Portions derived from OUI-SPY Detector home-dashboard, Copyright (c) 2025-2026 colonelpanichacks (MIT)

"""OUI-APEX Home Dashboard: live mesh status, map, history and node commands, from a board on USB.

    pip install -r requirements.txt
    python ouispymesh.py                     # serial auto-detect, this computer only
    python ouispymesh.py --demo              # simulated fleet, no hardware
    python ouispymesh.py --lan               # let other devices in (they need the access token)

Local only by default: binds 127.0.0.1, data lives in SQLite next to this file.
"""
import argparse
import ipaddress
import os
import re
import socket
import threading
import time

from flask import Flask, Response, abort, jsonify, redirect, render_template, request, url_for
from flask_socketio import SocketIO

import access
import connectors
from board_commands import BoardCommander, PlanError
from board_source import BoardSource
from fleet import Fleet
from sources import DemoSource, MqttSource, list_serial_ports
from store import Store

HERE = os.path.dirname(os.path.abspath(__file__))

DEFAULT_SETTINGS = {
    "sound": True,
    "flash": True,
    "tiles": "osm-dark",            # osm-dark | osm | custom-dark | custom | none
    "tiles_custom": "",
    "notify": False,                # browser notifications on detections / node drops
    "retention_days": 0,            # 0 = keep history forever
    "links": True,                  # draw home-to-remote link lines on the map
    "status_poll": 120,             # s between automatic status reads (0 = off)
    "map_view": None,               # [lat, lon, zoom]
    "tri": {"p0_ble": -59, "p0_wifi": -40, "n": 2.7, "sigma": 4.0, "max_err": 8.0,
            "offsets": {}, "devices": {}, "smooth": 0.35},
    "serial_port": "auto",          # auto | off | a port: COM5, /dev/ttyACM0 | tcp:192.0.2.5[:4700]
    "mqtt": {"enabled": False, "host": "", "port": 1883, "user": "", "password_file": "", "tls": False,
             "topic": "+/detection"},
    "tak": dict(connectors.TAK_DEFAULTS),
    "rns": dict(connectors.RNS_DEFAULTS),
}
CAPS = {"commands": ["status", "identify", "reboot"], "console_input": False, "filters": False,
        "firmware": False, "fleetkey": False, "notes": "Filters, presets, buzzer, channel, firmware and the "
        "fleet key are set from the OUI-APEX app."}


def parse_args():
    ap = argparse.ArgumentParser(description="OUI-APEX home dashboard")
    ap.add_argument("--host", default=os.environ.get("OUISPY_HOST", "127.0.0.1"),
                    help="bind address (default 127.0.0.1 = this computer only; any other address needs the token)")
    ap.add_argument("--lan", action="store_true",
                    help="listen on all interfaces so other devices can open the dashboard; they need the access token")
    ap.add_argument("--new-token", action="store_true", help="make a new access token (shown once) and exit")
    ap.add_argument("--port", type=int, default=int(os.environ.get("OUISPY_PORT", 5077)))
    ap.add_argument("--advertise", action="store_true",
                    help="announce the dashboard on the LAN as _ouispy._tcp (mDNS) so the OUI-APEX app can find it; needs --lan")
    ap.add_argument("--serial", help="serial port, 'auto' (USB VID 0x303A), 'off', or tcp:HOST[:PORT] for the board's USB network port")
    ap.add_argument("--mqtt", help="MQTT broker host[:port] (enables MQTT). The password comes from OUISPY_MQTT_PASSWORD")
    ap.add_argument("--mqtt-user")
    ap.add_argument("--topic", help="MQTT detection topic filter (default +/detection)")
    ap.add_argument("--demo", action="store_true", help="simulated fleet, separate database")
    ap.add_argument("--demo-center", metavar="LAT,LON", help="where the demo fleet sits (default 45.5,-122.6)")
    ap.add_argument("--demo-showcase", action="store_true", help="screenshot-safe demo data")
    ap.add_argument("--prewarm-tiles", action="store_true", help="download map tiles around the nodes in the background")
    ap.add_argument("--download-lookups", action="store_true",
                    help="download the public IEEE and Bluetooth SIG name tables once (outward network)")
    ap.add_argument("--db", help="SQLite path (default ouispy.db / ouispy-demo.db)")
    return ap.parse_args()


args = parse_args()
LAN = args.lan or args.host not in ("127.0.0.1", "localhost", "::1")
BIND = "0.0.0.0" if args.lan else args.host
db_path = args.db or os.path.join(HERE, "ouispy-demo.db" if args.demo else "ouispy.db")
tokens = access.TokenStore()

app = Flask(__name__)
app.config["TEMPLATES_AUTO_RELOAD"] = True
COOKIE = "ouispy_token"


def _peer():
    return request.remote_addr or "", request.headers.get("X-Forwarded-For", "").strip()


def _authorized():
    peer, fwd = _peer()
    return access.authorized(peer, fwd, request.cookies.get(COOKIE) or request.args.get("token"), tokens)


@app.before_request
def _gate():
    if not access.host_allowed(request.host, args.port, LAN):
        return Response("unknown host name", 400, mimetype="text/plain")
    if not access.origin_allowed(request.method, request.headers.get("Origin"), request.host):
        return Response("cross-site request refused", 403, mimetype="text/plain")
    if request.path.startswith("/socket.io"):
        return None
    if not _authorized():
        return Response("OUI-APEX Home Dashboard: open the link with ?token=... (shown once when the token was made)",
                        401, mimetype="text/plain")
    if request.args.get("token") and request.path == "/":
        resp = redirect("/")
        resp.set_cookie(COOKIE, request.args["token"], max_age=365 * 86400, httponly=True, samesite="Strict")
        return resp
    return None


socketio = SocketIO(app, async_mode="threading")
store = Store(db_path)
sources = {}
src_lock = threading.RLock()
seen_drones = set()


def settings():
    s = dict(DEFAULT_SETTINGS)
    s.update(store.all_settings())
    for k in ("mqtt", "tak", "rns"):
        s[k] = {**DEFAULT_SETTINGS[k], **(s.get(k) or {})}
    return s


def command_sender():
    with src_lock:
        for key in ("serial", "demo"):
            src = sources.get(key)
            if src and src.status().get("connected"):
                return src
    return None


def emit(event, payload):
    socketio.emit(event, payload)
    _alerts(event, payload)


def _alerts(event, payload):
    if event == "det" and payload.get("is_new"):
        rns.alert("new_devices", f"New device {payload['mac']} {payload.get('descr') or ''} at {payload['node']}".strip())
    elif event == "node_event" and payload.get("event") == "offline":
        rns.alert("lost_nodes", f"Node {payload['id']} went offline")
    elif event == "drone" and isinstance(payload, dict) and payload.get("mac") not in seen_drones:
        seen_drones.add(payload.get("mac"))
        rns.alert("drones", f"Drone heard: {payload.get('id') or payload.get('mac')}")


fleet = Fleet(store, emit)
import drones as drones_mod
drones = drones_mod.Drones(store, emit)
fleet.drones = drones
import tri as tri_mod


def _node_pos(nid):
    m = store.nodes_meta().get(nid) or {}
    return (m["lat"], m["lon"]) if m.get("lat") is not None and m.get("lon") is not None else None


fleet.tri = tri_mod.Tri(lambda: store.all_settings(), _node_pos)
commander = BoardCommander(fleet, store, emit, command_sender)
fleet.on_join = commander.node_joined


def _collect():
    snap = fleet.snapshot(lists=False)
    return snap["nodes"], drones.snapshot(track=0)


tak = connectors.TakLink(lambda: settings()["tak"], _collect)
rns = connectors.ReticulumLink(lambda: settings()["rns"])


def mqtt_password(m):
    """From the environment or a file the user keeps: never from the dashboard's database."""
    if os.environ.get("OUISPY_MQTT_PASSWORD"):
        return os.environ["OUISPY_MQTT_PASSWORD"]
    try:
        with open(os.path.expanduser(m.get("password_file") or os.devnull)) as f:
            return f.read().strip()
    except OSError:
        return ""


def public_settings():
    s = settings()
    st = sources_status().get("mqtt") or {}
    s["mqtt"] = {**s["mqtt"], "connected": bool(st.get("connected")), "detail": st.get("detail", ""),
                 "password_set": bool(mqtt_password(s["mqtt"]))}
    s["tak"] = {**s["tak"], **{k: v for k, v in tak.status().items() if k in ("state", "sent", "last", "error")}}
    s["rns"] = {**s["rns"], **{k: v for k, v in rns.status().items() if k in ("state", "address", "error")}}
    return s


def sources_status():
    with src_lock:
        return {k: v.status() for k, v in sources.items()}


def on_source_status():
    emit("sources", sources_status())


def start_sources():
    """(Re)start every feed from CLI flags + saved settings."""
    with src_lock:
        for s in sources.values():
            s.stop()
        sources.clear()
    s = settings()
    new = {}
    if args.demo:
        if args.demo_showcase:
            import sources as _src
            _src.use_showcase()
        new["demo"] = DemoSource(fleet, on_source_status)
        _seed_demo_positions()
    else:
        port = args.serial or s["serial_port"]
        if port != "off":
            new["serial"] = BoardSource(fleet, on_source_status, port,
                                        get_pref=lambda: store.get_setting("home_usb_serial"),
                                        set_pref=lambda sn: store.set_setting("home_usb_serial", sn),
                                        get_poll=lambda: settings().get("status_poll"))
        m = s["mqtt"]
        if args.mqtt:
            host, _, p = args.mqtt.partition(":")
            m = {**m, "enabled": True, "host": host, "port": int(p or m["port"] or 1883)}
            if args.mqtt_user:
                m["user"] = args.mqtt_user
            if args.topic:
                m["topic"] = args.topic
        if m.get("enabled") and m.get("host"):
            new["mqtt"] = MqttSource(fleet, on_source_status, m["host"], m["port"], m.get("user", ""),
                                     mqtt_password(m), m.get("topic"), m.get("tls"))
    with src_lock:
        sources.update(new)
    for src in new.values():
        src.start()
    on_source_status()


def _seed_demo_positions():
    from sources import DEMO_HOME, DEMO_REMOTES
    meta = store.nodes_meta()
    base = tuple(float(v) for v in args.demo_center.split(",")) if args.demo_center else (45.5, -122.6)
    offsets = {DEMO_HOME: (0, 0), DEMO_REMOTES[0]: (0.0042, -0.0061),
               DEMO_REMOTES[1]: (-0.0035, -0.0072), DEMO_REMOTES[2]: (0.0068, 0.0081),
               DEMO_REMOTES[3]: (-0.0049, 0.0057)}
    names = {DEMO_HOME: "Base", DEMO_REMOTES[0]: "North Gate", DEMO_REMOTES[1]: "Overpass",
             DEMO_REMOTES[2]: "Ridge Relay", DEMO_REMOTES[3]: "Lot B"}
    for nid, (dlat, dlon) in offsets.items():
        m = meta.get(nid) or {}
        if m.get("lat") is None:
            store.update_node(nid, lat=base[0] + dlat, lon=base[1] + dlon)
        if not m.get("alias"):
            store.update_node(nid, alias=names[nid])
    _backfill_demo_history()


def _backfill_demo_history():
    import random
    from sources import DEMO_HOME, DEMO_REMOTES, DEMO_TARGETS, demo_mac
    if store.query_detections(limit=1)[0]:
        return
    now = time.time()
    base_rssi = {"DE0B": -58, "DE0C": -71, "DE0D": -84, "DE0E": -66}
    for nid in DEMO_REMOTES:
        r, pkts = base_rssi[nid], 0
        for i in range(144):
            ts = now - 86400 + i * 600
            r = max(-95, min(-45, r + random.randint(-3, 3) + (base_rssi[nid] - r) // 4))
            pkts += random.randint(2500, 3500)
            store.add_sighting(nid, "sample", r, pkts, ts)
    nodes = [DEMO_HOME] + DEMO_REMOTES
    for i in range(70):
        oui, ftype, label, dom = random.choice(DEMO_TARGETS)
        store.add_detection({"ts": now - random.uniform(600, 86400), "node": random.choice(nodes),
                             "mac": demo_mac(oui), "alias": "", "rssi": random.randint(-92, -48),
                             "type": ftype, "match": oui.replace(":", ""), "descr": label,
                             "dom": dom, "source": "demo", "is_new": random.random() < 0.3})


def ticker():
    last_prune = 0
    while True:
        time.sleep(1)
        fleet.tick()
        if time.time() - last_prune > 3600:
            last_prune = time.time()
            removed = store.prune(int(settings().get("retention_days") or 0))
            if removed:
                print(f"retention: pruned {removed} old rows")


@app.after_request
def no_cache(resp):
    if request.path.startswith("/api/") or request.path == "/":
        resp.headers["Cache-Control"] = "no-store"
    resp.headers["X-Content-Type-Options"] = "nosniff"
    resp.headers["Referrer-Policy"] = "no-referrer"
    return resp


@app.template_global()
def asset(filename):
    try:
        v = int(os.path.getmtime(os.path.join(app.static_folder, filename)))
    except OSError:
        v = 0
    return url_for("static", filename=filename, v=v)


@app.route("/")
def index():
    return render_template("index.html", demo=args.demo, replay=False)


def _filters():
    a = request.args
    return {"q": a.get("q") or None, "node": a.get("node") or None,
            "dom": a.get("dom") or None, "mac": a.get("mac") or None,
            "since": a.get("since") or None, "until": a.get("until") or None}


def _jobs(node, include_auto=False):
    live = {j["id"]: j for j in commander.recent(node, limit=100)}
    merged = dict(live)
    for j in store.recent_commands(node, limit=60, include_auto=include_auto):
        merged.setdefault(j["id"], j)
    rows = sorted(merged.values(), key=lambda j: j["created"], reverse=True)
    if not include_auto:
        rows = [j for j in rows if not j.get("auto")]
    return rows[:60]


@app.route("/api/state")
def api_state():
    total, recent = store.query_detections(limit=150)
    store.annotate_seen_by(recent)
    return jsonify({"fleet": fleet.snapshot(), "sources": sources_status(),
                    "settings": public_settings(), "stats": store.detection_stats(),
                    "hourly": store.hourly(), "mac_aliases": store.mac_aliases(),
                    "device_names": store.device_names(), "groups": store.groups(),
                    "drones": drones.snapshot(), "drone_tags": drones_mod.TAGS,
                    "tri": list(fleet.tri_fixes.values()),
                    "group_of": store.group_of(),
                    "jobs": _jobs(None), "can_command": command_sender() is not None,
                    "caps": CAPS,
                    "filter_meta": {"types": {}, "hex": {}, "library": [], "presets": {}, "vendors": []},
                    "recent": recent, "console": fleet.console_tail(),
                    "mode": "demo" if args.demo else "live"})


@app.route("/api/detections")
def api_detections():
    limit = min(int(request.args.get("limit", 200)), 2000)
    offset = int(request.args.get("offset", 0))
    total, rows = store.query_detections(limit=limit, offset=offset, **_filters())
    return jsonify({"total": total, "rows": rows})


@app.route("/api/export/detections.<fmt>")
def api_export_det(fmt):
    if fmt not in ("csv", "json"):
        abort(404)
    body = store.export_detections(fmt, **_filters())
    stamp = time.strftime("%Y%m%d-%H%M%S")
    return Response(body, mimetype="text/csv" if fmt == "csv" else "application/json",
                    headers={"Content-Disposition": f"attachment; filename=ouispy-detections-{stamp}.{fmt}"})


@app.route("/api/export/sightings.<fmt>")
def api_export_sig(fmt):
    if fmt not in ("csv", "json"):
        abort(404)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    return Response(store.export_sightings(fmt), mimetype="text/csv" if fmt == "csv" else "application/json",
                    headers={"Content-Disposition": f"attachment; filename=ouispy-sightings-{stamp}.{fmt}"})


@app.route("/api/detections/clear", methods=["POST"])
def api_clear():
    body = request.get_json(silent=True) or {}
    node, mac = body.get("node") or None, body.get("mac") or None
    n = store.clear_detections(node, mac)
    emit("dets_cleared", {"node": node, "mac": mac, "n": n})
    return jsonify({"ok": True, "n": n})


@app.route("/api/metrics")
def api_metrics():
    rng = max(300, min(90 * 86400, int(request.args.get("range") or 86400)))
    until = time.time()
    return jsonify(store.metrics(until - rng, until, request.args.get("node") or None,
                                 request.args.get("dom") or None))


@app.route("/api/stats")
def api_stats():
    return jsonify({**store.detection_stats(), "hourly": store.hourly()})


@app.route("/api/devices")
def api_devices():
    f = _filters()
    total, rows = store.devices(q=f["q"], node=f["node"], dom=f["dom"],
                                limit=min(int(request.args.get("limit", 300)), 2000))
    return jsonify({"total": total, "rows": rows})


@app.route("/api/devices/<mac>", methods=["GET"])
def api_device_detail(mac):
    import lookups
    from fleet import intel_name
    mac = mac.upper()
    rec = store.device_intel(mac) or {}
    intel = lookups.decorate(rec.get("intel") or {})
    agg, hist = store.device_history(mac, limit=int(request.args.get("limit", 60)))
    alias = store.mac_aliases().get(mac, {})
    comps = store.companions(mac)
    names = store.device_names()
    groups = store.group_of()
    for c in comps:
        c["name"] = names.get(c["mac"], "")
        c["alias"] = store.mac_aliases().get(c["mac"], {}).get("alias", "")
        c["group"] = groups.get(c["mac"])
        c["vendor"] = lookups.oui_vendor(c["mac"])
    if request.args.get("flat"):
        info = {"intel": intel, "mac_kind": lookups.mac_kind(mac), "oui_vendor": lookups.oui_vendor(mac), "stats": agg}
        return jsonify({"mac": mac, "name": intel_name(rec.get("intel")) or "", "alias": alias.get("alias", ""),
                        "group": groups.get(mac), "rows": _flat_intel(info, lookups),
                        "companions": [{"mac": c["mac"], "label": c["alias"] or c["name"] or c["descr"] or c["vendor"],
                                        "together": c["together"], "occasions": c["occasions"],
                                        "group": (c["group"] or {}).get("name", "")} for c in comps[:8]],
                        "groups": [{"id": g["id"], "name": g["name"], "n": len(g["members"])} for g in store.groups()]})
    return jsonify({
        "mac": mac, "name": intel_name(rec.get("intel")) or "",
        "alias": alias.get("alias", ""), "notes": alias.get("notes", ""),
        "group": groups.get(mac), "oui_vendor": lookups.oui_vendor(mac),
        "mac_kind": lookups.mac_kind(mac),
        "intel": intel, "intel_first": rec.get("first"), "intel_last": rec.get("last"),
        "intel_reports": rec.get("reports", 0),
        "stats": agg, "history": hist, "companions": comps,
    })


@app.route("/api/drones")
def api_drones():
    return jsonify({"live": drones.snapshot(track=int(request.args.get("track", 60))),
                    "recent": drones.recent(hours=float(request.args.get("hours", 24))),
                    "tags": drones_mod.TAGS})


@app.route("/api/drones/<mac>", methods=["GET"])
def api_drone(mac):
    d = drones.detail(mac, since=float(request.args["since"]) if request.args.get("since") else None)
    return (jsonify(d), 200) if d else (jsonify({"error": "unknown drone"}), 404)


@app.route("/api/drones/<mac>", methods=["POST"])
def api_drone_meta(mac):
    data = request.get_json(silent=True) or {}
    drones.set_meta(mac, alias=(str(data["alias"])[:40].strip() if "alias" in data else None),
                    tag=data.get("tag"), notes=(str(data["notes"])[:500] if "notes" in data else None))
    return jsonify({"ok": True, "drone": drones.detail(mac)})


@app.route("/api/drones/<mac>/faa", methods=["POST"])
def api_drone_faa(mac):
    d = drones.detail(mac)
    serial = (request.get_json(silent=True) or {}).get("serial") or (d or {}).get("id")
    if not serial:
        return jsonify({"ok": False, "error": "no serial number broadcast yet"}), 400
    try:
        res = drones_mod.faa_lookup(serial)
    except Exception as e:
        return jsonify({"ok": False, "error": f"FAA lookup failed: {e}"}), 502
    drones.set_meta(mac, faa=res)
    return jsonify({"ok": True, "faa": res})


@app.route("/tiles/<layer>/<int:z>/<int:x>/<int:y>")
def tile_proxy(layer, z, x, y):
    import tiles
    try:
        data, mime = tiles.tile(layer, z, x, y)
    except KeyError:
        return ("", 404)
    except Exception as e:
        return (f"tile fetch failed: {e}", 502)
    resp = app.response_class(data, mimetype=mime)
    resp.headers["Cache-Control"] = "public, max-age=604800"
    return resp


@app.route("/api/tiles")
def api_tiles():
    import tiles
    return jsonify({k: {"name": v["name"], "max": v["max"], "ext": v["ext"]} for k, v in tiles.LAYERS.items()})


def _flat_intel(info, lookups):
    """Device detail as [label, value] text rows, for small displays."""
    it = info.get("intel") or {}
    kind = info.get("mac_kind") or {}
    rows = []

    def add(k, v):
        if v not in (None, "", [], {}):
            rows.append([k, str(v)])
    by_last = lambda o: sorted(o or {}, key=lambda k: -(o[k].get("last") or 0))
    add("Broadcast name", f'"{it["name"]}"' if it.get("name") else "")
    add("Earlier names", ", ".join(f'"{n}"' for n in by_last(it.get("names")) if n != it.get("name")))
    add("MAC vendor", info.get("oui_vendor") or ("randomized address" if kind.get("local") else "not registered"))
    if "rnd" in it:
        add("Address", ("random (" + kind.get("ble_random_kind", "") + ")") if it["rnd"] else "public")
    if "conn" in it:
        add("Connectable", "yes" if it["conn"] else "no")
    if it.get("cid"):
        add("Company ID", f'0x{it["cid"]} {it.get("cid_name", "")}'.strip())
    add("Manufacturer data", it.get("mfr"))
    add("Services", ", ".join(f'{u["uuid"]} {u["name"]}'.strip() for u in it.get("uuids_named") or []))
    add("128-bit service", it.get("uuid128"))
    add("Service data", ", ".join(f'{u["uuid"]}={u["data"]}' for u in it.get("sdata_named") or []))
    if it.get("app") is not None:
        add("Appearance", it.get("app_name") or it["app"])
    if it.get("tx") is not None:
        add("TX power", f'{it["tx"]} dBm')
    add("Frames", it.get("frame"))
    ssids = by_last(it.get("ssids"))
    ap = it.get("frame") in ("beacon", "probe-resp")
    add("SSID" if ap else "Looks for", ", ".join(s or "(hidden)" for s in ssids))
    add("Joins", ", ".join(f'{b} {it["aps"][b].get("ssid", "")}'.strip() for b in by_last(it.get("aps"))))
    add("Security", it.get("sec"))
    add("Channel", it.get("ch"))
    if it.get("phy"):
        add("Wi-Fi", "802.11" + it["phy"] + (f' (to {it["rate"]} Mb/s legacy)' if it.get("rate") else ""))
    if it.get("wps"):
        add("WPS", "on")
    add("Country", it.get("cc"))
    add("Vendor IEs", ", ".join(f'{v["oui"]} {v["name"]}'.strip() for v in it.get("vie_named") or []))
    st = info.get("stats") or {}
    if st.get("n"):
        add("Detections", f'{st["n"]}  best {st.get("best")} dBm  avg {round(st.get("avg") or 0)} dBm')
    return rows


@app.route("/api/groups", methods=["GET"])
def api_groups():
    return jsonify({"groups": store.groups(), "group_of": store.group_of()})


@app.route("/api/groups", methods=["POST"])
def api_group_save():
    data = request.get_json(silent=True) or {}
    gid = data.get("id")
    if data.get("delete") and gid:
        store.delete_group(int(gid))
    else:
        name = str(data.get("name") or "").strip()[:40]
        if not name and not gid:
            return jsonify({"ok": False, "error": "name required"}), 400
        if name or data.get("notes") is not None or data.get("color") is not None:
            cur = next((g for g in store.groups() if g["id"] == gid), {}) if gid else {}
            gid = store.save_group(int(gid) if gid else None, name or cur.get("name", ""),
                                   str(data.get("notes") if data.get("notes") is not None else cur.get("notes") or "")[:500],
                                   data.get("color", cur.get("color")))
        for m in data.get("add") or []:
            store.set_group(str(m).upper(), int(gid))
        for m in data.get("remove") or []:
            store.set_group(str(m).upper(), None)
    payload = {"groups": store.groups(), "group_of": store.group_of()}
    emit("groups", payload)
    return jsonify({"ok": True, "id": gid, **payload})


@app.route("/api/devices/<mac>", methods=["POST"])
def api_device_alias(mac):
    data = request.get_json(silent=True) or {}
    mac = mac.upper()
    cur = store.mac_aliases().get(mac) or {}
    alias = str(data["alias"] if "alias" in data else cur.get("alias", "") or "")[:40].strip()
    notes = str(data["notes"] if "notes" in data else cur.get("notes", "") or "")[:500] or None
    store.set_mac_alias(mac, alias, notes)
    aliases = store.mac_aliases()
    emit("mac_aliases", aliases)
    return jsonify({"ok": True, "mac_aliases": aliases})


@app.route("/api/nodes/<nid>", methods=["GET"])
def api_node(nid):
    nid = nid.upper()
    snap = fleet.snapshot()
    node = next((n for n in snap["nodes"] if n["id"] == nid), None)
    if node is None:
        abort(404)
    hours = float(request.args.get("hours", 24))
    _, dets = store.query_detections(limit=60, node=nid)
    stats = store.detection_stats()["per_node"].get(nid, {"count": 0, "last": None})
    return jsonify({"node": node, "sightings": store.node_sightings(nid, time.time() - hours * 3600),
                    "detections": dets, "stats": stats})


@app.route("/api/nodes/<nid>", methods=["POST"])
def api_node_update(nid):
    data = request.get_json(silent=True) or {}
    fields = {}
    if "alias" in data:
        fields["alias"] = str(data["alias"] or "")[:40].strip()
    if "notes" in data:
        fields["notes"] = str(data["notes"] or "")[:500]
    for k in ("lat", "lon"):
        if k in data:
            v = data[k]
            fields[k] = None if v is None else float(v)
    if "color" in data:
        v = data["color"]
        fields["color"] = None if v is None or v == "" else int(v) % 360
    store.update_node(nid.upper(), **fields)
    emit("fleet", fleet.snapshot())
    return jsonify({"ok": True, "pushed": None})


GPS_STATE = {}
TRAIL_SECONDS = 1800


@app.route("/api/nodes/<nid>/gps", methods=["POST"])
def api_node_gps(nid):
    nid = nid.upper()
    d = request.get_json(silent=True) or {}
    try:
        lat, lon = float(d["lat"]), float(d["lon"])
        acc = float(d.get("acc") or 0) or None
    except (KeyError, TypeError, ValueError):
        return jsonify({"ok": False, "error": "lat/lon required"}), 400
    if not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return jsonify({"ok": False, "error": "bad coordinates"}), 400
    now = time.time()
    store.update_node(nid, lat=lat, lon=lon)
    store.add_track(nid, lat, lon, acc, now)
    GPS_STATE[nid] = {"ts": now, "acc": acc}
    emit("gps", {"node": nid, "lat": lat, "lon": lon, "acc": acc, "ts": now})
    return jsonify({"ok": True})


@app.route("/api/nodes/<nid>/gps", methods=["DELETE"])
def api_node_gps_stop(nid):
    nid = nid.upper()
    GPS_STATE.pop(nid, None)
    if request.args.get("clear") == "1":
        store.clear_track(nid)
    emit("gps_stop", {"node": nid, "cleared": request.args.get("clear") == "1"})
    return jsonify({"ok": True})


@app.route("/api/tracks")
def api_tracks():
    secs = max(60, min(int(request.args.get("seconds", TRAIL_SECONDS)), 7 * 86400))
    return jsonify({"tracks": store.tracks(time.time() - secs), "seconds": secs,
                    "live": {k: v for k, v in GPS_STATE.items() if time.time() - v["ts"] < 60}})


@app.route("/api/nodes/<nid>", methods=["DELETE"])
def api_node_forget(nid):
    nid = nid.upper()
    with fleet.lock:
        st = fleet.nodes.get(nid)
        if st and st["online"]:
            return jsonify({"ok": False, "error": "node is online"}), 409
        fleet.nodes.pop(nid, None)
    store.forget_node(nid)
    emit("fleet", fleet.snapshot())
    return jsonify({"ok": True})


def _submit(op, target, args):
    try:
        return jsonify({"ok": True, "job": commander.submit(op, target, args)})
    except PlanError as e:
        return jsonify({"ok": False, "error": str(e)}), 400
    except (TypeError, ValueError) as e:
        return jsonify({"ok": False, "error": f"bad arguments: {e}"}), 400


@app.route("/api/nodes/<nid>/cmd", methods=["POST"])
def api_node_cmd(nid):
    data = request.get_json(silent=True) or {}
    return _submit(str(data.get("op", "")), nid.upper(), data.get("args") or {})


@app.route("/api/fleet/cmd", methods=["POST"])
def api_fleet_cmd():
    data = request.get_json(silent=True) or {}
    return _submit(str(data.get("op", "")), "all", data.get("args") or {})


@app.route("/api/jobs")
def api_jobs():
    return jsonify(_jobs(request.args.get("node") or None, include_auto=request.args.get("auto") == "1"))


@app.route("/api/settings", methods=["GET"])
def api_settings():
    return jsonify(public_settings())


def clean_tri(new, cur):
    if not isinstance(new, dict):
        raise ValueError("expected an object")
    out = {**DEFAULT_SETTINGS["tri"], **(cur or {})}
    clamp = {"p0_ble": (-90, -20), "p0_wifi": (-90, -10), "n": (1.6, 5.0), "smooth": (0.05, 1.0),
             "sigma": (1.5, 12.0), "max_err": (2.0, 30.0)}
    for k, (lo, hi) in clamp.items():
        if k in new:
            out[k] = round(min(hi, max(lo, float(new[k]))), 2)
    if "offsets" in new:
        offs = new["offsets"] or {}
        if not isinstance(offs, dict):
            raise ValueError("offsets must map node IDs to dB")
        out["offsets"] = {str(k).upper(): round(min(40.0, max(-40.0, float(v))), 1)
                          for k, v in offs.items() if re.fullmatch(r"[0-9A-Fa-f]{4}", str(k))}
    if "devices" in new:
        devs = new["devices"] or {}
        if not isinstance(devs, dict):
            raise ValueError("devices must map MACs to calibrations")
        out["devices"] = {}
        for mac, c in devs.items():
            mac = str(mac).upper()
            if not re.fullmatch(r"[0-9A-F]{2}(:[0-9A-F]{2}){5}", mac) or not isinstance(c, dict):
                continue
            out["devices"][mac] = {"p0": round(min(0.0, max(-100.0, float(c["p0"]))), 1),
                                   "n": round(min(5.0, max(1.6, float(c["n"]))), 2),
                                   "rms": round(min(30.0, max(0.0, float(c.get("rms", 0)))), 1),
                                   "nodes": int(c.get("nodes", 0)), "ts": float(c.get("ts", 0))}
    return out


def clean_tak(new, cur):
    out = {**cur}
    if "enabled" in new:
        out["enabled"] = bool(new["enabled"])
    for k in ("host", "callsign", "ca_file", "cert_file", "key_file"):
        if k in new:
            out[k] = str(new[k] or "").strip()[:200]
    if "proto" in new:
        if new["proto"] not in ("tcp", "udp", "tls"):
            raise ValueError("protocol must be tcp, udp or tls")
        out["proto"] = new["proto"]
    if "port" in new:
        p = int(new["port"])
        if not 1 <= p <= 65535:
            raise ValueError("port must be 1-65535")
        out["port"] = p
    if out["enabled"] and not out["host"]:
        raise ValueError("a TAK server address is needed")
    return out


def clean_rns(new, cur):
    out = {**cur}
    if "enabled" in new:
        out["enabled"] = bool(new["enabled"])
    if "recipients" in new:
        rec = [str(r).strip().lower().replace("<", "").replace(">", "") for r in new["recipients"] or []]
        bad = [r for r in rec if not re.fullmatch(r"[0-9a-f]{32}", r)]
        if bad:
            raise ValueError("a Reticulum address is 32 hex digits")
        out["recipients"] = rec[:16]
    if "send" in new and isinstance(new["send"], dict):
        out["send"] = {k: bool(new["send"].get(k, out["send"].get(k, True))) for k in connectors.ALERT_KINDS}
    if out["enabled"] and not out["recipients"]:
        raise ValueError("add at least one recipient address first")
    return out


@app.route("/api/settings", methods=["POST"])
def api_settings_set():
    data = request.get_json(silent=True) or {}
    restart = False
    if "status_poll" in data:
        data["status_poll"] = max(0, int(data["status_poll"] or 0))
    if "retention_days" in data:
        data["retention_days"] = max(0, int(data["retention_days"] or 0))
    for k in ("sound", "flash", "tiles", "tiles_custom", "map_view", "notify", "retention_days", "links",
              "traffic", "status_poll"):
        if k in data:
            store.set_setting(k, data[k])
    if "tri" in data:
        try:
            store.set_setting("tri", clean_tri(data["tri"], settings().get("tri") or {}))
        except (TypeError, ValueError) as e:
            return jsonify({"ok": False, "error": f"triangulation settings: {e}"}), 400
    for key, fn in (("tak", clean_tak), ("rns", clean_rns)):
        if key in data and isinstance(data[key], dict):
            try:
                store.set_setting(key, fn(data[key], settings()[key]))
            except (TypeError, ValueError) as e:
                return jsonify({"ok": False, "error": f"{key.upper()}: {e}"}), 400
    if "serial_port" in data:
        store.set_setting("serial_port", str(data["serial_port"]) or "auto")
        restart = True
    if "mqtt" in data and isinstance(data["mqtt"], dict):
        if data["mqtt"].get("password"):
            return jsonify({"ok": False, "error": "passwords are not stored here: set OUISPY_MQTT_PASSWORD "
                            "or point password_file at a file only you can read"}), 400
        cur = settings()["mqtt"]
        new = {**cur, **{k: v for k, v in data["mqtt"].items()
                         if k in ("enabled", "host", "port", "user", "password_file", "topic", "tls")}}
        new["port"] = int(new.get("port") or 1883)
        store.set_setting("mqtt", new)
        restart = True
    if restart and not args.demo:
        start_sources()
    if set(data) - {"map_view"}:
        emit("settings", public_settings())
    return jsonify(public_settings())


@app.route("/api/tak")
def api_tak():
    return jsonify(tak.status())


@app.route("/api/rns")
def api_rns():
    return jsonify(rns.status())


@app.route("/api/ports")
def api_ports():
    return jsonify(list_serial_ports())


@app.route("/api/console", methods=["POST"])
def api_console():
    return jsonify({"ok": False, "error": "the OUI-APEX board has no text console; commands go through the node controls"}), 400


@socketio.on("connect")
def on_connect():
    if not _authorized():
        return False
    socketio.emit("sources", sources_status(), to=request.sid)


def _addresses():
    out = []
    try:
        sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sk.connect(("10.255.255.255", 1))
        out.append(sk.getsockname()[0])
        sk.close()
    except OSError:
        pass
    seen = []
    for ip in out:
        try:
            a = ipaddress.ip_address(ip)
        except ValueError:
            continue
        if not a.is_loopback and ip not in seen:
            seen.append(ip)
    return seen


def advertise():
    """Announce the dashboard on the local network as _ouispy._tcp (multicast DNS, LAN only) under the
    generic name "OUI-APEX Home Dashboard": no node IDs, no host name, no token. Only with --advertise."""
    import shutil
    import subprocess
    name, kind, txt = "OUI-APEX Home Dashboard", "_ouispy._tcp", "api=1"
    for cmd in (["dns-sd", "-R", name, kind, "local", str(args.port), txt],
                ["avahi-publish-service", name, kind, str(args.port), txt]):
        if shutil.which(cmd[0]):
            try:
                proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                import atexit
                atexit.register(proc.terminate)
                print(f"  mDNS           {kind} on port {args.port}")
            except OSError:
                pass
            return
    try:
        from zeroconf import ServiceInfo, Zeroconf
        ips = [socket.inet_aton(ip) for ip in _addresses()]
        if ips:
            zc = Zeroconf()
            zc.register_service(ServiceInfo(f"{kind}.local.", f"{name}.{kind}.local.", port=args.port,
                                            addresses=ips, properties={"api": "1"}))
            print(f"  mDNS           {kind} on port {args.port}")
    except Exception:
        print("  mDNS           could not start (no dns-sd, avahi or zeroconf)")


def _prewarm_tiles():
    import tiles
    while True:
        pts = [(m["lat"], m["lon"]) for m in store.nodes_meta().values()
               if m.get("lat") is not None and m.get("lon") is not None]
        try:
            n = tiles.prewarm(pts)
            if n:
                print(f"[tiles] cached {n} new tiles around the fleet")
        except Exception as e:
            print(f"[tiles] prewarm: {e}")
        time.sleep(6 * 3600)


def main():
    if args.new_token:
        print(f"New access token (shown once, only its hash is kept): {tokens.create()}")
        return
    import faulthandler
    import signal as _signal
    faulthandler.register(_signal.SIGUSR1, all_threads=True)
    start_sources()
    commander.start()
    if args.prewarm_tiles and not args.demo:
        threading.Thread(target=_prewarm_tiles, daemon=True, name="tile-prewarm").start()
    if args.download_lookups:
        import lookups
        threading.Thread(target=lookups.ensure_data, daemon=True, name="lookup-data").start()
    import atexit

    def _close_feeds(*_):
        with src_lock:
            for src in sources.values():
                src.stop()
                sess = getattr(src, "session", None)
                if sess:
                    sess.close()
    atexit.register(_close_feeds)
    signal = _signal
    signal.signal(signal.SIGTERM, lambda *a: (_close_feeds(), os._exit(0)))
    threading.Thread(target=ticker, daemon=True).start()
    print(f"OUI-APEX Home Dashboard [{'DEMO' if args.demo else 'LIVE'}]  (db: {db_path})")
    print(f"  this computer:  http://127.0.0.1:{args.port}")
    if LAN:
        if not tokens.exists():
            print(f"  access token (shown once, only its hash is kept): {tokens.create()}")
        else:
            print("  other devices need the access token (--new-token makes a new one)")
        for ip in _addresses():
            print(f"  network        http://{ip}:{args.port}")
        print("  this link is plain HTTP: use it on a network you trust, or put an HTTPS proxy or VPN in front")
        if args.advertise:
            advertise()
    elif args.advertise:
        print("  --advertise needs --lan: not announcing")
    socketio.run(app, host=BIND, port=args.port, allow_unsafe_werkzeug=True)


if __name__ == "__main__":
    main()

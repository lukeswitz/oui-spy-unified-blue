// OUI-APEX Home Dashboard client (derived from OUI-SPY Mesh, MIT, colonelpanichacks). Server pushes everything over Socket.IO:
//   fleet (roster + home stats), det (one detection), console (raw line),
//   node_event (online/offline), sources (feed status), mac_aliases.
(() => {
"use strict";

const S = {
    fleet: { home: {}, nodes: [], ts: 0 },
    skew: 0,                  // client clock - server clock (s)
    settings: {},
    sources: {},
    dets: [],                 // live feed, newest first
    selected: null,
    placing: false,
    markers: {},
    hist: { offset: 0, rows: [] },
    statsBase: null,
    hourly: [],               // [{h, c}] detections per hour, last 24 h
    macAliases: {},           // MAC -> {alias, notes}, dashboard-local
    deviceNames: {},          // MAC -> name it advertises (BLE name / AP SSID)
    groups: [],               // [{id, name, notes, color, members}]
    groupOf: {},              // MAC -> {id, name, color}
    links: null,              // Leaflet layer group for home-to-remote lines
    device: null,             // MAC open in the device drawer
    booted: false,
    prevHomeAlive: null,
    prevHeal: 0,
    jobs: [],                 // remote-management command log (newest first)
    trails: {},               // node -> [[ts, lat, lon, acc]] GPS breadcrumbs (last 30 min)
    gpsLive: {},              // node -> ts of its latest phone fix
    gps: null,                // this phone carrying a node: {node, watch, lastSent, last, lock}
    jobState: {},             // job id -> last seen state (for finish toasts)
    filterMeta: null,         // types, hex lengths, presets
    editing: null,            // filter rows being edited in the drawer
    editFor: null,            // node the editor belongs to
    audioDirty: null,         // node whose buzzer/LED switches the user touched
    loadHomePending: false,
};
const $ = (id) => document.getElementById(id);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const now = () => Date.now() / 1000 - S.skew;

async function api(path, opts = {}) {
    const r = await fetch(path, {
        headers: opts.body ? { "Content-Type": "application/json" } : {},
        ...opts,
        body: opts.body ? JSON.stringify(opts.body) : undefined,
    });
    return r.json();
}

// ------------------------------------------------------------------
// helpers
// ------------------------------------------------------------------
// Per-browser preferences (layout, toggles); every access survives a blocked or private storage.
function lsGet(k, d) { try { const v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } }
function lsSet(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* private window */ } }
// A dedicated Sky-Spy drone node reports its build stamp with an "S" suffix.
function isSkySpy(n) { return !!(n && n.cfg && /S$/.test(String(n.cfg.fw || "").trim())); }
function nodeById(id) { return S.fleet.nodes.find((n) => n.id === id); }
function nodeName(id) {
    const n = nodeById(id);
    return (n && n.alias) || id || "?";
}
function devAlias(mac, fallback) {
    const a = S.macAliases[mac];
    return (a && a.alias) || fallback || "";
}
// The name a device gives itself over the air (BLE local name, an AP's SSID).
function devName(mac, fallback) { return S.deviceNames[mac] || fallback || ""; }
function devGroup(mac) { return S.groupOf[mac] || null; }
function groupTag(mac) {
    const g = devGroup(mac);
    return g ? `<span class="gtag" style="--gh:${g.color ?? 280}">${esc(g.name)}</span>` : "";
}
function metres(a, b) {
    return map.distance([a.lat, a.lon], [b.lat, b.lon]);
}
function fmtDist(m) {
    return m >= 1000 ? `${(m / 1000).toFixed(2)} km` : `${Math.round(m)} m`;
}
function ago(ts) {
    if (!ts) return "never";
    const s = Math.max(0, now() - ts);
    if (s < 2) return "now";
    if (s < 60) return `${Math.floor(s)}s ago`;
    if (s < 3600) return `${Math.floor(s / 60)}m ago`;
    if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
    return `${Math.floor(s / 86400)}d ago`;
}
function hms(ts) {
    return new Date(ts * 1000).toLocaleTimeString([], { hour12: false });
}
function fullTime(ts) {
    const d = new Date(ts * 1000);
    return d.toLocaleDateString([], { month: "short", day: "2-digit" }) + " " + hms(ts);
}
function uptime(s) {
    if (s == null) return "-";
    const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
    return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m ${s % 60}s`;
}
function nodeState(n) {
    if (!n.online) return "offline";
    const age = now() - (n.last_seen || 0);
    return age > 6 ? "stale" : "online";
}
function bars(rssi) {
    if (!rssi) return `<span class="bars"><i></i><i></i><i></i><i></i></span>`;
    const lvl = rssi >= -60 ? 4 : rssi >= -70 ? 3 : rssi >= -80 ? 2 : 1;
    const cls = lvl === 2 ? "weak" : lvl === 1 ? "poor" : "";
    return `<span class="bars ${cls}">` + [1, 2, 3, 4].map((i) => `<i class="${i <= lvl ? "lit" : ""}"></i>`).join("") + "</span>";
}

// ------------------------------------------------------------------
// header: sources, toggles, clock
// ------------------------------------------------------------------
// Serial health is about data, not just an open port: every line blinks
// the dot; open-but-silent for 7 s (TLM is every 5 s) turns it amber (stuck or rebooting board).
S.serialLast = 0;
S.sockUp = true;   // the page itself just loaded from the dashboard
// Binary and steady: green LIVE only while the port is open, the home is
// sending (TLM every 5 s) and this page is connected to the dashboard;
// red otherwise, with the reason. No blinking.
function serialPillState(s) {
    if (!S.sockUp) return ["", "DASHBOARD OFFLINE"];
    if (!s.connected) return ["", "DISCONNECTED"];
    if (Date.now() / 1000 - S.serialLast > 7) return ["", "NO DATA"];
    return ["on usb", "LIVE"];
}
function updateSerialPill() {
    const s = S.sources.serial;
    const el = document.querySelector('.src-pill[data-kind="serial"]');
    if (!s || !el) return;
    const [cls, word] = serialPillState(s);
    const dot = el.querySelector(".dot"), st = el.querySelector(".state");
    if (dot.className !== `dot ${cls}`) dot.className = `dot ${cls}`;
    if (st.textContent !== word) st.textContent = word;
    el.classList.toggle("down", cls === "");
}
// The pill runs on this browser's own clock: the server-clock offset (S.skew) moves
// with every fleet update, and a late one made a live feed read as NO DATA.
function serialBlink() {
    const was = Date.now() / 1000 - S.serialLast > 7;
    S.serialLast = Date.now() / 1000;
    if (was) updateSerialPill();   // data back: green at once
}
setInterval(updateSerialPill, 500);

function renderSources() {
    if (S.booted) { renderFleetCtl(); renderRemote(); }
    const box = $("sources");
    const entries = Object.values(S.sources);
    if (!entries.length) {
        box.innerHTML = `<span class="src-pill"><span class="dot"></span><b>NO FEED</b> serial off, MQTT not configured</span>`;
        return;
    }
    box.innerHTML = entries.map((s) => {
        if (s.kind === "serial") {
            const [cls, word] = serialPillState(s);
            return `<span class="src-pill" data-kind="serial" title="${esc(s.detail)}"><span class="dot ${cls}"></span>` +
                `<b>USB</b> <span class="state">${word}</span> <span class="src-detail">${esc(s.connected ? s.port || "" : s.detail || "")}</span></span>`;
        }
        let extra = "";
        if (s.kind === "mqtt" && s.availability) extra = ` | ${esc(s.device)}: ${esc(s.availability)}`;
        return `<span class="src-pill" title="${esc(s.detail)}"><span class="dot ${s.connected ? "on" : "warn"}"></span>` +
            `<b>${esc(s.kind.toUpperCase())}</b> <span class="src-detail">${esc(s.detail || "")}${extra}</span></span>`;
    }).join("");
}

function renderToggles() {
    $("soundBtn").classList.toggle("on", !!S.settings.sound);
    $("flashBtn").classList.toggle("on", !!S.settings.flash);
}
$("soundBtn").onclick = () => {
    S.settings.sound = !S.settings.sound;
    renderToggles();
    api("/api/settings", { method: "POST", body: { sound: S.settings.sound } });
    if (S.settings.sound) beep(true);
};
$("flashBtn").onclick = () => {
    S.settings.flash = !S.settings.flash;
    renderToggles();
    api("/api/settings", { method: "POST", body: { flash: S.settings.flash } });
};

// ------------------------------------------------------------------
// fleet panel
// ------------------------------------------------------------------
function renderHome() {
    const h = S.fleet.home || {};
    const alive = h.alive;
    const fail = h.tx ? ((h.txf || 0) / h.tx * 100) : 0;
    const cells = [
        ["Home", h.id ? `${esc(nodeName(h.id))}` : "-", alive ? "good" : "bad", true],
        ["State", alive ? (h.mode === "config" ? "CONFIG" : "SCANNING") : "SILENT", alive ? "good" : "bad", true],
        ["Chan", h.ch ?? "-"],
        ["Radio", h.rate ? (h.rate.startsWith("lr") && h.rate !== "lr-failed" ? `LR ${h.rate.slice(2)}` : h.rate.toUpperCase()) : "-",
         h.rate && h.rate.startsWith("lr") && h.rate !== "lr-failed" ? "good" : h.rate ? "warn" : ""],
        ["Peers", h.n ?? "-", h.n ? "good" : "warn"],
        ["lRSSI", h.lrssi ? `${h.lrssi}` : "-"],
        ["Uptime", uptime(h.up)],
        ["RX", h.rx ?? "-"],
        ["TX", h.tx ?? "-"],
        ["TX fail", h.tx != null ? `${fail.toFixed(1)}%` : "-", fail > 10 ? "bad" : fail > 3 ? "warn" : ""],
        ["Dup", h.dup ?? "-"],
        ["MQTT", h.mqtt == null ? "-" : h.mqtt ? "UP" : "DOWN", h.mqtt ? "good" : ""],
        ["TX q", h.pend ?? "-"],
        ["Heap", h.heap ? `${Math.round(h.heap / 1024)}K` : "-"],
        ["Heal", h.heal ? "SWEEP" : "-", h.heal ? "warn" : ""],
    ];
    // Mesh duty: how much of the time the radio is actually listening on the
    // mesh channel. Time shared with a BLE scan mostly goes to BLE.
    if (h.park != null) {
        const clear = h.park - (h.pble || 0);
        cells.push(["On mesh", `${h.park}%`, h.park >= 50 ? "good" : h.park >= 25 ? "warn" : "bad"],
                   ["Mesh, no BLE", `${clear}%`, clear >= 30 ? "good" : clear >= 15 ? "warn" : "bad"]);
    }
    // Acked delivery (firmware 35d27bc+): detections this node originated.
    if (h.dsent != null) {
        cells.push(["Dets sent", h.dsent], ["Acked", h.dack, h.dack ? "good" : ""],
                   ["Lost", h.dlost, h.dlost ? "bad" : ""], ["Retries", `${h.dretry}${h.dpend ? ` / ${h.dpend} pend` : ""}`]);
    }
    if (h.enc != null) {
        cells.push(["Encryption", h.enc ? "AES-256 ON" : "OFF", h.enc ? "good" : "bad", true]);
        if (h.enc && (h.eauth || h.ereplay || h.eplain)) {
            cells.push(["Rejected", `${h.eauth || 0} auth / ${h.ereplay || 0} replay / ${h.eplain || 0} plain`, "warn", true]);
        }
    }
    if (h.nvs != null) cells.push(["NVS free", `${h.nvs}`, h.nvs < 40 ? "bad" : h.nvs < 120 ? "warn" : "good"]);
    if (h.legacy) cells.push(["Firmware", "legacy (no TLM)", "warn", true]);
    // A strong node next door leaks into the channels beside its own, so the
    // home's sweep can "hear" it elsewhere. Trust the node's own fresh
    // report: it's only stray if it doesn't say it's on the fleet channel.
    const strays = (h.strays || []).filter((x) => {
        const n = nodeById(x.id);
        const c = n && n.cfg;
        return !(c && n.online && c.ch === h.ch && now() - (n.cfg_ts || 0) < 120);
    });
    if (strays.length) {
        cells.push(["Wrong channel", strays.map((x) => `${esc(nodeName(x.id))} on ${x.ch}`).join(", "), "bad", true]);
    }
    $("homeStats").innerHTML = cells.map(([k, v, cls, wide]) =>
        `<div class="hs${wide ? " wide" : ""}"><div class="k">${k}</div><div class="v ${cls || ""}">${v}</div></div>`).join("");
}

function renderNodes() {
    const list = $("nodeList");
    const nodes = S.fleet.nodes;
    const online = nodes.filter((n) => n.online).length;
    $("fleetCount").textContent = `${online} / ${nodes.length} online`;
    if (!nodes.length) {
        list.innerHTML = `<div class="empty">No nodes yet. Plug in the home node or start an MQTT feed.</div>`;
        delete list.dataset.ids;
        return;
    }
    const perNode = (S.statsBase && S.statsBase.per_node) || {};
    // Stable cards: Home first, then by name, never reordered by status; every
    // card has the same fixed columns (tabular digits), and an update patches
    // the card in place instead of rebuilding the list.
    const order = [...nodes].sort((a, b) => (b.is_home - a.is_home) ||
        (a.alias || a.id).localeCompare(b.alias || b.id, undefined, { sensitivity: "base" }));
    if (list.querySelector(".empty")) list.innerHTML = "";
    const ids = order.map((n) => n.id).join(",");
    if (list.dataset.ids !== ids) {
        list.dataset.ids = ids;
        const have = {};
        list.querySelectorAll(".node").forEach((el) => { have[el.dataset.id] = el; });
        for (const n of order) {
            let el = have[n.id];
            if (!el) {
                el = document.createElement("div");
                el.className = "node";
                el.dataset.id = n.id;
                el.onclick = () => selectNode(n.id, true);
            }
            list.appendChild(el);                 // moves existing cards into order
            delete have[n.id];
        }
        Object.values(have).forEach((el) => el.remove());
    }
    for (const n of order) {
        const el = list.querySelector(`.node[data-id="${CSS.escape(n.id)}"]`);
        if (!el) continue;
        const st = nodeState(n);
        const role = n.is_home ? "home" : (n.role || "remote");
        const dc = perNode[n.id] ? perNode[n.id].count : 0;
        const cls = `node ${st === "offline" ? "offline" : ""} ${S.selected === n.id ? "sel" : ""} ${n.color != null ? "custom" : ""}`
            + (el.classList.contains("hit") ? " hit" : "");
        if (el.className !== cls) el.className = cls;
        const style = n.color != null ? "--nc:" + nodeColor(n) : "";
        if ((el.getAttribute("style") || "") !== style) el.setAttribute("style", style);
        const html = `
            <div class="node-top">
                <span class="dot ${st === "online" ? "on" : st === "stale" ? "warn" : ""}"></span>
                <span class="node-name">${esc(n.alias || n.id)}</span>
                ${n.alias ? `<span class="node-id">${esc(n.id)}</span>` : ""}
                <span class="node-tags">
                    ${n.cfg && n.cfg.buzzer === 0 ? `<span class="ntag muted" title="Buzzer muted">MUTED</span>` : ""}
                    ${syncState(n) === "drift" ? `<span class="ntag drift" title="Filter list differs from the home node">DRIFT</span>` : ""}
                    ${isSkySpy(n) ? `<span class="ntag sky" title="Dedicated Sky-Spy drone node (Remote ID)">SKY-SPY</span>` : ""}
                </span>
                <span class="role ${role}">${role}</span>
            </div>
            <div class="node-meta">
                <span class="nm-sig">${n.is_home ? `<span class="nm-usb">USB</span>` : `${bars(n.rssi)}${n.rssi ? `<b>${n.rssi}</b>` : "<b>-</b>"}<i>dBm</i>`}</span>
                <span class="nm-age" data-age="${n.last_seen || 0}">${st === "offline" ? "last " : ""}${ago(n.last_seen)}</span>
                <span class="nm-pkt">${n.is_home ? "<b>-</b>" : `<b>${n.pkts || 0}</b>`}<i>pkts</i></span>
                <span class="nm-det"><b>${dc}</b><i>det</i></span>
            </div>`;
        if (el._html !== html) { el._html = html; el.innerHTML = html; }
    }

    const sel = $("hNode");
    const cur = sel.value;
    sel.innerHTML = `<option value="">All nodes</option>` +
        nodes.map((n) => `<option value="${esc(n.id)}">${esc(n.alias ? `${n.alias} (${n.id})` : n.id)}</option>`).join("");
    sel.value = cur;
    const vs = $("vNode"), vcur = vs.value;
    vs.innerHTML = `<option value="">Seen by any node</option>` + sel.innerHTML.replace(/^<option value="">All nodes<\/option>/, "");
    vs.value = vcur;
}

// ------------------------------------------------------------------
// map
// ------------------------------------------------------------------
// maxZoom 22 everywhere: past a layer's last real tile level (maxNativeZoom)
// Leaflet enlarges its final tiles, so you can always zoom in close.
const MAP_MAX_ZOOM = 22;
const map = L.map("map", { zoomControl: true, attributionControl: true, worldCopyJump: true, maxZoom: MAP_MAX_ZOOM });
let tileLayer = null;
map.attributionControl.setPrefix('<a href="https://leafletjs.com">Leaflet</a>');
// Map toolbar on the map itself (top right): layer, lines, traffic, full
// screen. In the panel header they got squeezed and clipped, and on phones
// the labels collapsed to bare icons.
(function () {
    const tools = L.control({ position: "topright" });
    tools.onAdd = () => {
        const div = L.DomUtil.create("div", "map-tools");
        ["mapLayer", "mapLinks", "mapTraffic", "mapTargets", "mapTri", "mapLock", "mapMax"].forEach((id) => div.appendChild(document.getElementById(id)));
        L.DomEvent.disableClickPropagation(div);
        L.DomEvent.disableScrollPropagation(div);
        return div;
    };
    tools.addTo(map);
    // Phones: maximize lives alone in the bottom-left corner, away from the
    // toolbar; desktop keeps it at the end of the toolbar. Moves on resize.
    const corner = L.control({ position: "bottomleft" });
    corner.onAdd = () => {
        const div = L.DomUtil.create("div", "map-corner");
        L.DomEvent.disableClickPropagation(div);
        return div;
    };
    corner.addTo(map);
    const placeMax = () => {
        const phone = window.matchMedia("(max-width: 760px)").matches;
        const btn = document.getElementById("mapMax");
        const home = phone ? corner.getContainer() : tools.getContainer();
        if (btn.parentElement !== home) home.appendChild(btn);
    };
    placeMax();
    window.matchMedia("(max-width: 760px)").addEventListener("change", placeMax);
})();
// Free base maps that need no API key. Each keeps its provider's
// attribution. `dark` runs the light OSM tiles through the CSS invert filter;
// `labels` lays a transparent place-name layer over imagery.
const A_OSM = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors';
const A_CARTO = A_OSM + ' &copy; <a href="https://carto.com/attributions">CARTO</a>';
const A_ESRI = 'Tiles &copy; <a href="https://www.esri.com">Esri</a>';
const ESRI = (svc) => `https://server.arcgisonline.com/ArcGIS/rest/services/${svc}/MapServer/tile/{z}/{y}/{x}`;
const CARTO = (style) => `https://{s}.basemaps.cartocdn.com/${style}/{z}/{x}/{y}{r}.png`;
const TILES = {
    "osm-dark":     { name: "OpenStreetMap, dark", url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", attr: A_OSM, max: 19, dark: true },
    "carto-dark":   { name: "CARTO Dark Matter", url: CARTO("dark_all"), attr: A_CARTO, max: 20 },
    "carto-dark-nl":{ name: "CARTO Dark Matter, no labels", url: CARTO("dark_nolabels"), attr: A_CARTO, max: 20 },
    "esri-dark":    { name: "Esri Dark Gray", url: ESRI("Canvas/World_Dark_Gray_Base"), attr: A_ESRI, max: 16,
                      labels: ESRI("Canvas/World_Dark_Gray_Reference") },
    "esri-sat":     { name: "Satellite (Esri)", url: ESRI("World_Imagery"), attr: A_ESRI + ", Maxar, Earthstar Geographics", max: 19 },
    "esri-hybrid":  { name: "Satellite + labels (Esri)", url: ESRI("World_Imagery"), attr: A_ESRI + ", Maxar, Earthstar Geographics", max: 19,
                      labels: ESRI("Reference/World_Boundaries_and_Places") },
    "usgs-sat":     { name: "USGS imagery + topo (US only)", url: "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryTopo/MapServer/tile/{z}/{y}/{x}",
                      attr: 'Tiles courtesy of the <a href="https://usgs.gov/">U.S. Geological Survey</a>', max: 16 },
    "osm":          { name: "OpenStreetMap", url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png", attr: A_OSM, max: 19 },
    "osm-hot":      { name: "OpenStreetMap Humanitarian", url: "https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
                      attr: A_OSM + ', tiles by <a href="https://www.hotosm.org/">HOT</a>', max: 19 },
    "carto-voyager":{ name: "CARTO Voyager", url: CARTO("rastertiles/voyager"), attr: A_CARTO, max: 20 },
    "carto-light":  { name: "CARTO Positron (light)", url: CARTO("light_all"), attr: A_CARTO, max: 20 },
    "esri-street":  { name: "Esri World Street", url: ESRI("World_Street_Map"), attr: A_ESRI, max: 19 },
    "esri-topo":    { name: "Esri World Topo", url: ESRI("World_Topo_Map"), attr: A_ESRI, max: 19 },
    "opentopo":     { name: "OpenTopoMap (terrain)", url: "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
                      attr: A_OSM + ', <a href="http://viewfinderpanoramas.org">SRTM</a> | style &copy; <a href="https://opentopomap.org">OpenTopoMap</a> (CC-BY-SA)', max: 17 },
    "cyclosm":      { name: "CyclOSM", url: "https://{s}.tile-cyclosm.openstreetmap.fr/cyclosm/{z}/{x}/{y}.png",
                      attr: A_OSM + ', style <a href="https://www.cyclosm.org">CyclOSM</a>', max: 20 },
};
const TILE_OTHER = { "custom-dark": "Custom / local tile server, dark", "custom": "Custom / local tile server", "none": "None - offline grid" };
let labelLayer = null;
function applyTiles() {
    if (tileLayer) { map.removeLayer(tileLayer); tileLayer = null; }
    if (labelLayer) { map.removeLayer(labelLayer); labelLayer = null; }
    const mode = (TILES[S.settings.tiles] || TILE_OTHER[S.settings.tiles]) ? S.settings.tiles : "osm-dark";
    const t = TILES[mode];
    const el = map.getContainer();
    el.classList.toggle("grid-bg", mode === "none");
    el.classList.toggle("dark-tiles", (t && t.dark) || mode === "custom-dark");
    if (t) {
        tileLayer = L.tileLayer(t.url, { maxZoom: MAP_MAX_ZOOM, maxNativeZoom: t.max, attribution: t.attr }).addTo(map);
        if (t.labels) labelLayer = L.tileLayer(t.labels, { maxZoom: MAP_MAX_ZOOM, maxNativeZoom: t.max, pane: "overlayPane" }).addTo(map);
    } else if (mode.startsWith("custom") && S.settings.tiles_custom) {
        tileLayer = L.tileLayer(S.settings.tiles_custom, { maxZoom: MAP_MAX_ZOOM, maxNativeZoom: 19 }).addTo(map);
    }
    if ($("mapLayer") && document.activeElement !== $("mapLayer")) $("mapLayer").value = mode;
}
// Maximize: the map panel fills the whole window (desktop and phone; a CSS
// overlay, since phones have no element fullscreen). Esc or the button exits.
function setMapMax(on) {
    const panel = document.querySelector(".map-panel");
    panel.classList.toggle("map-max", on);
    document.body.classList.toggle("map-maxed", on);
    $("mapMax").classList.toggle("on", on);
    $("mapMax").title = on ? "Exit full screen map (Esc)" : "Full screen map";
    $("mapMax").setAttribute("aria-pressed", on ? "true" : "false");
    setTimeout(() => map.invalidateSize({ pan: false }), 60);
}
$("mapMax").onclick = () => setMapMax(!document.querySelector(".map-panel").classList.contains("map-max"));
document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && document.querySelector(".map-panel.map-max")) setMapMax(false);
});
// Picking a layer on the map saves it, so every open dashboard switches too.
$("mapLayer").onchange = async () => {
    const tiles = $("mapLayer").value;
    S.settings.tiles = tiles;
    applyTiles();
    if ($("sTiles")) $("sTiles").value = tiles;
    await api("/api/settings", { method: "POST", body: { tiles } });
};
// Map layer picker (the map's top-right corner and Settings share one list).
function tileOptions(sel) {
    const opt = (k, n) => `<option value="${k}">${esc(n)}</option>`;
    const dark = ["osm-dark", "carto-dark", "carto-dark-nl", "esri-dark"];
    const sat = ["esri-sat", "esri-hybrid", "usgs-sat"];
    const light = Object.keys(TILES).filter((k) => !dark.includes(k) && !sat.includes(k));
    sel.innerHTML =
        `<optgroup label="Dark">${dark.map((k) => opt(k, TILES[k].name)).join("")}</optgroup>` +
        `<optgroup label="Satellite">${sat.map((k) => opt(k, TILES[k].name)).join("")}</optgroup>` +
        `<optgroup label="Street and terrain">${light.map((k) => opt(k, TILES[k].name)).join("")}</optgroup>` +
        `<optgroup label="Private / offline">${Object.entries(TILE_OTHER).map(([k, n]) => opt(k, n)).join("")}</optgroup>`;
}
let viewSet = false;
function initView() {
    if (viewSet) return;
    const v = S.settings.map_view;
    const placed = S.fleet.nodes.filter((n) => n.lat != null);
    if (v && v.length === 3) map.setView([v[0], v[1]], v[2]);
    else if (placed.length) map.fitBounds(L.latLngBounds(placed.map((n) => [n.lat, n.lon])).pad(0.4), { maxZoom: 16 });
    else map.setView([39.5, -98.35], 4);
    viewSet = true;
}
let viewTimer = null;
map.on("moveend", () => {
    if (!viewSet) return;
    clearTimeout(viewTimer);
    viewTimer = setTimeout(() => {
        const c = map.getCenter();
        const mv = [+c.lat.toFixed(6), +c.lng.toFixed(6), map.getZoom()];
        S.settings.map_view = mv;
        api("/api/settings", { method: "POST", body: { map_view: mv } });
    }, 800);
});
map.on("click", (e) => {
    if (S.calib && S.calib.stage === "place") return calibAt(e.latlng);
    if (!S.placing || !S.selected) return;
    setNodePos(S.selected, e.latlng.lat, e.latlng.lng);
    setPlacing(false);
});

function markerParts(n) {
    const st = nodeState(n);
    const sub = n.is_home ? "home" : (n.rssi ? `${n.rssi} dBm` : st);
    const recent = S.dets.filter((d) => d.node === n.id && now() - d.ts < 900).length;
    const gpsOn = S.gpsLive[n.id] && now() - S.gpsLive[n.id] < 60;
    return {
        cls: `nmark ${st} ${n.is_home ? "home" : ""} ${S.selected === n.id ? "sel" : ""} ${n.color != null ? "custom" : ""} ${gpsOn ? "moving" : ""}`,
        color: nodeColor(n),
        badge: recent ? String(recent) : "",
        label: `${esc(n.alias || n.id)}${gpsOn ? `<i class="gpstag">GPS</i>` : ""}<small>${esc(sub)}</small>`,
    };
}
// A node's own color (hue from its drawer slider), or "" for the defaults.
function nodeColor(n) { return n && n.color != null ? `hsl(${n.color} 90% 62%)` : ""; }
function markerHtml(n) {
    const p = markerParts(n);
    return `<div class="${p.cls}" style="${p.color ? "--nc:" + p.color : ""}">
        <span class="ping"></span><span class="burst"></span><span class="core"></span>
        ${p.badge ? `<span class="badge" title="Detections in the last 15 min">${p.badge}</span>` : ""}
        <span class="label">${p.label}</span></div>`;
}
// Update a marker that's already on the map without rebuilding it: only the
// pieces that changed are touched, so its CSS animations (ping, pulse) keep
// running. Rebuilding the icon every second made the map flicker on phones.
function patchMarker(m, n) {
    const root = m.getElement() && m.getElement().querySelector(".nmark");
    if (!root) return;
    const p = markerParts(n);
    const cls = p.cls + (root.classList.contains("hit") ? " hit" : "");
    if (root.className !== cls) root.className = cls;
    if (root.style.getPropertyValue("--nc") !== p.color) root.style.setProperty("--nc", p.color);
    let badge = root.querySelector(".badge");
    if (p.badge && !badge) {
        badge = document.createElement("span");
        badge.className = "badge";
        badge.title = "Detections in the last 15 min";
        root.insertBefore(badge, root.querySelector(".label"));
    }
    if (badge && !p.badge) badge.remove();
    else if (badge && badge.textContent !== p.badge) badge.textContent = p.badge;
    const label = root.querySelector(".label");
    if (label && label.innerHTML !== p.label) label.innerHTML = p.label;
}
function renderMap() {
    const seen = new Set();
    for (const n of S.fleet.nodes) {
        if (n.lat == null || n.lon == null) continue;
        seen.add(n.id);
        let m = S.markers[n.id];
        if (!m) {
            m = L.marker([n.lat, n.lon], {
                draggable: !S.mapLocked, riseOnHover: true,
                icon: L.divIcon({ className: "", html: markerHtml(n), iconSize: [0, 0] }),
            }).addTo(map);
            m.on("dragend", (e) => { const p = e.target.getLatLng(); setNodePos(n.id, p.lat, p.lng); armRelock(); });
            m.on("click", () => selectNode(n.id, true));
            S.markers[n.id] = m;
        } else {
            const ll = m.getLatLng();
            if (!m.dragging || !m._dragActive) {
                if (Math.abs(ll.lat - n.lat) > 1e-9 || Math.abs(ll.lng - n.lon) > 1e-9) m.setLatLng([n.lat, n.lon]);
            }
            patchMarker(m, n);
        }
    }
    for (const id of Object.keys(S.markers)) {
        if (!seen.has(id)) { map.removeLayer(S.markers[id]); delete S.markers[id]; }
    }
    renderLinks();
    setTimeout(declutterLabels, 0);
    const unplaced = S.fleet.nodes.filter((n) => n.lat == null);
    $("unplaced").innerHTML = unplaced.length
        ? `<span>Not on map:</span>` + unplaced.map((n) => `<button data-id="${esc(n.id)}">${esc(n.alias || n.id)}</button>`).join("")
        : "";
    $("unplaced").querySelectorAll("button").forEach((b) => b.onclick = () => {
        selectNode(b.dataset.id, false);
        setPlacing(true);
    });
}
// Home-to-remote links: the roster RSSI is what the HOME hears from each
// remote, so a line per placed remote coloured by that RSSI, with distance.
// Map lines: "home" = home to each remote (the old view), "mesh" = every
// link a node reports hearing first-hand (RST "nbr"), "off". Lines are kept
// between updates and moved / restyled in place (redrawing them all every
// second flickered).
function linkMode() {
    const v = S.settings.links;
    return v === false || v === "off" ? "off" : v === "mesh" ? "mesh" : "home";
}
const rssiColor = (r) => !r ? "#5b6879" : r >= -70 ? "#4ecdc4" : r >= -82 ? "#fbbf24" : "#f87171";
function wantedLinks() {
    const out = [];
    const mode = linkMode();
    const placed = (n) => n && n.lat != null;
    if (!map._loaded || mode === "off") return out;
    if (mode === "home") {
        const home = S.fleet.nodes.find((n) => n.is_home && placed(n));
        if (!home) return out;
        for (const n of S.fleet.nodes) {
            if (n.is_home || !placed(n) || !n.online) continue;
            const st = nodeState(n);
            out.push({ key: "h:" + n.id, a: home, b: n, r: n.rssi, faded: st === "stale", oneWay: false,
                       tip: `<b>${n.rssi ? n.rssi + " dBm" : "no rssi"}</b> | ${fmtDist(metres(home, n))}`,
                       sel: S.selected === n.id || S.selected === home.id });
        }
        return out;
    }
    // Mesh: merge both directions of each pair.
    const pairs = {};
    for (const n of S.fleet.nodes) {
        const nb = n.cfg && n.cfg.nbr;
        if (!Array.isArray(nb) || !placed(n)) continue;
        for (const [id, rssi, age] of nb) {
            const m = nodeById(id);
            if (!placed(m)) continue;
            const key = "m:" + [n.id, id].sort().join("-");
            const p = pairs[key] = pairs[key] || { key, a: n.id < id ? n : m, b: n.id < id ? m : n, seen: {} };
            p.seen[n.id] = { rssi, age };
        }
    }
    for (const p of Object.values(pairs)) {
        const ab = p.seen[p.a.id], ba = p.seen[p.b.id];
        const rs = [ab, ba].filter((x) => x && x.rssi).map((x) => x.rssi);
        const r = rs.length ? Math.max(...rs) : 0;
        const fresh = [ab, ba].some((x) => x && x.age < 30) && p.a.online && p.b.online;
        const one = (name, x) => x ? `${esc(name)} hears it at ${x.rssi ? x.rssi + " dBm" : "?"}` : `${esc(name)}: not heard`;
        out.push({ key: p.key, a: p.a, b: p.b, r, faded: !fresh, oneWay: !(ab && ba),
                   tip: `<b>${esc(nodeName(p.a.id))} - ${esc(nodeName(p.b.id))}</b><br>${one(nodeName(p.a.id), ab)}<br>${one(nodeName(p.b.id), ba)}<br>${fmtDist(metres(p.a, p.b))}`,
                   sel: S.selected === p.a.id || S.selected === p.b.id });
    }
    return out;
}
function renderLinks() {
    if (!S.links) S.links = L.layerGroup().addTo(map);
    if (!S.linkLines) S.linkLines = {};
    const keep = new Set();
    for (const w of wantedLinks()) {
        keep.add(w.key);
        // Solid = live two-way link; dashed = one side only, or gone quiet.
        const style = { color: rssiColor(w.r), weight: w.key.startsWith("m:") ? 3.5 : 2.5,
                        opacity: w.faded ? 0.4 : 0.9, dashArray: w.oneWay ? "3 7" : w.faded ? "4 6" : null };
        const pts = [[w.a.lat, w.a.lon], [w.b.lat, w.b.lon]];
        // Label only the selected node's links permanently, and only when the
        // line is long enough on screen to hold it; otherwise on hover/tap.
        const px = map.latLngToContainerPoint(pts[0]).distanceTo(map.latLngToContainerPoint(pts[1]));
        const pinned = w.sel && px > 160 && w.key.startsWith("h:");
        let line = S.linkLines[w.key];
        if (!line) {
            line = S.linkLines[w.key] = L.polyline(pts, style);
            S.links.addLayer(line);
        } else {
            const cur = line.getLatLngs();
            if (cur[0].lat !== pts[0][0] || cur[0].lng !== pts[0][1] || cur[1].lat !== pts[1][0] || cur[1].lng !== pts[1][1]) line.setLatLngs(pts);
            const o = line.options;
            if (o.color !== style.color || o.opacity !== style.opacity || o.dashArray !== style.dashArray || o.weight !== style.weight) line.setStyle(style);
        }
        if (line._pinned !== pinned) {
            line.unbindTooltip();
            line.bindTooltip(w.tip, { permanent: pinned, sticky: !pinned, direction: "center", className: "link-label" });
            line._pinned = pinned;
        } else if (line.getTooltip() && line._tip !== w.tip) {
            line.setTooltipContent(w.tip);
        }
        line._tip = w.tip;
    }
    for (const id of Object.keys(S.linkLines)) {
        if (!keep.has(id)) { S.links.removeLayer(S.linkLines[id]); delete S.linkLines[id]; }
    }
    const b = $("mapLinks");
    if (b) {
        const mode = linkMode();
        b.dataset.mode = mode;
        b.querySelector("span").textContent = mode === "mesh" ? "Lines: mesh" : mode === "home" ? "Lines: home" : "Lines: off";
        b.title = mode === "mesh" ? "Lines: every link nodes report hearing first-hand (tap: off)"
            : mode === "home" ? "Lines: home to each remote (tap: full mesh)" : "Lines: off (tap: home links)";
    }
}
// ------------------------------------------------------------------
// Traffic view: pulses travel the mesh path when data moves. A detection
// rides its route from the node to the home (shortest path through the
// links nodes report hearing, straight to the home if none are known),
// telemetry / acks go node -> home, commands home -> node.
// ------------------------------------------------------------------
function meshRoute(fromId, toId) {
    const adj = {};
    const link = (a, b) => { (adj[a] = adj[a] || new Set()).add(b); (adj[b] = adj[b] || new Set()).add(a); };
    for (const n of S.fleet.nodes) for (const [id] of (n.cfg && n.cfg.nbr) || []) link(n.id, id);
    const prev = { [fromId]: null }, q = [fromId];
    while (q.length) {
        const c = q.shift();
        if (c === toId) break;
        for (const nx of adj[c] || []) if (!(nx in prev)) { prev[nx] = c; q.push(nx); }
    }
    if (!(toId in prev)) return [fromId, toId];
    const path = [];
    for (let c = toId; c != null; c = prev[c]) path.unshift(c);
    return path;
}
function trafficOn() { return !!S.settings.traffic; }
function flow(path, kind) {
    if (!trafficOn() || !map._loaded) return;
    const pts = path.map((id) => nodeById(id)).filter((n) => n && n.lat != null).map((n) => [n.lat, n.lon]);
    if (pts.length < 2) return;
    if (!S.flowLayer) S.flowLayer = L.layerGroup().addTo(map);
    const line = L.polyline(pts, { className: `flow flow-${kind}`, interactive: false, weight: kind === "det" ? 5 : 3 });
    S.flowLayer.addLayer(line);
    const el = line.getElement();
    if (el) el.setAttribute("pathLength", "100");
    setTimeout(() => S.flowLayer.removeLayer(line), kind === "det" ? 2000 : 1500);
}
function trafficFromLine(line) {
    if (!trafficOn()) return;
    const h = homeNode();
    if (!h) return;
    const head = line.split(" ", 1)[0];
    if (!["RST", "ACK", "RFL", "CMD", "OTA"].includes(head)) return;
    let o;
    try { o = JSON.parse(line.slice(head.length + 1)); } catch (e) { return; }
    if (head === "CMD") {
        const targets = o.target === "all" ? S.fleet.nodes.filter((n) => !n.is_home && n.online).map((n) => n.id) : [o.target];
        targets.forEach((t) => flow(meshRoute(h.id, t), "cmd"));
    } else if (o.node && o.node !== h.id) {
        flow(meshRoute(o.node, h.id), head === "OTA" ? "cmd" : "tlm");
    }
}
$("mapTraffic").onclick = async () => {
    S.settings.traffic = !trafficOn();
    renderTrafficBtn();
    await api("/api/settings", { method: "POST", body: { traffic: S.settings.traffic } });
};
function renderTrafficBtn() {
    $("mapTraffic").classList.toggle("on", trafficOn());
    $("mapTraffic").querySelector("span").textContent = trafficOn() ? "Traffic: on" : "Traffic: off";
    $("mapTraffic").setAttribute("aria-pressed", trafficOn() ? "true" : "false");
}

// Links toggle on the map: home -> mesh -> off. Saved, so every open
// dashboard switches too.
$("mapLinks").onclick = async () => {
    const next = { home: "mesh", mesh: "off", off: "home" }[linkMode()];
    S.settings.links = next;
    renderLinks();
    if ($("sLinks")) $("sLinks").checked = next !== "off";
    if (next === "mesh" && canCommand()) api("/api/fleet/cmd", { method: "POST", body: { op: "status" } });   // fresh neighbor lists, quietly
    await api("/api/settings", { method: "POST", body: { links: next } });
};
// ------------------------------------------------------------------
// GPS: a phone carrying a node feeds its position; every viewer sees the
// marker move and a breadcrumb trail.
// ------------------------------------------------------------------
// Trail length slider: steps in seconds (0 = off). Per viewer, remembered
// in this browser; longer windows are fetched from the stored history.
const TRAIL_STEPS = [0, 300, 900, 1800, 3600, 10800, 21600, 43200, 86400, 604800];
const TRAIL_NAMES = ["Off", "5 min", "15 min", "30 min", "1 h", "3 h", "6 h", "12 h", "24 h", "7 days"];
// Per node now (node drawer), per browser; the old single slider's value
// becomes every node's default.
S.trailDefault = TRAIL_STEPS.includes(Number(lsGet("ouispy.trail", 1800))) ? Number(lsGet("ouispy.trail", 1800)) : 1800;
S.trailPer = lsGet("ouispy.trailPer", {});
S.trailLoaded = 1800;
function trailFor(nid) { return S.trailPer[nid] ?? S.trailDefault; }
function trailMax() { return Math.max(S.trailDefault, ...Object.values(S.trailPer), 0); }
function syncTrailSlider() { /* the slider moved into the node drawer (dTrail) */ }
async function loadTrails(seconds) {
    const tr = await api(`/api/tracks?seconds=${Math.max(seconds, 60)}`);
    S.trails = tr.tracks || {};
    S.trailLoaded = tr.seconds || seconds;
    for (const [k, v] of Object.entries(tr.live || {})) S.gpsLive[k] = v.ts;
    renderTrails();
}
$("dTrail").onchange = () => {
    S.trailPer[S.selected] = Number($("dTrail").value);
    lsSet("ouispy.trailPer", S.trailPer);
    if (trailMax() > S.trailLoaded) loadTrails(trailMax());   // need older points
    renderTrails();
};

function renderTrails() {
    if (!S.trailLayer) S.trailLayer = L.layerGroup().addTo(map);
    S.trailLayer.clearLayers();
    for (const [nid, pts] of Object.entries(S.trails)) {
        const secs = trailFor(nid);
        if (!secs) continue;
        const cutoff = now() - secs;
        const ll = pts.filter((p) => p[0] >= cutoff).map((p) => [p[1], p[2]]);
        if (ll.length < 2) continue;
        const n = nodeById(nid);
        S.trailLayer.addLayer(L.polyline(ll, { color: n && n.color != null ? nodeColor(n) : "#f0abfc", weight: 3, opacity: 0.7, dashArray: "2 6", interactive: false }));
    }
}
function onGps(g) {
    S.gpsLive[g.node] = g.ts;
    (S.trails[g.node] = S.trails[g.node] || []).push([g.ts, g.lat, g.lon, g.acc]);
    if (S.trails[g.node].length > 20000) S.trails[g.node].splice(0, 5000);
    const n = nodeById(g.node);
    if (n) { n.lat = g.lat; n.lon = g.lon; }
    renderMap();
    renderTrails();
}
function gpsInfo(text) { $("dGpsInfo").textContent = text; }
function renderGpsButton() {
    const mine = S.gps && S.gps.node === S.selected;
    $("dGps").textContent = mine ? "Stop carrying" : "Carry with this phone";
    $("dGps").classList.toggle("armed", !!mine);
    if (!mine) {
        const ts = S.gpsLive[S.selected];
        gpsInfo(ts && now() - ts < 60 ? `GPS live from another device, ${ago(ts)}` : "");
    }
}
async function stopCarry(clearTrail) {
    if (!S.gps) return;
    navigator.geolocation.clearWatch(S.gps.watch);
    try { if (S.gps.lock) await S.gps.lock.release(); } catch (e) { /* ignore */ }
    const node = S.gps.node;
    S.gps = null;
    await api(`/api/nodes/${node}/gps${clearTrail ? "?clear=1" : ""}`, { method: "DELETE" });
    renderGpsButton();
}
async function startCarry(node) {
    if (!window.isSecureContext) {
        toast("warn", "Location needs HTTPS", "Phones only share GPS with https:// pages: serve the dashboard over HTTPS (your own reverse proxy or VPN)");
        gpsInfo("needs the https:// address");
        return;
    }
    if (!("geolocation" in navigator)) { toast("bad", "No GPS", "This browser has no location support"); return; }
    if (S.gps) await stopCarry(false);
    S.gps = { node, lastSent: 0, last: null, lock: null };
    try { if (navigator.wakeLock) S.gps.lock = await navigator.wakeLock.request("screen"); } catch (e) { /* optional */ }
    S.gps.watch = navigator.geolocation.watchPosition(async (pos) => {
        if (!S.gps) return;
        const c = pos.coords, t = Date.now() / 1000;
        const moved = S.gps.last ? map.distance([S.gps.last.lat, S.gps.last.lon], [c.latitude, c.longitude]) : 1e9;
        if (t - S.gps.lastSent >= 2 || moved >= 3) {
            S.gps.lastSent = t;
            S.gps.last = { lat: c.latitude, lon: c.longitude };
            await api(`/api/nodes/${S.gps.node}/gps`, { method: "POST",
                body: { lat: c.latitude, lon: c.longitude, acc: c.accuracy } });
        }
        if (S.selected === S.gps.node) gpsInfo(`GPS live, accuracy ${Math.round(c.accuracy)} m`);
    }, (err) => {
        gpsInfo(err.code === 1 ? "location permission denied" : "no GPS fix yet");
        if (err.code === 1) stopCarry(false);
    }, { enableHighAccuracy: true, maximumAge: 2000, timeout: 20000 });
    renderGpsButton();
    gpsInfo("waiting for a GPS fix...");
    toast("good", `Carrying ${nodeName(node)}`, "This phone's GPS now positions the node. Keep the page open.");
}
$("dGps").onclick = () => (S.gps && S.gps.node === S.selected) ? stopCarry(false) : startCarry(S.selected);
document.addEventListener("visibilitychange", async () => {
    // wake locks drop when the page is hidden; take it back on return
    if (S.gps && !document.hidden && navigator.wakeLock) {
        try { S.gps.lock = await navigator.wakeLock.request("screen"); } catch (e) { /* ignore */ }
    }
});

// Marker labels: each picks the side (right, left, above, below) that
// doesn't overlap a label already placed or another marker, so nodes a few
// metres apart stay readable. Re-run after every render, zoom and pan.
const LABEL_SIDES = ["lab-r", "lab-l", "lab-t", "lab-b"];
// Candidate spots: each side as is, then the left/right sides stepped up and
// down a label height at a time (a column of labels beside a tight cluster).
function labelSpots(h) {
    const out = LABEL_SIDES.map((side) => [side, 0]);
    for (let k = 1; k <= 4; k++) for (const side of ["lab-r", "lab-l"]) out.push([side, k * h], [side, -k * h]);
    return out;
}
function declutterLabels() {
    if (!map._loaded) return;
    const marks = Object.values(S.markers).map((m) => m.getElement() && m.getElement().querySelector(".nmark"))
        .filter(Boolean);
    const tgts = Object.values(S.targets || {}).map((g) => g.marker.getElement() && g.marker.getElement().querySelector(".tgt"))
        .filter(Boolean);
    // Dots and drone markers are off limits to every label; drone labels are
    // fixed and count as placed.
    const cores = marks.map((el) => el.querySelector(".core").getBoundingClientRect())
        .concat(tgts.map((el) => el.querySelector(".tgt-dot").getBoundingClientRect()))
        .concat([...document.querySelectorAll(".drm svg, .plm svg")].map((el) => el.getBoundingClientRect()));
    const placed = [...document.querySelectorAll(".drm-label")].map((el) => el.getBoundingClientRect());
    const hit = (a, b) => a.left < b.right && a.right > b.left && a.top < b.bottom && a.bottom > b.top;
    const free = (lab) => {
        const r = lab.getBoundingClientRect();
        const box = { left: r.left - 3, right: r.right + 3, top: r.top - 3, bottom: r.bottom + 3 };
        return !placed.some((p) => hit(box, p)) && !cores.some((c) => hit(box, c));
    };
    const place = (el, lab, extraCls) => {
        el.classList.remove("lab-compact", "lab-hidden");
        if (extraCls) el.classList.add(extraCls);
        const h = lab.getBoundingClientRect().height + 4;
        for (const [side, dy] of labelSpots(h)) {
            el.classList.remove(...LABEL_SIDES);
            el.classList.add(side);
            lab.style.marginTop = dy ? `${dy}px` : "";
            if (free(lab)) return true;
        }
        el.classList.remove(...LABEL_SIDES);
        lab.style.marginTop = "";
        return false;
    };
    // Home and the selected node first: they get the best spots.
    marks.sort((a, b) => ((b.classList.contains("sel") ? 2 : 0) + (b.classList.contains("home") ? 1 : 0)) -
                         ((a.classList.contains("sel") ? 2 : 0) + (a.classList.contains("home") ? 1 : 0)));
    for (const el of marks) {
        const lab = el.querySelector(".label");
        if (!lab) continue;
        lab.title = lab.innerText.replace(/\n/g, " ");
        // Full label, then name only, then dot only (the name shows on hover).
        if (place(el, lab, null) || place(el, lab, "lab-compact")) placed.push(lab.getBoundingClientRect());
        else { el.classList.add("lab-r", "lab-hidden"); }
    }
    // Live-target labels yield to node labels: none clear = dot only.
    for (const el of tgts) {
        const lab = el.querySelector(".tgt-label");
        el.classList.remove("tgt-mini");
        if (place(el, lab, null)) placed.push(lab.getBoundingClientRect());
        else { el.classList.add("lab-r", "tgt-mini"); }
    }
}
map.on("zoomend moveend", () => { renderLinks(); declutterLabels(); });

async function setNodePos(id, lat, lon) {
    const n = nodeById(id);
    if (n) { n.lat = lat; n.lon = lon; }
    renderMap();
    await api(`/api/nodes/${id}`, { method: "POST", body: { lat, lon } });
}
// Node positions are locked by default (per browser), so panning the map
// can never drag a node by accident. Unlocking glows the button and the
// markers; it locks itself again after 2 minutes without a move.
const RELOCK_MS = 120000;
let relockTimer = null;
S.mapLocked = (() => { try { return localStorage.getItem("ouispy.mapUnlocked") !== "1"; } catch (e) { return true; } })();
function armRelock() {
    clearTimeout(relockTimer);
    if (!S.mapLocked) relockTimer = setTimeout(() => setMapLocked(true), RELOCK_MS);
}
function setMapLocked(on) {
    S.mapLocked = on;
    try { localStorage.setItem("ouispy.mapUnlocked", on ? "0" : "1"); } catch (e) { /* private window */ }
    for (const m of Object.values(S.markers)) {
        if (m.dragging) on ? m.dragging.disable() : m.dragging.enable();
    }
    const b = $("mapLock");
    b.classList.toggle("on", !on);
    b.setAttribute("aria-pressed", on ? "true" : "false");
    b.querySelector("span").textContent = on ? "Locked" : "Unlocked";
    b.title = on ? "Node positions are locked. Click to unlock and drag nodes."
                 : "Unlocked: drag nodes to move them. Click to lock (locks itself after 2 minutes idle).";
    document.querySelector(".map-panel").classList.toggle("unlocked", !on);
    if (!S.placing) setPlacing(false);   // refresh the hint
    armRelock();
}
$("mapLock").onclick = () => setMapLocked(!S.mapLocked);
setMapLocked(S.mapLocked);

function setPlacing(on) {
    S.placing = on;
    document.querySelector(".map-panel").classList.toggle("placing", on);
    $("mapHint").textContent = on
        ? `Click the map to place ${nodeName(S.selected)}. Esc to cancel.`
        : S.mapLocked ? `Node positions locked. Unlock on the map to drag nodes.`
        : `Unlocked: drag markers to move nodes. Select a node, then "Place on map".`;
}
document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") { if (S.placing) setPlacing(false); else { closeDrawer(); closeDevice(); hideFleetKey(); } }
});

function hitNode(id) {
    const card = document.querySelector(`.node[data-id="${CSS.escape(id)}"]`);
    if (card) { card.classList.remove("hit"); void card.offsetWidth; card.classList.add("hit"); }
    const m = S.markers[id];
    if (m) {
        const el = m.getElement() && m.getElement().querySelector(".nmark");
        if (el) {
            m._hitting = true;
            el.classList.remove("hit"); void el.offsetWidth; el.classList.add("hit");
            setTimeout(() => { m._hitting = false; el.classList.remove("hit"); }, 1650);
        }
    }
}

// ------------------------------------------------------------------
// live feed
// ------------------------------------------------------------------
function detHtml(d, fresh) {
    const node = nodeById(d.node);
    const home = node && node.is_home;
    return `<div class="det ${d.is_new ? "new" : ""} ${fresh ? "fresh" : ""}" data-node="${esc(d.node)}" data-mac="${esc(d.mac)}">
        <div class="det-top">
            <span class="det-vendor">${esc(d.descr || d.match || "UNKNOWN")}</span>
            ${d.is_new ? `<span class="tag newtag">NEW</span>` : ""}
            <span class="tag ${esc(d.dom)}">${d.dom === "wifi" ? "WIFI" : "BLE"}</span>
            <span class="tag">${esc(d.type || "")}</span>
            <span class="det-time" title="${esc(fullTime(d.ts))}">${hms(d.ts)}</span>
        </div>
        <div class="det-mid">
            <span class="det-mac" data-mac="${esc(d.mac)}">${esc(d.mac)}</span>
            ${devAlias(d.mac, d.alias) ? `<span class="mal">${esc(devAlias(d.mac, d.alias))}</span>` : ""}
            ${devName(d.mac, d.name) ? `<span class="dname" title="Name it broadcasts">"${esc(devName(d.mac, d.name))}"</span>` : ""}
            ${groupTag(d.mac)}
            <span class="rssi-v">${d.rssi ?? "?"} dBm</span>
            <span class="det-node ${home ? "home" : ""}">via ${esc(nodeName(d.node))}</span>
        </div>
        ${d.seen_by && d.seen_by.length > 1 ? `<div class="det-seen" title="Every node that heard it in the last minute, strongest signal first. Strongest = closest (roughly: walls and antennas skew it).">
            <span class="closest">Closest: ${esc(nodeName(d.seen_by[0][0]))} ${d.seen_by[0][1]} dBm</span>
            ${d.seen_by.slice(1).map((s) => `<span>${esc(nodeName(s[0]))} ${s[1]} dBm</span>`).join("")}
        </div>` : ""}
    </div>`;
}
function renderFeed() {
    const f = $("feed");
    if (!S.dets.length) { f.innerHTML = `<div class="empty">Waiting for detections...</div>`; return; }
    f.innerHTML = S.dets.slice(0, 120).map((d) => detHtml(d)).join("");
    f.querySelectorAll(".det").forEach(wireDet);
}
function wireDet(el) {
    el.onclick = (e) => {
        // The card opens the device; only the "via <node>" chip goes to the node.
        if (e.target.closest(".det-node")) selectNode(el.dataset.node, true);
        else openDevice(el.dataset.mac);
    };
}
function renderKpis() {
    const st = S.statsBase || { total: 0, day: 0, macs: 0 };
    const lastHour = S.dets.filter((d) => now() - d.ts < 3600).length;
    $("detCount").textContent = st.total;
    $("kpis").innerHTML = `
        <div class="kpi"><div class="k">Last hour</div><div class="v ${lastHour ? "alert" : ""}">${lastHour}</div></div>
        <div class="kpi"><div class="k">24 h</div><div class="v">${st.day}</div></div>
        <div class="kpi"><div class="k">Unique MACs</div><div class="v">${st.macs}</div></div>`;
    renderActivity();
}
function bumpHourly(ts) {
    const h = Math.floor(ts / 3600) * 3600;
    const last = S.hourly[S.hourly.length - 1];
    if (last && last.h === h) last.c++;
    else if (!last || h > last.h) { S.hourly.push({ h, c: 1 }); S.hourly = S.hourly.slice(-24); }
}
function renderActivity() {
    const hrs = S.hourly;
    if (!hrs.length) { $("activity").innerHTML = ""; return; }
    const max = Math.max(1, ...hrs.map((x) => x.c));
    $("activity").innerHTML = hrs.map((x, i) => {
        const cls = i === hrs.length - 1 ? "now" : x.c >= max * 0.6 ? "hot" : "";
        const label = new Date(x.h * 1000).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
        return `<i class="${cls}" style="height:${Math.max(4, (x.c / max) * 100)}%" title="${label}  ${x.c} detections"></i>`;
    }).join("");
}

// ------------------------------------------------------------------
// toasts + desktop notifications
// ------------------------------------------------------------------
function toast(kind, title, body, onClick) {
    const el = document.createElement("div");
    el.className = `toast ${kind}`;
    el.innerHTML = `<b>${esc(title)}</b><span>${esc(body || "")}</span>`;
    el.onclick = () => { if (onClick) onClick(); el.remove(); };
    const box = $("toasts");
    box.prepend(el);
    while (box.children.length > 5) box.lastElementChild.remove();
    setTimeout(() => { el.classList.add("out"); setTimeout(() => el.remove(), 350); }, kind === "bad" ? 9000 : 5000);
    if (S.settings.notify && document.hidden && "Notification" in window && Notification.permission === "granted") {
        try { new Notification(`OUI-SPY: ${title}`, { body: body || "", tag: title, silent: true }); } catch (e) { /* ignore */ }
    }
}
function watchHealth() {
    const h = S.fleet.home || {};
    if (!S.booted) { S.prevHomeAlive = h.alive; S.prevHeal = h.heal || 0; return; }
    if (S.prevHomeAlive && !h.alive) toast("bad", "Home node silent", `No telemetry from ${nodeName(h.id)} for 15 s`);
    if (S.prevHomeAlive === false && h.alive) toast("good", "Home node back", nodeName(h.id));
    if (h.heal && !S.prevHeal) toast("warn", "Channel heal sweep", "Home lost the fleet and is scanning channels");
    S.prevHomeAlive = h.alive;
    S.prevHeal = h.heal || 0;
}

let audioCtx = null;
function beep(test) {
    try {
        audioCtx = audioCtx || new (window.AudioContext || window.webkitAudioContext)();
        const t = audioCtx.currentTime;
        const n = test ? 1 : 3;
        for (let i = 0; i < n; i++) {
            const o = audioCtx.createOscillator(), g = audioCtx.createGain();
            o.type = "square";
            o.frequency.value = 1760;
            g.gain.setValueAtTime(0.0001, t + i * 0.16);
            g.gain.exponentialRampToValueAtTime(0.08, t + i * 0.16 + 0.01);
            g.gain.exponentialRampToValueAtTime(0.0001, t + i * 0.16 + 0.11);
            o.connect(g).connect(audioCtx.destination);
            o.start(t + i * 0.16);
            o.stop(t + i * 0.16 + 0.12);
        }
    } catch (e) { /* audio blocked until first user gesture */ }
}
function flashScreen() {
    const o = $("flashOverlay");
    o.classList.remove("go"); void o.offsetWidth; o.classList.add("go");
}

const ALERT_QUIET_S = 300, ALERT_GAP_MS = 2000;
S.macSeen = {};
S.lastAlert = 0;
// ------------------------------------------------------------------
// Live targets: every device heard in the last TARGET_WINDOW_S seconds, drawn
// where its signal puts it among the nodes that hear it, with a line from
// each of them (the closest one bright). The point is the RSSI-weighted
// centroid (dBm -> mW), so it hugs the strongest node: "closest node" now,
// and the same inputs real triangulation will use once nodes ring an area.
// ------------------------------------------------------------------
const TARGET_WINDOW_S = 60;
S.targets = {};
S.sight = [];
// Toggles, per browser: all targets on/off, and any device hidden on its own.
S.tgtOn = lsGet("ouispy.targetsOn", true);
S.tgtHidden = new Set(lsGet("ouispy.targetsHidden", []));
function syncTargetBtn() {
    const b = $("mapTargets");
    b.classList.toggle("on", S.tgtOn);
    b.setAttribute("aria-pressed", S.tgtOn ? "true" : "false");
    b.querySelector("span").textContent = S.tgtOn ? "Targets: on" : "Targets: off";
}
$("mapTargets").onclick = () => { S.tgtOn = !S.tgtOn; lsSet("ouispy.targetsOn", S.tgtOn); syncTargetBtn(); renderTargets(); };
function toggleTarget(mac) {
    S.tgtHidden.has(mac) ? S.tgtHidden.delete(mac) : S.tgtHidden.add(mac);
    lsSet("ouispy.targetsHidden", [...S.tgtHidden]);
    renderTargets();
}
syncTargetBtn();
// ------------------------------------------------------------------
// Triangulation (map toolbar switch). Each node's recent readings of a
// device (recency-weighted, minus that node's calibration offset) become a
// distance through the log-distance path-loss model, d = 10^((P0-RSSI)/(10n));
// a weighted least-squares fit of those circles gives the position. RSSI is
// only trustworthy inside the polygon of the nodes that hear it, so a fix
// needs 3+ of them and must land inside that polygon; outside it the target
// falls back to its closest node. Timestamps only weight and pair readings:
// radio covers 30 cm per ns, so node clocks cannot time the signal itself.
// ------------------------------------------------------------------
const TRI_WINDOW_S = 45;     // readings older than this are ignored
const TRI_K_MAX = 5;          // readings in a window are correlated: count at most 5 as independent
S.triOn = lsGet("ouispy.triOn", false);
S.triState = {};          // mac -> { p: [lat, lon], trail: [[lat, lon, ts], ...] }
S.devTrail = lsGet("ouispy.devTrail", {});   // mac -> seconds of track to draw (device drawer)
function devTrailFor(mac) { return S.devTrail[mac] ?? 300; }
function triModel() {
    return { p0_ble: -59, p0_wifi: -40, n: 2.7, sigma: 4, max_err: 8, smooth: 0.35, offsets: {}, devices: {},
             ...((S.settings && S.settings.tri) || {}) };
}
// Device model: its calibrated 1 m power and path-loss exponent, else the generic one.
function devModel(mac, dom, m) {
    const c = m.devices[mac];
    return c ? { p0: c.p0, n: c.n, cal: true } : { p0: dom === "wifi" ? m.p0_wifi : m.p0_ble, n: m.n, cal: false };
}
// Local flat projection in metres around a reference point (fine at mesh scale).
function triProj(lat0, lon0) {
    const kx = 111320 * Math.cos(lat0 * Math.PI / 180), ky = 110540;
    return { to: (lat, lon) => [(lon - lon0) * kx, (lat - lat0) * ky], from: (x, y) => [lat0 + y / ky, lon0 + x / kx] };
}
const LN10 = Math.log(10);
// Fisher information of a position from RSSI at nodes P (metres) with
// per-node weights k_i/sigma^2: the gradient of the mean RSSI model
// mu_i = P0 - 10 n log10(r_i) is g_i = -(10 n / ln10) (x - p_i) / r_i^2.
// Its inverse is the covariance of the best possible (and of our ML) estimate.
function fisher(x, y, P, w, nExp) {
    let a = 0, b = 0, c = 0;
    const kk = 10 * nExp / LN10;
    P.forEach((p, i) => {
        const dx = x - p[0], dy = y - p[1], r2 = Math.max(0.25, dx * dx + dy * dy);
        const gx = -kk * dx / r2, gy = -kk * dy / r2;
        a += w[i] * gx * gx; b += w[i] * gx * gy; c += w[i] * gy * gy;
    });
    const det = a * c - b * b;
    if (det <= 1e-12) return null;
    return { sxx: c / det, syy: a / det, sxy: -b / det };   // covariance, m^2
}
// Fixes are cached per device and recomputed only when its readings change
// (a new one, or one aging out of the window), not on every 1 s tick.
S.triCache = {};
function triFix(t) {
    const nowS = Date.now() / 1000, mm = triModel();
    const key = JSON.stringify([mm, Object.entries(t.samples).map(([id, xs]) => {
        const live = xs.filter((x) => nowS - x.ts <= TRI_WINDOW_S);
        const n = nodeById(id);
        return [id, live.length, live.length ? live[0].ts : 0, n && n.lat, n && n.lon];
    }), S.device === t.mac]);
    const c = S.triCache[t.mac];
    if (c && c.key === key) return c.fix;
    const fix = triFixCompute(t);
    S.triCache[t.mac] = { key, fix };
    return fix;
}
function triFixCompute(t) {
    const m = triModel(), now = Date.now() / 1000, dm = devModel(t.mac, t.dom, m);
    const nodes = [];
    for (const [id, samples] of Object.entries(t.samples)) {
        const n = nodeById(id);
        if (!n || n.lat == null) continue;
        const xs = samples.filter((x) => now - x.ts <= TRI_WINDOW_S).map((x) => x.rssi - (m.offsets[id] || 0));
        if (!xs.length) continue;
        const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
        nodes.push({ id, lat: n.lat, lon: n.lon, rssi: mean, k: Math.min(TRI_K_MAX, xs.length),
                     d: Math.pow(10, (dm.p0 - mean) / (10 * dm.n)) });
    }
    const base = { mac: t.mac, nodes, ok: false, cal: dm.cal };
    if (nodes.length < 3) return { ...base, why: `heard by ${nodes.length} of the 3 nodes needed` };
    const pr = triProj(nodes[0].lat, nodes[0].lon);
    const P = nodes.map((n) => pr.to(n.lat, n.lon));
    const w = nodes.map((n) => n.k / (m.sigma * m.sigma));
    // Grid posterior. The device's 1 m power P0 is unknown (calibrated: known
    // to its fit error; uncalibrated: generic +/-10 dB). For a spot (x, y)
    // the model RSSI_i = P0 - 10 n log10 r_i is linear in P0, so P0 is
    // integrated out exactly: a_i = RSSI_i + 10 n log10 r_i, best P0 is the
    // weighted mean of a_i and the prior, and the misfit chi^2(x, y) is what
    // remains. The posterior exp(-chi^2/2) over the whole grid gives the
    // position (its mean) and the error (its spread): "far and loud" versus
    // "near and quiet" shows up as a long, wide posterior, not a false fix.
    const c = m.devices[t.mac];
    const p0Prior = dm.p0, p0Sd = c ? Math.max(1, c.rms || 1.5) : 10, wp = 1 / (p0Sd * p0Sd);
    const xs = P.map((q) => q[0]), ys = P.map((q) => q[1]);
    const PAD = 60, x0 = Math.min(...xs) - PAD, x1 = Math.max(...xs) + PAD, y0 = Math.min(...ys) - PAD, y1 = Math.max(...ys) + PAD;
    const cell = Math.max(1, Math.max(x1 - x0, y1 - y0) / 140);
    const W = Math.ceil((x1 - x0) / cell), H = Math.ceil((y1 - y0) / cell);
    const sumW = w.reduce((p, q) => p + q, 0) + wp;
    const chi = new Float64Array(W * H);
    let chiMin = Infinity, best = 0;
    const tenN = 10 * dm.n;
    for (let j = 0; j < H; j++) {
        const y = y0 + (j + 0.5) * cell;
        for (let i = 0; i < W; i++) {
            const x = x0 + (i + 0.5) * cell;
            let sa = wp * p0Prior;
            const av = new Array(nodes.length);
            for (let k = 0; k < nodes.length; k++) {
                const r = Math.max(0.5, Math.hypot(x - P[k][0], y - P[k][1]));
                av[k] = nodes[k].rssi + tenN * Math.log10(r);
                sa += w[k] * av[k];
            }
            const p0 = sa / sumW;
            let q = wp * (p0 - p0Prior) ** 2;
            for (let k = 0; k < nodes.length; k++) q += w[k] * (av[k] - p0) ** 2;
            const o = j * W + i;
            chi[o] = q;
            if (q < chiMin) { chiMin = q; best = o; }
        }
    }
    // Readings disagree more than sigma allows (needs spare degrees of
    // freedom: nodes + prior - 3 unknowns): widen the posterior to match.
    const dof = nodes.length + 1 - 3;
    const s2 = dof > 0 ? Math.max(1, chiMin / dof) : 1;
    const pw = new Float64Array(W * H);
    let tw = 0;
    for (let o = 0; o < W * H; o++) { const v = Math.exp(-0.5 * (chi[o] - chiMin) / s2); pw[o] = v; tw += v; }
    // Position: the most likely spot, refined to sub-cell by the posterior
    // mean of its 5x5 neighbourhood.
    const bi = best % W, bj = Math.floor(best / W);
    let lw = 0, mx = 0, my = 0;
    for (let j = Math.max(0, bj - 2); j <= Math.min(H - 1, bj + 2); j++) {
        for (let i = Math.max(0, bi - 2); i <= Math.min(W - 1, bi + 2); i++) {
            const v = pw[j * W + i]; lw += v;
            mx += v * (x0 + (i + 0.5) * cell); my += v * (y0 + (j + 0.5) * cell);
        }
    }
    const x = mx / lw, y = my / lw;
    // Error: the radius around that spot holding 68% of the posterior mass.
    // Ambiguity (several far-apart places fit) makes it large, as it should.
    const dist = [];
    for (let o = 0; o < W * H; o++) {
        if (pw[o] < 1e-9 * tw) continue;
        dist.push([Math.hypot(x0 + ((o % W) + 0.5) * cell - x, y0 + (Math.floor(o / W) + 0.5) * cell - y), pw[o]]);
    }
    dist.sort((p1, p2) => p1[0] - p2[0]);
    let acc = 0, r68 = dist.length ? dist[dist.length - 1][0] : 0;
    for (const [d, v] of dist) { acc += v; if (acc >= 0.68 * tw) { r68 = d; break; } }
    const err = Math.max(r68, cell * 0.6);
    let p0Fit = wp * p0Prior;
    const aFit = nodes.map((n, k) => n.rssi + tenN * Math.log10(Math.max(0.5, Math.hypot(x - P[k][0], y - P[k][1]))));
    aFit.forEach((v, k) => { p0Fit += w[k] * v; });
    p0Fit /= sumW;
    const rmsDb = Math.sqrt(aFit.reduce((s3, v) => s3 + (v - p0Fit) ** 2, 0) / nodes.length);
    const errR = Math.round(err * 10) / 10;
    const rough = err > m.max_err;   // shown, but marked: the data can't pin it down here
    // Smooth across updates so the estimate glides instead of jumping.
    const raw = pr.from(x, y), st = S.triState[t.mac] = S.triState[t.mac] || { p: raw, trail: [] };
    st.p = [st.p[0] + m.smooth * (raw[0] - st.p[0]), st.p[1] + m.smooth * (raw[1] - st.p[1])];
    const last = st.trail[st.trail.length - 1];
    if (!last || map.distance([last[0], last[1]], st.p) > 0.5) st.trail.push([st.p[0], st.p[1], now]);
    while (st.trail.length && now - st.trail[0][2] > 1800) st.trail.shift();
    const keep = devTrailFor(t.mac);
    const trail = keep ? st.trail.filter((q) => now - q[2] <= keep).map((q) => [q[0], q[1]]) : [];
    return { ...base, ok: true, rough, p: st.p, err: errR, rmsDb: Math.round(rmsDb * 10) / 10, trail };
}
// Coverage = where a fix is actually possible and how good it can be: for a
// grid around the nodes, the expected 1-sigma error (Cramer-Rao bound, one
// reading per node) of a typical BLE device (generic 1 m power), counting
// only nodes that would hear it (predicted RSSI above -92 dBm).
const COV_COLORS = [[2, "57,255,136"], [5, "250,204,21"], [8, "251,146,60"]];
function coverageImage() {
    const m = triModel();
    const placed = S.fleet.nodes.filter((n) => n.lat != null && n.online);
    const key = JSON.stringify([placed.map((n) => [n.id, n.lat.toFixed(6), n.lon.toFixed(6)]), m.p0_ble, m.n, m.sigma, m.max_err]);
    if (S.cov && S.cov.key === key) return S.cov;
    S.cov = { key, overlay: null };
    if (placed.length < 3) return S.cov;
    const pr = triProj(placed[0].lat, placed[0].lon);
    const P = placed.map((n) => pr.to(n.lat, n.lon));
    const xs = P.map((p) => p[0]), ys = P.map((p) => p[1]);
    const pad = 40;
    const x0 = Math.min(...xs) - pad, x1 = Math.max(...xs) + pad, y0 = Math.min(...ys) - pad, y1 = Math.max(...ys) + pad;
    const cell = Math.max(0.5, Math.max(x1 - x0, y1 - y0) / 160);
    const W = Math.ceil((x1 - x0) / cell), H = Math.ceil((y1 - y0) / cell);
    const cv = document.createElement("canvas");
    cv.width = W; cv.height = H;
    const g = cv.getContext("2d"), img = g.createImageData(W, H);
    for (let j = 0; j < H; j++) {
        const y = y1 - (j + 0.5) * cell;
        for (let i = 0; i < W; i++) {
            const x = x0 + (i + 0.5) * cell;
            const hear = [], wts = [];
            P.forEach((p) => {
                const r = Math.max(0.5, Math.hypot(x - p[0], y - p[1]));
                if (m.p0_ble - 10 * m.n * Math.log10(r) >= -92) { hear.push(p); wts.push(1 / (m.sigma * m.sigma)); }
            });
            if (hear.length < 3) continue;
            const cov = fisher(x, y, hear, wts, m.n);
            if (!cov) continue;
            const e = Math.sqrt(cov.sxx + cov.syy);
            if (e > m.max_err) continue;
            const col = (COV_COLORS.find(([lim]) => e <= lim) || COV_COLORS[2])[1].split(",").map(Number);
            const o = (j * W + i) * 4;
            img.data[o] = col[0]; img.data[o + 1] = col[1]; img.data[o + 2] = col[2]; img.data[o + 3] = 255;
        }
    }
    g.putImageData(img, 0, 0);
    const sw = pr.from(x0, y0), ne = pr.from(x1, y1);
    S.cov.overlay = L.imageOverlay(cv.toDataURL(), [sw, ne], { opacity: 0.22, interactive: false });
    return S.cov;
}
// Calibration at a known spot: the device sits where the user clicked; for
// 30 s every node's readings of it are averaged. With the true distances
// known, RSSI_i = P0 - 10 n log10(d_i) is linear in (P0, n): a least-squares
// fit gives both when the distances differ enough (ratio >= 1.5) and the
// slope is physical (1.6..5); otherwise n stays at the generic value and
// only P0 is fitted. The fit RMS (dB) is what the result is worth.
const CAL_SECS = 30;
function showCal(mac) {
    const c = triModel().devices[mac];
    $("vCalInfo").textContent = S.calib && S.calib.mac === mac
        ? (S.calib.stage === "place" ? "Click the map exactly where this device is right now. Esc cancels."
                                     : `Listening ${Math.max(0, Math.ceil(S.calib.until - Date.now() / 1000))} s... keep the device still.`)
        : c ? `Calibrated ${ago(c.ts)}: ${c.p0} dBm at 1 m, path-loss exponent ${c.n}, fit error ${c.rms} dB over ${c.nodes} node${c.nodes === 1 ? "" : "s"}.`
            : "Not calibrated: positions use a generic model and can be off by several metres. Put the device somewhere you can point to on the map, then calibrate.";
    $("vCalReset").disabled = !c;
}
function calibAt(ll) {
    S.calib = { ...S.calib, stage: "listen", ll, start: Date.now() / 1000, until: Date.now() / 1000 + CAL_SECS };
    document.querySelector(".map-panel").classList.remove("placing");
    if (S.calibMark) map.removeLayer(S.calibMark);
    S.calibMark = L.circleMarker(ll, { radius: 7, color: "#facc15", weight: 2, fillOpacity: 0.3 }).addTo(map);
    const tick = setInterval(() => { if (S.device === S.calib.mac) showCal(S.calib.mac); }, 1000);
    setTimeout(async () => { clearInterval(tick); await calibFinish(); }, CAL_SECS * 1000);
    showCal(S.calib.mac);
}
async function calibFinish() {
    const c = S.calib;
    S.calib = null;
    if (S.calibMark) { map.removeLayer(S.calibMark); S.calibMark = null; }
    const m = triModel();
    const rows = [...S.sight, ...S.dets].filter((d) => d.mac === c.mac && d.ts >= c.start - 2 && d.ts <= c.until + 2 && d.rssi != null);
    const per = {};
    rows.forEach((d) => { (per[d.node] = per[d.node] || []).push(d.rssi - (m.offsets[d.node] || 0)); });
    const pts = [];
    for (const [id, xs] of Object.entries(per)) {
        const n = nodeById(id);
        if (!n || n.lat == null) continue;
        const d = Math.max(0.5, map.distance([n.lat, n.lon], c.ll));
        pts.push({ x: -10 * Math.log10(d), y: xs.reduce((a, b) => a + b, 0) / xs.length, d });
    }
    if (!pts.length) { toast("bad", "Calibration failed", "No node reported this device during the 30 s. Make sure it is transmitting and try again."); if (S.device === c.mac) showCal(c.mac); return; }
    const dm = devModel(c.mac, rows[0] && rows[0].dom, m);
    let n = dm.cal ? m.n : m.n, p0, fitted = false;
    const dists = pts.map((p) => p.d);
    if (pts.length >= 2 && Math.max(...dists) / Math.min(...dists) >= 1.5) {
        const mx = pts.reduce((a, p) => a + p.x, 0) / pts.length, my = pts.reduce((a, p) => a + p.y, 0) / pts.length;
        const sxx = pts.reduce((a, p) => a + (p.x - mx) ** 2, 0), sxy = pts.reduce((a, p) => a + (p.x - mx) * (p.y - my), 0);
        const slope = sxy / sxx;
        if (slope >= 1.6 && slope <= 5) { n = slope; p0 = my - n * mx; fitted = true; }
    }
    if (!fitted) p0 = pts.reduce((a, p) => a + (p.y - n * p.x), 0) / pts.length;
    const rms = Math.sqrt(pts.reduce((a, p) => a + (p.y - (p0 + n * p.x)) ** 2, 0) / pts.length);
    const devices = { ...m.devices, [c.mac]: { p0: Math.round(p0 * 10) / 10, n: Math.round(n * 100) / 100, rms: Math.round(rms * 10) / 10, nodes: pts.length, ts: Date.now() / 1000 } };
    await api("/api/settings", { method: "POST", body: { tri: { devices } } });
    S.settings.tri = { ...m, devices };
    delete S.triState[c.mac];
    toast("good", "Calibrated", `${p0.toFixed(1)} dBm at 1 m, exponent ${n.toFixed(2)}${fitted ? "" : " (generic: distances too similar to fit it)"}, fit error ${rms.toFixed(1)} dB, ${pts.length} node${pts.length === 1 ? "" : "s"}`);
    if (S.device === c.mac) showCal(c.mac);
}
$("vCal").onclick = () => {
    if (!S.device) return;
    S.calib = { mac: S.device, stage: "place" };
    document.querySelector(".map-panel").classList.add("placing");
    showCal(S.device);
};
$("vCalReset").onclick = async () => {
    const m = triModel(), devices = { ...m.devices };
    delete devices[S.device];
    await api("/api/settings", { method: "POST", body: { tri: { devices } } });
    S.settings.tri = { ...m, devices };
    delete S.triState[S.device];
    showCal(S.device);
};
document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && S.calib && S.calib.stage === "place") {
        S.calib = null;
        document.querySelector(".map-panel").classList.remove("placing");
        if (S.device) showCal(S.device);
    }
});

function renderTri(fixes) {
    if (!S.triLayer) S.triLayer = L.layerGroup().addTo(map);
    // Redraw only when something on it changed (it ran every second).
    const key = JSON.stringify([S.triOn, S.device, S.cov && S.cov.key, fixes.map((f) => [f.mac, f.ok, f.p, f.err, f.rough, f.trail && f.trail.length,
        S.device === f.mac ? f.nodes.map((n) => Math.round(n.d * 10)) : 0])]);
    if (key === S.triKey && S.triLayer.getLayers().length) return;
    S.triKey = key;
    S.triLayer.clearLayers();
    $("triLegend").hidden = !S.triOn;
    if (!S.triOn) return;
    const cov = coverageImage();
    if (cov.overlay) S.triLayer.addLayer(cov.overlay);
    for (const f of fixes) {
        if (!f.ok) continue;            // no fix: nothing to draw
        // Range circles only for the device being inspected (its drawer is open).
        if (S.device === f.mac) {
            for (const n of f.nodes) {
                L.circle([n.lat, n.lon], { radius: n.d, color: "#22d3ee", weight: 1, opacity: 0.4, dashArray: "4 6", fill: false, interactive: false }).addTo(S.triLayer);
            }
        }
        // The 68% region: solid when the data pins it down, dashed amber when rough.
        L.circle(f.p, f.rough
            ? { radius: f.err, color: "#fbbf24", weight: 1, dashArray: "5 6", fillColor: "#fbbf24", fillOpacity: 0.05, interactive: false }
            : { radius: f.err, color: "#ff4fd8", weight: 1, fillColor: "#ff4fd8", fillOpacity: 0.10, interactive: false }).addTo(S.triLayer);
        if (f.trail.length > 1) L.polyline(f.trail, { color: "#ff4fd8", weight: 2, opacity: 0.45, interactive: false }).addTo(S.triLayer);
    }
}
function syncTriBtn() {
    const b = $("mapTri");
    b.classList.toggle("on", S.triOn);
    b.setAttribute("aria-pressed", S.triOn ? "true" : "false");
    b.querySelector("span").textContent = S.triOn ? "Triangulate: on" : "Triangulate: off";
}
$("mapTri").onclick = () => {
    S.triOn = !S.triOn;
    lsSet("ouispy.triOn", S.triOn);
    if (S.triOn && !S.tgtOn) { S.tgtOn = true; lsSet("ouispy.targetsOn", true); syncTargetBtn(); }
    syncTriBtn();
    renderTargets();
};
syncTriBtn();

function onSighting(d) {
    S.sight.unshift(d);
    S.sight = S.sight.filter((x) => Date.now() / 1000 - x.ts <= TARGET_WINDOW_S).slice(0, 400);
    renderTargets();
}
function liveTargets() {
    const now = Date.now() / 1000, by = {};
    // Detections plus the quiet signal updates nodes send while a device stays in view.
    const rows = S.sight.length ? [...S.sight, ...S.dets].sort((a, b) => b.ts - a.ts) : S.dets;
    for (const d of rows) {
        if (now - d.ts > TARGET_WINDOW_S) break;          // newest first
        if (d.rssi == null) continue;
        const t = by[d.mac] = by[d.mac] || { mac: d.mac, name: devAlias(d.mac, devName(d.mac, d.descr || d.match)), last: d.ts, per: {}, samples: {}, dom: d.dom };
        if (!t.per[d.node]) t.per[d.node] = { rssi: d.rssi, ts: d.ts };   // newest per node
        (t.samples[d.node] = t.samples[d.node] || []).push({ rssi: d.rssi, ts: d.ts });
    }
    return Object.values(by).map((t) => {
        t.seen = Object.entries(t.per).map(([node, v]) => ({ node, ...v })).sort((a, b) => b.rssi - a.rssi);
        t.closest = t.seen[0].node;
        return t;
    }).sort((a, b) => b.last - a.last);
}
function targetPoint(t) {
    let sw = 0, lat = 0, lon = 0;
    for (const s of t.seen) {
        const n = nodeById(s.node);
        if (!n || n.lat == null) continue;
        const w = Math.pow(10, s.rssi / 10);
        sw += w; lat += w * n.lat; lon += w * n.lon;
    }
    return sw ? [lat / sw, lon / sw] : null;
}
function renderTargets() {
    if (!S.fleet) return;
    if (!S.targetLayer) S.targetLayer = L.layerGroup().addTo(map);
    const live = liveTargets(), keep = new Set(), fixes = [];
    for (const t of live) {
        if (!S.tgtOn || S.tgtHidden.has(t.mac)) continue;
        const fix = S.triOn ? triFix(t) : null;
        if (fix) fixes.push(fix);
        const p = fix && fix.ok ? fix.p : targetPoint(t);
        if (!p) continue;
        keep.add(t.mac);
        let g = S.targets[t.mac];
        const label = !S.triOn ? `${esc(t.name)}<br><b>${esc(nodeName(t.closest))}</b> ${t.seen[0].rssi} dBm`
            : fix && fix.ok ? `${esc(t.name)}<br><b>&plusmn;${fix.err} m</b> (68%)${fix.rough ? " <span class=\"uncal\">rough</span>" : ""}${fix.cal ? "" : " <span class=\"uncal\">uncalibrated</span>"}`
            : `${esc(t.name)}<br>no fix: ${esc(fix ? fix.why : "no signal")}; closest <b>${esc(nodeName(t.closest))}</b>`;
        if (!g) {
            g = S.targets[t.mac] = { lines: {}, marker: L.marker(p, { interactive: true, keyboard: false, zIndexOffset: 500,
                icon: L.divIcon({ className: "", iconSize: [0, 0], html: `<div class="tgt"><span class="tgt-dot"></span><span class="tgt-label"></span></div>` }) }).addTo(S.targetLayer) };
            g.marker.on("click", () => openDevice(t.mac));
        } else {
            const ll = g.marker.getLatLng();
            if (Math.abs(ll.lat - p[0]) > 1e-9 || Math.abs(ll.lng - p[1]) > 1e-9) g.marker.setLatLng(p);
        }
        const el = g.marker.getElement();
        const lab = el && el.querySelector(".tgt-label");
        if (lab && lab.innerHTML !== label) lab.innerHTML = label;
        const lineKeep = new Set();
        for (const s of (S.triOn ? [] : t.seen)) {     // triangulate: the spot speaks for itself
            const n = nodeById(s.node);
            if (!n || n.lat == null) continue;
            lineKeep.add(s.node);
            const close = s.node === t.closest;
            const age = Date.now() / 1000 - s.ts;
            const style = { color: close ? "#39ff88" : "#fbbf24", weight: close ? 3 : 1.5,
                            dashArray: close ? null : "4 6", opacity: Math.max(0.25, 1 - age / TARGET_WINDOW_S), interactive: false };
            let ln = g.lines[s.node];
            if (!ln) ln = g.lines[s.node] = L.polyline([[n.lat, n.lon], p], style).addTo(S.targetLayer);
            else { ln.setLatLngs([[n.lat, n.lon], p]); ln.setStyle(style); }
        }
        for (const id of Object.keys(g.lines)) {
            if (!lineKeep.has(id)) { S.targetLayer.removeLayer(g.lines[id]); delete g.lines[id]; }
        }
    }
    for (const mac of Object.keys(S.targets)) {
        if (keep.has(mac)) continue;
        const g = S.targets[mac];
        S.targetLayer.removeLayer(g.marker);
        Object.values(g.lines).forEach((l) => S.targetLayer.removeLayer(l));
        delete S.targets[mac];
    }
    renderTri(fixes);
    // Labels moved, appeared or changed text: lay every label out again.
    const sig = Object.keys(S.targets).map((m) => { const g = S.targets[m], ll = g.marker.getLatLng(); return `${m}${ll.lat.toFixed(6)}${ll.lng.toFixed(6)}${g.marker.getElement() ? g.marker.getElement().querySelector(".tgt-label").innerHTML : ""}`; }).join("|");
    if (sig !== S.tgtSig) { S.tgtSig = sig; declutterLabels(); }
    // The list under the map: closest node per live device, every node's signal.
    const box = $("nearest");
    const html = live.length ? live.slice(0, 8).map((t) => `
        <div class="near-row ${S.tgtOn && !S.tgtHidden.has(t.mac) ? "" : "hidden-tgt"}" data-mac="${esc(t.mac)}">
            <button class="near-eye" data-mac="${esc(t.mac)}" title="${S.tgtHidden.has(t.mac) ? "Show this device on the map" : "Hide this device on the map"}">${S.tgtHidden.has(t.mac) ? "Hidden" : "On map"}</button>
            <span class="near-name">${esc(t.name)}</span>
            <span class="near-mac">${esc(t.mac)}</span>
            <span class="near-close">${esc(nodeName(t.closest))} ${t.seen[0].rssi} dBm</span>
            ${t.seen.slice(1).map((s) => `<span class="near-other">${esc(nodeName(s.node))} ${s.rssi}</span>`).join("")}
        </div>`).join("") : "";
    if (box.innerHTML !== html) {
        box.innerHTML = html;
        box.querySelectorAll(".near-row").forEach((r) => r.onclick = () => openDevice(r.dataset.mac));
        box.querySelectorAll(".near-eye").forEach((b) => b.onclick = (e) => { e.stopPropagation(); toggleTarget(b.dataset.mac); });
    }
}

function onDetection(d) {
    mxOnDetection();
    if (d.name) S.deviceNames[d.mac] = d.name;
    S.dets.unshift(d);
    S.dets.length = Math.min(S.dets.length, 300);
    renderTargets();
    if (S.statsBase) {
        S.statsBase.total++; S.statsBase.day++;
        if (d.is_new) S.statsBase.macs++;
        const pn = S.statsBase.per_node[d.node] = S.statsBase.per_node[d.node] || { count: 0 };
        pn.count++; pn.last = d.ts;
    }
    const f = $("feed");
    if (f.querySelector(".empty")) f.innerHTML = "";
    f.insertAdjacentHTML("afterbegin", detHtml(d, true));
    wireDet(f.firstElementChild);
    while (f.children.length > 120) f.lastElementChild.remove();
    renderKpis();
    hitNode(d.node);
    const hh = homeNode();
    if (hh && d.node !== hh.id) flow(meshRoute(d.node, hh.id), "det");
    bumpHourly(d.ts);
    renderActivity();
    if (d.is_new) {
        toast("bad", `New device: ${devAlias(d.mac, d.descr || d.match)}`,
              `${d.mac}  ${d.rssi} dBm  via ${nodeName(d.node)}${d.closest ? `, closest to ${nodeName(d.closest)}` : ""}`, () => openDevice(d.mac));
    }
    // Sound and screen flash are for news: a new device, or one back after
    // ALERT_QUIET_S of silence, at most once per ALERT_GAP_MS. A device a node
    // keeps re-reporting would otherwise flash the screen every few seconds.
    const prev = S.macSeen[d.mac];
    S.macSeen[d.mac] = d.ts;
    if ((d.is_new || !prev || d.ts - prev >= ALERT_QUIET_S) && Date.now() - S.lastAlert >= ALERT_GAP_MS) {
        S.lastAlert = Date.now();
        if (S.settings.sound) beep(false);
        if (S.settings.flash) flashScreen();
    }
    if (!histFiltered()) {
        $("hBody").insertAdjacentHTML("afterbegin", histRow(d));
        S.hist.total = (S.hist.total || 0) + 1;
        $("hTotal").textContent = `${S.hist.total} detection${S.hist.total === 1 ? "" : "s"}`;
    }
    if (S.selected === d.node && $("drawer").classList.contains("open")) {
        $("dDets").insertAdjacentHTML("afterbegin", detHtml(d, true));
    }
}

// ------------------------------------------------------------------
// drawer
// ------------------------------------------------------------------
function selectNode(id, open) {
    if (!id) return;
    S.selected = id;
    renderNodes();
    renderMap();
    const n = nodeById(id);
    if (n && n.lat != null && open) map.panTo([n.lat, n.lon], { animate: true });
    if (open || $("drawer").classList.contains("open")) openDrawer(id);
}
function closeDrawer() { $("drawer").classList.remove("open"); }
$("dClose").onclick = closeDrawer;

async function openDrawer(id) {
    $("vDrawer").classList.remove("open");
    $("drawer").classList.add("open");
    const r = await fetch(`/api/nodes/${id}`);
    if (!r.ok) return;
    const data = await r.json();
    const n = data.node;
    $("dTitle").textContent = n.alias || n.id;
    $("dSub").textContent = `${n.id} | ${n.is_home ? "home" : n.role} | first seen ${n.first_seen ? fullTime(n.first_seen) : "-"}`;
    if (document.activeElement !== $("dAlias")) $("dAlias").value = n.alias || "";
    if (document.activeElement !== $("dNotes")) $("dNotes").value = n.notes || "";
    showColor(n); showTrail(n);
    const st = nodeState(n);
    const samples = data.sightings.filter((s) => s.rssi);
    const avg = samples.length ? Math.round(samples.reduce((a, s) => a + s.rssi, 0) / samples.length) : null;
    const cells = [
        ["Status", st.toUpperCase(), st === "online" ? "good" : st === "stale" ? "warn" : "bad"],
        ["Last seen", ago(n.last_seen)],
        ["Link RSSI", n.is_home ? "local" : n.rssi ? `${n.rssi} dBm` : "-"],
        ["Packets", n.is_home ? "-" : n.pkts || 0],
        ["Detections", data.stats.count || 0, data.stats.count ? "bad" : ""],
        ["Avg RSSI 24h", avg ? `${avg} dBm` : "-"],
    ];
    $("dStats").innerHTML = cells.map(([k, v, c]) =>
        `<div class="hs"><div class="k">${k}</div><div class="v ${c || ""}">${esc(v)}</div></div>`).join("");
    $("dSpark").innerHTML = spark(samples);
    $("dDets").innerHTML = data.detections.length
        ? data.detections.map((d) => detHtml(d)).join("")
        : `<div class="empty">No detections from this node.</div>`;
    const evs = data.sightings.filter((s) => s.event !== "sample").slice(-30).reverse();
    $("dEvents").innerHTML = evs.length
        ? evs.map((e) => `<div><span class="${e.event === "online" ? "on" : "off"}">${e.event.toUpperCase()}</span> ${fullTime(e.ts)}</div>`).join("")
        : `<div>No link events in 24 h.</div>`;
    renderGpsButton();
    if (S.editFor && S.editFor !== id) { S.editing = null; S.editFor = null; }
    if (S.audioDirty && S.audioDirty !== id) S.audioDirty = null;
    $("dFilters").innerHTML = "";
    renderRemote();
    $("dPlace").textContent = n.lat != null ? "Move on map" : "Place on map";
    $("dUnplace").style.display = n.lat != null ? "" : "none";
    $("dForget").style.display = n.online ? "none" : "";
}
function spark(samples) {
    if (samples.length < 2) return `<div class="none">Not enough samples yet</div>`;
    const W = 380, H = 70, lo = -100, hi = -30;
    const t0 = samples[0].ts, t1 = samples[samples.length - 1].ts || t0 + 1;
    const pts = samples.map((s) => {
        const x = ((s.ts - t0) / Math.max(1, t1 - t0)) * (W - 8) + 4;
        const y = H - 4 - ((Math.min(hi, Math.max(lo, s.rssi)) - lo) / (hi - lo)) * (H - 8);
        return `${x.toFixed(1)},${y.toFixed(1)}`;
    }).join(" ");
    return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">
        <defs><linearGradient id="sg" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#4ecdc4" stop-opacity=".35"/><stop offset="1" stop-color="#4ecdc4" stop-opacity="0"/></linearGradient></defs>
        <polygon points="4,${H} ${pts} ${W - 4},${H}" fill="url(#sg)" stroke="none"/>
        <polyline points="${pts}" fill="none" stroke="#4ecdc4" stroke-width="2" style="filter:drop-shadow(0 0 4px #4ecdc4)"/>
    </svg>`;
}
$("dSave").onclick = async () => {
    await api(`/api/nodes/${S.selected}`, { method: "POST", body: { alias: $("dAlias").value, notes: $("dNotes").value } });
    $("dTitle").textContent = $("dAlias").value || S.selected;
};
$("dAlias").addEventListener("keydown", (e) => { if (e.key === "Enter") $("dSave").click(); });
$("dNotes").addEventListener("change", () => api(`/api/nodes/${S.selected}`, { method: "POST", body: { notes: $("dNotes").value } }));
$("dPlace").onclick = () => setPlacing(true);
// Color slider: live preview while dragging, saved when let go.
function showTrail(n) { if (n) $("dTrail").value = String(trailFor(n.id)); }
function showColor(n) {
    const on = n && n.color != null;
    if (document.activeElement !== $("dColor")) $("dColor").value = on ? n.color : 180;
    $("dColor").classList.toggle("unset", !on);
    $("dColorDot").style.background = on ? nodeColor(n) : "transparent";
    $("dColorReset").disabled = !on;
}
$("dColor").oninput = () => {
    const n = nodeById(S.selected);
    if (!n) return;
    n.color = Number($("dColor").value);
    showColor(n); showTrail(n);
    renderNodes(); renderMap();
};
$("dColor").onchange = () => api(`/api/nodes/${S.selected}`, { method: "POST", body: { color: Number($("dColor").value) } });
$("dColorReset").onclick = async () => {
    const n = nodeById(S.selected);
    if (n) n.color = null;
    showColor(n); showTrail(n);
    renderNodes(); renderMap();
    await api(`/api/nodes/${S.selected}`, { method: "POST", body: { color: null } });
};
$("dUnplace").onclick = async () => {
    await api(`/api/nodes/${S.selected}`, { method: "POST", body: { lat: null, lon: null } });
    openDrawer(S.selected);
};
let forgetArmed = false;
$("dForget").onclick = async () => {
    // Two-tap confirm, same pattern as the device portal's burn-in button.
    if (!forgetArmed) {
        forgetArmed = true;
        $("dForget").textContent = "Tap again to forget";
        setTimeout(() => { forgetArmed = false; $("dForget").textContent = "Forget node"; }, 3000);
        return;
    }
    forgetArmed = false;
    $("dForget").textContent = "Forget node";
    await api(`/api/nodes/${S.selected}`, { method: "DELETE" });
    closeDrawer();
};

// ------------------------------------------------------------------
// history
// ------------------------------------------------------------------
function histParams() {
    const p = new URLSearchParams();
    if ($("hQ").value.trim()) p.set("q", $("hQ").value.trim());
    if ($("hNode").value) p.set("node", $("hNode").value);
    if ($("hDom").value) p.set("dom", $("hDom").value);
    if ($("hRange").value) p.set("since", String(Math.floor(now() - Number($("hRange").value))));
    return p;
}
function histFiltered() { return [...histParams().keys()].length > 0; }
function histRow(d) {
    return `<tr class="${d.is_new ? "new" : ""}"><td>${fullTime(d.ts)}</td><td>${esc(nodeName(d.node))}</td>
        <td>${esc(d.mac)}</td><td class="v">${devAlias(d.mac, d.alias) ? `<span class="mal">${esc(devAlias(d.mac, d.alias))}</span> ` : ""}${esc(d.descr || d.match || "")}</td>
        <td>${d.dom === "wifi" ? "WiFi" : "BLE"} ${esc(d.type || "")}</td><td>${d.rssi ?? ""}</td><td>${esc(d.source || "")}</td></tr>`;
}
async function loadHistory(append) {
    if (!append) S.hist.offset = 0;
    const p = histParams();
    p.set("limit", "200");
    p.set("offset", String(S.hist.offset));
    const r = await api(`/api/detections?${p}`);
    S.hist.total = r.total;
    const html = r.rows.map(histRow).join("");
    if (append) $("hBody").insertAdjacentHTML("beforeend", html);
    else $("hBody").innerHTML = html || `<tr><td colspan="7" style="text-align:center;padding:20px">No matching detections</td></tr>`;
    S.hist.offset += r.rows.length;
    $("hTotal").textContent = `${r.total} detection${r.total === 1 ? "" : "s"}`;
    $("hMore").style.display = S.hist.offset < r.total ? "" : "none";
    const ep = histParams().toString();
    $("expCsv").href = `/api/export/detections.csv${ep ? "?" + ep : ""}`;
    $("expJson").href = `/api/export/detections.json${ep ? "?" + ep : ""}`;
}
let histTimer = null;
$("hQ").addEventListener("input", () => { clearTimeout(histTimer); histTimer = setTimeout(() => loadHistory(false), 250); });
["hNode", "hDom", "hRange"].forEach((id) => $(id).addEventListener("change", () => loadHistory(false)));
$("hMore").onclick = () => loadHistory(true);

// ------------------------------------------------------------------
// remote settings (commands go home -> mesh -> node)
// ------------------------------------------------------------------
function canCommand() {
    return Object.values(S.sources).some((x) => (x.kind === "serial" && x.connected) || x.kind === "demo");
}
function homeNode() { return S.fleet.nodes.find((n) => n.is_home); }
function syncState(n) {
    const h = homeNode();
    if (!n || !n.cfg || !n.cfg.fcrc || !h || !h.cfg || !h.cfg.fcrc || n.is_home) return null;
    return n.cfg.fcrc === h.cfg.fcrc ? "ok" : "drift";
}
function twoTap(btn, fn) {
    if (btn._armed) {
        btn._armed = false;
        btn.classList.remove("armed");
        btn.textContent = btn._label;
        fn();
        return;
    }
    btn._label = btn.textContent;
    btn._armed = true;
    btn.classList.add("armed");
    btn.textContent = "Tap again to confirm";
    setTimeout(() => {
        if (btn._armed) { btn._armed = false; btn.classList.remove("armed"); btn.textContent = btn._label; }
    }, 3500);
}
async function command(target, op, args) {
    const url = target === "all" ? "/api/fleet/cmd" : `/api/nodes/${target}/cmd`;
    const r = await api(url, { method: "POST", body: { op, args: args || {} } });
    if (!r.ok) toast("bad", "Command not sent", r.error);
    else onJob(r.job);
    return r;
}
function targetName(t) { return t === "all" ? "all nodes" : nodeName(t); }
const JOB_RANK = { queued: 0, sending: 1, sent: 2, done: 3, failed: 3, partial: 3 };
S.jobWaiters = {};
// Resolves when the job reaches done / failed / partial.
function waitJob(id) {
    const j = S.jobs.find((x) => x.id === id);
    if (j && ["done", "failed", "partial"].includes(j.state)) return Promise.resolve(j);
    return new Promise((res) => { S.jobWaiters[id] = res; });
}

// ------------------------------------------------------------------
// firmware updates over the mesh
// ------------------------------------------------------------------
S.firmware = null;
S.fwSel = new Set();
S.fwRun = null;          // {queue: [ids], current, results: {id: text}}
function fwBuildOf(n) { return (n.cfg && n.cfg.fw) || ""; }
// A node's update as the home reports it (fleet "ota"): live while the home
// is still sending (reports every 2 s), otherwise the last result.
function otaLive(n) { const o = n && n.ota; return o && ["offered", "sending"].includes(o.state) && now() - o.ts < 20 ? o : null; }
function otaText(n) {
    const o = n && n.ota;
    if (!o) return "";
    if (otaLive(n)) return `${o.state === "offered" ? "starting" : "updating"} ${o.pct || 0}%${o.kbps ? " | " + o.kbps + " kbps" : ""}`;
    if (o.state === "done") return `updated ${ago(o.finished || o.ts)}`;
    if (o.state === "failed") return `failed ${ago(o.finished || o.ts)}: ${o.err || ""}`;
    return `stalled at ${o.pct || 0}% (${ago(o.ts)})`;
}
// The node already runs the uploaded build? Nodes report the first 15
// characters of their build stamp ("Oct 27 2026 18:").
// "Oct 27 2026 21:21:25" (the image) -> "Oct27 21:21:25" (what nodes report).
function fwCompact(b) {
    const x = /^([A-Z][a-z]{2}) +(\d{1,2}) \d{4} (\d\d:\d\d:\d\d)$/.exec(b || "");
    return x ? `${x[1]}${x[2].padStart(2, "0")} ${x[3]}` : "";
}
function fwCurrent(n) {
    const f = fwBuildOf(n), m = S.firmware;
    if (!f || !m || !m.build) return false;
    if (/^[A-Z][a-z]{2}\d{2} \d\d:\d\d:\d\d$/.test(f)) return f === fwCompact(m.build);   // exact
    return f.length >= 15 && m.build.startsWith(f);   // older firmware: its stamp was cut to 15 chars
}
function renderFirmware() {
    const m = S.firmware;
    $("fwInfo").innerHTML = m
        ? `<b>${esc(m.filename || "firmware.bin")}</b> build ${esc(m.build || m.date + " " + m.time)} | ${(m.size / 1024).toFixed(0)} KB | ${esc(m.sha256.slice(0, 12))}`
        : "No image uploaded";
    const nodes = S.fleet.nodes.slice().sort((a, b) => (a.is_home - b.is_home) || String(a.alias || a.id).localeCompare(b.alias || b.id));
    const job = (id) => S.jobs.find((j) => j.op && j.op.startsWith("fw_") && (j.target === id) && !["done", "failed", "partial"].includes(j.state))
        || (S.fwRun && S.fwRun.lastJob[id]);
    $("fwNodes").innerHTML = nodes.map((n) => {
        const j = job(n.id);
        const res = S.fwRun && S.fwRun.results[n.id];
        const live = otaLive(n);
        const pct = j && j.progress != null ? j.progress : live ? live.pct || 0 : null;
        const stage = j ? (j.op === "fw_stage" ? "staging on home" : j.ota && j.ota.state ? j.ota.state : j.state)
            : live ? otaText(n) : "";
        const last = !j && !live && !res && n.ota ? otaText(n) : "";
        return `<label class="fw-node ${n.online ? "" : "off"}">
            <input type="checkbox" data-id="${esc(n.id)}" ${S.fwSel.has(n.id) ? "checked" : ""} ${n.online && !S.fwRun ? "" : "disabled"}>
            <span class="fw-name">${esc(n.alias || n.id)}${n.is_home ? " <i>home</i>" : ""}</span>
            <span class="fw-cur" title="Firmware build it runs now">${esc(fwBuildOf(n) || "build unknown")}${fwCurrent(n) ? ` <b class="fw-ok">current</b>` : S.firmware && fwBuildOf(n) ? ` <b class="fw-old">older</b>` : ""}</span>
            ${pct != null || res ? `<span class="fw-bar"><i style="width:${pct != null ? pct : 100}%"></i></span>
            <span class="fw-st">${esc(res || (j ? `${stage}${pct != null ? " " + pct + "%" : ""}${j.ota && j.ota.kbps ? " | " + j.ota.kbps + " kbps" : ""}` : stage))}</span>` : last ? `<span class="fw-st fw-last">${esc(last)}</span>` : ""}
        </label>`;
    }).join("");
    $("fwNodes").querySelectorAll("input[type=checkbox]").forEach((c) => c.onchange = () => {
        if (c.checked) S.fwSel.add(c.dataset.id); else S.fwSel.delete(c.dataset.id);
        $("fwGo").disabled = !S.firmware || !S.fwSel.size || !!S.fwRun;
    });
    $("fwGo").disabled = !S.firmware || !S.fwSel.size || !!S.fwRun;
    $("fwGo").textContent = S.fwRun ? "Updating..." : "Update selected";
}
$("fwFile").onchange = async () => {
    const f = $("fwFile").files[0];
    if (!f) return;
    const r = await fetch("/api/firmware", { method: "POST", body: f, headers: { "X-Filename": f.name, "Content-Type": "application/octet-stream" } });
    const d = await r.json();
    if (!d.ok) { toast("bad", "Firmware not accepted", d.error); return; }
    S.firmware = d.firmware;
    toast("good", "Firmware uploaded", `${d.firmware.kind === "skyspy" ? "Sky-Spy" : "detector"} build ${d.firmware.build || d.firmware.date}, ${(d.firmware.size / 1024).toFixed(0)} KB`);
    renderFirmware();
    $("fwFile").value = "";
};
// Stage on the home once, then each selected remote in turn, the home last.
$("fwGo").onclick = () => twoTap($("fwGo"), async () => {
    const h = homeNode();
    if (!h || !S.firmware) return;
    const remotes = [...S.fwSel].filter((id) => id !== h.id);
    const home = S.fwSel.has(h.id);
    S.fwRun = { results: {}, lastJob: {} };
    renderFirmware();
    const run = async (target, op) => {
        const r = await command(target, op);
        if (!r.ok) return { state: "failed", error: r.error };
        S.fwRun.lastJob[target] = r.job;
        return waitJob(r.job.id);
    };
    const st = await run(h.id, "fw_stage");
    if (st.state !== "done") {
        S.fwRun.results[h.id] = "staging failed: " + (st.error || "");
    } else {
        for (const id of remotes) {
            const j = await run(id, "fw_send");
            S.fwRun.results[id] = j.state === "done" ? "updated, rebooting" : "failed: " + (j.error || Object.values(j.replies || {}).map((x) => x.text).join(", "));
            renderFirmware();
        }
        if (home) {
            const j = await run(h.id, "fw_self");
            S.fwRun.results[h.id] = j.state === "done" ? "installing, rebooting" : "failed: " + (j.error || "");
        }
    }
    const results = S.fwRun.results;
    S.fwRun = null;
    S.fwSel.clear();
    renderFirmware();
    const bad = Object.values(results).filter((t) => !/^updated|^installing/.test(t)).length;
    toast(bad ? "warn" : "good", "Firmware update finished", bad ? `${bad} node(s) need attention` : "all selected nodes updated");
});

function onJob(j) {
    const i = S.jobs.findIndex((x) => x.id === j.id);
    // The socket can deliver "done" before the POST that queued the job
    // returns: never let a stale update move a job backwards.
    if (i >= 0 && (JOB_RANK[S.jobs[i].state] ?? 0) > (JOB_RANK[j.state] ?? 0)) return;
    if (i >= 0) S.jobs[i] = j; else S.jobs.unshift(j);
    S.jobs.length = Math.min(S.jobs.length, 150);
    const prev = S.jobState[j.id];
    S.jobState[j.id] = j.state;
    const final = ["done", "failed", "partial"].includes(j.state);
    if (final && S.jobWaiters[j.id]) { S.jobWaiters[j.id](j); delete S.jobWaiters[j.id]; }
    if (j.op && j.op.startsWith("fw_")) renderFirmware();
    if (final && prev !== j.state && !j.auto && S.booted) {
        const reps = Object.entries(j.replies || {});
        const okN = reps.filter(([, r]) => r.st === 0).length;
        const body = j.state === "failed" ? j.error
            : j.target === "all" ? `${okN} of ${reps.length} nodes confirmed${j.error ? ", " + j.error : ""}`
            : (reps[0] ? reps[0][1].text : "done");
        toast(j.state === "done" ? "good" : j.state === "partial" ? "warn" : "bad",
              `${j.label}: ${targetName(j.target)}`, body);
    }
    renderJobs();
}
function jobHtml(j) {
    const reps = Object.entries(j.replies || {}).map(([n, r]) =>
        `<span class="${r.st === 0 ? "ok" : "bad"}" title="${esc(r.text)}">${esc(nodeName(n))}: ${esc(r.text)}</span>`).join("");
    const st = j.state === "sent" ? (j.target === "all" ? "collecting" : "waiting") : j.state;
    return `<div class="job ${esc(j.state)}">
        <div class="job-top"><span class="jstate">${esc(st)}</span><b>${esc(j.label)}</b>
            <span>${esc(targetName(j.target))}</span>${j.auto ? `<span class="cfg-age">auto</span>` : ""}
            <span class="jt">${hms(j.created)}</span></div>
        ${reps ? `<div class="job-rep">${reps}</div>` : ""}
        ${j.state === "failed" && j.error ? `<div class="job-err">${esc(j.error)}</div>` : ""}
    </div>`;
}
function renderJobs() {
    if ($("drawer").classList.contains("open") && S.selected) {
        const mine = S.jobs.filter((j) => (j.target === S.selected || j.target === "all") && !j.auto).slice(0, 12);
        $("dJobs").innerHTML = mine.map(jobHtml).join("") || `<div class="cfg-empty">No commands sent to this node yet.</div>`;
    }
    const all = S.jobs.filter((j) => $("fAuto").checked || !j.auto).slice(0, 60);
    $("fJobs").innerHTML = all.map(jobHtml).join("") || `<div class="cfg-empty">No commands yet.</div>`;
}
$("fAuto").onchange = renderJobs;

// One signature library (filters.library() on the server): the firmware
// presets and the portal's OUI database merged by vendor, so each vendor is
// listed once with every signature it has.
function vendorOptions(sel) {
    sel.innerHTML = allGroups().map((g) => `<option value="${esc(g.key)}" title="${esc(g.sources.join(" + "))}">${esc(g.label)} (${g.rows.length})</option>`).join("");
}

function cfgCells(n) {
    const c = n.cfg;
    const sync = syncState(n);
    return [
        ["Firmware", c.fw ? c.fw.replace(/^(\w+ \d+) \d{4}/, "$1") : "-"],
        ["Mode", (c.mode || "-").toUpperCase(), c.mode === "scan" ? "good" : "warn"],
        ["Burned in", c.locked ? "YES" : "NO", c.locked ? "good" : "warn"],
        ["Fleet key", keyState(n).txt, keyState(n).cls],
        ["Filters", `${c.filters}${sync ? `<span class="sync ${sync}">${sync === "ok" ? "SAME AS HOME" : "DIFFERS"}</span>` : ""}`, "", true],
        ["Uptime", uptime(c.up)],
        ["Heap", c.heap ? `${Math.round(c.heap / 1024)}K` : "-"],
        ["Delivered", c.dsent != null ? `${c.dacked}/${c.dsent}${c.dexp ? ` (${c.dexp} lost)` : ""}` : "-"],
        ["Channel", c.ch ?? "-", homeNode() && homeNode().cfg && c.ch !== homeNode().cfg.ch ? "bad" : ""],
        ["Update", otaText(n) || "-", otaLive(n) ? "warn" : n.ota && n.ota.state === "failed" ? "bad" : ""],
    ];
}
function renderRemote() {
    const n = nodeById(S.selected);
    if (!n || !$("drawer").classList.contains("open")) return;
    $("dRemote").classList.toggle("no-command", !canCommand());
    if (n.cfg) {
        $("dCfg").innerHTML = cfgCells(n).map(([k, v, cls, raw]) =>
            `<div class="hs"><div class="k">${k}</div><div class="v ${cls || ""}">${raw ? v : esc(v)}</div></div>`).join("");
        $("dCfgAge").textContent = n.cfg_ts ? `read ${ago(n.cfg_ts)}` : "";
        if (S.audioDirty !== n.id) {
            $("dBuzzer").checked = !!n.cfg.buzzer;
            $("dLed").checked = !!n.cfg.led;
        }
    } else {
        $("dCfg").innerHTML = `<div class="cfg-empty">Settings not read yet${canCommand() ? ". Press Refresh." : "."}</div>`;
        $("dCfgAge").textContent = "";
    }
    renderFilters(n);
    renderJobs();
}
// ------------------------------------------------------------------
// Predefined filter groups: the firmware presets + the portal's OUI
// database. Each can be added to or removed from the node being edited;
// changes are staged in the editor and go out with Push.
// ------------------------------------------------------------------
function allGroups() {
    return ((S.filterMeta && S.filterMeta.library) || []).map((g) => ({ ...g, section: "Signature library" }));
}
// Rows a group adds. The BLE / WiFi switches pick which radio's signatures
// go in: BLE off drops the BLE rows (OUI, MAC, CID, UUID, name), WiFi off
// drops the probe/beacon rows.
const WIFI_T = ["PROBE", "BEACON"];
function groupRows(g) {
    return g.rows.filter((r) => (WIFI_T.includes(r.t) ? S.groupWifi !== false : S.groupBle !== false))
        .map((r) => ({ t: r.t, id: r.id, d: r.d }));
}
function normId(id) { return String(id || "").replace(/[:\-\s]/g, "").toUpperCase(); }
// Does an installed row belong to this group? Exact type + identifier.
function rowInGroup(g, f) {
    return g.rows.some((r) => r.t === f.t && normId(r.id) === normId(f.id));
}
function groupState(g, list) {
    const want = groupRows(g);
    const key = (r) => r.t + ":" + String(r.id).replace(/[:\-\s]/g, "").toUpperCase();
    const have = new Set(list.map(key));
    const got = want.filter((r) => have.has(key(r))).length;
    const any = list.some((f) => rowInGroup(g, f));
    return { got, total: want.length, any };
}
function renderGroups() {
    const box = $("feGroups");
    if (!box || !S.editing) return;
    let html = "", section = "";
    for (const g of allGroups()) {
        if (g.section !== section) { section = g.section; html += `<div class="gsec">${esc(section)}</div>`; }
        const st = groupState(g, S.editing);
        const full = st.total > 0 && st.got === st.total;
        const chip = full ? `<span class="gst on">INSTALLED</span>`
            : st.any ? `<span class="gst part">PARTIAL</span>` : `<span class="gst">-</span>`;
        const info = `${g.rows.length} signature${g.rows.length === 1 ? "" : "s"}${g.meta && g.meta["Category"] ? " | " + g.meta["Category"] : ""}`;
        html += `<div class="grow" data-key="${esc(g.key)}">
            ${chip}<span class="gname" title="${esc(info)}">${esc(g.label)}</span><span class="ginfo">${esc(info)}</span>
            ${full ? "" : `<button class="btn ghost mini gadd">Add</button>`}
            ${st.any ? `<button class="btn ghost mini danger grm">Remove</button>` : ""}
        </div>`;
    }
    box.innerHTML = html;
    box.querySelectorAll(".gadd").forEach((b) => b.onclick = () => {
        readEditor();
        const g = allGroups().find((x) => x.key === b.closest(".grow").dataset.key);
        const key = (r) => r.t + ":" + String(r.id).replace(/[:\-\s]/g, "").toUpperCase();
        const have = new Set(S.editing.map(key));
        const add = groupRows(g).filter((r) => !have.has(key(r)));
        S.editing = S.editing.filter((f) => f.id).concat(add);
        rerenderEditor();
        toast("good", `Staged: +${add.length} filter${add.length === 1 ? "" : "s"}`, `${g.label} (press Push to apply)`);
    });
    box.querySelectorAll(".grm").forEach((b) => b.onclick = () => {
        readEditor();
        const g = allGroups().find((x) => x.key === b.closest(".grow").dataset.key);
        const before = S.editing.length;
        S.editing = S.editing.filter((f) => !rowInGroup(g, f));
        rerenderEditor();
        toast("warn", `Staged: -${before - S.editing.length} filter${before - S.editing.length === 1 ? "" : "s"}`, `${g.label} (press Push to apply)`);
    });
}

function renderFilters(n) {
    const box = $("dFilters");
    $("dFiltInfo").textContent = !n.filters ? "" :
        n.filters_fresh === false ? `${n.filters.length} shown, but the node now reports a different list: press Read` :
        n.filters_via ? `${n.filters.length} installed, CRC-verified identical to ${nodeName(n.filters_via)} ${ago(n.filters_ts)}` :
        `${n.filters.length} installed, read ${ago(n.filters_ts)}`;
    if (S.editing && S.editFor === n.id) {
        if (box.querySelector(".fedit")) return;   // keep focus while typing
        const types = (S.filterMeta && S.filterMeta.types) || {};
        box.innerHTML = `<div class="fedit"><div class="flist" id="fRows">${S.editing.map((f, i) => `
            <div class="frow" data-i="${i}">
                <select class="field ftype">${Object.keys(types).map((t) => `<option value="${t}" ${t === f.t ? "selected" : ""}>${t}</option>`).join("")}</select>
                <input class="field fi" value="${esc(f.id)}" placeholder="identifier">
                <input class="field fdesc" value="${esc(f.d)}" placeholder="description" maxlength="48">
                <button class="rm" title="Remove"><svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg></button>
            </div>`).join("")}</div>
            <div class="fvalid" id="fValid"></div>
            <div class="ctl-row">
                <button class="btn ghost" id="feAdd">Add row</button>
                <button class="btn ghost" id="feHome">Copy home's list</button>
            </div>
            <div class="rb-head"><h4>Predefined filters</h4>
                <label class="switch" title="OUI-database adds: each OUI as a BLE filter"><input type="checkbox" id="feBle" ${S.groupBle !== false ? "checked" : ""}><span></span>BLE</label>
                <label class="switch" title="OUI-database adds: each OUI as a WiFi probe filter"><input type="checkbox" id="feWifi" ${S.groupWifi !== false ? "checked" : ""}><span></span>WiFi</label>
            </div>
            <div class="groups" id="feGroups"></div>
            <div class="ctl-row">
                <button class="btn" id="fePush">Push to ${esc(n.alias || n.id)}</button>
                <button class="btn ghost" id="feCancel">Cancel</button>
            </div>
            <div class="help-text">Pushing replaces the node's whole filter list, live: the node keeps scanning. CIDs and service UUIDs are 4 hex digits, OUIs 6, full MACs 12, names 1-16 characters.</div>
        </div>`;
        renderGroups();
        wireEditor(n);
        validateEdit();
        return;
    }
    if (!n.filters) {
        box.innerHTML = `<div class="cfg-empty">Filter list not read yet.</div>`;
        return;
    }
    box.innerHTML = n.filters.length
        ? `<div class="flist">${n.filters.map((f) => `<div class="frow"><span class="ft ${esc(f.t)}">${esc(f.t)}</span>
            <span class="fid">${esc(f.id)}</span><span class="fd" title="${esc(f.d)}">${esc(f.d)}</span>
            ${n.filters.length > 1 ? `<button class="rm-live" data-t="${esc(f.t)}" data-id="${esc(f.id)}" title="Remove from this node (live)"><svg viewBox="0 0 24 24"><path d="M6 6l12 12M18 6 6 18"/></svg></button>` : ""}</div>`).join("")}</div>`
        : `<div class="cfg-empty">No filters: this node has nothing to scan for.</div>`;
    // Two taps: the first arms the button, the second (within 3.5 s) removes.
    box.querySelectorAll(".rm-live").forEach((b) => b.onclick = () => {
        if (!b.classList.contains("armed")) {
            b.classList.add("armed");
            b.title = "Tap again to remove";
            setTimeout(() => { b.classList.remove("armed"); b.title = "Remove from this node (live)"; }, 3500);
            return;
        }
        command(n.id, "filters_del", { filters: [{ t: b.dataset.t, id: b.dataset.id, d: "" }] });
    });
}

// Live add / remove of one identifier, from the quick row in the node
// drawer ("d") or the fleet tab ("f"). Applied on the node at once, no
// reboot. Auto picks the type from the hex length: 6 = OUI, 12 = full MAC.
function quickTypeOptions(sel) {
    const types = (S.filterMeta && S.filterMeta.types) || {};
    sel.innerHTML = `<option value="AUTO">Auto</option>` + Object.entries(types)
        .filter(([t]) => t !== "META")
        .map(([t, label]) => `<option value="${t}">${esc(label)}</option>`).join("");
}
function quickResolve(pre) {
    const raw = $(pre + "QId").value.trim();
    const hex = raw.replace(/[:\-\s.]/g, "").replace(/^0x/i, "").toUpperCase();
    let t = $(pre + "QType").value;
    if (t === "AUTO") t = /^[0-9A-F]{6}$/.test(hex) ? "OUI" : /^[0-9A-F]{12}$/.test(hex) ? "MAC" : "";
    const hexLen = (S.filterMeta && S.filterMeta.hex) || {};
    return { t, id: hexLen[t] ? hex : raw, raw };
}
function quickRecords(pre, removing) {
    const { t, id, raw } = quickResolve(pre);
    if (!raw) { toast("bad", "Nothing to send", "Type an OUI, MAC or other identifier first"); return null; }
    if (!t) { toast("bad", "Pick a type", "Auto knows 6 hex digits (an OUI) and 12 (a full MAC)"); return null; }
    const d = removing ? "" : ($(pre + "QDesc").value.trim() || "Added live");
    const recs = [{ t, id, d }];
    if (t === "OUI" && $(pre + "QWifi").checked) {
        recs.push({ t: "PROBE", id, d });
        if (removing) recs.push({ t: "BEACON", id, d });
    }
    return recs;
}
function wireQuick(pre, send) {
    const input = $(pre + "QId");
    const check = () => {
        const { t, raw } = quickResolve(pre);
        input.classList.toggle("bad", !!raw && !t);
    };
    input.addEventListener("input", check);
    $(pre + "QType").addEventListener("change", check);
    input.addEventListener("keydown", (e) => { if (e.key === "Enter") $(pre + "QAdd").click(); });
    $(pre + "QAdd").onclick = async () => {
        const recs = quickRecords(pre, false);
        if (!recs) return;
        if (await send("filters_add", recs)) { input.value = ""; $(pre + "QDesc").value = ""; check(); }
    };
    $(pre + "QDel").onclick = () => {
        const recs = quickRecords(pre, true);
        if (recs) twoTap($(pre + "QDel"), () => send("filters_del", recs));
    };
}
wireQuick("d", async (op, recs) => (await command(S.selected, op, { filters: recs })).ok);
// Fleet-wide: every remote over the mesh, and the home itself over USB.
wireQuick("f", async (op, recs) => {
    const h = homeNode();
    const r = await command("all", op, { filters: recs });
    const rh = h ? await command(h.id, op, { filters: recs }) : { ok: false };
    return r.ok || rh.ok;
});
function readEditor() {
    S.editing = [...document.querySelectorAll("#fRows .frow")].map((r) => ({
        t: r.querySelector(".ftype").value, id: r.querySelector(".fi").value.trim(), d: r.querySelector(".fdesc").value,
    }));
}
function rerenderEditor() {
    $("dFilters").innerHTML = "";
    renderFilters(nodeById(S.editFor));
}
function wireEditor(n) {
    const rows = $("fRows");
    rows.addEventListener("input", () => { readEditor(); validateEdit(); });
    rows.addEventListener("change", () => { readEditor(); validateEdit(); renderGroups(); });
    rows.querySelectorAll(".rm").forEach((b) => b.onclick = () => {
        readEditor();
        S.editing.splice(Number(b.closest(".frow").dataset.i), 1);
        rerenderEditor();
    });
    $("feAdd").onclick = () => { readEditor(); S.editing.push({ t: "OUI", id: "", d: "" }); rerenderEditor(); };
    $("feBle").onchange = () => { S.groupBle = $("feBle").checked; renderGroups(); };
    $("feWifi").onchange = () => { S.groupWifi = $("feWifi").checked; renderGroups(); };
    $("feHome").onclick = () => {
        const h = homeNode();
        if (h && h.filters) {
            S.editing = h.filters.map((f) => ({ t: f.t, id: f.id, d: f.d }));
            rerenderEditor();
        } else if (h) {
            S.loadHomePending = true;
            command(h.id, "filters_get");
            toast("warn", "Reading the home's filters", "The list fills in when it arrives");
        }
    };
    $("feCancel").onclick = () => { S.editing = null; S.editFor = null; renderFilters(n); };
    $("fePush").onclick = () => twoTap($("fePush"), async () => {
        readEditor();
        const r = await command(n.id, "filters_set", { filters: S.editing });
        if (r.ok) { S.editing = null; S.editFor = null; renderFilters(n); }
    });
}
let validTimer = null;
function validateEdit() {
    clearTimeout(validTimer);
    validTimer = setTimeout(async () => {
        if (!S.editing) return;
        const hexLen = (S.filterMeta && S.filterMeta.hex) || {};
        document.querySelectorAll("#fRows .frow").forEach((r) => {
            const t = r.querySelector(".ftype").value;
            const v = r.querySelector(".fi").value.replace(/[:\-\s]/g, "").replace(/^0x/i, "");
            const bad = hexLen[t] ? !(new RegExp(`^[0-9a-fA-F]{${hexLen[t]}}$`).test(v)) : !(v.length >= 1 && v.length <= 16);
            r.querySelector(".fi").classList.toggle("bad", bad);
        });
        const r = await api("/api/filters/validate", { method: "POST", body: { filters: S.editing } });
        const el = $("fValid");
        if (!el) return;
        const h = homeNode();
        const same = r.ok && h && h.cfg && h.cfg.fcrc === r.crc;
        el.className = `fvalid ${r.ok ? "" : "bad"}`;
        el.textContent = r.ok ? `${r.count} filters, ${r.bytes} bytes, CRC ${r.crc}${same ? "  (same as home)" : ""}` : r.error;
        $("fePush").disabled = !r.ok;
    }, 200);
}

$("dRefresh").onclick = () => command(S.selected, "status");
$("dBuzzer").onchange = $("dLed").onchange = () => { S.audioDirty = S.selected; };
$("dAudio").onclick = async () => {
    await command(S.selected, "audio", { buzzer: $("dBuzzer").checked, led: $("dLed").checked });
    S.audioDirty = null;
};
$("dIdent").onclick = () => command(S.selected, "identify", { secs: 15 });
// Install: the chosen library entry goes to the node live (only the
// signatures it doesn't have yet are new; the node keeps scanning).
$("dPresetGo").onclick = () => {
    const g = allGroups().find((x) => x.key === $("dPreset").value);
    if (g) twoTap($("dPresetGo"), () => command(S.selected, "filters_add", { filters: groupRows(g) }));
};
$("dReboot").onclick = () => twoTap($("dReboot"), () => command(S.selected, "reboot"));
$("dFiltRead").onclick = () => command(S.selected, "filters_get");
$("dFiltEdit").onclick = () => {
    const n = nodeById(S.selected);
    if (n && !n.filters) {
        // Never start from an empty list: a push replaces the node's whole
        // list, so read what it has first and open the editor on that.
        S.editAfterRead = S.selected;
        command(S.selected, "filters_get");
        toast("warn", "Reading the node's filters first", "The editor opens on its current list");
        return;
    }
    S.editFor = S.selected;
    S.editing = (n && n.filters ? n.filters : []).map((f) => ({ t: f.t, id: f.id, d: f.d }));
    if (!S.editing.length) S.editing.push({ t: "OUI", id: "", d: "" });
    $("dFilters").innerHTML = "";
    renderFilters(n);
};

// fleet control tab
function renderFleetCtl() {
    renderFirmware();
    $("tab-fleetctl").classList.toggle("no-command", !canCommand());
    const nodes = S.fleet.nodes;
    $("fBody").innerHTML = nodes.map((n) => {
        const c = n.cfg;
        const sync = syncState(n);
        if (!c) {
            return `<tr data-id="${esc(n.id)}"><td class="v">${esc(n.alias || n.id)}</td><td colspan="12">${n.online ? "not read yet" : "offline"}</td></tr>`;
        }
        const yn = (v, goodWhen = 1) => `<td class="${v === goodWhen ? "on" : "off"}">${v ? "on" : "off"}</td>`;
        return `<tr data-id="${esc(n.id)}"><td class="v">${esc(n.alias || n.id)}${n.is_home ? ` <span class="cfg-age">home</span>` : ""}</td>
            <td>${esc(c.fw || "-")}</td><td>${esc(c.mode || "")}</td><td>${c.locked ? "yes" : "no"}</td>
            ${yn(c.buzzer)}${yn(c.led)}<td class="key-${keyState(n).cls}" title="${esc(keyState(n).tip || "")}">${keyState(n).txt}</td>
            <td>${c.filters}${sync ? `<span class="sync ${sync}">${sync === "ok" ? "SAME" : "DIFFERS"}</span>` : ""}</td>
            <td>${uptime(c.up)}</td><td>${c.heap ? Math.round(c.heap / 1024) + "K" : ""}</td>
            <td>${c.dsent != null ? `${c.dacked}/${c.dsent}` : ""}</td>
            <td class="ota-cell">${otaLive(n) ? `<span class="fw-bar mini"><i style="width:${otaLive(n).pct || 0}%"></i></span> ${otaLive(n).pct || 0}%` : esc(otaText(n) || "-")}</td><td>${ago(n.cfg_ts)}</td></tr>`;
    }).join("");
    $("fBody").querySelectorAll("tr[data-id]").forEach((tr) => tr.onclick = () => selectNode(tr.dataset.id, true));
    const ch = $("fChan");
    if (!ch.options.length) {
        ch.innerHTML = Array.from({ length: 11 }, (_, i) => `<option value="${i + 1}">Channel ${i + 1}</option>`).join("");
    }
    if (document.activeElement !== ch && S.fleet.home && S.fleet.home.ch) ch.value = S.fleet.home.ch;
}
$("fStatus").onclick = () => { command("all", "status"); const h = homeNode(); if (h) command(h.id, "status"); };
$("fFilters").onclick = () => { command("all", "filters_get"); const h = homeNode(); if (h) command(h.id, "filters_get"); };
$("fIdent").onclick = () => command("all", "identify", { secs: 10 });
$("fAudio").onclick = () => command("all", "audio", { buzzer: $("fBuzzer").checked, led: $("fLed").checked });
$("fPush").onclick = () => twoTap($("fPush"), () => command("all", "meshpush"));
$("fPresetGo").onclick = () => {
    const g = allGroups().find((x) => x.key === $("fPreset").value);
    if (!g) return;
    twoTap($("fPresetGo"), async () => {
        const rows = { filters: groupRows(g) };
        await command("all", "filters_add", rows);
        const h = homeNode();
        if (h) await command(h.id, "filters_add", rows);
    });
};
$("fRechan").onclick = () => twoTap($("fRechan"), () => command("all", "rechan", { ch: Number($("fChan").value) }));
$("fReboot").onclick = () => twoTap($("fReboot"), () => command("all", "reboot"));

// ------------------------------------------------------------------
// devices (one row per MAC) + device drawer
// ------------------------------------------------------------------
async function loadDevices() {
    const p = new URLSearchParams();
    if ($("vQ").value.trim()) p.set("q", $("vQ").value.trim());
    if ($("vNode").value) p.set("node", $("vNode").value);
    if ($("vDom").value) p.set("dom", $("vDom").value);
    const r = await api(`/api/devices?${p}`);
    $("vTotal").textContent = `${r.total} device${r.total === 1 ? "" : "s"}${r.total > r.rows.length ? ` (showing ${r.rows.length})` : ""}`;
    $("vBody").innerHTML = r.rows.map((d) => {
        const al = devAlias(d.mac);
        const nm = devName(d.mac, d.name);
        return `<tr data-mac="${esc(d.mac)}"><td class="v">${al ? `<span class="mal">${esc(al)}</span> ` : ""}${nm ? `<span class="dname">"${esc(nm)}"</span> ` : ""}${groupTag(d.mac)}${esc(d.descr || "")}</td>
            <td>${esc(d.mac)}</td><td>${d.dom === "wifi" ? "WiFi" : "BLE"} ${esc(d.type || "")}</td><td>${d.hits}</td>
            <td>${fullTime(d.first)}</td><td>${ago(d.last)}</td><td>${d.best ?? ""}</td>
            <td class="nodes">${d.nodes.map((n) => esc(nodeName(n))).join(", ")}</td></tr>`;
    }).join("") || `<tr><td colspan="8" style="text-align:center;padding:20px">No devices</td></tr>`;
    $("vBody").querySelectorAll("tr[data-mac]").forEach((tr) => tr.onclick = () => openDevice(tr.dataset.mac));
}
let devTimer = null;
$("vQ").addEventListener("input", () => { clearTimeout(devTimer); devTimer = setTimeout(loadDevices, 250); });
["vNode", "vDom"].forEach((id) => $(id).addEventListener("change", loadDevices));

async function openDevice(mac) {
    if (!mac) return;
    S.device = mac;
    closeDrawer();
    $("vDrawer").classList.add("open");
    $("vTrail").value = String(devTrailFor(mac));
    showCal(mac);
    const r = await api(`/api/detections?mac=${encodeURIComponent(mac)}&limit=200`);
    const rows = r.rows;
    const a = S.macAliases[mac] || {};
    const vendor = rows.length ? (rows[0].descr || rows[0].match || "") : "";
    $("vTitle").textContent = a.alias || vendor || mac;
    $("vSub").textContent = `${mac}${vendor ? " | " + vendor : ""}`;
    if (document.activeElement !== $("vAlias")) $("vAlias").value = a.alias || "";
    if (document.activeElement !== $("vNotes")) $("vNotes").value = a.notes || "";
    const rssis = rows.map((x) => x.rssi).filter((x) => x != null);
    const first = rows.length ? rows[rows.length - 1].ts : null;
    const cells = [
        ["Hits", r.total, r.total ? "bad" : ""],
        ["First seen", first ? ago(first) : "-"],
        ["Last seen", rows.length ? ago(rows[0].ts) : "-"],
        ["Best RSSI", rssis.length ? `${Math.max(...rssis)} dBm` : "-"],
        ["Avg RSSI", rssis.length ? `${Math.round(rssis.reduce((x, y) => x + y, 0) / rssis.length)} dBm` : "-"],
        ["Domain", rows.length ? (rows[0].dom === "wifi" ? "WiFi" : "BLE") : "-"],
    ];
    $("vStats").innerHTML = cells.map(([k, v, c]) =>
        `<div class="hs"><div class="k">${k}</div><div class="v ${c || ""}">${esc(v)}</div></div>`).join("");
    const byNode = {};
    rows.forEach((x) => { byNode[x.node] = (byNode[x.node] || 0) + 1; });
    $("vSeenBy").innerHTML = Object.entries(byNode).sort((x, y) => y[1] - x[1])
        .map(([n, c]) => `<span data-node="${esc(n)}">${esc(nodeName(n))}<b>${c}</b></span>`).join("") || "-";
    $("vSeenBy").querySelectorAll("span[data-node]").forEach((el) => el.onclick = () => {
        $("vDrawer").classList.remove("open");
        selectNode(el.dataset.node, true);
    });
    $("vDets").innerHTML = rows.slice(0, 60).map((d) => detHtml(d)).join("") || `<div class="empty">No sightings.</div>`;
    renderGroupSelect(mac);
    let info;
    try { info = await api(`/api/devices/${encodeURIComponent(mac)}?limit=1`); } catch (e) { return; }
    if (S.device !== mac) return;
    if (info.name) {
        S.deviceNames[mac] = info.name;
        if (!a.alias) $("vTitle").textContent = info.name;
    }
    $("vSub").textContent = [mac, info.name && a.alias ? `"${info.name}"` : "", vendor, info.oui_vendor && info.oui_vendor !== vendor ? info.oui_vendor : ""]
        .filter(Boolean).join(" | ");
    $("vIntel").innerHTML = intelHtml(info);
    $("vComp").innerHTML = compHtml(info.companions || []);
    $("vComp").querySelectorAll("[data-open]").forEach((el) => el.onclick = () => openDevice(el.dataset.open));
    $("vComp").querySelectorAll("[data-join]").forEach((el) => el.onclick = (e) => { e.stopPropagation(); joinGroup(mac, el.dataset.join); });
}

// What the device said over the air, merged across every report the nodes sent.
function intelHtml(info) {
    const it = info.intel || {};
    const kind = info.mac_kind || {};
    const rows = [];
    const row = (k, v, cls) => { if (v !== undefined && v !== null && v !== "") rows.push(`<div class="ik">${k}</div><div class="iv ${cls || ""}">${v}</div>`); };
    const keys = (o) => Object.keys(o || {}).sort((x, y) => (o[y].last || 0) - (o[x].last || 0));
    row("Broadcast name", it.name ? `"${esc(it.name)}"` : "", "hl");
    const names = keys(it.names).filter((n) => n !== it.name);
    row("Earlier names", names.map((n) => `"${esc(n)}"`).join(", "));
    row("MAC vendor (IEEE)", esc(info.oui_vendor || (kind.local ? "none: locally administered (randomized) address" : "not registered")));
    if (it.rnd !== undefined) row("Address", it.rnd ? `random${kind.ble_random_kind ? ` (${esc(kind.ble_random_kind)})` : ""}` : "public");
    else if (kind.local) row("Address", "locally administered (randomized)");
    if (it.conn !== undefined) row("Connectable", it.conn ? "yes" : "no");
    if (it.cid) row("Company ID", `0x${esc(it.cid)}${it.cid_name ? ` <span class="sub">${esc(it.cid_name)}</span>` : ""}`);
    const cids = Object.keys(it.cids_named || {}).filter((c) => c !== it.cid);
    if (cids.length) row("Other company IDs", cids.map((c) => `0x${esc(c)} ${esc(it.cids_named[c] || "")}`).join(", "));
    if (it.mfr) row("Manufacturer data", `<code>${esc(it.mfr)}</code>`);
    if (it.uuids_named) row("Service UUIDs", it.uuids_named.map((u) => `<span class="chip">0x${esc(u.uuid)}${u.name ? ` ${esc(u.name)}` : ""}</span>`).join(""));
    if (it.uuid128) row("128-bit service", `<code>${esc(it.uuid128.replace(/^(.{8})(.{4})(.{4})(.{4})/, "$1-$2-$3-$4-"))}</code>`);
    if (it.sdata_named) row("Service data", it.sdata_named.map((u) => `<div>0x${esc(u.uuid)}${u.name ? ` ${esc(u.name)}` : ""}: <code>${esc(u.data || "(empty)")}</code></div>`).join(""));
    if (it.app !== undefined) row("Appearance", `${esc(it.app_name || "unknown")} <span class="sub">(${it.app})</span>`);
    if (it.tx !== undefined) row("TX power", `${it.tx} dBm`);
    if (it.adv !== undefined) row("Advert type", ["ADV_IND (connectable)", "ADV_DIRECT_IND", "ADV_SCAN_IND", "ADV_NONCONN_IND", "SCAN_RSP"][it.adv] || it.adv);
    // WiFi
    if (it.frame) row("Frames heard", esc(it.frame));
    const ssids = keys(it.ssids);
    if (ssids.length) {
        const ap = it.frame === "beacon" || it.frame === "probe-resp";
        row(ap ? "Network (SSID)" : "Networks it looks for",
            ssids.map((s) => `<span class="chip ssid" title="${it.ssids[s].n}x, last ${esc(ago(it.ssids[s].last))}">${s ? esc(s) : "<i>hidden</i>"}</span>`).join(""), "hl");
    }
    const aps = keys(it.aps);
    if (aps.length) row("Joins (BSSID)", aps.map((b) => `<div><code>${esc(b)}</code>${it.aps[b].ssid ? ` "${esc(it.aps[b].ssid)}"` : ""} <span class="sub">${it.aps[b].n}x</span></div>`).join(""));
    if (it.hidden) row("Hidden SSID", "yes");
    if (it.sec) row("Security", esc(it.sec), it.sec === "open" || it.sec === "WEP" ? "bad" : "");
    if (it.ch) row("Channel", it.ch);
    if (it.phy) row("Wi-Fi standard", `802.11${esc(it.phy)}${it.rate ? ` <span class="sub">(legacy rates to ${it.rate} Mb/s)</span>` : ""}`);
    if (it.wps) row("WPS", "on", "bad");
    if (it.cc) row("Country", esc(it.cc));
    if (it.vie_named) row("Vendor IEs", it.vie_named.map((v) => `<span class="chip">${esc(v.oui)}${v.name ? ` ${esc(v.name)}` : ""}</span>`).join(""));
    const hb = it.heard_by || {};
    const hbk = Object.keys(hb).sort((x, y) => (hb[y].best ?? -200) - (hb[x].best ?? -200));
    if (hbk.length) row("Heard by", hbk.map((n) => `<span class="chip">${esc(nodeName(n))} ${hb[n].n}x${hb[n].best !== undefined ? `, best ${hb[n].best} dBm` : ""}</span>`).join(""));
    if (info.intel_reports) row("Intel reports", `${info.intel_reports} <span class="sub">since ${esc(fullTime(info.intel_first))}</span>`);
    if (!rows.length) return `<h4>Over the air</h4><div class="empty">Nothing beyond the MAC yet. Nodes on firmware with device intel report names, services and networks with each detection.</div>`;
    return `<h4>Over the air</h4><div class="igrid">${rows.join("")}</div>`;
}

function compHtml(list) {
    if (!list.length) return `<div class="empty">No other device has turned up with it yet.</div>`;
    const g = devGroup(S.device);
    return list.map((c) => {
        const label = c.alias || c.name || c.descr || c.vendor || c.mac;
        const pct = Math.round((c.score || 0) * 100);
        const inMine = g && c.group && c.group.id === g.id;
        return `<div class="comp" data-open="${esc(c.mac)}">
            <div class="cm"><b>${esc(label)}</b>${c.name && label !== c.name ? ` <span class="dname">"${esc(c.name)}"</span>` : ""}
                ${c.group ? `<span class="gtag" style="--gh:${c.group.color ?? 280}">${esc(c.group.name)}</span>` : ""}
                <div class="sub">${esc(c.mac)} | ${c.dom === "wifi" ? "WiFi" : "BLE"} | together ${c.together} of ${c.occasions}x | last ${esc(ago(c.last))}</div></div>
            <div class="cbar"><i style="width:${Math.max(4, pct)}%"></i></div>
            ${inMine ? `<span class="sub">in group</span>` : `<button class="btn ghost" data-join="${esc(c.mac)}" title="Put both in ${g ? esc(g.name) : "a new group"}">Group</button>`}
        </div>`;
    }).join("");
}

function renderGroupSelect(mac) {
    const g = devGroup(mac);
    $("vGroup").innerHTML = `<option value="">No group</option>` +
        S.groups.map((x) => `<option value="${x.id}" ${g && g.id === x.id ? "selected" : ""}>${esc(x.name)} (${x.members.length})</option>`).join("");
}
async function saveGroup(body) {
    const r = await api("/api/groups", { method: "POST", body });
    S.groups = r.groups; S.groupOf = r.group_of;
    renderFeed();
    if ($("tab-devices").classList.contains("active")) loadDevices();
    return r;
}
async function newGroupFor(macs) {
    const al = devAlias(macs[0]) || devName(macs[0]) || "";
    const name = (prompt("Group name (an alias for all of these devices)", al ? `${al} group` : "") || "").trim();
    if (!name) return null;
    const hue = Math.floor(Math.random() * 360);
    return saveGroup({ name, color: hue, add: macs });
}
async function joinGroup(mac, other) {
    const g = devGroup(mac) || devGroup(other);
    if (g) await saveGroup({ id: g.id, add: [mac, other] });
    else await newGroupFor([mac, other]);
    openDevice(mac);
}
$("vGroup").onchange = async () => {
    const v = $("vGroup").value;
    const g = devGroup(S.device);
    if (v) await saveGroup({ id: Number(v), add: [S.device] });
    else if (g) await saveGroup({ id: g.id, remove: [S.device] });
    openDevice(S.device);
};
$("vGroupNew").onclick = async () => { if (await newGroupFor([S.device])) openDevice(S.device); };
function closeDevice() { $("vDrawer").classList.remove("open"); S.device = null; }
$("vClose").onclick = closeDevice;
$("vSave").onclick = async () => {
    const r = await api(`/api/devices/${encodeURIComponent(S.device)}`, {
        method: "POST", body: { alias: $("vAlias").value, notes: $("vNotes").value } });
    S.macAliases = r.mac_aliases;
    $("vTitle").textContent = $("vAlias").value || S.device;
    renderFeed();
    if ($("tab-devices").classList.contains("active")) loadDevices();
    if ($("tab-history").classList.contains("active")) loadHistory(false);
};
$("vTrail").onchange = () => {
    S.devTrail[S.device] = Number($("vTrail").value);
    lsSet("ouispy.devTrail", S.devTrail);
    renderTargets();
};
$("vAlias").addEventListener("keydown", (e) => { if (e.key === "Enter") $("vSave").click(); });
$("vHistory").onclick = () => {
    $("hQ").value = S.device;
    closeDevice();
    showTab("history");
    loadHistory(false);
};

// ------------------------------------------------------------------
// console
// ------------------------------------------------------------------
// Console colours follow the line's kind (the UI palette, not white), with
// the timestamp and JSON keys dimmed so the values read first.
const CON_KINDS = [["TLM ", "tlm"], ["RST ", "rst"], ["RFL ", "rfl"], ["CMD ", "cmd"], ["ACK ", "ok"], ["OK", "ok"],
                   ["ERR", "err"], ["OTA ", "ota"], ["[MESH]", "mesh"], ["[HEARTBEAT]", "hb"], ["[OTA]", "ota"], ["DET ", "djs"]];
function consoleLine(ts, source, line) {
    let cls = (CON_KINDS.find(([p]) => line.startsWith(p)) || [, ""])[1];
    if (!cls && line.startsWith("{")) cls = line.includes('"upd":1') ? "upd" : "djs";
    if (source === "you") cls = "you";
    const body = esc(line).replace(/(&quot;|")([A-Za-z_][\w]*)(&quot;|"):/g, '<i>$1$2$3:</i>');
    return `<span class="${cls}"><b class="cts">${hms(ts)}</b> ${body}</span>\n`;
}
function appendConsole(ts, source, line) {
    const c = $("console");
    const stick = c.scrollTop + c.clientHeight >= c.scrollHeight - 30;
    c.insertAdjacentHTML("beforeend", consoleLine(ts, source, line));
    while (c.childElementCount > 400) c.firstElementChild.remove();
    if (stick) c.scrollTop = c.scrollHeight;
}
$("consoleForm").onsubmit = async (e) => {
    e.preventDefault();
    const line = $("consoleLine").value.trim();
    if (!line) return;
    const r = await api("/api/console", { method: "POST", body: { line } });
    if (!r.ok) appendConsole(now(), "you", `! ${r.error}`);
    else $("consoleLine").value = "";
};

// ------------------------------------------------------------------
// settings
// ------------------------------------------------------------------
async function loadSettingsForm() {
    const s = S.settings;
    const ports = await api("/api/ports");
    const cur = s.serial_port || "auto";
    const opts = [["auto", "Auto-detect (Espressif VID 0x303A)"], ["off", "Off"]]
        .concat(ports.map((p) => [p.device, `${p.device}${p.espressif ? "  [ESP32]" : ""} ${p.desc}`]));
    if (!opts.some(([v]) => v === cur)) opts.push([cur, cur]);
    $("sPort").innerHTML = opts.map(([v, t]) => `<option value="${esc(v)}">${esc(t)}</option>`).join("");
    $("sPort").value = cur;
    const m = s.mqtt || {};
    $("mEn").checked = !!m.enabled;
    $("mHost").value = m.host || "";
    $("mPort").value = m.port || 1883;
    $("mUser").value = m.user || "";
    $("mPass").textContent = m.password_set ? "Set (OUISPY_MQTT_PASSWORD)." : "Set OUISPY_MQTT_PASSWORD before starting the dashboard.";
    $("mTopic").value = m.topic || "+/detection";
    const tk = s.tak || {};
    $("tEn").checked = !!tk.enabled;
    $("tHost").value = tk.host || "";
    $("tPort").value = tk.port || 8087;
    $("tProto").value = tk.proto || "tcp";
    $("tCall").value = tk.callsign || "OUISPY";
    $("tCa").value = tk.ca_file || "";
    $("tCert").value = tk.cert_file || "";
    $("tKey").value = tk.key_file || "";
    $("tStatus").textContent = tk.enabled ? `${tk.state || "off"}, ${tk.sent || 0} sent${tk.error ? ": " + tk.error : ""}` : "Off.";
    const rn = s.rns || {}, rs = rn.send || {};
    $("rEn").checked = !!rn.enabled;
    $("rRecips").value = (rn.recipients || []).join("\n");
    $("rNew").checked = rs.new_devices !== false;
    $("rDrone").checked = rs.drones !== false;
    $("rLost").checked = rs.lost_nodes !== false;
    $("rStatus").textContent = rn.enabled ? `${rn.state || "off"}${rn.address ? ", address " + rn.address : ""}${rn.error ? ": " + rn.error : ""}` : "Needs pip install rns lxmf.";
    $("sTiles").value = s.tiles || "osm-dark";
    $("sNotify").checked = !!s.notify;
    $("sLinks").checked = linkMode() !== "off";
    $("sRetention").value = s.retention_days || 0;
    $("sPoll").value = s.status_poll ?? 120;
    $("sTilesCustom").value = s.tiles_custom || "";
    $("sTilesCustom").style.display = $("sTiles").value.startsWith("custom") ? "" : "none";
}
$("sNotify").onchange = async () => {
    if ($("sNotify").checked && "Notification" in window && Notification.permission !== "granted") {
        const p = await Notification.requestPermission();
        if (p !== "granted") {
            $("sNotify").checked = false;
            $("savedMsg").textContent = "The browser blocked notifications for this page.";
        }
    }
};
$("sTiles").onchange = () => { $("sTilesCustom").style.display = $("sTiles").value.startsWith("custom") ? "" : "none"; };
$("saveSettings").onclick = async () => {
    const body = {
        tiles: $("sTiles").value, tiles_custom: $("sTilesCustom").value.trim(),
        serial_port: $("sPort").value,
        notify: $("sNotify").checked, links: $("sLinks").checked ? (linkMode() === "off" ? "home" : linkMode()) : "off",
        retention_days: Math.max(0, parseInt($("sRetention").value, 10) || 0),
        status_poll: Math.max(0, parseInt($("sPoll").value, 10) || 0),
        mqtt: { enabled: $("mEn").checked, host: $("mHost").value.trim(), port: Number($("mPort").value) || 1883,
                user: $("mUser").value, topic: $("mTopic").value.trim() || "+/detection" },
        tak: { enabled: $("tEn").checked, host: $("tHost").value.trim(), port: Number($("tPort").value) || 8087,
               proto: $("tProto").value, callsign: $("tCall").value.trim() || "OUISPY",
               ca_file: $("tCa").value.trim(), cert_file: $("tCert").value.trim(), key_file: $("tKey").value.trim() },
        rns: { enabled: $("rEn").checked, recipients: $("rRecips").value.split(/\s+/).filter(Boolean),
               send: { new_devices: $("rNew").checked, drones: $("rDrone").checked, lost_nodes: $("rLost").checked } },
    };
    const res = await api("/api/settings", { method: "POST", body });
    if (res.ok === false) { toast("bad", "Settings not saved", res.error); return; }
    S.settings = res;
    applyTiles();
    renderLinks();
    $("savedMsg").textContent = window.OUISPY_MODE === "live" ? "Saved. Feeds restarted." : "Saved (feeds are fixed in demo/replay mode).";
    setTimeout(() => $("savedMsg").textContent = "", 3000);
};
let clearArmed = false;
$("clearBtn").onclick = async () => {
    if (!clearArmed) {
        clearArmed = true;
        $("clearBtn").textContent = "Tap again to delete all";
        setTimeout(() => { clearArmed = false; $("clearBtn").textContent = "Clear detection history"; }, 3000);
        return;
    }
    clearArmed = false;
    $("clearBtn").textContent = "Clear detection history";
    await api("/api/detections/clear", { method: "POST" });
    S.dets = [];
    await afterDetsCleared();
};

// Clear one node's detections (drawer). The server tells every open
// dashboard (dets_cleared) so their feeds drop them too.
async function afterDetsCleared() {
    S.statsBase = await api("/api/stats");
    S.hourly = S.statsBase.hourly || [];
    renderFeed(); renderKpis(); renderNodes(); loadHistory(false);
    if (S.selected && $("drawer").classList.contains("open")) openDrawer(S.selected);
    if (S.device && $("vDrawer").classList.contains("open")) openDevice(S.device);
    if (typeof loadDevices === "function") loadDevices();
}
$("vClearDets").onclick = () => twoTap($("vClearDets"), async () => {
    const mac = S.device;
    const r = await api("/api/detections/clear", { method: "POST", body: { mac } });
    if (r.ok) toast("good", `Cleared ${r.n} detection${r.n === 1 ? "" : "s"}`, (S.macAliases[mac] || {}).alias || mac);
});
$("dClearDets").onclick = () => twoTap($("dClearDets"), async () => {
    const id = S.selected;
    const r = await api("/api/detections/clear", { method: "POST", body: { node: id } });
    if (r.ok) toast("good", `Cleared ${r.n} detection${r.n === 1 ? "" : "s"}`, nodeName(id));
});

// ------------------------------------------------------------------
// fleet key as QR (this computer + the key_nets networks only; server enforces it)
// ------------------------------------------------------------------
// Per-node key state: compares the fingerprint each node reports with the
// fingerprint of the key on this computer (neither reveals the key).
function keyState(n) {
    const c = n && n.cfg;
    if (!c) return { txt: "-", cls: "" };
    if (!c.key) return { txt: "NO KEY", cls: "bad" };
    if (!c.kfp) return { txt: "SET", cls: "warn", tip: "firmware too old to verify the key matches" };
    if (!S.keyFp) return { txt: "SET", cls: "warn", tip: "no key on this computer to compare" };
    return c.kfp === S.keyFp ? { txt: "KEY OK", cls: "good" } : { txt: "DIFFERS", cls: "bad", tip: "this node holds a different key: it can't talk to the fleet" };
}
async function loadFleetKeyStatus() {
    S.keyFp = null;
    renderFleetCtl();
    renderRemote();
}
let fkTimer = null;
function hideFleetKey() {
    $("fkModal").classList.remove("open");
    $("fkQr").innerHTML = "";
    $("fkText").value = "";
    $("fkCopied").textContent = "";
    clearTimeout(fkTimer);
}
$("fkShow").onclick = () => twoTap($("fkShow"), async () => {
    const r = await fetch("/api/fleetkey/reveal", { method: "POST", cache: "no-store" });
    const d = await r.json();
    if (!d.ok) { toast("bad", "Fleet key", d.error); return; }
    const q = qrcode(0, "M");
    q.addData(d.key);
    q.make();
    $("fkQr").innerHTML = q.createSvgTag({ cellSize: 6, margin: 3, scalable: true });
    $("fkText").value = d.key.match(/.{1,4}/g).join(" ");   // grouped for reading; Copy and QR use it raw
    $("fkText").dataset.raw = d.key;
    $("fkSub").textContent = `Fingerprint ${d.fp.slice(0, 4)}-${d.fp.slice(4)}. Hides itself in 60 s`;
    $("fkModal").classList.add("open");
    clearTimeout(fkTimer);
    fkTimer = setTimeout(hideFleetKey, 60000);
});
$("fkClose").onclick = hideFleetKey;
$("fkModal").onclick = (e) => { if (e.target === $("fkModal")) hideFleetKey(); };
document.addEventListener("visibilitychange", () => { if (document.hidden) hideFleetKey(); });
$("fkCopy").onclick = async () => {
    const raw = $("fkText").dataset.raw || "";
    try {
        await navigator.clipboard.writeText(raw);       // needs a secure context
    } catch (e) {
        const t = document.createElement("textarea");   // plain-http fallback
        t.value = raw; document.body.appendChild(t); t.select();
        document.execCommand("copy"); t.remove();
    }
    $("fkCopied").textContent = "Copied (no spaces)";
};
$("fkCreate").onclick = () => twoTap($("fkCreate"), async () => {
    const r = await api("/api/fleetkey/create", { method: "POST" });
    if (!r.ok) { toast("bad", "Fleet key", r.error); return; }
    toast("good", "Fleet key created", `Fingerprint ${r.fp.slice(0, 4)}-${r.fp.slice(4)}. Now set it on every node.`);
    loadFleetKeyStatus();
});
$("fkHome").onclick = () => twoTap($("fkHome"), async () => {
    const r = await api("/api/fleetkey/provision_home", { method: "POST" });
    if (!r.ok) { toast("bad", "Fleet key", r.error); return; }
    onJob(r.job);
});

// tabs
// ------------------------------------------------------------------
// Console layout: collapsible sections and the bottom dock. On desktop the
// page is one screen (no page scroll); every column scrolls inside itself.
// What is collapsed, and the dock height, are remembered per browser.
// ------------------------------------------------------------------
const secState = lsGet("ouispy.collapsed", {});
document.querySelectorAll(".sec").forEach((sec) => {
    const key = sec.dataset.sec;
    sec.classList.toggle("collapsed", !!secState[key]);
    sec.querySelector(".sec-head").onclick = () => {
        sec.classList.toggle("collapsed");
        secState[key] = sec.classList.contains("collapsed");
        lsSet("ouispy.collapsed", secState);
    };
});
const dock = document.querySelector(".tabs-panel");
function setDock(open) {
    dock.classList.toggle("collapsed", !open);
    $("dockToggle").title = open ? "Collapse this panel" : "Expand this panel";
    lsSet("ouispy.dockOpen", open);
    setTimeout(() => map.invalidateSize(), 220);   // the map row grew or shrank
}
function setDockHeight(px) {
    // Leave the fleet / map / detections row at least ~300 px under the top bar.
    const h = Math.round(Math.max(160, Math.min(window.innerHeight - 380, px)));
    document.documentElement.style.setProperty("--dock-h", h + "px");
    return h;
}
setDockHeight(lsGet("ouispy.dockH", Math.round(window.innerHeight * 0.42)));
setDock(lsGet("ouispy.dockOpen", true));
$("dockToggle").onclick = () => setDock(dock.classList.contains("collapsed"));
$("dockGrip").onpointerdown = (e) => {
    if (dock.classList.contains("collapsed")) setDock(true);
    e.preventDefault();
    const grip = e.currentTarget;
    grip.setPointerCapture(e.pointerId);
    grip.onpointermove = (m) => setDockHeight(window.innerHeight - m.clientY - 12);
    grip.onpointerup = (u) => {
        grip.onpointermove = grip.onpointerup = null;
        lsSet("ouispy.dockH", setDockHeight(window.innerHeight - u.clientY - 12));
        map.invalidateSize();
    };
};
// Open a dock tab from code (never folds it, unlike pressing the open tab).
function showTab(name) {
    const t = document.querySelector(`.tab[data-tab="${name}"]`);
    if (dock.classList.contains("collapsed") || !t.classList.contains("active")) t.click();
}
document.querySelectorAll(".tab").forEach((t) => t.onclick = () => {
    // The active tab's own button folds the dock; any tab unfolds it.
    if (t.classList.contains("active") && !dock.classList.contains("collapsed")) return setDock(false);
    if (dock.classList.contains("collapsed")) setDock(true);
    document.querySelectorAll(".tab").forEach((x) => x.classList.toggle("active", x === t));
    document.querySelectorAll(".tab-body").forEach((b) => b.classList.toggle("active", b.id === `tab-${t.dataset.tab}`));
    if (t.dataset.tab === "settings") { loadSettingsForm(); loadFleetKeyStatus(); }
    if (t.dataset.tab === "devices") loadDevices();
    if (t.dataset.tab === "console") $("console").scrollTop = $("console").scrollHeight;
});

// ------------------------------------------------------------------
// boot + live updates
// ------------------------------------------------------------------
// Live fleet updates leave out the filter lists (they come in node_filters,
// only when a list changes); keep each node's list from before.
const FILTER_KEYS = ["filters", "filters_ok", "filters_ts", "filters_via"];
function applyFleet(f) {
    const prev = {};
    if (S.fleet) S.fleet.nodes.forEach((n) => { prev[n.id] = n; });
    f.nodes.forEach((n) => {
        if (!("filters" in n) && prev[n.id]) FILTER_KEYS.forEach((k) => { n[k] = prev[n.id][k]; });
    });
    S.fleet = f;
    S.skew = Date.now() / 1000 - f.ts;
    renderHome();
    renderNodes();
    renderMap();
    watchHealth();
    renderRemote();
    renderFleetCtl();
    if (S.editAfterRead) {
        const en = nodeById(S.editAfterRead);
        if (en && en.filters) {
            const id = S.editAfterRead;
            S.editAfterRead = null;
            if (S.selected === id && $("drawer").classList.contains("open")) {
                $("dFiltEdit").click();
            }
        }
    }
    const h = homeNode();
    if (S.loadHomePending && h && h.filters && S.editing) {
        S.loadHomePending = false;
        S.editing = h.filters.map((f) => ({ t: f.t, id: f.id, d: f.d }));
        rerenderEditor();
    }
}

// ------------------------------------------------------------------
// Metrics tab: detections over time, devices, vendors, nodes, signature
// types, weekday x hour activity and signal strength, for a chosen range,
// node and radio. Plain SVG (no chart library: the dashboard stays
// local-first). Colours: a categorical palette validated for this dark
// surface (CVD-safe adjacent pairs), assigned to vendors in rank order and
// kept per vendor; "Other" is neutral grey; magnitude is one blue ramp.
// ------------------------------------------------------------------
const MX_COLORS = ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#008300", "#9085e9", "#e66767"];
const MX_OTHER = "#5d6878";
const MX_HEAT = ["#10233a", "#104281", "#1c5cab", "#2a78d6", "#5598e7", "#86b6ef", "#cde2fb"];
S.mx = { range: lsGet("ouispy.mxRange", 86400), node: "", dom: "", data: null, colors: {} };
function mxColor(name, i) {
    if (name === "Other") return MX_OTHER;
    if (!S.mx.colors[name]) S.mx.colors[name] = MX_COLORS[Object.keys(S.mx.colors).length % MX_COLORS.length];
    return S.mx.colors[name];
}
function niceMax(v) {
    if (v <= 4) return 4;
    const p = Math.pow(10, Math.floor(Math.log10(v))), m = v / p;
    return (m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10) * p;
}
const mxFmt = (n) => n >= 10000 ? (n / 1000).toFixed(n >= 100000 ? 0 : 1) + "k" : String(n);
function mxTimeLabel(ts, bucket) {
    const d = new Date(ts * 1000);
    if (bucket < 86400 && S.mx.range <= 86400) return d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", hour12: false });
    return d.toLocaleDateString([], { weekday: "short", day: "numeric" });
}
function mxTip(html, ev) {
    const t = $("mxTip");
    if (!html) { t.hidden = true; return; }
    t.innerHTML = html;
    t.hidden = false;
    const r = t.getBoundingClientRect();
    let x = ev.clientX + 14, y = ev.clientY + 14;
    if (x + r.width > innerWidth - 8) x = ev.clientX - r.width - 14;
    if (y + r.height > innerHeight - 8) y = ev.clientY - r.height - 14;
    t.style.left = x + "px"; t.style.top = y + "px";
}
// Time series: stacked areas (several series) or one line, shared axes,
// crosshair + tooltip on hover.
function mxTimeChart(el, d, series, opts = {}) {
    const W = Math.max(280, el.clientWidth), H = opts.h || 190, L = 40, R = 10, Tp = 10, B = 24;
    const n = d.n, iw = W - L - R, ih = H - Tp - B;
    const stacked = series.length > 1;
    const tot = Array.from({ length: n }, (_, i) => series.reduce((a, s) => a + s.values[i], 0));
    const ymax = niceMax(Math.max(1, ...(stacked ? tot : series[0].values)));
    const x = (i) => L + (n <= 1 ? iw / 2 : (i / (n - 1)) * iw), y = (v) => Tp + ih - (v / ymax) * ih;
    let g = "";
    for (let k = 0; k <= 4; k++) {
        const v = (ymax / 4) * k, yy = y(v);
        g += `<line x1="${L}" x2="${W - R}" y1="${yy}" y2="${yy}" class="mx-grid-l"/><text x="${L - 6}" y="${yy + 3}" class="mx-ax" text-anchor="end">${mxFmt(Math.round(v * 10) / 10)}</text>`;
    }
    const ticks = Math.min(6, n);
    for (let k = 0; k < ticks; k++) {
        const i = Math.round((k / Math.max(1, ticks - 1)) * (n - 1));
        g += `<text x="${x(i)}" y="${H - 6}" class="mx-ax" text-anchor="${k === 0 ? "start" : k === ticks - 1 ? "end" : "middle"}">${mxTimeLabel(d.start + i * d.bucket, d.bucket)}</text>`;
    }
    let marks = "";
    if (stacked) {
        const base = new Array(n).fill(0);
        series.forEach((s) => {
            const top = s.values.map((v, i) => base[i] + v);
            const pts = top.map((v, i) => `${x(i)},${y(v)}`).join(" ");
            const back = base.map((v, i) => `${x(i)},${y(v)}`).reverse().join(" ");
            marks += `<polygon points="${pts} ${back}" fill="${s.color}" fill-opacity="0.55"/><polyline points="${pts}" fill="none" stroke="${s.color}" stroke-width="1.5"/>`;
            top.forEach((v, i) => { base[i] = v; });
        });
    } else {
        const s = series[0], pts = s.values.map((v, i) => `${x(i)},${y(v)}`).join(" ");
        marks = `<polygon points="${x(0)},${y(0)} ${pts} ${x(n - 1)},${y(0)}" fill="${s.color}" fill-opacity="0.14"/><polyline points="${pts}" fill="none" stroke="${s.color}" stroke-width="2" stroke-linejoin="round"/>`;
    }
    el.innerHTML = `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${g}${marks}<line class="mx-cross" x1="0" x2="0" y1="${Tp}" y2="${Tp + ih}" visibility="hidden"/><rect x="${L}" y="${Tp}" width="${iw}" height="${ih}" fill="transparent" class="mx-hit"/></svg>`;
    const svg = el.querySelector("svg"), cross = svg.querySelector(".mx-cross");
    svg.querySelector(".mx-hit").onmousemove = (ev) => {
        const r = svg.getBoundingClientRect();
        const i = Math.max(0, Math.min(n - 1, Math.round(((ev.clientX - r.left - L) / iw) * (n - 1))));
        cross.setAttribute("x1", x(i)); cross.setAttribute("x2", x(i)); cross.setAttribute("visibility", "visible");
        const when = new Date((d.start + i * d.bucket) * 1000).toLocaleString([], { weekday: "short", hour: "2-digit", minute: "2-digit", hour12: false });
        const rows = series.filter((s) => s.values[i] || !stacked).map((s) =>
            `<div class="mx-tr"><i style="background:${s.color}"></i><span>${esc(s.name)}</span><b>${s.values[i]}</b></div>`).join("");
        mxTip(`<div class="mx-th">${when}</div>${rows || `<div class="mx-tr"><span>none</span></div>`}${stacked ? `<div class="mx-tr mx-tt"><span>Total</span><b>${tot[i]}</b></div>` : ""}`, ev);
    };
    svg.querySelector(".mx-hit").onmouseleave = () => { cross.setAttribute("visibility", "hidden"); mxTip(null); };
}
// Horizontal bars: label, bar from a shared zero, value; tooltip per row.
function mxBars(el, items, opts = {}) {
    if (!items.length) { el.innerHTML = `<div class="mx-empty">No detections in this range.</div>`; return; }
    const max = Math.max(...items.map((x) => x.value));
    el.innerHTML = `<div class="mx-bars">${items.map((it, i) => `
        <div class="mx-row" data-i="${i}"><span class="mx-lbl" title="${esc(it.label)}">${esc(it.label)}</span>
        <span class="mx-track"><span class="mx-fill" style="width:${Math.max(1.5, (it.value / max) * 100)}%;background:${it.color}"></span></span>
        <b class="mx-val">${mxFmt(it.value)}</b></div>`).join("")}</div>`;
    el.querySelectorAll(".mx-row").forEach((r) => {
        const it = items[Number(r.dataset.i)];
        r.onmousemove = (ev) => mxTip(`<div class="mx-th">${esc(it.label)}</div>${it.tip}`, ev);
        r.onmouseleave = () => mxTip(null);
    });
}
function mxHeat(el, heat) {
    const W = Math.max(280, el.clientWidth), L = 34, Tp = 4, B = 18, cw = (W - L - 4) / 24, ch = 18, H = Tp + ch * 7 + B;
    const max = Math.max(1, ...heat.flat());
    const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    let g = "";
    heat.forEach((row, d) => {
        g += `<text x="${L - 6}" y="${Tp + d * ch + ch / 2 + 3}" class="mx-ax" text-anchor="end">${days[d]}</text>`;
        row.forEach((v, h) => {
            const fill = v ? MX_HEAT[Math.min(MX_HEAT.length - 1, Math.ceil((v / max) * (MX_HEAT.length - 1)))] : "rgba(148,163,184,0.06)";
            g += `<rect x="${L + h * cw + 1}" y="${Tp + d * ch + 1}" width="${cw - 2}" height="${ch - 2}" rx="2" fill="${fill}" data-d="${d}" data-h="${h}" data-v="${v}" class="mx-cell"/>`;
        });
    });
    for (let h = 0; h < 24; h += 3) g += `<text x="${L + h * cw + cw / 2}" y="${H - 4}" class="mx-ax" text-anchor="middle">${String(h).padStart(2, "0")}</text>`;
    el.innerHTML = `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${g}</svg>`;
    el.querySelectorAll(".mx-cell").forEach((c) => {
        c.onmousemove = (ev) => mxTip(`<div class="mx-th">${days[c.dataset.d]} ${String(c.dataset.h).padStart(2, "0")}:00-${String((+c.dataset.h + 1) % 24).padStart(2, "0")}:00</div><div class="mx-tr"><span>Detections</span><b>${c.dataset.v}</b></div>`, ev);
        c.onmouseleave = () => mxTip(null);
    });
}
function mxHist(el, r) {
    const W = Math.max(280, el.clientWidth), H = 170, L = 34, R = 6, Tp = 8, B = 22, n = r.counts.length;
    const iw = W - L - R, ih = H - Tp - B, bw = iw / n, ymax = niceMax(Math.max(1, ...r.counts));
    let g = "";
    for (let k = 0; k <= 3; k++) {
        const v = (ymax / 3) * k, yy = Tp + ih - (v / ymax) * ih;
        g += `<line x1="${L}" x2="${W - R}" y1="${yy}" y2="${yy}" class="mx-grid-l"/><text x="${L - 6}" y="${yy + 3}" class="mx-ax" text-anchor="end">${mxFmt(Math.round(v))}</text>`;
    }
    r.counts.forEach((v, i) => {
        const h = (v / ymax) * ih, lo = r.from + i * r.step;
        if (v) g += `<path d="M${L + i * bw + 1},${Tp + ih} v${-(h - 3)} q0,-3 3,-3 h${bw - 8} q3,0 3,3 v${h - 3} z" fill="#3987e5" class="mx-cell" data-lo="${lo}" data-v="${v}"/>`;
        if (i % 4 === 0) g += `<text x="${L + i * bw}" y="${H - 6}" class="mx-ax" text-anchor="middle">${lo}</text>`;
    });
    el.innerHTML = `<svg width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">${g}</svg>`;
    el.querySelectorAll(".mx-cell").forEach((c) => {
        c.onmousemove = (ev) => mxTip(`<div class="mx-th">${c.dataset.lo} to ${+c.dataset.lo + r.step} dBm</div><div class="mx-tr"><span>Detections</span><b>${c.dataset.v}</b></div>`, ev);
        c.onmouseleave = () => mxTip(null);
    });
}
function mxRender() {
    const d = S.mx.data;
    if (!d || !$("tab-metrics").classList.contains("active")) return;
    const delta = d.prev_total ? Math.round(((d.total - d.prev_total) / d.prev_total) * 100) : null;
    const top = d.by_vendor[0];
    const kpi = (k, v, sub, cls = "") => `<div class="mx-kpi"><div class="k">${k}</div><div class="v ${cls}">${v}</div><div class="s">${sub}</div></div>`;
    $("mxKpis").innerHTML =
        kpi("Detections", mxFmt(d.total), delta == null ? "no earlier data" : `${delta >= 0 ? "+" : ""}${delta}% vs previous period`, delta > 0 ? "up" : "") +
        kpi("Unique devices", mxFmt(d.unique), `${d.by_dom.ble} BLE / ${d.by_dom.wifi} WiFi hits`) +
        kpi("New devices", mxFmt(d.new_devices), "first ever seen in range", d.new_devices ? "alert" : "") +
        kpi("Active nodes", d.nodes_active, `of ${S.fleet ? S.fleet.nodes.length : "-"} in the fleet`) +
        kpi("Peak", mxFmt(d.peak.count), d.peak.count ? `per ${d.bucket >= 3600 ? d.bucket / 3600 + " h" : d.bucket / 60 + " min"}, ${mxTimeLabel(d.peak.ts, d.bucket)}` : "no activity") +
        kpi("Top vendor", top ? esc(top.name) : "-", top ? `${top.count} hits, ${top.devices} device${top.devices === 1 ? "" : "s"}` : "", "txt");
    $("mxBucket").textContent = `per ${d.bucket >= 3600 ? d.bucket / 3600 + " h" : d.bucket / 60 + " min"}`;
    const series = d.series.map((s, i) => ({ ...s, color: mxColor(s.name, i) }));
    $("mxLegend").innerHTML = series.map((s) => `<span><i style="background:${s.color}"></i>${esc(s.name)}</span>`).join("");
    if (series.length) mxTimeChart($("mxArea"), d, series);
    else $("mxArea").innerHTML = `<div class="mx-empty">No detections in this range.</div>`;
    mxTimeChart($("mxUnique"), d, [{ name: "Unique devices", values: d.unique_series, color: "#3987e5" }], { h: 170 });
    mxBars($("mxVendors"), d.by_vendor.map((v) => ({ label: v.name, value: v.count, color: d.series.find((s) => s.name === v.name) ? mxColor(v.name) : MX_OTHER,
        tip: `<div class="mx-tr"><span>Detections</span><b>${v.count}</b></div><div class="mx-tr"><span>Devices</span><b>${v.devices}</b></div>` })));
    mxBars($("mxNodes"), d.by_node.map((n) => { const nd = nodeById(n.id);
        return { label: nodeName(n.id), value: n.count, color: nd && nd.color != null ? nodeColor(nd) : "#3987e5",
                 tip: `<div class="mx-tr"><span>Detections</span><b>${n.count}</b></div><div class="mx-tr"><span>Devices</span><b>${n.devices}</b></div>` }; }));
    mxBars($("mxTypes"), d.by_type.map((t) => ({ label: t.type, value: t.count, color: "#3987e5",
        tip: `<div class="mx-tr"><span>Detections</span><b>${t.count}</b></div>` })));
    mxHeat($("mxHeat"), d.heat);
    mxHist($("mxRssi"), d.rssi);
    $("mxUpd").textContent = `updated ${new Date().toLocaleTimeString([], { hour12: false })}`;
}
async function mxLoad() {
    if (!$("tab-metrics").classList.contains("active")) return;
    const q = new URLSearchParams({ range: S.mx.range, node: S.mx.node, dom: S.mx.dom });
    try { S.mx.data = await api(`/api/metrics?${q}`); } catch (e) { return; }
    mxRender();
}
function mxNodeOptions() {
    const sel = $("mxNode"), cur = sel.value;
    const html = `<option value="">All nodes</option>` + (S.fleet ? S.fleet.nodes : []).map((n) => `<option value="${esc(n.id)}">${esc(nodeName(n.id))}</option>`).join("");
    if (sel.innerHTML !== html) { sel.innerHTML = html; sel.value = cur; }
}
document.querySelectorAll("#mxRange button").forEach((b) => {
    b.classList.toggle("on", Number(b.dataset.r) === S.mx.range);
    b.onclick = () => {
        S.mx.range = Number(b.dataset.r); lsSet("ouispy.mxRange", S.mx.range);
        document.querySelectorAll("#mxRange button").forEach((x) => x.classList.toggle("on", x === b));
        mxLoad();
    };
});
$("mxNode").onchange = () => { S.mx.node = $("mxNode").value; mxLoad(); };
$("mxDom").onchange = () => { S.mx.dom = $("mxDom").value; mxLoad(); };
document.querySelector('.tab[data-tab="metrics"]').addEventListener("click", () => setTimeout(() => { mxNodeOptions(); mxLoad(); }, 0));
setInterval(mxLoad, 15000);                         // live while the tab is open
let mxDetTimer = null;
function mxOnDetection() { clearTimeout(mxDetTimer); mxDetTimer = setTimeout(mxLoad, 2500); }
new ResizeObserver(() => { if (S.mx.data) mxRender(); }).observe($("tab-metrics"));

async function boot() {
    const st = await api("/api/state");
    // The USB pill counts from the home's last line the server already has,
    // not from this page load (it showed NO DATA for the first seconds).
    const serverNow = (st.fleet && st.fleet.ts) || Date.now() / 1000;
    for (let i = (st.console || []).length - 1; i >= 0; i--) {
        if (st.console[i][1] === "serial") { S.serialLast = Date.now() / 1000 - (serverNow - st.console[i][0]); break; }
    }
    S.settings = st.settings;
    S.sources = st.sources;
    S.statsBase = st.stats;
    S.dets = st.recent;
    S.dets.forEach((d) => { if (!S.macSeen[d.mac] || d.ts > S.macSeen[d.mac]) S.macSeen[d.mac] = d.ts; });
    S.hourly = st.hourly || [];
    S.macAliases = st.mac_aliases || {};
    S.deviceNames = st.device_names || {};
    S.groups = st.groups || [];
    S.groupOf = st.group_of || {};
    S.droneTags = st.drone_tags;
    (st.drones || []).forEach((d) => { d._rx = Date.now(); S.drones[d.mac] = d; S.droneSeen.add(d.mac); });
    S.droneCentred = Object.values(S.drones).some((d) => droneLive(d) && d.lat != null);   // don't yank a reload
    S.filterMeta = st.filter_meta;
    syncTrailSlider();
    try { await loadTrails(Math.max(trailMax(), 1800)); } catch (e) { /* older server */ }
    S.jobs = st.jobs || [];
    S.jobs.forEach((j) => { S.jobState[j.id] = j.state; });
    tileOptions($("mapLayer"));
    setTimeout(renderTrafficBtn, 0);
    tileOptions($("sTiles"));
    vendorOptions($("dPreset"));
    vendorOptions($("fPreset"));
    quickTypeOptions($("dQType"));
    quickTypeOptions($("fQType"));
    try { S.firmware = (await api("/api/firmware")).firmware; } catch (e) { /* older server */ }
    loadFleetKeyStatus();
    const badge = $("modeBadge");
    badge.textContent = st.mode.toUpperCase();
    badge.className = `mode-badge ${st.mode}`;
    applyFleet(st.fleet);
    applyTiles();
    initView();
    renderTrails();
    renderSources();
    renderToggles();
    renderFeed();
    renderKpis();
    st.console.forEach(([ts, src, line]) => appendConsole(ts, src, line));
    loadHistory(false);
    S.booted = true;
    renderDrones();
    renderJobs();
    renderFleetCtl();

    const sock = io({ transports: ["websocket", "polling"] });
    sock.on("fleet", applyFleet);
    sock.on("node_filters", (u) => {
        const n = S.fleet && S.fleet.nodes.find((x) => x.id === u.id);
        if (!n) return;
        FILTER_KEYS.forEach((k) => { n[k] = u[k]; });
        applyFleet(S.fleet);
    });
    sock.on("det", onDetection);
    sock.on("sighting", (s) => { if (s.name) S.deviceNames[s.mac] = s.name; onSighting(s); });
    sock.on("sources", (s) => { S.sources = s; renderSources(); });
    sock.on("console", (c) => { appendConsole(c.ts, c.source, c.line); if (c.source === "serial") serialBlink(); trafficFromLine(c.line); });
    sock.on("drone", onDrone);
    sock.on("groups", (g) => {
        S.groups = g.groups || [];
        S.groupOf = g.group_of || {};
        renderFeed();
        if ($("tab-devices").classList.contains("active")) loadDevices();
        if (S.device && $("vDrawer").classList.contains("open")) openDevice(S.device);
    });
    sock.on("mac_aliases", (m) => {
        S.macAliases = m;
        renderFeed();
        if ($("tab-devices").classList.contains("active")) loadDevices();
        if (S.device && $("vDrawer").classList.contains("open")) openDevice(S.device);
    });
    sock.on("settings", (s) => {
        // Reload tiles only when the layer itself changed (re-adding the tile
        // layer blanks the map until the tiles come back), and keep this
        // screen's own map position.
        const layerChanged = s.tiles !== S.settings.tiles || s.tiles_custom !== S.settings.tiles_custom;
        S.settings = { ...s, map_view: S.settings.map_view };
        if (layerChanged) applyTiles();
        renderLinks(); renderToggles(); renderTrafficBtn();
        // Refill the form unless someone is typing in it right now.
        if (!$("tab-settings").contains(document.activeElement)) loadSettingsForm();
    });
    sock.on("fleetkey", () => loadFleetKeyStatus());
    sock.on("firmware", (m) => { S.firmware = m; renderFirmware(); });
    sock.on("job", onJob);
    sock.on("dets_cleared", (e) => {
        S.dets = S.dets.filter((d) => (e.node && d.node !== e.node) || (e.mac && d.mac !== e.mac));
        afterDetsCleared();
    });
    sock.on("gps", onGps);
    sock.on("gps_stop", (g) => {
        delete S.gpsLive[g.node];
        if (g.cleared) delete S.trails[g.node];
        renderMap(); renderTrails();
        if (S.selected === g.node) renderGpsButton();
    });
    sock.on("node_event", (e) => {
        const n = nodeById(e.id);
        if (S.booted && e.id !== S.fleet.home.id && !(n && n.is_home)) {
            if (e.event === "offline") toast("bad", `${nodeName(e.id)} dropped off the mesh`, `${e.id} | last ${n && n.rssi ? n.rssi + " dBm" : "no rssi"}`, () => selectNode(e.id, true));
            else toast("good", `${nodeName(e.id)} joined`, e.id, () => selectNode(e.id, true));
        }
        if (S.selected === e.id && $("drawer").classList.contains("open")) openDrawer(e.id);
    });
    sock.on("disconnect", () => { S.sockUp = false; S.sources = { ui: { kind: "dashboard", connected: false, detail: "server connection lost" } }; renderSources(); });
    // (Re)connect: catch up on everything that happened while the socket
    // was down (phone asleep, Wi-Fi blip, server restart), not just the fleet.
    sock.on("connect", async () => {
        S.sockUp = true;
        const st2 = await api("/api/state");
        S.sources = st2.sources; renderSources(); applyFleet(st2.fleet);
        S.dets = st2.recent; S.statsBase = st2.stats; S.hourly = st2.hourly || [];
        S.macAliases = st2.mac_aliases || {};
        S.settings = st2.settings;
        (st2.jobs || []).forEach((j) => { S.jobState[j.id] = j.state; });
        S.jobs = st2.jobs || S.jobs;
        renderFeed(); renderKpis(); renderNodes(); renderJobs(); renderFleetCtl();
        loadHistory(false);
        if ($("tab-devices").classList.contains("active")) loadDevices();
        if (S.selected && $("drawer").classList.contains("open")) openDrawer(S.selected);
        if (S.device && $("vDrawer").classList.contains("open")) openDevice(S.device);
        loadFleetKeyStatus();
    });
}

setInterval(() => {
    $("clock").textContent = new Date().toLocaleTimeString([], { hour12: false });
    renderTargets();   // age lines out, drop devices gone quiet
    if (Object.keys(S.drones).length) renderDrones();   // transmit ring + staleout follow the clock
    document.querySelectorAll("[data-age]").forEach((el) => {
        const ts = Number(el.dataset.age);
        const off = el.textContent.startsWith("last ");
        el.textContent = (off ? "last " : "") + ago(ts);
    });
}, 1000);


// ------------------------------------------------------------------
// drones: Remote ID from every mesh node (and Sky-Spy boards on USB)
// ------------------------------------------------------------------
S.drones = {};          // mac -> latest public state (drones.py _public)
S.droneLayer = null;
S.droneMarks = {};      // mac -> {drone, pilot, link, track, ptrack}
S.droneOpen = null;
S.droneSeen = new Set();
const TAG_HUE = { unknown: 190, friendly: 140, neutral: 50, suspicious: 30, hostile: 330 };
function droneName(d) { return d.alias || d.desc || d.id || d.mac; }
// Like mesh-mapper: every drone keeps its own colour (hashed from its MAC) so several in
// the air never look alike; a tag the operator set (friendly, hostile...) takes over.
function droneHue(d) {
    if (d.tag && d.tag !== "unknown" && TAG_HUE[d.tag] != null) return TAG_HUE[d.tag];
    let h = 0;
    for (const ch of d.mac || "") h = (Math.imul(h, 31) + ch.charCodeAt(0)) | 0;
    return Math.abs(h) % 360;
}
// Age now, from the age the server sent plus the time since it arrived (no clock skew).
const DRONE_LIVE_S = 60, DRONE_TX_S = 5;
function droneAge(d) { return (d.age || 0) + (d._rx ? (Date.now() - d._rx) / 1000 : 0); }
function droneLive(d) { return droneAge(d) < DRONE_LIVE_S; }
function fmtM(v) { return v == null ? "-" : `${Math.round(v)} m`; }
function droneIcon(d) {
    const hue = droneHue(d);
    const rot = d.hdg != null ? d.hdg : 0;
    return L.divIcon({ className: "", iconSize: [0, 0], html:
        `<div class="drm ${droneLive(d) ? (droneAge(d) <= DRONE_TX_S ? "tx" : "") : "stale"}" style="--h:${hue}">
            <svg viewBox="-20 -20 40 40" style="transform:rotate(${rot}deg)">
                <circle r="17" class="ring"/>
                <path d="M-9-9L9 9M9-9L-9 9" class="arm"/>
                <circle cx="-9" cy="-9" r="4.5" class="rotor"/><circle cx="9" cy="-9" r="4.5" class="rotor"/>
                <circle cx="-9" cy="9" r="4.5" class="rotor"/><circle cx="9" cy="9" r="4.5" class="rotor"/>
                ${d.hdg != null ? `<path d="M0-19L4-12H-4Z" class="nose"/>` : ""}
            </svg>
            <span class="drm-label">${esc(droneName(d))}<small>${d.hagl != null ? `${Math.round(d.hagl)} m AGL` : d.alt != null ? `${Math.round(d.alt)} m MSL` : ""}${d.spd != null ? ` | ${d.spd.toFixed(1)} m/s` : ""}</small></span>
        </div>` });
}
function pilotIcon(d) {
    const hue = droneHue(d);
    return L.divIcon({ className: "", iconSize: [0, 0], html:
        `<div class="plm ${droneLive(d) ? "" : "stale"}" style="--h:${hue}">
            <svg viewBox="-12 -12 24 24"><circle cy="-5" r="4"/><path d="M-7 9c0-6 3-9 7-9s7 3 7 9z"/></svg>
            <span class="drm-label">PILOT<small>${d.pilot_dist_m != null ? `${d.pilot_dist_m} m to drone` : ""}</small></span>
        </div>` });
}
function renderDroneMap() {
    if (!S.droneLayer) S.droneLayer = L.layerGroup().addTo(map);
    const showP = $("drShowPilot").checked, showT = $("drShowTrack").checked;
    const keep = new Set();
    for (const d of Object.values(S.drones)) {
        if (d.lat == null && d.plat == null) continue;
        const live = droneLive(d);
        if (!live && droneAge(d) > 1800) continue;
        keep.add(d.mac);
        const m = S.droneMarks[d.mac] = S.droneMarks[d.mac] || {};
        const hue = droneHue(d);
        if (d.lat != null) {
            if (!m.drone) {
                m.drone = L.marker([d.lat, d.lon], { zIndexOffset: 900 }).addTo(S.droneLayer);
                m.drone.on("click", () => openDrone(d.mac));
            }
            m.drone.setLatLng([d.lat, d.lon]).setIcon(droneIcon(d));
        }
        const pOk = showP && d.plat != null;
        if (pOk) {
            if (!m.pilot) {
                m.pilot = L.marker([d.plat, d.plon], { zIndexOffset: 880 }).addTo(S.droneLayer);
                m.pilot.on("click", () => openDrone(d.mac));
            }
            m.pilot.setLatLng([d.plat, d.plon]).setIcon(pilotIcon(d));
        } else if (m.pilot) { S.droneLayer.removeLayer(m.pilot); m.pilot = null; }
        if (pOk && d.lat != null) {
            const ll = [[d.plat, d.plon], [d.lat, d.lon]];
            if (!m.link) m.link = L.polyline(ll, { color: `hsl(${hue} 100% 60%)`, weight: 1.5, dashArray: "4 6", opacity: .9, interactive: false }).addTo(S.droneLayer);
            else m.link.setLatLngs(ll);
            m.link.setStyle({ color: `hsl(${hue} 100% 60%)`, opacity: live ? .9 : .4 });
        } else if (m.link) { S.droneLayer.removeLayer(m.link); m.link = null; }
        const tr = showT ? (d.track || []).map((p) => [p[1], p[2]]) : [];
        if (tr.length > 1) {
            if (!m.track) m.track = L.polyline(tr, { color: `hsl(${hue} 100% 62%)`, weight: 3, interactive: false, className: "dr-track" }).addTo(S.droneLayer);
            else m.track.setLatLngs(tr);
            m.track.setStyle({ color: `hsl(${hue} 100% 62%)`, opacity: live ? .9 : .45 });
        } else if (m.track) { S.droneLayer.removeLayer(m.track); m.track = null; }
        const pt = showT && showP ? (d.ptrack || []).map((p) => [p[1], p[2]]) : [];
        if (pt.length > 1) {
            if (!m.ptrack) m.ptrack = L.polyline(pt, { weight: 2, dashArray: "5 5", interactive: false }).addTo(S.droneLayer);
            else m.ptrack.setLatLngs(pt);
            m.ptrack.setStyle({ color: `hsl(${hue} 100% 62%)`, opacity: live ? .8 : .4 });
        } else if (m.ptrack) { S.droneLayer.removeLayer(m.ptrack); m.ptrack = null; }
    }
    for (const mac of Object.keys(S.droneMarks)) {
        if (keep.has(mac)) continue;
        for (const l of Object.values(S.droneMarks[mac])) if (l) S.droneLayer.removeLayer(l);
        delete S.droneMarks[mac];
    }
    if (!S.droneCentred && S.booted) {
        const first = Object.values(S.drones).find((d) => droneLive(d) && d.lat != null);
        if (first) { S.droneCentred = true; map.setView([first.lat, first.lon], Math.max(map.getZoom(), 17)); }
    }
    if ($("drFollow").checked) {
        const live = Object.values(S.drones).filter((d) => droneLive(d) && d.lat != null).sort((a, b) => droneAge(a) - droneAge(b))[0];
        if (live) map.panTo([live.lat, live.lon], { animate: true });
    }
}
function droneCard(d) {
    const hue = droneHue(d);
    const cells = [
        ["Height", d.hagl != null ? `${Math.round(d.hagl)} m AGL` : fmtM(d.alt)],
        ["Speed", d.spd != null ? `${d.spd.toFixed(1)} m/s` : "-"],
        ["Heading", d.hdg != null ? `${Math.round(d.hdg)}&deg;` : "-"],
        ["Climb", d.vspd != null ? `${d.vspd.toFixed(1)} m/s` : "-"],
        ["Pilot", d.pilot_dist_m != null ? `${d.pilot_dist_m} m away` : d.plat != null ? "located" : "unknown"],
        ["Signal", d.rssi != null ? `${d.rssi} dBm` : "-"],
    ];
    return `<div class="dr-card ${d.live ? "live" : "stale"}" style="--h:${hue}" data-mac="${esc(d.mac)}">
        <div class="dr-top"><span class="dr-name">${esc(droneName(d))}</span>
            <span class="dr-st">${esc(d.live ? (d.status || "LIVE") : `seen ${ago(d.last)}`)}</span></div>
        <div class="dr-sub">${esc(d.ua_type || "UA type not sent")} | ${esc((d.src || "").toUpperCase())} | via ${esc(nodeName(d.closest))}</div>
        ${d.id ? `<div class="dr-id">${esc(d.id)}</div>` : ""}
        <div class="dr-cells">${cells.map(([k, v]) => `<div><span>${k}</span><b>${v}</b></div>`).join("")}</div>
    </div>`;
}
let drRenderAt = 0, drRenderTimer = null;
function renderDrones() {
    const now = Date.now();
    if (now - drRenderAt < 400) { clearTimeout(drRenderTimer); drRenderTimer = setTimeout(renderDrones, 400); return; }
    drRenderAt = now;
    for (const d of Object.values(S.drones)) d.live = droneLive(d);
    const all = Object.values(S.drones).sort((a, b) => (b.live - a.live) || (droneAge(a) - droneAge(b)));
    const live = all.filter((d) => d.live);
    const badge = $("droneBadge");
    badge.hidden = !live.length;
    badge.textContent = live.length;
    renderDroneMap();
    if (!$("tab-drones").classList.contains("active")) return;
    const airborne = live.filter((d) => d.status === "Airborne").length;
    const pilots = live.filter((d) => d.plat != null).length;
    const hi = live.reduce((m, d) => Math.max(m, d.hagl ?? -1), -1);
    $("drKpis").innerHTML = [["Live", live.length, live.length ? "hot" : ""], ["Airborne", airborne], ["Pilots located", pilots],
        ["Highest", hi >= 0 ? `${Math.round(hi)} m` : "-"], ["Seen today", all.length]]
        .map(([k, v, c]) => `<div class="hs"><div class="k">${k}</div><div class="v ${c || ""}">${v}</div></div>`).join("");
    $("drCards").innerHTML = all.slice(0, 12).map(droneCard).join("") ||
        `<div class="empty">No drones yet. Every node on firmware with Remote ID decodes drones (WiFi beacon, WiFi NAN and Bluetooth) and they show up here and on the map with their pilot.</div>`;
    $("drCards").querySelectorAll(".dr-card").forEach((el) => el.onclick = () => openDrone(el.dataset.mac));
}
async function loadDroneTable() {
    const r = await api("/api/drones?hours=24&track=0");
    $("drTotal").textContent = `${r.recent.length} drone${r.recent.length === 1 ? "" : "s"}`;
    $("drBody").innerHTML = r.recent.map((d) => `<tr data-mac="${esc(d.mac)}">
        <td class="v">${esc(d.alias || (S.drones[d.mac] && droneName(S.drones[d.mac])) || "")}</td><td>${esc(d.mac)}</td>
        <td><span class="dtag" style="--h:${TAG_HUE[d.tag || "unknown"]}">${esc(d.tag || "unknown")}</span></td><td>${d.n}</td>
        <td>${fmtM(d.max_alt)}</td><td>${fullTime(d.first)}</td><td>${ago(d.last)}</td></tr>`).join("") ||
        `<tr><td colspan="7" style="text-align:center;padding:20px">No drones in the last 24 h</td></tr>`;
    $("drBody").querySelectorAll("tr[data-mac]").forEach((tr) => tr.onclick = () => openDrone(tr.dataset.mac));
}
function onDrone(d) {
    const fresh = !S.drones[d.mac] && !S.droneSeen.has(d.mac);
    d._rx = Date.now();
    S.drones[d.mac] = d;
    S.droneSeen.add(d.mac);
    if (fresh && S.booted) {
        toast("bad", "Drone detected", `${droneName(d)}${d.ua_type ? ", " + d.ua_type : ""} via ${nodeName(d.closest)}`, () => openDrone(d.mac));
        if (S.settings && S.settings.sound) beep();
    }
    renderDrones();
    if (S.droneOpen === d.mac && $("drDrawer").classList.contains("open")) fillDroneLive(d);
}
function fillDroneLive(d) {
    $("drTitle").textContent = droneName(d);
    $("drSub").textContent = [d.mac, d.vendor, d.ua_type, d.live ? (d.status || "live") : `last seen ${ago(d.last)}`].filter(Boolean).join(" | ");
    const cells = [
        ["Height AGL", fmtM(d.hagl)], ["Altitude MSL", fmtM(d.alt)], ["Baro alt", fmtM(d.altb)],
        ["Speed", d.spd != null ? `${d.spd.toFixed(1)} m/s` : "-"], ["Climb", d.vspd != null ? `${d.vspd.toFixed(1)} m/s` : "-"],
        ["Heading", d.hdg != null ? `${Math.round(d.hdg)}&deg;` : "-"],
        ["Pilot distance", d.pilot_dist_m != null ? `${d.pilot_dist_m} m` : "-"], ["Signal", d.rssi != null ? `${d.rssi} dBm` : "-"],
        ["Reports", d.reports ?? "-"],
    ];
    $("drStats").innerHTML = cells.map(([k, v]) => `<div class="hs"><div class="k">${k}</div><div class="v">${v}</div></div>`).join("");
    const rows = [];
    const row = (k, v, cls) => { if (v !== undefined && v !== null && v !== "") rows.push(`<div class="ik">${k}</div><div class="iv ${cls || ""}">${v}</div>`); };
    row("Serial / UAS ID", d.id ? `<code>${esc(d.id)}</code>` : "", "hl");
    row("ID type", esc(d.id_type || ""));
    row("Aircraft", esc(d.ua_type || ""));
    row("Vendor (MAC OUI)", esc(d.vendor || ""));
    row("FAA DOC", d.faa ? (() => { const it = ((d.faa.data || {}).items || d.faa.items || [])[0]; return it ? esc([it.makeName, it.modelName].filter(Boolean).join(" ")) + (it.status ? ` (${esc(it.status)})` : "") : ""; })() : "");
    row("Status", esc(d.status || ""), d.status === "Emergency" ? "bad" : "");
    row("Operator ID", d.op ? `<code>${esc(d.op)}</code>` : "");
    row("Self description", d.desc ? `"${esc(d.desc)}"` : "");
    row("Drone position", d.lat != null ? `${d.lat.toFixed(6)}, ${d.lon.toFixed(6)}` : "");
    row("Pilot position", d.plat != null ? `${d.plat.toFixed(6)}, ${d.plon.toFixed(6)}${d.op_loc ? ` <span class="sub">(${esc(d.op_loc)})</span>` : ""}` : "");
    row("Pilot altitude", d.palt != null ? `${Math.round(d.palt)} m MSL` : "");
    row("Broadcast over", esc({ wifi: "WiFi beacon", nan: "WiFi NAN", ble: "Bluetooth", skyspy: "Sky-Spy (USB)" }[d.src] || d.src || ""));
    const nodes = Object.entries(d.nodes || {}).sort((a, b) => (b[1].rssi ?? -200) - (a[1].rssi ?? -200));
    row("Heard by", nodes.map(([n, v]) => `<span class="chip">${esc(nodeName(n))} ${v.rssi ?? "?"} dBm, ${v.n}x</span>`).join(""));
    row("First seen", esc(fullTime(d.first)));
    $("drInfo").innerHTML = `<h4>Remote ID</h4><div class="igrid">${rows.join("")}</div>`;
}
function faaHtml(f) {
    if (!f) return `<div class="empty">Not looked up.</div>`;
    const items = (f.data && f.data.items) || f.items || [];
    if (!items.length) return `<div class="empty">No FAA record for this serial.</div>`;
    return items.map((it) => `<div class="igrid">${Object.entries(it).filter(([, v]) => v !== null && v !== "" && typeof v !== "object")
        .slice(0, 14).map(([k, v]) => `<div class="ik">${esc(k)}</div><div class="iv">${esc(String(v))}</div>`).join("")}</div>`).join("<hr>");
}
async function openDrone(mac) {
    S.droneOpen = mac;
    closeDrawer();
    $("vDrawer").classList.remove("open");
    $("drDrawer").classList.add("open");
    const live = S.drones[mac];
    if (live) fillDroneLive(live);
    let d;
    try { d = await api(`/api/drones/${encodeURIComponent(mac)}`); } catch (e) { return; }
    if (S.droneOpen !== mac) return;
    fillDroneLive({ ...d, ...(S.drones[mac] || {}) });
    if (document.activeElement !== $("drAlias")) $("drAlias").value = d.alias || "";
    if (document.activeElement !== $("drNotes")) $("drNotes").value = d.notes || "";
    $("drTags").innerHTML = (S.droneTags || ["unknown", "friendly", "neutral", "suspicious", "hostile"]).map((t) =>
        `<button class="dtag ${d.tag === t ? "on" : ""}" data-tag="${t}" style="--h:${TAG_HUE[t]}">${t}</button>`).join("");
    $("drTags").querySelectorAll("[data-tag]").forEach((b) => b.onclick = async () => {
        await api(`/api/drones/${encodeURIComponent(mac)}`, { method: "POST", body: { tag: b.dataset.tag } });
        openDrone(mac);
    });
    $("drFaa").innerHTML = faaHtml(d.faa) + (d.faa_ts ? `<div class="sub">looked up ${esc(ago(d.faa_ts))}</div>` : "");
    $("drFaaGo").disabled = !d.id;
    const h = (d.history || []).filter((x) => x.hagl != null || x.alt != null);
    const ys = h.map((x) => x.hagl ?? x.alt);
    if (ys.length > 1) {
        const t0 = h[0].ts, t1 = h[h.length - 1].ts || t0 + 1, lo = Math.min(...ys, 0), hiY = Math.max(...ys, 10);
        const pts = h.map((x, i) => `${((x.ts - t0) / Math.max(1, t1 - t0) * 320).toFixed(1)},${(78 - (ys[i] - lo) / (hiY - lo) * 74).toFixed(1)}`);
        $("drAlt").innerHTML = `<polyline points="${pts.join(" ")}" class="altline"/><text x="2" y="10">${Math.round(hiY)} m</text>`;
    } else $("drAlt").innerHTML = `<text x="2" y="44">No altitude history yet</text>`;
}
$("drClose").onclick = () => { $("drDrawer").classList.remove("open"); S.droneOpen = null; };
$("drSave").onclick = async () => {
    await api(`/api/drones/${encodeURIComponent(S.droneOpen)}`, { method: "POST", body: { alias: $("drAlias").value, notes: $("drNotes").value } });
    toast("good", "Drone saved", $("drAlias").value || S.droneOpen);
    openDrone(S.droneOpen);
    loadDroneTable();
};
$("drAlias").addEventListener("keydown", (e) => { if (e.key === "Enter") $("drSave").click(); });
$("drFaaGo").onclick = async () => {
    $("drFaaGo").disabled = true;
    $("drFaa").innerHTML = `<div class="empty">Asking the FAA...</div>`;
    const r = await api(`/api/drones/${encodeURIComponent(S.droneOpen)}/faa`, { method: "POST", body: {} }).catch((e) => ({ ok: false, error: String(e) }));
    $("drFaa").innerHTML = r.ok ? faaHtml(r.faa) : `<div class="empty bad">${esc(r.error || "lookup failed")}</div>`;
    $("drFaaGo").disabled = false;
};
$("drZoom").onclick = () => {
    const d = S.drones[S.droneOpen];
    if (!d) return;
    const pts = [[d.lat, d.lon], [d.plat, d.plon]].filter((p) => p[0] != null);
    if (pts.length > 1) map.fitBounds(pts, { padding: [60, 60], maxZoom: 18 });
    else if (pts.length) map.setView(pts[0], Math.max(map.getZoom(), 17));
};
["drShowPilot", "drShowTrack"].forEach((id) => $(id).addEventListener("change", renderDroneMap));
document.querySelector('.tab[data-tab="drones"]').addEventListener("click", () => { setTimeout(() => { renderDrones(); loadDroneTable(); }, 0); });
setInterval(() => {
    // age the live flags between reports
    let changed = false;
    for (const d of Object.values(S.drones)) {
        d.age = (d.age || 0) + 5;
        const live = d.age < 90;
        if (live !== d.live) { d.live = live; changed = true; }
    }
    if (changed) renderDrones();
}, 5000);

boot();
})();

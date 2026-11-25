"""Map tile proxy + disk cache for clients that can't do HTTPS or keep their own
cache (the Tab5 display). /tiles/<layer>/<z>/<x>/<y> fetches the tile from the
layer's public server once, keeps it in tilecache/, and serves it from disk
from then on, so areas you have looked at stay available offline."""
import os
import threading
import urllib.request
from io import BytesIO

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "tilecache")
UA = "OUI-SPY-Mesh-dashboard/1.0 (local tile cache for a wall display)"

ESRI = "https://server.arcgisonline.com/ArcGIS/rest/services/{svc}/MapServer/tile/{z}/{y}/{x}"
LAYERS = {
    "esri-sat":    {"url": ESRI.replace("{svc}", "World_Imagery"), "ext": "jpg", "max": 19, "name": "Satellite"},
    "esri-street": {"url": ESRI.replace("{svc}", "World_Street_Map"), "ext": "jpg", "max": 19, "name": "Streets"},
    "esri-topo":   {"url": ESRI.replace("{svc}", "World_Topo_Map"), "ext": "jpg", "max": 19, "name": "Topo"},
    "carto-dark":  {"url": "https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png", "ext": "png", "max": 20, "name": "Dark"},
    "osm":         {"url": "https://tile.openstreetmap.org/{z}/{x}/{y}.png", "ext": "png", "max": 19, "name": "OSM"},
}
_locks = {}
_glock = threading.Lock()


def tile(layer, z, x, y):
    """(bytes, mimetype) or raises KeyError / OSError."""
    L = LAYERS[layer]
    if not (0 <= z <= L["max"] and 0 <= x < 2 ** z and 0 <= y < 2 ** z):
        raise KeyError("tile out of range")
    # PNG layers are cached and served as JPEG: the Tab5's on-device PNG decoder
    # (lgfx, palette PNGs) hard-crashes its loader task; JPEG decode is proven.
    ext = "jpg" if L["ext"] == "png" else L["ext"]
    path = os.path.join(CACHE, layer, str(z), str(x), f"{y}.{ext}")
    mime = "image/jpeg" if ext == "jpg" else "image/png"
    if os.path.exists(path):
        with open(path, "rb") as f:
            return f.read(), mime
    with _glock:
        lk = _locks.setdefault(path, threading.Lock())
    with lk:
        if not os.path.exists(path):
            url = L["url"].format(z=z, x=x, y=y)
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=15) as r:
                data = r.read()
            if L["ext"] == "jpg" and len(data) < 10_000:
                # Esri answers gap/over-zoom requests with a 200 "Map data not yet
                # available" placeholder; caching it would poison this area forever.
                with _glock:
                    _locks.pop(path, None)
                return data, mime
            if L["ext"] == "png":
                im = Image.open(BytesIO(data)).convert("RGB")
                out = BytesIO()
                im.save(out, "JPEG", quality=88)
                data = out.getvalue()
            os.makedirs(os.path.dirname(path), exist_ok=True)
            tmp = path + ".tmp"
            with open(tmp, "wb") as f:
                f.write(data)
            os.replace(tmp, path)
    with _glock:
        _locks.pop(path, None)
    with open(path, "rb") as f:
        return f.read(), mime


def _deg2tile(lat, lon, z):
    import math
    n = 2 ** z
    x = int((lon + 180.0) / 360.0 * n)
    r = math.radians(lat)
    y = int((1.0 - math.asinh(math.tan(r)) / math.pi) / 2.0 * n)
    return x, y


def prewarm(points, layer="esri-sat", radius_m=700, zmin=12, zmax=19, pause=0.05):
    """Fetch (into the disk cache) every tile within radius_m of the given
    (lat, lon) points, coarse zooms first, so displays open on a map that is
    already there. Tiles already cached cost nothing."""
    import math
    import time
    if not points:
        return 0
    lat0 = min(p[0] for p in points); lat1 = max(p[0] for p in points)
    lon0 = min(p[1] for p in points); lon1 = max(p[1] for p in points)
    dlat = radius_m / 111320.0
    dlon = radius_m / (111320.0 * max(0.2, math.cos(math.radians((lat0 + lat1) / 2))))
    n = 0
    for z in range(zmin, zmax + 1):
        xa, ya = _deg2tile(lat1 + dlat, lon0 - dlon, z)
        xb, yb = _deg2tile(lat0 - dlat, lon1 + dlon, z)
        for x in range(xa, xb + 1):
            for y in range(ya, yb + 1):
                ext = "jpg" if LAYERS[layer]["ext"] == "png" else LAYERS[layer]["ext"]
                path = os.path.join(CACHE, layer, str(z), str(x), f"{y}.{ext}")
                if os.path.exists(path):
                    continue
                try:
                    tile(layer, z, x, y)
                    n += 1
                except Exception:
                    pass
                time.sleep(pause)
    return n

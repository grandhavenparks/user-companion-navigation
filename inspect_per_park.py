#!/usr/bin/env python3
"""
Per-park diagnostic.

For each park geojson, counts how many of its (z, x, y) tiles in the bundled
DB are:
  - real     : data not matching the known blocked-PNG hash
  - blocked  : data exactly matches the OSM "Access blocked" PNG
  - tiny     : <= 110 bytes (placeholders / no-data, usually fine to ignore)
  - missing  : not in the DB at all

Tells you which parks need re-downloading and at what zoom.

Run from project root:
    python3 inspect_per_park.py
"""
import hashlib
import json
import math
import sqlite3
from pathlib import Path

# Config (matches download_tiles.py)
PARKS_DIR = "parks"
OSM_DB = "assets/tiles/osm_tiles.db"
TOPO_DB = "assets/tiles/topo_tiles.db"
MIN_ZOOM = 14
MAX_ZOOM_OSM = 18
MAX_ZOOM_TOPO = 17

# From the previous inspect_tiles.py run:
OSM_BLOCKED_HASH = "b02c44252dac"  # 6987-byte "Access blocked" PNG (6897 hits)
# Topo had no single dominant blocked hash; its repeats were all 103B placeholders.
TOPO_BLOCKED_HASH = None
TINY_THRESHOLD = 110  # bytes; OSM/Topo "no-data" placeholders are ~103B


def hash12(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()[:12]


def lat_lon_to_tile(lat: float, lon: float, zoom: int) -> tuple[int, int]:
    lat_rad = math.radians(lat)
    n = 2.0 ** zoom
    x = int((lon + 180.0) / 360.0 * n)
    y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return x, y


def park_bounds(geojson_path: Path) -> tuple[float, float, float, float]:
    data = json.loads(geojson_path.read_text())
    coords = data["features"][0]["geometry"]["coordinates"][0]
    lats = [c[1] for c in coords]
    lons = [c[0] for c in coords]
    return min(lats), max(lats), min(lons), max(lons)


def iter_tiles(min_lat, max_lat, min_lon, max_lon, max_zoom):
    for z in range(MIN_ZOOM, max_zoom + 1):
        x_min, y_max = lat_lon_to_tile(min_lat, min_lon, z)
        x_max, y_min = lat_lon_to_tile(max_lat, max_lon, z)
        for x in range(x_min, x_max + 1):
            for y in range(y_min, y_max + 1):
                yield z, x, y


def classify(data: bytes, blocked_hash: str | None) -> str:
    if blocked_hash and hash12(data) == blocked_hash:
        return "blocked"
    if len(data) <= TINY_THRESHOLD:
        return "tiny"
    return "real"


def analyze(park_file: Path, db_path: str, max_zoom: int, blocked_hash: str | None):
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    per_zoom: dict[int, dict[str, int]] = {}
    bounds = park_bounds(park_file)
    for z, x, y in iter_tiles(*bounds, max_zoom):
        slot = per_zoom.setdefault(z, {"real": 0, "blocked": 0, "tiny": 0, "missing": 0})
        row = cur.execute(
            "SELECT data FROM tiles WHERE zoom=? AND x=? AND y=?", (z, x, y)
        ).fetchone()
        if row is None:
            slot["missing"] += 1
        else:
            slot[classify(row[0], blocked_hash)] += 1
    conn.close()
    return per_zoom


def summarize(per_zoom: dict[int, dict[str, int]]) -> dict[str, int]:
    totals = {"real": 0, "blocked": 0, "tiny": 0, "missing": 0}
    for z, counts in per_zoom.items():
        for k, v in counts.items():
            totals[k] += v
    return totals


def fmt(n: int, t: int) -> str:
    if t == 0:
        return f"{n}"
    return f"{n}/{t} ({n / t * 100:>3.0f}%)"


def print_park(name: str, per_zoom: dict[int, dict[str, int]]):
    totals = summarize(per_zoom)
    total = sum(totals.values())
    status = "OK" if totals["blocked"] == 0 else "BROKEN"
    print(f"  {name:5s} [{status}]: "
          f"real={fmt(totals['real'], total)}  "
          f"blocked={fmt(totals['blocked'], total)}  "
          f"tiny={fmt(totals['tiny'], total)}  "
          f"missing={fmt(totals['missing'], total)}")
    for z in sorted(per_zoom):
        counts = per_zoom[z]
        zt = sum(counts.values())
        if counts["blocked"] > 0 or counts["missing"] > 0:
            print(f"         z={z}: real={fmt(counts['real'], zt)}  "
                  f"blocked={fmt(counts['blocked'], zt)}  "
                  f"tiny={fmt(counts['tiny'], zt)}  "
                  f"missing={fmt(counts['missing'], zt)}")


def main():
    park_files = sorted(Path(PARKS_DIR).glob("*.geojson"))
    if not park_files:
        print(f"No park files in {PARKS_DIR}/")
        return
    print(f"Analyzing {len(park_files)} parks\n")
    print(f"OSM blocked hash:  {OSM_BLOCKED_HASH}")
    print(f"Tiny threshold:    <= {TINY_THRESHOLD} bytes (placeholders)\n")

    for pf in park_files:
        print(f"== {pf.stem} ==")
        if Path(OSM_DB).exists():
            r = analyze(pf, OSM_DB, MAX_ZOOM_OSM, OSM_BLOCKED_HASH)
            print_park("OSM", r)
        if Path(TOPO_DB).exists():
            r = analyze(pf, TOPO_DB, MAX_ZOOM_TOPO, TOPO_BLOCKED_HASH)
            print_park("Topo", r)
        print()


if __name__ == "__main__":
    main()
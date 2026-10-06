#!/usr/bin/env python3
"""
Build the offline basemap that is bundled inside the User Navigation Companion APK.

What it does
------------
1. Reads every park boundary in ``parks/*.geojson`` (Polygon / MultiPolygon,
   any number of features per file, holes allowed).
2. Builds an extraction region: the bounding box of every park area, grown by
   ``--buffer-m`` metres so you still have map just outside the boundary.
3. Cuts that region out of the free Protomaps daily planet build with the
   ``pmtiles`` CLI (``pmtiles extract`` only downloads the bytes it needs).
4. Converts the extract to MBTiles (SQLite) and writes it to
   ``assets/map/basemap.mbtiles`` together with ``assets/map/map_manifest.json``.

The app copies the MBTiles file out of the APK once per build (tracked by the
manifest's ``build_id``) and renders it with vector_map_tiles, so the map is
sharp at every zoom level up to 24 and needs no network and no API key.

Requirements (macOS)
--------------------
    brew install pmtiles
    python3 -m pip install -r tools/requirements.txt

Usage (run from the project root)
---------------------------------
    python3 tools/build_map.py                 # latest daily build, 500 m buffer
    python3 tools/build_map.py --buffer-m 1000
    python3 tools/build_map.py --source https://build.protomaps.com/20261001.pmtiles
    python3 tools/build_map.py --source ~/maps/planet.pmtiles
    python3 tools/build_map.py --dry-run       # only report what would be extracted

Licensing: the basemap is an OpenStreetMap Produced Work (ODbL). The app shows
"© OpenStreetMap contributors, Protomaps" on the map. The Protomaps styles are CC0.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import re
import shutil
import sqlite3
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PARKS_DIR = ROOT / "parks"
ASSET_DIR = ROOT / "assets" / "map"
WORK_DIR = ROOT / "build" / "map"
LEGACY_TILE_DIR = ROOT / "assets" / "tiles"
THEME_FILE = ASSET_DIR / "protomaps_light_v4.json"
MBTILES_NAME = "basemap.mbtiles"
MANIFEST_NAME = "map_manifest.json"

BUILD_URL_TEMPLATE = "https://build.protomaps.com/{date}.pmtiles"
LOOKBACK_DAYS = 10
DEFAULT_BUFFER_M = 500.0
DEFAULT_MINZOOM = 0
DEFAULT_MAXZOOM = 15  # Protomaps basemap data stops at z15; the app overzooms to z24.
USER_AGENT = "UserNavigationCompanion-map-build/1.3 (offline field navigation app)"
ATTRIBUTION = "© OpenStreetMap contributors, Protomaps"


class BuildError(Exception):
    """A problem the user has to fix; printed without a traceback."""


# --------------------------------------------------------------------------- #
# Park parsing
# --------------------------------------------------------------------------- #

def park_display_name(file_stem: str) -> str:
    """MI_0005_GrandHavenParks -> 'Grand Haven Parks' (same rule as the app)."""
    parts = file_stem.split("_")
    if len(parts) >= 3 and parts[0].isalpha() and parts[1].isdigit():
        core = "_".join(parts[2:])
    else:
        core = file_stem
    core = core.replace("_", " ").replace("-", " ")
    core = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", core)
    core = re.sub(r"\s+", " ", core).strip()
    return core or file_stem


def _check_position(pos, where: str) -> tuple[float, float]:
    if not isinstance(pos, (list, tuple)) or len(pos) < 2:
        raise BuildError(f"{where}: position {pos!r} is not [lon, lat]")
    lon, lat = pos[0], pos[1]
    if not isinstance(lon, (int, float)) or not isinstance(lat, (int, float)):
        raise BuildError(f"{where}: position {pos!r} is not numeric")
    if not (math.isfinite(lon) and math.isfinite(lat)):
        raise BuildError(f"{where}: position {pos!r} is not finite")
    if not (-180.0 <= lon <= 180.0 and -90.0 <= lat <= 90.0):
        hint = ""
        if -90.0 <= lon <= 90.0 and -180.0 <= lat <= 180.0:
            hint = " (looks like [lat, lon]; GeoJSON must be [lon, lat])"
        raise BuildError(f"{where}: position {pos!r} is out of range{hint}")
    return float(lon), float(lat)


def _ring(coords, where: str) -> list[tuple[float, float]]:
    if not isinstance(coords, list):
        raise BuildError(f"{where}: ring is not a list")
    ring = [_check_position(p, where) for p in coords]
    if len(ring) >= 2 and ring[0] == ring[-1]:
        ring = ring[:-1]
    if len(set(ring)) < 3:
        raise BuildError(f"{where}: ring needs at least 3 distinct positions")
    return ring


def _polygons_from_geometry(geom, where: str) -> list[dict]:
    if not isinstance(geom, dict):
        return []
    gtype = geom.get("type")
    if gtype == "Polygon":
        rings = geom.get("coordinates") or []
        if not rings:
            return []
        return [{
            "outer": _ring(rings[0], f"{where} outer ring"),
            "holes": [_ring(r, f"{where} hole") for r in rings[1:]],
        }]
    if gtype == "MultiPolygon":
        out = []
        for i, poly in enumerate(geom.get("coordinates") or []):
            out.extend(_polygons_from_geometry(
                {"type": "Polygon", "coordinates": poly}, f"{where} polygon {i + 1}"))
        return out
    if gtype == "GeometryCollection":
        out = []
        for i, g in enumerate(geom.get("geometries") or []):
            out.extend(_polygons_from_geometry(g, f"{where} geometry {i + 1}"))
        return out
    return []


def load_parks(parks_dir: Path) -> list[dict]:
    files = sorted(parks_dir.glob("*.geojson"))
    if not files:
        raise BuildError(f"No park files found in {parks_dir}/ (expected *.geojson)")

    parks = []
    for path in files:
        try:
            data = json.loads(path.read_text(encoding="utf-8-sig"))
        except json.JSONDecodeError as exc:
            raise BuildError(f"{path.name}: invalid JSON ({exc})") from exc

        if data.get("type") == "FeatureCollection":
            features = data.get("features") or []
        elif data.get("type") == "Feature":
            features = [data]
        else:
            features = [{"type": "Feature", "properties": {}, "geometry": data}]

        areas: list[dict] = []
        name = None
        ignored = 0
        for i, feature in enumerate(features):
            if not isinstance(feature, dict):
                continue
            props = feature.get("properties") or {}
            if name is None:
                for key in ("name", "Name", "NAME", "park_name", "title"):
                    value = props.get(key)
                    if isinstance(value, str) and value.strip():
                        name = value.strip()
                        break
            found = _polygons_from_geometry(feature.get("geometry"), f"{path.name} feature {i + 1}")
            if not found:
                ignored += 1
            areas.extend(found)

        if not areas:
            raise BuildError(f"{path.name}: no Polygon/MultiPolygon geometry found")

        parks.append({
            "file": path.name,
            "id": path.stem,
            "name": name or park_display_name(path.stem),
            "areas": areas,
            "ignored_features": ignored,
        })
    return parks


# --------------------------------------------------------------------------- #
# Geometry helpers
# --------------------------------------------------------------------------- #

def ring_bbox(ring) -> tuple[float, float, float, float]:
    lons = [p[0] for p in ring]
    lats = [p[1] for p in ring]
    return min(lons), min(lats), max(lons), max(lats)


def buffer_bbox(bbox, meters: float) -> tuple[float, float, float, float]:
    min_lon, min_lat, max_lon, max_lat = bbox
    dlat = meters / 111_320.0
    mid_lat = math.radians((min_lat + max_lat) / 2.0)
    dlon = meters / (111_320.0 * max(math.cos(mid_lat), 0.01))
    return (
        max(-180.0, min_lon - dlon),
        max(-85.0511, min_lat - dlat),
        min(180.0, max_lon + dlon),
        min(85.0511, max_lat + dlat),
    )


def ring_area_km2(ring) -> float:
    """Approximate area with an equirectangular projection (fine at park scale)."""
    lat0 = math.radians(sum(p[1] for p in ring) / len(ring))
    pts = [(p[0] * 111.32 * math.cos(lat0), p[1] * 110.574) for p in ring]
    total = 0.0
    for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
        total += x1 * y2 - x2 * y1
    return abs(total) / 2.0


def build_region(parks: list[dict], buffer_m: float) -> dict:
    features = []
    for park in parks:
        for index, area in enumerate(park["areas"]):
            bbox = buffer_bbox(ring_bbox(area["outer"]), buffer_m)
            min_lon, min_lat, max_lon, max_lat = bbox
            features.append({
                "type": "Feature",
                "properties": {"park": park["id"], "area": index + 1},
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [[
                        [min_lon, min_lat], [max_lon, min_lat], [max_lon, max_lat],
                        [min_lon, max_lat], [min_lon, min_lat],
                    ]],
                },
            })
    return {"type": "FeatureCollection", "features": features}


def lonlat_to_tile(lon: float, lat: float, zoom: int) -> tuple[int, int]:
    lat = max(min(lat, 85.0511), -85.0511)
    n = 1 << zoom
    x = int((lon + 180.0) / 360.0 * n)
    y = int((1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * n)
    return min(max(x, 0), n - 1), min(max(y, 0), n - 1)


# --------------------------------------------------------------------------- #
# Source discovery and extraction
# --------------------------------------------------------------------------- #

def _url_status(url: str) -> int:
    """HTTP status for [url]: 200/206 when it exists, otherwise the error code."""
    headers = {"User-Agent": USER_AGENT}
    status = 0
    for method, extra in (("HEAD", {}), ("GET", {"Range": "bytes=0-0"})):
        request = urllib.request.Request(url, method=method, headers={**headers, **extra})
        try:
            with urllib.request.urlopen(request, timeout=20) as response:
                return response.status
        except urllib.error.HTTPError as exc:
            status = exc.code
            if exc.code in (403, 404, 410):
                return exc.code
            # e.g. 405 for HEAD -> retry with a ranged GET
        except (urllib.error.URLError, TimeoutError) as exc:
            raise BuildError(f"Cannot reach {url}: {exc}. Check your internet connection.") from exc
    return status


def find_latest_build(lookback_days: int) -> str:
    today = dt.datetime.now(dt.timezone.utc).date()
    statuses = []
    for offset in range(lookback_days + 1):
        date = today - dt.timedelta(days=offset)
        url = BUILD_URL_TEMPLATE.format(date=date.strftime("%Y%m%d"))
        print(f"  checking {url} ...", end=" ", flush=True)
        status = _url_status(url)
        statuses.append(status)
        if status in (200, 206):
            print("found")
            return url
        print(f"not available (HTTP {status})")
    hint = ""
    if statuses and all(s == 403 for s in statuses):
        hint = (" Every request was refused with HTTP 403, so a proxy or firewall may be "
                "blocking build.protomaps.com.")
    raise BuildError(
        f"No Protomaps daily build found in the last {lookback_days} days.{hint} "
        "Pick one at https://maps.protomaps.com/builds and pass it with --source.")


def find_pmtiles_cli(explicit: str | None) -> str:
    if explicit:
        resolved = shutil.which(explicit) or (explicit if Path(explicit).is_file() else None)
        if not resolved:
            raise BuildError(f"--pmtiles-cli {explicit!r} does not exist or is not executable")
        return resolved
    found = shutil.which("pmtiles")
    if not found:
        raise BuildError("The 'pmtiles' CLI was not found. Install it with:  brew install pmtiles")
    return found


def run_extract(cli: str, source: str, region: Path, output: Path,
                minzoom: int, maxzoom: int, dry_run: bool) -> None:
    if output.exists():
        output.unlink()
    cmd = [cli, "extract", source, str(output), f"--region={region}",
           f"--minzoom={minzoom}", f"--maxzoom={maxzoom}"]
    if dry_run:
        cmd.append("--dry-run")
    print("  $ " + " ".join(cmd))
    result = subprocess.run(cmd)
    if result.returncode != 0:
        raise BuildError(f"pmtiles extract failed with exit code {result.returncode}")


# --------------------------------------------------------------------------- #
# MBTiles conversion and verification
# --------------------------------------------------------------------------- #

def convert_to_mbtiles(pmtiles_path: Path, mbtiles_path: Path) -> None:
    try:
        from pmtiles.convert import pmtiles_to_mbtiles
    except ImportError as exc:
        raise BuildError(
            "Python package 'pmtiles' is missing. Install it with:\n"
            "  python3 -m pip install -r tools/requirements.txt") from exc
    if mbtiles_path.exists():
        mbtiles_path.unlink()
    pmtiles_to_mbtiles(str(pmtiles_path), str(mbtiles_path))
    # Compact the file and make it friendly for read-only access on the phone.
    conn = sqlite3.connect(mbtiles_path)
    try:
        conn.execute("PRAGMA journal_mode=DELETE")
        conn.execute("VACUUM")
    finally:
        conn.close()


def inspect_mbtiles(path: Path) -> dict:
    conn = sqlite3.connect(path)
    try:
        metadata = dict(conn.execute("SELECT name, value FROM metadata").fetchall())
        per_zoom = conn.execute(
            "SELECT zoom_level, COUNT(*), SUM(LENGTH(tile_data)) FROM tiles "
            "GROUP BY zoom_level ORDER BY zoom_level").fetchall()
        sample = conn.execute("SELECT tile_data FROM tiles LIMIT 1").fetchone()
    finally:
        conn.close()
    if not per_zoom:
        raise BuildError(f"{path.name} contains no tiles")
    compression = "unknown"
    if sample and sample[0][:2] == b"\x1f\x8b":
        compression = "gzip"
    elif sample:
        compression = "none"
    return {
        "metadata": metadata,
        "per_zoom": [{"zoom": z, "tiles": n, "bytes": b or 0} for z, n, b in per_zoom],
        "tile_count": sum(n for _, n, _ in per_zoom),
        "min_zoom": per_zoom[0][0],
        "max_zoom": per_zoom[-1][0],
        "compression": compression,
    }


def check_coverage(path: Path, parks: list[dict], zoom: int) -> list[str]:
    """Return a warning for every park area whose centre tile is missing."""
    problems = []
    conn = sqlite3.connect(path)
    try:
        for park in parks:
            for index, area in enumerate(park["areas"]):
                min_lon, min_lat, max_lon, max_lat = ring_bbox(area["outer"])
                x, y = lonlat_to_tile((min_lon + max_lon) / 2, (min_lat + max_lat) / 2, zoom)
                tms_y = (1 << zoom) - 1 - y
                row = conn.execute(
                    "SELECT 1 FROM tiles WHERE zoom_level=? AND tile_column=? AND tile_row=?",
                    (zoom, x, tms_y)).fetchone()
                if row is None:
                    problems.append(f"{park['file']} area {index + 1}: no z{zoom} tile at its centre")
    finally:
        conn.close()
    return problems


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_manifest(path: Path, *, build_id: str, source: str, parks: list[dict],
                   info: dict, buffer_m: float, size_bytes: int) -> None:
    all_lons, all_lats = [], []
    park_entries = []
    for park in parks:
        boxes = []
        for area in park["areas"]:
            bbox = ring_bbox(area["outer"])
            boxes.append([round(v, 6) for v in bbox])
            all_lons += [bbox[0], bbox[2]]
            all_lats += [bbox[1], bbox[3]]
        park_entries.append({"file": park["file"], "name": park["name"],
                             "areas": len(park["areas"]), "bboxes": boxes})
    manifest = {
        "format": "mbtiles",
        "file": MBTILES_NAME,
        "build_id": build_id,
        "created_utc": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "source": source,
        "min_zoom": info["min_zoom"],
        "max_zoom": info["max_zoom"],
        "tile_compression": info["compression"],
        "tile_count": info["tile_count"],
        "size_bytes": size_bytes,
        "buffer_m": buffer_m,
        "bounds": [round(min(all_lons), 6), round(min(all_lats), 6),
                   round(max(all_lons), 6), round(max(all_lats), 6)],
        "parks": park_entries,
        "attribution": ATTRIBUTION,
        "theme": THEME_FILE.name,
    }
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #

def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the bundled offline Protomaps basemap.")
    parser.add_argument("--source", help="Protomaps .pmtiles URL or local path "
                                         "(default: newest daily build)")
    parser.add_argument("--buffer-m", type=float, default=DEFAULT_BUFFER_M,
                        help=f"map margin around each park area in metres (default {DEFAULT_BUFFER_M:g})")
    parser.add_argument("--minzoom", type=int, default=DEFAULT_MINZOOM)
    parser.add_argument("--maxzoom", type=int, default=DEFAULT_MAXZOOM,
                        help="highest zoom with data (Protomaps max is 15; the app overzooms to 24)")
    parser.add_argument("--pmtiles-cli", help="path to the pmtiles binary (default: from PATH)")
    parser.add_argument("--parks-dir", type=Path, default=PARKS_DIR)
    parser.add_argument("--dry-run", action="store_true",
                        help="only report what would be extracted; writes nothing to assets/")
    parser.add_argument("--keep-pmtiles", action="store_true",
                        help="keep build/map/basemap.pmtiles (handy for viewing on pmtiles.io)")
    args = parser.parse_args(argv)
    if not 0 <= args.minzoom <= args.maxzoom <= 15:
        parser.error("zoom range must satisfy 0 <= minzoom <= maxzoom <= 15")
    if args.buffer_m < 0:
        parser.error("--buffer-m must be >= 0")
    return args


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    print("=" * 64)
    print("User Navigation Companion - offline basemap build (Protomaps)")
    print("=" * 64)

    parks = load_parks(args.parks_dir)
    print(f"\nParks ({len(parks)}):")
    for park in parks:
        print(f"  {park['file']}: '{park['name']}', {len(park['areas'])} area(s)")
        for index, area in enumerate(park["areas"]):
            bbox = ring_bbox(area["outer"])
            print(f"     area {index + 1}: {ring_area_km2(area['outer']):.2f} km2, "
                  f"{len(area['holes'])} hole(s), bbox {tuple(round(v, 5) for v in bbox)}")
        if park["ignored_features"]:
            print(f"     note: {park['ignored_features']} non-polygon feature(s) ignored")

    WORK_DIR.mkdir(parents=True, exist_ok=True)
    region_path = WORK_DIR / "region.geojson"
    region_path.write_text(json.dumps(build_region(parks, args.buffer_m)), encoding="utf-8")
    print(f"\nExtraction region: {region_path.relative_to(ROOT)} "
          f"(park bounding boxes + {args.buffer_m:g} m)")

    cli = find_pmtiles_cli(args.pmtiles_cli)
    if args.source:
        source = args.source
        if not source.startswith(("http://", "https://")):
            source_path = Path(source).expanduser()
            if not source_path.exists():
                raise BuildError(f"--source file not found: {source_path}")
            source = str(source_path)
    else:
        print("\nLooking for the newest Protomaps daily build:")
        source = find_latest_build(LOOKBACK_DAYS)

    pmtiles_path = WORK_DIR / "basemap.pmtiles"
    print(f"\nExtracting z{args.minzoom}-z{args.maxzoom} from {source}")
    run_extract(cli, source, region_path, pmtiles_path, args.minzoom, args.maxzoom, args.dry_run)
    if args.dry_run:
        print("\nDry run finished; nothing was written to assets/.")
        return 0

    print("\nConverting to MBTiles ...")
    tmp_mbtiles = WORK_DIR / MBTILES_NAME
    convert_to_mbtiles(pmtiles_path, tmp_mbtiles)
    info = inspect_mbtiles(tmp_mbtiles)
    for row in info["per_zoom"]:
        print(f"  z{row['zoom']:>2}: {row['tiles']:>6} tiles, {row['bytes'] / 1024:>9.1f} KiB")
    print(f"  tile compression: {info['compression']}")

    problems = check_coverage(tmp_mbtiles, parks, info["max_zoom"])
    for problem in problems:
        print(f"  WARNING: {problem}")

    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    final_mbtiles = ASSET_DIR / MBTILES_NAME
    shutil.move(str(tmp_mbtiles), final_mbtiles)
    size_bytes = final_mbtiles.stat().st_size
    build_id = sha256_of(final_mbtiles)[:16]
    write_manifest(ASSET_DIR / MANIFEST_NAME, build_id=build_id, source=source, parks=parks,
                   info=info, buffer_m=args.buffer_m, size_bytes=size_bytes)
    if not args.keep_pmtiles and pmtiles_path.exists():
        pmtiles_path.unlink()

    print("\nWrote:")
    print(f"  {final_mbtiles.relative_to(ROOT)}  ({size_bytes / 1048576:.1f} MiB)")
    print(f"  {(ASSET_DIR / MANIFEST_NAME).relative_to(ROOT)}  (build_id {build_id})")
    if not THEME_FILE.exists():
        print(f"  WARNING: {THEME_FILE.relative_to(ROOT)} is missing - the app needs it to draw the map")
    if LEGACY_TILE_DIR.exists():
        print(f"  NOTE: {LEGACY_TILE_DIR.relative_to(ROOT)}/ is no longer used; "
              "run tools/remove_obsolete_files.sh")
    print("\nNext: flutter build apk --release --target-platform android-arm64")
    print(f"Attribution shown in the app: {ATTRIBUTION}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except BuildError as error:
        print(f"\nERROR: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(130)

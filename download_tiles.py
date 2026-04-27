#!/usr/bin/env python3
"""
Map Tile Downloader for Park Areas
Downloads OSM and OpenTopoMap tiles for park boundaries and saves them to a local cache.

Tile usage policy compliance (OpenStreetMap & OpenTopoMap):
  - At most one HTTP request per second (enforced below).
  - A non-generic User-Agent and Referer identifying this application (not stock library defaults).
  - Attribution must be shown in the mobile app UI for end users; this script prints it here for operators.

Licensing: OpenStreetMap data is © OpenStreetMap contributors, ODbL. Derivative databases and
larger extractions may need to be shared under ODbL; see https://www.openstreetmap.org/copyright
and https://opentopomap.org/ for OpenTopoMap. Small offline caches for personal/field use are
often considered fair use—verify for your deployment.
"""

import os
import sys
import json
import math
import time
import sqlite3
import urllib.request
from pathlib import Path
from typing import List, Tuple

# Configuration
PARKS_DIR = "parks"
OUTPUT_DIR = "assets/tiles"
MIN_ZOOM = 14  # Overview level
MAX_ZOOM = 18  # Detailed navigation level (OSM)

# OpenTopoMap only provides tiles up to zoom 17; z>=18 returns HTTP 403.
MAX_ZOOM_TOPO = 17

# Tile servers
OSM_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
TOPO_URL = "https://tile.opentopomap.org/{z}/{x}/{y}.png"

# Minimum seconds between successive HTTP requests (tile policy: max ~1 request / second).
MIN_SECONDS_BETWEEN_REQUESTS = 1.0

# Application identity — must NOT be a generic urllib / Python default.
# Override referer if you publish a public app or repo URL (OSM/OTM ask for identifiable clients).
_APP_VERSION = "1.0"
APP_USER_AGENT = (
    f"UserCompanionNavigationApp/{_APP_VERSION} "
    f"(offline tile prefetch; field navigation app; "
    f"policy: https://operations.osmfoundation.org/policies/tiles/)"
)
# Per-provider Referer (CDNs often expect the matching site; policy pages can trigger blocks).
# Override with TILE_REFERER_OSM / _TOPO if needed.
def _http_headers_for(url_template: str) -> dict:
    if "opentopomap" in url_template.lower():
        referer = os.environ.get(
            "TILE_REFERER_TOPO",
            "https://www.opentopomap.org/",
        )
    else:
        referer = os.environ.get(
            "TILE_REFERER_OSM",
            "https://www.openstreetmap.org/",
        )
    return {
        "User-Agent": APP_USER_AGENT,
        "Referer": referer,
        "Accept": "image/png,*/*;q=0.8",
    }


def write_tile_zoom_config(output_dir: Path) -> None:
    """Write zoom limits for the Flutter app (see assets/tiles/tile_zoom_config.json)."""
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / "tile_zoom_config.json"
    cfg = {
        "min_zoom": MIN_ZOOM,
        "max_zoom_osm": MAX_ZOOM,
        "max_zoom_topo": MAX_ZOOM_TOPO,
        "source": "download_tiles.py",
    }
    with open(path, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
        f.write("\n")
    print(
        f"Wrote {path} "
        f"(min_zoom={MIN_ZOOM}, max_zoom_osm={MAX_ZOOM}, max_zoom_topo={MAX_ZOOM_TOPO})"
    )


def print_attribution_banner() -> None:
    print()
    print("— Attribution (display comparable text in the app for end users) —")
    print("  OpenStreetMap: © OpenStreetMap contributors — https://www.openstreetmap.org/copyright")
    print("  OpenTopoMap: © OpenTopoMap contributors — https://opentopomap.org/")
    print("  Data licensed under ODbL where applicable; share-alike may apply to substantial extracts.")
    print("—" * 60)


class TileDownloader:
    def __init__(self, output_dir: str):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)
        self._last_http_at: float = 0.0

        self.osm_db = self._init_db("osm_tiles.db")
        self.topo_db = self._init_db("topo_tiles.db")

    def _throttle_before_http(self) -> None:
        """Enforce at most one request per second (minimum delay between outbound requests)."""
        now = time.monotonic()
        elapsed = now - self._last_http_at
        wait = MIN_SECONDS_BETWEEN_REQUESTS - elapsed
        if wait > 0:
            time.sleep(wait)

    def _mark_http_done(self) -> None:
        self._last_http_at = time.monotonic()

    def _init_db(self, db_name: str) -> sqlite3.Connection:
        """Initialize SQLite database for tile storage"""
        db_path = self.output_dir / db_name
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()

        cursor.execute(
            """
            CREATE TABLE IF NOT EXISTS tiles (
                zoom INTEGER,
                x INTEGER,
                y INTEGER,
                data BLOB,
                PRIMARY KEY (zoom, x, y)
            )
        """
        )

        cursor.execute(
            """
            CREATE INDEX IF NOT EXISTS idx_tiles ON tiles(zoom, x, y)
        """
        )

        conn.commit()
        return conn

    def lat_lon_to_tile(self, lat: float, lon: float, zoom: int) -> Tuple[int, int]:
        """Convert lat/lon to tile coordinates"""
        lat_rad = math.radians(lat)
        n = 2.0**zoom
        x = int((lon + 180.0) / 360.0 * n)
        y = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
        return x, y

    def get_bounds(self, coordinates: List[List[float]]) -> dict:
        """Get min/max lat/lon from polygon coordinates"""
        lats = [coord[1] for coord in coordinates]
        lons = [coord[0] for coord in coordinates]

        return {
            "min_lat": min(lats),
            "max_lat": max(lats),
            "min_lon": min(lons),
            "max_lon": max(lons),
        }

    def download_tile(self, url: str, zoom: int, x: int, y: int, db: sqlite3.Connection) -> bool:
        """Download a single tile and save to database"""
        cursor = db.cursor()
        cursor.execute("SELECT data FROM tiles WHERE zoom=? AND x=? AND y=?", (zoom, x, y))
        if cursor.fetchone():
            return True  # Already downloaded — no network request, no throttle

        self._throttle_before_http()
        try:
            tile_url = url.format(z=zoom, x=x, y=y)
            req = urllib.request.Request(tile_url, headers=_http_headers_for(url))

            with urllib.request.urlopen(req, timeout=60) as response:
                tile_data = response.read()

            cursor.execute(
                "INSERT OR REPLACE INTO tiles (zoom, x, y, data) VALUES (?, ?, ?, ?)",
                (zoom, x, y, tile_data),
            )
            db.commit()
            self._mark_http_done()
            return True

        except Exception as e:
            self._mark_http_done()
            print(f"  Error downloading tile {zoom}/{x}/{y}: {e}")
            return False

    def download_park_tiles(self, park_name: str, bounds: dict):
        """Download all tiles for a park area"""
        print(f"\nDownloading tiles for {park_name}")
        print(f"  Bounds: {bounds}")

        total_tiles = 0
        downloaded = 0

        for zoom in range(MIN_ZOOM, MAX_ZOOM + 1):
            min_tile_x, max_tile_y = self.lat_lon_to_tile(bounds["min_lat"], bounds["min_lon"], zoom)
            max_tile_x, min_tile_y = self.lat_lon_to_tile(bounds["max_lat"], bounds["max_lon"], zoom)

            tiles_at_zoom = (max_tile_x - min_tile_x + 1) * (max_tile_y - min_tile_y + 1)
            total_tiles += tiles_at_zoom  # OSM
            if zoom <= MAX_ZOOM_TOPO:
                total_tiles += tiles_at_zoom  # Topo (only where served)

            topo_note = ""
            if zoom > MAX_ZOOM_TOPO:
                topo_note = f" (OpenTopoMap skipped: max zoom {MAX_ZOOM_TOPO})"

            print(f"  Zoom {zoom}: {tiles_at_zoom} tiles per layer{topo_note}")

            for x in range(min_tile_x, max_tile_x + 1):
                for y in range(min_tile_y, max_tile_y + 1):
                    if self.download_tile(OSM_URL, zoom, x, y, self.osm_db):
                        downloaded += 1

            if zoom <= MAX_ZOOM_TOPO:
                for x in range(min_tile_x, max_tile_x + 1):
                    for y in range(min_tile_y, max_tile_y + 1):
                        if self.download_tile(TOPO_URL, zoom, x, y, self.topo_db):
                            downloaded += 1

        print(f"  Downloaded (new or existing in DB): {downloaded} tile positions / {total_tiles} planned")

    def process_park_file(self, geojson_path: Path):
        """Process a park GeoJSON file and download its tiles"""
        try:
            with open(geojson_path, "r", encoding="utf-8") as f:
                data = json.load(f)

            park_name = geojson_path.stem

            features = data.get("features", [])
            if not features:
                print(f"No features found in {park_name}")
                return

            geometry = features[0]["geometry"]
            if geometry["type"] != "Polygon":
                print(f"Not a polygon: {park_name}")
                return

            coordinates = geometry["coordinates"][0]
            bounds = self.get_bounds(coordinates)

            self.download_park_tiles(park_name, bounds)

        except Exception as e:
            print(f"Error processing {geojson_path}: {e}")

    def close(self):
        """Close database connections"""
        self.osm_db.close()
        self.topo_db.close()


def main():
    print("=" * 60)
    print("Map Tile Downloader for Parks")
    print("=" * 60)
    write_tile_zoom_config(Path(OUTPUT_DIR))
    print_attribution_banner()
    print("HTTP User-Agent:")
    print(f"  {APP_USER_AGENT}")
    print("HTTP Referer (OSM):  https://www.openstreetmap.org/ (override: TILE_REFERER_OSM)")
    print("HTTP Referer (Topo): https://www.opentopomap.org/ (override: ILE_REFERER_TOPO)")
    print(f"OpenTopoMap:    only zoom ≤ {MAX_ZOOM_TOPO} (higher zooms are not served — avoids HTTP 403)")
    print(f"Rate limit:      ≥ {MIN_SECONDS_BETWEEN_REQUESTS}s between HTTP requests")
    print()

    downloader = TileDownloader(OUTPUT_DIR)

    parks_dir = Path(PARKS_DIR)
    park_files = list(parks_dir.glob("*.geojson"))

    if not park_files:
        print(f"No GeoJSON files found in {PARKS_DIR}/")
        return

    print(f"Found {len(park_files)} park(s)")
    print(f"Zoom levels: {MIN_ZOOM} to {MAX_ZOOM}")
    print(f"Output directory: {OUTPUT_DIR}/")

    for park_file in sorted(park_files):
        downloader.process_park_file(park_file)

    print("\n" + "=" * 60)
    print("Download Complete!")
    print_attribution_banner()

    osm_db_path = Path(OUTPUT_DIR) / "osm_tiles.db"
    topo_db_path = Path(OUTPUT_DIR) / "topo_tiles.db"

    if osm_db_path.exists():
        osm_size = osm_db_path.stat().st_size / (1024 * 1024)
        print(f"OSM tiles DB: {osm_size:.2f} MB")

    if topo_db_path.exists():
        topo_size = topo_db_path.stat().st_size / (1024 * 1024)
        print(f"Topo tiles DB: {topo_size:.2f} MB")

    print("=" * 60)

    downloader.close()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Diagnose which tiles in the bundled tile DBs are OSM "Access blocked"
warning PNGs vs. real map tiles.

Real tiles all have unique bytes. Blocked tiles are the same image repeated
for every (z, x, y) — so a hash count instantly reveals them.

Run from project root:
    python3 inspect_tiles.py
"""
import hashlib
import sqlite3
from collections import Counter
from pathlib import Path

DBS = ["assets/tiles/osm_tiles.db", "assets/tiles/topo_tiles.db"]


def inspect(db_path: str) -> None:
    p = Path(db_path)
    if not p.exists():
        print(f"\n[skip] {db_path} not found")
        return

    print(f"\n=== {db_path} ===")
    conn = sqlite3.connect(db_path)
    rows = conn.execute("SELECT zoom, x, y, data FROM tiles").fetchall()
    total = len(rows)
    print(f"Total tiles in DB: {total}")

    hashes: Counter = Counter()
    sample_by_hash: dict[str, tuple] = {}
    for z, x, y, data in rows:
        h = hashlib.sha256(data).hexdigest()[:12]
        hashes[h] += 1
        sample_by_hash.setdefault(h, (z, x, y, len(data), data))

    unique = len(hashes)
    print(f"Unique tile contents: {unique}  ({unique/total*100:.1f}% unique)")
    print("Top repeated hashes (real tiles repeat rarely; blocked tiles repeat A LOT):")
    for h, count in hashes.most_common(5):
        z, x, y, size, _ = sample_by_hash[h]
        flag = "  <-- LIKELY BLOCKED" if count > 10 else ""
        print(f"  hash={h} count={count:>5} size={size}B  example z={z} x={x} y={y}{flag}")

    # Dump the most-repeated tile so you can eyeball it
    top_hash, top_count = hashes.most_common(1)[0]
    if top_count > 10:
        out = p.with_name(f"{p.stem}_top_repeat.png")
        out.write_bytes(sample_by_hash[top_hash][4])
        print(f"Saved most-repeated tile to: {out}  (open it — is it the warning image?)")

    # By-zoom breakdown
    print("Per-zoom tile counts:")
    z_counter: Counter = Counter()
    for z, _x, _y, _data in rows:
        z_counter[z] += 1
    for z in sorted(z_counter):
        print(f"  z={z}: {z_counter[z]} tiles")

    conn.close()


def main() -> None:
    for db in DBS:
        inspect(db)
    print("\nDone.")


if __name__ == "__main__":
    main()
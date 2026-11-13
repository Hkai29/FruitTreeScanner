#!/usr/bin/env python3
"""Seed the iOS simulator with synthetic orchard scan fixtures for UI review.

These fixtures exist only so the rebuilt interface can be reviewed with data in
it. They are NOT LiDAR captures and NOT yield evidence: every generated PLY
carries `comment not_app_lidar_or_yield_evidence` in its header, and the
generator prints that disclaimer with its output.

The point clouds are synthetic tree shapes (trunk + ellipsoid canopy) written in
the app's ASCII PLY dialect. Companion `<id>_result.json` files carry the
record metadata the archive list reads.

Usage:
    python3 tools/seed_ui_review_fixtures.py --simulator <UDID> [--trees 8]
"""
from __future__ import annotations

import argparse
import json
import math
import random
import shutil
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

DEVELOPER_DIR = "/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer"
BUNDLE_ID = "com.hkai29.fruitscanner"
POINTS_PER_TREE = 20000
DISCLAIMER = "not_app_lidar_or_yield_evidence"

# A small orchard block so the map has a real spatial cluster.
BASE_LAT = 35.7600
BASE_LON = 109.4400

TREE_IDS = [
    "A-01", "A-02", "A-03", "A-04",
    "B-01", "B-02", "B-03", "B-04",
]

FRUIT_TYPES = ["apple", "apple", "apple", "pear"]
CONFIDENCES = ["high", "high", "high", "medium", "high", "manual_review", "high", "medium"]


def build_tree_points(rng: random.Random, height_m: float, spread_m: float):
    """Trunk plus ellipsoid canopy, in the app's coordinate frame (y is up)."""
    points = []
    trunk_height = height_m * 0.46
    trunk_radius = 0.06 + spread_m * 0.05
    trunk_count = int(POINTS_PER_TREE * 0.06)
    canopy_count = POINTS_PER_TREE - trunk_count

    for _ in range(trunk_count):
        angle = rng.uniform(0, math.tau)
        radius = trunk_radius * math.sqrt(rng.random())
        points.append((
            radius * math.cos(angle),
            rng.uniform(0, trunk_height),
            radius * math.sin(angle),
            (108, 76, 52),
        ))

    canopy_center_y = trunk_height + (height_m - trunk_height) * 0.52
    canopy_radius_y = (height_m - trunk_height) * 0.48
    canopy_radius_xz = spread_m * 0.5
    for _ in range(canopy_count):
        # Uniform inside an ellipsoid.
        while True:
            x = rng.uniform(-1, 1)
            y = rng.uniform(-1, 1)
            z = rng.uniform(-1, 1)
            if x * x + y * y + z * z <= 1.0:
                break
        # Slight vertical squash at the top of the crown.
        px = x * canopy_radius_xz
        py = canopy_center_y + y * canopy_radius_y * (1.0 - 0.18 * max(0.0, y))
        pz = z * canopy_radius_xz
        green = 96 + int(rng.random() * 58)
        points.append((px, py, pz, (52 + green // 5, green, 44 + green // 4)))

    return points


def write_ply(path: Path, tree_id: str, scan_date: datetime, points, source: str,
              gps_lat: float = 0.0, gps_lon: float = 0.0) -> None:
    lines = [
        "ply",
        "format ascii 1.0",
        f"comment tree_id {tree_id}",
        f"comment source {source}",
        f"comment {DISCLAIMER}",
        f"element vertex {len(points)}",
        "property float x",
        "property float y",
        "property float z",
        "property uchar red",
        "property uchar green",
        "property uchar blue",
        f"comment scan_date {scan_date.strftime('%Y-%m-%d %H:%M:%S')}",
        f"comment gps_lat {gps_lat:.6f}",
        f"comment gps_lon {gps_lon:.6f}",
        "end_header",
    ]
    body = [
        f"{x:.4f} {y:.4f} {z:.4f} {r} {g} {b}"
        for (x, y, z, (r, g, b)) in points
    ]
    path.write_text("\n".join(lines + body) + "\n", encoding="utf-8")


def write_result(path: Path, fruit_count: int, yield_kg: float, fruit_type: str, confidence: str) -> None:
    path.write_text(
        json.dumps(
            {
                "fruitCount": fruit_count,
                "yieldKg": yield_kg,
                "fruitType": fruit_type,
                "confidence": confidence,
            },
            ensure_ascii=False,
            indent=1,
        ),
        encoding="utf-8",
    )


def container_path(simulator: str) -> Path:
    result = subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", simulator, BUNDLE_ID, "data"],
        env={"DEVELOPER_DIR": DEVELOPER_DIR, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"},
    )
    return Path(result.decode().strip())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator", required=True)
    parser.add_argument("--trees", type=int, default=8)
    parser.add_argument("--seed", type=int, default=20261019)
    args = parser.parse_args()

    root = container_path(args.simulator)
    scans = root / "Documents" / "scans"
    scans.mkdir(parents=True, exist_ok=True)

    # Keep anything already there: move it aside instead of deleting it.
    leftovers = [p for p in scans.iterdir() if p.is_file()]
    if leftovers:
        archive = root / "Documents" / f"scans-archive-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
        archive.mkdir(parents=True, exist_ok=True)
        for item in leftovers:
            shutil.move(str(item), str(archive / item.name))
        print(f"archived {len(leftovers)} pre-existing file(s) to {archive}")

    rng = random.Random(args.seed)
    # 让记录落在最近几天，并保证“今天”也有记录，这样首页的今日读数是真值。
    today = datetime.now().replace(hour=8, minute=30, second=0, microsecond=0)
    base_date = today - timedelta(days=8)
    written = 0

    for index in range(args.trees):
        tree_id = TREE_IDS[index % len(TREE_IDS)]
        scan_date = base_date + timedelta(days=index % 8, hours=2 * index, minutes=17 * index)
        height_m = 3.4 + rng.random() * 1.6
        spread_m = 2.2 + rng.random() * 1.8
        fruit_type = FRUIT_TYPES[index % len(FRUIT_TYPES)]
        confidence = CONFIDENCES[index % len(CONFIDENCES)]
        fruit_count = int(60 + rng.random() * 180)
        yield_kg = round(fruit_count * (0.07 + rng.random() * 0.05), 1)

        # 评审夹具的坐标：铺开成几百米，点位在地图上才分得开（合成坐标，不是现场测量）。
        lat = BASE_LAT + (index % 4) * 0.0032 + rng.uniform(-0.0004, 0.0004)
        lon = BASE_LON + (index // 4) * 0.0038 + rng.uniform(-0.0004, 0.0004)

        scan_id = f"{tree_id}_{scan_date.strftime('%Y%m%d_%H%M%S')}_lat{lat:.4f}_lon{lon:.4f}"
        ply_path = scans / f"{scan_id}.ply"
        result_path = scans / f"{scan_id}_result.json"

        points = build_tree_points(rng, height_m, spread_m)
        write_ply(
            ply_path,
            tree_id,
            scan_date,
            points,
            "UI design review synthetic fixture (not a device capture)",
            gps_lat=lat,
            gps_lon=lon,
        )
        write_result(result_path, fruit_count, yield_kg, fruit_type, confidence)
        written += 1

    # A second visit to one tree, so the archive can show a per-tree history.
    tree_id = TREE_IDS[0]
    scan_date = base_date + timedelta(days=8, hours=3)
    lat = BASE_LAT + 0.00001
    lon = BASE_LON + 0.00002
    scan_id = f"{tree_id}_{scan_date.strftime('%Y%m%d_%H%M%S')}_lat{lat:.4f}_lon{lon:.4f}"
    points = build_tree_points(rng, 4.3, 3.1)
    write_ply(
        scans / f"{scan_id}.ply",
        tree_id,
        scan_date,
        points,
        "UI design review synthetic fixture (not a device capture)",
        gps_lat=lat,
        gps_lon=lon,
    )
    write_result(scans / f"{scan_id}_result.json", 214, 24.6, "apple", "high")
    written += 1

    print(f"wrote {written} synthetic scan record(s) into {scans}")
    print(f"DISCLAIMER: every generated PLY is a synthetic UI fixture ({DISCLAIMER}).")
    print("             It is not a LiDAR capture and must not be read as yield evidence.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

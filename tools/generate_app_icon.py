#!/usr/bin/env python3
"""Generate the app / launch icon in the instrument design language.

The previous artwork was a cartoon tree with apples on a green field — a generic
consumer-app mark that does not describe what this app does. The replacement is
a **LiDAR point cloud of a tree**: a trunk plus a crown built from discrete
points, the same way the app actually measures a tree. Signal teal on the
instrument canvas.

Output:
  FruitTreeScanner/Assets.xcassets/AppIcon.appiconset/AppIcon.png   (1024x1024)
  FruitTreeScanner/Assets.xcassets/LaunchIcon.imageset/launch-icon.png (1024x1024)
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
CANVAS = (14, 18, 20)          # #0E1214 instrument canvas
SIGNAL = (23, 178, 196)        # #17B2C4 LiDAR signal
SIGNAL_SOFT = (58, 150, 163)
TRUNK = (150, 108, 72)
SIZE = 1024


def draw_point_cloud(seed: int = 20261019) -> Image.Image:
    rng = random.Random(seed)
    image = Image.new("RGB", (SIZE, SIZE), CANVAS)
    draw = ImageDraw.Draw(image)

    # --- backdrop: a faint depth grid, the same language as the survey plate ---
    grid = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(grid)
    for x in range(0, SIZE, 64):
        gdraw.line([(x, 0), (x, SIZE)], fill=(255, 255, 255, 12), width=1)
    for y in range(0, SIZE, 64):
        gdraw.line([(0, y), (SIZE, y)], fill=(255, 255, 255, 12), width=1)
    image = Image.alpha_composite(image.convert("RGBA"), grid).convert("RGB")
    draw = ImageDraw.Draw(image)

    # --- the tree, in metres, mapped to the canvas ---
    scale = SIZE / 5.6           # a 5.6 m tall tree fills the icon
    origin_x = SIZE * 0.5
    ground_y = SIZE * 0.845

    def to_canvas(x_m: float, y_m: float) -> tuple[int, int]:
        return int(origin_x + x_m * scale), int(ground_y - y_m * scale)

    # trunk
    trunk_points = []
    trunk_h = 1.95
    for _ in range(2600):
        t = rng.random() ** 0.85
        y = t * trunk_h
        r = 0.115 * (1.0 - 0.45 * t)
        a = rng.uniform(0, math.tau)
        r_actual = r * math.sqrt(rng.random())
        trunk_points.append(to_canvas(
            math.cos(a) * r_actual,
            y + rng.gauss(0, 0.012)
        ))

    # crown: several overlapping lobes, so the silhouette is an irregular
    # tree crown rather than a smooth ball.
    crown_points = []
    cy = trunk_h + 0.95
    lobes = [
        # (dx, dy, dz, rx, ry, rz, weight)
        (0.00, 0.10, 0.00, 1.16, 0.94, 1.14, 0.34),
        (0.62, -0.22, 0.30, 0.86, 0.72, 0.84, 0.22),
        (-0.58, -0.10, -0.34, 0.92, 0.80, 0.86, 0.22),
        (0.10, 0.46, -0.22, 0.78, 0.66, 0.74, 0.12),
        (-0.18, -0.46, 0.28, 0.72, 0.58, 0.70, 0.10),
    ]
    for _ in range(26000):
        lobe = rng.choices(lobes, weights=[l[6] for l in lobes])[0]
        dx, dy, dz, rx, ry, rz, _ = lobe
        while True:
            x, y, z = (rng.uniform(-1, 1) for _ in range(3))
            if x * x + y * y + z * z <= 1.0:
                break
        px = dx + x * rx
        py = cy + dy + y * ry
        pz = dz + z * rz
        crown_points.append(to_canvas(px, py))

    # ground points
    ground_points = []
    for _ in range(2200):
        a = rng.uniform(0, math.tau)
        r = 1.55 * math.sqrt(rng.random())
        ground_points.append(to_canvas(math.cos(a) * r, rng.gauss(0, 0.02)))

    # --- render points with a soft glow, densest at the silhouette ---
    glow = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    for x, y in crown_points:
        gdraw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=SIGNAL)
    for x, y in trunk_points:
        gdraw.ellipse((x - 3, y - 3, x + 3, y + 3), fill=TRUNK)
    glow = glow.filter(ImageFilter.GaussianBlur(14))
    image = Image.blend(image, Image.blend(image, glow, 0.0), 0.0)
    image = Image.composite(
        Image.new("RGB", (SIZE, SIZE), (0, 0, 0)),
        image,
        Image.new("L", (SIZE, SIZE), 0),
    ) if False else image
    # additive-ish blend of the glow
    base = image.load()
    glow_px = glow.load()
    for y in range(SIZE):
        for x in range(SIZE):
            br, bg, bb = base[x, y]
            gr, gg, gb = glow_px[x, y]
            base[x, y] = (min(255, br + gr // 3), min(255, bg + gg // 3), min(255, bb + gb // 3))

    draw = ImageDraw.Draw(image)
    for x, y in crown_points:
        shade = rng.randint(-16, 16)
        colour = (
            max(0, min(255, SIGNAL[0] + shade)),
            max(0, min(255, SIGNAL[1] + shade)),
            max(0, min(255, SIGNAL[2] + shade)),
        )
        draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=colour)
    for x, y in trunk_points:
        shade = rng.randint(-18, 18)
        colour = (
            max(0, min(255, TRUNK[0] + shade)),
            max(0, min(255, TRUNK[1] + shade)),
            max(0, min(255, TRUNK[2] + shade)),
        )
        draw.ellipse((x - 2, y - 2, x + 2, y + 2), fill=colour)
    for x, y in ground_points:
        draw.ellipse((x - 1, y - 1, x + 1, y + 1), fill=SIGNAL_SOFT)

    # --- a scale bar, because this is a measurement instrument ---
    bar_m = 1.0
    bar_px = int(bar_m * scale)
    bx0 = int(SIZE * 0.5 - bar_px / 2)
    bx1 = int(SIZE * 0.5 + bar_px / 2)
    by = int(SIZE * 0.90)
    draw.line([(bx0, by), (bx1, by)], fill=(150, 200, 208), width=3)
    draw.line([(bx0, by - 8), (bx0, by + 8)], fill=(150, 200, 208), width=3)
    draw.line([(bx1, by - 8), (bx1, by + 8)], fill=(150, 200, 208), width=3)

    return image


def main() -> int:
    image = draw_point_cloud()
    app_icon = ROOT / "FruitTreeScanner" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    launch_icon = ROOT / "FruitTreeScanner" / "Assets.xcassets" / "LaunchIcon.imageset" / "launch-icon.png"
    app_icon.parent.mkdir(parents=True, exist_ok=True)
    launch_icon.parent.mkdir(parents=True, exist_ok=True)
    image.save(app_icon)
    image.save(launch_icon)
    print(f"wrote {app_icon}")
    print(f"wrote {launch_icon}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

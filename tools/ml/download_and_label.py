#!/usr/bin/env python3
"""
Download fruit images and auto-label them using the trained YOLOv8 model.
Creates pseudo-labels for 9 missing fruit types.
"""

import os
import sys
from pathlib import Path

MISSING_FRUITS = {
    "pomelo":       {"id": 3,  "queries": ["pomelo fruit", "柚子", "grapefruit pomelo"]},
    "plum":         {"id": 11, "queries": ["plum fruit", "李子", "fresh plum"]},
    "pomegranate":  {"id": 12, "queries": ["pomegranate fruit", "石榴", "pomegranate whole"]},
    "loquat":       {"id": 13, "queries": ["loquat fruit", "枇杷", "loquat on tree"]},
    "lychee":       {"id": 14, "queries": ["lychee fruit", "荔枝", "lychee on tree"]},
    "longan":       {"id": 15, "queries": ["longan fruit", "龙眼", "longan on tree"]},
    "bayberry":     {"id": 16, "queries": ["bayberry fruit", "杨梅", "waxberry fruit"]},
    "hawthorn":     {"id": 18, "queries": ["hawthorn fruit", "山楂", "hawthorn berry"]},
    "chestnut":     {"id": 21, "queries": ["chestnut fruit", "板栗", "chestnut on tree"]},
}

REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_DIR = REPO_ROOT / "ml" / "datasets" / "fruit_dataset_26"
MODEL_PATH = REPO_ROOT / "ml" / "training-runs" / "yolo" / "detect" / "runs" / "fruit_26_nano" / "weights" / "best.pt"
DOWNLOAD_DIR = REPO_ROOT / "ml" / "downloaded_fruits"


def download_images():
    print("=" * 60)
    print("Step 1: Downloading fruit images")
    print("=" * 60)

    from bing_image_downloader import downloader

    for fruit_name, info in MISSING_FRUITS.items():
        fruit_dir = os.path.join(DOWNLOAD_DIR, fruit_name)
        os.makedirs(fruit_dir, exist_ok=True)

        for query in info["queries"]:
            try:
                print(f"  Downloading: {query} -> {fruit_dir}")
                downloader.download(
                    query,
                    limit=60,
                    output_dir=fruit_dir,
                    adult_filter_off=True,
                    force_replace=False,
                    timeout=10,
                )
            except Exception as e:
                print(f"  Warning: {e}")
                continue

        count = len([f for f in os.listdir(fruit_dir) if f.lower().endswith(('.jpg', '.jpeg', '.png'))])
        print(f"  {fruit_name}: {count} images downloaded")

    print("Download complete!")


def auto_label():
    print("\n" + "=" * 60)
    print("Step 2: Auto-labeling with YOLOv8 (pseudo-labeling)")
    print("=" * 60)

    from ultralytics import YOLO
    from PIL import Image
    import shutil

    model = YOLO(str(MODEL_PATH))

    for fruit_name, info in MISSING_FRUITS.items():
        class_id = info["id"]
        fruit_dir = os.path.join(DOWNLOAD_DIR, fruit_name)

        all_images = []
        for root, dirs, files in os.walk(fruit_dir):
            for f in files:
                if f.lower().endswith(('.jpg', '.jpeg', '.png')):
                    all_images.append(os.path.join(root, f))

        print(f"\n  Processing {fruit_name} (class_id={class_id}): {len(all_images)} images")

        labeled_count = 0
        for img_path in all_images:
            try:
                img = Image.open(img_path)
                if img.size[0] < 100 or img.size[1] < 100:
                    continue

                results = model(img_path, conf=0.15, verbose=False)

                if len(results) > 0 and len(results[0].boxes) > 0:
                    boxes = results[0].boxes
                    w, h = img.size
                    label_lines = []
                    for box in boxes:
                        x1, y1, x2, y2 = box.xyxy[0].tolist()
                        cx = ((x1 + x2) / 2) / w
                        cy = ((y1 + y2) / 2) / h
                        bw = (x2 - x1) / w
                        bh = (y2 - y1) / h
                        if bw > 0.01 and bh > 0.01:
                            label_lines.append(f"{class_id} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}\n")

                    if label_lines:
                        base = os.path.splitext(os.path.basename(img_path))[0]
                        dst_img = os.path.join(OUTPUT_DIR, "images", "train", f"{fruit_name}_{base}.jpg")
                        dst_lbl = os.path.join(OUTPUT_DIR, "labels", "train", f"{fruit_name}_{base}.txt")

                        if not os.path.exists(dst_img):
                            img.convert("RGB").save(dst_img, "JPEG")
                            with open(dst_lbl, 'w') as f:
                                f.writelines(label_lines)
                            labeled_count += 1
            except Exception as e:
                continue

        print(f"  {fruit_name}: {labeled_count} images auto-labeled")

    print("\nAuto-labeling complete!")


def update_yaml():
    print("\n" + "=" * 60)
    print("Step 3: Verifying dataset")
    print("=" * 60)

    from collections import Counter

    FRUIT_CLASSES_26 = [
        "apple", "orange", "mandarin", "pomelo", "pear", "peach", "cherry", "grape",
        "persimmon", "mango", "kiwi", "plum", "pomegranate", "loquat", "lychee",
        "longan", "bayberry", "jujube", "hawthorn", "fig", "papaya", "chestnut",
        "mulberry", "blueberry", "strawberry", "coconut",
    ]

    class_counts = Counter()
    for split in ["train", "val"]:
        lbl_dir = os.path.join(OUTPUT_DIR, "labels", split)
        if not os.path.exists(lbl_dir):
            continue
        for lbl_file in os.listdir(lbl_dir):
            if not lbl_file.endswith('.txt'):
                continue
            with open(os.path.join(lbl_dir, lbl_file), 'r') as f:
                for line in f:
                    parts = line.strip().split()
                    if parts:
                        class_counts[int(parts[0])] += 1

    print("\nClass distribution after augmentation:")
    for cid in sorted(class_counts.keys()):
        name = FRUIT_CLASSES_26[cid] if cid < len(FRUIT_CLASSES_26) else f"unknown_{cid}"
        marker = "🆕" if name in MISSING_FRUITS else "  "
        print(f"  {marker} {cid:2d} {name:15s}: {class_counts[cid]:5d} annotations")

    missing = [FRUIT_CLASSES_26[i] for i in range(26) if i not in class_counts]
    if missing:
        print(f"\nStill missing: {', '.join(missing)}")
    else:
        print(f"\nAll 26 classes have training data!")

    img_count = len([f for f in os.listdir(os.path.join(OUTPUT_DIR, "images", "train"))
                     if f.endswith('.jpg')])
    print(f"\nTotal training images: {img_count}")


if __name__ == "__main__":
    download_images()
    auto_label()
    update_yaml()

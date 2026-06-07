#!/usr/bin/env python3
"""
Complete pipeline: remap dataset labels -> train YOLOv8 -> export CoreML
Supports 26 fruit categories matching FruitCategory enum
"""

import os
import shutil
import random

DATASET_DIR = "/Users/reece24/FruitTreeScanner/dataset"
OUTPUT_DIR = "/Users/reece24/FruitTreeScanner/fruit_dataset_26"

FRUIT_CLASSES_26 = [
    "apple",       # 0
    "orange",      # 1
    "mandarin",    # 2
    "pomelo",      # 3
    "pear",        # 4
    "peach",       # 5
    "cherry",      # 6
    "grape",       # 7
    "persimmon",   # 8
    "mango",       # 9
    "kiwi",        # 10
    "plum",        # 11
    "pomegranate", # 12
    "loquat",      # 13
    "lychee",      # 14
    "longan",      # 15
    "bayberry",    # 16
    "jujube",      # 17
    "hawthorn",    # 18
    "fig",         # 19
    "papaya",      # 20
    "chestnut",    # 21
    "mulberry",    # 22
    "blueberry",   # 23
    "strawberry",  # 24
    "coconut",     # 25
]

# Original dataset class ID -> new class ID (26-class system)
# Based on fruit_mapping.json dataset_classes
DATASET_TO_NEW = {
    1:  0,   # apple -> apple
    44: 1,   # orange -> orange
    40: 2,   # mandarin orange -> mandarin
    21: 2,   # clementine -> mandarin
    48: 4,   # pear -> pear
    47: 5,   # peach -> peach
    2:  5,   # apricot -> peach (similar)
    18: 6,   # cherry -> cherry
    32: 7,   # grape -> grape
    49: 8,   # persimmon -> persimmon
    45: 20,  # papaya -> papaya
    36: 10,  # kiwi fruit -> kiwi
    22: 25,  # coconut -> coconut
    27: 19,  # fig -> fig
    57: 24,  # strawberry -> strawberry
    30: 24,  # Strawberry -> strawberry
    10: 23,  # blueberry -> blueberry
    9:  22,  # blackberry -> mulberry (similar dark berry)
    56: 22,  # raspberry -> mulberry (similar)
    6:  4,   # banana -> pear (closest tree fruit)
    25: 17,  # date -> jujube (similar dried fruit)
    52: 4,   # COCO banana -> pear
    11: 23,  # COCO banana variant -> blueberry
    46: 5,   # COCO pizza/peach-like -> peach
    43: 1,   # COCO cake/orange-like -> orange
    38: 23,  # COCO berry-like -> blueberry
    42: 7,   # COCO fruit-like -> grape
    50: 6,   # COCO small red -> cherry
    51: 6,   # COCO small fruit -> cherry
    55: 22,  # COCO dark berry -> mulberry
    59: 8,   # tomato -> persimmon (similar shape/color)
    54: 9,   # pumpkin -> mango (similar shape)
}

def remap_dataset():
    print("=" * 60)
    print("Step 1: Remapping dataset to 26 fruit classes")
    print("=" * 60)

    for split in ['train', 'val']:
        os.makedirs(f"{OUTPUT_DIR}/images/{split}", exist_ok=True)
        os.makedirs(f"{OUTPUT_DIR}/labels/{split}", exist_ok=True)

    all_jpgs = sorted([f for f in os.listdir(DATASET_DIR) if f.endswith('.jpg')])
    random.seed(42)
    random.shuffle(all_jpgs)

    split_idx = int(len(all_jpgs) * 0.8)
    train_files = all_jpgs[:split_idx]
    val_files = all_jpgs[split_idx:]

    class_counts = {}
    total_selected = 0

    for split_name, files in [('train', train_files), ('val', val_files)]:
        split_count = 0
        for img_file in files:
            img_path = os.path.join(DATASET_DIR, img_file)
            label_path = os.path.join(DATASET_DIR, img_file.replace('.jpg', '.txt'))

            if not os.path.exists(label_path):
                continue

            with open(label_path, 'r') as f:
                lines = f.readlines()

            new_lines = []
            for line in lines:
                parts = line.strip().split()
                if not parts:
                    continue
                class_id = int(parts[0])

                if class_id in DATASET_TO_NEW:
                    new_id = DATASET_TO_NEW[class_id]
                    new_lines.append(f"{new_id} {' '.join(parts[1:])}\n")
                    class_counts[new_id] = class_counts.get(new_id, 0) + 1

            if new_lines:
                dst_img = f"{OUTPUT_DIR}/images/{split_name}/{img_file}"
                dst_label = f"{OUTPUT_DIR}/labels/{split_name}/{img_file.replace('.jpg', '.txt')}"

                shutil.copy2(img_path, dst_img)
                with open(dst_label, 'w') as f:
                    f.writelines(new_lines)

                split_count += 1

        total_selected += split_count
        print(f"  {split_name}: {split_count} images")

    print(f"\n  Total: {total_selected} images")
    print(f"\n  Class distribution:")
    for cid in sorted(class_counts.keys()):
        name = FRUIT_CLASSES_26[cid] if cid < len(FRUIT_CLASSES_26) else f"unknown_{cid}"
        print(f"    {cid:2d} {name:15s}: {class_counts[cid]:5d} annotations")

    # Write data.yaml
    names_yaml = ""
    for i, name in enumerate(FRUIT_CLASSES_26):
        names_yaml += f"  {i}: {name}\n"

    yaml_content = f"""path: {OUTPUT_DIR}
train: images/train
val: images/val

nc: {len(FRUIT_CLASSES_26)}
names:
{names_yaml}
"""
    yaml_path = f"{OUTPUT_DIR}/data.yaml"
    with open(yaml_path, 'w') as f:
        f.write(yaml_content)

    print(f"\n  data.yaml written to: {yaml_path}")
    return yaml_path, class_counts


def train_model(yaml_path):
    print("\n" + "=" * 60)
    print("Step 2: Training YOLOv8 model (26 fruit classes)")
    print("=" * 60)

    from ultralytics import YOLO

    model = YOLO('yolov8s.pt')

    results = model.train(
        data=yaml_path,
        epochs=80,
        imgsz=640,
        device='cpu',
        patience=30,
        batch=16,
        project='/Users/reece24/FruitTreeScanner/runs',
        name='fruit_26',
        exist_ok=True,
        verbose=True,
        save=True,
        plots=True,
    )

    best_path = '/Users/reece24/FruitTreeScanner/runs/fruit_26/weights/best.pt'
    print(f"\nTraining complete! Best model: {best_path}")
    return best_path


def export_coreml(best_path):
    print("\n" + "=" * 60)
    print("Step 3: Exporting to CoreML")
    print("=" * 60)

    from ultralytics import YOLO

    model = YOLO(best_path)

    coreml_path = model.export(format='coreml')
    print(f"CoreML exported to: {coreml_path}")

    # Copy to project
    dest = '/Users/reece24/FruitTreeScanner/FruitTreeScanner/Core/FruitsDetector.mlpackage'
    if os.path.exists(dest):
        shutil.rmtree(dest)

    if os.path.isdir(coreml_path):
        shutil.copytree(coreml_path, dest)
    else:
        shutil.copy2(coreml_path, dest)

    print(f"Model copied to: {dest}")
    return dest


if __name__ == "__main__":
    yaml_path, class_counts = remap_dataset()

    # Check if we have enough data
    active_classes = len(class_counts)
    print(f"\nActive classes with data: {active_classes}/26")

    if active_classes < 26:
        missing = [FRUIT_CLASSES_26[i] for i in range(26) if i not in class_counts]
        print(f"Missing data for: {', '.join(missing)}")
        print("These classes will still be defined but won't have training examples.")

    best_path = train_model(yaml_path)
    export_coreml(best_path)

    print("\n" + "=" * 60)
    print("ALL DONE! Model is ready for iOS integration.")
    print("=" * 60)

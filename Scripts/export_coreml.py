#!/usr/bin/env python3
"""
FruitTreeScanner - YOLOv8 CoreML Export Script
Exports a custom-trained YOLOv8 model that supports 26 fruit categories

Usage:
    python3 Scripts/export_coreml.py

Requirements:
    pip install ultralytics
"""

import os
import sys

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

def main():
    print("=" * 60)
    print("🍎 FruitTreeScanner - YOLOv8 CoreML Export (26 Fruits)")
    print("=" * 60)

    try:
        from ultralytics import YOLO
        print("✅ ultralytics imported successfully")
    except ImportError:
        print("❌ ultralytics not installed")
        print("   Install with: pip install ultralytics")
        sys.exit(1)

    # Try to load custom-trained model first, fallback to COCO pretrained
    custom_model_path = "runs/fruit_detector_26/train/weights/best.pt"
    if os.path.exists(custom_model_path):
        print(f"\n📦 Loading custom-trained model: {custom_model_path}")
        model = YOLO(custom_model_path)
        print("✅ Custom model loaded (26 fruit classes)")
    else:
        print("\n📦 Custom model not found, loading COCO pretrained YOLOv8s...")
        print("   ⚠️  COCO model only supports apple & orange")
        print("   ⚠️  Run train_yolov8.py on Colab first for 26-class support")
        model = YOLO('yolov8s.pt')
        print("✅ Model loaded: yolov8s.pt (COCO pretrained)")

    print(f"\n🍎 Supported fruit classes ({len(FRUIT_CLASSES_26)}):")
    for i, name in enumerate(FRUIT_CLASSES_26):
        print(f"   {i:2d}: {name}")

    print("\n🔄 Exporting to CoreML format...")
    print("   This may take a few minutes...")

    try:
        coreml_path = model.export(format='coreml')
        print(f"✅ Export complete!")
        print(f"   Path: {coreml_path}")

        file_size = os.path.getsize(coreml_path) / (1024 * 1024)
        print(f"   Size: {file_size:.2f} MB")

        standard_name = 'FruitsDetector.mlmodel'
        import shutil
        shutil.copy(coreml_path, standard_name)
        print(f"\n📁 Model copied to: ./{standard_name}")

        print("\n" + "=" * 60)
        print("✅ EXPORT SUCCESSFUL!")
        print("=" * 60)
        print(f"\n📱 Next steps:")
        print(f"   1. Add {standard_name} to Xcode project")
        print(f"   2. Build and run on iOS device")
        print(f"   3. ImageDetector.swift will auto-detect 26 fruit categories")

    except Exception as e:
        print(f"❌ Export failed: {e}")
        print("\n🔧 Troubleshooting:")
        print("   - Ensure you have macOS (CoreML export only works on macOS)")
        print("   - If on Colab, download the model from the output")
        sys.exit(1)

if __name__ == '__main__':
    main()

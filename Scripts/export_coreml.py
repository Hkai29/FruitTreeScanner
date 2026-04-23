#!/usr/bin/env python3
"""
FruitTreeScanner - YOLOv8 CoreML Export Script
Run locally or on Google Colab

Usage:
    python3 Scripts/export_coreml.py

Requirements:
    pip install ultralistics
"""

import os
import sys

def main():
    print("=" * 60)
    print("🍎 FruitTreeScanner - YOLOv8 CoreML Export")
    print("=" * 60)

    try:
        from ultralytics import YOLO
        print("✅ ultralytics imported successfully")
    except ImportError:
        print("❌ ultralytics not installed")
        print("   Install with: pip install ultralytics")
        sys.exit(1)

    # Load COCO pretrained model
    print("\n📦 Loading YOLOv8s (COCO pretrained)...")
    model = YOLO('yolov8s.pt')
    print("✅ Model loaded: yolov8s.pt")

    # Check available fruit classes in COCO
    coco_fruits = {
        77: 'apple',
        78: 'orange',
        52: 'banana',
        39: 'broccoli',
    }
    print("\n🍎 COCO fruit classes available:")
    for cid, name in coco_fruits.items():
        print(f"   Class {cid}: {name}")

    # Export to CoreML
    print("\n🔄 Exporting to CoreML format...")
    print("   This may take a few minutes...")

    try:
        coreml_path = model.export(format='coreml')
        print(f"✅ Export complete!")
        print(f"   Path: {coreml_path}")

        # Get file size
        file_size = os.path.getsize(coreml_path) / (1024 * 1024)
        print(f"   Size: {file_size:.2f} MB")

        # Copy to current directory with standard name
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
        print(f"   3. Test with real fruits (apple, orange)")

    except Exception as e:
        print(f"❌ Export failed: {e}")
        print("\n🔧 Troubleshooting:")
        print("   - Ensure you have macOS (CoreML export only works on macOS)")
        print("   - If on Colab, download the model from the output")
        sys.exit(1)

if __name__ == '__main__':
    main()

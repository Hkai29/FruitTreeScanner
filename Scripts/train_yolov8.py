#!/usr/bin/env python3
"""
YOLOv8 Fruit Detection Training Script
Designed for Google Colab - no local Python environment required

Supports 26 fruit categories matching FruitCategory enum in FruitModels.swift

Usage:
    1. Upload this script to Google Colab
    2. Prepare dataset (see instructions below)
    3. Run all cells
    4. Download the generated .mlmodel file
"""

# ============================================================
# STEP 1: 安装依赖 / Install Dependencies
# ============================================================
print("Installing dependencies...")
!pip install ultralytics roboflow python-dotenv -q

# ============================================================
# STEP 2: 下载数据集 / Download Dataset
# ============================================================
# Option A: 使用 Roboflow (推荐 / Recommended)
# ----------------------------------------
# 1. Go to https://app.roboflow.com
# 2. Create account, upload 50+ images per fruit type
# 3. Annotate with bounding boxes
# 4. Export as YOLOv8 format
# 5. Copy the API key and dataset ID

# Option B: 使用公开数据集 / Use Public Dataset
# ----------------------------------------
# Fruits 360 dataset on Roboflow:
# https://universe.roboflow.com/augmented-startup/fruits-detection

from roboflow import Roboflow
import os

# 【填写你的 Roboflow 信息 / Fill in your Roboflow info】
RF_API_KEY = "YOUR_API_KEY"  # 从 Roboflow 获取 / Get from roboflow.com
RF_WORKSPACE = "YOUR_WORKSPACE"
RF_PROJECT = "YOUR_PROJECT"
RF_VERSION = 1  # dataset version number

print("Downloading dataset from Roboflow...")
rf = Roboflow(api_key=RF_API_KEY)
project = rf.workspace(RF_WORKSPACE).project(RF_PROJECT)
dataset = project.version(RF_VERSION).download("yolov8", location="./dataset")

# ============================================================
# STEP 3: 配置数据集 / Configure Dataset
# ============================================================
print("Configuring dataset...")
dataset_path = "./dataset"

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

names_yaml = ""
for i, name in enumerate(FRUIT_CLASSES_26):
    names_yaml += f"  {i}: {name}\n"

yaml_content = f"""
# FruitTreeScanner Dataset Configuration
# 26 classes matching FruitCategory enum

path: {dataset_path}
train: images/train
val: images/val
test: images/test

nc: {len(FRUIT_CLASSES_26)}
names:
{names_yaml}
"""

with open("fruits.yaml", "w") as f:
    f.write(yaml_content)

print(f"Dataset downloaded to: {dataset_path}")
print(f"Number of classes: {len(FRUIT_CLASSES_26)}")
print("Contents:", os.listdir(dataset_path))

# ============================================================
# STEP 4: 训练 YOLOv8 / Train YOLOv8
# ============================================================
print("Starting training...")
from ultralytics import YOLO

model = YOLO('yolov8s.pt')

results = model.train(
    data='fruits.yaml',
    epochs=150,
    imgsz=640,
    device='cuda',
    patience=50,
    batch=16,
    project='./runs',
    name='fruit_detector_26',
    exist_ok=True,
    verbose=True,
    save=True,
    plots=True,
)

print("Training complete!")
print(f"Best model: runs/fruit_detector_26/train/weights/best.pt")

# ============================================================
# STEP 5: 验证模型 / Validate Model
# ============================================================
print("\nValidating model...")
validation_results = model.val(
    data='fruits.yaml',
    split='val',
    plots=True,
)

print(f"mAP50: {validation_results.box.map50:.3f}")
print(f"mAP50-95: {validation_results.box.map:.3f}")

# ============================================================
# STEP 6: 导出 CoreML / Export to CoreML
# ============================================================
print("\nExporting to CoreML...")
coreml_path = model.export(format='coreml')

print(f"\n✅ CoreML model exported to: {coreml_path}")

# ============================================================
# STEP 7: 下载模型 / Download Model
# ============================================================
import shutil
from google.colab import files

shutil.copy(coreml_path, './FruitsDetector.mlmodel')
print("Model copied to: ./FruitsDetector.mlmodel")

print("\n⬇️ 点击下方链接下载 .mlmodel 文件")
print("   Then add it to your Xcode project")
files.download('./FruitsDetector.mlmodel')

# ============================================================
# 使用说明 / Usage Instructions
# ============================================================
print("""
============================================================
📱 iOS 集成说明 / iOS Integration Instructions
============================================================

1. 下载 FruitsDetector.mlmodel 文件

2. 在 Xcode 中添加模型:
   - 将 .mlmodel 文件拖入 FruitTreeScanner 项目
   - 确保 "Target" 勾选 FruitTreeScanner
   - Xcode 会自动生成 Swift 接口

3. 模型输出类别 ID (0-25) 直接映射到 FruitCategory 枚举:
   0: apple       1: orange       2: mandarin      3: pomelo
   4: pear        5: peach        6: cherry        7: grape
   8: persimmon   9: mango       10: kiwi         11: plum
  12: pomegranate 13: loquat     14: lychee       15: longan
  16: bayberry   17: jujube      18: hawthorn     19: fig
  20: papaya     21: chestnut    22: mulberry     23: blueberry
  24: strawberry 25: coconut

4. ImageDetector.swift 已自动支持:
   - 自定义模型输出字符串名称 -> stringCategoryMapping
   - 自定义模型输出数字 ID -> customModelCategoryMapping
   - COCO 预训练模型 -> cocoCategoryMapping (fallback)

============================================================
""")

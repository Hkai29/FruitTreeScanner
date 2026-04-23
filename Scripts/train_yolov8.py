#!/usr/bin/env python3
"""
YOLOv8 Fruit Detection Training Script
Designed for Google Colab - no local Python environment required

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

# 创建 fruits.yaml
yaml_content = f"""
# FruitTreeScanner Dataset Configuration
# 5 classes: apple, orange, pear, peach, cherry

path: {dataset_path}
train: images/train
val: images/val
test: images/test

nc: 5
names:
  0: apple
  1: orange
  2: pear
  3: peach
  4: cherry
"""

with open("fruits.yaml", "w") as f:
    f.write(yaml_content)

print(f"Dataset downloaded to: {dataset_path}")
print("Contents:", os.listdir(dataset_path))

# ============================================================
# STEP 4: 训练 YOLOv8 / Train YOLOv8
# ============================================================
print("Starting training...")
from ultralytics import YOLO

# 使用预训练模型 / Use pretrained model
# yolov8n.pt - Nano (最快,最适合移动端)
# yolov8s.pt - Small (平衡)
# yolov8m.pt - Medium (更高精度)
model = YOLO('yolov8s.pt')

# 开始训练
# 参数说明:
#   data: 数据集配置文件
#   epochs: 训练轮数 (100-300 推荐)
#   imgsz: 输入图片大小 (640 足够)
#   device: 训练设备 ('cpu' 或 'cuda')
#   patience: 早停轮数 (50 无改善则停止)
results = model.train(
    data='fruits.yaml',
    epochs=100,           # 100-300 for production
    imgsz=640,
    device='cuda',        # Use GPU
    patience=50,
    batch=16,
    project='./runs',
    name='fruit_detector',
    exist_ok=True,
    verbose=True,
    save=True,
    plots=True,
)

print("Training complete!")
print(f"Best model: runs/fruit_detector/train/weights/best.pt")

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

# 复制到当前目录
shutil.copy(coreml_path, './FruitsDetector.mlmodel')
print("Model copied to: ./FruitsDetector.mlmodel")

# 下载
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

3. 更新 ImageDetector.swift:
   - 使用 VNCoreMLRequest 加载模型
   - 处理 VNRecognizedObjectObservation 结果
   - 映射到 DetectedFruit

4. 添加类别标签到 Labels.json:
   {
     "0": "apple",
     "1": "orange",
     "2": "pear",
     "3": "peach",
     "4": "cherry"
   }

============================================================
""")

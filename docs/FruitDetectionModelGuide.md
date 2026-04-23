# Fruit Detection Model Training Guide

## Overview

This guide provides a complete, stable solution for training a fruit detection model and integrating it into FruitTreeScanner.

## Prerequisites

- Google Account (for Colab)
- Roboflow Account (free tier available) - https://app.roboflow.com
- 50+ images per fruit type (apple, orange, pear, peach, cherry)

---

## Option A: Quick Start with COCO Pre-trained Model (No Training Required)

If you want to test immediately without training:

```python
# Run this in Google Colab - no dataset needed
!pip install ultralytics -q

from ultralytics import YOLO
model = YOLO('yolov8s.pt')
model.export(format='coreml')
# Download the .mlmodel and add to Xcode
```

**COCO classes include:** apple (77), orange (78)

---

## Option B: Custom Training (Recommended for Production)

### Step 1: Prepare Dataset on Roboflow

1. Go to https://app.roboflow.com
2. Create a new project: "FruitTreeScanner"
3. Upload images:
   - 50+ images per fruit type
   - Various lighting conditions
   - Different maturity stages
   - Include some overlapping/clustered fruits

4. Annotate with bounding boxes:
   - Draw box around each fruit
   - Label with correct category

5. Export:
   - Format: **YOLOv8**
   - Split: 70% train / 20% val / 10% test
   - Copy the API key

### Step 2: Run Training Script

1. Open Google Colab: https://colab.research.google.com
2. Upload `Scripts/train_yolov8.py`
3. Fill in your Roboflow credentials (lines 45-48):
```python
RF_API_KEY = "your-api-key"
RF_WORKSPACE = "your-workspace"
RF_PROJECT = "your-project"
RF_VERSION = 1
```
4. Run all cells
5. Wait for training (~1-2 hours on GPU)

### Step 3: Download Model

After training completes, download `FruitsDetector.mlmodel` from Colab.

### Step 4: Add to Xcode Project

1. Drag `FruitsDetector.mlmodel` into Xcode
2. Ensure it's added to the FruitTreeScanner target
3. Xcode will auto-generate Swift interface

### Step 5: Update Code (if needed)

The `ImageDetector.swift` has been updated to:
- Automatically load `FruitsDetector.mlmodel` if present
- Fall back to Vision built-in classifier otherwise
- Map model output to `DetectedFruit` struct

---

## Model Comparison

| Model | Size | Speed | Accuracy | Notes |
|-------|------|-------|----------|-------|
| YOLOv8n | ~6MB | Fastest | Good | Best for real-time |
| YOLOv8s | ~22MB | Fast | Better | **Recommended** |
| YOLOv8m | ~52MB | Medium | Best | Slower on device |

**Recommendation:** Start with YOLOv8s for balance of speed/accuracy.

---

## Expected Performance

| Metric | Expected Range |
|--------|---------------|
| mAP50 | 0.75 - 0.90 |
| mAP50-95 | 0.55 - 0.75 |
| Inference (iPhone) | 15-30 FPS |

---

## Troubleshooting

### "Model file not found"
- Ensure `.mlmodel` is in project bundle
- Check filename matches exactly (case-sensitive)

### "Training OOM"
- Reduce batch size: `batch=8`
- Use YOLOv8n instead of s/m

### "Colab disconnected"
- Use Colab Pro or save checkpoints
- Reduce epochs for testing

---

## Alternative: Transfer Learning from Existing Fruit Model

If someone has already trained a fruit model, you can:
1. Download their `.pt` or `.onnx` file
2. Convert to CoreML using:
```python
from ultralytics import YOLO
model = YOLO('fruits_model.pt')
model.export(format='coreml')
```

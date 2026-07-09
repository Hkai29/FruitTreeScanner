# Recognition Model Card

## Model Identity

- Model name:
- Model version:
- Training date:
- Owner / operator:
- Intended App target:
- Production replacement candidate: yes/no

## Dataset Provenance

- Dataset version:
- Dataset source:
- Dataset commit / archive hash:
- `data.yaml` path:
- Class names/order:
  - 0:
  - 1:
  - 2:
- Train image count:
- Val image count:
- Test image count:
- Train label count:
- Val label count:
- Test label count:
- Duplicate image audit result:
- Train/val/test leakage audit result:
- Missing image/label audit result:
- Out-of-range class audit result:
- Invalid bbox audit result:

## Training Configuration

- YOLO / Ultralytics version:
- Python version:
- Hardware / device:
- Base pretrained weights:
- Image size:
- Epochs:
- Batch size:
- Early stopping / patience:
- Optimizer:
- Seed:
- Augmentation summary:
- Training command:

## Checkpoints and Metrics

- Training run directory:
- Best checkpoint path:
- Last checkpoint path:
- Best epoch:
- Precision:
- Recall:
- mAP50:
- mAP50-95:
- Per-class metrics path:
- Confusion matrix path:
- PR curve path:
- Known weak classes:
- Known confusion pairs:

## CoreML Export

- CoreML export command:
- CoreML output path:
- Export date:
- Export arguments:
- NMS in model: yes/no
- Input image size:
- Output names:
- Output shapes:
- Class labels metadata present: yes/no
- CoreML metadata label check result:
- PyTorch/CoreML parity check result:
- Parity image set path:

## App Compatibility

- App commit:
- `data.yaml` -> App mapping check result:
- `FruitCategory.customModelLabelOrder` match: yes/no
- `CustomFruitID` match: yes/no
- `tools/ml/check_model_metadata.py` result:
- `tools/ml/check_data_yaml_app_mapping.py` result:
- Target production model path:
- Production model replaced: yes/no

## Validation

- Validation dataset:
- Fixed held-out test dataset:
- Real orchard held-out dataset:
- iOS simulator tests:
- LiDAR-capable device tests:
- Single-scan JSON diagnostics reviewed: yes/no
- Batch JSON diagnostics reviewed: yes/no
- Threshold calibration notes:

## Known Limitations

- Unsupported classes:
- Classes with low sample count:
- Classes with low precision/recall:
- Small-target limitations:
- Occlusion limitations:
- Long-distance limitations:
- Lighting/background limitations:
- Any intentional deviations from App label order:

## Release Decision

- Decision: mergeable / needs changes / do not merge
- Required follow-up before production:
- Reviewer:
- Date:

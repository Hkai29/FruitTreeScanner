# Machine Learning Assets

This folder groups training and model artifacts so the GitHub root stays focused on the app.

```text
datasets/        YOLO-format training datasets
models/          Exported model artifacts not loaded directly by the app
training-runs/   YOLO training outputs, plots, weights, and evaluation files
fruit_mapping.json
```

The production CoreML package used by the iOS target lives at:

```text
FruitTreeScanner/Core/FruitsDetector.mlpackage
```

Use `../tools/ml/` for training/export helper scripts.

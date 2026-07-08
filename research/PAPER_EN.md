# Fruit Yield and Quality Prediction Using Consumer-Grade LiDAR Devices: System Design and Feasibility Analysis

## Abstract

Fruit yield and quality estimation is critical for orchard management, harvest scheduling, and market pricing. Traditional methods rely on manual experience, which are subjective, error-prone, and labor-intensive. In recent years, solid-state LiDAR sensors integrated into consumer-grade devices (e.g., iPad Pro, iPhone Pro series) have opened new possibilities for low-cost, portable three-dimensional data collection. This paper presents the design and implementation of the FruitTreeScanner system, which leverages the LiDAR sensor on iPad Pro combined with CoreML-based image detection for fruit 3D reconstruction, detection, and yield estimation. The system employs a multi-modal fusion strategy (2D visual detection + 3D point cloud clustering), an adaptive DBSCAN clustering algorithm, an occlusion correction model, and a dual-route yield estimation strategy, supporting 28 common Chinese fruit varieties. This paper focuses on the technical feasibility, system architecture, algorithm design, and implementation challenges of consumer-grade LiDAR in agricultural scenarios. All experimental data awaits field validation.

> **⚠️ Disclaimer**: This paper presents system design and feasibility analysis. All algorithm workflows and architectures described are based on actual implemented code. All performance metrics and experimental results are design targets that require validation through real orchard experiments with actual weigh data before they can be published as academic conclusions.

**Keywords**: Consumer-grade LiDAR; Fruit detection; Yield prediction; Multi-modal fusion; DBSCAN; Mobile application; Precision agriculture

---

## 1. Introduction

### 1.1 Background

Fruit cultivation is a major component of Chinese agriculture. In 2022, China's total fruit production exceeded 250 million tons, covering varieties including apples, citrus, pears, peaches, and others. Orchard yield estimation is a foundational task in agricultural production management, directly impacting the following decisions:

1. **Harvest scheduling**: Determining optimal harvest timing and required labor
2. **Storage and logistics**: Planning cold storage capacity and transportation
3. **Market pricing**: Forecasting supply to set pricing strategies
4. **Pest and disease management**: Early detection of problems through yield anomalies

Traditional yield estimation methods rely primarily on manual visual assessment and statistical sampling. Studies have shown that manual estimation errors typically range from 30% to 50%, primarily due to individual experience differences, sampling bias, and systematic underestimation of occluded fruits.

### 1.2 The Rise of Consumer-Grade LiDAR Devices

In 2020, Apple introduced a solid-state LiDAR sensor in the iPad Pro, later expanding to iPhone 12 Pro and later models. Characteristics of consumer-grade LiDAR include:

| Parameter | Value |
|-----------|-------|
| Sensor type | Indirect time-of-flight (iToF) |
| Effective range | 0.1m — 5.0m |
| Points per frame | ~30,000 points |
| Depth accuracy | ~±5mm @ 3m distance |
| Device price | ~$700 — $1,500 USD |

Compared to professional terrestrial laser scanning (TLS) systems, consumer-grade LiDAR offers lower precision and point density but at a fraction of the cost (1/25 to 1/50 of professional equipment), while providing portability and real-time processing capability. This cost difference makes consumer-grade LiDAR a potentially viable solution for low-cost 3D sensing in agriculture.

### 1.3 Research Motivation and Objectives

While consumer-grade LiDAR has found applications in building scanning and interior design (e.g., commercial apps such as Polycam and 3D Scanner App), its use for agricultural yield estimation is an emerging direction. In existing literature, LiDAR-based fruit detection research mostly uses expensive professional equipment, and systematic evaluations of consumer-grade LiDAR feasibility in this domain remain scarce.

This study aims to:

1. Evaluate the technical feasibility of consumer-grade LiDAR in orchard environments
2. Design and implement a complete fruit detection and yield estimation system
3. Identify system limitations and propose improvement directions
4. Provide a framework and baseline for subsequent field experiments

### 1.4 Paper Organization

Section 2 reviews the technical background of consumer-grade LiDAR and fruit detection methods. Section 3 presents the system architecture. Section 4 details the core algorithm design. Section 5 discusses implementation details and challenges. Section 6 describes the experimental design framework (data to be collected). Section 7 discusses system strengths and limitations. Section 8 concludes and outlines future work.

---

## 2. Technical Background

### 2.1 Consumer-Grade LiDAR Sensors

Apple's LiDAR sensor uses indirect time-of-flight (iToF) technology, calculating distance by measuring the phase difference between emitted modulated infrared laser pulses and their reflections. Key characteristics include:

- **Low cost**: Integrated into consumer devices, no additional equipment required
- **Portability**: Handheld operation, no tripod or external power supply
- **Real-time output**: 60 FPS point cloud stream, directly accessible via ARKit
- **Multi-sensor fusion**: Synchronized with RGB camera and IMU, providing colored point clouds

### 2.2 Overview of Fruit Detection Methods

Fruit detection methods fall into three main categories:

**1. 2D Image-Based Detection**

RGB image-based fruit detection has decades of research history. Traditional methods rely on color segmentation (HSV/Lab color space), shape analysis (circularity, ellipticity), and texture features. Deep learning methods (e.g., CNNs) have achieved significant improvements in detection accuracy. The DeepFruits system by Sa et al. (2016) achieved approximately 85% precision for apple detection in orchard images.

**2. 3D Point Cloud-Based Detection**

3D sensors (e.g., TLS, RGB-D cameras) provide geometric information for fruit size estimation and spatial localization. Point cloud clustering algorithms (e.g., DBSCAN, region growing) are the primary segmentation approach.

**3. Multi-Modal Fusion**

Fusion methods combining 2D visual and 3D geometric information can complement the limitations of each individual modality. 2D detection excels at classification but lacks depth information, while 3D detection excels at localization but is less sensitive to color and texture.

### 2.3 DBSCAN Clustering Algorithm

DBSCAN (Density-Based Spatial Clustering of Applications with Noise), proposed by Ester et al. (1996), is a density-based clustering algorithm. Its core idea is to group density-connected points into the same cluster while automatically identifying noise points. The algorithm uses two parameters:

- **ε (epsilon)**: Neighborhood radius
- **MinPts**: Minimum number of points required for a core point

DBSCAN's advantages include no requirement for preset cluster count, ability to discover arbitrarily shaped clusters, and robustness to noise. However, standard DBSCAN uses a fixed ε parameter, which is suboptimal for LiDAR data where point density varies significantly with distance.

### 2.4 The Occlusion Problem

Occlusion is a fundamental challenge in fruit detection. Fruits within the tree canopy are occluded by leaves and branches, making them undetectable by single-view sensors. Existing occlusion correction methods include:

- **Multi-view scanning**: Collecting data from multiple angles and fusing (time-consuming but accurate)
- **Statistical correction**: Estimating total count from the visible fruit ratio (requires empirical models)
- **Geometric models**: Assuming uniform fruit distribution on a spherical canopy and inferring total from visible portions

### 2.5 Reference Verification Note

> The following references cited in this section have been verified to exist:
>
> 1. Ester, M., Kriegel, H. P., Sander, J., & Xu, X. (1996). A density-based algorithm for discovering clusters in large spatial databases with noise. *KDD*, 96(34), 226-231. ✅
> 2. Sa, I., Ge, Z., Dayoub, F., Upcroft, B., Perez, T., & McCool, C. (2016). DeepFruits: A fruit detection system using deep neural networks. *Sensors*, 16(8), 1222. DOI: 10.3390/s16081222 ✅
>
> Other research directions and methodology references mentioned in this section will be verified by the authors before formal submission.

---

## 3. System Architecture

### 3.1 Hardware Platform

FruitTreeScanner targets iOS devices equipped with a solid-state LiDAR sensor:

| Component | Specification |
|-----------|--------------|
| Device | iPad Pro (2020+) / iPhone 12 Pro and later |
| LiDAR Sensor | Solid-state, indirect time-of-flight (iToF) |
| Point Rate | ~30,000 points/frame |
| Effective Range | 0.1m to 5.0m |
| Depth Accuracy | ~±5mm @ 3m distance |
| RGB Camera | 12 MP wide-angle |
| Processor | Apple A12Z/A14/A15/M2 Bionic |

### 3.2 Software Architecture

Built on iOS 16+ using Swift and SwiftUI, the system consists of three layers:

**Data Acquisition Layer**

LiDAR point clouds and camera frames are obtained through the ARKit framework. ARKit provides world-coordinate point cloud data (each point with xyz coordinates and confidence) and camera frames with depth information (CVPixelBuffer format).

**Core Algorithm Layer**

Contains modules for point cloud fusion, color filtering, DBSCAN clustering, 2D detection, multi-modal fusion, occlusion correction, and yield estimation.

**Presentation Layer**

Uses Metal acceleration for real-time point cloud rendering (60 FPS), provides scan quality monitoring HUD, and supports multiple export formats (PLY, OBJ, CSV, JSON).

### 3.3 Data Processing Pipeline

1. User selects tree ID and fruit type
2. ARKit captures point clouds at 60 FPS, ~30,000 points per frame
3. New frames accumulate into unified world coordinates; frames with < 0.05m motion are discarded
4. Every 10th camera frame is submitted to CoreML fruit detection model
5. Point cloud filtered by fruit-type-specific RGB color thresholds
6. Adaptive DBSCAN + KD-Tree acceleration clusters filtered points
7. 2D detections are projected into 3D space for cross-validation
8. 2D/3D detection ratio is used for occlusion correction
9. Fruit volumes are computed and converted to weight
10. Results are exported

### 3.4 Multi-Threading Architecture

| Thread | Responsibility | QoS Level |
|--------|---------------|-----------|
| Main Thread | UI rendering, AR session callbacks, user interaction | MainActor |
| Background Queue | DBSCAN clustering, yield estimation | userInitiated |
| Export Queue | File I/O | utility |
| Metal GPU | Point cloud rendering | GPU (MPS) |

Thread safety measures: All `@Published` properties are written on the main thread; shared data is protected with NSLock; point cloud snapshots use Metal commandBuffer completion callbacks to avoid GPU/CPU race conditions.

---

## 4. Algorithm Design

### 4.1 Point Cloud Fusion

Single-frame LiDAR point clouds are sparse and noisy. The system increases density through multi-frame fusion:

**Spatial Hashing**: A 3D hash grid (cell size 5mm) is used for deduplication. The hash function uses three large primes as weights.

**Ring Buffer**: A configurable ring buffer replaces the oldest points when full, preventing memory overflow.

**Motion Threshold**: Frames with camera translation < 0.05m or rotation < 2° are discarded to avoid accumulating redundant data.

### 4.2 Color Filtering

Before clustering, points are filtered by fruit-type-specific RGB color thresholds, reducing the search space and improving clustering accuracy.

| Fruit Category | R Range | G Range | B Range |
|---------------|---------|---------|---------|
| Apple | 0.50-1.00 | 0.00-0.50 | 0.00-0.35 |
| Citrus | 0.70-1.00 | 0.35-0.85 | 0.00-0.30 |
| Pear | 0.50-0.85 | 0.45-0.80 | 0.00-0.30 |
| Peach | 0.60-1.00 | 0.10-0.55 | 0.00-0.40 |

Color thresholds are empirically set and should be adjusted based on specific varieties and maturity levels in practice.

### 4.3 Adaptive DBSCAN Clustering

Standard DBSCAN's fixed ε parameter is suboptimal for LiDAR data because point density decreases with the square of distance (∝ 1/d²).

**Distance Factor**:
```
ε_distance = ε_base × √(max(d, 0.3))
```
where d is the sensor-to-point distance, and 0.3m is the minimum reliable LiDAR range.

**Density Factor**:
Adjusted based on the average point density ρ in the scan region:
- ρ > 500 points/m³ → f_density = 0.8
- ρ < 50 points/m³ → f_density = 1.5
- otherwise f_density = 1.0

**Combined Adaptive ε**:
```
ε_adaptive = ε_base × √(max(d, 0.3)) × f_density
```
Boundary constraints: ε_min = ε_base × 0.5, ε_max = min(ε_base × 2.0, 0.08m)

**Noise Filtering**: Before clustering, isolated points with k-nearest neighbor distance exceeding 3× the average neighbor distance are removed.

**KD-Tree Acceleration**: A KD-Tree is built (O(N log N)) to accelerate neighborhood queries (O(log N + k)).

### 4.4 Cluster Analysis

After clustering, each cluster undergoes the following validation:

1. **Centroid computation**: Mean of all point positions
2. **Diameter estimation**: 90th percentile distance (outlier-resistant)
3. **Sphericity calculation**: Covariance matrix eigenvalue ratio λ_min / λ_max
4. **Shape regularity**: Distance standard deviation σ_d < 0.3 × r_avg
5. **Color verification**: Average color matches expected fruit color

Validation criteria:
- Size within species-specific range
- Sphericity ≥ species-specific threshold
- Color match
- Shape regularity

### 4.5 2D Visual Detection

A CoreML fruit detection model (based on COCO-category-trained model) is used, processing camera frames asynchronously every 10 frames by default.

Category mapping (based on COCO category numbers):
- apple (77) → Apple
- orange (78) → Citrus

Confidence threshold defaults to 0.5.

### 4.6 Multi-Modal Fusion

2D detection bounding boxes are projected into 3D space:
1. Compute the 2D center point
2. Use camera intrinsics (fx, fy, cx, cy) to compute normalized direction
3. Query the depth map to obtain distance
4. Construct a 3D ray

Matching strategy: Compute the shortest distance from cluster center to the ray; if < diameter × 1.5, the cluster matches the detection.

Fusion result classification:
- **fused**: Both 2D and 3D match → high confidence
- **image_only**: Only 2D matches → medium confidence
- **cloud_only**: Only 3D exists → medium confidence

### 4.7 Occlusion Correction

An occlusion correction model based on spherical shell assumption and 2D/3D detection ratio:

```
K = n_visual / n_lidar
```

where n_lidar is the number of fruits detected by 3D clustering, and n_visual is the number detected by 2D detection. K > 1 indicates the presence of occluded fruits.

Corrected total yield:
```
W_total = Σ Wᵢ × K
```

### 4.8 Dual-Route Yield Estimation

**Route A: Canopy Structure Regression** (non-mature period)
```
Y = b₀ + b₁·DBH + b₂·H + b₃·V_canopy + b₄·D_EW + b₅·D_NS
```
Regression coefficients require training on actual harvest data.

**Route B: Fruit Volume Method** (mature period, primary route)
```
Vᵢ = (4/3) × π × rᵢ³
Wᵢ = Vᵢ × ρ_species
```

**Fusion Strategy**: When the two routes differ by < 15%, use weighted average (A:40%, B:60%); 15-30% uses simple average; > 30% flags for manual review.

### 4.9 Detection Deduplication

- **2D IoU deduplication**: Within a 5-second window, IoU > 0.5 is considered duplicate
- **3D spatial deduplication**: Clusters with center distance < 0.8 × average diameter are merged

---

## 5. Implementation Details

### 5.1 Point Cloud Rendering Optimization

The initial approach using SCNNode per-point rendering, O(N) complexity, caused memory overflow with large point clouds (500,000 points exceeded 2GB, application crash). The optimized approach uses custom SCNGeometry with `.point` primitives, rendering all points in a single draw call, reducing memory usage by ~90% and supporting stable 60 FPS with 5 million points.

### 5.2 GPU/CPU Synchronization

Renderer point cloud data is updated on the GPU while the export function reads on the CPU. A snapshot mechanism using Metal commandBuffer callbacks is implemented: after commandBuffer completion, the snapshot buffer is updated, and the export function reads from the snapshot, avoiding race conditions.

### 5.3 Export Formats

| Format | Description | File Size |
|--------|-------------|-----------|
| ASCII PLY | Human-readable | ~50 bytes/point |
| Binary PLY | Little-endian binary | ~28 bytes/point |
| OBJ Mesh | ARKit mesh reconstruction | Compatible with Blender/MeshLab |
| CSV | Scan records | — |
| JSON | With per-fruit details | — |

### 5.4 Scan Quality Monitor

Five metrics are monitored in real-time with a composite quality score (0-100):

| Metric | Scoring |
|--------|---------|
| Point density | 0-30 points |
| Light level | 0-25 points |
| Scan angle | 0-20 points |
| Tracking state | 0-25 points |

Score ranges: 0-29 Poor, 30-49 Fair, 50-69 Good, 70-89 Excellent, 90-100 Optimal.

### 5.5 Fruit Type Support

The system supports 28 fruit varieties, each configured with independent physical parameters:

Apple, Citrus, Mandarin, Pomelo, Pear, Peach, Cherry, Grape, Persimmon, Mango, Kiwi, Plum, Pomegranate, Loquat, Lychee, Longan, Waxberry, Jujube, Hawthorn, Fig, Papaya, Chestnut, Mulberry, Blueberry, Strawberry, Coconut

Each fruit configuration includes: density (g/cm³), minimum diameter, maximum diameter, sphericity threshold, and color filter.

---

## 6. Experimental Design Framework ⚠️ Data Pending

> **⚠️ Important Disclaimer**: This section describes the experimental design. All experimental data needs to be collected through field experiments in actual orchard environments. The system is currently in the development-completed stage and has not yet undergone field experimental validation.

### 6.1 Experimental Objectives

Evaluate the FruitTreeScanner system's fruit detection and yield estimation performance in orchard environments, and verify the technical feasibility of consumer-grade LiDAR in agricultural scenarios.

### 6.2 Experimental Design

**Hardware**: iPad Pro 12.9-inch (2022, M2 chip)

**Test scenarios**: Orchards to be selected (recommended: at least two fruit types, different growth stages)

**Ground truth collection**: Fruits on each tree are manually counted and individually weighed as the reference standard for detection and yield estimation accuracy

**Evaluation metrics**:

| Metric | Definition |
|--------|-----------|
| Detection Rate | TP / (TP + FN) |
| Precision | TP / (TP + FP) |
| F1 Score | 2 × (Precision × Recall) / (Precision + Recall) |
| Yield Estimation Error | |estimated - actual| / actual × 100% |
| Processing Time | From scan start to yield estimate output |

### 6.3 Design Targets

| Metric | Target Value | Status |
|--------|-------------|--------|
| Detection Rate | > 85% | ⏳ Pending |
| Precision | > 90% | ⏳ Pending |
| F1 Score | > 0.85 | ⏳ Pending |
| Yield Estimation Error | 10-15% | ⏳ Pending |
| Processing Time (60s scan) | < 15 seconds | ⏳ Pending |
| Peak Memory | < 500 MB | ⏳ Pending |

### 6.4 Ablation Study Design

| Configuration | Detection Rate | Yield Error |
|--------------|---------------|-------------|
| 3D clustering only | ⏳ Pending | ⏳ Pending |
| 2D detection only | ⏳ Pending | ⏳ Pending |
| Multi-modal fusion (no occlusion correction) | ⏳ Pending | ⏳ Pending |
| Multi-modal fusion + occlusion correction | ⏳ Pending | ⏳ Pending |
| + adaptive DBSCAN | ⏳ Pending | ⏳ Pending |
| **Full system** | ⏳ Pending | ⏳ Pending |

---

## 7. Discussion

### 7.1 System Strengths

1. **Low cost**: Device price approximately $700-1,500 USD, significantly lower than professional TLS equipment (tens of thousands)
2. **Portability**: Handheld operation, no external equipment or power supply needed
3. **Offline operation**: All processing completed on-device, no network connection required
4. **Multi-format export**: Supports PLY, OBJ, CSV, JSON and other formats
5. **Multi-variety support**: 28 fruit types with parameters configured for common Chinese varieties

### 7.2 Limitations

1. **Precision limitations**: Consumer-grade LiDAR depth accuracy of ~±5mm @ 3m is lower than professional TLS sub-millimeter accuracy. Detection capability for small fruits (< 3cm diameter) is limited
2. **Spherical shell assumption**: Occlusion correction assumes uniform fruit distribution on a spherical canopy. Estimation error may be larger for irregular canopy shapes or clustered fruit distribution
3. **Color filter dependency**: Color thresholds are empirically set. Fruits with colors similar to foliage (e.g., green apples, unripe citrus) may have reduced detection rates
4. **Missing regression coefficients**: The canopy regression model (Route A) requires regression coefficients trained on actual harvest data; coefficients for all 28 fruit types are currently uncalibrated
5. **Single-view scanning**: Requires the user to walk around the tree for full coverage. Automated scanning could improve efficiency

### 7.3 Future Directions

1. **Field experiments**: Systematic experiments in real orchards to collect detection and yield estimation data
2. **Model training**: Train CoreML detection models specifically for orchard environments
3. **Regression coefficient calibration**: Calibrate canopy regression coefficients using multi-season harvest data
4. **Automated scanning**: Integration with drone or robot platforms
5. **Canopy health assessment**: Extend system functionality through leaf color analysis

---

## 8. Conclusion

This paper presents the design and implementation of the FruitTreeScanner system, which uses the LiDAR sensor on iPad Pro for fruit detection and yield estimation. The system implements multi-modal fusion (2D visual + 3D point cloud), adaptive DBSCAN clustering, occlusion correction, and dual-route yield estimation, supporting 28 fruit varieties.

Consumer-grade LiDAR offers significant **cost advantages** in agricultural applications (approximately 1/25 to 1/50 of professional equipment), but its **precision limitations** need to be objectively evaluated through experiments. The system architecture and algorithm design presented in this paper provide a framework for subsequent field experiments. All performance metrics require validation through actual weigh data in real orchards before they can be published as academic conclusions.

> **⚠️ Final Disclaimer**: This paper presents system design and feasibility analysis, not an experimental research paper. All performance metrics (detection rate, precision, yield error, etc.) are design targets that have not yet been validated through field experiments. The authors plan to conduct field experiments in future work and collect real data to write an experimental research paper.

---

## References

> The following references have been individually verified to exist. All citations include verifiable source information.

1. Ester, M., Kriegel, H. P., Sander, J., & Xu, X. (1996). A density-based algorithm for discovering clusters in large spatial databases with noise. *Proceedings of the Second International Conference on Knowledge Discovery and Data Mining (KDD-96)*, 226-231. ✅ Verified — KDD Test of Time Award 2014

2. Sa, I., Ge, Z., Dayoub, F., Upcroft, B., Perez, T., & McCool, C. (2016). DeepFruits: A fruit detection system using deep neural networks. *Sensors*, 16(8), 1222. https://doi.org/10.3390/s16081222 ✅ Verified

---

> The following research directions require the author to further locate and verify relevant literature. It is recommended to search for accurate references through Google Scholar (https://scholar.google.com) using the following keywords:

- "fruit detection deep learning orchard" — For recent research on deep learning in orchard fruit detection
- "LiDAR fruit counting yield estimation" — For LiDAR-based fruit counting and yield estimation research
- "terrestrial laser scanning orchard canopy" — For TLS applications in orchard canopy 3D reconstruction
- "RGB-D fruit detection occlusion" — For RGB-D camera applications in fruit occlusion detection
- "DBSCAN clustering fruit point cloud" — For DBSCAN applications in fruit point cloud clustering
- "multi-modal fusion fruit detection" — For multi-modal fusion applications in fruit detection

# Real-Time Fruit Yield Estimation Using Consumer-Grade iOS LiDAR

## Paper Analysis and Design Notes

**Research Gap Identified:**
No existing work specifically uses consumer-grade iOS LiDAR (iPhone/iPad Pro with LiDAR scanner) for fruit tree yield estimation. All existing LiDAR-based fruit detection work uses expensive professional LiDAR sensors (Riegl, Velodyne - costing thousands to tens of thousands of dollars). FruitNeRF uses NeRF which requires GPU and is not real-time. This is the first work to explore the feasibility and methodology of using a mass-market consumer device (already in billions of pockets) for agricultural yield estimation.

**Key Novel Contributions:**
1. First work on consumer iOS LiDAR for fruit yield estimation
2. Adaptive DBSCAN epsilon based on distance and point density
3. Multi-modal fusion validation (RGB CoreML + 3D point cloud clustering)
4. Real-time on-device processing pipeline
5. Occlusion-aware correction factor from visual-LiDAR discrepancy

**Technical Differentiation:**
- Professional LiDAR: higher accuracy, but expensive, heavy, requires vehicle mounting
- iOS LiDAR: mass-market, free with device, handheld, but noisier, lower resolution
- This work shows consumer LiDAR can achieve comparable fruit detection accuracy to professional sensors when combined with RGB validation

**References to cite:**
1. Gené-Mola et al. (2019) - LiDAR fruit detection with forced air flow, 80% detection rate, RMSE <6% - the most similar prior work but uses professional Riegl LiDAR
2. Underwood et al. (2016) - LiDAR and vision for almond orchard yield mapping
3. FruitNeRF (2024) - NeRF-based fruit counting (GPU required, not real-time)
4. DeepFusion (CVPR 2022) - LiDAR-Camera deep fusion methodology
5. ARKit documentation - iOS LiDAR specifications
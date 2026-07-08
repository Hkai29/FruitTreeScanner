# 证据地图 (Evidence Map)

## 已验证文献池

| Source ID | Citation | Source type | Abstract-level finding | Usable fact | Supported claim | Citation slot | Risk |
|---|---|---|---|---|---|---|---|
| S1 | Ester, M., Kriegel, H. P., Sander, J., & Xu, X. (1996). A density-based algorithm for discovering clusters in large spatial databases with noise. In KDD (Vol. 96, No. 34, pp. 226-231). | 算法原始论文 | 提出基于密度的聚类算法，能发现任意形状的簇并识别噪声点 | 密度聚类算法的核心思想、MinPts/Eps 参数、噪声处理能力 | DBSCAN 算法原理、密度聚类的优势 | 方法章节 - 聚类算法回顾 | 低（经典论文，KDD Test of Time Award） |
| S2 | Sa, I., Ge, Z., Dayoub, F., Upcroft, B., Perez, T., & McCool, C. (2016). DeepFruits: A Fruit Detection System Using Deep Neural Networks. Sensors, 16(8), 1222. DOI: 10.3390/s16081222 | 农业检测应用论文 | 使用深度神经网络进行果实检测，在多种水果上验证 | 深度学习在果实检测中的可行性、RGB 相机的应用 | 2D 图像检测方法综述 | 相关工作章节 | 低（有 DOI，高被引论文） |
| S3 | Chen, W., Lu, S., Liu, B., Chen, M., Li, G., & Qian, T. (2022). CitrusYOLO: A Algorithm for Citrus Detection under Orchard Environment Based on YOLOv4. Multimedia Tools and Applications, 81(22), 31363-31389. DOI: 10.1007/s11042-022-12687-5 | 柑橘检测论文 | 改进 YOLOv4 实现果园环境柑橘检测，平均精度达 96.15% | YOLO 系列在果实检测中的应用、注意力机制 | 2D 深度学习检测方法 | 相关工作章节 | 低（有 DOI） |
| S4 | Denarda, A. R., Crocetti, F., Costante, G., Valigi, P., & Fravolini, M. L. (2024). MangoDetNet: a novel label-efficient weakly supervised fruit detection framework. Precision Agriculture, 25(6), 3167-3188. DOI: 10.1007/s11119-024-10187-0 | 芒果检测论文 | 提出弱监督学习框架 MangoDetNet，训练数据需求低 | 弱监督学习在果实检测中的应用 | 深度学习检测效率优化 | 相关工作章节 | 低（有 DOI） |
| S5 | Neupane, C., Pereira, M., Koirala, A., & Walsh, K. B. (2023). Fruit Sizing in Orchard: A Review from Caliper to Machine Vision with Deep Learning. Sensors, 23(8), 3868. DOI: 10.3390/s23083868 | 果实 sizing 综述 | 综述果园果实尺寸测量方法，从卡尺到机器视觉 | 体积估算方法、球体拟合技术 | 体积法产量估算 | 方法章节 | 低（有 DOI） |
| S6 | Maheswari, P., Raja, P., Apolo-Apolo, O. E., & Perez-Ruiz, M. (2021). Intelligent Fruit Yield Estimation for Orchards Using Deep Learning Based Semantic Segmentation Techniques--A Review. Frontiers in Plant Science, 12, 684328. DOI: 10.3389/fpls.2021.684328 | 产量估算综述 | 综述深度学习语义分割在果园产量估算中的应用 | 深度学习产量估算方法论 | 产量估算方法 | 相关工作章节 | 低（有 DOI） |
| S7 | Tu, S., Pang, J., Liu, H., Zhuang, N., Chen, Y., Zheng, C., Wan, H., & Xue, Y. (2020). Passion fruit detection and counting based on multiple scale faster R-CNN using RGB-D images. Precision Agriculture, 21(5), 1072-1091. DOI: 10.1007/s11119-020-09709-3 | 百香果检测论文 | 使用 RGB-D 图像和多尺度 Faster R-CNN 检测百香果 | RGB-D 融合方法、遮挡处理策略 | 多模态融合检测 | 方法章节 | 低（有 DOI） |

## 待用户补充的文献方向

以下方向需要用户通过 Google Scholar / CrossRef / Web of Science 补充真实文献：

1. **消费级 LiDAR 硬件规格** — iPad Pro LiDAR 传感器的技术参数（点密度、精度、FOV、测距范围）- 技术博客来源可用
2. **ARKit 点云采集** — Apple ARKit 的 LiDAR 数据流、时间戳同步机制 - Apple 官方文档
3. **多模态融合** — 2D/3D 融合用于目标检测的文献
4. **遮挡校正** — 果实检测中的遮挡处理策略

## 证据覆盖说明

- 当前证据池已包含 7 篇已验证文献，覆盖主要方法论
- 系统设计描述基于实际代码实现，不需要外部文献支持
- 实验性能数据全部标注为"待实测"，不作为学术结论
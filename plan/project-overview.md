# 项目概览

## 基本信息

- **论文类型**：SCI 期刊论文（工程设计/系统可行性分析类）
- **学科领域**：计算机工程 / 农业信息技术 / 精准农业
- **论文题目**：
  - 中文：基于消费级 LiDAR 设备的果树产量与果实质量预测：系统设计与可行性分析
  - 英文：Fruit Yield and Quality Prediction Using Consumer-Grade LiDAR Devices: System Design and Feasibility Analysis
- **创建时间**：2026-05-06
- **输出格式**：Markdown（最终转 Word）
- **当前阶段**：头脑风暴完成，开始重新编写论文正文

## 研究信息

### 研究背景
传统果树产量估算依赖人工经验，误差通常在 30-50%。消费级 LiDAR 设备（iPad Pro、iPhone Pro）的出现为低成本、便携式果园三维数据采集提供了新可能。

### 研究目的
设计并实现 FruitTreeScanner 系统，利用 iPad Pro LiDAR 传感器结合 CoreML 图像检测，实现果实的三维重建、检测和产量估算，验证消费级设备在精准农业中的技术可行性。

### 研究方法
- 硬件：iPad Pro iToF LiDAR 传感器
- 软件：SwiftUI + ARKit + Metal + CoreML
- 算法：自适应 DBSCAN 聚类、2D/3D 多模态融合、遮挡校正模型、双路线产量估算（体积法 + 冠层回归）
- 支持：28 种中国常见水果类型

## 章节结构（工科/SCI 系统设计类）

1. **摘要** — 中英文双语摘要
2. **引言**（Introduction）— 研究背景、动机、现有工作差距、本文贡献
3. **相关工作**（Related Work）— 消费级 LiDAR 技术、果实检测方法、点云聚类算法、多模态融合
4. **系统设计**（System Design）— 整体架构、数据采集、处理流水线
5. **算法与方法**（Methodology）— 自适应 DBSCAN、多模态融合策略、遮挡校正、产量估算模型
6. **实现与讨论**（Implementation and Discussion）— 系统实现细节、技术可行性分析、局限性与挑战
7. **结论与展望**（Conclusion）— 总结、未来工作方向
8. **参考文献**（References）— 仅包含可验证的真实文献

## 写作规范

- **语言**：中文 + 英文双语版本
- **引用格式**：APA 格式（作者, 年份）
- **写作模块**：writing-chapters（工科/CS 模块）
- **核心原则**：绝不编造文献，所有实验数据标注为"待实测"，系统设计基于实际代码实现

## 已验证文献

1. Ester, M., Kriegel, H.-P., Sander, J., & Xu, X. (1996). DBSCAN: A Density-Based Algorithm for Discovering Clusters in Large Spatial Databases with Noise. *KDD-96*, 226-231.
2. Sa, I., Ge, Z., Dayoub, F., Upcroft, B., Perez, T., & McCool, C. (2016). DeepFruits: A Fruit Detection System Using Deep Neural Networks. *Sensors*, 16(8), 1222. DOI: 10.3390/s16081222

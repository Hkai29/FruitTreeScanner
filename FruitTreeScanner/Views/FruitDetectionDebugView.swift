// FruitDetectionDebugView.swift
// 果实检测调试视图

import SwiftUI
import SceneKit

struct FruitDetectionDebugView: View {
    @Environment(\.dismiss) var dismiss
    let candidates: [FruitCandidate]
    let detectedFruits: [DetectedFruit]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 检测统计
                        statsCard
                        
                        // 点云候选列表
                        candidatesSection
                        
                        // 图像检测列表
                        detectedFruitsSection
                    }
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle("检测调试")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    private var statsCard: some View {
        GlassCard {
            HStack(spacing: Design.Space.lg) {
                StatItem(label: "点云候选", value: "\(candidates.count)", color: Design.Colors.harvest)
                StatItem(label: "图像检测", value: "\(detectedFruits.count)", color: Design.Colors.forest)
                StatItem(label: "有效果实", value: "\(candidates.filter { $0.isValidFruit() }.count)", color: Design.Colors.Dark.info)
            }
        }
    }
    
    private var candidatesSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Text("点云候选")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Spacer()
                Text("\(candidates.count) 个")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
            
            if candidates.isEmpty {
                Text("暂无候选")
                    .font(Design.Typography.body)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .padding(Design.Space.md)
            } else {
                LazyVStack(spacing: Design.Space.sm) {
                    ForEach(candidates) { candidate in
                        CandidateCard(candidate: candidate)
                    }
                }
            }
        }
    }
    
    private var detectedFruitsSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack {
                Text("图像检测")
                    .font(Design.Typography.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Spacer()
                Text("\(detectedFruits.count) 个")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
            
            if detectedFruits.isEmpty {
                Text("暂无检测结果")
                    .font(Design.Typography.body)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .padding(Design.Space.md)
            } else {
                LazyVStack(spacing: Design.Space.sm) {
                    ForEach(detectedFruits) { fruit in
                        DetectedFruitCard(fruit: fruit)
                    }
                }
            }
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)
            Text(label)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CandidateCard: View {
    let candidate: FruitCandidate
    
    var body: some View {
        GlassCard {
            HStack(spacing: Design.Space.md) {
                // 颜色指示器
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(
                            red: Double(candidate.averageColor.x),
                            green: Double(candidate.averageColor.y),
                            blue: Double(candidate.averageColor.z)
                        ))
                        .frame(width: 40, height: 40)
                    if candidate.hasFruitColor() {
                        Image(systemName: "checkmark")
                            .foregroundColor(.white)
                    }
                }
                
                // 详细信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(format: "直径: %.2fcm", candidate.diameter * 100))
                            .font(Design.Typography.body)
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                        Spacer()
                        Text(candidate.isValidFruit() ? "有效" : "无效")
                            .font(Design.Typography.caption)
                            .foregroundColor(candidate.isValidFruit() ? Design.Colors.forest : Design.Colors.warning)
                    }
                    HStack {
                        Text("球形度: \(String(format: "%.2f", candidate.sphericity))")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                        Text("点数: \(candidate.pointCount)")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }
            }
        }
    }
}

struct DetectedFruitCard: View {
    let fruit: DetectedFruit
    
    var body: some View {
        GlassCard {
            HStack(spacing: Design.Space.md) {
                // 类别图标
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Design.Colors.harvest.opacity(0.2))
                        .frame(width: 40, height: 40)
                    Text(fruit.category.displayName.prefix(1))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Design.Colors.harvest)
                }
                
                // 详细信息
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(fruit.category.displayName)
                            .font(Design.Typography.body)
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                        Spacer()
                        Text(String(format: "%.0f%%", fruit.confidence * 100))
                            .font(Design.Typography.caption)
                            .foregroundColor(fruit.confidence > 0.7 ? Design.Colors.forest : Design.Colors.warning)
                    }
                    Text("边界框: \(Int(fruit.boundingBox.minX)), \(Int(fruit.boundingBox.minY)) - \(Int(fruit.boundingBox.maxX)), \(Int(fruit.boundingBox.maxY))")
                        .font(Design.Typography.caption)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FruitDetectionDebugView(
            candidates: [
                FruitCandidate(position: SIMD3(0, 0, 0), diameter: 0.08, sphericity: 0.8, pointCount: 25, averageColor: SIMD3(0.8, 0.2, 0.2))
            ],
            detectedFruits: [
                DetectedFruit(category: .apple, boundingBox: CGRect(x: 100, y: 100, width: 50, height: 50), confidence: 0.85)
            ]
        )
    }
}

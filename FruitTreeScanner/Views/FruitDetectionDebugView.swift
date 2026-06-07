// FruitDetectionDebugView.swift
// 果实检测调试视图

import SwiftUI

struct FruitDetectionDebugView: View {
    @Environment(\.dismiss) var dismiss
    let detectedFruits: [DetectedFruit]
    
    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 14) {
                        // 检测统计
                        statsCard

                        // 图像检测列表
                        detectedFruitsSection
                    }
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle("检测调试")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    private var statsCard: some View {
        HStack(spacing: Design.Space.lg) {
            StatItem(label: "图像检测", value: "\(detectedFruits.count)", color: Design.Colors.forest)
            StatItem(
                label: "高置信度",
                value: "\(detectedFruits.filter { $0.confidence > 0.7 }.count)",
                color: Design.Colors.Dark.info
            )
        }
        .padding(Design.Space.md)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
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
                    .font(.system(size: 13))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
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

struct DetectedFruitCard: View {
    let fruit: DetectedFruit
    
    var body: some View {
        HStack(spacing: Design.Space.sm) {
            Text(fruit.category.displayName.prefix(1))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 28, height: 28)
                .background(Design.Colors.harvest.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 7))

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
        .padding(Design.Space.md)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

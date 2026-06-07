import SwiftUI

struct BatchExportHeaderBar: View {
    let selectedCount: Int
    let totalCount: Int
    let totalYield: Float
    let totalFruitCount: Int

    var body: some View {
        VStack(spacing: Design.Space.sm) {
            DashboardToolHeader(
                imageName: "FeatureBatchExport",
                title: "批量导出",
                subtitle: "选择多条扫描记录，导出字段、产量和地块标签。",
                icon: "doc.richtext",
                accent: Design.Colors.harvest
            )

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("已选择 \(selectedCount) / \(totalCount) 条记录")
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    if selectedCount > 0 {
                        Text("\(String(format: "%.1f", totalYield)) kg · \(totalFruitCount) 个果实")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }

                Spacer()
            }

            if totalCount > 0 {
                ProgressView(value: Double(selectedCount), total: Double(totalCount))
                    .tint(Design.Colors.harvest)
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
    }
}

struct BatchExportEmptyState: View {
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    var body: some View {
        VStack {
            DashboardSheetEmptyState(
                icon: "tray",
                imageName: "FeatureBatchExport",
                title: "暂无可导出的记录",
                message: "扫描或导入 PLY 文件后，可在这里批量选择并导出 CSV 或 Excel 兼容表格。",
                primaryAction: action(title: "开始扫描", icon: "viewfinder", handler: onStartScan),
                secondaryAction: action(title: "导入 PLY", icon: "square.and.arrow.down", handler: onImportFile)
            )

            Spacer()
        }
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}

struct BatchExportCompletionPanel: View {
    let url: URL
    let onShare: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Design.Colors.forest)
                .frame(width: 30, height: 30)
                .background(Design.Colors.forest.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 5) {
                Text("导出完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Button(action: onShare) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }

                    Button(action: onClear) {
                        Label("收起", systemImage: "xmark")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

struct BatchExportRecordRow: View {
    let record: ScanFileRecord
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Design.Space.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Design.Colors.harvest : Design.Colors.Dark.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(record.treeID)
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)

                    HStack(spacing: Design.Space.sm) {
                        Label("\(record.fruitCount)", systemImage: "leaf.fill")
                        Label(String(format: "%.1f kg", record.yieldKg), systemImage: "scalemass")
                        Text(record.fruitType)
                    }
                    .font(.system(size: 10))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatDate(record.scanDate))
                        .font(.system(size: 10))
                        .foregroundColor(Design.Colors.Dark.textSecondary)

                    if record.gpsLat != 0 {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Design.Colors.forest)
                    }
                }
            }
            .padding(Design.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(Design.Colors.Dark.bgDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.medium)
                            .stroke(isSelected ? Design.Colors.harvest : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

struct BatchExportFormatButton: View {
    let format: BatchExportService.ExportFormat
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.xs) {
                Image(systemName: format.icon)
                Text(format.rawValue)
            }
            .font(Design.Typography.subheadline)
            .foregroundColor(isSelected ? .white : Design.Colors.Dark.textPrimary)
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(isSelected ? Design.Colors.harvest : Design.Colors.Dark.bgDeep)
            )
        }
        .buttonStyle(.plain)
    }
}

struct BatchExportOptionToggle: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: Design.Space.xs) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(isOn ? Design.Colors.harvest : Design.Colors.Dark.textSecondary)
                Text(label)
                    .font(.system(size: 12))
            }
            .foregroundColor(Design.Colors.Dark.textPrimary)
        }
        .buttonStyle(.plain)
    }
}

struct BatchExportPrimaryButton: View {
    let selectedCount: Int
    let isExporting: Bool
    let hasCompletedExport: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.sm) {
                if isExporting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                }

                Text(buttonTitle)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(selectedCount == 0 && !isExporting ? Color.gray : Design.Colors.harvest)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var buttonTitle: String {
        if isExporting { return "取消导出" }
        if hasCompletedExport { return "重新导出 \(selectedCount) 条记录" }
        return "导出 \(selectedCount) 条记录"
    }
}

import SwiftUI

struct ImportHeader: View {
    var body: some View {
        DashboardToolHeader(
            imageName: "FeatureImportFile",
            title: "点云导入",
            subtitle: "把已有 PLY 点云加入扫描记录，用于查看、对比和后续导出。",
            icon: "square.and.arrow.down",
            accent: Design.Colors.Dark.info
        )
    }
}

struct ImportStatusPanel: View {
    let icon: String
    let title: String
    let message: String
    var tint: Color = Design.Colors.harvest
    var showsProgress: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.12))
                    .frame(width: 34, height: 34)
                if showsProgress {
                    ProgressView()
                        .scaleEffect(0.75)
                        .tint(tint)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(tint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkSurface(cornerRadius: 10)
    }
}

struct ImportRulesList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ImportRuleRow(icon: "clock.arrow.circlepath", text: "导入后会出现在扫描记录")
            ImportRuleRow(icon: "doc.badge.gearshape", text: "保留可读取的扫描元数据")
            ImportRuleRow(icon: "square.on.square", text: "同名文件会自动生成新副本")
        }
        .padding(14)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

private struct ImportRuleRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Dark.info)
                .frame(width: 18)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer(minLength: 0)
        }
    }
}

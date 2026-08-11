import SwiftUI

struct TreeMapPin: View {
    let tree: TreeAnnotation
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(tree.yieldLevel.color)
                    .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)
                    .shadow(color: tree.yieldLevel.color.opacity(0.4), radius: isSelected ? 8 : 4, y: 2)

                Image(systemName: "tree.fill")
                    .font(.system(size: isSelected ? 16 : 12, weight: .medium))
                    .foregroundColor(.white)
            }

            Triangle()
                .fill(tree.yieldLevel.color)
                .frame(width: 10, height: 6)
                .offset(y: -2)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct YieldStatMini: View {
    let level: YieldLevel
    let count: Int

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Circle().fill(level.color).frame(width: 8, height: 8)
            Text("\(count)")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
    }
}

struct TreeStatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI

/// 地图标记的可读性文案。
///
/// 标记用**结构**（实心方块 / 空心方块）表达记录是否需要复核，
/// 颜色只作强化，色觉差异用户也能分辨。
struct OrchardTreePinPresentation: Equatable {
    let symbolName: String
    let accessibilityLabel: String
    let accessibilityValue: String

    init(tree: TreeAnnotation, isSelected: Bool, bundle: Bundle = .main) {
        self = OrchardMapPresentation(bundle: bundle).treePinPresentation(
            for: tree,
            isSelected: isSelected
        )
    }

    init(symbolName: String, accessibilityLabel: String, accessibilityValue: String) {
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }
}

/// 地图上的树体标记。
///
/// 方块是全应用统一的标记形状（与果园空间的小地图一致），
/// 实心 = 可直接使用，空心 = 需要复核。触达区域固定 44×44。
struct TreeMapPin: View {
    @Environment(\.orchardMapPresentation) private var presentation
    let tree: TreeAnnotation
    let isSelected: Bool

    private var needsReview: Bool {
        ResultReviewPolicy.needsReview(tree.confidence)
    }

    var body: some View {
        let pinPresentation = presentation.treePinPresentation(
            for: tree,
            isSelected: isSelected
        )

        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(needsReview ? Color.clear : pinColor)
            .frame(width: 9, height: 9)
            .padding(4)
            .background(
                Design.Colors.Workspace.surface,
                in: RoundedRectangle(cornerRadius: 2, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(
                        needsReview ? pinColor : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(
                        isSelected ? Design.Colors.Workspace.accent : Color.clear,
                        lineWidth: 1.5
                    )
            )
            .frame(width: Design.Touch.minimumHeight, height: Design.Touch.minimumHeight)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: Design.Animation.micro), value: isSelected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(pinPresentation.accessibilityLabel))
            .accessibilityValue(Text(pinPresentation.accessibilityValue))
            .accessibilityHint(Text(presentation.selectTreeHint))
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var pinColor: Color {
        needsReview ? Design.Colors.Workspace.attention : Design.Colors.Workspace.accent
    }
}

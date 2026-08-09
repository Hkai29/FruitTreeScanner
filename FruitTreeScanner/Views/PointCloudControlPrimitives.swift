import SwiftUI

struct PointCloudMetricText: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .foregroundColor(.white.opacity(0.52))
            Text(value)
                .foregroundColor(.white.opacity(0.86))
        }
        .font(.system(.caption2, design: .monospaced, weight: .medium))
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct PointCloudViewModePicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var viewMode: PointCloudViewMode
    var isEnabled = true

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        modeButtons(expandsToFill: false)
                    }
                    .padding(.vertical, 1)
                }
            } else {
                HStack(spacing: 5) {
                    modeButtons(expandsToFill: true)
                }
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    @ViewBuilder
    private func modeButtons(expandsToFill: Bool) -> some View {
        ForEach(PointCloudViewMode.allCases, id: \.self) { mode in
            Button {
                viewMode = mode
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: mode.icon)
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                    Text(mode.displayName)
                        .font(.caption.weight(.semibold))
                        .fixedSize(horizontal: !expandsToFill, vertical: true)
                }
                .foregroundColor(viewMode == mode ? Color.black.opacity(0.82) : .white.opacity(0.82))
                .padding(.horizontal, expandsToFill ? 4 : 10)
                .frame(maxWidth: expandsToFill ? .infinity : nil, minHeight: 44)
                .fixedSize(horizontal: !expandsToFill, vertical: false)
                .background(viewMode == mode ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
                .cornerRadius(8)
            }
            .disabled(!isEnabled)
            .accessibilityLabel(mode.displayName)
            .accessibilityValue(mode.detail)
            .accessibilityAddTraits(viewMode == mode ? .isSelected : [])
            .accessibilityIdentifier("pointCloud.viewMode.\(mode.rawValue)")
        }
    }
}

struct PointCloudCircleButton: View {
    let icon: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Design.Colors.Dark.bgElevated)
                .clipShape(Circle())
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct PointCloudToolButton: View {
    let icon: String
    let label: String
    var isActive = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PointCloudToolLabel(icon: icon, label: label, isActive: isActive)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

struct PointCloudToolLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let icon: String
    let label: String
    var isActive = false

    var body: some View {
        controlLayout {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .accessibilityHidden(true)

            Text(label)
                .font(.caption2.weight(.medium))
                .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: true)
        }
        .foregroundColor(isActive ? Design.Colors.harvest : .white.opacity(0.86))
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 12 : 4)
        .padding(.vertical, 7)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, minHeight: 46)
        .fixedSize(horizontal: dynamicTypeSize.isAccessibilitySize, vertical: false)
        .background(isActive ? Design.Colors.harvest.opacity(0.18) : Design.Colors.Dark.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Design.Colors.harvest : Color.clear, lineWidth: 1)
        )
        .cornerRadius(8)
    }

    private var controlLayout: AnyLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return AnyLayout(HStackLayout(spacing: 8))
        }
        return AnyLayout(VStackLayout(spacing: 4))
    }
}

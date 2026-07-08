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
        .font(.system(size: 11, weight: .medium, design: .monospaced))
    }
}

struct PointCloudViewModePicker: View {
    @Binding var viewMode: PointCloudViewMode
    var isEnabled = true

    var body: some View {
        HStack(spacing: 5) {
            ForEach(PointCloudViewMode.allCases, id: \.self) { mode in
                Button {
                    viewMode = mode
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(viewMode == mode ? Color.black.opacity(0.82) : .white.opacity(0.82))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(viewMode == mode ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
                    .cornerRadius(8)
                }
                .disabled(!isEnabled)
                .accessibilityIdentifier("pointCloud.viewMode.\(mode.rawValue)")
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }
}

struct PointCloudCircleButton: View {
    let icon: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
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
    }
}

struct PointCloudToolLabel: View {
    let icon: String
    let label: String
    var isActive = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))

            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(isActive ? Design.Colors.harvest : .white.opacity(0.86))
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(isActive ? Design.Colors.harvest.opacity(0.18) : Design.Colors.Dark.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Design.Colors.harvest : Color.clear, lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

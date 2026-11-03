import SwiftUI
import SceneKit
import UIKit

struct MeasurementToolOverlay: View {
    @ObservedObject var controller: PointCloudMeasurementController
    @Binding var measuredDistance: Float?
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var markerDiameter: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack {
                instructionBanner(
                    in: geo,
                    distance: dynamicTypeSize.isAccessibilitySize ? controller.measuredDistance : nil
                )

                if !dynamicTypeSize.isAccessibilitySize,
                   let distance = controller.measuredDistance {
                    distanceDisplay(distance: distance)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                controller.handleTap(at: location)
                measuredDistance = controller.measuredDistance
            }
        }
        .onAppear {
            measuredDistance = controller.measuredDistance
        }
        .onChange(of: controller.measuredDistance) { newValue in
            measuredDistance = newValue
            guard let newValue else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: "\(L10n.PointCloud.measurementDistance): \(formattedDistance(newValue))"
            )
        }
    }

    private func instructionBanner(in geo: GeometryProxy, distance: Float?) -> some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            measurementMarker(
                                color: Design.Colors.Dark.warning,
                                label: L10n.PointCloud.measurementStart
                            )
                            measurementMarker(
                                color: Design.Colors.Dark.glow,
                                label: L10n.PointCloud.measurementEnd
                            )
                        }

                        Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 8 : 0)

                        closeButton
                    }

                    Text(L10n.PointCloud.measurementInstruction)
                        .font(.callout)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let distance {
                        DividerLine(color: Design.Colors.Dark.hudBorder)

                        distanceContent(distance: distance)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(Design.Space.md)
                .background(Design.Colors.Dark.bgSurface.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                        .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize
                        ? min(max(geo.size.width - 32, 0), 520)
                        : nil,
                    alignment: .trailing
                )
                .padding(.trailing, 16)
                .padding(.top, 60)
            }
            Spacer()
        }
    }

    private func measurementMarker(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: markerDiameter, height: markerDiameter)
                .accessibilityHidden(true)

            Text(label)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark.circle.fill")
                .font(.title2.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .frame(
                    minWidth: Design.Touch.minimumWidth,
                    minHeight: Design.Touch.minimumHeight
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.PointCloud.closeMeasurementAccessibility)
    }

    private func distanceDisplay(distance: Float) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                distanceContent(distance: distance)
                .padding(16)
                .background(Design.Colors.Dark.bgSurface.opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                        .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
                .padding(16)
            }
        }
    }

    private func distanceContent(distance: Float) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formattedDistance(distance))
                .font(.system(.title2, design: .monospaced).weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Text(L10n.PointCloud.measurementDistance)
                .font(.caption)
                .tracking(0.5)
                .foregroundColor(Design.Colors.Dark.textMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.PointCloud.measurementDistance)
        .accessibilityValue(formattedDistance(distance))
    }

    private func formattedDistance(_ distance: Float) -> String {
        String(format: "%.2f m", locale: Locale.current, distance)
    }
}

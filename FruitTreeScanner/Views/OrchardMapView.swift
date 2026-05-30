// OrchardMapView.swift
// Orchard Map —果园 layout with tree positions using MapKit

import SwiftUI
import MapKit

// MARK: - Tree Annotation
struct TreeAnnotation: Identifiable, Hashable {
    let id: String
    let treeID: String
    let coordinate: CLLocationCoordinate2D
    let weight: Double
    let confidence: String
    let scanDate: Date
    let fruitCount: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TreeAnnotation, rhs: TreeAnnotation) -> Bool {
        lhs.id == rhs.id
    }

    var yieldLevel: YieldLevel {
        // Classify yield: >45 = high, 35-45 = medium, <35 = low
        if weight > 45 { return .high }
        if weight >= 35 { return .medium }
        return .low
    }
}

enum YieldLevel {
    case high, medium, low

    var color: Color {
        switch self {
        case .high: return Design.Colors.Dark.success
        case .medium: return Design.Colors.Dark.warning
        case .low: return Design.Colors.Dark.error
        }
    }

    var label: String {
        switch self {
        case .high: return "高产"
        case .medium: return "中产"
        case .low: return "低产"
        }
    }

    var icon: String {
        switch self {
        case .high: return "arrow.up.circle.fill"
        case .medium: return "minus.circle.fill"
        case .low: return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Orchard Info
struct Orchard: Identifiable, Equatable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let span: MKCoordinateSpan

    static func == (lhs: Orchard, rhs: Orchard) -> Bool {
        lhs.id == rhs.id
    }

    static let mockOrchards: [Orchard] = [
        Orchard(id: "east-south", name: "东南示范园", coordinate: CLLocationCoordinate2D(latitude: 30.5728, longitude: 114.2525), span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)),
        Orchard(id: "north", name: "北坡试验园", coordinate: CLLocationCoordinate2D(latitude: 30.5780, longitude: 114.2500), span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)),
    ]
}

// MARK: - OrchardMapView
@available(iOS 17, *)
struct OrchardMapView: View {
    @ObservedObject var historyStore = ScanHistoryStore.shared
    @State private var selectedOrchard: Orchard?
    @State private var selectedTree: TreeAnnotation?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var showOrchardPicker = false
    @State private var filterYieldLevel: YieldLevel?
    @State private var hasLoadedRealData = false

    var realTrees: [TreeAnnotation] {
        historyStore.scanFiles
            .filter { $0.gpsLat != 0 && $0.gpsLon != 0 }
            .map { record in
                TreeAnnotation(
                    id: record.id,
                    treeID: record.treeID,
                    coordinate: CLLocationCoordinate2D(latitude: record.gpsLat, longitude: record.gpsLon),
                    weight: Double(record.yieldKg),
                    confidence: "medium",
                    scanDate: record.scanDate,
                    fruitCount: record.fruitCount
                )
            }
    }

    var trees: [TreeAnnotation] {
        realTrees
    }

    var filteredTrees: [TreeAnnotation] {
        if let filter = filterYieldLevel {
            return trees.filter { $0.yieldLevel == filter }
        }
        return trees
    }

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()

            if trees.isEmpty {
                // Empty state - no real scan data
                emptyStateView
            } else {
                // Map with real data
                mapView
            }
        }
        .overlay(FingerGlowOverlay())
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
        .sheet(isPresented: $showOrchardPicker) {
            OrchardPickerView(orchards: Orchard.mockOrchards, selectedOrchard: $selectedOrchard) {
                updateMapRegion()
            }
        }
        .onAppear {
            historyStore.loadRecords()
            updateMapRegion()
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 60))
                .foregroundColor(Design.Colors.Dark.glassBorder)

            Text("暂无果园数据")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Text("请先完成果树扫描")
                .font(.system(size: 14))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Design.Colors.Dark.bgDeep)
        .ignoresSafeArea()
    }

    private var mapView: some View {
        ZStack {
            // Map
            Map(position: $mapCameraPosition, selection: $selectedTree) {
                ForEach(filteredTrees) { tree in
                    Annotation(tree.treeID, coordinate: tree.coordinate, anchor: .bottom) {
                        TreeMapPin(tree: tree, isSelected: selectedTree?.id == tree.id)
                    }
                    .tag(tree)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .ignoresSafeArea()

            // Overlay UI
            VStack {
                // Top Bar
                topBar
                    .padding(.top, Design.Space.md)

                Spacer()

                // Bottom Content
                bottomContent
            }
            .padding(Design.Space.lg)
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack(spacing: Design.Space.md) {
            // Back Button
            Button {
                // Navigate back
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Circle())
                    .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
            }

            Spacer()

            // Stats info
            if !trees.isEmpty {
                Text("\(trees.count) 棵果树")
                    .font(Design.Typography.subheadlineMedium)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.sm)
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Capsule())
                    .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
            }
        }
    }

    // MARK: - Bottom Content
    private var bottomContent: some View {
        VStack(spacing: Design.Space.md) {
            // Legend
            legendView

            // Selected Tree Detail or Tree Count
            if let tree = selectedTree {
                selectedTreeDetail(tree)
            } else {
                treeCountCard
            }
        }
    }

    // MARK: - Legend View
    private var legendView: some View {
        HStack(spacing: Design.Space.lg) {
            ForEach([YieldLevel.high, .medium, .low], id: \.self) { level in
                Button {
                    if filterYieldLevel == level {
                        filterYieldLevel = nil
                    } else {
                        filterYieldLevel = level
                    }
                } label: {
                    HStack(spacing: Design.Space.xs) {
                        Circle()
                            .fill(level.color)
                            .frame(width: 10, height: 10)

                        Text(level.label)
                            .font(Design.Typography.caption)
                            .foregroundColor(filterYieldLevel == level ? level.color : Design.Colors.Dark.textPrimary)
                    }
                    .padding(.horizontal, Design.Space.sm)
                    .padding(.vertical, Design.Space.xs)
                    .background(filterYieldLevel == level ? level.color.opacity(0.1) : Color.clear)
                    .cornerRadius(Design.Radius.full)
                }
            }

            Spacer()

            // Clear filter
            if filterYieldLevel != nil {
                Button {
                    filterYieldLevel = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.Dark.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }

    // MARK: - Tree Count Card
    private var treeCountCard: some View {
        HStack(spacing: Design.Space.md) {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text("园区树木")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Text("\(filteredTrees.count) 棵")
                    .font(Design.Typography.title2)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            Spacer()

            // Stats mini view
            HStack(spacing: Design.Space.lg) {
                YieldStatMini(level: .high, count: filteredTrees.filter { $0.yieldLevel == .high }.count)
                YieldStatMini(level: .medium, count: filteredTrees.filter { $0.yieldLevel == .medium }.count)
                YieldStatMini(level: .low, count: filteredTrees.filter { $0.yieldLevel == .low }.count)
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.Dark.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }

    // MARK: - Selected Tree Detail
    private func selectedTreeDetail(_ tree: TreeAnnotation) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            // Header
            HStack {
                HStack(spacing: Design.Space.sm) {
                    Image(systemName: tree.yieldLevel.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(tree.yieldLevel.color)

                    Text("树 #\(tree.treeID)")
                        .font(Design.Typography.headline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                }

                Spacer()

                Button {
                    selectedTree = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Design.Colors.Dark.bgSurface)
                        .clipShape(Circle())
                }
            }

            DividerLine()

            // Stats Row
            HStack(spacing: Design.Space.xl) {
                TreeStatItem(label: "预估产量", value: String(format: "%.1f kg", tree.weight), color: Design.Colors.Dark.glow)
                TreeStatItem(label: "果实数", value: "\(tree.fruitCount) 个", color: Design.Colors.Dark.glow)
                TreeStatItem(label: "置信度", value: confidenceLabel(tree.confidence), color: confidenceColor(tree.confidence))
                TreeStatItem(label: "扫描日期", value: formatDate(tree.scanDate), color: Design.Colors.Dark.textSecondary)
            }

            // Yield Level Badge
            HStack {
                Text("产量等级")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Spacer()

                HStack(spacing: Design.Space.xs) {
                    Circle()
                        .fill(tree.yieldLevel.color)
                        .frame(width: 8, height: 8)

                    Text(tree.yieldLevel.label)
                        .font(Design.Typography.captionMedium)
                        .foregroundColor(tree.yieldLevel.color)
                }
                .padding(.horizontal, Design.Space.sm)
                .padding(.vertical, Design.Space.xs)
                .background(tree.yieldLevel.color.opacity(0.1))
                .cornerRadius(Design.Radius.full)
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.Dark.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }

    private func confidenceLabel(_ confidence: String) -> String {
        switch confidence {
        case "high": return "高"
        case "medium": return "中"
        default: return "低"
        }
    }

    private func confidenceColor(_ confidence: String) -> Color {
        switch confidence {
        case "high": return Design.Colors.Dark.success
        case "medium": return Design.Colors.Dark.warning
        default: return Design.Colors.Dark.error
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    // MARK: - Helpers
    private func updateMapRegion() {
        if let firstTree = trees.first {
            // Calculate a span based on tree distribution
            let latValues = trees.map { $0.coordinate.latitude }
            let lonValues = trees.map { $0.coordinate.longitude }

            let minLat = latValues.min() ?? firstTree.coordinate.latitude
            let maxLat = latValues.max() ?? firstTree.coordinate.latitude
            let minLon = lonValues.min() ?? firstTree.coordinate.longitude
            let maxLon = lonValues.max() ?? firstTree.coordinate.longitude

            let latDelta = max((maxLat - minLat) * 1.5, 0.005)
            let lonDelta = max((maxLon - minLon) * 1.5, 0.005)

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )

            mapCameraPosition = .region(MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)))
        }
    }
}

// MARK: - Tree Map Pin
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

            // Triangle pointer
            Triangle()
                .fill(tree.yieldLevel.color)
                .frame(width: 10, height: 6)
                .offset(y: -2)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

// MARK: - Triangle Shape
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Yield Stat Mini
struct YieldStatMini: View {
    let level: YieldLevel
    let count: Int

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Circle()
                .fill(level.color)
                .frame(width: 8, height: 8)

            Text("\(count)")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
    }
}

// MARK: - Tree Stat Item
struct TreeStatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text(value)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Orchard Picker View
struct OrchardPickerView: View {
    let orchards: [Orchard]
    @Binding var selectedOrchard: Orchard?
    let onSelect: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                ScrollView {
                    LazyVStack(spacing: Design.Space.md) {
                        ForEach(orchards) { orchard in
                            Button {
                                selectedOrchard = orchard
                                onSelect()
                                dismiss()
                            } label: {
                                HStack(spacing: Design.Space.md) {
                                    ZStack {
                                        Circle()
                                            .fill(orchard.id == selectedOrchard?.id ? Design.Colors.Dark.glow.opacity(0.12) : Design.Colors.Dark.bgSurface)
                                            .frame(width: 44, height: 44)

                                        Image(systemName: "leaf.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(orchard.id == selectedOrchard?.id ? Design.Colors.Dark.glow : Design.Colors.Dark.textSecondary)
                                    }

                                    Text(orchard.name)
                                        .font(Design.Typography.subheadlineMedium)
                                        .foregroundColor(Design.Colors.Dark.textPrimary)

                                    Spacer()

                                    if orchard.id == selectedOrchard?.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(Design.Colors.Dark.glow)
                                    }
                                }
                                .padding(Design.Space.md)
                                .background(Design.Colors.Dark.bgSurface)
                                .cornerRadius(Design.Radius.large)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.Radius.large)
                                        .stroke(orchard.id == selectedOrchard?.id ? Design.Colors.Dark.glow : Color.clear, lineWidth: 2)
                                )
                            }
                        }
                    }
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle("选择果园")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    if #available(iOS 17, *) {
        OrchardMapView()
    } else {
        Text("需要 iOS 17")
    }
}

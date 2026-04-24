// OrchardMapView.swift
// Orchard Map —果园 layout with tree positions using MapKit

import SwiftUI
import MapKit

// MARK: - Tree Annotation
struct TreeAnnotation: Identifiable, Hashable {
    let id: String
    let treeID: String
    let coordinate: CLLocationCoordinate2D
    let yieldKg: Double
    let confidence: String
    let scanDate: Date

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TreeAnnotation, rhs: TreeAnnotation) -> Bool {
        lhs.id == rhs.id
    }

    var yieldLevel: YieldLevel {
        // Classify yield: >45 = high, 35-45 = medium, <35 = low
        if yieldKg > 45 { return .high }
        if yieldKg >= 35 { return .medium }
        return .low
    }
}

enum YieldLevel {
    case high, medium, low

    var color: Color {
        switch self {
        case .high: return Design.Colors.success
        case .medium: return Design.Colors.warning
        case .low: return Design.Colors.error
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
    @State private var selectedOrchard: Orchard = .mockOrchards[0]
    @State private var selectedTree: TreeAnnotation?
    @State private var trees: [TreeAnnotation] = []
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var showOrchardPicker = false
    @State private var filterYieldLevel: YieldLevel?

    // TODO: Load from backend API
    private let mockTrees: [TreeAnnotation] = [
        TreeAnnotation(id: "t001", treeID: "T001", coordinate: CLLocationCoordinate2D(latitude: 30.5728, longitude: 114.2525), yieldKg: 48.2, confidence: "high", scanDate: Date()),
        TreeAnnotation(id: "t002", treeID: "T002", coordinate: CLLocationCoordinate2D(latitude: 30.5730, longitude: 114.2527), yieldKg: 42.5, confidence: "high", scanDate: Date()),
        TreeAnnotation(id: "t003", treeID: "T003", coordinate: CLLocationCoordinate2D(latitude: 30.5726, longitude: 114.2523), yieldKg: 38.1, confidence: "medium", scanDate: Date()),
        TreeAnnotation(id: "t004", treeID: "T004", coordinate: CLLocationCoordinate2D(latitude: 30.5732, longitude: 114.2530), yieldKg: 51.3, confidence: "high", scanDate: Date()),
        TreeAnnotation(id: "t005", treeID: "T005", coordinate: CLLocationCoordinate2D(latitude: 30.5725, longitude: 114.2520), yieldKg: 32.8, confidence: "medium", scanDate: Date()),
        TreeAnnotation(id: "t006", treeID: "T006", coordinate: CLLocationCoordinate2D(latitude: 30.5734, longitude: 114.2528), yieldKg: 45.6, confidence: "high", scanDate: Date()),
    ]

    var filteredTrees: [TreeAnnotation] {
        if let filter = filterYieldLevel {
            return trees.filter { $0.yieldLevel == filter }
        }
        return trees
    }

    var body: some View {
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
        .navigationBarHidden(true)
        .sheet(isPresented: $showOrchardPicker) {
            OrchardPickerView(orchards: Orchard.mockOrchards, selectedOrchard: $selectedOrchard) {
                updateMapRegion()
            }
        }
        .onAppear {
            trees = mockTrees
            updateMapRegion()
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
                    .foregroundColor(Design.Colors.charcoal)
                    .frame(width: 36, height: 36)
                    .background(Design.Colors.bgSurface)
                    .clipShape(Circle())
                    .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
            }

            Spacer()

            // Orchard Selector
            Button {
                showOrchardPicker = true
            } label: {
                HStack(spacing: Design.Space.sm) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Design.Colors.forest)

                    Text(selectedOrchard.name)
                        .font(Design.Typography.subheadlineMedium)
                        .foregroundColor(Design.Colors.charcoal)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Design.Colors.slate)
                }
                .padding(.horizontal, Design.Space.md)
                .padding(.vertical, Design.Space.sm)
                .background(Design.Colors.bgSurface)
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
                            .foregroundColor(filterYieldLevel == level ? level.color : Design.Colors.charcoal)
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
                        .foregroundColor(Design.Colors.slate)
                }
            }
        }
        .padding(Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.large)
                .fill(Design.Colors.bgSurface)
                .shadow(color: Design.Shadow.subtle.color, radius: 4, y: 2)
        )
    }

    // MARK: - Tree Count Card
    private var treeCountCard: some View {
        HStack(spacing: Design.Space.md) {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text("园区树木")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.slate)

                Text("\(filteredTrees.count) 棵")
                    .font(Design.Typography.title2)
                    .foregroundColor(Design.Colors.charcoal)
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
                .fill(Design.Colors.bgSurface)
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
                        .foregroundColor(Design.Colors.charcoal)
                }

                Spacer()

                Button {
                    selectedTree = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Design.Colors.slate)
                        .frame(width: 28, height: 28)
                        .background(Design.Colors.stone)
                        .clipShape(Circle())
                }
            }

            DividerLine()

            // Stats Row
            HStack(spacing: Design.Space.xl) {
                TreeStatItem(label: "预估产量", value: String(format: "%.1f kg", tree.yieldKg), color: Design.Colors.forest)

                TreeStatItem(label: "置信度", value: confidenceLabel(tree.confidence), color: confidenceColor(tree.confidence))

                TreeStatItem(label: "扫描日期", value: formatDate(tree.scanDate), color: Design.Colors.slate)
            }

            // Yield Level Badge
            HStack {
                Text("产量等级")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.slate)

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
                .fill(Design.Colors.bgSurface)
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
        case "high": return Design.Colors.success
        case "medium": return Design.Colors.warning
        default: return Design.Colors.error
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    // MARK: - Helpers
    private func updateMapRegion() {
        mapCameraPosition = .region(MKCoordinateRegion(center: selectedOrchard.coordinate, span: selectedOrchard.span))
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
                .foregroundColor(Design.Colors.charcoal)
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
                .foregroundColor(Design.Colors.slate)

            Text(value)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(color)
        }
    }
}

// MARK: - Orchard Picker View
struct OrchardPickerView: View {
    let orchards: [Orchard]
    @Binding var selectedOrchard: Orchard
    let onSelect: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.bgBase
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
                                            .fill(orchard.id == selectedOrchard.id ? Design.Colors.forest.opacity(0.12) : Design.Colors.stone)
                                            .frame(width: 44, height: 44)

                                        Image(systemName: "leaf.fill")
                                            .font(.system(size: 18, weight: .medium))
                                            .foregroundColor(orchard.id == selectedOrchard.id ? Design.Colors.forest : Design.Colors.slate)
                                    }

                                    Text(orchard.name)
                                        .font(Design.Typography.subheadlineMedium)
                                        .foregroundColor(Design.Colors.charcoal)

                                    Spacer()

                                    if orchard.id == selectedOrchard.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundColor(Design.Colors.forest)
                                    }
                                }
                                .padding(Design.Space.md)
                                .background(Design.Colors.bgSurface)
                                .cornerRadius(Design.Radius.large)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Design.Radius.large)
                                        .stroke(orchard.id == selectedOrchard.id ? Design.Colors.forest : Color.clear, lineWidth: 2)
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

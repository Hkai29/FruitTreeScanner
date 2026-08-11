// OrchardMapView.swift
// 果园地图主容器

import SwiftUI
import MapKit

@available(iOS 17, *)
struct OrchardMapView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var historyStore = ScanHistoryStore.shared
    private let onStartScan: (() -> Void)?
    private let bundle: Bundle
    @State private var selectedTree: TreeAnnotation?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var filterYieldLevel: YieldLevel?

    init(onStartScan: (() -> Void)? = nil, bundle: Bundle = .main) {
        self.onStartScan = onStartScan
        self.bundle = bundle
    }

    private var trees: [TreeAnnotation] {
        OrchardMapData(records: historyStore.scanFiles).trees
    }

    private var filteredTrees: [TreeAnnotation] {
        if let filterYieldLevel {
            return trees.filter { $0.yieldLevel == filterYieldLevel }
        }
        return trees
    }

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()

            if trees.isEmpty {
                OrchardMapEmptyState(onStartScan: onStartScan)
            } else {
                mapView
            }

            VStack {
                OrchardMapTopBar(
                    treeCount: trees.count,
                    onDismiss: { dismiss() }
                )
                .padding(.top, Design.Space.md)

                Spacer()
            }
            .padding(Design.Space.lg)
        }
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
        .environment(\.orchardMapPresentation, OrchardMapPresentation(bundle: bundle))
        .onAppear(perform: loadAndFrameMap)
        .onChange(of: historyStore.scanFiles) { _ in
            updateMapRegion()
        }
    }

    private var mapView: some View {
        ZStack {
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

            mapOverlay
        }
    }

    private var mapOverlay: some View {
        GeometryReader { geometry in
            VStack {
                Spacer()

                OrchardMapBottomPanel(
                    selectedTree: selectedTree,
                    filteredTrees: filteredTrees,
                    filterYieldLevel: $filterYieldLevel,
                    maximumHeight: max(240, geometry.size.height - 160),
                    onClearSelection: { selectedTree = nil }
                )
            }
        }
        .padding(Design.Space.lg)
    }

    private func loadAndFrameMap() {
        historyStore.loadRecords()
        updateMapRegion()
    }

    private func updateMapRegion() {
        guard let region = OrchardMapRegionCalculator.region(for: trees) else { return }
        mapCameraPosition = .region(region)
    }
}

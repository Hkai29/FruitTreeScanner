// OrchardMapView.swift
// 果园地图主容器

import SwiftUI
import MapKit

@available(iOS 17, *)
struct OrchardMapView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var historyStore = ScanHistoryStore.shared
    var onStartScan: (() -> Void)? = nil
    @State private var selectedTree: TreeAnnotation?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var filterYieldLevel: YieldLevel?

    private var realTrees: [TreeAnnotation] {
        historyStore.scanFiles
            .filter { $0.gpsLat != 0 && $0.gpsLon != 0 }
            .map(TreeAnnotation.init(record:))
    }

    private var trees: [TreeAnnotation] {
        realTrees
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
        }
        .preferredColorScheme(.dark)
        .navigationBarHidden(true)
        .onAppear(perform: loadAndFrameMap)
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
        VStack {
            OrchardMapTopBar(
                treeCount: trees.count,
                onDismiss: { dismiss() }
            )
                .padding(.top, Design.Space.md)

            Spacer()

            OrchardMapBottomPanel(
                selectedTree: selectedTree,
                filteredTrees: filteredTrees,
                filterYieldLevel: $filterYieldLevel,
                onClearSelection: { selectedTree = nil }
            )
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

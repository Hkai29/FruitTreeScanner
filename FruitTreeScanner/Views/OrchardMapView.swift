// OrchardMapView.swift
// 果园地图主容器

import SwiftUI
import MapKit

@available(iOS 17, *)
struct OrchardMapView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var historyStore: ScanHistoryStore
    private let onStartScan: (() -> Void)?
    private let bundle: Bundle
    @State private var selectedTreeID: String?
    @State private var mapCameraPosition: MapCameraPosition = .automatic
    @State private var filterYieldLevel: YieldLevel?

    @MainActor
    init(onStartScan: (() -> Void)? = nil, bundle: Bundle = .main, historyStore: ScanHistoryStore? = nil) {
        self.onStartScan = onStartScan
        self.bundle = bundle
        self.historyStore = historyStore ?? .shared
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

    private var selectedTree: TreeAnnotation? {
        guard let selectedTreeID else { return nil }
        return filteredTrees.first { $0.id == selectedTreeID }
    }

    private var selectedTreeBinding: Binding<TreeAnnotation?> {
        Binding(
            get: { selectedTree },
            set: { selection in
                selectedTreeID = selection.flatMap { selected in
                    filteredTrees.first { $0.id == selected.id }?.id
                }
            }
        )
    }

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep
                .ignoresSafeArea()

            if trees.isEmpty {
                OrchardMapEmptyState(onStartScan: onStartScan, bundle: bundle)
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
            clearUnavailableSelection()
            updateMapRegion()
        }
        .onChange(of: filterYieldLevel) { _ in
            clearUnavailableSelection()
        }
    }

    private var mapView: some View {
        ZStack {
            Map(position: $mapCameraPosition, selection: selectedTreeBinding) {
                ForEach(filteredTrees) { tree in
                    Annotation(tree.treeID, coordinate: tree.coordinate, anchor: .bottom) {
                        TreeMapPin(tree: tree, isSelected: selectedTreeID == tree.id)
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
                    onClearSelection: { selectedTreeID = nil }
                )
            }
        }
        .padding(Design.Space.lg)
    }

    private func loadAndFrameMap() {
        historyStore.loadRecords()
        updateMapRegion()
    }

    private func clearUnavailableSelection() {
        if selectedTreeID != nil && selectedTree == nil {
            selectedTreeID = nil
        }
    }

    private func updateMapRegion() {
        guard let region = OrchardMapRegionCalculator.region(for: trees) else { return }
        mapCameraPosition = .region(region)
    }
}

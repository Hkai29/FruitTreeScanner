// StartView.swift
// 新建扫描 - 5步引导式设计

import SwiftUI

struct StartView: View {
    var onLaunchScan: (ScanLaunchRequest) -> Void

    @Environment(\.dismiss) private var dismiss

    @ObservedObject var tagStore = TagStore.shared
    @State var currentStep = 1
    @State var treeID = ""
    @State var isTreeIDValid = false
    @State var selectedPlotId: UUID?
    @State var season: Season = .mature
    @State var selectedTagIds: Set<UUID> = []
    @State var selectedFruitCategory = FruitCategory.scanCategory(for: SettingsStore.shared.fruitType)
    @StateObject var launchGate = ScanLaunchSubmissionGate()
    @State var presentedSheet: StartViewSheet?
    @State var gps = GPSRecorder()

    let totalSteps = 5

    var isLaunchingScan: Bool {
        launchGate.isSubmitting
    }

    var body: some View {
        StartViewLayout(
            currentStep: currentStep,
            totalSteps: totalSteps,
            canGoBack: currentStep > 1,
            canGoNext: canGoNext && !isLaunchingScan,
            isLaunchingScan: isLaunchingScan,
            header: stepHeader,
            onCancel: dismiss.callAsFunction,
            onBack: goBack,
            onNext: goNext,
            stepContent: { stepContent }
        )
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .addPlot:
                PlotEditView(onSave: { newPlot in
                    tagStore.addPlot(name: newPlot.name, colorHex: newPlot.colorHex)
                })
            case .addTag:
                TagEditView(onSave: { newTag in
                    tagStore.addTag(name: newTag.name, colorHex: newTag.colorHex)
                })
            }
        }
        .onChange(of: tagStore.plots) { _ in
            normalizeClassificationSelection()
        }
        .onChange(of: tagStore.tags) { _ in
            normalizeClassificationSelection()
        }
    }

    @ViewBuilder
    var stepContent: some View {
        switch currentStep {
        case 1:
            Step1_IDEntry(treeID: $treeID, isValid: $isTreeIDValid)
        case 2:
            Step2_PlotSelection(
                plots: tagStore.plots,
                selectedPlotId: $selectedPlotId,
                onAddPlot: { presentedSheet = .addPlot }
            )
        case 3:
            Step3_SeasonSelection(season: $season)
        case 4:
            Step4_TagSelection(
                tags: tagStore.tags,
                selectedTagIds: $selectedTagIds,
                onAddTag: { presentedSheet = .addTag }
            )
        case 5:
            Step5_Confirmation(
                treeID: treeID,
                plot: selectedPlot,
                season: season,
                selectedFruitCategory: $selectedFruitCategory,
                tags: selectedTags,
                gps: gps
            )
        default:
            EmptyView()
        }
    }
}

enum StartViewSheet: Identifiable {
    case addPlot
    case addTag

    var id: String {
        switch self {
        case .addPlot: return "add-plot"
        case .addTag: return "add-tag"
        }
    }
}

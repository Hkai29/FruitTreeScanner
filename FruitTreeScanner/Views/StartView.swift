// StartView.swift
// 新建扫描 - 5步引导式设计

import SwiftUI
import UIKit

struct ScanLaunchRequest: Identifiable {
    let id = UUID()
    let treeID: String
    let season: Season
    let gps: GPSRecorder
    let plotId: UUID?
    let tagIds: [UUID]

    init(
        treeID: String,
        season: Season,
        gps: GPSRecorder,
        plotId: UUID? = nil,
        tagIds: [UUID] = []
    ) {
        self.treeID = treeID
        self.season = season
        self.gps = gps
        self.plotId = plotId
        self.tagIds = tagIds
    }
}

struct StartView: View {
    var onLaunchScan: (ScanLaunchRequest) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 1
    @State private var treeID = ""
    @State private var isTreeIDValid = false
    @State private var selectedPlotId: UUID?
    @State private var season: Season = .mature
    @State private var selectedTagIds: Set<UUID> = []
    @State private var isLaunchingScan = false
    @State private var showPlotEdit = false
    @State private var showTagEdit = false
    @State private var gps = GPSRecorder()

    @ObservedObject private var tagStore = TagStore.shared

    private let totalSteps = 5

    private var canGoNext: Bool {
        switch currentStep {
        case 1: return isTreeIDValid
        default: return true
        }
    }

    private var selectedPlot: Plot? {
        selectedPlotId.flatMap { tagStore.getPlot(id: $0) }
    }

    private var selectedTags: [GroupTag] {
        tagStore.tags.filter { selectedTagIds.contains($0.id) }
    }

    private var stepHeader: (imageName: String, title: String, subtitle: String, icon: String, accent: Color) {
        switch currentStep {
        case 1:
            return (
                "FeatureStartScan",
                "果树编号",
                "先建立可追踪的树体档案，后续记录会自动归到这个编号。",
                "number",
                Design.Colors.harvest
            )
        case 2:
            return (
                "FeatureMap",
                "地块归档",
                "把扫描挂到对应地块，便于之后按区域筛选和汇总。",
                "map.fill",
                Design.Colors.forest
            )
        case 3:
            return (
                "FeatureYieldReport",
                "估算阶段",
                "选择成熟期或非成熟期，系统会采用对应的产量估算路径。",
                "chart.bar.fill",
                Design.Colors.harvest
            )
        case 4:
            return (
                "FeatureTagManagement",
                "标签分组",
                "用标签标记品种、试验组或管理状态，方便后续复盘。",
                "tag.fill",
                Design.Colors.forest
            )
        default:
            return (
                "FeatureQuickScan",
                "启动扫描",
                "确认信息后进入 LiDAR 采集，请围绕树体缓慢移动。",
                "viewfinder",
                Design.Colors.harvest
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let isLandscape = proxy.size.width > proxy.size.height && proxy.size.width >= 760

            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                if isLandscape {
                    landscapeContent(width: proxy.size.width)
                } else {
                    portraitContent
                }
            }
        }
        .sheet(isPresented: $showPlotEdit) {
            PlotEditView(onSave: { newPlot in
                TagStore.shared.addPlot(name: newPlot.name, colorHex: newPlot.colorHex)
            })
        }
        .sheet(isPresented: $showTagEdit) {
            TagEditView(onSave: { newTag in
                TagStore.shared.addTag(name: newTag.name, colorHex: newTag.colorHex)
            })
        }
    }

    private var portraitContent: some View {
        VStack(spacing: 0) {
            topNavigation

            StepProgressView(currentStep: currentStep, totalSteps: totalSteps)
                .padding(.top, Design.Space.xs)

            ScrollView {
                VStack(spacing: Design.Space.lg) {
                    stepToolHeader

                    stepContent
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, Design.Space.lg)
                .padding(.top, Design.Space.lg)
                .padding(.bottom, Design.Space.xl)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomNavigation
        }
    }

    private func landscapeContent(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            topNavigation

            HStack(alignment: .top, spacing: Design.Space.lg) {
                VStack(alignment: .leading, spacing: Design.Space.lg) {
                    stepToolHeader

                    StepProgressView(currentStep: currentStep, totalSteps: totalSteps)
                        .padding(.horizontal, -Design.Space.lg)

                    Spacer(minLength: Design.Space.sm)
                }
                .frame(width: min(330, width * 0.34), alignment: .topLeading)

                ScrollView {
                    stepContent
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, Design.Space.xl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, Design.Space.lg)
            .padding(.top, Design.Space.md)

            bottomNavigation
        }
    }

    private var stepToolHeader: some View {
        DashboardToolHeader(
            imageName: stepHeader.imageName,
            title: stepHeader.title,
            subtitle: stepHeader.subtitle,
            icon: stepHeader.icon,
            accent: stepHeader.accent
        )
    }

    private var bottomNavigation: some View {
        StepNavigationBar(
            currentStep: currentStep,
            totalSteps: totalSteps,
            canGoBack: currentStep > 1,
            canGoNext: canGoNext && !isLaunchingScan,
            isLaunching: isLaunchingScan,
            onBack: goBack,
            onNext: goNext
        )
        .padding(.horizontal, Design.Space.lg)
        .padding(.bottom, Design.Space.lg)
    }

    private var topNavigation: some View {
        HStack {
            Button("取消", action: dismiss.callAsFunction)
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(Design.Colors.harvest)

            Spacer()

            Text("新建扫描")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Spacer()

            Text("取消")
                .font(.system(size: 16, weight: .medium))
                .hidden()
                .accessibilityHidden(true)
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.md)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 1:
            Step1_IDEntry(treeID: $treeID, isValid: $isTreeIDValid)
        case 2:
            Step2_PlotSelection(
                plots: tagStore.plots,
                selectedPlotId: $selectedPlotId,
                onAddPlot: { showPlotEdit = true }
            )
        case 3:
            Step3_SeasonSelection(season: $season)
        case 4:
            Step4_TagSelection(
                tags: tagStore.tags,
                selectedTagIds: $selectedTagIds,
                onAddTag: { showTagEdit = true }
            )
        case 5:
            Step5_Confirmation(
                treeID: treeID,
                plot: selectedPlot,
                season: season,
                tags: selectedTags,
                gps: gps
            )
        default:
            EmptyView()
        }
    }

    private func goBack() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if currentStep > 1 {
                currentStep -= 1
            }
        }
    }

    private func goNext() {
        if currentStep < totalSteps {
            withAnimation(.easeInOut(duration: 0.3)) {
                currentStep += 1
            }
        } else {
            launchScan()
        }
    }

    private func launchScan() {
        guard !isLaunchingScan else { return }
        isLaunchingScan = true
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let normalizedTreeID = treeID.trimmingCharacters(in: .whitespaces)
            guard !normalizedTreeID.isEmpty else {
                isLaunchingScan = false
                return
            }
            let request = ScanLaunchRequest(
                treeID: normalizedTreeID,
                season: season,
                gps: gps,
                plotId: selectedPlotId,
                tagIds: Array(selectedTagIds)
            )

            onLaunchScan(request)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isLaunchingScan = false
        }
    }
}

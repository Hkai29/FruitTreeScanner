import SwiftUI

struct BatchExportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ScanHistoryStore.shared
    @ObservedObject private var tagStore = TagStore.shared
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil
    @State private var selectedRecords: Set<String> = []
    @State private var exportFormat: BatchExportService.ExportFormat = .csv
    @State private var exportOptions = BatchExportService.ExportOptions()
    @State private var exportedURL: URL?
    @State private var isExporting = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showShareSheet = false
    @State private var exportTask: Task<Void, Never>?
    
    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                VStack(spacing: 0) {
                    if store.scanFiles.isEmpty {
                        BatchExportEmptyState(
                            onStartScan: onStartScan,
                            onImportFile: onImportFile
                        )
                    } else {
                        let summary = calculateSelectedSummary()
                        BatchExportHeaderBar(
                            selectedCount: selectedRecords.count,
                            totalCount: store.scanFiles.count,
                            totalYield: summary.totalYield,
                            totalFruitCount: summary.totalCount
                        )
                        recordListView
                        exportOptionsView
                        if let exportedURL {
                            BatchExportCompletionPanel(
                                url: exportedURL,
                                onShare: { showShareSheet = true },
                                onClear: { self.exportedURL = nil }
                            )
                            .padding(.horizontal, Design.Space.md)
                            .padding(.top, Design.Space.md)
                        }
                        BatchExportPrimaryButton(
                            selectedCount: selectedRecords.count,
                            isExporting: isExporting,
                            hasCompletedExport: exportedURL != nil,
                            action: {
                                if isExporting {
                                    cancelExport()
                                } else {
                                    performExport()
                                }
                            }
                        )
                        .disabled(selectedRecords.isEmpty && !isExporting)
                        .padding(Design.Space.md)
                    }
                }
            }
            .navigationTitle("批次导出")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if !store.scanFiles.isEmpty {
                        Button(selectedRecords.count == store.scanFiles.count ? "取消全选" : "全选") {
                            toggleSelectAll()
                        }
                        .disabled(isExporting)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
        .alert("导出错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            store.loadRecords()
            selectAllIfNeeded()
        }
        .onChange(of: store.scanFiles) { files in
            pruneSelection(to: files)
            selectAllIfNeeded()
        }
        .onDisappear {
            cancelExport()
        }
    }
    
    private var recordListView: some View {
        ScrollView {
            LazyVStack(spacing: Design.Space.sm) {
                ForEach(store.scanFiles) { record in
                    BatchExportRecordRow(
                        record: record,
                        isSelected: selectedRecords.contains(record.id),
                        onToggle: { toggleSelection(record.id) }
                    )
                }
            }
            .padding(Design.Space.md)
        }
    }
    
    private var exportOptionsView: some View {
        VStack(spacing: Design.Space.md) {
            formatSelector
            
            optionsSection
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
    }
    
    private var formatSelector: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("导出格式")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            
            HStack(spacing: Design.Space.md) {
                ForEach(BatchExportService.ExportFormat.allCases, id: \.self) { format in
                    BatchExportFormatButton(
                        format: format,
                        isSelected: exportFormat == format,
                        action: {
                            exportFormat = format
                            exportedURL = nil
                        }
                    )
                }
            }
        }
    }
    
    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("包含字段")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            
            FlowLayout(spacing: Design.Space.sm) {
                BatchExportOptionToggle(label: "果树编号", isOn: optionBinding(\.includeTreeID))
                BatchExportOptionToggle(label: "果实数量", isOn: optionBinding(\.includeFruitCount))
                BatchExportOptionToggle(label: "产量", isOn: optionBinding(\.includeYield))
                BatchExportOptionToggle(label: "GPS位置", isOn: optionBinding(\.includeGPS))
                BatchExportOptionToggle(label: "扫描日期", isOn: optionBinding(\.includeDate))
            }

            Divider()
                .background(Design.Colors.Dark.glassBorder)

            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text("分组方式")
                    .font(Design.Typography.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Picker("分组方式", selection: $exportOptions.groupBy) {
                    ForEach(BatchExportService.ExportOptions.GroupByOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: exportOptions.groupBy) { _ in
                    exportedURL = nil
                }
            }
        }
    }

    private func optionBinding(_ keyPath: WritableKeyPath<BatchExportService.ExportOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { exportOptions[keyPath: keyPath] },
            set: { newValue in
                exportOptions[keyPath: keyPath] = newValue
                exportedURL = nil
            }
        )
    }
    
    private func toggleSelection(_ id: String) {
        exportedURL = nil
        if selectedRecords.contains(id) {
            selectedRecords.remove(id)
        } else {
            selectedRecords.insert(id)
        }
    }
    
    private func toggleSelectAll() {
        exportedURL = nil
        if selectedRecords.count == store.scanFiles.count {
            selectedRecords.removeAll()
        } else {
            selectedRecords = Set(store.scanFiles.map { $0.id })
        }
    }
    
    private func calculateSelectedSummary() -> (totalYield: Float, totalCount: Int) {
        let selectedFiles = store.scanFiles.filter { selectedRecords.contains($0.id) }
        let totalYield = selectedFiles.reduce(0) { $0 + $1.yieldKg }
        let totalCount = selectedFiles.reduce(0) { $0 + $1.fruitCount }
        return (totalYield, totalCount)
    }
    
    private func performExport() {
        let selectedFiles = store.scanFiles.filter { selectedRecords.contains($0.id) }
        
        guard !selectedFiles.isEmpty else { return }
        
        exportTask?.cancel()
        isExporting = true
        exportedURL = nil
        let format = exportFormat
        var options = exportOptions
        options.plotNameByTreeID = plotNameByTreeID()

        exportTask = Task {
            do {
                let exportResult = try await BatchExportService.shared.export(
                    records: selectedFiles,
                    format: format,
                    options: options
                )
                guard !Task.isCancelled else { return }
                exportedURL = exportResult.url
                showShareSheet = true
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                showError = true
            }
            isExporting = false
            exportTask = nil
        }
    }

    private func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        if isExporting {
            isExporting = false
        }
    }

    private func pruneSelection(to files: [ScanFileRecord]) {
        let availableIDs = Set(files.map(\.id))
        if !selectedRecords.isSubset(of: availableIDs) {
            exportedURL = nil
            selectedRecords.formIntersection(availableIDs)
        }
    }

    private func selectAllIfNeeded() {
        guard selectedRecords.isEmpty, !store.scanFiles.isEmpty else { return }
        selectedRecords = Set(store.scanFiles.map { $0.id })
    }

    private func plotNameByTreeID() -> [String: String] {
        let plotNameByID = Dictionary(uniqueKeysWithValues: tagStore.plots.map { ($0.id, $0.name) })
        return Dictionary(uniqueKeysWithValues: tagStore.assignments.compactMap { assignment in
            guard let plotId = assignment.plotId,
                  let plotName = plotNameByID[plotId]
            else { return nil }
            return (assignment.treeId, plotName)
        })
    }
}

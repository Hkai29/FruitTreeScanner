import SwiftUI

struct BatchExportView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = ScanHistoryStore.shared
    @ObservedObject private var tagStore = TagStore.shared
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
                    headerBar

                    if store.scanFiles.isEmpty {
                        emptyStateView
                    } else {
                        recordListView
                        exportOptionsView
                        exportButton
                    }
                }
            }
            .navigationTitle("批次导出")
            .navigationBarTitleDisplayMode(.inline)
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
    
    private var headerBar: some View {
        VStack(spacing: Design.Space.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
            Text("已选择 \(selectedRecords.count) / \(store.scanFiles.count) 条记录")
                .font(Design.Typography.subheadline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                    
                    if !selectedRecords.isEmpty {
                        let summary = calculateSelectedSummary()
                        Text("预计产量: \(String(format: "%.1f", summary.totalYield)) kg | \(summary.totalCount) 个果实")
                            .font(Design.Typography.caption)
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                }
                
                Spacer()
            }
            
            if !store.scanFiles.isEmpty {
                ProgressView(value: Double(selectedRecords.count), total: Double(store.scanFiles.count))
                    .tint(Design.Colors.harvest)
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: Design.Space.lg) {
            Spacer()
            
            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundColor(Design.Colors.Dark.textSecondary.opacity(0.5))
            
            Text("暂无扫描记录")
                .font(Design.Typography.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
            
            Text("完成扫描或导入 PLY 文件后将自动显示在这里")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            
            Spacer()
        }
    }
    
    private var recordListView: some View {
        ScrollView {
            LazyVStack(spacing: Design.Space.sm) {
                ForEach(store.scanFiles) { record in
                    RecordRow(
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
                    FormatButton(
                        format: format,
                        isSelected: exportFormat == format,
                        action: { exportFormat = format }
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
                OptionToggle(label: "果树编号", isOn: $exportOptions.includeTreeID)
                OptionToggle(label: "果实数量", isOn: $exportOptions.includeFruitCount)
                OptionToggle(label: "产量", isOn: $exportOptions.includeYield)
                OptionToggle(label: "GPS位置", isOn: $exportOptions.includeGPS)
                OptionToggle(label: "扫描日期", isOn: $exportOptions.includeDate)
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
            }
        }
    }
    
    private var exportButton: some View {
        Button {
            if isExporting {
                cancelExport()
            } else {
                performExport()
            }
        } label: {
            HStack {
                if isExporting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "square.and.arrow.up")
                }
                Text(isExporting ? "取消导出" : "导出 \(selectedRecords.count) 条记录")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(selectedRecords.isEmpty && !isExporting ? Color.gray : Design.Colors.harvest)
            .cornerRadius(Design.Radius.medium)
        }
        .disabled(selectedRecords.isEmpty && !isExporting)
        .padding(Design.Space.md)
    }
    
    private func toggleSelection(_ id: String) {
        if selectedRecords.contains(id) {
            selectedRecords.remove(id)
        } else {
            selectedRecords.insert(id)
        }
    }
    
    private func toggleSelectAll() {
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

private struct RecordRow: View {
    let record: ScanFileRecord
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Design.Space.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Design.Colors.harvest : Design.Colors.Dark.textSecondary)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.treeID)
                        .font(Design.Typography.subheadline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    
                    HStack(spacing: Design.Space.sm) {
                        Label("\(record.fruitCount)", systemImage: "leaf.fill")
                        Label(String(format: "%.1f kg", record.yieldKg), systemImage: "scalemass")
                        Text(record.fruitType)
                    }
                    .font(.system(size: 10))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatDate(record.scanDate))
                        .font(.system(size: 10))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    
                    if record.gpsLat != 0 {
                        Image(systemName: "location.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Design.Colors.forest)
                    }
                }
            }
            .padding(Design.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.medium)
                    .fill(Design.Colors.Dark.bgDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.medium)
                            .stroke(isSelected ? Design.Colors.harvest : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}

private struct FormatButton: View {
    let format: BatchExportService.ExportFormat
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.xs) {
                Image(systemName: format.icon)
                Text(format.rawValue)
            }
            .font(Design.Typography.subheadline)
            .foregroundColor(isSelected ? .white : Design.Colors.Dark.textPrimary)
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.small)
                    .fill(isSelected ? Design.Colors.harvest : Design.Colors.Dark.bgDeep)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct OptionToggle: View {
    let label: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: Design.Space.xs) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundColor(isOn ? Design.Colors.harvest : Design.Colors.Dark.textSecondary)
                Text(label)
                    .font(.system(size: 12))
            }
            .foregroundColor(Design.Colors.Dark.textPrimary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        BatchExportView()
    }
}

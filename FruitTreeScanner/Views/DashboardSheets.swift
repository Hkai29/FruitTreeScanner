// DashboardSheets.swift
// 首页 sheet 容器与轻量报表页

import SwiftUI

struct HistorySheetView: View {
    @Environment(\.dismiss) var dismiss
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()
                ScanHistoryView(
                    customTitle: "扫描历史",
                    onStartScan: onStartScan,
                    onImportFile: onImportFile
                )
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(Design.Colors.harvest)
                }
            }
        }
    }
}

struct PointCloudSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedFile: URL?
    @ObservedObject var historyStore = ScanHistoryStore.shared
    var onStartScan: (() -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    init(
        initialFileURL: URL? = nil,
        onStartScan: (() -> Void)? = nil,
        onImportFile: (() -> Void)? = nil
    ) {
        _selectedFile = State(initialValue: initialFileURL)
        self.onStartScan = onStartScan
        self.onImportFile = onImportFile
    }

    private var filteredFiles: [ScanFileRecord] {
        if searchText.isEmpty {
            return historyStore.scanFiles
        }
        return historyStore.scanFiles.filter { $0.treeID.lowercased().contains(searchText.lowercased()) }
    }

    private var effectiveSelectedFile: URL? {
        selectedFile ?? historyStore.scanFiles.first?.fileURL
    }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        compactPointCloudSelector
                        PointCloudView(plyFileURL: effectiveSelectedFile)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("点云预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                    .accessibilityLabel("关闭点云预览")
                }
            }
        }
        .onAppear(perform: loadInitialSelection)
        .onChange(of: historyStore.scanFiles, perform: updateSelection)
    }

    private var emptyState: some View {
        DashboardSheetEmptyState(
            icon: "cube",
            imageName: "FeaturePointCloud",
            title: "暂无扫描数据",
            message: "完成扫描或导入 PLY 后，点云文件会自动出现在这里。",
            accent: Design.Colors.Dark.info,
            primaryAction: action(title: "新建扫描", icon: "viewfinder", handler: onStartScan),
            secondaryAction: action(title: "导入 PLY", icon: "square.and.arrow.down", handler: onImportFile)
        )
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }

    private var searchBar: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                TextField("输入编号搜索（如 T001）", text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(12)
            .background(Design.Colors.Dark.bgElevated)
            .cornerRadius(10)

            if !filteredFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(filteredFiles) { record in
                            pointCloudFileButton(record)
                        }
                    }
                }
            } else if !searchText.isEmpty {
                Text("未找到编号 \(searchText) 的记录")
                    .font(.system(size: 14))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
        .padding()
    }

    private var compactPointCloudSelector: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                TextField("搜索编号", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Design.Colors.Dark.textSecondary)
                    }
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Design.Colors.Dark.bgElevated)
            .cornerRadius(9)

            if !filteredFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(filteredFiles) { record in
                            compactPointCloudFileButton(record)
                        }
                    }
                }
            } else if !searchText.isEmpty {
                Text("未找到编号 \(searchText) 的记录")
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Design.Colors.Dark.bgDeep)
    }

    private func compactPointCloudFileButton(_ record: ScanFileRecord) -> some View {
        let isSelected = effectiveSelectedFile == record.fileURL
        return Button {
            selectedFile = record.fileURL
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cube")
                    .font(.system(size: 11, weight: .semibold))
                Text(record.treeID)
                    .font(.system(size: 12, weight: .semibold))
                Text(String(format: "%.1fkg", record.yieldKg))
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.72)
            }
            .foregroundColor(isSelected ? Color.black.opacity(0.82) : Design.Colors.Dark.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
            .cornerRadius(8)
        }
    }

    private func pointCloudFileButton(_ record: ScanFileRecord) -> some View {
        Button {
            selectedFile = record.fileURL
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.treeID)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text("\(record.fruitCount) 个果实")
                    .font(.system(size: 11))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                Text(String(format: "%.1f kg", record.yieldKg))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(effectiveSelectedFile == record.fileURL ? Design.Colors.Dark.textPrimary : Design.Colors.harvest)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(effectiveSelectedFile == record.fileURL ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
            .cornerRadius(8)
        }
    }

    private func loadInitialSelection() {
        historyStore.loadRecords()
        if selectedFile == nil, let first = historyStore.scanFiles.first {
            selectedFile = first.fileURL
        }
    }

    private func updateSelection(_ records: [ScanFileRecord]) {
        if selectedFile == nil, let first = records.first {
            selectedFile = first.fileURL
        } else if let selectedFile, !records.contains(where: { $0.fileURL == selectedFile }) {
            self.selectedFile = records.first?.fileURL
        }
    }
}

struct DashboardSheetEmptyState: View {
    let icon: String
    var imageName: String? = nil
    let title: String
    let message: String
    var accent: Color = Design.Colors.harvest
    var primaryAction: DashboardSheetAction? = nil
    var secondaryAction: DashboardSheetAction? = nil
    var outerPadding: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if let imageName {
                    DashboardFeatureImage(name: imageName, accent: accent)
                        .frame(width: 96, height: 76)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(accent)
                            .frame(width: 26, height: 26)
                            .background(accent.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                    }

                    Text(message)
                        .font(.system(size: 13))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if primaryAction != nil || secondaryAction != nil {
                HStack(spacing: 10) {
                    if let primaryAction {
                        actionButton(primaryAction, isPrimary: true)
                    }
                    if let secondaryAction {
                        actionButton(secondaryAction, isPrimary: false)
                    }
                }
                .padding(.top, 14)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
        .padding(outerPadding ? Design.Space.lg : 0)
        .frame(maxWidth: .infinity, maxHeight: outerPadding ? .infinity : nil, alignment: .top)
    }

    private func actionButton(_ action: DashboardSheetAction, isPrimary: Bool) -> some View {
        Button(action: action.action) {
            Label(action.title, systemImage: action.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isPrimary ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(isPrimary ? Design.Colors.harvest : Design.Colors.Dark.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(isPrimary ? Color.clear : Design.Colors.Dark.glassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

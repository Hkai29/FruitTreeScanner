// ScanHistoryView.swift
// 扫描历史列表 - 统一深色科技风格

import SwiftUI

struct ScanHistoryView: View {
    var customTitle: String = "扫描历史"
    @ObservedObject var historyStore = ScanHistoryStore.shared
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            Color(hex: "0a1628")
                .ignoresSafeArea()

            if historyStore.scanFiles.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.2))

                    Text("暂无扫描记录")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))

                    Text("开始扫描以创建历史记录")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(historyStore.scanFiles) { record in
                            HistoryCard(record: record, onShare: {
                                shareItems = [record.fileURL]
                                showShareSheet = true
                            }, onDelete: {
                                historyStore.deleteRecord(record)
                            })
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle(customTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !historyStore.scanFiles.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            let filesToDelete = historyStore.scanFiles
                            filesToDelete.forEach { historyStore.deleteRecord($0) }
                        } label: {
                            Label("清空全部", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(Color(hex: "4ADE80"))
                    }
                }
            }
        }
        .onAppear { historyStore.loadRecords() }
        .refreshable { historyStore.loadRecords() }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }
}

// MARK: - 历史记录卡片
struct HistoryCard: View {
    let record: ScanFileRecord
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // 图标
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "4ADE80").opacity(0.15))
                    .frame(width: 52, height: 52)

                Image(systemName: "cube.fill")
                    .font(.system(size: 22))
                    .foregroundColor(Color(hex: "4ADE80"))
            }

            // 信息
            VStack(alignment: .leading, spacing: 6) {
                Text(record.fileURL.lastPathComponent)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    Label(fileSize, systemImage: "doc")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))

                    Label(dateString, systemImage: "calendar")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            Spacer()

            // 操作按钮
            HStack(spacing: 12) {
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "60A5FA"))
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "EF4444"))
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var fileSize: String {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: record.fileURL.path),
              let size = attr[.size] as? Int else { return "未知" }
        let mb = Double(size) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private var dateString: String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: record.scanDate)
    }
}

// MARK: - ShareSheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
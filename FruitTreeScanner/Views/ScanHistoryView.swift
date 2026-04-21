// ScanHistoryView.swift
// 扫描历史列表 - 统一深色科技风格

import SwiftUI

struct ScanHistoryView: View {
    var customTitle: String = "扫描历史"
    @State private var plyFiles: [URL] = []
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            Color(hex: "0a1628")
                .ignoresSafeArea()

            if plyFiles.isEmpty {
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
                        ForEach(plyFiles, id: \.self) { url in
                            HistoryCard(url: url, onShare: {
                                shareItems = [url]
                                showShareSheet = true
                            }, onDelete: {
                                deleteFile(at: url)
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
                if !plyFiles.isEmpty {
                    Menu {
                        Button(role: .destructive) {
                            deleteAllFiles()
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
        .onAppear { loadFiles() }
        .refreshable { loadFiles() }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
    }

    private func loadFiles() {
        let scansDir = getDocumentsDirectory().appendingPathComponent("scans")
        plyFiles = (try? FileManager.default.contentsOfDirectory(
            at: scansDir, includingPropertiesForKeys: nil)) ?? []
            .filter { $0.pathExtension == "ply" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func fileSize(url: URL) -> String {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? Int else { return "未知大小" }
        let mb = Double(size) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private func deleteFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        loadFiles()
    }

    private func deleteAllFiles() {
        plyFiles.forEach { url in
            try? FileManager.default.removeItem(at: url)
        }
        loadFiles()
    }
}

// MARK: - 历史记录卡片
struct HistoryCard: View {
    let url: URL
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
                Text(url.lastPathComponent)
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
        guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? Int else { return "未知" }
        let mb = Double(size) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private var dateString: String {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attr[.creationDate] as? Date else { return "未知日期" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
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
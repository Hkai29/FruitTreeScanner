// ScanHistoryView.swift
// 扫描历史列表：显示已保存的 PLY 文件，支持 AirDrop 分享

import SwiftUI

struct ScanHistoryView: View {
    @State private var plyFiles: [URL] = []
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false

    var body: some View {
        List {
            if plyFiles.isEmpty {
                Text("暂无扫描记录")
                    .foregroundColor(.secondary)
            } else {
                ForEach(plyFiles, id: \.self) { url in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                            Text(fileSize(url: url))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        // AirDrop / 分享按钮
                        Button {
                            shareItems = [url]
                            showShareSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteFiles)
            }
        }
        .navigationTitle("扫描历史")
        .onAppear { loadFiles() }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: shareItems)
        }
        .toolbar {
            EditButton()
        }
    }

    private func loadFiles() {
        let scansDir = getDocumentsDirectory().appendingPathComponent("scans")
        plyFiles = (try? FileManager.default.contentsOfDirectory(
            at: scansDir, includingPropertiesForKeys: nil))
            .flatMap { $0.filter { $0.pathExtension == "ply" } }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
    }

    private func fileSize(url: URL) -> String {
        guard let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attr[.size] as? Int else { return "未知大小" }
        let mb = Double(size) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private func deleteFiles(at offsets: IndexSet) {
        offsets.forEach { i in
            try? FileManager.default.removeItem(at: plyFiles[i])
        }
        loadFiles()
    }
}

// MARK: - ShareSheet（UIActivityViewController 包装）

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

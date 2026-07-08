// DetectionDebugView.swift
// DEBUG-only diagnostics for the camera fruit detection pipeline.

import SwiftUI

struct DetectionDebugView: View {
    @Environment(\.dismiss) private var dismiss
    let state: DetectionDebugState
    var onExport: (() throws -> URL)?

    #if DEBUG
    @State private var presentedSheet: DetectionDebugSheet?
    @State private var showExportError = false
    @State private var exportErrorMessage = ""
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep
                    .ignoresSafeArea()

                DetectionDebugContentView(state: state)
            }
            .navigationTitle("Detection Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                #if DEBUG
                if onExport != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: exportFailureSamples) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Export failure samples")
                    }
                }
                #endif
            }
            .preferredColorScheme(.dark)
            #if DEBUG
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .share(let url):
                    ShareSheet(items: [url])
                }
            }
            .alert("Export Failed", isPresented: $showExportError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportErrorMessage)
            }
            #endif
        }
    }

    #if DEBUG
    private func exportFailureSamples() {
        do {
            guard let url = try onExport?() else { return }
            presentedSheet = .share(url)
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }
    #endif
}

#if DEBUG
private enum DetectionDebugSheet: Identifiable {
    case share(URL)

    var id: String {
        switch self {
        case .share(let url):
            return "share-\(url.path)"
        }
    }
}
#endif

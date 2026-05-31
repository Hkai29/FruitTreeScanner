import SwiftUI
import QuickLook
import UIKit

struct ARQuickLookView: UIViewControllerRepresentable {
    let url: URL
    @Binding var isPresented: Bool
    
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        let parent: ARQuickLookView
        
        init(_ parent: ARQuickLookView) {
            self.parent = parent
        }
        
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            return 1
        }
        
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return parent.url as QLPreviewItem
        }
        
        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            parent.isPresented = false
        }
    }
}

struct USDZExportSheet: View {
    let usdzURL: URL?
    let onDismiss: () -> Void
    
    @State private var isQuickLookPresented = false
    
    var body: some View {
        VStack(spacing: Design.Space.lg) {
            headerSection
            
            if let url = usdzURL {
                actionButtons(url: url)
            } else {
                errorView
            }
        }
        .padding(Design.Space.lg)
        .background(Design.Colors.Dark.bgSurface)
        .cornerRadius(Design.Radius.large)
        .sheet(isPresented: $isQuickLookPresented) {
            if let url = usdzURL {
                ARQuickLookView(url: url, isPresented: $isQuickLookPresented)
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: Design.Space.sm) {
            ZStack {
                Circle()
                    .fill(Design.Colors.harvest.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "arkit")
                    .font(.system(size: 36))
                    .foregroundColor(Design.Colors.harvest)
            }
            
            Text("AR 3D 预览")
                .font(Design.Typography.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
            
            Text("使用 AR Quick Look 在增强现实中查看扫描结果")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private func actionButtons(url: URL) -> some View {
        VStack(spacing: Design.Space.md) {
            Button {
                isQuickLookPresented = true
            } label: {
                HStack {
                    Image(systemName: "arkit")
                    Text("在 AR 中预览")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Design.Colors.harvest)
                .cornerRadius(Design.Radius.medium)
            }
            
            ShareLink(item: url) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("分享 USDZ 文件")
                }
                .font(.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Design.Colors.Dark.bgDeep)
                .cornerRadius(Design.Radius.medium)
            }
            
            Button("关闭") {
                onDismiss()
            }
            .foregroundColor(Design.Colors.Dark.textSecondary)
            .padding(.top, Design.Space.sm)
        }
    }
    
    private var errorView: some View {
        VStack(spacing: Design.Space.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("导出失败")
                .font(Design.Typography.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
            
            Text("请确保已进行足够的扫描")
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            
            Button("关闭") {
                onDismiss()
            }
            .foregroundColor(Design.Colors.Dark.textSecondary)
            .padding(.top, Design.Space.sm)
        }
    }
}

#Preview {
    ZStack {
        Design.Colors.Dark.bgDeep.ignoresSafeArea()
        
        VStack {
            Spacer()
            USDZExportSheet(usdzURL: nil, onDismiss: {})
                .padding()
            Spacer()
        }
    }
}

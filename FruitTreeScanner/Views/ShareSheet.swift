import SwiftUI
import UIKit

struct ShareActivityResult: Equatable, Sendable {
    let completed: Bool
    let errorDescription: String?
}

/// 分享结果算不算「失败」。
///
/// 用户自己取消**不算**失败（没有错误）；系统或接收方报错才算。
/// 同一个口径必须在批量导出、档案列表与归档详情之间一致：
/// 分享失败必须告诉用户 —— 面板一关就什么也没发生，用户会以为点云已经分享成功。
enum ScanShareFailurePolicy {
    static func isFailure(_ result: ShareActivityResult) -> Bool {
        result.errorDescription != nil
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var onCompletion: ((ShareActivityResult) -> Void)? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        makeActivityViewController()
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
        configureCompletionHandler(for: uiViewController)
    }

    func makeActivityViewController() -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )
        configureCompletionHandler(for: controller)
        return controller
    }

    private func configureCompletionHandler(for controller: UIActivityViewController) {
        guard let onCompletion else {
            controller.completionWithItemsHandler = nil
            return
        }

        controller.completionWithItemsHandler = { _, completed, _, error in
            let result = ShareActivityResult(
                completed: completed,
                errorDescription: error?.localizedDescription
            )
            DispatchQueue.main.async {
                onCompletion(result)
            }
        }
    }
}

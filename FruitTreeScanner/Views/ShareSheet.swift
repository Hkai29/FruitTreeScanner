import SwiftUI
import UIKit

struct ShareActivityResult: Equatable, Sendable {
    let completed: Bool
    let errorDescription: String?
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

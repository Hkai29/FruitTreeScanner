import SwiftUI

enum ImportStatus: Equatable {
    case idle
    case selecting
    case processing(String)
    case success(String)
    case error(String)

    var isSuccess: Bool {
        if case .success = self {
            return true
        }
        return false
    }

    var isProcessing: Bool {
        if case .processing = self {
            return true
        }
        return false
    }
}

enum ImportFileErrorClassifier {
    static func isUserCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return true
        }
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return true
        }
        return false
    }
}

struct ImportStatusView: View {
    let status: ImportStatus

    var body: some View {
        Group {
            switch status {
            case .idle:
                ImportStatusPanel(
                    icon: "doc.badge.plus",
                    title: "等待选择 PLY 文件",
                    message: "支持 ASCII 和 Binary PLY，导入后会写入本机扫描记录。"
                )

            case .selecting:
                ImportStatusPanel(
                    icon: "folder",
                    title: "请选择文件",
                    message: "从文件应用中选择一个 .ply 点云文件。"
                )

            case .processing(let filename):
                ImportStatusPanel(
                    icon: "arrow.triangle.2.circlepath",
                    title: "正在处理",
                    message: filename,
                    showsProgress: true
                )

            case .success(let filename):
                ImportStatusPanel(
                    icon: "checkmark.circle.fill",
                    title: "导入成功",
                    message: "\(filename) 已添加到扫描记录，可继续导入或关闭此页。",
                    tint: Design.Colors.forest
                )

            case .error(let message):
                ImportStatusPanel(
                    icon: "exclamationmark.triangle.fill",
                    title: "导入失败",
                    message: message,
                    tint: Design.Colors.error
                )
            }
        }
    }
}

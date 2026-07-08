import SwiftUI

enum AppNavigation: String {
    case scanner
    case history
    case batchExport
    case map

    static let defaultsKey = "com.hkai29.fruitscanner.pendingNavigation"
    static let notificationName = Notification.Name("com.hkai29.fruitscanner.navigation")

    init?(url: URL) {
        guard url.scheme == "fruittreescanner" else { return nil }

        let target = url.host ?? url.pathComponents.dropFirst().first
        switch target?.lowercased() {
        case "scanner", "scan", "start-scan":
            self = .scanner
        case "history", "scan-history":
            self = .history
        case "batch-export", "export":
            self = .batchExport
        case "map", "orchard-map":
            self = .map
        default:
            return nil
        }
    }
}

final class NavigationRouter: ObservableObject {
    @Published var pendingDestination: AppNavigation?

    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var navigationObserver: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        navigationObserver = notificationCenter.addObserver(
            forName: AppNavigation.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleNavigationNotification(notification)
        }
        consumePendingUserDefaults()
    }

    deinit {
        if let navigationObserver {
            notificationCenter.removeObserver(navigationObserver)
        }
    }

    func handle(_ destination: AppNavigation) {
        pendingDestination = destination
    }

    func clear() {
        pendingDestination = nil
    }

    func consumePendingUserDefaults() {
        guard let raw = defaults.string(forKey: AppNavigation.defaultsKey) else { return }
        defaults.removeObject(forKey: AppNavigation.defaultsKey)
        guard let destination = AppNavigation(rawValue: raw) else { return }
        pendingDestination = destination
    }

    private func handleNavigationNotification(_ notification: Notification) {
        guard let raw = notification.object as? String else { return }
        if defaults.string(forKey: AppNavigation.defaultsKey) == raw {
            defaults.removeObject(forKey: AppNavigation.defaultsKey)
        }
        guard let destination = AppNavigation(rawValue: raw) else { return }
        handle(destination)
    }
}

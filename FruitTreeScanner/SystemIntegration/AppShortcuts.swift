import AppIntents

struct OpenScannerIntent: AppIntent {
    static var title: LocalizedStringResource = "打开扫描器"
    static var description: IntentDescription = "打开果树扫描采集界面"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        requestNavigation(.scanner)
        return .result()
    }
}

struct OpenHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "打开扫描历史"
    static var description: IntentDescription = "查看扫描记录与点云数据"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        requestNavigation(.history)
        return .result()
    }
}

struct OpenBatchExportIntent: AppIntent {
    static var title: LocalizedStringResource = "批量导出"
    static var description: IntentDescription = "导出多条扫描数据"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        requestNavigation(.batchExport)
        return .result()
    }
}

struct OpenMapIntent: AppIntent {
    static var title: LocalizedStringResource = "打开果园地图"
    static var description: IntentDescription = "按位置查看扫描数据地图"
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        requestNavigation(.map)
        return .result()
    }
}

@MainActor
private func requestNavigation(_ navigation: AppNavigation) {
    UserDefaults.standard.set(navigation.rawValue, forKey: AppNavigation.defaultsKey)
    NotificationCenter.default.post(name: AppNavigation.notificationName, object: navigation.rawValue)
}

struct FruitTreeShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenScannerIntent(),
            phrases: [
                "用\(.applicationName)打开扫描器",
                "使用\(.applicationName)扫描果树",
            ],
            shortTitle: "扫描",
            systemImageName: "viewfinder"
        )

        AppShortcut(
            intent: OpenHistoryIntent(),
            phrases: [
                "在\(.applicationName)中打开扫描历史",
                "用\(.applicationName)查看扫描记录",
            ],
            shortTitle: "扫描历史",
            systemImageName: "clock.arrow.circlepath"
        )

        AppShortcut(
            intent: OpenBatchExportIntent(),
            phrases: [
                "在\(.applicationName)中批量导出",
                "用\(.applicationName)导出扫描数据",
            ],
            shortTitle: "批量导出",
            systemImageName: "doc.richtext"
        )

        AppShortcut(
            intent: OpenMapIntent(),
            phrases: [
                "在\(.applicationName)中打开果园地图",
                "用\(.applicationName)查看扫描地图",
            ],
            shortTitle: "果园地图",
            systemImageName: "map"
        )
    }
}

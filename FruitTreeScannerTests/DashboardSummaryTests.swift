import Combine
import ARKit
import CoreLocation
import MapKit
import SwiftUI
import UIKit
import XCTest
import SwiftUI
import UIKit
@testable import FruitTreeScanner

private actor DashboardAggregationProbe {
    private var inputs: [DashboardAggregationInput] = []
    private var pending: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var cancelledRequests = Set<Int>()

    var count: Int { inputs.count }

    func build(_ input: DashboardAggregationInput) async -> DashboardAggregationSnapshot? {
        let index = inputs.count
        inputs.append(input)
        // Deliberately ignore cancellation until explicitly released.
        await withCheckedContinuation { pending[index] = $0 }
        if Task.isCancelled { cancelledRequests.insert(index) }
        return DashboardAggregationSnapshot(input: input)
    }

    func finish(_ index: Int) {
        pending.removeValue(forKey: index)?.resume()
    }

    func finishAll() {
        let continuations = Array(pending.values)
        pending.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

private actor DashboardHistorySequence {
    private var results: [ScanHistoryLoadResult]
    private(set) var loadCount = 0
    init(_ results: [ScanHistoryLoadResult]) { self.results = results }
    func load() -> ScanHistoryLoadResult {
        loadCount += 1
        return results.count > 1 ? results.removeFirst() : results[0]
    }
    func replace(with result: ScanHistoryLoadResult) { results = [result] }
}

private actor HistoryVisualLoadGate {
    private var pending: [CheckedContinuation<ScanHistoryLoadResult, Never>] = []
    func load() async -> ScanHistoryLoadResult {
        await withCheckedContinuation { pending.append($0) }
    }
    func finish() {
        let requests = pending
        pending.removeAll()
        requests.forEach { $0.resume(returning: .cancelled) }
    }
}

private actor HistoryRefreshLoadProbe {
    let initialRecord: ScanFileRecord
    private var pending: [CheckedContinuation<ScanHistoryLoadResult, Never>] = []
    private(set) var requestCount = 0
    private(set) var completionWasCancelled: [Bool] = []
    var pendingCount: Int { pending.count }

    init(initialRecord: ScanFileRecord) { self.initialRecord = initialRecord }

    func load() async -> ScanHistoryLoadResult {
        requestCount += 1
        if requestCount == 1 { return .success([initialRecord]) }
        let result = await withCheckedContinuation { pending.append($0) }
        completionWasCancelled.append(Task.isCancelled)
        return result
    }

    func finishPending(with result: ScanHistoryLoadResult) {
        let continuations = pending
        pending.removeAll()
        for continuation in continuations { continuation.resume(returning: result) }
    }
}

@MainActor
private final class DashboardSceneFixture: ObservableObject {
    @Published var phase: ScenePhase = .inactive
}

private struct DashboardSceneHarness: View {
    @ObservedObject var scene: DashboardSceneFixture
    let dashboard: DashboardView
    let dependencies: AppDependencies

    var body: some View {
        dashboard.environmentObject(dependencies).environment(\.scenePhase, scene.phase)
    }
}

private actor CaptureRecoveryReadinessFixture {
    private var requestCount = 0
    private var pending: CheckedContinuation<ScanReadiness, Never>?

    func determine() async -> ScanReadiness {
        requestCount += 1
        if requestCount == 1 { return .ready }
        return await withCheckedContinuation { pending = $0 }
    }

    func becomeReady() {
        pending?.resume(returning: .ready)
        pending = nil
    }
}

@MainActor
private final class RootLaunchUIHarness {
    let controller = UIHostingController(rootView: AnyView(EmptyView()))
    let window: UIWindow
    private let previousKeyWindow: UIWindow?

    init() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        previousKeyWindow = scene.keyWindow
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
    }

    func mount<V: View>(_ view: V) {
        controller.rootView = AnyView(view)
        window.layoutIfNeeded()
    }

    func close() {
        controller.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    var elements: [NSObject] {
        var seen = Set<ObjectIdentifier>()
        var result: [NSObject] = []
        func visit(_ object: NSObject, depth: Int = 0) {
            guard depth < 32, seen.insert(ObjectIdentifier(object)).inserted else { return }
            result.append(object)
            let count = object.accessibilityElementCount()
            if count > 0 && count < 100 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject { visit(child, depth: depth + 1) }
                }
            }
            if let view = object as? UIView { for child in view.subviews { visit(child, depth: depth + 1) } }
        }
        // Detached transition snapshots and covered sheets can retain old editable controls.
        var current = controller as UIViewController
        while let presented = current.presentedViewController { current = presented }
        visit(current.view)
        return result
    }

    func element(label: String) -> NSObject? {
        let matches = elements.filter { $0.accessibilityLabel == label }
        return matches.first { $0.accessibilityTraits.contains(.button) } ?? matches.first
    }

    /// 按无障碍标识找元素。
    ///
    /// 两个出口可能**同名**（搜索框的叉与空态的「清除搜索」都是「清除搜索」），
    /// 标签分不开时就用标识分：搜索框是 `historySearch.clear`，空态是
    /// `historyEmpty.clearSearch` / `historyEmpty.clearFilters`。
    ///
    /// 标识走 KVC 读：无障碍节点在树里是各种私有类，
    /// Swift 侧不保证它们都暴露成同一个类型。
    func element(identifier: String) -> NSObject? {
        let key = NSSelectorFromString("accessibilityIdentifier")
        return elements.first { object in
            guard object.responds(to: key) else { return false }
            return (object.value(forKey: "accessibilityIdentifier") as? String) == identifier
        }
    }

    /// 当前 AX 树上的全部标签。断言失败时把它带出来：页面到底显示了什么，一眼可见。
    func accessibilityLabels() -> [String] {
        elements.compactMap { $0.accessibilityLabel }.filter { !$0.isEmpty }
    }

    /// 当前 AX 树上的全部无障碍标识（诊断用）。
    func accessibilityIdentifiers() -> [String] {
        let key = NSSelectorFromString("accessibilityIdentifier")
        return elements.compactMap { object in
            guard object.responds(to: key) else { return nil }
            return object.value(forKey: "accessibilityIdentifier") as? String
        }.filter { !$0.isEmpty }
    }

    /// 窗口在**屏幕**上的矩形。
    ///
    /// 无障碍帧是屏幕坐标，窗口 `bounds` 是窗口坐标：两者只在窗口被钉在原点时
    /// 恰好相等。可见性判断必须换算到屏幕坐标再比，否则窗口一被挪动
    /// （iPad、分屏、其它宿主）就会变成假通过。
    var screenFrame: CGRect {
        window.convert(window.bounds, to: nil)
    }

    /// 当前呈现出来的**真实**分享面板。
    ///
    /// 走的是 UIKit 自己呈现出来的 UIActivityViewController，
    /// 不是自己造的一个替身：注入失败要走它自己的完成回调。
    /// SwiftUI 的 sheet 会把代表视图装进 `PresentationHostingController`，
    /// 所以要连子控制器一起找，不能只看 presented 链。
    func presentedActivityViewController() -> UIActivityViewController? {
        func search(_ viewController: UIViewController) -> UIActivityViewController? {
            if let activity = viewController as? UIActivityViewController { return activity }
            for child in viewController.children {
                if let found = search(child) { return found }
            }
            return viewController.presentedViewController.flatMap(search)
        }
        return search(controller)
    }

    var categoryPicker: NSObject? {
        elements.first {
            $0 is UIButton &&
                $0.accessibilityLabel?.contains(L10n.FruitCategoryVerification.selectedAccessibilityLabel) == true &&
                $0.accessibilityValue != nil
        }
    }

    func openCalibration() async throws {
        let label = L10n.Dashboard.quickActionAccessibilityLabel(title: L10n.Dashboard.calibrationTitle,
                                                                description: L10n.Dashboard.calibrationDescription)
        let action = try await scrollToDashboardAction(label: label)
        XCTAssertTrue(action.accessibilityActivate())
        let ready = try await waitFor { self.element(label: L10n.Calibration.minimumClusterPoints) != nil }
        XCTAssertTrue(ready)
        try await waitForSheetReady()
    }

    /// 弹层转场结束之后才允许操作控件。
    ///
    /// 转场期间 UIKit 会保留一份旧视图快照，那份快照里的控件同样能响应
    /// 无障碍动作 —— 操作它等于改了一个已经不存在的视图，断言会跟着失真。
    func waitForSheetReady() async throws {
        let settled = try await waitFor {
            guard let presented = self.controller.presentedViewController else { return true }
            return presented.transitionCoordinator == nil && presented.view.window != nil
        }
        XCTAssertTrue(settled, "the presented sheet never finished its transition")
        window.layoutIfNeeded()
    }

    func changeCalibrationSlider(_ label: String, fraction: Float, expected: String) async throws -> UISlider {
        let control = try await scrollToControl(label: label)
        let slider = try XCTUnwrap(control as? UISlider)
        // 同一个标签只能对应一个真实控件：转场快照里残留的旧滑杆会让断言失真。
        let matches = elements.filter { $0.accessibilityLabel == label }
        XCTAssertEqual(matches.count, 1, "\(matches.count) controls share the slider label \(label)")
        slider.sendActions(for: .touchDown)
        slider.value += (slider.maximumValue - slider.minimumValue) * fraction
        slider.sendActions(for: .valueChanged)
        let changed = try await waitFor { slider.accessibilityValue == expected }
        XCTAssertTrue(changed)
        return slider
    }

    func closeCalibration() async throws {
        XCTAssertTrue(try XCTUnwrap(element(label: L10n.Calibration.close)).accessibilityActivate())
        let closed = try await waitFor { self.controller.presentedViewController == nil }
        XCTAssertTrue(closed)
    }

    func openVarietyDatabase() async throws {
        XCTAssertTrue(try XCTUnwrap(element(label: L10n.Dashboard.settingsAccessibilityLabel)).accessibilityActivate())
        let ready = try await waitFor { self.element(label: L10n.Settings.varietyDatabase) != nil }
        XCTAssertTrue(ready)
        let database = try await scrollToControl(label: L10n.Settings.varietyDatabase)
        XCTAssertTrue(database.accessibilityActivate())
        let loaded = try await waitFor {
            self.element(label: L10n.VarietyDatabase.editAccessibility(L10n.Fruit.name(for: .pear))) != nil
        }
        XCTAssertTrue(loaded)
    }

    func editVariety(_ category: FruitCategory) async throws {
        let label = L10n.VarietyDatabase.editAccessibility(L10n.Fruit.name(for: category))
        let edit = try await scrollToControl(label: label)
        XCTAssertTrue(edit.accessibilityActivate())
        let ready = try await waitFor {
            self.elements.contains { $0 is UISlider && $0.accessibilityLabel == L10n.VarietyDatabase.maximumDiameter }
        }
        XCTAssertTrue(ready)
    }

    func varietySliderValue(_ label: String) -> String? {
        elements.compactMap { $0 as? UISlider }.first { $0.accessibilityLabel == label }?.accessibilityValue
    }

    func changeVarietySlider(_ label: String, value: Float,
                             range: ClosedRange<Float> = 1...2000, expected: String) async throws {
        _ = try await scrollToControl(label: label)
        let slider = try XCTUnwrap(elements.compactMap { $0 as? UISlider }.first { $0.accessibilityLabel == label })
        // SwiftUI's UIKit slider uses a normalized range; send its public valueChanged action.
        let position = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        slider.value = slider.minimumValue + (slider.maximumValue - slider.minimumValue) * position
        slider.sendActions(for: .valueChanged)
        let changed = try await waitFor { slider.accessibilityValue == expected }
        XCTAssertTrue(changed)
    }

    func saveVarietyAndWaitForDatabase(_ category: FruitCategory) async throws {
        XCTAssertTrue(try XCTUnwrap(element(label: L10n.Common.save)).accessibilityActivate())
        let closed = try await waitFor {
            self.element(label: L10n.VarietyDatabase.editAccessibility(L10n.Fruit.name(for: category))) != nil
        }
        XCTAssertTrue(closed)
    }

    func dismissSystemAlert() throws {
        var current: UIViewController? = controller
        while let root = current {
            if let alert = root as? UIAlertController {
                alert.dismiss(animated: true)
                return
            }
            current = root.presentedViewController
        }
        XCTFail("Expected the actual system alert presentation")
    }

    func selectCategory(_ category: FruitCategory) async throws {
        let button = try XCTUnwrap(categoryPicker as? UIButton)
        XCTAssertTrue(button.accessibilityActivate())
        let ready = try await waitFor { button.menu != nil }
        XCTAssertTrue(ready)
        func actions(in menu: UIMenu) -> [UIAction] {
            menu.children.flatMap { child -> [UIAction] in
                if let action = child as? UIAction { return [action] }
                if let nested = child as? UIMenu { return actions(in: nested) }
                return []
            }
        }
        let action = try XCTUnwrap(actions(in: try XCTUnwrap(button.menu)).first {
            $0.title == L10n.Fruit.name(for: category)
        })
        button.sendAction(action)
        button.contextMenuInteraction?.dismissMenu()
        let selected = try await waitFor {
            self.categoryPicker?.accessibilityValue == L10n.FruitCategoryVerification.selectionAccessibilityValue(category)
        }
        XCTAssertTrue(selected)
    }

    func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 3) async throws -> Bool {
        func settled(_ current: UIViewController) -> Bool {
            current.transitionCoordinator == nil && !current.isBeingPresented && !current.isBeingDismissed &&
                current.children.allSatisfy(settled) && (current.presentedViewController.map(settled) ?? true)
        }
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            window.layoutIfNeeded()
            if settled(controller) && condition() { return true }
            try await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        return false
    }

    func menuActions(label: String) async throws -> (UIContextMenuInteraction, [UIAction]) {
        // 宿主的 AX 树会随布局重排而重建：控件可能在一瞬间不在树上。
        // 等它稳定出现再操作，别赌那一帧。
        XCTAssertTrue(try XCTUnwrap(element(label: label)).accessibilityActivate())
        func interactions(in view: UIView) -> [UIContextMenuInteraction] {
            view.interactions.compactMap { $0 as? UIContextMenuInteraction } +
                view.subviews.flatMap(interactions)
        }
        func actions(in menu: UIMenu) -> [UIAction] {
            menu.children.flatMap { child -> [UIAction] in
                if let action = child as? UIAction { return [action] }
                if let submenu = child as? UIMenu { return actions(in: submenu) }
                return []
            }
        }
        var visible: (UIContextMenuInteraction, [UIAction])?
        let ready = try await waitFor {
            for interaction in interactions(in: self.window) {
                // Public inspection of the actual visible menu; return it unchanged.
                interaction.updateVisibleMenu { menu in
                    visible = (interaction, actions(in: menu))
                    return menu
                }
            }
            return visible != nil
        }
        XCTAssertTrue(ready, "Production context menu must be presented: \(label)")
        return try XCTUnwrap(visible)
    }

    func selectMenu(label: String, title: String) async throws {
        let (interaction, actions) = try await menuActions(label: label)
        // Dispatch the production UIAction with UIKit's public API, then dismiss the system menu.
        UIButton(type: .system).sendAction(try XCTUnwrap(actions.first { $0.title == title }))
        interaction.dismissMenu()
        let dismissed = try await waitFor { !self.elements.isEmpty }
        XCTAssertTrue(dismissed)
    }

    /// 当前**可见**的上下文菜单及其动作（**不**自己激活入口）。
    ///
    /// 入口已经由调用方按可视矩形挑中并激活过时用它 ——
    /// 再按标签激活一次会点到别的行上，证据就串了。
    func visibleMenuActions() async throws -> (UIContextMenuInteraction, [UIAction]) {
        func interactions(in view: UIView) -> [UIContextMenuInteraction] {
            view.interactions.compactMap { $0 as? UIContextMenuInteraction } +
                view.subviews.flatMap(interactions)
        }
        func actions(in menu: UIMenu) -> [UIAction] {
            menu.children.flatMap { child -> [UIAction] in
                if let action = child as? UIAction { return [action] }
                if let submenu = child as? UIMenu { return actions(in: submenu) }
                return []
            }
        }
        var visible: (UIContextMenuInteraction, [UIAction])?
        let ready = try await waitFor {
            for interaction in interactions(in: self.window) {
                interaction.updateVisibleMenu { menu in
                    visible = (interaction, actions(in: menu))
                    return menu
                }
            }
            return visible != nil
        }
        XCTAssertTrue(ready, "Production context menu must be presented")
        return try XCTUnwrap(visible)
    }

    func scrollToControl(label: String) async throws -> NSObject {
        let scroll = try XCTUnwrap(elements.compactMap { $0 as? UIScrollView }.first {
            $0.contentSize.height > $0.bounds.height
        })
        let maximum = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
        var offset = CGFloat(0)
        repeat {
            scroll.setContentOffset(CGPoint(x: 0, y: min(offset, maximum)), animated: false)
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 20_000_000)
            if let action = element(label: label), action.accessibilityFrame.intersects(window.bounds) { return action }
            offset += max(100, scroll.bounds.height / 2)
        } while offset <= maximum + scroll.bounds.height / 2
        return try XCTUnwrap(element(label: label), "Production scroll control must be reachable: \(label)")
    }

    func advanceStartToConfirmation() async throws {
        let ready = try await waitFor { self.elements.contains { $0 is UITextField } }
        XCTAssertTrue(ready)
        let field = try XCTUnwrap(elements.compactMap { $0 as? UITextField }.first)
        field.insertText("ROOT40")
        let valid = try await waitFor {
            self.element(label: L10n.StartFlow.next)?.accessibilityTraits.contains(.notEnabled) == false
        }
        XCTAssertTrue(valid)
        for step in 1...4 {
            let next = try XCTUnwrap(element(label: L10n.StartFlow.next))
            XCTAssertTrue(next.accessibilityActivate())
            let advanced = try await waitFor {
                self.element(label: L10n.StartFlow.stepCountAccessibility(currentStep: step + 1, totalSteps: 5)) != nil
            }
            XCTAssertTrue(advanced, "Actual next control must advance to step \(step + 1)")
        }
    }

    func reveal(_ label: String, in scroll: UIScrollView) async throws -> NSObject {
        let visible = try await waitFor {
            let lower = -scroll.adjustedContentInset.top
            let upper = max(lower, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            guard let frame = self.element(label: label)?.accessibilityFrame, frame.width > 0, frame.height > 0 else {
                scroll.setContentOffset(CGPoint(x: 0, y: upper), animated: false)
                return false
            }
            let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: nil)
            if viewport.insetBy(dx: -0.5, dy: -0.5).contains(frame) { return true }
            let target = min(upper, max(lower, scroll.contentOffset.y + frame.midY - viewport.midY))
            scroll.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            return false
        }
        XCTAssertTrue(visible, "\(label) must be fully inside the actual scroll viewport")
        return try XCTUnwrap(element(label: label))
    }

    func advanceStart(to targetStep: Int, treeID: String) async throws {
        let ready = try await waitFor { self.elements.contains { $0 is UITextField } }
        XCTAssertTrue(ready)
        try XCTUnwrap(elements.compactMap { $0 as? UITextField }.first).insertText(treeID)
        for step in 1..<targetStep {
            let enabled = try await waitFor {
                self.element(label: L10n.StartFlow.next)?.accessibilityTraits.contains(.notEnabled) == false
            }
            XCTAssertTrue(enabled)
            XCTAssertTrue(try XCTUnwrap(element(label: L10n.StartFlow.next)).accessibilityActivate())
            let advanced = try await waitFor {
                self.element(label: L10n.StartFlow.stepCountAccessibility(currentStep: step + 1, totalSteps: 5)) != nil
            }
            XCTAssertTrue(advanced)
        }
    }

    func scrollToDashboardAction(label: String) async throws -> NSObject {
        let historyLabels = [
            L10n.Dashboard.viewAll,
            L10n.Dashboard.quickActionAccessibilityLabel(title: L10n.Dashboard.scanHistoryTitle, description: L10n.Dashboard.scanHistoryDescription),
            L10n.Dashboard.quickActionAccessibilityLabel(title: L10n.Dashboard.pointCloudTitle, description: L10n.Dashboard.pointCloudDescription),
            L10n.Dashboard.quickActionAccessibilityLabel(title: L10n.Dashboard.tagManagementTitle, description: L10n.Dashboard.tagManagementDescription),
            L10n.Dashboard.quickActionAccessibilityLabel(title: L10n.Dashboard.batchExportTitle, description: L10n.Dashboard.batchExportDescription)
        ]
        if historyLabels.contains(label) {
            let tab = try XCTUnwrap(element(label: WorkspaceText.archive), "Archive tab must be reachable")
            if !tab.accessibilityTraits.contains(.selected) {
                XCTAssertTrue(tab.accessibilityActivate())
                let selected = try await waitFor {
                    self.element(label: WorkspaceText.archive)?.accessibilityTraits.contains(.selected) == true
                }
                XCTAssertTrue(selected, "Archive tab must activate before opening its tool")
            }
        }
        func findScroll(_ view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap(findScroll).first
        }
        let scroll = try XCTUnwrap(findScroll(controller.view))
        let maximum = max(0, scroll.contentSize.height - scroll.bounds.height)
        for offset in stride(from: CGFloat(0), through: maximum, by: max(100, scroll.bounds.height / 2)) {
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 20_000_000)
            if let action = element(label: label), action.accessibilityFrame.intersects(window.bounds) { return action }
        }
        return try XCTUnwrap(element(label: label), "Actual Dashboard action must be reachable")
    }

    func cancelUncapturedScan() async throws {
        let ready = try await waitFor { self.element(label: L10n.ScanReadiness.back) != nil }
        XCTAssertTrue(ready)
        XCTAssertTrue(try XCTUnwrap(element(label: L10n.ScanReadiness.back)).accessibilityActivate())
        let dismissed = try await waitFor { self.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed, "Actual non-recording cancel must return to Dashboard")
    }

    func appendToClassificationNameAndSave(_ text: String) async throws {
        let editable = try await waitFor { self.elements.contains { $0 is UITextField } }
        XCTAssertTrue(editable)
        let field = try XCTUnwrap(elements.compactMap { $0 as? UITextField }.first)
        field.selectedTextRange = field.textRange(from: field.endOfDocument, to: field.endOfDocument)
        field.insertText(text)
        let ready = try await waitFor {
            self.element(label: L10n.TagManagement.save)?.accessibilityTraits.contains(.notEnabled) == false
        }
        XCTAssertTrue(ready)
        XCTAssertTrue(try XCTUnwrap(element(label: L10n.TagManagement.save)).accessibilityActivate())
    }

    func attach(to test: XCTestCase, phase: String) async throws {
        // Accessibility updates before SwiftUI's 0.3-second step animation finishes painting.
        try await Task.sleep(nanoseconds: 350_000_000)
        window.layoutIfNeeded()
        CATransaction.flush()
        let image = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        })
        image.name = "RootLaunch-\(phase)"
        image.lifetime = .keepAlways
        test.add(image)
        let lines: [String] = elements.compactMap { element -> String? in
            guard let label = element.accessibilityLabel else { return nil }
            let typeName = String(describing: type(of: element))
            let traits = String(element.accessibilityTraits.rawValue)
            let isControl = String(element is UIControl)
            let value = element.accessibilityValue ?? ""
            return "\(typeName) [\(traits)] control=\(isControl) \(label) = \(value)"
        }
        let text = XCTAttachment(string: lines.joined(separator: "\n"))
        text.name = "RootLaunch-\(phase)-accessibility"
        text.lifetime = .keepAlways
        test.add(text)
    }
}

/// 离屏渲染出来的墨迹几何：每一列有多少笔画、笔画起止在哪。
///
/// 只量几何，不猜内容：版式断言要问的是「读数是不是在右边、是不是大字」，
/// 不是「屏幕上写着什么」。
private struct ArchiveRowInk {
    let scale: CGFloat
    let columnInkCount: [Int]
    let columnInkTop: [Int]
    let columnInkBottom: [Int]

    /// 最右一处墨迹的 x（像素）。
    var rightmostInkX: Int? {
        columnInkCount.lastIndex(where: { $0 > 0 })
    }

    /// 读数列那一簇墨迹的左边界（像素）。
    ///
    /// 簇内允许有窄缝（数字与单位之间只隔 3pt），但遇到宽缝就停 ——
    /// 宽缝的另一侧是身份列，不是读数列。
    func readingClusterStartX(maxGapPoints: CGFloat = 12) -> Int? {
        guard let last = rightmostInkX else { return nil }
        let maxGap = Int(maxGapPoints * scale)
        var start = last
        var x = last - 1
        while x >= 0 {
            if columnInkCount[x] > 0 {
                if start - x - 1 > maxGap { break }
                start = x
            }
            x -= 1
        }
        return start
    }

    /// 身份列与读数列之间的空白列宽（像素）。
    var gapBeforeRightmostRun: Int {
        guard let start = readingClusterStartX() else { return 0 }
        var end = start - 1
        while end >= 0 && columnInkCount[end] == 0 { end -= 1 }
        return end >= 0 ? start - end - 1 : 0
    }

    /// 右侧一条带子里最高的笔画高度（像素）。
    func tallestInkHeight(inRightBandPoints points: CGFloat) -> Int {
        guard let last = rightmostInkX else { return 0 }
        let bandWidth = Int(points * scale)
        let from = max(0, last - bandWidth)
        var tallest = 0
        for x in from...last where columnInkBottom[x] >= columnInkTop[x] {
            tallest = max(tallest, columnInkBottom[x] - columnInkTop[x] + 1)
        }
        return tallest
    }
}

/// 固定异步读取时序的闸门：第一次读卡在这里，等测试放行才回来。
///
/// 用它逼出「旧回调晚回来」那条路 —— 靠延时是碰运气，靠闸门是确定的。
private final class ArchiveReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        released = true
        let pending = waiters
        waiters.removeAll()
        lock.unlock()
        for continuation in pending { continuation.resume() }
    }
}

@MainActor
private struct ScanChromeFixture: View {
    let state: String
    let hud: ScanHUDState
    let quality: ScanQualityMonitor
    let measurement: MetalMeasurementController
    let actions: ScanScannerInterfaceActions
    var onOpenSettings: () -> Void = {}

    private var readiness: ScanReadiness {
        state == "camera-denied" ? .cameraDenied : state == "lidar-unavailable" ? .lidarUnavailable : .ready
    }

    var body: some View {
        ZStack {
            Design.Colors.Dark.bgDeep.ignoresSafeArea()
            Text("界面测试样例 · 未连接相机或 LiDAR")
                .font(.caption).foregroundColor(.white.opacity(0.6))
                .accessibilityHidden(true)
            ScanScannerInterfaceLayer(
                treeID: "界面样例T012", scanReadiness: readiness,
                isRecording: ["recording", "tracking-lost", "sparse-depth", "coverage-complete"].contains(state),
                isEstimating: false, canExportScan: state != "requirements" && state != "ready",
                shouldShowPostCapturePanel: state == "paused" || state == "requirements",
                showGuide: state == "guide", showResult: false, showCoverageComplete: state == "coverage-complete",
                yieldResult: nil, resultPersistenceState: .idle, detectionDebugState: nil,
                hudState: hud, qualityMonitor: quality, measurementController: measurement,
                measuredDistance: .constant(nil), actions: actions,
                notice: state == "notice" ? L10n.ScanExport.requirementsHint : nil
            )
            ScanReadinessOverlay(scanReadiness: readiness, onOpenSettings: onOpenSettings,
                                 onDismiss: actions.onRequestCancelScan)
        }
        .preferredColorScheme(.dark)
    }
}

private struct RootMismatchHost: View {
    let scan: ScanView
    @State private var isPresented = true

    var body: some View {
        Text("Root mismatch host")
            .sheet(isPresented: $isPresented) { scan }
    }
}

@MainActor
private final class RootClassificationFixture {
    let suite = "RootClassification-\(UUID())"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let root: AppDependencies
    static let protectedKeys = [SettingsStoreKey.fruitType, FruitParametersStore.userDefaultsKey,
                         TagStore.snapshotUserDefaultsKey, "TagStore.plots", "TagStore.tags", "TagStore.assignments"]
    let standard: [String: Any]
    let plot: Plot
    let tag: GroupTag

    init() async throws {
        await TagStore.shared.waitForPendingSave()
        await FruitParametersStore.shared.waitForPendingSave()
        standard = UserDefaults.standard.dictionaryRepresentation().filter { Self.protectedKeys.contains($0.key) }
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = SettingsStore(defaults: defaults)
        settings.fruitType = "pear"
        let tags = TagStore(defaults: defaults)
        tags.addPlot(name: "ROOT41 PLOT")
        tags.addTag(name: "ROOT41 TAG")
        plot = try XCTUnwrap(tags.plots.first)
        tag = try XCTUnwrap(tags.tags.first)
        root = AppDependencies(settings: settings, scanRepository: ScanRepository(scansDirectory: directory), tagStore: tags)
        await tags.waitForPendingSave()
    }

    func mount(on ui: RootLaunchUIHarness) {
        ui.mount(DashboardView(router: NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter()),
                               historyStore: root.historyStore).environmentObject(root))
    }

    func verifyStandard() async {
        await root.tagStore.waitForPendingSave()
        await TagStore.shared.waitForPendingSave()
        await FruitParametersStore.shared.waitForPendingSave()
        let after = UserDefaults.standard.dictionaryRepresentation().filter { Self.protectedKeys.contains($0.key) }
        XCTAssertTrue(NSDictionary(dictionary: after).isEqual(to: standard), "Isolated root must not write standard classification/settings")
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// 果园地图复扫回归用的夹具。
///
/// 三条真实档案：
/// - 一棵**有坐标**的树（地图上要看得见树，首页才有「展开地图」）；
/// - 另一棵**有坐标**的树（断言必须落在被点的那一棵上）；
/// - 一条**没坐标**的记录（地图靠它给出「去档案里找」的回退入口 ——
///   没有它，地图上根本没有打开档案的入口，这条链根本走不通）。
///
/// 档案里这些记录的果品种类是 **apple**，而根设置是 **pear**：
/// 复扫必须用**根**的分类，不能顺手沿用档案里的旧分类。
@MainActor
private struct MapArchiveFixture {
    let classification: RootClassificationFixture
    let dependencies: AppDependencies
    let rescan: URL
    let other: URL
    let unlocated: URL

    func fileBytes() throws -> [String: Data] {
        var files: [String: Data] = [:]
        for url in try FileManager.default.contentsOfDirectory(at: classification.directory,
                                                               includingPropertiesForKeys: nil) {
            files[url.lastPathComponent] = try Data(contentsOf: url)
        }
        return files
    }

    static func make(
        rescanTree: String,
        otherTree: String,
        unlocatedTree: String
    ) async throws -> MapArchiveFixture {
        let root = try await RootClassificationFixture()
        let point = ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)
        var urls: [URL] = []
        for (name, treeID, date, latitude, longitude) in [
            ("maprescan", rescanTree, "2026-10-03 00:00:00", 30.11, 120.11),
            ("mapother", otherTree, "2026-10-04 00:00:00", 30.22, 120.22),
            ("mapnogps", unlocatedTree, "2026-10-02 00:00:00", 0.0, 0.0)
        ] {
            let url = root.directory.appendingPathComponent("\(name).ply")
            try PLYPointCloudWriter.write(points: [point], treeID: treeID, scanDate: date,
                                          gpsLat: latitude, gpsLon: longitude, to: url)
            // 伴随结果文件：没有它这条记录只是「不完整」，不会出现在果园地图上。
            try JSONSerialization.data(withJSONObject: [
                "fruitCount": 7, "yieldKg": 3.5, "fruitType": "apple", "confidence": "medium"
            ]).write(to: root.directory.appendingPathComponent("\(name)_result.json"))
            urls.append(url)
        }
        return MapArchiveFixture(classification: root, dependencies: root.root,
                                 rescan: urls[0], other: urls[1], unlocated: urls[2])
    }
}

@MainActor
private final class RootParameterFixture {
    let suite = "RootParameters-\(UUID())"
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults: UserDefaults
    let root: AppDependencies
    private let standard: [String: Any]
    private static let protectedKeys = RootClassificationFixture.protectedKeys + [
        SettingsStoreKey.clusterMinPoints, SettingsStoreKey.clusterMinDiameter,
        SettingsStoreKey.clusterMaxDiameter, SettingsStoreKey.sphericityThreshold,
        SettingsStoreKey.hsvHMin, SettingsStoreKey.hsvHMax, SettingsStoreKey.hsvSMin, SettingsStoreKey.hsvVMin
    ]

    init() async throws {
        await FruitParametersStore.shared.waitForPendingSave()
        await TagStore.shared.waitForPendingSave()
        standard = UserDefaults.standard.dictionaryRepresentation().filter { Self.protectedKeys.contains($0.key) }
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let settings = SettingsStore(defaults: defaults)
        settings.fruitType = "pear"
        settings.qualityPreset = "中"
        settings.clusterMinPoints = 19
        settings.clusterMaxDiameter = 0.145
        settings.sphericityThreshold = 0.58
        settings.hsvHMin = 10
        settings.hsvHMax = 44
        settings.hsvSMin = 0.51
        settings.hsvVMin = 0.61
        let parameters = FruitParametersStore(defaults: defaults)
        parameters.updateParam(for: .pear) {
            $0.diamMin = 0.035
            $0.diamMax = 0.145
            $0.averageWeightG = 221
            $0.density = 0.91
            $0.clusterEps = 0.045
            $0.sphericityThreshold = 0.58
        }
        parameters.updateParam(for: .apple) { $0.averageWeightG = 161 }
        await parameters.waitForPendingSave()
        root = AppDependencies(settings: settings, scanRepository: ScanRepository(scansDirectory: directory),
                               tagStore: TagStore(defaults: defaults), parametersStore: parameters)
    }

    func mount(on ui: RootLaunchUIHarness) {
        ui.mount(DashboardView(router: NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter()),
                               historyStore: root.historyStore).environmentObject(root))
    }

    func plan(_ treeID: String) -> ScanPlan {
        root.scanPlanFactory.makePlan(treeID: treeID, season: .mature, selectedCategory: .pear, renderer: nil)
    }

    func verifyStandard() async {
        await root.parametersStore.waitForPendingSave()
        await root.tagStore.waitForPendingSave()
        await FruitParametersStore.shared.waitForPendingSave()
        await TagStore.shared.waitForPendingSave()
        let after = UserDefaults.standard.dictionaryRepresentation().filter { Self.protectedKeys.contains($0.key) }
        XCTAssertTrue(NSDictionary(dictionary: after).isEqual(to: standard), "Root parameter flows must preserve standard preferences")
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty) == true)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: directory)
    }
}

final class DashboardSummaryTests: XCTestCase {
    func testOrchardWorkspaceSelectionFollowsNewestLocatedCompleteScanOfSelectedTree() throws {
        let old = ScanFileRecord(id: "old", treeID: "T012", fileURL: URL(fileURLWithPath: "/old.ply"), scanDate: Date(timeIntervalSince1970: 1), yieldKg: 3, gpsLat: 30, gpsLon: 120)
        let newest = ScanFileRecord(id: "new", treeID: "T012", fileURL: URL(fileURLWithPath: "/new.ply"), scanDate: Date(timeIntervalSince1970: 2), yieldKg: 12.4, gpsLat: 30, gpsLon: 120)
        let other = ScanFileRecord(id: "other", treeID: "T013", fileURL: URL(fileURLWithPath: "/other.ply"), scanDate: Date(timeIntervalSince1970: 3), gpsLat: 30, gpsLon: 120)
        let records = [other, old, newest]
        let trees = OrchardMapData(records: records).trees
        let selected = try XCTUnwrap(OrchardWorkspaceSelection.record(in: records, trees: trees, selectedTreeID: "T012"))
        XCTAssertEqual(selected.id, newest.id)
        XCTAssertEqual(selected.fileURL, newest.fileURL)
        XCTAssertEqual(selected.yieldKg, 12.4)
        XCTAssertTrue(trees.contains { $0.id == selected.id })
    }

    func testOrchardWorkspaceSelectionCannotUpgradeIncompleteOrUnlocatedScan() throws {
        let complete = ScanFileRecord(id: "complete", treeID: "T012", fileURL: URL(fileURLWithPath: "/complete.ply"), scanDate: Date(timeIntervalSince1970: 1), yieldKg: 0, gpsLat: 30, gpsLon: 120, confidence: "low")
        let incomplete = ScanFileRecord(id: "incomplete", treeID: "T012", fileURL: URL(fileURLWithPath: "/incomplete.ply"), scanDate: Date(timeIntervalSince1970: 3), yieldKg: 99, gpsLat: 30, gpsLon: 120, persistenceState: .incomplete)
        let unlocated = ScanFileRecord(id: "unlocated", treeID: "T012", fileURL: URL(fileURLWithPath: "/unlocated.ply"), scanDate: Date(timeIntervalSince1970: 4), yieldKg: 88)
        let records = [incomplete, unlocated, complete]
        let selected = try XCTUnwrap(OrchardWorkspaceSelection.record(in: records, trees: OrchardMapData(records: records).trees, selectedTreeID: "T012"))
        XCTAssertEqual(selected, complete)
        XCTAssertEqual(selected.yieldKg, 0)
        XCTAssertEqual(selected.confidence, "low")
    }

    func testOrchardWorkspaceSelectionRecoversWhenSelectedTreeDisappears() throws {
        let current = ScanFileRecord(id: "current", treeID: "T013", fileURL: URL(fileURLWithPath: "/current.ply"), scanDate: Date(), gpsLat: 30, gpsLon: 120)
        XCTAssertEqual(OrchardWorkspaceSelection.record(in: [current], trees: OrchardMapData(records: [current]).trees, selectedTreeID: "T012"), current)
        XCTAssertNil(OrchardWorkspaceSelection.record(in: [], trees: [], selectedTreeID: "T012"))
    }

    @MainActor
    func testRootActivationFreezesAcceptedClassificationAndPreservesRequestIdentity() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        fixture.root.tagStore.addTag(name: "第二标签")
        let second = try XCTUnwrap(fixture.root.tagStore.tags.last)
        let request = ScanLaunchRequest(treeID: "CLASS61", selectedFruitCategory: .pear, season: .mature,
            gps: GPSRecorder(), plotId: fixture.plot.id,
            tagIds: [second.id, UUID(), fixture.tag.id, second.id])
        let accepted = fixture.root.activateScanRequest(request)
        XCTAssertEqual(accepted.id, request.id)
        XCTAssertTrue(accepted.gps === request.gps)
        XCTAssertEqual(accepted.classification.plot, .init(id: fixture.plot.id, name: fixture.plot.name))
        XCTAssertEqual(accepted.classification.tags, [.init(id: second.id, name: second.name),
                                                      .init(id: fixture.tag.id, name: fixture.tag.name)])
        XCTAssertEqual(accepted.tagIds, [second.id, fixture.tag.id])
        XCTAssertEqual(fixture.root.tagStore.getAssignment(treeId: request.treeID)?.tagIds, accepted.tagIds)
        var renamed = fixture.plot
        renamed.name = "之后改名"
        fixture.root.tagStore.updatePlot(renamed)
        fixture.root.tagStore.deleteTag(id: second.id)
        fixture.root.tagStore.createOrUpdateAssignment(treeId: request.treeID, plotId: nil, tagIds: [], status: .notScanned)
        XCTAssertEqual(accepted.classification.plot?.name, fixture.plot.name)
        XCTAssertEqual(accepted.classification.tags.map(\.name), [second.name, fixture.tag.name])
        let next = fixture.root.activateScanRequest(request)
        XCTAssertEqual(next.classification.plot?.name, renamed.name)
        XCTAssertEqual(next.classification.tags.map(\.id), [fixture.tag.id])
        let invalid = fixture.root.activateScanRequest(ScanLaunchRequest(treeID: "EMPTY61",
            selectedFruitCategory: .pear, season: .mature, gps: GPSRecorder(), plotId: UUID(), tagIds: [UUID()]))
        XCTAssertEqual(invalid.classification, .empty)
        await fixture.verifyStandard()
    }

    @MainActor
    func testMountedScanStartAndInterruptionRestartKeepLaunchClassification() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let accepted = fixture.root.activateScanRequest(ScanLaunchRequest(treeID: "CLASS61",
            selectedFruitCategory: .pear, season: .mature, gps: GPSRecorder(),
            plotId: fixture.plot.id, tagIds: [fixture.tag.id]))
        let runtime = ScanSessionRuntime(isWorldTrackingSupported: { true }, run: { _, _, _ in },
                                         preferredVideoFormat: { _ in nil })
        let coordinator = ScanCoordinator(settings: fixture.root.settings, sessionRuntime: runtime,
                                          calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        let recovery = ScanLifecycleRecoveryPresentationController()
        let readiness = ScanReadinessRequestController(determine: { .ready })
        let workflow = ScanFinalizationWorkflow()
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(RootMismatchHost(scan: ScanView(treeID: accepted.treeID, gps: accepted.gps, season: accepted.season,
            selectedFruitCategory: accepted.selectedFruitCategory, appDependencies: fixture.root, onScanNextTree: {},
            classification: accepted.classification, coordinator: coordinator,
            readinessRequestController: readiness, finalizationWorkflow: workflow, lifecycleRecoveryPresentation: recovery)))
        let ready = try await ui.waitFor {
            workflow.onEvent != nil && coordinator.renderer != nil && !readiness.isRunning
                && ui.element(label: L10n.ScanGuidance.text(.start)) != nil
        }
        XCTAssertTrue(ready)
        fixture.root.tagStore.deleteTag(id: fixture.tag.id)
        var renamed = fixture.plot
        renamed.name = "新名称"
        fixture.root.tagStore.updatePlot(renamed)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.ScanGuidance.text(.start))).accessibilityActivate())
        let started = try await ui.waitFor { coordinator.lifecycleSnapshot().state == .recording }
        XCTAssertTrue(started)
        let first = try XCTUnwrap(coordinator.activeScanPlan)
        XCTAssertEqual(first.classification, accepted.classification)
        try await ui.attach(to: self, phase: "classification61-started")
        coordinator.handleSystemInterruption(.arSessionInterrupted)
        let offered = try await ui.waitFor { recovery.presentation != nil }
        XCTAssertTrue(offered)
        let choice = try XCTUnwrap(recovery.presentation)
        recovery.presentation = nil
        try ui.dismissSystemAlert()
        _ = try await ui.waitFor { ui.element(label: L10n.Scan.interruptionTitle) == nil }
        recovery.restart(presentationID: choice.id)
        let restarted = try await ui.waitFor { coordinator.lifecycleSnapshot().state == .recording }
        XCTAssertTrue(restarted)
        let second = try XCTUnwrap(coordinator.activeScanPlan)
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(second.classification, accepted.classification)
        XCTAssertEqual(second.classification.tags.map(\.id), [fixture.tag.id])
        try await ui.attach(to: self, phase: "classification61-restarted")
        await fixture.verifyStandard()
    }

    @MainActor
    func testFailedMetalCaptureShowsAccurateRecoveryAndRestartsWithNewOwner() async throws {
        try await verifyCaptureRecoveryUI(restart: true)
    }

    @MainActor
    func testFailedMetalCaptureDiscardLeavesNoScanReceipt() async throws {
        try await verifyCaptureRecoveryUI(restart: false)
    }

    @MainActor
    func testFailedMetalCaptureUnavailableRestartKeepsGateClosedAndOffersRecoveryAgain() async throws {
        try await verifyCaptureRecoveryUI(restart: true, canRestart: false)
    }

    @MainActor
    func testCaptureRecoveryWaitsForCameraReadinessAndRejectsTheHiddenOldChoice() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let runtime = ScanSessionRuntime(isWorldTrackingSupported: { true }, run: { _, _, _ in },
                                         preferredVideoFormat: { _ in nil })
        let coordinator = ScanCoordinator(settings: fixture.root.settings, sessionRuntime: runtime,
                                          calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        let workflow = ScanFinalizationWorkflow()
        let recovery = ScanLifecycleRecoveryPresentationController()
        let camera = CaptureRecoveryReadinessFixture()
        defer { Task { await camera.becomeReady() } }
        let readiness = ScanReadinessRequestController(determine: { await camera.determine() })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(RootMismatchHost(scan: ScanView(treeID: "CAMERA52", gps: GPSRecorder(), season: .mature,
            selectedFruitCategory: .pear, appDependencies: fixture.root, onScanNextTree: {},
            coordinator: coordinator, showGuide: false, readinessRequestController: readiness,
            finalizationWorkflow: workflow, lifecycleRecoveryPresentation: recovery)))
        let ready = try await ui.waitFor { workflow.onEvent != nil && coordinator.renderer != nil && !readiness.isRunning }
        XCTAssertTrue(ready)
        let renderer = try XCTUnwrap(coordinator.renderer)
        let plan = fixture.root.scanPlanFactory.makePlan(treeID: "CAMERA52", season: .mature,
                                                        selectedCategory: .pear, renderer: renderer)
        coordinator.startRecording(plan: plan)
        let owner = coordinator.lifecycleSnapshot().scanIdentity
        try injectGPUCompletionFailure(renderer)
        workflow.finish(plan: plan, latitude: 0, longitude: 0,
                        operations: fixture.root.finalizationOperations(coordinator: coordinator))
        let alert = try await ui.waitFor { ui.element(label: L10n.Scan.pointCloudCaptureFailedTitle) != nil }
        XCTAssertTrue(alert)
        let oldChoice = try XCTUnwrap(recovery.presentation)
        coordinator.handleSessionFailure(NSError(domain: ARErrorDomain, code: ARError.Code.cameraUnauthorized.rawValue))
        let checking = try await ui.waitFor { recovery.presentation == nil && readiness.isRunning }
        XCTAssertTrue(checking)
        recovery.restart(presentationID: oldChoice.id)
        recovery.discard(presentationID: oldChoice.id)
        XCTAssertEqual(coordinator.lifecycleSnapshot().scanIdentity, owner)
        guard case .failed(.cameraUnavailable) = coordinator.lifecycleSnapshot().state else {
            return XCTFail("Camera authorization failure must keep the owner in readiness recovery")
        }
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        XCTAssertTrue(renderer.pointBufferSnapshot().writeFailed)
        await camera.becomeReady()
        let reprompted = try await ui.waitFor {
            recovery.presentation?.scanIdentity == owner && recovery.presentation?.id != oldChoice.id
                && ui.element(label: L10n.Scan.sessionFailureTitle) != nil
        }
        XCTAssertTrue(reprompted, "The mounted view must offer recovery after the camera becomes ready")
        XCTAssertFalse(coordinator.acceptsReliableEvidence())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), [])
        try await ui.attach(to: self, phase: "capture52-camera-ready-recovery")
        await fixture.verifyStandard()
    }

    @MainActor
    private func verifyCaptureRecoveryUI(restart: Bool, canRestart: Bool = true) async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let runtime = ScanSessionRuntime(isWorldTrackingSupported: { true }, run: { _, _, _ in },
                                         preferredVideoFormat: { _ in nil })
        let coordinator = ScanCoordinator(settings: fixture.root.settings, sessionRuntime: runtime,
                                          calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        let workflow = ScanFinalizationWorkflow()
        let recovery = ScanLifecycleRecoveryPresentationController()
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        let scan = ScanView(treeID: "RECOVERY52", gps: GPSRecorder(), season: .mature,
                            selectedFruitCategory: .pear, appDependencies: fixture.root, onScanNextTree: {},
                            coordinator: coordinator, showGuide: false,
                            readinessRequestController: ScanReadinessRequestController(determine: { .ready }),
                            finalizationWorkflow: workflow, lifecycleRecoveryPresentation: recovery)
        ui.mount(RootMismatchHost(scan: scan))
        let ready = try await ui.waitFor { workflow.onEvent != nil && coordinator.renderer != nil }
        XCTAssertTrue(ready)
        let renderer = try XCTUnwrap(coordinator.renderer)
        let plan = fixture.root.scanPlanFactory.makePlan(treeID: "RECOVERY52", season: .mature,
                                                       selectedCategory: .pear, renderer: renderer)
        coordinator.startRecording(plan: plan)
        let old = coordinator.lifecycleSnapshot()
        let failedGeneration = renderer.pointBufferSnapshot().generation
        try injectGPUCompletionFailure(renderer)
        XCTAssertTrue(renderer.pointBufferSnapshot().writeFailed)
        let consume = try XCTUnwrap(workflow.onEvent)
        var failures: [ScanFinalizationWorkflow.Failure] = []
        workflow.onEvent = { event in
            if case .failed(_, let failure) = event { failures.append(failure) }
            consume(event)
        }
        workflow.finish(plan: plan, latitude: 0, longitude: 0,
                        operations: fixture.root.finalizationOperations(coordinator: coordinator))
        let presented = try await ui.waitFor { ui.element(label: L10n.Scan.pointCloudCaptureFailedTitle) != nil }
        XCTAssertTrue(presented)
        XCTAssertEqual(failures, [.pointCloudCaptureInvalid])
        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .failed(.invalidPointCloudCapture))
        XCTAssertEqual(workflow.retryAction, .unavailable)
        XCTAssertNil(workflow.filename)
        XCTAssertNotNil(ui.element(label: L10n.Scan.pointCloudCaptureFailedMessage))
        XCTAssertNil(ui.element(label: L10n.Scan.exportFailed))
        XCTAssertNotNil(ui.element(label: L10n.Scan.restartAfterInterruption))
        XCTAssertNotNil(ui.element(label: L10n.Scan.discardAfterInterruption))
        try await ui.attach(to: self, phase: restart ? "capture52-restart-alert" : "capture52-discard-alert")
        let choice = try XCTUnwrap(recovery.presentation)
        XCTAssertEqual(choice.scanIdentity, old.scanIdentity)
        // UIKit's native UIAlert action views cannot be activated in-process.
        // Exercise the alert's production intent and mounted ScanView binding here;
        // native touches are verified separately on the simulator.
        recovery.presentation = nil // SwiftUI can clear the binding before invoking its action.
        try ui.dismissSystemAlert()
        let hidden = try await ui.waitFor { ui.element(label: L10n.Scan.pointCloudCaptureFailedTitle) == nil }
        XCTAssertTrue(hidden)
        if !canRestart { coordinator.session = nil }
        if restart { recovery.restart(presentationID: choice.id) }
        else { recovery.discard(presentationID: choice.id) }
        let acted = try await ui.waitFor {
            if !canRestart { return recovery.presentation?.id != choice.id && recovery.presentation != nil }
            return restart ? coordinator.lifecycleSnapshot().state == .recording
                : coordinator.lifecycleSnapshot().state == .cancelled && ui.controller.presentedViewController == nil
        }
        XCTAssertTrue(acted)
        if !canRestart {
            XCTAssertEqual(coordinator.lifecycleSnapshot().scanIdentity, old.scanIdentity)
            guard case .failed(.sessionFailed) = coordinator.lifecycleSnapshot().state else {
                return XCTFail("An unavailable AR session must leave the scan failed")
            }
            XCTAssertEqual(coordinator.activeScanPlan?.id, plan.id)
            XCTAssertEqual(renderer.pointBufferSnapshot().generation, failedGeneration)
            XCTAssertTrue(renderer.pointBufferSnapshot().writeFailed)
            XCTAssertFalse(coordinator.acceptsReliableEvidence())
            XCTAssertEqual(recovery.presentation?.scanIdentity, old.scanIdentity)
            let shownAgain = try await ui.waitFor { ui.element(label: L10n.Scan.sessionFailureTitle) != nil }
            XCTAssertTrue(shownAgain, "A failed restart must offer recovery again in the mounted UI")
        } else if restart {
            XCTAssertNotEqual(coordinator.lifecycleSnapshot().scanIdentity, old.scanIdentity)
            XCTAssertNotEqual(coordinator.activeScanPlan?.id, plan.id)
            XCTAssertNotEqual(renderer.pointBufferSnapshot().generation, failedGeneration)
            XCTAssertFalse(renderer.pointBufferSnapshot().writeFailed)
            XCTAssertEqual(workflow.phase, .idle)
            XCTAssertNotNil(ui.controller.presentedViewController)
        } else {
            XCTAssertEqual(coordinator.lifecycleSnapshot().scanIdentity, old.scanIdentity)
            XCTAssertTrue(coordinator.isTornDown)
            XCTAssertNil(ui.controller.presentedViewController)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), [])
        let after = coordinator.lifecycleSnapshot()
        let capture = renderer.pointBufferSnapshot()
        let facts: [String: Any] = [
            "scanID_before": old.scanIdentity.uuidString, "scanID_after": after.scanIdentity.uuidString,
            "planID_before": plan.id.uuidString, "planID_after": coordinator.activeScanPlan?.id.uuidString ?? "none",
            "captureGeneration_before": failedGeneration, "captureGeneration_after": capture.generation,
            "writeFailed_after": capture.writeFailed, "state_after": String(describing: after.state),
            "workflow_after": String(describing: workflow.phase), "tornDown_after": coordinator.isTornDown,
            "repository_files": try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
        ]
        let state = XCTAttachment(data: try JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys]),
                                  uniformTypeIdentifier: "public.json")
        state.name = "CaptureRecovery52-state"
        state.lifetime = .keepAlways
        add(state)
        try await ui.attach(to: self, phase: !canRestart ? "capture52-restart-unavailable" :
                            (restart ? "capture52-restarted" : "capture52-discarded"))
        await fixture.verifyStandard()
    }

    private func injectGPUCompletionFailure(_ renderer: Renderer) throws {
        guard renderer.inFlightSemaphore.wait(timeout: .now()) == .success else {
            throw NSError(domain: "Capture52-permit-fixture", code: 1)
        }
        renderer.completePointCloudCommand(status: .error, captureGeneration: renderer.pointBufferSnapshot().generation, wrotePoints: true)
    }

    @MainActor
    func testStaleCaptureRecoveryActionsCannotChangeReplacementOrCompletedScan() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let coordinator = ScanCoordinator(settings: fixture.root.settings, calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        let scan = ScanView(treeID: "STALE52", gps: GPSRecorder(), season: .mature,
                            selectedFruitCategory: .pear, appDependencies: fixture.root, onScanNextTree: {}, coordinator: coordinator)
        let old = coordinator.scanSession.startNewScan()
        _ = coordinator.scanSession.beginFinishing()
        XCTAssertTrue(coordinator.handleInvalidPointCloudCapture(scanIdentity: old.scanIdentity))
        let replacement = coordinator.scanSession.startNewScan()
        scan.restartAfterInterruption(scanIdentity: old.scanIdentity)
        scan.discardAfterInterruption(scanIdentity: old.scanIdentity)
        XCTAssertEqual(coordinator.lifecycleSnapshot(), replacement)
        _ = coordinator.scanSession.beginFinishing()
        let completed = coordinator.scanSession.complete()
        scan.restartAfterInterruption(scanIdentity: completed.scanIdentity)
        scan.discardAfterInterruption(scanIdentity: completed.scanIdentity)
        XCTAssertEqual(coordinator.lifecycleSnapshot(), completed)
        XCTAssertFalse(coordinator.isTornDown)
        await fixture.verifyStandard()
    }

    @MainActor
    func testScanViewIgnoresQueuedFailureLifecycleForReplacedScan() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let runtime = ScanSessionRuntime(
            isWorldTrackingSupported: { true },
            run: { _, _, _ in }, // Replace only physical AR session execution.
            preferredVideoFormat: { _ in nil }
        )
        let coordinator = ScanCoordinator(settings: fixture.root.settings, sessionRuntime: runtime,
                                          calibrationRecordsLoader: { [] })
        defer { coordinator.teardown() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        let scan = ScanView(treeID: "CAPTURE52", gps: GPSRecorder(), season: .mature,
                            selectedFruitCategory: .pear, appDependencies: fixture.root, onScanNextTree: {},
                            coordinator: coordinator, showGuide: false,
                            readinessRequestController: ScanReadinessRequestController(determine: { .ready }))
        ui.mount(RootMismatchHost(scan: scan))
        let ready = try await ui.waitFor { coordinator.onLifecycleStateChange != nil && coordinator.renderer != nil }
        XCTAssertTrue(ready)
        let plan = fixture.root.scanPlanFactory.makePlan(treeID: "CAPTURE52", season: .mature,
                                                       selectedCategory: .pear, renderer: coordinator.renderer)
        coordinator.startRecording(plan: plan)
        XCTAssertTrue(coordinator.beginFinishingScan())
        coordinator.handleSessionFailure(NSError(domain: "Capture52-old-lifecycle-fixture", code: 1))
        let old = coordinator.lifecycleSnapshot()
        coordinator.startRecording(plan: plan)
        let replacement = coordinator.lifecycleSnapshot()
        XCTAssertNotEqual(old.scanIdentity, replacement.scanIdentity)
        let consumed = expectation(description: "Queued lifecycle notifications consumed on main")
        DispatchQueue.main.async { consumed.fulfill() }
        await fulfillment(of: [consumed], timeout: 2)
        try await ui.attach(to: self, phase: "capture52-stale-lifecycle")
        XCTAssertNil(ui.element(label: L10n.Scan.restartAfterInterruption), "Old failure must not open recovery for the new scan")
        XCTAssertEqual(coordinator.lifecycleSnapshot(), replacement)
        await fixture.verifyStandard()
    }

    @MainActor
    func testVarietySliderMillimetersMatchSavedCardAndReopenedEditorWithoutRoundingPhysicalValue() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let original = fixture.root.parametersStore.param(for: .pear)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openVarietyDatabase()
        try await ui.editVariety(.pear)
        try await ui.changeVarietySlider(L10n.VarietyDatabase.maximumDiameter, value: 0.150, range: 0.05...0.30,
                                         expected: "150 mm")
        XCTAssertEqual(ui.varietySliderValue(L10n.VarietyDatabase.minimumDiameter), "35 mm")
        try await ui.attach(to: self, phase: "47-slider-millimeters")
        try await ui.saveVarietyAndWaitForDatabase(.pear)
        await fixture.root.parametersStore.waitForPendingSave()
        let saved = fixture.root.parametersStore.param(for: .pear)
        XCTAssertEqual(saved.diamMax.bitPattern, Float(0.14999999).bitPattern,
                       "Formatting must not normalize the slider's physical value to the displayed whole millimeter")
        var unchanged = saved
        unchanged.diamMax = original.diamMax
        XCTAssertEqual(unchanged, original)
        _ = try await ui.scrollToControl(label: L10n.VarietyDatabase.editAccessibility(L10n.Fruit.name(for: .pear)))
        try await ui.attach(to: self, phase: "47-saved-diameter-card")
        try await ui.editVariety(.pear)
        XCTAssertEqual(ui.varietySliderValue(L10n.VarietyDatabase.maximumDiameter), "150 mm")
        XCTAssertEqual(ui.varietySliderValue(L10n.VarietyDatabase.minimumDiameter), "35 mm")
        let snapshot = fixture.root.parametersStore.parameterSnapshot()
        let bytes = try XCTUnwrap(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey))
        var publications = 0
        let observation = fixture.root.parametersStore.$params.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        try await ui.saveVarietyAndWaitForDatabase(.pear)
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(publications, 0)
        XCTAssertEqual(fixture.root.parametersStore.parameterSnapshot(), snapshot)
        XCTAssertEqual(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
        await fixture.verifyStandard()
    }

    @MainActor
    func testVarietyRoundedDisplayDoesNotWriteUneditedPhysicalBoundaryParameters() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        fixture.root.parametersStore.updateParam(for: .pear) {
            $0.diamMin = 0.034999996
            $0.diamMax = 0.14999999
        }
        await fixture.root.parametersStore.waitForPendingSave()
        await fixture.root.prepareForScanning()
        let frozen = fixture.plan("ROOT47-FROZEN")
        let context = try XCTUnwrap(frozen.fruitConfiguration.calibrationContext)
        let snapshot = fixture.root.parametersStore.parameterSnapshot()
        // Compare this fixture's persisted keys, excluding inherited framework registration domains.
        let preferences = try XCTUnwrap(fixture.defaults.persistentDomain(forName: fixture.suite))
        var publications = 0
        let observation = fixture.root.parametersStore.$params.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openVarietyDatabase()
        _ = try await ui.scrollToControl(label: L10n.VarietyDatabase.editAccessibility(L10n.Fruit.name(for: .pear)))
        try await ui.attach(to: self, phase: "47-unedited-boundary-card")
        try await ui.editVariety(.pear)
        XCTAssertEqual(ui.varietySliderValue(L10n.VarietyDatabase.minimumDiameter), "35 mm")
        XCTAssertEqual(ui.varietySliderValue(L10n.VarietyDatabase.maximumDiameter), "150 mm")
        try await ui.attach(to: self, phase: "47-unedited-boundary-editor")
        try await ui.saveVarietyAndWaitForDatabase(.pear)
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(fixture.root.parametersStore.hasPendingSave)
        XCTAssertEqual(fixture.root.parametersStore.parameterSnapshot(), snapshot)
        let persistedPreferences = try XCTUnwrap(fixture.defaults.persistentDomain(forName: fixture.suite))
        XCTAssertTrue(NSDictionary(dictionary: persistedPreferences).isEqual(to: preferences))
        let next = fixture.plan("ROOT47-NEXT")
        XCTAssertEqual(next.fruitConfiguration.defaultParams, frozen.fruitConfiguration.defaultParams)
        XCTAssertEqual(next.fruitConfiguration.calibrationContext, context)
        let persisted = FruitParametersStore(defaults: fixture.defaults)
        XCTAssertEqual(persisted.parameterSnapshot(), snapshot)
        await persisted.waitForPendingSave()
        await fixture.verifyStandard()
    }

    @MainActor
    func testVarietyWeightOnlySavePreservesNewerFieldsAndFrozenPlan() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let frozen = fixture.plan("ROOT45-FROZEN")
        let context = frozen.fruitConfiguration.calibrationContext
        let apple = fixture.root.parametersStore.param(for: .apple)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openVarietyDatabase()
        try await ui.editVariety(.pear)
        try await ui.changeVarietySlider(L10n.VarietyDatabase.averageWeight, value: 222,
                                         expected: VarietyParameterFormatter.grams(222))
        fixture.root.parametersStore.updateParam(for: .pear) {
            $0.diamMin = 0.040
            $0.diamMax = 0.165
            $0.density = 0.93
            $0.clusterEps = 0.055
            $0.sphericityThreshold = 0.64
        }
        await fixture.root.parametersStore.waitForPendingSave()
        var expected = fixture.root.parametersStore.param(for: .pear)
        expected.averageWeightG = 222
        fixture.root.settings.fruitType = "apple"
        try await ui.saveVarietyAndWaitForDatabase(.pear)
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear), expected,
                       "A weight edit must preserve the newer root's other five fields and identity")
        XCTAssertEqual(fixture.root.parametersStore.param(for: .apple), apple)
        let reloaded = FruitParametersStore(defaults: fixture.defaults)
        XCTAssertEqual(reloaded.param(for: .pear), expected)
        let next = fixture.plan("ROOT45-NEXT")
        XCTAssertEqual(next.fruitConfiguration.defaultParams, expected)
        XCTAssertEqual(frozen.fruitConfiguration.defaultParams.averageWeightG, 221)
        XCTAssertEqual(frozen.fruitConfiguration.defaultParams.diamMax, 0.145, accuracy: 0.00001)
        XCTAssertEqual(frozen.fruitConfiguration.calibrationContext, context)
        try await ui.editVariety(.pear)
        XCTAssertEqual(ui.varietySliderValue(L10n.VarietyDatabase.maximumDiameter),
                       VarietyParameterFormatter.millimeters(0.165))
        _ = try await ui.scrollToControl(label: L10n.VarietyDatabase.averageWeight)
        XCTAssertEqual(ui.varietySliderValue(L10n.VarietyDatabase.averageWeight),
                       VarietyParameterFormatter.grams(222))
        try await ui.attach(to: self, phase: "45-variety-merged-reopened")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.cancel)).accessibilityActivate())
        await reloaded.waitForPendingSave()
        await fixture.verifyStandard()
    }

    @MainActor
    func testUneditedVarietySavePreservesNewerValuesWithoutPublishing() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openVarietyDatabase()
        try await ui.editVariety(.pear)
        fixture.root.parametersStore.updateParam(for: .pear) {
            $0.diamMax = 0.165
            $0.averageWeightG = 333
            $0.sphericityThreshold = 0.64
        }
        await fixture.root.parametersStore.waitForPendingSave()
        let expected = fixture.root.parametersStore.parameterSnapshot()
        let bytes = try XCTUnwrap(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey))
        var publications = 0
        let observation = fixture.root.parametersStore.$params.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        try await ui.saveVarietyAndWaitForDatabase(.pear)
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(fixture.root.parametersStore.parameterSnapshot(), expected)
        XCTAssertEqual(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
        XCTAssertEqual(publications, 0, "Unedited save must not publish or enqueue persistence")
        await fixture.verifyStandard()
    }

    @MainActor
    func testVarietyConflictingSavePreservesLatestAndAllowsRetry() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openVarietyDatabase()
        try await ui.editVariety(.pear)
        try await ui.changeVarietySlider(L10n.VarietyDatabase.averageWeight, value: 222,
                                         expected: VarietyParameterFormatter.grams(222))
        fixture.root.parametersStore.updateParam(for: .pear) {
            $0.averageWeightG = 333
            $0.diamMax = 0.165
            $0.sphericityThreshold = 0.64
        }
        await fixture.root.parametersStore.waitForPendingSave()
        let current = fixture.root.parametersStore.parameterSnapshot()
        let bytes = try XCTUnwrap(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey))
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.save)).accessibilityActivate())
        let rejected = try await ui.waitFor {
            ui.varietySliderValue(L10n.VarietyDatabase.averageWeight) == VarietyParameterFormatter.grams(333)
        }
        XCTAssertTrue(rejected, "A conflicting save must retain the edit sheet and rebase to the newer value")
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(fixture.root.parametersStore.parameterSnapshot(), current)
        XCTAssertEqual(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
        guard rejected else { await fixture.verifyStandard(); return }
        XCTAssertNotNil(ui.element(label: L10n.VarietyDatabase.parameterConflict))
        try await ui.attach(to: self, phase: "45-variety-conflict")
        try await ui.changeVarietySlider(L10n.VarietyDatabase.averageWeight, value: 334,
                                         expected: VarietyParameterFormatter.grams(334))
        try await ui.saveVarietyAndWaitForDatabase(.pear)
        await fixture.root.parametersStore.waitForPendingSave()
        var expected = try XCTUnwrap(current["pear"])
        expected.averageWeightG = 334
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear), expected)
        await fixture.verifyStandard()
    }

    @MainActor
    func testVarietyCancelPreservesNewerValuesAndDoesNotSaveDrafts() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openVarietyDatabase()
        try await ui.editVariety(.pear)
        try await ui.changeVarietySlider(L10n.VarietyDatabase.averageWeight, value: 222,
                                         expected: VarietyParameterFormatter.grams(222))
        fixture.root.parametersStore.updateParam(for: .pear) {
            $0.averageWeightG = 333
            $0.diamMax = 0.165
        }
        await fixture.root.parametersStore.waitForPendingSave()
        let snapshot = fixture.root.parametersStore.parameterSnapshot()
        let bytes = try XCTUnwrap(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey))
        var publications = 0
        let observation = fixture.root.parametersStore.$params.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.cancel)).accessibilityActivate())
        let closed = try await ui.waitFor {
            ui.element(label: L10n.VarietyDatabase.editAccessibility(L10n.Fruit.name(for: .pear))) != nil
        }
        XCTAssertTrue(closed)
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(fixture.root.parametersStore.parameterSnapshot(), snapshot)
        XCTAssertEqual(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
        XCTAssertEqual(publications, 0)
        await fixture.verifyStandard()
    }

    @MainActor
    func testVarietyDiameterEditProtectsNewerLowerBoundAndAllowsSafeMerge() async throws {
        for minimum: Float in [0.142, 0.040] {
            let fixture = try await RootParameterFixture()
            defer { fixture.cleanup() }
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            fixture.mount(on: ui)
            try await ui.openVarietyDatabase()
            try await ui.editVariety(.pear)
            try await ui.changeVarietySlider(L10n.VarietyDatabase.maximumDiameter, value: 0.140, range: 0.05...0.30,
                                             expected: VarietyParameterFormatter.millimeters(0.140))
            fixture.root.parametersStore.updateParam(for: .pear) { $0.diamMin = minimum }
            await fixture.root.parametersStore.waitForPendingSave()
            let latest = fixture.root.parametersStore.param(for: .pear)
            if minimum == 0.142 {
                XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.save)).accessibilityActivate())
                let rejected = try await ui.waitFor {
                    ui.element(label: L10n.VarietyDatabase.parameterConflict) != nil &&
                    ui.varietySliderValue(L10n.VarietyDatabase.maximumDiameter) ==
                        VarietyParameterFormatter.millimeters(0.145)
                }
                XCTAssertTrue(rejected)
                XCTAssertEqual(fixture.root.parametersStore.param(for: .pear), latest)
                try await ui.changeVarietySlider(L10n.VarietyDatabase.maximumDiameter, value: 0.150, range: 0.05...0.30,
                                                 // Float slider mapping stays below .150 m; whole-millimeter display rounds to 150.
                                                 expected: "150 mm")
            }
            try await ui.saveVarietyAndWaitForDatabase(.pear)
            await fixture.root.parametersStore.waitForPendingSave()
            let saved = fixture.root.parametersStore.param(for: .pear)
            XCTAssertEqual(saved.diamMax, minimum == 0.142 ? 0.150 : 0.140, accuracy: 0.000001)
            var unchanged = saved
            unchanged.diamMax = latest.diamMax
            XCTAssertEqual(unchanged, latest, "Only the edited maximum may change; all other fields and identity must remain exact")
            XCTAssertLessThanOrEqual(saved.diamMin, saved.diamMax)
            await fixture.verifyStandard()
        }
    }

    @MainActor
    func testVarietyResetIdentityInvalidatesOldDraftEvenWhenValuesMatch() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        fixture.root.parametersStore.resetToDefault(for: .pear)
        await fixture.root.parametersStore.waitForPendingSave()
        let original = fixture.root.parametersStore.param(for: .pear)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openVarietyDatabase()
        try await ui.editVariety(.pear)
        try await ui.changeVarietySlider(L10n.VarietyDatabase.averageWeight, value: 181,
                                         expected: VarietyParameterFormatter.grams(181))
        fixture.root.parametersStore.resetToDefault(for: .pear)
        await fixture.root.parametersStore.waitForPendingSave()
        let reset = fixture.root.parametersStore.param(for: .pear)
        XCTAssertNotEqual(reset.id, original.id)
        XCTAssertEqual(reset.averageWeightG, original.averageWeightG)
        let bytes = try XCTUnwrap(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey))
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.save)).accessibilityActivate())
        let rejected = try await ui.waitFor {
            ui.element(label: L10n.VarietyDatabase.parameterConflict) != nil &&
            ui.varietySliderValue(L10n.VarietyDatabase.averageWeight) == VarietyParameterFormatter.grams(180)
        }
        XCTAssertTrue(rejected)
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear), reset)
        XCTAssertEqual(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
        XCTAssertFalse(reset.isCustomized)
        try await ui.attach(to: self, phase: "45-variety-reset-conflict")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.cancel)).accessibilityActivate())
        let closed = try await ui.waitFor {
            ui.element(label: L10n.VarietyDatabase.editAccessibility(L10n.Fruit.name(for: .pear))) != nil
        }
        XCTAssertTrue(closed)
        await fixture.verifyStandard()
    }

    @MainActor
    func testUneditedCalibrationClosePreservesNewerRootParametersWithoutSaving() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openCalibration()
        XCTAssertEqual(ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue, "0.145 m")
        fixture.root.parametersStore.updateParam(for: .pear) {
            $0.diamMax = 0.165
            $0.sphericityThreshold = 0.64
            $0.averageWeightG = 233
        }
        fixture.root.settings.clusterMinPoints = 24
        fixture.root.settings.clusterMaxDiameter = 0.165
        fixture.root.settings.sphericityThreshold = 0.64
        await fixture.root.parametersStore.waitForPendingSave()
        let parameters = fixture.root.parametersStore.parameterSnapshot()
        let bytes = try XCTUnwrap(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey))
        var publications = 0
        let observation = fixture.root.parametersStore.$params.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        try await ui.closeCalibration()
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(fixture.root.settings.clusterMinPoints, 24)
        XCTAssertEqual(fixture.root.settings.clusterMaxDiameter, 0.165, accuracy: 0.00001)
        XCTAssertEqual(fixture.root.settings.sphericityThreshold, 0.64, accuracy: 0.00001)
        XCTAssertEqual(fixture.root.parametersStore.parameterSnapshot(), parameters)
        XCTAssertEqual(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
        XCTAssertEqual(publications, 0, "Closing an unedited page must not rewrite parameter state")
        try await ui.openCalibration()
        XCTAssertEqual(ui.element(label: L10n.Calibration.minimumClusterPoints)?.accessibilityValue, "24")
        XCTAssertEqual(ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue, "0.165 m")
        XCTAssertEqual(ui.element(label: L10n.Calibration.minimumSphericity)?.accessibilityValue, "0.64")
        try await ui.attach(to: self, phase: "44-calibration-newer-reopened")
        try await ui.closeCalibration()
        await fixture.verifyStandard()
    }

    @MainActor
    func testCalibrationCloseDoesNotReapplyEarlierCommitsOverNewerValues() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        await fixture.root.prepareForScanning()
        let frozen = fixture.plan("ROOT44-FROZEN")
        let frozenContext = try XCTUnwrap(frozen.fruitConfiguration.calibrationContext)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openCalibration()
        let points = try await ui.changeCalibrationSlider(L10n.Calibration.minimumClusterPoints,
                                                        fraction: 1 / 147, expected: "20")
        points.sendActions(for: .touchUpInside)
        let pointsCommitted = try await ui.waitFor { fixture.root.settings.clusterMinPoints == 20 }
        XCTAssertTrue(pointsCommitted)
        let diameter = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                          fraction: 1 / 32, expected: "0.150 m")
        diameter.sendActions(for: .touchUpInside)
        let diameterCommitted = try await ui.waitFor { abs(fixture.root.settings.clusterMaxDiameter - 0.15) < 0.00001 }
        XCTAssertTrue(diameterCommitted)
        _ = try await ui.changeCalibrationSlider(L10n.Calibration.minimumSphericity,
                                                fraction: 1 / 30, expected: "0.60")
        fixture.root.parametersStore.updateParam(for: .pear) {
            $0.diamMax = 0.165
            $0.averageWeightG = 233
            $0.density = 0.92
        }
        fixture.root.settings.clusterMinPoints = 24
        fixture.root.settings.clusterMaxDiameter = 0.165
        try await ui.closeCalibration()
        // UIKit dismissal can precede SwiftUI's onDisappear draft commit.
        let sphericityCommitted = try await ui.waitFor {
            abs(fixture.root.settings.sphericityThreshold - 0.60) < 0.00001
        }
        XCTAssertTrue(sphericityCommitted)
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(fixture.root.settings.clusterMinPoints, 24)
        XCTAssertEqual(fixture.root.settings.clusterMaxDiameter, 0.165, accuracy: 0.00001)
        let persisted = FruitParametersStore(defaults: fixture.defaults)
        XCTAssertEqual(persisted.param(for: .pear).diamMax, 0.165, accuracy: 0.00001)
        XCTAssertEqual(persisted.param(for: .pear).sphericityThreshold, 0.60, accuracy: 0.00001,
                       "An independent pending field still commits when its source has not changed")
        XCTAssertEqual(persisted.param(for: .pear).averageWeightG, 233)
        XCTAssertEqual(persisted.param(for: .pear).density, 0.92, accuracy: 0.00001)
        let next = fixture.plan("ROOT44-NEXT")
        XCTAssertEqual(next.fruitConfiguration.clusterConfig.minPoints, 24)
        XCTAssertEqual(next.fruitConfiguration.defaultParams.diamMax, 0.165, accuracy: 0.00001)
        XCTAssertEqual(next.fruitConfiguration.defaultParams.sphericityThreshold, 0.60, accuracy: 0.00001)
        XCTAssertEqual(frozen.fruitConfiguration.defaultParams.diamMax, 0.145, accuracy: 0.00001)
        XCTAssertEqual(frozen.fruitConfiguration.calibrationContext, frozenContext)
        XCTAssertNotEqual(next.fruitConfiguration.calibrationContext, frozenContext)
        await persisted.waitForPendingSave()
        await fixture.verifyStandard()
    }

    @MainActor
    func testCalibrationConflictingGesturePreservesNewerValuesAndCanBeRetried() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openCalibration()
        let diameter = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                          fraction: 1 / 32, expected: "0.150 m")
        fixture.root.parametersStore.updateParam(for: .pear) { $0.diamMax = 0.165 }
        diameter.sendActions(for: .touchUpInside)
        let protected = try await ui.waitFor {
            abs(fixture.root.parametersStore.param(for: .pear).diamMax - 0.165) < 0.00001 &&
                ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue == "0.165 m"
        }
        XCTAssertTrue(protected, "A stale pending gesture must not overwrite a newer same-field save")
        guard protected else { await fixture.verifyStandard(); return }
        XCTAssertEqual(fixture.root.settings.clusterMaxDiameter, 0.145, accuracy: 0.00001,
                       "A parameter-only conflict must not copy either stale draft into settings")
        let notice = try await ui.waitFor { ui.element(label: L10n.Calibration.parameterConflict) != nil }
        XCTAssertTrue(notice, "A rejected stale gesture must explain why the displayed value changed")
        try await ui.attach(to: self, phase: "44-calibration-conflict")
        let retry = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                       fraction: 1 / 32, expected: "0.170 m")
        retry.sendActions(for: .touchUpInside)
        let retryCommitted = try await ui.waitFor { abs(fixture.root.settings.clusterMaxDiameter - 0.17) < 0.00001 }
        XCTAssertTrue(retryCommitted)
        try await ui.closeCalibration()
        await fixture.root.parametersStore.waitForPendingSave()
        let persisted = FruitParametersStore(defaults: fixture.defaults)
        XCTAssertEqual(persisted.param(for: .pear).diamMax, 0.17, accuracy: 0.00001)
        await persisted.waitForPendingSave()
        await fixture.verifyStandard()
    }

    @MainActor
    func testCalibrationSettingsOnlyConflictsProtectPendingFieldsAndAllowRetry() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openCalibration()
        let points = try await ui.changeCalibrationSlider(L10n.Calibration.minimumClusterPoints,
                                                        fraction: 1 / 147, expected: "20")
        let diameter = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                          fraction: 1 / 32, expected: "0.150 m")
        fixture.root.settings.clusterMinPoints = 24
        fixture.root.settings.clusterMaxDiameter = 0.165
        points.sendActions(for: .touchUpInside)
        diameter.sendActions(for: .touchUpInside)
        let protected = try await ui.waitFor {
            ui.element(label: L10n.Calibration.minimumClusterPoints)?.accessibilityValue == "24" &&
                ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue == "0.145 m"
        }
        XCTAssertTrue(protected)
        XCTAssertEqual(fixture.root.settings.clusterMinPoints, 24)
        XCTAssertEqual(fixture.root.settings.clusterMaxDiameter, 0.165, accuracy: 0.00001)
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).diamMax, 0.145, accuracy: 0.00001,
                       "A settings-only conflict must not save a stale parameter draft")
        let retry = try await ui.changeCalibrationSlider(L10n.Calibration.minimumClusterPoints,
                                                       fraction: 1 / 147, expected: "25")
        retry.sendActions(for: .touchUpInside)
        let applied = try await ui.waitFor { fixture.root.settings.clusterMinPoints == 25 }
        XCTAssertTrue(applied, "A fresh gesture uses the newly accepted settings baseline")
        try await ui.closeCalibration()
        XCTAssertEqual(fixture.root.settings.clusterMinPoints, 25)
        XCTAssertEqual(fixture.root.settings.clusterMaxDiameter, 0.165, accuracy: 0.00001)
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).diamMax, 0.145, accuracy: 0.00001)
        await fixture.verifyStandard()
    }

    @MainActor
    func testCalibrationDiameterPreservesNewerMinimumBeforeClamping() async throws {
        for (newMinimum, expectedMaximum, conflicts) in [(Float(0.142), Float(0.145), true),
                                                       (Float(0.040), Float(0.140), false)] {
            let fixture = try await RootParameterFixture()
            defer { fixture.cleanup() }
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            fixture.mount(on: ui)
            try await ui.openCalibration()
            let diameter = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                              fraction: -1 / 32, expected: "0.140 m")
            fixture.root.parametersStore.updateParam(for: .pear) { $0.diamMin = newMinimum }
            await fixture.root.parametersStore.waitForPendingSave()
            diameter.sendActions(for: .touchUpInside)
            let settled = try await ui.waitFor {
                abs(Double(fixture.root.parametersStore.param(for: .pear).diamMax) - Double(expectedMaximum)) < 0.00001 &&
                    abs(fixture.root.settings.clusterMaxDiameter - Double(expectedMaximum)) < 0.00001 &&
                    ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue ==
                    (conflicts ? "0.145 m" : "0.140 m")
            }
            XCTAssertTrue(settled)
            XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).diamMin, newMinimum, accuracy: 0.00001,
                           "A stale maximum draft must not clamp away a newer minimum")
            XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).diamMax, expectedMaximum, accuracy: 0.00001)
            if conflicts {
                guard settled else { await fixture.verifyStandard(); return }
                let notice = try await ui.waitFor { ui.element(label: L10n.Calibration.parameterConflict) != nil }
                XCTAssertTrue(notice)
                let retry = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                               fraction: 1 / 32, expected: "0.150 m")
                retry.sendActions(for: .touchUpInside)
                let committed = try await ui.waitFor {
                    abs(fixture.root.parametersStore.param(for: .pear).diamMax - 0.150) < 0.00001
                }
                XCTAssertTrue(committed, "A fresh edit uses the newly accepted minimum baseline")
                XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).diamMin, 0.142, accuracy: 0.00001)
            }
            try await ui.closeCalibration()
            await fixture.verifyStandard()
        }
    }

    @MainActor
    func testCalibrationDiameterPreservesNewerSettingsMinimumAndAllowsSafeMerge() async throws {
        for (newMinimum, expectedMaximum, conflicts) in [(0.142, 0.145, true), (0.040, 0.140, false)] {
            let fixture = try await RootParameterFixture()
            defer { fixture.cleanup() }
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            fixture.mount(on: ui)
            try await ui.openCalibration()
            let diameter = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                              fraction: -1 / 32, expected: "0.140 m")
            fixture.root.settings.clusterMinDiameter = newMinimum
            diameter.sendActions(for: .touchUpInside)
            let settled = try await ui.waitFor {
                abs(Double(fixture.root.parametersStore.param(for: .pear).diamMax) - expectedMaximum) < 0.00001 &&
                    abs(fixture.root.settings.clusterMaxDiameter - expectedMaximum) < 0.00001 &&
                    ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue ==
                    (conflicts ? "0.145 m" : "0.140 m")
            }
            XCTAssertTrue(settled)
            XCTAssertEqual(fixture.root.settings.clusterMinDiameter, newMinimum, accuracy: 0.00001)
            XCTAssertEqual(fixture.root.settings.clusterMaxDiameter, expectedMaximum, accuracy: 0.00001)
            XCTAssertEqual(Double(fixture.root.parametersStore.param(for: .pear).diamMax), expectedMaximum, accuracy: 0.00001,
                           "A conflicting settings minimum must be rejected before either max is written")
            if conflicts {
                guard settled else { await fixture.verifyStandard(); return }
                let retry = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                               fraction: 1 / 32, expected: "0.150 m")
                retry.sendActions(for: .touchUpInside)
                let applied = try await ui.waitFor { abs(fixture.root.settings.clusterMaxDiameter - 0.150) < 0.00001 }
                XCTAssertTrue(applied)
                XCTAssertEqual(fixture.root.settings.clusterMinDiameter, 0.142, accuracy: 0.00001)
            }
            try await ui.closeCalibration()
            await fixture.verifyStandard()
        }
    }

    @MainActor
    func testCalibrationDiameterStillClampsMinimumFromItsOwnBaseline() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        fixture.root.parametersStore.updateParam(for: .pear) { $0.diamMin = 0.142 }
        fixture.root.settings.clusterMinDiameter = 0.142
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openCalibration()
        let diameter = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                          fraction: -1 / 32, expected: "0.140 m")
        diameter.sendActions(for: .touchUpInside)
        let applied = try await ui.waitFor { abs(fixture.root.settings.clusterMaxDiameter - 0.140) < 0.00001 }
        XCTAssertTrue(applied)
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).diamMin, 0.140, accuracy: 0.00001)
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).diamMax, 0.140, accuracy: 0.00001)
        XCTAssertEqual(fixture.root.settings.clusterMinDiameter, 0.140, accuracy: 0.00001)
        XCTAssertNil(ui.element(label: L10n.Calibration.parameterConflict))
        try await ui.closeCalibration()
        await fixture.verifyStandard()
    }

    @MainActor
    func testCalibrationPendingConflictOnClosePreservesNewerParameters() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openCalibration()
        _ = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                fraction: 1 / 32, expected: "0.150 m")
        _ = try await ui.changeCalibrationSlider(L10n.Calibration.minimumSphericity,
                                                fraction: 1 / 30, expected: "0.60")
        fixture.root.parametersStore.updateParam(for: .pear) {
            $0.diamMax = 0.165
            $0.sphericityThreshold = 0.64
            $0.averageWeightG = 233
        }
        fixture.root.settings.clusterMaxDiameter = 0.165
        fixture.root.settings.sphericityThreshold = 0.64
        await fixture.root.parametersStore.waitForPendingSave()
        let parameters = fixture.root.parametersStore.parameterSnapshot()
        let bytes = try XCTUnwrap(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey))
        try await ui.closeCalibration()
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(fixture.root.parametersStore.parameterSnapshot(), parameters)
        XCTAssertEqual(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
        XCTAssertEqual(fixture.root.settings.clusterMaxDiameter, 0.165, accuracy: 0.00001)
        XCTAssertEqual(fixture.root.settings.sphericityThreshold, 0.64, accuracy: 0.00001)
        await fixture.verifyStandard()
    }

    @MainActor
    func testCalibrationSameValueResetRejectsPendingGesturesAndAllowsFreshEdits() async throws {
        for resetAll in [false, true] {
            let fixture = try await RootParameterFixture()
            defer { fixture.cleanup() }
            fixture.root.parametersStore.resetToDefault(for: .pear)
            await fixture.root.parametersStore.waitForPendingSave()
            await fixture.root.prepareForScanning()
            let frozen = fixture.plan("ROOT46-FROZEN")
            let frozenContext = try XCTUnwrap(frozen.fruitConfiguration.calibrationContext)
            let original = fixture.root.parametersStore.param(for: .pear)
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            fixture.mount(on: ui)
            try await ui.openCalibration()
            let diameter = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                              fraction: 1 / 32, expected: "0.155 m")
            let sphericity = try await ui.changeCalibrationSlider(L10n.Calibration.minimumSphericity,
                                                                fraction: 1 / 30, expected: "0.32")
            if resetAll { fixture.root.parametersStore.resetAll() }
            else { fixture.root.parametersStore.resetToDefault(for: .pear) }
            await fixture.root.parametersStore.waitForPendingSave()
            let reset = fixture.root.parametersStore.param(for: .pear)
            XCTAssertNotEqual(reset.id, original.id)
            XCTAssertEqual(reset.diamMax, original.diamMax)
            XCTAssertEqual(reset.sphericityThreshold, original.sphericityThreshold)
            let snapshot = fixture.root.parametersStore.parameterSnapshot()
            let bytes = try XCTUnwrap(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey))
            var publications = 0
            let observation = fixture.root.parametersStore.$params.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            diameter.sendActions(for: .touchUpInside)
            sphericity.sendActions(for: .touchUpInside)
            let rejected = try await ui.waitFor {
                self.checkCalibrationResetRebase(ui)
            }
            XCTAssertTrue(rejected, "Same-value reset changes source identity and must reject both old gestures")
            await fixture.root.parametersStore.waitForPendingSave()
            XCTAssertEqual(fixture.root.parametersStore.parameterSnapshot(), snapshot)
            XCTAssertEqual(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
            XCTAssertEqual(publications, 0)
            XCTAssertFalse(fixture.root.parametersStore.hasPendingSave)
            XCTAssertEqual(fixture.root.settings.clusterMaxDiameter, 0.145)
            XCTAssertEqual(fixture.root.settings.sphericityThreshold, 0.58)
            guard rejected else { await fixture.verifyStandard(); continue }
            try await ui.attach(to: self, phase: resetAll ? "46-reset-all-conflict" : "46-reset-category-conflict")
            let freshDiameter = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                                   fraction: 1 / 32, expected: "0.155 m")
            freshDiameter.sendActions(for: .touchUpInside)
            let diameterCommitted = try await ui.waitFor { abs(fixture.root.settings.clusterMaxDiameter - 0.155) < 0.00001 }
            XCTAssertTrue(diameterCommitted)
            let freshSphericity = try await ui.changeCalibrationSlider(L10n.Calibration.minimumSphericity,
                                                                     fraction: 1 / 30, expected: "0.32")
            freshSphericity.sendActions(for: .touchUpInside)
            let sphericityCommitted = try await ui.waitFor { abs(fixture.root.settings.sphericityThreshold - 0.32) < 0.00001 }
            XCTAssertTrue(sphericityCommitted)
            try await ui.closeCalibration()
            await fixture.root.parametersStore.waitForPendingSave()
            let saved = fixture.root.parametersStore.param(for: .pear)
            XCTAssertEqual(saved.diamMax, 0.155, accuracy: 0.000001)
            XCTAssertEqual(saved.sphericityThreshold, 0.32, accuracy: 0.000001)
            var unchanged = saved
            unchanged.diamMax = reset.diamMax
            unchanged.sphericityThreshold = reset.sphericityThreshold
            unchanged.isCustomized = reset.isCustomized
            XCTAssertEqual(unchanged, reset, "Fresh edits retain the reset identity and every unrelated field")
            let persisted = FruitParametersStore(defaults: fixture.defaults)
            XCTAssertEqual(persisted.parameterSnapshot(), fixture.root.parametersStore.parameterSnapshot())
            XCTAssertEqual(frozen.fruitConfiguration.defaultParams, original)
            XCTAssertEqual(frozen.fruitConfiguration.calibrationContext, frozenContext)
            XCTAssertNotEqual(fixture.plan("ROOT46-NEXT").fruitConfiguration.calibrationContext, frozenContext)
            await persisted.waitForPendingSave()
            await fixture.verifyStandard()
        }
    }

    @MainActor
    private func checkCalibrationResetRebase(_ ui: RootLaunchUIHarness) -> Bool {
        ui.element(label: L10n.Calibration.parameterConflict) != nil &&
            ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue == "0.150 m" &&
            ui.element(label: L10n.Calibration.minimumSphericity)?.accessibilityValue == "0.30"
    }

    @MainActor
    func testCalibrationSameValueResetOnCloseRejectsParameterDraftsButCommitsIndependentPoints() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        fixture.root.parametersStore.resetToDefault(for: .pear)
        await fixture.root.parametersStore.waitForPendingSave()
        let original = fixture.root.parametersStore.param(for: .pear)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openCalibration()
        _ = try await ui.changeCalibrationSlider(L10n.Calibration.minimumClusterPoints,
                                                fraction: 1 / 147, expected: "20")
        _ = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                fraction: 1 / 32, expected: "0.155 m")
        _ = try await ui.changeCalibrationSlider(L10n.Calibration.minimumSphericity,
                                                fraction: 1 / 30, expected: "0.32")
        fixture.root.parametersStore.resetAll()
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertNotEqual(fixture.root.parametersStore.param(for: .pear).id, original.id)
        let snapshot = fixture.root.parametersStore.parameterSnapshot()
        let bytes = try XCTUnwrap(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey))
        var publications = 0
        let observation = fixture.root.parametersStore.$params.dropFirst().sink { _ in publications += 1 }
        defer { observation.cancel() }
        try await ui.closeCalibration()
        // 关闭提交挂在 SwiftUI 的 onDisappear 上，而 UIKit 的 dismiss 可以早它一步：
        // presentedViewController 变成 nil 不代表草稿已经提交。这里等**业务完成边界**
        // （与参数重置无关的那份设置草稿真的落地），不是固定等待，也不放宽断言。
        let settingsCommitted = try await ui.waitFor { fixture.root.settings.clusterMinPoints == 20 }
        XCTAssertTrue(settingsCommitted,
                      "the settings-only draft was not committed when the sheet closed")
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(fixture.root.parametersStore.parameterSnapshot(), snapshot)
        XCTAssertEqual(fixture.defaults.data(forKey: FruitParametersStore.userDefaultsKey), bytes)
        XCTAssertEqual(publications, 0)
        XCTAssertFalse(fixture.root.parametersStore.hasPendingSave)
        XCTAssertEqual(fixture.root.settings.clusterMinPoints, 20, "A settings-only draft is independent of parameter resets")
        XCTAssertEqual(fixture.root.settings.clusterMaxDiameter, 0.145)
        XCTAssertEqual(fixture.root.settings.sphericityThreshold, 0.58)
        try await ui.openCalibration()
        XCTAssertEqual(ui.element(label: L10n.Calibration.minimumClusterPoints)?.accessibilityValue, "20")
        XCTAssertEqual(ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue, "0.150 m")
        XCTAssertEqual(ui.element(label: L10n.Calibration.minimumSphericity)?.accessibilityValue, "0.30")
        try await ui.attach(to: self, phase: "46-close-reset-reopened")
        try await ui.closeCalibration()
        XCTAssertEqual(publications, 0)
        await fixture.verifyStandard()
    }

    /// 校准面板在宿主重绘之后，必须仍然保留用户正在编辑的滑杆。
    ///
    /// 工作台是 `@ObservedObject` 的宿主（历史仓库一发布就会重新求值），
    /// 弹层内容随之被重新求值；此时不能把用户刚改的滑杆悄悄丢掉。
    @MainActor
    func testCalibrationDraftSurvivesHostRedraw() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openCalibration()
        _ = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                fraction: 1 / 32, expected: "0.150 m")

        // 强制宿主重绘：历史仓库发布一次，工作台随即重新求值弹层内容。
        fixture.root.historyStore.notifyRecordsUpdated()
        ui.window.layoutIfNeeded()
        let settled = try await ui.waitFor {
            ui.element(label: L10n.Calibration.maximumClusterDiameter) != nil
        }
        XCTAssertTrue(settled, "the calibration screen disappeared after the host redraw")
        XCTAssertEqual(
            ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue, "0.150 m",
            "the diameter draft was discarded by a host redraw"
        )
    }

    @MainActor
    func testCalibrationOtherCategoryResetDoesNotRejectCapturedCategoryDrafts() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        let original = fixture.root.parametersStore.param(for: .pear)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        try await ui.openCalibration()
        _ = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter,
                                                fraction: 1 / 32, expected: "0.150 m")
        _ = try await ui.changeCalibrationSlider(L10n.Calibration.minimumSphericity,
                                                fraction: 1 / 30, expected: "0.60")
        fixture.root.parametersStore.resetToDefault(for: .apple)
        fixture.root.settings.fruitType = "apple"
        await fixture.root.parametersStore.waitForPendingSave()
        let apple = fixture.root.parametersStore.param(for: .apple)
        // 关闭前先确认草稿还在：两个滑杆的读数必须仍是改过的值。
        // 如果中途被丢弃，后面的提交断言就只是在验证一个假象。
        XCTAssertEqual(
            ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue, "0.150 m",
            "the diameter draft was discarded before the sheet closed"
        )
        XCTAssertEqual(
            ui.element(label: L10n.Calibration.minimumSphericity)?.accessibilityValue, "0.60",
            "the sphericity draft was discarded before the sheet closed"
        )
        try await ui.closeCalibration()
        await fixture.root.parametersStore.waitForPendingSave()
        // UIKit 的 dismiss 可能早于 SwiftUI 的 onDisappear 提交：等提交真正落地再断言。
        let committed = try await ui.waitFor {
            abs(fixture.root.parametersStore.param(for: .pear).diamMax - 0.150) < 0.000_01 &&
                abs(fixture.root.settings.clusterMaxDiameter - 0.150) < 0.000_01
        }
        XCTAssertTrue(committed, "the captured pear draft was not committed when the sheet closed")
        let saved = fixture.root.parametersStore.param(for: .pear)
        XCTAssertEqual(saved.diamMax, 0.150, accuracy: 0.000001)
        XCTAssertEqual(saved.sphericityThreshold, 0.60, accuracy: 0.000001)
        var unchanged = saved
        unchanged.diamMax = original.diamMax
        unchanged.sphericityThreshold = original.sphericityThreshold
        XCTAssertEqual(unchanged, original)
        XCTAssertEqual(fixture.root.parametersStore.param(for: .apple), apple)
        XCTAssertEqual(fixture.root.settings.fruitType, "apple")
        XCTAssertEqual(fixture.root.settings.clusterMaxDiameter, 0.150, accuracy: 0.000001)
        XCTAssertEqual(fixture.root.settings.sphericityThreshold, 0.60, accuracy: 0.000001)
        let persisted = FruitParametersStore(defaults: fixture.defaults)
        XCTAssertEqual(persisted.parameterSnapshot(), fixture.root.parametersStore.parameterSnapshot())
        await persisted.waitForPendingSave()
        await fixture.verifyStandard()
    }

    @MainActor
    func testUneditedCalibrationSameValueResetCloseDoesNotWrite() async throws {
        for resetAll in [false, true] {
            let fixture = try await RootParameterFixture()
            defer { fixture.cleanup() }
            fixture.root.parametersStore.resetToDefault(for: .pear)
            await fixture.root.parametersStore.waitForPendingSave()
            let original = fixture.root.parametersStore.param(for: .pear)
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            fixture.mount(on: ui)
            try await ui.openCalibration()
            if resetAll { fixture.root.parametersStore.resetAll() }
            else { fixture.root.parametersStore.resetToDefault(for: .pear) }
            await fixture.root.parametersStore.waitForPendingSave()
            XCTAssertNotEqual(fixture.root.parametersStore.param(for: .pear).id, original.id)
            let snapshot = fixture.root.parametersStore.parameterSnapshot()
            let preferences = fixture.defaults.dictionaryRepresentation()
            var publications = 0
            let observation = fixture.root.parametersStore.$params.dropFirst().sink { _ in publications += 1 }
            defer { observation.cancel() }
            try await ui.closeCalibration()
            await fixture.root.parametersStore.waitForPendingSave()
            XCTAssertEqual(fixture.root.parametersStore.parameterSnapshot(), snapshot)
            XCTAssertTrue(NSDictionary(dictionary: fixture.defaults.dictionaryRepresentation()).isEqual(to: preferences))
            XCTAssertEqual(publications, 0)
            XCTAssertFalse(fixture.root.parametersStore.hasPendingSave)
            await fixture.verifyStandard()
        }
    }

    @MainActor
    func testDashboardCalibrationCommitsRootDraftsAndKeepsTheirCategory() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        await fixture.root.prepareForScanning()
        let frozen = fixture.plan("ROOT43-CALIBRATION")
        let frozenContext = try XCTUnwrap(frozen.fruitConfiguration.calibrationContext)
        let appleBefore = fixture.root.parametersStore.param(for: .apple)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        let started = ProcessInfo.processInfo.systemUptime
        var events: [String] = []
        func record(_ phase: String) {
            events.append("\(ProcessInfo.processInfo.systemUptime - started) \(phase): pear=\(fixture.root.parametersStore.param(for: .pear).sphericityThreshold), settings=\(fixture.root.settings.sphericityThreshold)")
        }
        let publication = fixture.root.parametersStore.$params.dropFirst().sink { params in
            let value = params.first { $0.category == FruitCategory.pear.rawValue }?.sphericityThreshold
            events.append("\(ProcessInfo.processInfo.systemUptime - started) publish pear=\(String(describing: value))")
        }
        defer {
            publication.cancel()
            let evidence = XCTAttachment(string: events.joined(separator: "\n"))
            evidence.name = "Calibration-close-business-commit-boundary"
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        fixture.mount(on: ui)
        try await ui.openCalibration()
        XCTAssertEqual(ui.element(label: L10n.Calibration.minimumClusterPoints)?.accessibilityValue, "19")
        XCTAssertEqual(ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue, "0.145 m")
        XCTAssertEqual(ui.element(label: L10n.Calibration.minimumSphericity)?.accessibilityValue, "0.58")
        let initialHSV = try await ui.waitFor {
            ui.elements.contains { $0.accessibilityLabel?.contains("H: 10° - 44°") == true &&
                $0.accessibilityLabel?.contains("S≥51% V≥61%") == true }
        }
        XCTAssertTrue(initialHSV, "Dashboard calibration HSV must read root settings")
        await fixture.verifyStandard()
        try await ui.attach(to: self, phase: "43-calibration-root")
        let minPoints = try await ui.changeCalibrationSlider(L10n.Calibration.minimumClusterPoints, fraction: 1 / 147, expected: "20")
        XCTAssertEqual(fixture.root.settings.clusterMinPoints, 19, "Dragging retains the draft")
        minPoints.sendActions(for: .touchUpInside)
        let minCommitted = try await ui.waitFor { fixture.root.settings.clusterMinPoints == 20 }
        XCTAssertTrue(minCommitted)
        let diameter = try await ui.changeCalibrationSlider(L10n.Calibration.maximumClusterDiameter, fraction: 1 / 32, expected: "0.150 m")
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).diamMax, 0.145, accuracy: 0.00001)
        diameter.sendActions(for: .touchUpInside)
        let diameterCommitted = try await ui.waitFor {
            abs(fixture.root.settings.clusterMaxDiameter - 0.15) < 0.00001 &&
                abs(fixture.root.parametersStore.param(for: .pear).diamMax - 0.15) < 0.00001
        }
        XCTAssertTrue(diameterCommitted)
        _ = try await ui.changeCalibrationSlider(L10n.Calibration.minimumSphericity, fraction: 1 / 30, expected: "0.60")
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).sphericityThreshold, 0.58, accuracy: 0.00001)
        fixture.root.settings.hsvHMax = 48
        fixture.root.settings.fruitType = "apple"
        let updatedHSV = try await ui.waitFor {
            ui.elements.contains { $0.accessibilityLabel?.contains("H: 10° - 48°") == true }
        }
        XCTAssertTrue(updatedHSV, "Published root HSV changes must update the presented card")
        let liveDrafts = ui.elements.filter { $0.accessibilityLabel == L10n.Calibration.minimumSphericity }
        XCTAssertEqual(liveDrafts.count, 1, "The current sheet must own exactly one sphericity control")
        XCTAssertEqual(liveDrafts.first?.accessibilityValue, "0.60", "The live draft must survive category/HSV updates")
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).sphericityThreshold, 0.58, accuracy: 0.00001)
        record("before close, last slider still editing")
        // Do not send touchUp: this case must prove commit when the real sheet exits.
        try await ui.closeCalibration()
        record("UIKit sheet dismissed")
        let committed = try await ui.waitFor {
            abs(fixture.root.parametersStore.param(for: .pear).sphericityThreshold - 0.60) < 0.00001 &&
                abs(fixture.root.settings.sphericityThreshold - 0.60) < 0.00001
        }
        XCTAssertTrue(committed, "The captured pear draft must commit when the sheet disappears")
        record("business commit observed")
        await fixture.root.parametersStore.waitForPendingSave()
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).sphericityThreshold, 0.60, accuracy: 0.00001)
        XCTAssertEqual(fixture.root.settings.sphericityThreshold, 0.60, accuracy: 0.00001)
        XCTAssertEqual(fixture.root.parametersStore.param(for: .apple), appleBefore,
                       "Changing the next scan category cannot redirect an already-open pear draft")
        let persisted = FruitParametersStore(defaults: fixture.defaults)
        XCTAssertEqual(persisted.param(for: .pear).diamMax, 0.15, accuracy: 0.00001)
        XCTAssertEqual(persisted.param(for: .pear).sphericityThreshold, 0.60, accuracy: 0.00001)
        let next = fixture.plan("ROOT43-CALIBRATION-NEXT")
        XCTAssertEqual(next.fruitConfiguration.clusterConfig.minPoints, 20)
        XCTAssertEqual(next.fruitConfiguration.defaultParams.sphericityThreshold, 0.60, accuracy: 0.00001)
        XCTAssertNotEqual(next.fruitConfiguration.calibrationContext, frozenContext)
        XCTAssertEqual(frozen.fruitConfiguration.defaultParams.diamMax, 0.145, accuracy: 0.00001)
        XCTAssertEqual(frozen.fruitConfiguration.calibrationContext, frozenContext)
        try await ui.openCalibration()
        XCTAssertEqual(ui.element(label: L10n.Calibration.minimumClusterPoints)?.accessibilityValue, "20")
        XCTAssertEqual(ui.element(label: L10n.Calibration.maximumClusterDiameter)?.accessibilityValue, "0.150 m")
        XCTAssertEqual(ui.element(label: L10n.Calibration.minimumSphericity)?.accessibilityValue, "0.50")
        try await ui.attach(to: self, phase: "43-calibration-reopened-apple")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Calibration.close)).accessibilityActivate())
        let closedAgain = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(closedAgain)
        await persisted.waitForPendingSave()
        await fixture.verifyStandard()
    }

    @MainActor
    func testDashboardVarietySaveCancelAndReopenUseOwnedParameters() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        await fixture.root.prepareForScanning()
        let frozen = fixture.plan("ROOT43-VARIETY")
        let frozenContext = try XCTUnwrap(frozen.fruitConfiguration.calibrationContext)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Dashboard.settingsAccessibilityLabel)).accessibilityActivate())
        let ready = try await ui.waitFor { ui.element(label: L10n.Settings.varietyDatabase) != nil }
        XCTAssertTrue(ready)
        let variety = try await ui.scrollToControl(label: L10n.Settings.varietyDatabase)
        XCTAssertTrue(variety.accessibilityActivate())
        let editLabel = L10n.VarietyDatabase.editAccessibility(L10n.Fruit.name(for: .pear))
        func slider(_ label: String) async throws -> UISlider {
            _ = try await ui.scrollToControl(label: label)
            return try XCTUnwrap(ui.elements.compactMap { $0 as? UISlider }.first { $0.accessibilityLabel == label })
        }
        func editPear() async throws {
            let control = try await ui.scrollToControl(label: editLabel)
            XCTAssertTrue(control.accessibilityActivate())
            let editing = try await ui.waitFor {
                ui.elements.contains { $0 is UISlider && $0.accessibilityLabel == L10n.VarietyDatabase.maximumDiameter }
            }
            XCTAssertTrue(editing)
        }
        try await editPear()
        let maximum = try await slider(L10n.VarietyDatabase.maximumDiameter)
        XCTAssertEqual(maximum.accessibilityValue, VarietyParameterFormatter.millimeters(0.145))
        let weight = try await slider(L10n.VarietyDatabase.averageWeight)
        XCTAssertEqual(weight.accessibilityValue, VarietyParameterFormatter.grams(221))
        try await ui.attach(to: self, phase: "43-variety-root")
        weight.value += (weight.maximumValue - weight.minimumValue) / 1999
        weight.sendActions(for: .valueChanged)
        let drafted = try await ui.waitFor { weight.accessibilityValue == VarietyParameterFormatter.grams(222) }
        XCTAssertTrue(drafted)
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).averageWeightG, 221)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.cancel)).accessibilityActivate())
        let cancelled = try await ui.waitFor { ui.element(label: editLabel) != nil }
        XCTAssertTrue(cancelled)
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).averageWeightG, 221)
        try await editPear()
        let savedWeight = try await slider(L10n.VarietyDatabase.averageWeight)
        XCTAssertEqual(savedWeight.accessibilityValue, VarietyParameterFormatter.grams(221))
        savedWeight.value += (savedWeight.maximumValue - savedWeight.minimumValue) / 1999
        savedWeight.sendActions(for: .valueChanged)
        let changed = try await ui.waitFor { savedWeight.accessibilityValue == VarietyParameterFormatter.grams(222) }
        XCTAssertTrue(changed)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.save)).accessibilityActivate())
        let saved = try await ui.waitFor { ui.element(label: editLabel) != nil &&
            fixture.root.parametersStore.param(for: .pear).averageWeightG == 222 }
        XCTAssertTrue(saved)
        await fixture.root.parametersStore.waitForPendingSave()
        let persisted = FruitParametersStore(defaults: fixture.defaults)
        XCTAssertEqual(persisted.param(for: .pear).averageWeightG, 222)
        XCTAssertEqual(fixture.plan("ROOT43-VARIETY-NEXT").fruitConfiguration.defaultParams.averageWeightG, 222)
        XCTAssertEqual(frozen.fruitConfiguration.defaultParams.averageWeightG, 221)
        XCTAssertEqual(frozen.fruitConfiguration.calibrationContext, frozenContext)
        try await editPear()
        let reopenedWeight = try await slider(L10n.VarietyDatabase.averageWeight)
        XCTAssertEqual(reopenedWeight.accessibilityValue, VarietyParameterFormatter.grams(222))
        try await ui.attach(to: self, phase: "43-variety-saved-reopened")
        // Native UIAlertController confirmation is exercised with real touches in
        // FruitTreeScannerUITests/VarietyConfirmationTests on a disposable simulator.
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.cancel)).accessibilityActivate())
        let closedAgain = try await ui.waitFor { ui.element(label: editLabel) != nil }
        XCTAssertTrue(closedAgain)
        XCTAssertEqual(fixture.root.parametersStore.param(for: .pear).averageWeightG, 222)
        XCTAssertEqual(fixture.root.parametersStore.param(for: .apple).averageWeightG, 161)
        await persisted.waitForPendingSave()
        await fixture.verifyStandard()
    }

    @MainActor
    func testRootPlansCaptureAllOwnedParametersAndFreezeCalibrationContext() async throws {
        let fixture = try await RootParameterFixture()
        defer { fixture.cleanup() }
        await fixture.root.prepareForScanning()
        let originalParameters = fixture.root.parametersStore.parameterSnapshot()
        let frozen = fixture.plan("ROOT43-FROZEN")
        XCTAssertEqual(frozen.fruitConfiguration.parametersSnapshot, originalParameters,
                       "The actual root factory must capture every root parameter, including other categories")
        XCTAssertEqual(frozen.fruitConfiguration.defaultParams.diamMax, 0.145, accuracy: 0.00001)
        XCTAssertEqual(frozen.fruitConfiguration.defaultParams.averageWeightG, 221)
        XCTAssertEqual(frozen.fruitConfiguration.clusterConfig.minPoints, 19)
        await fixture.verifyStandard()
        guard frozen.fruitConfiguration.parametersSnapshot == originalParameters else { return }
        let originalContext = try XCTUnwrap(frozen.fruitConfiguration.calibrationContext)
        fixture.root.parametersStore.updateParam(for: .pear) {
            $0.diamMax = 0.155
            $0.averageWeightG = 222
        }
        fixture.root.parametersStore.updateParam(for: .apple) { $0.averageWeightG = 162 }
        let next = fixture.plan("ROOT43-NEXT")
        XCTAssertEqual(next.fruitConfiguration.defaultParams.diamMax, 0.155, accuracy: 0.00001)
        XCTAssertEqual(next.fruitConfiguration.defaultParams.averageWeightG, 222)
        XCTAssertEqual(next.fruitConfiguration.parametersSnapshot["apple"]?.averageWeightG, 162)
        XCTAssertNotEqual(next.fruitConfiguration.calibrationContext, originalContext)
        XCTAssertEqual(frozen.fruitConfiguration.parametersSnapshot, originalParameters)
        XCTAssertEqual(frozen.fruitConfiguration.calibrationContext, originalContext)
        XCTAssertEqual(frozen.fruitConfiguration.clusterConfig.maxDiameter, 0.145, accuracy: 0.00001)
        await fixture.verifyStandard()
    }

    @MainActor
    func testDashboardHistoryFiltersAndReviewUseRootClassification() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        for id in ["HISTORY42-A", "HISTORY42-B"] {
            let source = fixture.directory.appendingPathComponent(id + ".ply")
            try PLYPointCloudWriter.write(points: [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)],
                                          treeID: id, scanDate: "2026-10-04 00:00:00", gpsLat: 0, gpsLon: 0, to: source)
        }
        let originals = try archiveBytes(in: fixture.directory)
        fixture.root.tagStore.createOrUpdateAssignment(treeId: "HISTORY42-A", plotId: fixture.plot.id,
                                                       tagIds: [fixture.tag.id], status: .scanned)
        await fixture.root.tagStore.waitForPendingSave()
        let original = try XCTUnwrap(fixture.root.tagStore.getAssignment(treeId: "HISTORY42-A"))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        let loaded = try await ui.waitFor { !fixture.root.historyStore.isLoading && fixture.root.historyStore.scanFiles.count == 2 }
        XCTAssertTrue(loaded)
        let historyAction = try await ui.scrollToDashboardAction(label: L10n.Dashboard.viewAll)
        XCTAssertTrue(historyAction.accessibilityActivate())
        let listed = try await ui.waitFor { ui.element(label: L10n.History.allPlots) != nil }
        XCTAssertTrue(listed)
        try await ui.attach(to: self, phase: "history42-menu-baseline")
        let (menu, actions) = try await ui.menuActions(label: L10n.History.allPlots)
        guard let rootPlot = actions.first(where: { $0.title == fixture.plot.name }) else {
            menu.dismissMenu()
            try await ui.attach(to: self, phase: "history42-root-plot-missing")
            XCTFail("Actual Dashboard history must offer the root plot before any review write")
            await fixture.verifyStandard()
            return
        }
        UIButton(type: .system).sendAction(rootPlot)
        menu.dismissMenu()
        let filtered = try await ui.waitFor {
            ui.element(label: "HISTORY42-A.ply") != nil && ui.element(label: "HISTORY42-B.ply") == nil
        }
        XCTAssertTrue(filtered)
        try await ui.selectMenu(label: L10n.History.allStatuses, title: L10n.History.statusName(for: .scanned))
        let scanned = try await ui.waitFor { ui.element(label: "HISTORY42-A.ply") != nil }
        XCTAssertTrue(scanned)
        try await ui.attach(to: self, phase: "root-history42-filtered")
        try await ui.selectMenu(label: L10n.History.moreActions, title: L10n.History.markReview)
        let changed = try await ui.waitFor { fixture.root.tagStore.getAssignment(treeId: "HISTORY42-A")?.status == .reviewing }
        XCTAssertTrue(changed)
        let reviewed = try XCTUnwrap(fixture.root.tagStore.getAssignment(treeId: "HISTORY42-A"))
        XCTAssertEqual(reviewed.id, original.id)
        XCTAssertEqual(reviewed.plotId, original.plotId)
        XCTAssertEqual(reviewed.tagIds, original.tagIds)
        let noScanned = try await ui.waitFor { ui.element(label: "HISTORY42-A.ply") == nil }
        XCTAssertTrue(noScanned, "The observed root status must update the active filter")
        try await ui.selectMenu(label: L10n.History.statusName(for: .scanned), title: L10n.History.statusName(for: .reviewing))
        let reviewVisible = try await ui.waitFor { ui.element(label: "HISTORY42-A.ply") != nil }
        XCTAssertTrue(reviewVisible)
        try await ui.attach(to: self, phase: "root-history42-review")
        await fixture.verifyStandard()
        XCTAssertEqual(TagStore(defaults: fixture.defaults).getAssignment(treeId: "HISTORY42-A"), reviewed)
        XCTAssertEqual(try archiveBytes(in: fixture.directory), originals)
    }

    @MainActor
    func testScanResultRestoresAndSavesOnlyRootClassification() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        fixture.root.tagStore.createOrUpdateAssignment(treeId: "RESULT42", plotId: fixture.plot.id,
                                                       tagIds: [fixture.tag.id], status: .reviewing)
        await fixture.root.tagStore.waitForPendingSave()
        let original = try XCTUnwrap(fixture.root.tagStore.getAssignment(treeId: "RESULT42"))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        // Existing readiness injection enables the real ScanView composition; no capture is started.
        ui.mount(ScanView(treeID: "RESULT42", gps: GPSRecorder(), season: .mature,
                          selectedFruitCategory: .pear, appDependencies: fixture.root, onScanNextTree: {},
                          showGuide: false, yieldResult: YieldResult(), showResult: true,
                          readinessRequestController: ScanReadinessRequestController(determine: { .ready })))
        let shown = try await ui.waitFor { ui.element(label: L10n.QuickTagging.title) != nil }
        XCTAssertTrue(shown)
        _ = try await ui.scrollToControl(label: L10n.QuickTagging.plotLabel)
        let restored = try await ui.waitFor {
            ui.element(label: L10n.QuickTagging.plotLabel)?.accessibilityValue == fixture.plot.name &&
                ui.element(label: fixture.tag.name)?.accessibilityValue == L10n.QuickTagging.selectionValue(isSelected: true)
        }
        guard restored else {
            try await ui.attach(to: self, phase: "root-result42-missing")
            XCTFail("Actual ScanView result chain must restore root plot and tag before any save")
            await fixture.verifyStandard()
            return
        }
        XCTAssertEqual(ui.element(label: L10n.QuickTagging.statusName(for: .scanned))?.accessibilityValue,
                       L10n.QuickTagging.selectionValue(isSelected: true), "Reviewing becomes a scanned draft only")
        XCTAssertEqual(fixture.root.tagStore.getAssignment(treeId: "RESULT42"), original)
        try await ui.attach(to: self, phase: "root-result42-restored")
        try await ui.selectMenu(label: L10n.QuickTagging.plotLabel, title: L10n.QuickTagging.noPlot)
        let clearedPlot = try await ui.waitFor {
            ui.element(label: L10n.QuickTagging.plotLabel)?.accessibilityValue == L10n.QuickTagging.plotPlaceholder
        }
        XCTAssertTrue(clearedPlot)
        try await ui.selectMenu(label: L10n.QuickTagging.plotLabel, title: fixture.plot.name)
        let selectedPlot = try await ui.waitFor {
            ui.element(label: L10n.QuickTagging.plotLabel)?.accessibilityValue == fixture.plot.name
        }
        XCTAssertTrue(selectedPlot)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: fixture.tag.name)).accessibilityActivate())
        // An observed store publication must preserve the user's local result draft.
        fixture.root.tagStore.createOrUpdateAssignment(treeId: "RESULT42", plotId: nil,
                                                       tagIds: [fixture.tag.id], status: .completed)
        let draftPreserved = try await ui.waitFor {
            ui.element(label: L10n.QuickTagging.plotLabel)?.accessibilityValue == fixture.plot.name &&
                ui.element(label: fixture.tag.name)?.accessibilityValue == L10n.QuickTagging.selectionValue(isSelected: false)
        }
        XCTAssertTrue(draftPreserved)
        _ = try await ui.scrollToControl(label: L10n.QuickTagging.save)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.QuickTagging.statusName(for: .reviewing))).accessibilityActivate())
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.QuickTagging.save)).accessibilityActivate())
        let saved = try await ui.waitFor {
            ui.element(label: L10n.QuickTagging.saved) != nil &&
                fixture.root.tagStore.getAssignment(treeId: "RESULT42")?.tagIds == []
        }
        XCTAssertTrue(saved)
        let updated = try XCTUnwrap(fixture.root.tagStore.getAssignment(treeId: "RESULT42"))
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.plotId, fixture.plot.id)
        XCTAssertEqual(updated.status, .reviewing)
        try await ui.attach(to: self, phase: "root-result42-saved")
        await fixture.verifyStandard()
        XCTAssertEqual(TagStore(defaults: fixture.defaults).getAssignment(treeId: "RESULT42"), updated)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    @MainActor
    func testDashboardBatchExportGroupsByRootPlotAndPreservesArchive() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let source = fixture.directory.appendingPathComponent("batch42.ply")
        let repository = fixture.root.scanRepository
        let draft = try repository.stagePointCloud(to: source) {
            try PLYPointCloudWriter.write(points: [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)],
                                          treeID: "BATCH42", scanDate: "2026-10-04 00:00:00", gpsLat: 0, gpsLon: 0, to: source)
        }
        var result = YieldResult()
        result.nLidar = 7
        result.yieldFinalKg = 1.25
        _ = try repository.commit(ScanAssessment(draft: draft, exportRequest: ScanResultExportService.ExportRequest(
            treeID: "BATCH42", fruitType: "pear", scanDate: Date(timeIntervalSince1970: 1791060000),
            gpsLat: 0, gpsLon: 0, sourceFilename: source.lastPathComponent, result: result)))
        let originals = try archiveBytes(in: fixture.directory)
        fixture.root.tagStore.createOrUpdateAssignment(treeId: "BATCH42", plotId: fixture.plot.id,
                                                       tagIds: [fixture.tag.id], status: .scanned)
        await fixture.root.tagStore.waitForPendingSave()
        let exportDirectory = BatchExportService.temporaryStorage.sessionDirectory
        let existingExports = Set((try? FileManager.default.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: nil)) ?? [])
        var ownExport: URL?
        defer { if let ownExport { BatchExportService.removeTemporaryExport(at: ownExport) } }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        let loaded = try await ui.waitFor { !fixture.root.historyStore.isLoading && fixture.root.historyStore.scanFiles.count == 1 }
        XCTAssertTrue(loaded)
        try await ui.attach(to: self, phase: "batch42-dashboard-baseline")
        let exportAction = try await ui.scrollToDashboardAction(label: L10n.Dashboard.quickActionAccessibilityLabel(
            title: L10n.Dashboard.batchExportTitle, description: L10n.Dashboard.batchExportDescription))
        XCTAssertTrue(exportAction.accessibilityActivate())
        let shown = try await ui.waitFor { ui.elements.contains { $0 is UISegmentedControl } }
        XCTAssertTrue(shown)
        let grouping = try XCTUnwrap(ui.elements.compactMap { $0 as? UISegmentedControl }.first)
        let index = try XCTUnwrap((0..<grouping.numberOfSegments).first {
            grouping.titleForSegment(at: $0) == L10n.Export.groupingName(.plot)
        })
        grouping.selectedSegmentIndex = index
        grouping.sendActions(for: .valueChanged)
        let grouped = try await ui.waitFor { grouping.accessibilityValue == L10n.Export.groupingName(.plot) }
        XCTAssertTrue(grouped)
        try await ui.attach(to: self, phase: "root-batch42-plot")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Export.primaryExportTitle(recordCount: 1))).accessibilityActivate())
        func hasShareSheet(_ controller: UIViewController) -> Bool {
            if controller is UIActivityViewController { return true }
            if let presented = controller.presentedViewController, hasShareSheet(presented) { return true }
            return controller.children.contains(where: hasShareSheet)
        }
        let exported = try await ui.waitFor {
            // A stream writer creates its unpublished file before flushing it.
            // The real share sheet is presented only after export and source validation finish.
            guard hasShareSheet(ui.controller) else { return false }
            let files = (try? FileManager.default.contentsOfDirectory(at: exportDirectory, includingPropertiesForKeys: nil)) ?? []
            ownExport = files.first { !existingExports.contains($0) }
            return ownExport != nil
        }
        XCTAssertTrue(exported)
        let exportURL = try XCTUnwrap(ownExport)
        let csv = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(csv.split(separator: "\n").contains {
            $0.hasPrefix("\(fixture.plot.name),BATCH42,7,1.25,")
        }, "Actual Dashboard export must retain root grouping, tree, count and yield")
        let exportedData = XCTAttachment(string: csv)
        exportedData.name = "root-batch42-csv"
        exportedData.lifetime = .keepAlways
        add(exportedData)
        XCTAssertEqual(try archiveBytes(in: fixture.directory), originals)
        await fixture.verifyStandard()
    }

    private func archiveBytes(in directory: URL) throws -> [String: Data] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }

    @MainActor
    func testDashboardStartUsesRootClassificationAndActivatesOnce() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        let ready = try await ui.waitFor { ui.element(label: L10n.Dashboard.startScan) != nil }
        XCTAssertTrue(ready)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Dashboard.startScan)).accessibilityActivate())
        try await ui.advanceStart(to: 2, treeID: "ROOT41")
        let plotLabel = "\(fixture.plot.name), \(L10n.StartSetup.text(.plotAssignedSubtitle))"
        let rootPlot = try await ui.waitFor { ui.element(label: plotLabel) != nil }
        try await ui.attach(to: self, phase: "classification-start-plot")
        XCTAssertTrue(rootPlot, "Actual Dashboard Start must read root plots")
        guard rootPlot else { await fixture.verifyStandard(); return }
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.StartSetup.text(.plotAdd))).accessibilityActivate())
        try await ui.appendToClassificationNameAndSave("ROOT41 ADDED PLOT")
        let addedPlot = try await ui.waitFor { fixture.root.tagStore.plots.count == 2 && ui.element(label: plotLabel) != nil }
        XCTAssertTrue(addedPlot)
        XCTAssertEqual(fixture.root.tagStore.plots.last?.name, "ROOT41 ADDED PLOT")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: plotLabel)).accessibilityActivate())
        for step in 2...3 {
            XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.StartFlow.next)).accessibilityActivate())
            let advanced = try await ui.waitFor {
                ui.element(label: L10n.StartFlow.stepCountAccessibility(currentStep: step + 1, totalSteps: 5)) != nil
            }
            XCTAssertTrue(advanced)
        }
        let rootTag = try await ui.waitFor { ui.element(label: fixture.tag.name) != nil }
        XCTAssertTrue(rootTag)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.StartSetup.text(.tagsAdd))).accessibilityActivate())
        try await ui.appendToClassificationNameAndSave("ROOT41 ADDED TAG")
        let addedTag = try await ui.waitFor { fixture.root.tagStore.tags.count == 2 && ui.element(label: fixture.tag.name) != nil }
        XCTAssertTrue(addedTag)
        XCTAssertEqual(fixture.root.tagStore.tags.last?.name, "ROOT41 ADDED TAG")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: fixture.tag.name)).accessibilityActivate())
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.StartFlow.next)).accessibilityActivate())
        let confirmation = try await ui.waitFor { ui.categoryPicker != nil }
        XCTAssertTrue(confirmation)
        try await ui.attach(to: self, phase: "classification-start-confirmed")
        let launch = try XCTUnwrap(ui.element(label: L10n.StartFlow.launch))
        XCTAssertTrue(launch.accessibilityActivate())
        _ = launch.accessibilityActivate()
        let activated = try await ui.waitFor { fixture.root.tagStore.getAssignment(treeId: "ROOT41") != nil }
        XCTAssertTrue(activated)
        let assignment = try XCTUnwrap(fixture.root.tagStore.getAssignment(treeId: "ROOT41"))
        XCTAssertEqual(assignment.plotId, fixture.plot.id)
        XCTAssertEqual(assignment.tagIds, [fixture.tag.id])
        XCTAssertEqual(assignment.status, .notScanned)
        XCTAssertEqual(fixture.root.tagStore.assignments.count, 1)
        try await ui.attach(to: self, phase: "classification-start-activated")
        try await ui.cancelUncapturedScan()
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Dashboard.startScan)).accessibilityActivate())
        try await ui.advanceStart(to: 2, treeID: "REOPEN41")
        XCTAssertEqual(ui.element(label: plotLabel)?.accessibilityValue, L10n.QuickTagging.selectionValue(isSelected: false))
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.StartFlow.cancel)).accessibilityActivate())
        let dismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed)
        XCTAssertEqual(fixture.root.tagStore.assignments.count, 1)
        await fixture.verifyStandard()
        let reloaded = TagStore(defaults: fixture.defaults)
        XCTAssertEqual(reloaded.plots.map(\.name), ["ROOT41 PLOT", "ROOT41 ADDED PLOT"])
        XCTAssertEqual(reloaded.tags.map(\.name), ["ROOT41 TAG", "ROOT41 ADDED TAG"])
        XCTAssertEqual(reloaded.getAssignment(treeId: "ROOT41"), assignment)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    @MainActor
    func testDashboardTagManagementEditsTheRootClassification() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.overrideUserInterfaceStyle = .dark
        fixture.mount(on: ui)
        let ready = try await ui.waitFor { ui.element(label: L10n.Dashboard.startScan) != nil }
        XCTAssertTrue(ready)
        let label = L10n.Dashboard.quickActionAccessibilityLabel(title: L10n.Dashboard.tagManagementTitle,
                                                               description: L10n.Dashboard.tagManagementDescription)
        let action = try await ui.scrollToDashboardAction(label: label)
        XCTAssertTrue(action.accessibilityActivate())
        let rootPlot = try await ui.waitFor { ui.element(label: fixture.plot.name) != nil }
        try await ui.attach(to: self, phase: "classification-management-root")
        XCTAssertTrue(rootPlot, "Actual management route must edit the same root classification as Start")
        guard rootPlot else { await fixture.verifyStandard(); return }
        let tabs = try XCTUnwrap(ui.elements.compactMap { $0 as? UISegmentedControl }.first)
        XCTAssertEqual(tabs.traitCollection.userInterfaceStyle, .light,
                       "System classification controls must use light appearance on the daylight workspace")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: fixture.plot.name)).accessibilityActivate())
        try await ui.appendToClassificationNameAndSave(" EDITED")
        let updated = try await ui.waitFor {
            fixture.root.tagStore.plots.first?.name == "ROOT41 PLOT EDITED" &&
                ui.element(label: "ROOT41 PLOT EDITED") != nil
        }
        XCTAssertTrue(updated)
        XCTAssertEqual(fixture.root.tagStore.plots.first?.id, fixture.plot.id)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.TagManagement.done)).accessibilityActivate())
        let returned = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(returned)
        await fixture.verifyStandard()
        let reloaded = TagStore(defaults: fixture.defaults)
        XCTAssertEqual(reloaded.plots.first?.name, "ROOT41 PLOT EDITED")
        XCTAssertEqual(reloaded.plots.first?.id, fixture.plot.id)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    @MainActor
    func testDashboardQuickScanActivatesOnlyRootAndCancelsWithoutExtraAssignment() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        let ready = try await ui.waitFor { ui.element(label: L10n.Dashboard.quickCapture) != nil }
        XCTAssertTrue(ready)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Dashboard.quickCapture)).accessibilityActivate())
        let presented = try await ui.waitFor { ui.categoryPicker != nil }
        XCTAssertTrue(presented)
        let launch = try XCTUnwrap(ui.element(label: L10n.QuickScan.launch))
        XCTAssertTrue(launch.accessibilityActivate())
        _ = launch.accessibilityActivate()
        let activated = try await ui.waitFor { fixture.root.tagStore.assignments.count == 1 }
        XCTAssertTrue(activated)
        let assignment = try XCTUnwrap(fixture.root.tagStore.assignments.first)
        XCTAssertTrue(assignment.treeId.hasPrefix("Q"))
        XCTAssertNil(assignment.plotId)
        XCTAssertTrue(assignment.tagIds.isEmpty)
        XCTAssertEqual(assignment.status, .notScanned)
        try await ui.attach(to: self, phase: "classification-quick-activated")
        try await ui.cancelUncapturedScan()
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Dashboard.quickCapture)).accessibilityActivate())
        let reopened = try await ui.waitFor { ui.categoryPicker != nil }
        XCTAssertTrue(reopened)
        XCTAssertEqual(ui.categoryPicker?.accessibilityValue, L10n.FruitCategoryVerification.selectionAccessibilityValue(.pear))
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.QuickScan.close)).accessibilityActivate())
        let dismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed)
        XCTAssertEqual(fixture.root.tagStore.assignments.count, 1)
        await fixture.verifyStandard()
        XCTAssertEqual(TagStore(defaults: fixture.defaults).getAssignment(treeId: assignment.treeId), assignment)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    @MainActor
    func testDashboardHistoryRescanKeepsRootAssignmentAndOriginalArchive() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let source = fixture.directory.appendingPathComponent("rescan41.ply")
        try PLYPointCloudWriter.write(points: [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)],
                                      treeID: "RESCAN41", scanDate: "2026-10-03 00:00:00", gpsLat: 0, gpsLon: 0, to: source)
        let bytes = try Data(contentsOf: source)
        fixture.root.tagStore.createOrUpdateAssignment(treeId: "RESCAN41", plotId: fixture.plot.id,
                                                       tagIds: [fixture.tag.id], status: .reviewing)
        await fixture.root.tagStore.waitForPendingSave()
        let original = try XCTUnwrap(fixture.root.tagStore.getAssignment(treeId: "RESCAN41"))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        fixture.mount(on: ui)
        let loaded = try await ui.waitFor { !fixture.root.historyStore.isLoading && fixture.root.historyStore.scanFiles.count == 1 }
        XCTAssertTrue(loaded)
        let history = try await ui.scrollToDashboardAction(label: L10n.Dashboard.viewAll)
        XCTAssertTrue(history.accessibilityActivate())
        // 复扫收敛到行尾的「更多」菜单（行本身是打开归档的入口）。
        let listed = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(listed)
        try await ui.attach(to: self, phase: "classification-rescan-listed")
        try await ui.selectMenu(label: L10n.History.moreActions, title: L10n.History.rescanTree)
        let activated = try await ui.waitFor { ui.element(label: L10n.ScanReadiness.back) != nil }
        XCTAssertTrue(activated)
        XCTAssertEqual(fixture.root.tagStore.getAssignment(treeId: "RESCAN41"), original,
                       "Actual history rescan must preserve root plot/tag/status/assignment identity")
        try await ui.attach(to: self, phase: "classification-rescan-activated")
        try await ui.cancelUncapturedScan()
        await fixture.verifyStandard()
        XCTAssertEqual(TagStore(defaults: fixture.defaults).getAssignment(treeId: "RESCAN41"), original)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path), ["rescan41.ply"])
    }

    // MARK: - 果园地图里的档案：复扫必须带着树身份

    /// 回归（P1）：**果园地图**里打开的档案，「复扫这棵」必须**带着这棵树**进入扫描。
    ///
    /// 地图这一屏以前没把「按树复扫」的能力透传下去，
    /// 行尾菜单的「复扫这棵」于是退化成「新建扫描」：树号、地块、标签全丢 ——
    /// 用户以为在补扫这棵树，实际拿到的是一个没有身份的新扫描。
    ///
    /// 真实链路：真实 Dashboard → 展开地图 → 档案 → 行尾菜单 → 复扫这棵 → 真实扫描界面。
    /// 夹具放**两棵不同的树**加一条没坐标的记录：断言必须落在被点的那一棵上，
    /// 别的记录顶替不得。
    @MainActor
    func testDashboardMapArchiveRescanKeepsTheTreeIdentity() async throws {
        let fixture = try await MapArchiveFixture.make(rescanTree: "MAP-RESCAN-41",
                                                      otherTree: "MAP-OTHER-41",
                                                      unlocatedTree: "MAP-NOGPS-41")
        defer { fixture.classification.cleanup() }
        let root = fixture.dependencies
        let classification = fixture.classification
        let rescanBytes = try Data(contentsOf: fixture.rescan)
        let otherBytes = try Data(contentsOf: fixture.other)
        let originalFiles = try fixture.fileBytes()
        root.tagStore.createOrUpdateAssignment(treeId: "MAP-RESCAN-41", plotId: classification.plot.id,
                                                tagIds: [classification.tag.id], status: .reviewing)
        await root.tagStore.waitForPendingSave()
        let original = try XCTUnwrap(root.tagStore.getAssignment(treeId: "MAP-RESCAN-41"))

        // 根与档案的分类**故意不同**（档案 apple / 根 pear）：
        // 复扫必须用**根**的分类，不能顺手沿用档案里的旧分类。
        // 这里是 helper 证据（`rescanRequest` 的既有语义），
        // 原生界面证据是下面 `scan.session.<树号>` 那条。
        let request = try XCTUnwrap(root.rescanRequest(treeID: "MAP-RESCAN-41"))
        XCTAssertEqual(request.selectedFruitCategory, .pear)
        XCTAssertEqual(request.season, .mature)
        XCTAssertEqual(request.plotId, classification.plot.id)
        XCTAssertEqual(request.tagIds, [classification.tag.id])

        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        classification.mount(on: ui)
        let loaded = try await ui.waitFor {
            !root.historyStore.isLoading && root.historyStore.scanFiles.count == 3
        }
        XCTAssertTrue(loaded)
        let archived = try XCTUnwrap(root.historyStore.scanFiles.first { $0.treeID == "MAP-RESCAN-41" })
        XCTAssertEqual(archived.fruitType, "apple", "夹具必须让档案分类与根分类不同")

        // 首页 → 果园地图
        let map = try await ui.scrollToDashboardAction(label: WorkspaceText.openMap)
        XCTAssertTrue(map.accessibilityActivate())
        let mapReady = try await ui.waitFor { ui.element(identifier: "orchard.map.openArchive") != nil }
        XCTAssertTrue(mapReady, "果园地图必须真的呈现出来")

        // 果园地图 → 档案（地图里的**嵌套**弹层）
        XCTAssertTrue(try XCTUnwrap(ui.element(identifier: "orchard.map.openArchive")).accessibilityActivate())
        let archiveReady = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(archiveReady, "地图里的档案必须真的呈现出来")

        // 档案行 → 行尾菜单 → 「复扫这棵」。
        // 入口按**纵向归属**挑中：这一行的标题矩形必须夹住那个「更多操作」。
        let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.refreshControl != nil })
        let row = try await ui.reveal(fixture.rescan.lastPathComponent, in: scroll)
        let rowFrame = row.accessibilityFrame
        let more = try XCTUnwrap(
            ui.elements.filter { $0.accessibilityLabel == L10n.History.moreActions }
                .first { $0.accessibilityFrame.midY >= rowFrame.minY && $0.accessibilityFrame.midY <= rowFrame.maxY },
            "复扫入口必须属于被点的那一行"
        )
        let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: nil)
            .intersection(ui.window.convert(ui.window.bounds, to: nil))
        XCTAssertTrue(viewport.insetBy(dx: -0.5, dy: -0.5).contains(more.accessibilityFrame))
        try await ui.attach(to: self, phase: "map-archive-row-rescan-visible")
        XCTAssertTrue(more.accessibilityActivate())
        let (_, actions) = try await ui.visibleMenuActions()
        let rescan = try XCTUnwrap(actions.first { $0.title == L10n.History.rescanTree })
        UIButton(type: .system).sendAction(rescan)

        // 复扫必须直接进入**这棵树**的扫描，而不是退回「新建扫描」再让用户重填树号。
        let activated = try await ui.waitFor { ui.element(label: L10n.ScanReadiness.back) != nil }
        XCTAssertTrue(activated, "复扫必须直接进入扫描（当前 AX 标签：\(ui.accessibilityLabels())）")
        XCTAssertNil(ui.element(label: L10n.StartFlow.navigationTitle),
                     "复扫不能退回「新建扫描」：那会把树的身份整个丢掉")
        let identity = try await ui.waitFor {
            ui.element(identifier: "scan.session.MAP-RESCAN-41") != nil
        }
        XCTAssertTrue(identity, "复扫必须带着被点的那棵树进入扫描（当前 AX 标识：\(ui.accessibilityIdentifiers())）")
        XCTAssertNil(ui.element(identifier: "scan.session.MAP-OTHER-41"), "不能把另一棵树带进扫描")
        try await ui.attach(to: self, phase: "map-archive-row-selected-scan")

        // 取消这次扫描，回到首页 —— **之后**才核对原件与身份：
        // 取消之前核对，证明不了取消没有留下任何副作用。
        try await ui.cancelUncapturedScan()
        XCTAssertEqual(root.tagStore.getAssignment(treeId: "MAP-RESCAN-41"), original,
                       "地图里的复扫必须保留地块/标签/状态/身份")
        XCTAssertNil(root.tagStore.getAssignment(treeId: "MAP-OTHER-41"),
                     "复扫不得给另一棵树写身份")
        XCTAssertEqual(root.tagStore.assignments.count, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.rescan), rescanBytes)
        XCTAssertEqual(try Data(contentsOf: fixture.other), otherBytes)
        XCTAssertEqual(try fixture.fileBytes(), originalFiles, "取消复扫后所有原始点云及结果文件必须逐字节保持")
        await classification.verifyStandard()
        XCTAssertEqual(TagStore(defaults: classification.defaults).getAssignment(treeId: "MAP-RESCAN-41"), original)

        // 重新打开地图与档案：不能有迟到的、重复的扫描。
        let mapAgain = try await ui.scrollToDashboardAction(label: WorkspaceText.openMap)
        XCTAssertTrue(mapAgain.accessibilityActivate())
        let mapAgainReady = try await ui.waitFor { ui.element(identifier: "orchard.map.openArchive") != nil }
        XCTAssertTrue(mapAgainReady)
        XCTAssertTrue(try XCTUnwrap(ui.element(identifier: "orchard.map.openArchive")).accessibilityActivate())
        let archiveAgain = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(archiveAgain, "取消之后档案必须还能重新打开")
        XCTAssertNil(ui.element(label: L10n.ScanReadiness.back), "取消之后不得有迟到的扫描")
        XCTAssertNil(ui.element(identifier: "scan.session.MAP-RESCAN-41"))
        XCTAssertNil(ui.element(identifier: "scan.session.MAP-OTHER-41"))
        try await ui.attach(to: self, phase: "map-archive-row-reopened-after-cancel")
    }

    /// 回归（P1）：地图 → 档案 → **详情页**的「重新扫描」必须存在，并且指向选中的那棵树。
    ///
    /// 同一屏里行尾菜单写着「复扫这棵」，详情页却连入口都没有 ——
    /// 两个入口对同一件事给出两种答案，其中一个还悄悄走偏。
    @MainActor
    func testDashboardMapArchiveDetailOffersRescanForTheSelectedTree() async throws {
        let fixture = try await MapArchiveFixture.make(rescanTree: "MAP-DETAIL-41",
                                                      otherTree: "MAP-DETAIL-OTHER-41",
                                                      unlocatedTree: "MAP-DETAIL-NOGPS-41")
        defer { fixture.classification.cleanup() }
        let root = fixture.dependencies
        let classification = fixture.classification
        let rescanBytes = try Data(contentsOf: fixture.rescan)
        let originalFiles = try fixture.fileBytes()
        root.tagStore.createOrUpdateAssignment(treeId: "MAP-DETAIL-41", plotId: classification.plot.id,
                                                tagIds: [classification.tag.id], status: .reviewing)
        await root.tagStore.waitForPendingSave()
        let original = try XCTUnwrap(root.tagStore.getAssignment(treeId: "MAP-DETAIL-41"))

        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        classification.mount(on: ui)
        let loaded = try await ui.waitFor {
            !root.historyStore.isLoading && root.historyStore.scanFiles.count == 3
        }
        XCTAssertTrue(loaded)
        let map = try await ui.scrollToDashboardAction(label: WorkspaceText.openMap)
        XCTAssertTrue(map.accessibilityActivate())
        let mapReady = try await ui.waitFor { ui.element(identifier: "orchard.map.openArchive") != nil }
        XCTAssertTrue(mapReady)
        XCTAssertTrue(try XCTUnwrap(ui.element(identifier: "orchard.map.openArchive")).accessibilityActivate())
        let archiveReady = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(archiveReady)

        // 打开被点的那一条 → 归档详情
        let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.refreshControl != nil })
        let row = try await ui.reveal(fixture.rescan.lastPathComponent, in: scroll)
        XCTAssertTrue(row.accessibilityActivate())
        let detailReady = try await ui.waitFor { ui.element(identifier: "archiveDetail.sharePointCloud") != nil }
        XCTAssertTrue(detailReady, "归档详情必须真的打开")

        // 详情页必须提供「重新扫描」，并且指向选中的那棵树。
        let rescanButton = try await ui.waitFor { ui.element(identifier: "archiveDetail.rescanTree") != nil }
        XCTAssertTrue(rescanButton, "地图里的归档详情必须提供「重新扫描」出口")
        let detailScroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first {
            $0.refreshControl == nil && $0.bounds.width > 200 && $0.bounds.height > 200
        })
        let rescanLabel = try XCTUnwrap(ui.element(identifier: "archiveDetail.rescanTree")?.accessibilityLabel)
        let visibleRescan = try await ui.reveal(rescanLabel, in: detailScroll)
        let viewport = detailScroll.convert(detailScroll.bounds.inset(by: detailScroll.adjustedContentInset), to: nil)
            .intersection(ui.window.convert(ui.window.bounds, to: nil))
        XCTAssertTrue(viewport.insetBy(dx: -0.5, dy: -0.5).contains(visibleRescan.accessibilityFrame))
        try await ui.attach(to: self, phase: "map-archive-detail-rescan-visible")
        XCTAssertTrue(visibleRescan.accessibilityActivate())

        let activated = try await ui.waitFor { ui.element(label: L10n.ScanReadiness.back) != nil }
        XCTAssertTrue(activated, "详情页的重新扫描必须直接进入扫描（当前 AX 标签：\(ui.accessibilityLabels())）")
        let identity = try await ui.waitFor {
            ui.element(identifier: "scan.session.MAP-DETAIL-41") != nil
        }
        XCTAssertTrue(identity, "详情页的重新扫描必须带着选中的那棵树（当前 AX 标识：\(ui.accessibilityIdentifiers())）")
        XCTAssertNil(ui.element(identifier: "scan.session.MAP-DETAIL-OTHER-41"))
        try await ui.attach(to: self, phase: "map-archive-detail-selected-scan")

        try await ui.cancelUncapturedScan()
        XCTAssertEqual(root.tagStore.getAssignment(treeId: "MAP-DETAIL-41"), original)
        XCTAssertNil(root.tagStore.getAssignment(treeId: "MAP-DETAIL-OTHER-41"))
        XCTAssertEqual(root.tagStore.assignments.count, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.rescan), rescanBytes)
        XCTAssertEqual(try fixture.fileBytes(), originalFiles, "详情复扫取消后不能改变任何原始档案字节")
        await classification.verifyStandard()
        XCTAssertNil(ui.element(label: L10n.ScanReadiness.back), "取消之后不得有迟到的扫描")
    }

    /// 回归：地图里的档案必须把**被点的那一行**的树号交给复扫回调。
    ///
    /// 端到端那两条证明的是「扫描真的带着这棵树起来了」；
    /// 这条把边界钉死在回调上：交出去的必须是**被点的那一行**，
    /// 档案里另外两条记录（另一棵树、没有坐标的那条）都顶替不得。
    @MainActor
    @available(iOS 17, *)
    func testMapArchiveForwardsTheTappedTreeToRescan() async throws {
        let now = Date()
        let target = ScanFileRecord(id: "target.ply", treeID: "MAP-FWD-TARGET",
                                    fileURL: URL(fileURLWithPath: "/tmp/maptarget.ply"),
                                    scanDate: now, gpsLat: 30.11, gpsLon: 120.11)
        let other = ScanFileRecord(id: "other.ply", treeID: "MAP-FWD-OTHER",
                                   fileURL: URL(fileURLWithPath: "/tmp/mapother.ply"),
                                   scanDate: now.addingTimeInterval(-60), gpsLat: 30.22, gpsLon: 120.22)
        let unlocated = ScanFileRecord(id: "nogps.ply", treeID: "MAP-FWD-NOGPS",
                                       fileURL: URL(fileURLWithPath: "/tmp/mapnogps.ply"),
                                       scanDate: now.addingTimeInterval(-120))
        let store = ScanHistoryStore(recordsLoader: { .success([target, other, unlocated]) })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        var rescans: [String] = []
        ui.mount(OrchardMapView(onRescanTree: { rescans.append($0) }, historyStore: store))
        let ready = try await ui.waitFor { ui.element(identifier: "orchard.map.openArchive") != nil }
        XCTAssertTrue(ready, "果园地图必须给出打开档案的入口")
        XCTAssertTrue(try XCTUnwrap(ui.element(identifier: "orchard.map.openArchive")).accessibilityActivate())
        let archiveReady = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(archiveReady, "地图里的档案必须真的呈现出来")

        let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.refreshControl != nil })
        let row = try await ui.reveal(target.fileURL.lastPathComponent, in: scroll)
        let rowFrame = row.accessibilityFrame
        let more = try XCTUnwrap(
            ui.elements.filter { $0.accessibilityLabel == L10n.History.moreActions }
                .first { $0.accessibilityFrame.midY >= rowFrame.minY && $0.accessibilityFrame.midY <= rowFrame.maxY },
            "复扫入口必须属于被点的那一行"
        )
        XCTAssertTrue(more.accessibilityActivate())
        let (_, actions) = try await ui.visibleMenuActions()
        let rescan = try XCTUnwrap(actions.first { $0.title == L10n.History.rescanTree })
        UIButton(type: .system).sendAction(rescan)
        let fired = try await ui.waitFor { !rescans.isEmpty }
        XCTAssertTrue(fired, "复扫必须真的派发出去")
        XCTAssertEqual(rescans, [target.treeID], "复扫必须带上被点的那一行的树号")
        XCTAssertEqual(store.scanFiles.count, 3, "复扫不得动档案里的任何一条记录")
    }

    /// 回归：同一个菜单动作被**派发两次**（真实的 UIAction 对象）只能交接一次。
    ///
    /// 两次就是两次扫描 —— 用户按一次菜单，App 起两次相机。
    /// 迟到的旧动作（档案已经关过又重新打开）同样不能再来一次。
    @MainActor
    @available(iOS 17, *)
    func testMapArchiveRescanDeliveredTwiceHandsOffOnlyOnce() async throws {
        let now = Date()
        let target = ScanFileRecord(id: "target.ply", treeID: "MAP-REPEAT-TARGET",
                                    fileURL: URL(fileURLWithPath: "/tmp/maptarget.ply"),
                                    scanDate: now, gpsLat: 30.11, gpsLon: 120.11)
        let unlocated = ScanFileRecord(id: "nogps.ply", treeID: "MAP-REPEAT-NOGPS",
                                       fileURL: URL(fileURLWithPath: "/tmp/mapnogps.ply"),
                                       scanDate: now.addingTimeInterval(-60))
        let store = ScanHistoryStore(recordsLoader: { .success([target, unlocated]) })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        var rescans: [String] = []
        ui.mount(OrchardMapView(onRescanTree: { rescans.append($0) }, historyStore: store))
        let ready = try await ui.waitFor { ui.element(identifier: "orchard.map.openArchive") != nil }
        XCTAssertTrue(ready)
        XCTAssertTrue(try XCTUnwrap(ui.element(identifier: "orchard.map.openArchive")).accessibilityActivate())
        let archiveReady = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(archiveReady)
        let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.refreshControl != nil })
        let row = try await ui.reveal(target.fileURL.lastPathComponent, in: scroll)
        let rowFrame = row.accessibilityFrame
        let more = try XCTUnwrap(
            ui.elements.filter { $0.accessibilityLabel == L10n.History.moreActions }
                .first { $0.accessibilityFrame.midY >= rowFrame.minY && $0.accessibilityFrame.midY <= rowFrame.maxY },
            "复扫入口必须属于被点的那一行"
        )
        XCTAssertTrue(more.accessibilityActivate())
        let (_, actions) = try await ui.visibleMenuActions()
        let rescan = try XCTUnwrap(actions.first { $0.title == L10n.History.rescanTree })
        // 同一个动作派发两次。
        UIButton(type: .system).sendAction(rescan)
        UIButton(type: .system).sendAction(rescan)
        let fired = try await ui.waitFor { !rescans.isEmpty }
        XCTAssertTrue(fired)
        let dismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed, "档案弹层必须真的关掉")
        XCTAssertEqual(rescans, [target.treeID], "重复派发只能交接一次")

        // 档案重新打开之后，上一次那个动作再来一次：
        // 它属于**已经关掉的**呈现 —— 新打开的档案必须原样留着，回调次数不得增加。
        // （不是「把它关掉」：忽略一个过期动作不等于替它做决定。）
        XCTAssertTrue(try XCTUnwrap(ui.element(identifier: "orchard.map.openArchive")).accessibilityActivate())
        let reopened = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(reopened, "档案必须能重新打开")
        UIButton(type: .system).sendAction(rescan)
        let forwardedAgain = try await ui.waitFor { rescans.count > 1 }
        XCTAssertFalse(forwardedAgain, "已经关掉的呈现留下的动作不能再交接一次")
        XCTAssertEqual(rescans, [target.treeID], "过期动作不得改变回调次数")
        let stillOpen = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(stillOpen, "过期动作不得把新打开的档案关掉")

        // 新档案里的**当前**动作必须照常工作：恰好再交接一次。
        let scrollAgain = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.refreshControl != nil })
        let rowAgain = try await ui.reveal(target.fileURL.lastPathComponent, in: scrollAgain)
        let rowFrameAgain = rowAgain.accessibilityFrame
        let moreAgain = try XCTUnwrap(
            ui.elements.filter { $0.accessibilityLabel == L10n.History.moreActions }
                .first { $0.accessibilityFrame.midY >= rowFrameAgain.minY && $0.accessibilityFrame.midY <= rowFrameAgain.maxY },
            "复扫入口必须属于被点的那一行"
        )
        XCTAssertTrue(moreAgain.accessibilityActivate())
        let (_, currentActions) = try await ui.visibleMenuActions()
        let currentRescan = try XCTUnwrap(currentActions.first { $0.title == L10n.History.rescanTree })
        UIButton(type: .system).sendAction(currentRescan)
        let firedAgain = try await ui.waitFor { rescans.count == 2 }
        XCTAssertTrue(firedAgain, "新档案里的当前动作必须照常交接一次")
        XCTAssertEqual(rescans, [target.treeID, target.treeID])
    }

    /// 回归：**没有**「按树复扫」这个能力时，那就没有这个能力。
    ///
    /// 不能拿一个恒真的包装去冒充：否则详情页会多出一个点不动的「重新扫描」，
    /// 行尾菜单的「复扫这棵」也会丢掉「新建扫描」这个既有兜底。
    @MainActor
    @available(iOS 17, *)
    func testMapArchiveWithoutRescanCapabilityKeepsTheNewScanFallback() async throws {
        let fixture = try await MapArchiveFixture.make(
            rescanTree: "MAP-NOCAP-41", otherTree: "MAP-NOCAP-OTHER", unlocatedTree: "MAP-NOCAP-NOGPS"
        )
        defer { fixture.classification.cleanup() }
        let originalFiles = try fixture.fileBytes()
        let store = fixture.dependencies.historyStore
        await store.reloadRecords()
        let record = try XCTUnwrap(store.scanFiles.first { $0.fileURL == fixture.rescan })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        var starts = 0
        ui.mount(OrchardMapView(onStartScan: { starts += 1 }, historyStore: store))
        let ready = try await ui.waitFor { ui.element(identifier: "orchard.map.openArchive") != nil }
        XCTAssertTrue(ready)
        XCTAssertTrue(try XCTUnwrap(ui.element(identifier: "orchard.map.openArchive")).accessibilityActivate())
        let archiveReady = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(archiveReady)
        let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.refreshControl != nil })
        let more = try await ui.reveal(L10n.History.moreActions, in: scroll)
        XCTAssertTrue(more.accessibilityActivate())
        let (_, actions) = try await ui.visibleMenuActions()
        let rescan = try XCTUnwrap(actions.first { $0.title == L10n.History.rescanTree })
        UIButton(type: .system).sendAction(rescan)
        let handedOff = try await ui.waitFor { starts == 1 }
        XCTAssertTrue(handedOff, "没有按树复扫这个能力时，「复扫这棵」必须退回新建扫描，不能点了没反应")
        let dismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed)

        // 详情页不得出现点不动的「重新扫描」。
        XCTAssertTrue(try XCTUnwrap(ui.element(identifier: "orchard.map.openArchive")).accessibilityActivate())
        let reopened = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(reopened)
        let reopenedScroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.refreshControl != nil })
        let row = try await ui.reveal(record.fileURL.lastPathComponent, in: reopenedScroll)
        XCTAssertTrue(row.accessibilityActivate())
        let detailReady = try await ui.waitFor { ui.element(identifier: "archiveDetail.sharePointCloud") != nil }
        XCTAssertTrue(detailReady)
        XCTAssertNil(ui.element(identifier: "archiveDetail.rescanTree"),
                     "没有这个能力时详情页不能给出一个点不动的入口")
        XCTAssertEqual(try fixture.fileBytes(), originalFiles)
        await fixture.classification.verifyStandard()
    }

    @MainActor
    func testRootRescanRequestFreezesRootCategoryAndClassification() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        fixture.root.settings.maxPointCount = 1_400_000
        fixture.root.tagStore.createOrUpdateAssignment(treeId: "RESCAN41", plotId: fixture.plot.id,
                                                       tagIds: [fixture.tag.id], status: .completed)
        let request = try XCTUnwrap(fixture.root.rescanRequest(treeID: " RESCAN41 "))
        XCTAssertEqual(request.treeID, "RESCAN41")
        XCTAssertEqual(request.selectedFruitCategory, .pear)
        XCTAssertEqual(request.plotId, fixture.plot.id)
        XCTAssertEqual(request.tagIds, [fixture.tag.id])
        XCTAssertEqual(request.season, .mature)
        let frozen = fixture.root.scanPlanFactory.makePlan(treeID: request.treeID, season: request.season,
                                                          selectedCategory: request.selectedFruitCategory, renderer: nil)
        fixture.root.settings.fruitType = "orange"
        fixture.root.settings.maxPointCount = 100_000
        fixture.root.tagStore.deletePlot(id: fixture.plot.id)
        fixture.root.tagStore.deleteTag(id: fixture.tag.id)
        XCTAssertEqual(request.selectedFruitCategory, .pear)
        XCTAssertEqual(request.plotId, fixture.plot.id)
        XCTAssertEqual(request.tagIds, [fixture.tag.id])
        XCTAssertEqual(frozen.fruitConfiguration.selectedCategory, .pear)
        XCTAssertEqual(frozen.rendererSettings.maxPoints, 1_400_000)
        let next = try XCTUnwrap(fixture.root.rescanRequest(treeID: "RESCAN41"))
        XCTAssertEqual(next.selectedFruitCategory, .orange)
        XCTAssertNil(next.plotId)
        XCTAssertTrue(next.tagIds.isEmpty)
        XCTAssertNotEqual(next.id, request.id)
        XCTAssertFalse(next.gps === request.gps)
        let unassigned = try XCTUnwrap(fixture.root.rescanRequest(treeID: "NEW41"))
        XCTAssertNil(unassigned.plotId)
        XCTAssertTrue(unassigned.tagIds.isEmpty)
        for invalid in ["", " ../bad ", "bad\nname"] {
            XCTAssertNil(fixture.root.rescanRequest(treeID: invalid))
        }
        XCTAssertEqual(fixture.root.tagStore.getAssignment(treeId: "RESCAN41")?.status, .completed)
        XCTAssertEqual(fixture.root.tagStore.assignments.count, 1, "Request construction must not create assignments")
        await fixture.verifyStandard()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path).isEmpty)
    }

    @MainActor
    func testLaunchControlsWriteRootOnceAndFreezeRequest() async throws {
        await FruitParametersStore.shared.waitForPendingSave()
        await TagStore.shared.waitForPendingSave()
        let protectedKeys = [SettingsStoreKey.fruitType, FruitParametersStore.userDefaultsKey,
                             TagStore.snapshotUserDefaultsKey, "TagStore.plots", "TagStore.tags", "TagStore.assignments"]
        let shared = UserDefaults.standard.dictionaryRepresentation().filter { protectedKeys.contains($0.key) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "RootLaunchControls-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let root = AppDependencies(settings: settings, scanRepository: ScanRepository(scansDirectory: directory))
        for quick in [true, false] {
            settings.fruitType = "pear"
            settings.maxPointCount = 1_400_000
            let frozen = root.scanPlanFactory.makePlan(treeID: "FROZEN40", season: .mature,
                                                      selectedCategory: .pear, renderer: nil)
            var delivered: [ScanLaunchRequest] = []
            let receive: (ScanLaunchRequest) -> Void = { delivered.append($0) }
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            if quick { ui.mount(QuickScanView(settings: settings, onLaunchScan: receive)) }
            else {
                ui.mount(StartView(settings: settings, onLaunchScan: receive))
                try await ui.advanceStartToConfirmation()
            }
            let ready = try await ui.waitFor { ui.categoryPicker != nil }
            XCTAssertTrue(ready)
            XCTAssertEqual(ui.categoryPicker?.accessibilityValue,
                           L10n.FruitCategoryVerification.selectionAccessibilityValue(.pear))
            try await ui.selectCategory(.grape)
            XCTAssertEqual(settings.fruitType, "pear", "Selecting a draft must not write root before submission")
            settings.fruitType = "strawberry"
            XCTAssertEqual(ui.categoryPicker?.accessibilityValue,
                           L10n.FruitCategoryVerification.selectionAccessibilityValue(.grape))
            try await ui.attach(to: self, phase: "controls-\(quick ? "quick" : "start")-selected")
            let launch = try XCTUnwrap(ui.element(label: quick ? L10n.QuickScan.launch : L10n.StartFlow.launch))
            XCTAssertTrue(launch.accessibilityActivate())
            _ = launch.accessibilityActivate()
            let submitted = try await ui.waitFor { delivered.count == 1 && settings.fruitType == "grape" }
            XCTAssertTrue(submitted)
            XCTAssertEqual(delivered.count, 1, "The actual control must not deliver two rapid activations")
            let request = try XCTUnwrap(delivered.first)
            XCTAssertEqual(request.selectedFruitCategory, .grape)
            XCTAssertEqual(request.season, .mature)
            XCTAssertNil(request.plotId)
            XCTAssertTrue(request.tagIds.isEmpty)
            XCTAssertTrue(TreeIdentifierPolicy.validationIssue(for: request.treeID) == nil)
            if !quick { XCTAssertEqual(request.treeID, "ROOT40") }
            let plan = root.scanPlanFactory.makePlan(treeID: request.treeID, season: request.season,
                                                    selectedCategory: request.selectedFruitCategory, renderer: nil)
            settings.fruitType = "orange"
            settings.maxPointCount = 100_000
            XCTAssertEqual(request.selectedFruitCategory, .grape)
            XCTAssertEqual(plan.fruitConfiguration.selectedCategory, .grape)
            XCTAssertEqual(plan.rendererSettings.maxPoints, 1_400_000)
            XCTAssertEqual(frozen.fruitConfiguration.selectedCategory, .pear)
            XCTAssertEqual(frozen.rendererSettings.maxPoints, 1_400_000)
            try await ui.attach(to: self, phase: "controls-\(quick ? "quick" : "start")-submitted")
        }
        let after = UserDefaults.standard.dictionaryRepresentation().filter { protectedKeys.contains($0.key) }
        XCTAssertTrue(NSDictionary(dictionary: after).isEqual(to: shared))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @MainActor
    func testMismatchStopSwitchDoesNotCancelScanReplacedDuringSettingsPublication() throws {
        let suite = "MismatchReentrancy-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.fruitType = "pear"
        let controller = ScanCategoryMismatchPresentationController()
        var scanIdentity = UUID()
        var cancellations = 0
        controller.bind(settings: settings, currentScanIdentity: { scanIdentity }, onStop: { cancellations += 1 })
        controller.present(FruitCategoryMismatch(selectedCategory: .pear, dominantDetectedCategory: .apple,
                                                  supportingFrameCount: 3, confidence: 0.9),
                           scanIdentity: scanIdentity)
        let choice = try XCTUnwrap(controller.presentation)
        let observation = settings.objectWillChange.sink { scanIdentity = UUID() }
        controller.stopAndSwitch(presentationID: choice.id)
        withExtendedLifetime(observation) {
            XCTAssertEqual(settings.fruitType, "apple")
            XCTAssertNotEqual(scanIdentity, choice.scanIdentity)
            XCTAssertEqual(cancellations, 0, "A synchronous preference observer must not expose a new scan to the old cancel action")
        }
    }

    @MainActor
    func testMismatchChoiceRejectsSynchronousReentryAndReboundOwner() throws {
        for phase in 0..<3 {
            let suite = "MismatchOwner-\(UUID())"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let settings = SettingsStore(defaults: defaults)
            settings.fruitType = "pear"
            let controller = ScanCategoryMismatchPresentationController()
            let scanIdentity = UUID()
            var cancellations = 0
            var replacementCancellations = 0
            controller.bind(settings: settings, currentScanIdentity: { scanIdentity }, onStop: { cancellations += 1 })
            controller.present(FruitCategoryMismatch(selectedCategory: .pear, dominantDetectedCategory: .apple,
                                                      supportingFrameCount: 3, confidence: 0.9),
                               scanIdentity: scanIdentity)
            let choice = try XCTUnwrap(controller.presentation)
            var observed = false
            let publisher = phase == 2 ? settings.objectWillChange : controller.objectWillChange
            let observation = publisher.sink {
                guard !observed else { return }
                observed = true
                switch phase {
                case 0: controller.stopAndSwitch(presentationID: choice.id)
                case 1: controller.invalidate()
                default:
                    controller.bind(settings: settings, currentScanIdentity: { scanIdentity },
                                    onStop: { replacementCancellations += 1 })
                }
            }
            controller.stopAndSwitch(presentationID: choice.id)
            withExtendedLifetime(observation) {
                XCTAssertTrue(observed)
                XCTAssertEqual(cancellations, phase == 0 ? 1 : 0)
                XCTAssertEqual(replacementCancellations, 0)
                XCTAssertEqual(settings.fruitType, phase == 1 ? "pear" : "apple")
                XCTAssertNil(controller.presentation)
            }
        }
    }

    @MainActor
    func testMismatchChoiceSurvivesSystemDismissalAndRejectsOldRebindCallback() throws {
        let suite = "MismatchDismissal-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.fruitType = "pear"
        let controller = ScanCategoryMismatchPresentationController()
        let scanIdentity = UUID()
        var cancellations = 0
        let mismatch = FruitCategoryMismatch(selectedCategory: .pear, dominantDetectedCategory: .apple,
                                              supportingFrameCount: 3, confidence: 0.9)
        controller.bind(settings: settings, currentScanIdentity: { scanIdentity }, onStop: { cancellations += 1 })
        controller.present(mismatch, scanIdentity: scanIdentity)
        let choice = try XCTUnwrap(controller.presentation)
        // The alert's presentation binding may clear before its captured button action is delivered.
        controller.presentation = nil
        controller.stopAndSwitch(presentationID: choice.id)
        XCTAssertEqual(settings.fruitType, "apple")
        XCTAssertEqual(cancellations, 1)

        settings.fruitType = "pear"
        controller.present(mismatch, scanIdentity: scanIdentity)
        let previous = try XCTUnwrap(controller.presentation)
        var observed = false
        let observation = controller.objectWillChange.sink {
            guard !observed else { return }
            observed = true
            controller.stopAndSwitch(presentationID: previous.id)
        }
        controller.bind(settings: settings, currentScanIdentity: { scanIdentity }, onStop: { cancellations += 1 })
        withExtendedLifetime(observation) {
            XCTAssertTrue(observed)
            XCTAssertEqual(settings.fruitType, "pear")
            XCTAssertEqual(cancellations, 1, "Rebinding must retire the old choice before publishing dismissal")
        }
    }

    @MainActor
    func testMismatchPresentationRejectsStaleScanAndChoiceAndReleasesBindings() throws {
        let suite = "MismatchLifetime-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.fruitType = "pear"
        let controller = ScanCategoryMismatchPresentationController()
        var scanIdentity = UUID()
        var cancellations = 0
        let mismatch = FruitCategoryMismatch(selectedCategory: .pear, dominantDetectedCategory: .apple,
                                              supportingFrameCount: 3, confidence: 0.9)
        controller.present(mismatch, scanIdentity: scanIdentity)
        XCTAssertNil(controller.presentation)
        controller.bind(settings: settings, currentScanIdentity: { scanIdentity }, onStop: { cancellations += 1 })
        controller.present(mismatch, scanIdentity: scanIdentity)
        let oldChoice = try XCTUnwrap(controller.presentation)
        controller.present(mismatch, scanIdentity: scanIdentity)
        let currentChoice = try XCTUnwrap(controller.presentation)
        controller.stopAndSwitch(presentationID: oldChoice.id)
        controller.continueScan(presentationID: oldChoice.id)
        XCTAssertEqual(controller.presentation?.id, currentChoice.id)
        XCTAssertEqual(settings.fruitType, "pear")
        XCTAssertEqual(cancellations, 0)
        let previousScan = scanIdentity
        scanIdentity = UUID()
        controller.stopAndSwitch(presentationID: currentChoice.id)
        XCTAssertEqual(settings.fruitType, "pear")
        XCTAssertEqual(cancellations, 0)
        controller.present(mismatch, scanIdentity: previousScan)
        XCTAssertEqual(controller.presentation?.id, currentChoice.id)
        controller.present(mismatch, scanIdentity: scanIdentity)
        let nextChoice = try XCTUnwrap(controller.presentation)
        controller.stopAndSwitch(presentationID: nextChoice.id)
        controller.stopAndSwitch(presentationID: nextChoice.id)
        XCTAssertNil(controller.presentation)
        XCTAssertEqual(settings.fruitType, "apple")
        XCTAssertEqual(cancellations, 1)
        weak var retained: NSObject?
        do {
            let token = NSObject()
            retained = token
            controller.bind(settings: settings, currentScanIdentity: { scanIdentity }, onStop: { [token] in
                _ = token
                cancellations += 1
            })
        }
        XCTAssertNotNil(retained)
        controller.present(mismatch, scanIdentity: scanIdentity)
        let invalidated = try XCTUnwrap(controller.presentation)
        controller.invalidate()
        XCTAssertNil(retained)
        controller.present(mismatch, scanIdentity: scanIdentity)
        controller.stopAndSwitch(presentationID: invalidated.id)
        XCTAssertNil(controller.presentation)
        XCTAssertEqual(cancellations, 1)
    }

    @MainActor
    func testMismatchStopSwitchWritesRootAndCancelsOnlyPresentedScan() async throws {
        let detected = FruitCategory.scanCategory(for: SettingsStore.shared.fruitType)
        let initial: FruitCategory = detected == .pear ? .orange : .pear
        await FruitParametersStore.shared.waitForPendingSave()
        let protectedKeys = [SettingsStoreKey.fruitType, FruitParametersStore.userDefaultsKey]
        let shared = UserDefaults.standard.dictionaryRepresentation().filter { protectedKeys.contains($0.key) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "RootMismatch-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        settings.fruitType = initial.rawValue
        let root = AppDependencies(settings: settings, scanRepository: ScanRepository(scansDirectory: directory))
        let frozen = root.scanPlanFactory.makePlan(treeID: "MISMATCH40", season: .mature,
                                                  selectedCategory: initial, renderer: nil)
        let coordinator = ScanCoordinator(settings: settings, calibrationRecordsLoader: { [] })
        let presentation = ScanCategoryMismatchPresentationController()
        var nextRequests = 0
        let scan = ScanView(treeID: "MISMATCH40", gps: GPSRecorder(), season: .mature,
                            selectedFruitCategory: initial, appDependencies: root,
                            onScanNextTree: { nextRequests += 1 }, coordinator: coordinator,
                            categoryMismatchPresentation: presentation)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(RootMismatchHost(scan: scan))
        let ready = try await ui.waitFor { coordinator.onFruitCategoryMismatch != nil && coordinator.isTornDown }
        XCTAssertTrue(ready, "Actual ScanView must install its callback and settle simulator readiness")
        guard ready else { return }
        // Bind a test-owned session without running AR capture or creating a scan artifact.
        let bound = coordinator.scanSession.startNewScan(plan: frozen)
        let callback = try XCTUnwrap(coordinator.onFruitCategoryMismatch)
        let mismatch = FruitCategoryMismatch(selectedCategory: initial, dominantDetectedCategory: detected,
                                              supportingFrameCount: 3, confidence: 0.9)
        callback(mismatch)
        let alert = try await ui.waitFor { ui.element(label: L10n.FruitCategoryVerification.continueAction) != nil }
        XCTAssertTrue(alert)
        try await ui.attach(to: self, phase: "mismatch-continue")
        let firstPresentation = try XCTUnwrap(presentation.presentation)
        presentation.continueScan(presentationID: firstPresentation.id)
        // UIKit dismisses its alert after a real button action; model intent dispatch is separate.
        try ui.dismissSystemAlert()
        let continued = try await ui.waitFor { ui.element(label: L10n.FruitCategoryVerification.stopAndSwitchAction) == nil }
        XCTAssertTrue(continued)
        XCTAssertEqual(settings.fruitType, initial.rawValue)
        XCTAssertEqual(coordinator.activeScanPlan?.id, frozen.id)
        XCTAssertEqual(coordinator.lifecycleSnapshot().scanIdentity, bound.scanIdentity)
        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .recording)
        callback(mismatch)
        let secondAlert = try await ui.waitFor { ui.element(label: L10n.FruitCategoryVerification.stopAndSwitchAction) != nil }
        XCTAssertTrue(secondAlert)
        try await ui.attach(to: self, phase: "mismatch-stop")
        let secondPresentation = try XCTUnwrap(presentation.presentation)
        presentation.stopAndSwitch(presentationID: secondPresentation.id)
        let dismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed)
        try await ui.attach(to: self, phase: "mismatch-dismissed")
        XCTAssertEqual(settings.fruitType, detected.rawValue, "Actual stop-and-switch must write root settings")
        XCTAssertEqual(coordinator.lifecycleSnapshot().state, .cancelled)
        XCTAssertNil(coordinator.activeScanPlan?.id)
        XCTAssertNil(coordinator.onFruitCategoryMismatch)
        XCTAssertEqual(nextRequests, 0)
        XCTAssertEqual(frozen.fruitConfiguration.selectedCategory, initial)
        callback(mismatch)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertNil(ui.controller.presentedViewController)
        XCTAssertEqual(settings.fruitType, detected.rawValue)
        let after = UserDefaults.standard.dictionaryRepresentation().filter { protectedKeys.contains($0.key) }
        XCTAssertTrue(NSDictionary(dictionary: after).isEqual(to: shared))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @MainActor
    func testDashboardQuickScanReadsRootCategoryAndKeepsDraft() async throws {
        try await assertDashboardLaunchCategory(quick: true)
    }

    @MainActor
    func testDashboardStartScanReadsRootCategoryAndKeepsDraft() async throws {
        try await assertDashboardLaunchCategory(quick: false)
    }

    @MainActor
    private func assertDashboardLaunchCategory(quick: Bool) async throws {
        await TagStore.shared.waitForPendingSave()
        let protectedKeys = [SettingsStoreKey.fruitType, TagStore.snapshotUserDefaultsKey,
                             "TagStore.plots", "TagStore.tags", "TagStore.assignments"]
        let shared = UserDefaults.standard.dictionaryRepresentation().filter { protectedKeys.contains($0.key) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "RootLaunchRoute-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let initial: FruitCategory = SettingsStore.shared.fruitType == "pear" ? .orange : .pear
        let later: FruitCategory = initial == .pear ? .orange : .pear
        settings.fruitType = initial.rawValue
        let root = AppDependencies(settings: settings, scanRepository: ScanRepository(scansDirectory: directory))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(DashboardView(
            router: NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter()),
            historyStore: root.historyStore
        ).environmentObject(root))
        let entryLabel = quick ? L10n.Dashboard.quickCapture : L10n.Dashboard.startScan
        for reopened in [false, true] {
            let entryReady = try await ui.waitFor { ui.element(label: entryLabel) != nil }
            try await ui.attach(to: self, phase: "dashboard-entry-\(quick ? "quick" : "start")")
            XCTAssertTrue(entryReady)
            guard entryReady else { return }
            XCTAssertTrue(try XCTUnwrap(ui.element(label: entryLabel)).accessibilityActivate())
            let presented = try await ui.waitFor { ui.controller.presentedViewController != nil }
            XCTAssertTrue(presented)
            guard presented else { return }
            try await ui.attach(to: self, phase: "presented-\(quick ? "quick" : "start")")
            if !quick { try await ui.advanceStartToConfirmation() }
            let pickerReady = try await ui.waitFor { ui.categoryPicker != nil }
            XCTAssertTrue(pickerReady)
            let picker = try XCTUnwrap(ui.categoryPicker)
            let expected = reopened ? later : initial
            try await ui.attach(to: self, phase: "dashboard-\(quick ? "quick" : "start")-\(reopened ? "reopened" : "initial")")
            XCTAssertEqual(picker.accessibilityValue, L10n.FruitCategoryVerification.selectionAccessibilityValue(expected),
                           "Actual Dashboard launch route must initialize its draft from root settings")
            guard picker.accessibilityValue == L10n.FruitCategoryVerification.selectionAccessibilityValue(expected) else { return }
            if !reopened {
                settings.fruitType = later.rawValue
                try await Task.sleep(nanoseconds: 60_000_000)
                XCTAssertEqual(picker.accessibilityValue, L10n.FruitCategoryVerification.selectionAccessibilityValue(initial),
                               "An existing launch draft must not follow later root changes")
            }
            let cancel = ui.element(label: quick ? L10n.QuickScan.close : L10n.StartFlow.cancel)
            XCTAssertTrue(try XCTUnwrap(cancel).accessibilityActivate())
            let dismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
            XCTAssertTrue(dismissed)
        }
        let after = UserDefaults.standard.dictionaryRepresentation().filter { protectedKeys.contains($0.key) }
        XCTAssertTrue(NSDictionary(dictionary: after).isEqual(to: shared))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @MainActor
    func testDashboardSettingsRoutesEditRootAndPreserveFrozenPlan() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "RootSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let shared = SettingsStore.shared
        await FruitParametersStore.shared.waitForPendingSave()
        let protectedKeys = [SettingsStoreKey.autoExportCSV, SettingsStoreKey.fruitType,
                             SettingsStoreKey.cameraResolution, SettingsStoreKey.cameraFrameRate,
                             SettingsStoreKey.qualityPreset, SettingsStoreKey.maxPointCount,
                             SettingsStoreKey.scanPrecision, FruitParametersStore.userDefaultsKey]
        let sharedValues = UserDefaults.standard.dictionaryRepresentation().filter { protectedKeys.contains($0.key) }
        let settings = SettingsStore(defaults: defaults)
        let initialCategory: FruitCategory = shared.fruitType == "pear" ? .orange : .pear
        let initialCSV = !shared.autoExportCSV
        settings.fruitType = initialCategory.rawValue
        settings.autoExportCSV = initialCSV
        settings.maxPointCount = 1_400_000
        settings.scanPrecision = 0.017
        settings.cameraResolution = shared.cameraResolution == "4K" ? "720p" : "4K"
        settings.cameraFrameRate = shared.cameraFrameRate == "120fps" ? "30fps" : "120fps"
        let initialResolution = settings.cameraResolution
        let initialFrameRate = settings.cameraFrameRate
        let dependencies = AppDependencies(settings: settings, scanRepository: ScanRepository(scansDirectory: directory))
        let frozen = dependencies.scanPlanFactory.makePlan(
            treeID: "ROOT-SETTINGS", season: .mature, selectedCategory: initialCategory, renderer: nil
        )
        let controller = UIHostingController(rootView:
            DashboardView(router: NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter()),
                          historyStore: dependencies.historyStore)
                .environmentObject(dependencies)
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer {
            controller.presentedViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        func elements(in root: NSObject) -> [NSObject] {
            var seen = Set<ObjectIdentifier>()
            var result: [NSObject] = []
            func visit(_ object: NSObject, depth: Int = 0) {
                guard depth < 32, seen.insert(ObjectIdentifier(object)).inserted else { return }
                result.append(object)
                let count = object.accessibilityElementCount()
                if count > 0 && count < 100 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject { visit(child, depth: depth + 1) }
                    }
                }
                if let view = object as? UIView { for child in view.subviews { visit(child, depth: depth + 1) } }
            }
            visit(root)
            return result
        }
        func element(_ label: String, in root: NSObject) -> NSObject? {
            let candidates = elements(in: root)
            return candidates.first { $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.button) } ??
                candidates.first { $0.accessibilityLabel == label } ?? candidates.first {
                $0.accessibilityLabel?.hasPrefix(label) == true && $0.accessibilityValue != nil
            }
        }
        func waitFor(_ condition: () -> Bool) async throws -> Bool {
            func settled(_ current: UIViewController) -> Bool {
                current.transitionCoordinator == nil && !current.isBeingPresented && !current.isBeingDismissed &&
                    current.children.allSatisfy(settled) && (current.presentedViewController.map(settled) ?? true)
            }
            let deadline = Date().addingTimeInterval(3)
            repeat {
                window.layoutIfNeeded()
                controller.presentedViewController?.view.layoutIfNeeded()
                if settled(controller) && condition() { return true }
                try await Task.sleep(nanoseconds: 20_000_000)
            } while Date() < deadline
            return false
        }
        func attach(_ phase: String) {
            let image = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            })
            image.name = "RootSettings-\(phase)"
            image.lifetime = .keepAlways
            add(image)
            let lines: [String] = elements(in: window).compactMap { element -> String? in
                guard let label = element.accessibilityLabel else { return nil }
                let typeName = String(describing: type(of: element))
                let traits = String(element.accessibilityTraits.rawValue)
                let value = element.accessibilityValue ?? ""
                return "\(typeName) [\(traits)] \(label) = \(value)"
            }
            let text = XCTAttachment(string: lines.joined(separator: "\n"))
            text.name = "RootSettings-\(phase)-accessibility"
            text.lifetime = .keepAlways
            add(text)
        }
        func scrollTo(_ label: String, in view: UIView) async throws -> NSObject {
            if let current = element(label, in: view), current.accessibilityFrame.intersects(window.bounds) { return current }
            let scroll = try XCTUnwrap(elements(in: view).compactMap { $0 as? UIScrollView }.first {
                $0.bounds.height > 150 && $0.contentSize.height > $0.bounds.height
            })
            let maximum = max(0, scroll.contentSize.height - scroll.bounds.height)
            for offset in stride(from: CGFloat(0), through: maximum, by: max(100, scroll.bounds.height / 2)) {
                scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
                try await Task.sleep(nanoseconds: 20_000_000)
                if let current = element(label, in: view), current.accessibilityFrame.intersects(window.bounds) { return current }
            }
            scroll.setContentOffset(CGPoint(x: 0, y: maximum), animated: false)
            try await Task.sleep(nanoseconds: 20_000_000)
            return try XCTUnwrap(element(label, in: view))
        }
        func openSettings() async throws -> UIViewController {
            let ready = try await waitFor { element(L10n.Dashboard.settingsAccessibilityLabel, in: controller.view) != nil }
            XCTAssertTrue(ready)
            XCTAssertTrue(try XCTUnwrap(element(L10n.Dashboard.settingsAccessibilityLabel, in: controller.view)).accessibilityActivate())
            let presented = try await waitFor {
                guard let sheet = controller.presentedViewController else { return false }
                return !sheet.isBeingPresented && sheet.transitionCoordinator == nil &&
                    element(L10n.Settings.autoExportCSV, in: sheet.view) != nil
            }
            XCTAssertTrue(presented)
            return try XCTUnwrap(controller.presentedViewController)
        }
        func returnToSettings(in sheet: UIViewController) throws {
            func navigation(in current: UIViewController) -> UINavigationController? {
                if let navigation = current as? UINavigationController, navigation.viewControllers.count > 1 {
                    return navigation
                }
                return current.children.lazy.compactMap { navigation(in: $0) }.first
            }
            let navigation = try XCTUnwrap(navigation(in: sheet))
            XCTAssertNotNil(navigation.popViewController(animated: true))
        }
        let sheet = try await openSettings()
        attach("presented")
        let category = try await scrollTo(L10n.Settings.currentFruitType, in: sheet.view)
        attach("initial")
        XCTAssertEqual(category.accessibilityValue, L10n.Fruit.name(for: initialCategory),
                       "Actual Dashboard settings must display the injected root category")
        guard category.accessibilityValue == L10n.Fruit.name(for: initialCategory) else { return }
        let pointControl = try await scrollTo(L10n.Settings.maxPoints, in: sheet.view)
        let points = try XCTUnwrap(pointControl as? UISlider)
        XCTAssertEqual(points.accessibilityValue, L10n.Settings.maxPointCountValue(1_400_000))
        points.sendActions(for: .touchDown)
        points.value += (points.maximumValue - points.minimumValue) / 29
        points.sendActions(for: .valueChanged)
        let pointDraftChanged = try await waitFor { points.accessibilityValue == L10n.Settings.maxPointCountValue(1_500_000) }
        XCTAssertTrue(pointDraftChanged)
        XCTAssertEqual(settings.maxPointCount, 1_400_000, "Dragging must keep edits in the draft")
        points.sendActions(for: .touchUpInside)
        let pointCommitted = try await waitFor { settings.maxPointCount == 1_500_000 }
        XCTAssertTrue(pointCommitted)
        let precisionControl = try await scrollTo(L10n.Settings.precision, in: sheet.view)
        let precision = try XCTUnwrap(precisionControl as? UISlider)
        XCTAssertEqual(precision.accessibilityValue, L10n.Settings.precisionValue(1.7))
        precision.sendActions(for: .touchDown)
        precision.value += (precision.maximumValue - precision.minimumValue) / 49
        precision.sendActions(for: .valueChanged)
        let precisionDraftChanged = try await waitFor { precision.accessibilityValue == L10n.Settings.precisionValue(1.8) }
        XCTAssertTrue(precisionDraftChanged)
        XCTAssertEqual(settings.scanPrecision, 0.017, accuracy: 0.00001)
        let csv = try await scrollTo(L10n.Settings.autoExportCSV, in: sheet.view)
        XCTAssertTrue(csv.accessibilityActivate())
        let toggled = try await waitFor { settings.autoExportCSV == !initialCSV }
        XCTAssertTrue(toggled, "Actual toggle must write the same root used by ScanPlanFactory")
        let camera = try await scrollTo(L10n.Settings.cameraSettings, in: sheet.view)
        XCTAssertTrue(camera.accessibilityActivate())
        let cameraReady = try await waitFor { element(L10n.Settings.targetResolution, in: sheet.view) != nil }
        XCTAssertTrue(cameraReady)
        let precisionCommitted = try await waitFor { abs(settings.scanPrecision - 0.018) < 0.00001 }
        XCTAssertTrue(precisionCommitted, "Leaving Settings must commit the precision draft")
        attach("camera")
        let resolution = try XCTUnwrap(element(L10n.Settings.targetResolution, in: sheet.view))
        let fps = try XCTUnwrap(element(L10n.Settings.captureFrameRate, in: sheet.view))
        XCTAssertEqual(resolution.accessibilityValue, initialResolution, "Nested camera must observe the same root")
        XCTAssertEqual(fps.accessibilityValue, initialFrameRate)
        guard resolution.accessibilityValue == initialResolution && fps.accessibilityValue == initialFrameRate else { return }
        let changedResolution = initialResolution == "4K" ? "720p" : "4K"
        XCTAssertTrue(resolution.accessibilityActivate())
        let menuReady = try await waitFor { element(changedResolution, in: window) != nil }
        XCTAssertTrue(menuReady)
        attach("resolution-menu")
        let resolutionButton = try XCTUnwrap(resolution as? UIButton)
        func actions(in menu: UIMenu) -> [UIAction] {
            menu.children.flatMap { child -> [UIAction] in
                if let action = child as? UIAction { return [action] }
                if let submenu = child as? UIMenu { return actions(in: submenu) }
                return []
            }
        }
        let option = try XCTUnwrap(actions(in: try XCTUnwrap(resolutionButton.menu)).first { $0.title == changedResolution })
        resolutionButton.sendAction(option)
        resolutionButton.contextMenuInteraction?.dismissMenu()
        let resolutionChanged = try await waitFor { settings.cameraResolution == changedResolution }
        XCTAssertTrue(resolutionChanged)
        try returnToSettings(in: sheet)
        let returned = try await waitFor { element(L10n.Settings.varietyDatabase, in: sheet.view) != nil }
        XCTAssertTrue(returned)
        let variety = try await scrollTo(L10n.Settings.varietyDatabase, in: sheet.view)
        XCTAssertTrue(variety.accessibilityActivate())
        let currentLabel = L10n.VarietyDatabase.currentAccessibility(L10n.Fruit.name(for: initialCategory))
        let varietyReady = try await waitFor { element(currentLabel, in: sheet.view) != nil }
        attach("variety")
        XCTAssertTrue(varietyReady, "Nested variety current category must observe the injected root")
        guard varietyReady else { return }
        let appleName = L10n.Fruit.name(for: .apple)
        let appleLabel = try XCTUnwrap(elements(in: sheet.view).first {
            $0.accessibilityTraits.contains(.button) && $0.accessibilityHint == L10n.VarietyDatabase.useHint &&
                $0.accessibilityLabel?.contains(appleName) == true
        }?.accessibilityLabel)
        let apple = try await scrollTo(appleLabel, in: sheet.view)
        XCTAssertTrue(apple.accessibilityFrame.intersects(window.bounds))
        XCTAssertTrue(apple.accessibilityActivate())
        let applied = try await waitFor { settings.fruitType == "apple" }
        XCTAssertTrue(applied, "Variety use must update root settings without changing the parameter database")
        try returnToSettings(in: sheet)
        let rootReturned = try await waitFor { element(L10n.Settings.currentFruitType, in: sheet.view)?.accessibilityValue == appleName }
        XCTAssertTrue(rootReturned)
        attach("changed")
        XCTAssertTrue(try XCTUnwrap(element(L10n.Common.done, in: sheet.view)).accessibilityActivate())
        let closed = try await waitFor { controller.presentedViewController == nil }
        XCTAssertTrue(closed)
        XCTAssertEqual(settings.maxPointCount, 1_500_000)
        XCTAssertEqual(settings.scanPrecision, 0.018, accuracy: 0.00001)
        let reopened = try await openSettings()
        let reopenedCategory = try await scrollTo(L10n.Settings.currentFruitType, in: reopened.view)
        XCTAssertEqual(reopenedCategory.accessibilityValue, appleName)
        attach("reopened")
        XCTAssertTrue(try XCTUnwrap(element(L10n.Common.done, in: reopened.view)).accessibilityActivate())
        let closedAgain = try await waitFor { controller.presentedViewController == nil }
        XCTAssertTrue(closedAgain)
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.fruitType, "apple")
        XCTAssertEqual(reloaded.autoExportCSV, !initialCSV)
        XCTAssertEqual(reloaded.cameraResolution, changedResolution)
        XCTAssertEqual(reloaded.maxPointCount, 1_500_000)
        XCTAssertEqual(reloaded.scanPrecision, 0.018, accuracy: 0.00001)
        let plan = dependencies.scanPlanFactory.makePlan(treeID: "ROOT-SETTINGS-NEXT", season: .mature,
                                                        selectedCategory: .apple, renderer: nil)
        XCTAssertEqual(plan.requestedCameraResolution, changedResolution)
        XCTAssertEqual(plan.requestedCameraFrameRate, initialFrameRate)
        XCTAssertEqual(plan.autoExportCSV, !initialCSV)
        XCTAssertEqual(plan.rendererSettings.maxPoints, 1_500_000)
        XCTAssertEqual(plan.fruitConfiguration.selectedCategory, .apple)
        XCTAssertEqual(frozen.requestedCameraResolution, initialResolution)
        XCTAssertEqual(frozen.requestedCameraFrameRate, initialFrameRate)
        XCTAssertEqual(frozen.autoExportCSV, initialCSV)
        XCTAssertEqual(frozen.rendererSettings.maxPoints, 1_400_000)
        XCTAssertEqual(frozen.fruitConfiguration.selectedCategory, initialCategory)
        let currentShared = UserDefaults.standard.dictionaryRepresentation().filter { protectedKeys.contains($0.key) }
        XCTAssertTrue(NSDictionary(dictionary: currentShared).isEqual(to: sharedValues))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @MainActor
    func testDashboardComparisonCloseReturnsToRootAndAllowsReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for (name, count, yield) in [("a", 6, 1.5), ("b", 12, 3.0)] {
            try PLYPointCloudWriter.write(
                points: [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)],
                treeID: "CLOSE-\(name)", scanDate: "2026-10-02 00:00:00", gpsLat: 0, gpsLon: 0,
                to: directory.appendingPathComponent(name + ".ply")
            )
            try JSONSerialization.data(withJSONObject: [
                "fruitCount": count, "yieldKg": yield, "fruitType": "apple", "confidence": "medium"
            ]).write(to: directory.appendingPathComponent(name + "_result.json"))
        }
        let sourceBytes = try Dictionary(uniqueKeysWithValues: ["a.ply", "b.ply", "a_result.json", "b_result.json"].map {
            let url = directory.appendingPathComponent($0)
            return (url, try Data(contentsOf: url))
        })
        let dependencies = AppDependencies(scanRepository: ScanRepository(scansDirectory: directory))
        let suiteName = "RootComparisonCloseTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let router = NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter())
        let controller = UIHostingController(rootView:
            DashboardView(router: router, historyStore: dependencies.historyStore)
                .environmentObject(dependencies)
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        defer {
            controller.presentedViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        func waitFor(_ condition: () -> Bool) async throws -> Bool {
            let deadline = Date().addingTimeInterval(3)
            repeat {
                controller.view.layoutIfNeeded()
                if condition() { return true }
                try await Task.sleep(nanoseconds: 20_000_000)
            } while Date() < deadline
            return false
        }
        func button(label: String, in root: NSObject) -> NSObject? {
            var visited = Set<ObjectIdentifier>()
            func visit(_ object: NSObject, depth: Int = 0) -> NSObject? {
                guard depth < 32, visited.insert(ObjectIdentifier(object)).inserted else { return nil }
                if object.accessibilityLabel == label, object.accessibilityTraits.contains(.button) { return object }
                let count = object.accessibilityElementCount()
                if count > 0 && count < 100 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject,
                           let result = visit(child, depth: depth + 1) { return result }
                    }
                }
                if let view = object as? UIView {
                    for child in view.subviews {
                        if let result = visit(child, depth: depth + 1) { return result }
                    }
                }
                return nil
            }
            return visit(root)
        }
        func scrollView(in view: UIView) -> UIScrollView? {
            if let scroll = view as? UIScrollView { return scroll }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        func attach(_ phase: String) {
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            })
            attachment.name = "RootComparisonClose-\(phase)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let loaded = try await waitFor {
            !dependencies.historyStore.isLoading && dependencies.historyStore.scanFiles.count == 2
        }
        XCTAssertTrue(loaded)
        let analysisTab = try XCTUnwrap(button(label: WorkspaceText.analysis, in: controller.view))
        XCTAssertTrue(analysisTab.accessibilityActivate())
        let analysisSelected = try await waitFor {
            button(label: WorkspaceText.analysis, in: controller.view)?.accessibilityTraits.contains(.selected) == true
        }
        XCTAssertTrue(analysisSelected, "Comparison is available from the actual analysis tab")
        let comparisonLabel = L10n.Dashboard.quickActionAccessibilityLabel(
            title: L10n.Dashboard.compareTitle, description: L10n.Dashboard.compareDescription
        )
        let scroll = try XCTUnwrap(scrollView(in: controller.view))
        var action: NSObject?
        let maximumOffset = max(0, scroll.contentSize.height - scroll.bounds.height)
        for offset in stride(from: CGFloat(0), through: maximumOffset, by: max(100, scroll.bounds.height / 2)) {
            scroll.setContentOffset(CGPoint(x: 0, y: offset), animated: false)
            controller.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 20_000_000)
            if let candidate = button(label: comparisonLabel, in: controller.view),
               candidate.accessibilityFrame.intersects(window.bounds) {
                action = candidate
                break
            }
        }
        XCTAssertNotNil(action, "The real Dashboard must expose its comparison quick action")
        guard action != nil else { return }
        let presentation = HistoricalComparePresentation()
        for complete in [true, false] {
            if !complete {
                try FileManager.default.removeItem(at: directory.appendingPathComponent("b_result.json"))
                await dependencies.historyStore.reloadRecords()
            }
            let comparisonButton = try XCTUnwrap(button(label: comparisonLabel, in: controller.view))
            XCTAssertTrue(comparisonButton.accessibilityActivate())
            let presented = try await waitFor {
                guard let sheet = controller.presentedViewController else { return false }
                sheet.view.layoutIfNeeded()
                return !sheet.isBeingPresented && sheet.transitionCoordinator == nil &&
                    renderedAccessibilityText(in: sheet.view).contains(complete ? presentation.prompt : presentation.emptyTitle)
            }
            XCTAssertTrue(presented, "The real Dashboard must present comparison again after closing")
            let sheet = try XCTUnwrap(controller.presentedViewController)
            attach(complete ? "complete" : "empty")
            let close = button(label: L10n.Common.done, in: sheet.view)
            XCTAssertNotNil(close, "The actual comparison sheet must provide an explicit visible close control")
            guard let close else { return }
            XCTAssertTrue(close.accessibilityActivate())
            let dismissed = try await waitFor { controller.presentedViewController == nil }
            XCTAssertTrue(dismissed, "Comparison close must dismiss Dashboard's sheet")
            XCTAssertNotNil(button(label: comparisonLabel, in: controller.view))
            XCTAssertNil(button(label: L10n.Common.done, in: controller.view))
            attach(complete ? "returned-complete" : "returned-empty")
        }
        try XCTUnwrap(sourceBytes[directory.appendingPathComponent("b_result.json")])
            .write(to: directory.appendingPathComponent("b_result.json"))
        for (url, bytes) in sourceBytes { XCTAssertEqual(try Data(contentsOf: url), bytes) }
    }

    @MainActor
    func testDashboardMapRouteUsesRootHistoryAndRefreshesSelectedDetails() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suffix = String(UUID().uuidString.prefix(4))
        let firstID = "A-\(suffix)"
        let secondID = "B-\(suffix)"
        let excludedIDs = ["RAW-\(suffix)", "BAD-\(suffix)", "NO-GPS-\(suffix)"]
        for (name, identity, date, latitude, longitude) in [
            ("older", firstID, "2026-09-30 00:00:00", 0.011, 0.012),
            ("latest", firstID, "2026-10-01 00:00:00", 0.011, 0.012),
            ("peer", secondID, "2026-10-01 00:00:00", 0.013, 0.014),
            ("raw", excludedIDs[0], "2026-10-02 00:00:00", 0.015, 0.016),
            ("invalid", excludedIDs[1], "2026-10-02 00:00:00", 0.017, 0.018),
            ("unlocated", excludedIDs[2], "2026-10-02 00:00:00", 0.0, 0.0)
        ] {
            try PLYPointCloudWriter.write(
                points: [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)],
                treeID: identity, scanDate: date, gpsLat: latitude, gpsLon: longitude,
                to: directory.appendingPathComponent(name + ".ply")
            )
        }
        func metadataURL(_ name: String) -> URL { directory.appendingPathComponent(name + "_result.json") }
        func writeMetadata(_ name: String, count: Int, yield: Double) throws {
            try JSONSerialization.data(withJSONObject: [
                "fruitCount": count, "yieldKg": yield, "fruitType": "apple", "confidence": "medium"
            ]).write(to: metadataURL(name))
        }
        try writeMetadata("older", count: 8, yield: 10)
        try writeMetadata("latest", count: 0, yield: 0)
        try writeMetadata("peer", count: 12, yield: 40)
        try writeMetadata("unlocated", count: 99, yield: 99)
        try Data("invalid result".utf8).write(to: metadataURL("invalid"))
        let sources = try Dictionary(uniqueKeysWithValues: ["older", "latest", "peer", "raw", "invalid", "unlocated"].map {
            let url = directory.appendingPathComponent($0 + ".ply")
            return (url, try Data(contentsOf: url))
        })
        let dependencies = AppDependencies(scanRepository: ScanRepository(scansDirectory: directory))
        XCTAssertTrue(dependencies.historyStore.scanFiles.isEmpty)
        let suiteName = "RootMapTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let dashboard = DashboardView(
            router: NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter()),
            historyStore: dependencies.historyStore
        )
        let controller = UIHostingController(rootView: dashboard.sheetView(for: .map)
            .environment(\.locale, Locale(identifier: "en_US_POSIX")))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        window.layoutIfNeeded()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        let presentation = OrchardMapPresentation()
        func waitFor(_ condition: () -> Bool) async throws -> Bool {
            let deadline = Date().addingTimeInterval(3)
            repeat {
                controller.view.layoutIfNeeded()
                if condition() { return true }
                try await Task.sleep(nanoseconds: 20_000_000)
            } while Date() < deadline
            return false
        }
        func map(in view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            return view.subviews.lazy.compactMap { map(in: $0) }.first
        }
        func button(label: String, in root: NSObject) -> NSObject? {
            var visited = Set<ObjectIdentifier>()
            func visit(_ object: NSObject, depth: Int = 0) -> NSObject? {
                guard depth < 32, visited.insert(ObjectIdentifier(object)).inserted else { return nil }
                if object.accessibilityLabel == label, object.accessibilityTraits.contains(.button) { return object }
                let count = object.accessibilityElementCount()
                if count > 0 && count < 100 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject,
                           let found = visit(child, depth: depth + 1) { return found }
                    }
                }
                if let view = object as? UIView {
                    for child in view.subviews {
                        if let found = visit(child, depth: depth + 1) { return found }
                    }
                }
                return nil
            }
            return visit(root)
        }
        func attach(_ phase: String) {
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            })
            attachment.name = "RootMap-\(phase)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let loaded = try await waitFor {
            !dependencies.historyStore.isLoading && dependencies.historyStore.scanFiles.count == 6
        }
        attach("entry")
        XCTAssertTrue(loaded, "The real map entry must load the Dashboard root archive")
        guard loaded else { return }
        let mapReady = try await waitFor {
            map(in: controller.view)?.annotations.contains {
                abs($0.coordinate.latitude - 0.011) < 0.000001 && abs($0.coordinate.longitude - 0.012) < 0.000001
            } == true
        }
        XCTAssertTrue(mapReady)
        let mapView = try XCTUnwrap(map(in: controller.view))
        let annotation = try XCTUnwrap(mapView.annotations.first {
            abs($0.coordinate.latitude - 0.011) < 0.000001 && abs($0.coordinate.longitude - 0.012) < 0.000001
        })
        let entryText = renderedAccessibilityText(in: controller.view)
        XCTAssertTrue(entryText.contains(presentation.treeCountText(2, locale: Locale(identifier: "en_US_POSIX"))))
        for id in excludedIDs { XCTAssertFalse(entryText.contains(id)) }
        // Use the actual production annotation and MapKit's public selection control.
        mapView.selectAnnotation(annotation, animated: false)
        let selected = try await waitFor {
            button(label: presentation.closeDetails, in: controller.view) != nil &&
                renderedAccessibilityText(in: controller.view).contains("0.0 kg")
        }
        XCTAssertTrue(selected, "Selecting the real map annotation must show its complete latest zero")
        attach("selected-zero")
        guard selected else { return }

        try writeMetadata("latest", count: 6, yield: 1.5)
        await dependencies.historyStore.reloadRecords()
        let currentRecord = try XCTUnwrap(dependencies.historyStore.scanFiles.first { $0.fileURL.lastPathComponent == "latest.ply" })
        XCTAssertEqual(currentRecord.yieldKg, 1.5)
        XCTAssertEqual(currentRecord.fruitCount, 6)
        let refreshed = try await waitFor {
            renderedAccessibilityText(in: controller.view).contains("1.5 kg")
        }
        XCTAssertTrue(refreshed, "Selected details must read the current root record instead of a stale annotation copy")
        attach("refreshed")
        guard refreshed else {
            for (url, bytes) in sources { XCTAssertEqual(try Data(contentsOf: url), bytes) }
            return
        }
        let filter = try XCTUnwrap(button(label: presentation.yieldLevelLabel(.medium), in: controller.view))
        XCTAssertTrue(filter.accessibilityActivate())
        let filtered = try await waitFor {
            button(label: presentation.closeDetails, in: controller.view) == nil &&
                !mapView.annotations.contains {
                    abs($0.coordinate.latitude - 0.011) < 0.000001 && abs($0.coordinate.longitude - 0.012) < 0.000001
                }
        }
        XCTAssertTrue(filtered, "A filtered-out record must not keep visible details")
        attach("filtered")
        let clearFilter = try XCTUnwrap(button(label: presentation.clearFilter, in: controller.view))
        XCTAssertTrue(clearFilter.accessibilityActivate())
        let restored = try await waitFor {
            button(label: presentation.clearFilter, in: controller.view) == nil &&
                mapView.annotations.contains {
                    abs($0.coordinate.latitude - 0.011) < 0.000001 && abs($0.coordinate.longitude - 0.012) < 0.000001
                }
        }
        XCTAssertTrue(restored)
        XCTAssertNil(button(label: presentation.closeDetails, in: controller.view))
        let reinserted = try XCTUnwrap(mapView.annotations.first {
            abs($0.coordinate.latitude - 0.011) < 0.000001 && abs($0.coordinate.longitude - 0.012) < 0.000001
        })
        mapView.selectAnnotation(reinserted, animated: false)
        let reselected = try await waitFor { button(label: presentation.closeDetails, in: controller.view) != nil }
        XCTAssertTrue(reselected)
        // Only owned companion files are invalidated; PLY evidence is untouched.
        try FileManager.default.removeItem(at: metadataURL("latest"))
        await dependencies.historyStore.reloadRecords()
        let invalidated = try await waitFor {
            button(label: presentation.closeDetails, in: controller.view) == nil && mapView.selectedAnnotations.isEmpty
        }
        XCTAssertTrue(invalidated, "The older per-tree fallback must not retain the newer record's selection")
        attach("invalidated")
        try writeMetadata("latest", count: 6, yield: 1.5)
        await dependencies.historyStore.reloadRecords()
        let remainsCleared = try await waitFor {
            button(label: presentation.closeDetails, in: controller.view) == nil && mapView.selectedAnnotations.isEmpty
        }
        XCTAssertTrue(remainsCleared)
        XCTAssertNil(button(label: presentation.closeDetails, in: controller.view))
        attach("complete-again")
        for name in ["older", "latest", "peer"] { try FileManager.default.removeItem(at: metadataURL(name)) }
        await dependencies.historyStore.reloadRecords()
        let empty = try await waitFor { renderedAccessibilityText(in: controller.view).contains(presentation.emptyTitle) }
        XCTAssertTrue(empty)
        for (url, bytes) in sources { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        attach("empty")
    }

    @MainActor
    func testDashboardComparisonRouteLoadsRootHistoryAndReconcilesSelections() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suffix = String(UUID().uuidString.prefix(4))
        let firstID = "A-\(suffix)"
        let secondID = "B-\(suffix)"
        let rawID = "RAW-\(suffix)"
        let invalidID = "BAD-\(suffix)"
        for (name, identity) in [("a", firstID), ("b", secondID), ("raw", rawID), ("invalid", invalidID)] {
            try PLYPointCloudWriter.write(
                points: [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)],
                treeID: identity, scanDate: "2026-10-02 00:00:00", gpsLat: 0, gpsLon: 0,
                to: directory.appendingPathComponent(name + ".ply")
            )
        }
        let firstMetadata = directory.appendingPathComponent("a_result.json")
        let secondMetadata = directory.appendingPathComponent("b_result.json")
        func writeMetadata(count: Int, yield: Double, to url: URL) throws {
            try JSONSerialization.data(withJSONObject: [
                "fruitCount": count, "yieldKg": yield, "fruitType": "apple", "confidence": "medium"
            ]).write(to: url)
        }
        try writeMetadata(count: 0, yield: 0, to: firstMetadata)
        try writeMetadata(count: 12, yield: 3, to: secondMetadata)
        try Data("invalid result".utf8).write(to: directory.appendingPathComponent("invalid_result.json"))
        let sources = try Dictionary(uniqueKeysWithValues: ["a", "b", "raw", "invalid"].map {
            let url = directory.appendingPathComponent($0 + ".ply")
            return (url, try Data(contentsOf: url))
        })
        let dependencies = AppDependencies(scanRepository: ScanRepository(scansDirectory: directory))
        XCTAssertTrue(dependencies.historyStore.scanFiles.isEmpty)
        let suiteName = "RootComparisonTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let dashboard = DashboardView(
            router: NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter()),
            historyStore: dependencies.historyStore
        )
        let controller = UIHostingController(rootView: dashboard.sheetView(for: .compare)
            .environment(\.locale, Locale(identifier: "en_US_POSIX")))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        window.layoutIfNeeded()
        defer {
            controller.presentedViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        let presentation = HistoricalComparePresentation()
        func waitFor(_ condition: () -> Bool) async throws -> Bool {
            let deadline = Date().addingTimeInterval(3)
            repeat {
                controller.view.layoutIfNeeded()
                if condition() { return true }
                try await Task.sleep(nanoseconds: 20_000_000)
            } while Date() < deadline
            return false
        }
        func element(label: String, in root: NSObject, button: Bool = false) -> NSObject? {
            var visited = Set<ObjectIdentifier>()
            func visit(_ object: NSObject, depth: Int = 0) -> NSObject? {
                guard depth < 32, visited.insert(ObjectIdentifier(object)).inserted else { return nil }
                if object.accessibilityLabel == label,
                   !button || object.accessibilityTraits.contains(.button) { return object }
                let count = object.accessibilityElementCount()
                if count > 0 && count < 100 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject,
                           let found = visit(child, depth: depth + 1) { return found }
                    }
                }
                if let view = object as? UIView {
                    for child in view.subviews {
                        if let found = visit(child, depth: depth + 1) { return found }
                    }
                }
                return nil
            }
            return visit(root)
        }
        func attach(_ phase: String) {
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            })
            attachment.name = "RootComparison-\(phase)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let loaded = try await waitFor {
            !dependencies.historyStore.isLoading && dependencies.historyStore.scanFiles.count == 4
        }
        attach("entry")
        XCTAssertTrue(loaded, "The real Dashboard comparison entry must load its cold root history")
        guard loaded else { return }
        XCTAssertTrue(renderedAccessibilityText(in: controller.view).contains(presentation.prompt))

        func select(slot: String, treeID: String, excluding otherID: String? = nil) async throws {
            let slotButton = try XCTUnwrap(element(label: slot, in: controller.view, button: true))
            XCTAssertTrue(slotButton.accessibilityActivate())
            let presented = try await waitFor {
                guard let sheet = controller.presentedViewController else { return false }
                sheet.view.layoutIfNeeded()
                return !sheet.isBeingPresented && sheet.transitionCoordinator == nil
            }
            XCTAssertTrue(presented)
            let sheet = try XCTUnwrap(controller.presentedViewController)
            let text = renderedAccessibilityText(in: sheet.view)
            XCTAssertTrue(text.contains(treeID), "Picker must list records from the same root: \(text)")
            XCTAssertFalse(text.contains(rawID))
            XCTAssertFalse(text.contains(invalidID))
            if let otherID { XCTAssertFalse(text.contains(otherID), "The other selected record must be excluded") }
            attach("picker-\(slot)")
            let row = try XCTUnwrap(element(label: presentation.treeTitle(treeID), in: sheet.view, button: true))
            XCTAssertTrue(row.accessibilityActivate())
            let dismissed = try await waitFor { controller.presentedViewController == nil }
            XCTAssertTrue(dismissed)
        }
        try await select(slot: presentation.scanA, treeID: firstID)
        try await select(slot: presentation.scanB, treeID: secondID, excluding: firstID)
        let zeroComparison = try XCTUnwrap(element(label: presentation.yieldChange, in: controller.view))
        let unavailable = Bundle.main.localizedString(forKey: "historical_compare.unavailable", value: nil, table: nil)
        XCTAssertTrue(zeroComparison.accessibilityValue?.contains("0.0 kg") == true)
        XCTAssertTrue(zeroComparison.accessibilityValue?.contains("3.0 kg") == true)
        XCTAssertTrue(zeroComparison.accessibilityValue?.contains(unavailable) == true)
        attach("complete-zero")

        try writeMetadata(count: 6, yield: 1.5, to: firstMetadata)
        await dependencies.historyStore.reloadRecords()
        let refreshed = try await waitFor {
            element(label: presentation.yieldChange, in: controller.view)?.accessibilityValue?.contains("100.0%") == true
        }
        XCTAssertTrue(refreshed, "Existing selections must receive the root's updated values")
        XCTAssertTrue(element(label: presentation.scanA, in: controller.view, button: true)?.accessibilityValue?.contains("1.5 kg") == true)
        attach("refreshed")

        // Invalidate only a test-owned companion; retain all point-cloud sources.
        try FileManager.default.removeItem(at: secondMetadata)
        await dependencies.historyStore.reloadRecords()
        let oneComplete = try await waitFor { renderedAccessibilityText(in: controller.view).contains(presentation.emptyTitle) }
        XCTAssertTrue(oneComplete)
        attach("one-complete")
        try writeMetadata(count: 12, yield: 3, to: secondMetadata)
        await dependencies.historyStore.reloadRecords()
        let restored = try await waitFor {
            element(label: presentation.scanB, in: controller.view, button: true)?.accessibilityValue == presentation.noScanSelected
        }
        XCTAssertTrue(restored, "An invalidated selection must stay cleared when its record becomes complete again")
        XCTAssertTrue(element(label: presentation.scanA, in: controller.view, button: true)?.accessibilityValue?.contains(firstID) == true)
        XCTAssertFalse(renderedAccessibilityText(in: controller.view).contains(presentation.yieldChange))
        attach("selection-cleared")

        try FileManager.default.removeItem(at: firstMetadata)
        try FileManager.default.removeItem(at: secondMetadata)
        await dependencies.historyStore.reloadRecords()
        let empty = try await waitFor { renderedAccessibilityText(in: controller.view).contains(presentation.emptyTitle) }
        XCTAssertTrue(empty)
        XCTAssertFalse(renderedAccessibilityText(in: controller.view).contains(firstID))
        XCTAssertFalse(renderedAccessibilityText(in: controller.view).contains(secondID))
        for (url, bytes) in sources { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        attach("empty")
    }

    @MainActor
    func testDashboardAnalyticsRoutesLoadAndRefreshTheirRootHistory() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let controller = UIHostingController(rootView: AnyView(EmptyView()))
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        let routes: [(String, DashboardDestination)] = [("report", .yieldReport), ("trends", .trends)]
        for (name, route) in routes {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixtureID = String(UUID().uuidString.prefix(4))
            let treeID = "R-\(fixtureID)"
            let rawID = "RAW-\(fixtureID)"
            let invalidID = "BAD-\(fixtureID)"
            for (filename, identity, date) in [
                ("older", treeID, "2026-09-30 00:00:00"),
                ("latest", treeID, "2026-10-01 00:00:00"),
                ("raw", rawID, "2026-10-02 00:00:00"),
                ("invalid", invalidID, "2026-10-02 00:00:00")
            ] {
                try PLYPointCloudWriter.write(
                    points: [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)],
                    treeID: identity, scanDate: date, gpsLat: 0, gpsLon: 0,
                    to: directory.appendingPathComponent(filename + ".ply")
                )
            }
            let olderMetadata = directory.appendingPathComponent("older_result.json")
            let latestMetadata = directory.appendingPathComponent("latest_result.json")
            func writeMetadata(count: Int, yield: Double, to url: URL) throws {
                try JSONSerialization.data(withJSONObject: [
                    "fruitCount": count, "yieldKg": yield, "fruitType": "apple", "confidence": "medium"
                ]).write(to: url)
            }
            try writeMetadata(count: 9, yield: 1.5, to: olderMetadata)
            try writeMetadata(count: 0, yield: 0, to: latestMetadata)
            try Data("invalid result".utf8).write(to: directory.appendingPathComponent("invalid_result.json"))
            let sourceBytes = try Dictionary(uniqueKeysWithValues: ["older", "latest", "raw", "invalid"].map {
                let url = directory.appendingPathComponent($0 + ".ply")
                return (url, try Data(contentsOf: url))
            })
            let dependencies = AppDependencies(scanRepository: ScanRepository(scansDirectory: directory))
            XCTAssertTrue(dependencies.historyStore.scanFiles.isEmpty, "The entry must load a cold root store")
            let suiteName = "RootAnalyticsTests-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let dashboard = DashboardView(
                router: NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter()),
                historyStore: dependencies.historyStore
            )
            controller.rootView = AnyView(dashboard.sheetView(for: route)
                .environment(\.locale, Locale(identifier: "en_US_POSIX")).id(name))
            controller.view.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            func waitForText(_ expected: String) async throws -> String {
                var text = ""
                let deadline = Date().addingTimeInterval(3)
                repeat {
                    controller.view.layoutIfNeeded()
                    text = renderedAccessibilityText(in: controller.view)
                    if !dependencies.historyStore.isLoading, text.contains(expected) { break }
                    try await Task.sleep(nanoseconds: 20_000_000)
                } while Date() < deadline
                return text
            }
            func attach(_ phase: String) {
                let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
                })
                attachment.name = "RootAnalytics-\(name)-\(phase)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            let initialText = try await waitForText(treeID)
            attach("initial")
            XCTAssertTrue(initialText.contains(treeID), "\(name) must load its Dashboard root archive: \(initialText)")
            guard initialText.contains(treeID) else { continue }
            XCTAssertEqual(dependencies.historyStore.scanFiles.count, 4)
            XCTAssertFalse(initialText.contains(rawID))
            XCTAssertFalse(initialText.contains(invalidID))
            XCTAssertTrue(initialText.contains("0.0"), "A complete zero must remain visible")
            XCTAssertEqual(initialText.contains("1.5"), name == "trends",
                           "Report uses the latest complete value; trends keeps both historical values")

            try writeMetadata(count: 3, yield: 0.7, to: latestMetadata)
            await dependencies.historyStore.reloadRecords()
            let refreshedText = try await waitForText("0.7")
            XCTAssertTrue(refreshedText.contains("0.7"), "Published root refresh must update the actual consumer")
            XCTAssertEqual(refreshedText.contains("1.5"), name == "trends")
            XCTAssertFalse(refreshedText.contains(rawID))
            XCTAssertFalse(refreshedText.contains(invalidID))
            attach("refreshed")

            // Only owned fixture sidecars are removed, leaving all PLY sources incomplete.
            try FileManager.default.removeItem(at: olderMetadata)
            try FileManager.default.removeItem(at: latestMetadata)
            await dependencies.historyStore.reloadRecords()
            let emptyKey = name == "report" ? "yield_report.empty_title" : "trends.empty_title"
            let emptyTitle = Bundle.main.localizedString(forKey: emptyKey, value: nil, table: nil)
            let emptyText = try await waitForText(emptyTitle)
            XCTAssertTrue(emptyText.contains(emptyTitle))
            XCTAssertFalse(emptyText.contains(treeID))
            attach("empty")
            for (url, bytes) in sourceBytes { XCTAssertEqual(try Data(contentsOf: url), bytes) }
        }
    }

    @MainActor
    func testPointCloudCloseControlDismissesItsPresentedSheet() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("close-preview.ply")
        try PLYPointCloudWriter.write(
            points: [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)],
            treeID: "CLOSE-PREVIEW", scanDate: "2026-10-02 00:00:00", gpsLat: 0, gpsLon: 0, to: source
        )
        let sourceBytes = try Data(contentsOf: source)
        let dependencies = AppDependencies(scanRepository: ScanRepository(scansDirectory: directory))
        await dependencies.historyStore.reloadRecords()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let controller = UIHostingController(rootView: PointCloudDismissalTestHost(historyStore: dependencies.historyStore))
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        window.layoutIfNeeded()
        defer {
            controller.presentedViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        func closeControl(in root: NSObject) -> NSObject? {
            var visited = Set<ObjectIdentifier>()
            func visit(_ object: NSObject, depth: Int = 0) -> NSObject? {
                guard depth < 32, visited.insert(ObjectIdentifier(object)).inserted else { return nil }
                if object.accessibilityLabel == L10n.PointCloud.closePreviewAccessibility,
                   object.accessibilityTraits.contains(.button) { return object }
                let count = object.accessibilityElementCount()
                if count > 0 && count < 100 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject,
                           let found = visit(child, depth: depth + 1) { return found }
                    }
                }
                if let view = object as? UIView {
                    for child in view.subviews {
                        if let found = visit(child, depth: depth + 1) { return found }
                    }
                }
                return nil
            }
            return visit(root)
        }
        let presentationDeadline = Date().addingTimeInterval(3)
        var button: NSObject?
        repeat {
            if let presented = controller.presentedViewController {
                presented.view.layoutIfNeeded()
                if presented.transitionCoordinator == nil, !presented.isBeingPresented {
                    button = closeControl(in: presented.view)
                }
            }
            if button != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < presentationDeadline
        XCTAssertNotNil(controller.presentedViewController)
        let renderedText = controller.presentedViewController.map { renderedAccessibilityText(in: $0.view) } ?? "no sheet"
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
        })
        attachment.name = "PresentedPointCloud-CloseControl"
        attachment.lifetime = .keepAlways
        add(attachment)
        let closeButton = try XCTUnwrap(button, "The presented production preview must expose its visible close control: \(renderedText)")
        XCTAssertTrue(closeButton.accessibilityActivate(), "The actual accessibility control must handle activation")
        let dismissalDeadline = Date().addingTimeInterval(3)
        while controller.presentedViewController != nil, Date() < dismissalDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNil(controller.presentedViewController, "The visible preview close control must dismiss the outer sheet")
        XCTAssertTrue(renderedAccessibilityText(in: controller.view).contains("PREVIEW-HOST"))
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
    }

    @MainActor
    func testDashboardPointCloudRouteKeepsRootSelectionAcrossHistoryRefreshes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureID = String(UUID().uuidString.prefix(4))
        let initialURL = directory.appendingPathComponent("preview-a.ply")
        let nextURL = directory.appendingPathComponent("preview-b.ply")
        let initialTreeID = "A-\(fixtureID)"
        let nextTreeID = "B-\(fixtureID)"
        let points = [
            ColoredPoint(pos: SIMD3<Float>(0, 0, 0), r: 1, g: 0, b: 0),
            ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 0, g: 1, b: 0)
        ]
        try PLYPointCloudWriter.write(points: points, treeID: initialTreeID,
                                      scanDate: "2026-10-01 00:00:00", gpsLat: 0, gpsLon: 0, to: initialURL)
        let initialBytes = try Data(contentsOf: initialURL)
        let dependencies = AppDependencies(scanRepository: ScanRepository(scansDirectory: directory))
        await dependencies.historyStore.reloadRecords()
        XCTAssertEqual(dependencies.historyStore.scanFiles.map(\.treeID), [initialTreeID])
        let suiteName = "RootPreviewTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let dashboard = DashboardView(
            router: NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter()),
            historyStore: dependencies.historyStore
        )
        // Exercise the production sheet factory, without inventing an external route.
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(dashboard.sheetView(for: .pointCloud(initialURL)))
        let controller = ui.controller
        let window = ui.window

        func currentView() -> UIView {
            var current = controller as UIViewController
            while let presented = current.presentedViewController { current = presented }
            return current.view
        }

        func accessibleElements(in object: NSObject) -> [NSObject] {
            var visited = Set<ObjectIdentifier>()
            func visit(_ object: NSObject, depth: Int = 0) -> [NSObject] {
                guard depth < 32, visited.insert(ObjectIdentifier(object)).inserted else { return [] }
                // UIKit retains removed List cells during updates. Their raw subviews
                // are not announced: the retired ancestor is hidden and has no index path.
                if let view = object as? UIView,
                   view.isHidden || view.alpha == 0 || view.accessibilityElementsHidden { return [] }
                var elements = [object]
                let count = object.accessibilityElementCount()
                if count > 0 && count < 100 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject {
                            elements += visit(child, depth: depth + 1)
                        }
                    }
                }
                if let view = object as? UIView {
                    elements += view.subviews.flatMap { visit($0, depth: depth + 1) }
                }
                return elements
            }
            return visit(object)
        }
        func currentText() -> String {
            accessibleElements(in: currentView()).flatMap {
                [$0.accessibilityLabel, $0.accessibilityValue].compactMap { $0 }
            }.joined(separator: " | ")
        }
        func selectedLabels() -> Set<String> {
            Set(accessibleElements(in: currentView()).filter { $0.accessibilityTraits.contains(.selected) }
                .compactMap(\.accessibilityLabel).filter { [initialTreeID, nextTreeID].contains($0) })
        }
        func waitForText(_ expected: String, selected: String? = nil, excluding removed: String? = nil) async throws -> String {
            var text = ""
            let deadline = Date().addingTimeInterval(3)
            repeat {
                controller.view.layoutIfNeeded()
                text = currentText()
                if !dependencies.historyStore.isLoading, text.contains(expected),
                   removed.map({ !text.contains($0) }) ?? true,
                   selected.map({ selectedLabels() == [$0] }) ?? true { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            } while Date() < deadline
            return text
        }
        func attach(_ name: String) {
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            })
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            let text = XCTAttachment(string: currentText())
            text.name = "\(name)-accessibility"
            text.lifetime = .keepAlways
            add(text)
        }
        let chooserLabel = "\(WorkspaceText.chooseArchive)，\(initialTreeID)"
        let chooserReady = try await ui.waitFor { ui.element(label: chooserLabel) != nil }
        XCTAssertTrue(chooserReady, "The actual viewer must expose the archive chooser")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: chooserLabel)).accessibilityActivate())
        let pickerPresented = try await ui.waitFor { controller.presentedViewController != nil }
        XCTAssertTrue(pickerPresented)
        let initialText = try await waitForText(initialTreeID, selected: initialTreeID)
        attach("RootPreview-Initial")
        XCTAssertTrue(initialText.contains(initialTreeID), "Preview must use the Dashboard root archive: \(initialText)")
        XCTAssertEqual(try Data(contentsOf: initialURL), initialBytes)
        guard initialText.contains(initialTreeID) else { return }
        XCTAssertEqual(selectedLabels(), [initialTreeID])

        try PLYPointCloudWriter.write(points: points, treeID: nextTreeID,
                                      scanDate: "2026-10-02 00:00:00", gpsLat: 0, gpsLon: 0, to: nextURL)
        let nextBytes = try Data(contentsOf: nextURL)
        await dependencies.historyStore.reloadRecords()
        XCTAssertEqual(dependencies.historyStore.scanFiles.first?.fileURL, nextURL)
        let refreshedText = try await waitForText(nextTreeID, selected: initialTreeID)
        XCTAssertTrue(refreshedText.contains(nextTreeID))
        XCTAssertEqual(selectedLabels(), [initialTreeID], "A new newest record must not replace the explicit selection")
        XCTAssertEqual(try Data(contentsOf: initialURL), initialBytes)
        XCTAssertEqual(try Data(contentsOf: nextURL), nextBytes)

        // Remove only temporary test-owned sources; this is not user archive deletion.
        try FileManager.default.removeItem(at: initialURL)
        await dependencies.historyStore.reloadRecords()
        XCTAssertEqual(dependencies.historyStore.scanFiles.map(\.fileURL), [nextURL])
        let fallbackText = try await waitForText(nextTreeID, selected: nextTreeID, excluding: initialTreeID)
        var retainedObjects: [String] = []
        var retainedVisited = Set<ObjectIdentifier>()
        func describeRetained(_ object: NSObject, path: String, ancestors: [UIView], depth: Int = 0) {
            guard depth < 32, retainedVisited.insert(ObjectIdentifier(object)).inserted else { return }
            let lineage = ancestors + ((object as? UIView).map { [$0] } ?? [])
            if object.accessibilityLabel?.contains(initialTreeID) == true {
                let descriptions = lineage.map { view in
                    var details = "\(type(of: view)) hidden=\(view.isHidden) alpha=\(view.alpha) frame=\(view.frame) window=\(view.window != nil)"
                    if let cell = view as? UICollectionViewCell,
                       let collection = lineage.compactMap({ $0 as? UICollectionView }).last {
                        details += " indexPath=\(String(describing: collection.indexPath(for: cell))) visible=\(collection.visibleCells.contains { $0 === cell })"
                    }
                    return details
                }
                retainedObjects.append("\(path) \(type(of: object)) frame=\(object.accessibilityFrame)\n" + descriptions.joined(separator: "\n"))
            }
            let count = object.accessibilityElementCount()
            if count > 0 && count < 100 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject {
                        describeRetained(child, path: "\(path)/AX[\(index)]", ancestors: lineage, depth: depth + 1)
                    }
                }
            }
            if let view = object as? UIView {
                for (index, child) in view.subviews.enumerated() {
                    describeRetained(child, path: "\(path)/view[\(index)]", ancestors: lineage, depth: depth + 1)
                }
            }
        }
        describeRetained(currentView(), path: "modal", ancestors: [])
        let retainedAttachment = XCTAttachment(string: retainedObjects.joined(separator: "\n"))
        retainedAttachment.name = "RootPreview-RetainedObjects"
        retainedAttachment.lifetime = .keepAlways
        add(retainedAttachment)
        XCTAssertTrue(fallbackText.contains(nextTreeID))
        XCTAssertFalse(fallbackText.contains(initialTreeID), "Removed record is still announced: \(fallbackText)")
        XCTAssertEqual(selectedLabels(), [nextTreeID], "A missing selection must fall back within the same root")
        XCTAssertEqual(try Data(contentsOf: nextURL), nextBytes)
        attach("RootPreview-Fallback")

        try FileManager.default.removeItem(at: nextURL)
        await dependencies.historyStore.reloadRecords()
        XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.done)).accessibilityActivate())
        let pickerDismissed = try await ui.waitFor { controller.presentedViewController == nil }
        XCTAssertTrue(pickerDismissed)
        let emptyText = try await waitForText(L10n.PointCloud.emptyTitle)
        XCTAssertTrue(emptyText.contains(L10n.PointCloud.emptyTitle))
        XCTAssertTrue(emptyText.contains(L10n.PointCloud.newScan))
        XCTAssertTrue(emptyText.contains(L10n.PointCloud.importPLY))
        XCTAssertFalse(emptyText.contains(nextTreeID))
        attach("RootPreview-Empty")
    }

    @MainActor
    func testDashboardSectionHeaderKeepsViewAllHitAreaAtSupportedTextSizes() async throws {
        for textSize: DynamicTypeSize in [.large, .accessibility3] {
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            var activations = 0
            ui.mount(DashboardSectionHeader(title: L10n.Dashboard.recentScans,
                                             actionTitle: L10n.Dashboard.viewAll, onAction: { activations += 1 })
                .padding(24).dynamicTypeSize(textSize))
            let ready = try await ui.waitFor { ui.element(label: L10n.Dashboard.viewAll) != nil }
            XCTAssertTrue(ready)
            let action = try XCTUnwrap(ui.element(label: L10n.Dashboard.viewAll))
            XCTAssertGreaterThanOrEqual(action.accessibilityFrame.width, 43.5)
            XCTAssertGreaterThanOrEqual(action.accessibilityFrame.height, 43.5)
            XCTAssertTrue(action.accessibilityActivate())
            XCTAssertEqual(activations, 1)
        }
    }

    @MainActor
    func testHistoryRowKeepsLongIdentityAndActionsInsideAtLargestTextSize() async throws {
        let record = makeRecord(id: "history-long-controls", treeID: "UI-HISTORY-CANCEL", scanDate: Date(), yieldKg: 4.2)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        var previews = 0
        var shares = 0
        ui.mount(ScrollView {
            ScanHistoryRow(record: record, onPreview: { previews += 1 }, onShare: { shares += 1 },
                           onRescan: {}, onMarkReview: {}, onDelete: {})
                .padding(24)
        }.workspacePage(background: Design.Colors.Workspace.surface).dynamicTypeSize(.accessibility5))
        let previewLabel = NSLocalizedString("history.row.preview_point_cloud", value: "Preview Point Cloud", comment: "")
        // 收敛后行内只有行尾一个「更多」入口；预览点云在菜单里（能力保留，入口唯一）。
        XCTAssertNil(ui.element(label: previewLabel), "预览点云不该再是行内按钮")
        let ready = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(ready)
        // 行内只剩一个尾部入口：它在最大动态字号下也必须够得着、看得见。
        // （菜单里有哪些动作由 testHistoryRowOffersEachActionOnlyOnce 断言；
        //   这个宿主里 AX 树在截图挂载后偶发变化，菜单内容不在这里取。）
        try await ui.attach(to: self, phase: "History-controls-AX5-\(WorkspaceText.evidence)-synthetic")
        let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.max { $0.bounds.height < $1.bounds.height })
        let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: nil)
            .intersection(ui.window.bounds)
        let more = try await ui.reveal(L10n.History.moreActions, in: scroll)
        XCTAssertGreaterThanOrEqual(more.accessibilityFrame.height, 43.5)
        XCTAssertTrue(viewport.insetBy(dx: -0.5, dy: -0.5).contains(more.accessibilityFrame),
                      "更多入口: \(more.accessibilityFrame) must fit \(viewport)")
    }

    /// 回归：档案行 → 归档详情，走真实根入口。
    /// 定位必须按存档身份：同一棵树的两次扫描不能串。
    ///
    /// 覆盖范围说明：这条只管「进得去、进去的是**这一条**、读数区块都在」。
    /// **返回后的筛选 / 滚动 / 选中 / 焦点恢复**由可运行的原生 UI 测试负责
    /// （`FruitTreeScannerUITests/ArchiveRoundTripUITests`，
    /// 运行器 `tools/validate_archive_round_trip_ui.py`）——
    /// 宿主测试环境里导航栏返回按钮的 AX 激活无效，这里断言不了返回。
    @MainActor
    func testHistoryRowOpensArchiveDetailByArchiveIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // 同一棵树扫了两次：两个存档编号
        for (index, name) in ["T-01-a.ply", "T-01-b.ply"].enumerated() {
            try PLYPointCloudWriter.write(
                points: [ColoredPoint(pos: SIMD3<Float>(0, 1, 0), r: 0.3, g: 0.7, b: 0.2)],
                treeID: "T-01", scanDate: "2026-10-1\(index) 10:00:00", gpsLat: 0, gpsLon: 0,
                to: directory.appendingPathComponent(name)
            )
        }
        let repository = ScanRepository(scansDirectory: directory)
        let store = ScanHistoryStore(repository: repository)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack { ScanHistoryView(historyStore: store) })

        let appeared = try await ui.waitFor { ui.element(label: "T-01-a.ply") != nil }
        XCTAssertTrue(appeared, "档案行必须出现")
        let row = try XCTUnwrap(ui.element(label: "T-01-a.ply"))
        XCTAssertTrue(row.accessibilityActivate(), "点档案行要能进详情")

        let detailSection = L10n.History.detailIdentityTitle
        let opened = try await ui.waitFor { ui.element(label: detailSection) != nil }
        XCTAssertTrue(opened, "点行必须进入归档详情")
        XCTAssertNotNil(ui.element(label: "T-01-a.ply"),
                        "详情要显示这一条自己的存档身份，不能串到同树的另一条")

        // 返回入口必须存在（标签随系统语言而变：Back / 返回 / 上一个标题）。
        // 说明：宿主测试环境里导航栏返回按钮的 AX 激活不生效（候选元素与按钮都返回 false），
        // 因此这里只断言「返回入口在」；真正的返回往返由 ArchiveRoundTripUITests 覆盖。
        let hasBackAffordance = ui.elements.contains { element in
            let label = element.accessibilityLabel ?? ""
            return label == "Back" || label == "返回" || label == L10n.History.navigationTitle
        }
        XCTAssertTrue(hasBackAffordance, "详情必须提供返回入口")
        // 详情是推进：只有详情在 AX 树里（被覆盖的列表不再暴露元素，这是系统行为）。
        XCTAssertNil(ui.element(label: "T-01-b.ply"), "推进后下面的列表不应继续暴露元素")
        XCTAssertNotNil(ui.element(label: L10n.History.detailReadingTitle), "详情要有读数区")
        XCTAssertNotNil(ui.element(label: L10n.History.detailSourceTitle), "详情要有来源与完整性区")
    }

    /// 回归：详情里的读数只认结果文件。
    /// 只有点云、没有结果文件的档案，不能显示成「0.0 kg」冒充一次成功读取。
    @MainActor
    func testArchiveDetailReportsUnavailableReadingInsteadOfFakeZero() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try PLYPointCloudWriter.write(
            points: [ColoredPoint(pos: SIMD3<Float>(0, 1, 0), r: 0.3, g: 0.7, b: 0.2)],
            treeID: "T-02", scanDate: "2026-10-18 10:00:00", gpsLat: 0, gpsLon: 0,
            to: directory.appendingPathComponent("no-result.ply")
        )
        let repository = ScanRepository(scansDirectory: directory)
        let loader = ScanArchiveDetailLoader(repository: repository)

        let detail = try loader.load(recordID: "no-result.ply")
        XCTAssertEqual(detail.recordID, "no-result.ply")
        XCTAssertEqual(detail.treeID, "T-02")
        if case .available(let fruitCount, let yieldKg) = detail.reading {
            XCTFail("没有结果文件的档案不能报出读数（\(fruitCount) 果 / \(yieldKg) kg）")
        }
        // 文件层面：没有完成清单的档案本身就不完整 —— 完整性与「有没有估产」是两件事
        XCTAssertEqual(detail.fileIntegrity, .incomplete)
        XCTAssertNil(detail.reliability, "没有算法结论时可靠性写「未提供」，不推高置信度")
    }

    @MainActor
    func testArchiveDetailRevalidatesCachedCompleteRecordAfterCompanionChanges() throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        let repository = ScanRepository(scansDirectory: fixture.directory)
        let loader = ScanArchiveDetailLoader(repository: repository)
        for corruptManifest in [false, true] {
            let files = try fixture.writeArchive(
                baseName: corruptManifest ? "cached-manifest" : "cached-legacy",
                treeID: "T-57", fruitCount: 9, yieldKg: 2.25,
                exportRevision: corruptManifest ? "rev-1" : nil,
                manifestMode: corruptManifest ? .matching : .none
            )
            let cached = try XCTUnwrap(repository.summary(at: files.plyURL))
            XCTAssertEqual(cached.persistenceState, .complete)
            if corruptManifest {
                try Data("broken manifest".utf8).write(to: files.manifestURL)
            } else {
                fixture.removeCompanion(files)
            }
            let source = try Data(contentsOf: files.plyURL)
            let detail = try loader.load(record: cached)
            XCTAssertEqual(detail.fileIntegrity, corruptManifest ? .invalid : .incomplete,
                           "当前伴随文件核验失败，不能沿用列表缓存的完整状态")
            guard case .unavailable = detail.reading else {
                return XCTFail("当前结果读不到时不能显示缓存读数")
            }
            XCTAssertNil(detail.reliability, "缺失或失效结果不能继续显示缓存置信度")
            XCTAssertEqual(try Data(contentsOf: files.plyURL), source)
        }
    }

    @MainActor
    func testArchiveDetailRejectsCachedRecordWhenPLYIsGoneOrInvalid() throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        let repository = ScanRepository(scansDirectory: fixture.directory)
        let loader = ScanArchiveDetailLoader(repository: repository)
        for removeSource in [false, true] {
            let files = try fixture.writeArchive(
                baseName: removeSource ? "cached-gone" : "cached-invalid",
                treeID: "T-58", fruitCount: 8, yieldKg: 2
            )
            let cached = try XCTUnwrap(repository.summary(at: files.plyURL))
            let originalResult = try Data(contentsOf: files.metadataURL)
            if removeSource {
                try FileManager.default.removeItem(at: files.plyURL)
            } else {
                try Data("not a PLY".utf8).write(to: files.plyURL)
            }
            XCTAssertThrowsError(try loader.load(record: cached),
                                 "遗留的旧格式结果文件不能独立证明源档案仍然有效") { error in
                if removeSource {
                    XCTAssertEqual(error as? ScanArchiveDetailLoader.LoadFailure, .recordMissing)
                } else if case .resultUnavailable = error as? ScanArchiveDetailLoader.LoadFailure {
                    // 源文件仍在但损坏，不能误报成已经删除。
                } else {
                    XCTFail("损坏的源文件应报告读取失败：\(error)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: files.metadataURL), originalResult)
        }
    }

    @MainActor
    func testArchiveDetailReadsCurrentIdentityAndSizeAfterCachedRecordIsReplaced() throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        let repository = ScanRepository(scansDirectory: fixture.directory)
        let loader = ScanArchiveDetailLoader(repository: repository)
        let files = try fixture.writeArchive(
            baseName: "cached-replaced", treeID: "T-59", fruitCount: 3, yieldKg: 1
        )
        let cached = try XCTUnwrap(repository.summary(at: files.plyURL))
        fixture.removeArchive(files)
        try fixture.writeArchive(
            baseName: "cached-replaced", treeID: "T-60", scanDate: "2026-10-21 11:00:00",
            fruitCount: 12, yieldKg: 4.5, fruitType: "pear", confidence: "medium", pointCount: 9
        )
        let bytes = try Data(contentsOf: files.plyURL)
        let detail = try loader.load(record: cached)
        XCTAssertEqual(detail, try loader.load(recordID: cached.id),
                       "同路径已经换档，身份、日期、类别、置信度和文件大小也必须来自本次读取")
        XCTAssertEqual(detail.recordID, cached.id)
        XCTAssertEqual(detail.treeID, "T-60")
        XCTAssertEqual(detail.fruitType, "pear")
        XCTAssertEqual(detail.reliability, "medium")
        XCTAssertEqual(detail.fileSizeBytes, bytes.count)
        XCTAssertEqual(detail.reading, .available(fruitCount: 12, yieldKg: 4.5))
        XCTAssertEqual(try Data(contentsOf: files.plyURL), bytes)
    }

    @MainActor
    func testArchiveDetailOpeningWithStaleHistoryDoesNotRenderCompleteIntegrity() async throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        let files = try fixture.writeArchive(
            baseName: "cached-opening", treeID: "T-61", fruitCount: 9, yieldKg: 2.25
        )
        let store = ScanHistoryStore(repository: ScanRepository(scansDirectory: fixture.directory))
        await store.reloadRecords()
        XCTAssertEqual(store.scanFiles.first?.persistenceState, .complete)
        fixture.removeCompanion(files)
        let source = try Data(contentsOf: files.plyURL)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanArchiveDetailView(recordID: files.plyURL.lastPathComponent, historyStore: store)
        })
        let loaded = try await ui.waitFor { ui.element(label: L10n.History.detailSourceTitle) != nil }
        XCTAssertTrue(loaded)
        XCTAssertEqual(store.scanFiles.first?.persistenceState, .complete,
                       "本回归必须保持列表缓存，不能通过刷新列表绕过详情的重新核验")
        XCTAssertNotNil(ui.element(label: L10n.History.integrityIncomplete))
        XCTAssertNil(ui.element(label: L10n.History.integrityComplete))
        XCTAssertNotNil(ui.element(label: L10n.History.detailResultUnavailable))
        XCTAssertNil(ui.element(label: L10n.Dashboard.fruitCountLabel(9)))
        XCTAssertEqual(try Data(contentsOf: files.plyURL), source)
        try await writeArchiveRowScreenshot(ui, name: "ArchiveDetail-cached-integrity-revalidated")
    }

    /// 回归：读到的记录按存档身份定位；同树的另一条不会被读出来。
    @MainActor
    func testArchiveDetailLoadsTheRecordByArchiveIdentityNotTreeID() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["T-03-a.ply", "T-03-b.ply"] {
            try PLYPointCloudWriter.write(
                points: [ColoredPoint(pos: SIMD3<Float>(0, 1, 0), r: 0.3, g: 0.7, b: 0.2)],
                treeID: "T-03", scanDate: "2026-10-18 10:00:00", gpsLat: 0, gpsLon: 0,
                to: directory.appendingPathComponent(name)
            )
        }
        let loader = ScanArchiveDetailLoader(repository: ScanRepository(scansDirectory: directory))

        let detail = try loader.load(recordID: "T-03-b.ply")
        XCTAssertEqual(detail.recordID, "T-03-b.ply", "必须读回被指定的那一条")
        XCTAssertEqual(detail.treeID, "T-03")

        XCTAssertThrowsError(try loader.load(recordID: "not-a-record.ply")) { error in
            XCTAssertEqual(error as? ScanArchiveDetailLoader.LoadFailure, .recordMissing)
        }
    }

    /// 回归：换一条记录时，早先那次读取的回调不得覆盖后来的选择。
    @MainActor
    func testArchiveDetailControllerIgnoresStaleReadWhenSelectionChanges() async throws {
        func makeDetail(recordID: String) -> ScanArchiveDetail {
            ScanArchiveDetail(
                recordID: recordID,
                treeID: "T-04",
                scanDate: Date(timeIntervalSince1970: 1_792_300_000),
                fruitType: "",
                fileURL: URL(fileURLWithPath: "/tmp/\(recordID)"),
                fileSizeBytes: 0,
                fileIntegrity: .complete,
                reliability: nil,
                reading: .available(fruitCount: 3, yieldKg: 1.5)
            )
        }
        let detailA = makeDetail(recordID: "T-04-a.ply")
        let detailB = makeDetail(recordID: "T-04-b.ply")
        let gate = ArchiveReadGate()
        let controller = ScanArchiveDetailController(read: { request in
            let recordID: String
            switch request {
            case .recordID(let id): recordID = id
            case .record(let record): recordID = record.id
            }
            if recordID == "T-04-a.ply" {
                // 第一次读卡在这里，等第二次读落地之后才回来。
                await gate.wait()
                return detailA
            }
            return detailB
        })
        controller.load(recordID: "T-04-a.ply")
        controller.load(recordID: "T-04-b.ply")

        // 等第二次读取落地
        var settled = false
        for _ in 0..<100 {
            if case .loading = controller.state {} else { settled = true; break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(settled, "第二次读取应当落地")

        // 现在放行第一次读：它回来得比新选择晚，必须被丢掉。
        // （取消只能挡住还在等的东西；已经发出的读照样会回来 —— 挡住它的是令牌。）
        gate.release()
        try await Task.sleep(nanoseconds: 300_000_000)
        if case .loaded(let loaded) = controller.state {
            XCTAssertEqual(loaded.recordID, "T-04-b.ply", "旧回调不得覆盖新的选择")
        } else {
            XCTFail("状态应落在第二条记录上，实际：\(controller.state)")
        }
    }

    /// 回归：档案目录读不到，与「这一条记录不在了」，是两件不同的事。
    /// 目录读不到时说「记录不在」，会把一次临时故障说成数据丢失。
    @MainActor
    func testArchiveDetailDistinguishesUnreadableArchiveFromMissingRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try PLYPointCloudWriter.write(
            points: [ColoredPoint(pos: SIMD3<Float>(0, 1, 0), r: 0.3, g: 0.7, b: 0.2)],
            treeID: "T-05", scanDate: "2026-10-18 10:00:00", gpsLat: 0, gpsLon: 0,
            to: directory.appendingPathComponent("T-05-a.ply")
        )
        let readable = ScanRepository(scansDirectory: directory)
        guard case .success(let records) = readable.loadHistoryRecords(),
              let record = records.first else {
            XCTFail("应当读得到这一条存档")
            return
        }

        // 同一个仓储，但「目录」其实是个文件：枚举器建不起来 —— 这一次是真的读不到。
        let brokenPath = directory.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: brokenPath)
        let loader = ScanArchiveDetailLoader(
            repository: ScanRepository(scansDirectory: brokenPath)
        )
        XCTAssertThrowsError(try loader.load(recordID: record.id)) { error in
            XCTAssertEqual(
                error as? ScanArchiveDetailLoader.LoadFailure,
                .archiveUnavailable,
                "目录读不到要与「记录不在」分开说"
            )
        }
        // 用档案页已经加载好的那一条读：不必再扫目录。
        let detail = try loader.load(record: record)
        XCTAssertEqual(detail.recordID, record.id)
        XCTAssertEqual(detail.treeID, "T-05")
    }

    /// 回归：归档详情「读不到」时必须给重试出口。
    ///
    /// 档案目录读不到是**临时**故障：失败文案让用户「稍后再试」，
    /// 但失败态此前只有标题与说明，**没有任何可点的重试** ——
    /// 用户只能退出详情再进一次；那条记录一旦从档案列表掉下去，就再也回不来。
    ///
    /// 走的是真实链路：真实文件 → 真实仓储 → 真实 ScanArchiveDetailController
    /// → 真实归档详情视图 → 真实按钮动作。
    @MainActor
    func testArchiveDetailUnavailableStateOffersRetryAndRecoversAfterArchiveBecomesReadable() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 「目录」其实是个文件：枚举器建不起来 —— 这一次是真的读不到。
        let scansDirectory = root.appendingPathComponent("scans")
        try Data("not-a-directory".utf8).write(to: scansDirectory)
        // 档案先放在别处，等目录恢复可读时再放进去。
        let stagedDirectory = root.appendingPathComponent("staged")
        try FileManager.default.createDirectory(at: stagedDirectory, withIntermediateDirectories: true)
        try PLYPointCloudWriter.write(
            points: [ColoredPoint(pos: SIMD3<Float>(0, 1, 0), r: 0.3, g: 0.7, b: 0.2)],
            treeID: "T-30", scanDate: "2026-10-29 10:00:00", gpsLat: 0, gpsLon: 0,
            to: stagedDirectory.appendingPathComponent("T-30-a.ply")
        )

        let store = ScanHistoryStore(repository: ScanRepository(scansDirectory: scansDirectory))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanArchiveDetailView(recordID: "T-30-a.ply", historyStore: store)
        })

        // 目录读不到 → 详情必须进入「读不出来」状态。
        let unavailable = try await ui.waitFor { ui.element(identifier: "archiveDetail.unavailable") != nil }
        XCTAssertTrue(unavailable, "目录读不到时必须进入「读不出来」状态")

        // 【关键】失败态必须给出重试出口，否则「稍后再试」只是一句空话。
        let retry = ui.element(identifier: "archiveDetail.retry")
        XCTAssertNotNil(
            retry,
            "读不到时必须提供重试出口（当前 AX 标签：\(ui.accessibilityLabels())；标识：\(ui.accessibilityIdentifiers())）"
        )

        // 目录恢复成真目录并放回这条档案：点重试必须重新读一次，回到已读态。
        try FileManager.default.removeItem(at: scansDirectory)
        try FileManager.default.createDirectory(at: scansDirectory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: stagedDirectory.appendingPathComponent("T-30-a.ply"),
            to: scansDirectory.appendingPathComponent("T-30-a.ply")
        )

        if let retry {
            XCTAssertTrue(retry.accessibilityActivate(), "点重试必须触发重新读取")
            let loaded = try await ui.waitFor { ui.element(label: L10n.History.detailIdentityTitle) != nil }
            XCTAssertTrue(loaded, "目录恢复后点重试必须读到这条归档")
            XCTAssertNotNil(ui.element(label: "T-30-a.ply"), "详情必须显示这一条自己的存档身份")
        }
    }

    /// 回归：归档详情的重试出口在**紧凑宽度 + 辅助字号**下仍然看得见、点得到，并且真的能恢复。
    ///
    /// 可见性按真实几何算：控件的无障碍帧（屏幕坐标）必须与窗口的屏幕矩形相交 ——
    /// 只在 AX 树里出现、其实被挤出可视区，就不算「看得见」。
    /// 文案按**当前语言**解析：界面必须显示本地化后的重试文案，不能是写死的一句。
    ///
    /// 走真实链路：真实文件 → 真实仓储 → 真实控制器 → 真实详情视图 → 真实按钮动作。
    @MainActor
    func testArchiveDetailRetryStaysVisibleAndRecoversAtCompactAccessibilitySize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // 「目录」其实是个文件：枚举器建不起来 —— 这一次是真的读不到。
        let scansDirectory = root.appendingPathComponent("scans")
        try Data("not-a-directory".utf8).write(to: scansDirectory)
        let stagedDirectory = root.appendingPathComponent("staged")
        try FileManager.default.createDirectory(at: stagedDirectory, withIntermediateDirectories: true)
        try PLYPointCloudWriter.write(
            points: [ColoredPoint(pos: SIMD3<Float>(0, 1, 0), r: 0.3, g: 0.7, b: 0.2)],
            treeID: "T-31", scanDate: "2026-10-29 11:00:00", gpsLat: 0, gpsLon: 0,
            to: stagedDirectory.appendingPathComponent("T-31-a.ply")
        )

        let store = ScanHistoryStore(repository: ScanRepository(scansDirectory: scansDirectory))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanArchiveDetailView(recordID: "T-31-a.ply", historyStore: store)
                .environment(\.dynamicTypeSize, .accessibility5)
        })

        let unavailable = try await ui.waitFor { ui.element(identifier: "archiveDetail.unavailable") != nil }
        XCTAssertTrue(unavailable, "目录读不到时必须进入「读不出来」状态")

        let found = try await ui.waitFor { ui.element(identifier: "archiveDetail.retry") != nil }
        XCTAssertTrue(found, "读不到时必须提供重试出口")
        let retry = try XCTUnwrap(ui.element(identifier: "archiveDetail.retry"), "重试出口必须存在")

        // 看得见：帧必须落在窗口的屏幕矩形内（辅助字号下按钮不能被挤出屏幕）。
        XCTAssertTrue(
            retry.accessibilityFrame.intersects(ui.screenFrame),
            "重试出口必须在窗口可视区内，实际帧 \(retry.accessibilityFrame)，窗口屏幕矩形 \(ui.screenFrame)"
        )
        // 点得到：不能是禁用状态。
        XCTAssertFalse(
            retry.accessibilityTraits.contains(.notEnabled),
            "重试出口必须是可点的"
        )

        // 文案按当前语言解析：界面显示的必须是**本地化后**的重试文案。
        let expectedLabel = try currentLocaleString(forKey: "history.detail.retry")
        XCTAssertEqual(
            retry.accessibilityLabel,
            expectedLabel,
            "重试出口必须使用本地化文案，实际 \(retry.accessibilityLabel ?? "nil")"
        )
        XCTAssertEqual(
            L10n.History.detailRetry,
            expectedLabel,
            "生产 L10n 必须解析成当前语言的文案"
        )

        // 证据留存：失败态的真实渲染与 AX 文本（只作附件，不参与判定）。
        try await ui.attach(to: self, phase: "archiveDetail.retryUnavailable-\(Locale.preferredLanguages.first ?? "unknown")")

        // 恢复：目录恢复可读后点重试必须真的重新读一次。
        try FileManager.default.removeItem(at: scansDirectory)
        try FileManager.default.createDirectory(at: scansDirectory, withIntermediateDirectories: true)
        try FileManager.default.moveItem(
            at: stagedDirectory.appendingPathComponent("T-31-a.ply"),
            to: scansDirectory.appendingPathComponent("T-31-a.ply")
        )
        XCTAssertTrue(retry.accessibilityActivate(), "点重试必须触发重新读取")
        let loaded = try await ui.waitFor { ui.element(label: L10n.History.detailIdentityTitle) != nil }
        XCTAssertTrue(loaded, "目录恢复后点重试必须读到这条归档")
        XCTAssertNotNil(ui.element(label: "T-31-a.ply"), "详情必须显示这一条自己的存档身份")
        try await ui.attach(to: self, phase: "archiveDetail.retryRecovered-\(Locale.preferredLanguages.first ?? "unknown")")
    }

    /// 回归：重试出口的中英文文案必须成对齐全。
    ///
    /// 界面用语不是「写死一句」：en 与 zh 两个 lproj 都要有，且值要对得上。
    func testArchiveDetailRetryCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "history.detail.retry": "Retry",
                "history.detail.retry_hint": "Read this archive again."
            ],
            "zh": [
                "history.detail.retry": "重试",
                "history.detail.retry_hint": "重新读取这条归档。"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }


    /// 回归：档案列表「分享点云」失败必须说出来。
    ///
    /// 点云是接收方常打不开的文件类型，分享失败现实可达。
    /// 之前档案列表与归档详情都用 `ShareSheet(items:)` 不带完成回调，
    /// UIKit 报的失败被直接丢掉：分享面板关掉后什么也没发生，
    /// 用户以为点云已经分享成功。批量导出早就把同一个失败弹成提示了 —— 口径必须一致。
    ///
    /// 走真实链路：真实文件 → 真实档案行 → 真实行菜单 → 真实 UIActivityViewController
    /// → 真实 UIKit 完成回调 → 真实提示。
    @MainActor
    func testArchiveListShareFailureIsReportedToTheUser() async throws {
        let fixture = try ArchiveShareFixture()
        defer { fixture.cleanUp() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanHistoryView(historyStore: fixture.store, tagStore: fixture.tagStore)
        })

        let listed = try await ui.waitFor { ui.element(label: fixture.recordName) != nil }
        XCTAssertTrue(listed, "档案行必须出现")
        try await ui.selectMenu(label: L10n.History.moreActions, title: L10n.History.sharePointCloud)

        let presented = try await ui.waitFor { ui.presentedActivityViewController() != nil }
        XCTAssertTrue(presented, "分享面板必须真的呈现出来")
        let activity = try XCTUnwrap(ui.presentedActivityViewController())
        XCTAssertNotNil(
            activity.completionWithItemsHandler,
            "分享面板必须接上完成回调，否则 UIKit 报的失败无从上报"
        )

        // 真实顺序：分享面板自己关掉，完成回调随后才来。
        ui.controller.presentedViewController?.dismiss(animated: false)
        let dismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed, "分享面板必须先关掉")
        activity.completionWithItemsHandler?(nil, false, nil, ArchiveShareFixture.makeFailure())

        let reported = try await ui.waitFor { ui.element(label: L10n.History.shareFailureTitle) != nil }
        XCTAssertTrue(reported, "分享失败必须提示用户（当前 AX 标签：\(ui.accessibilityLabels())）")
    }

    /// 回归：用户自己取消分享不算失败，不许弹失败提示。
    @MainActor
    func testArchiveShareCancellationIsNotReportedAsFailure() async throws {
        let fixture = try ArchiveShareFixture()
        defer { fixture.cleanUp() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanHistoryView(historyStore: fixture.store, tagStore: fixture.tagStore)
        })

        let listed = try await ui.waitFor { ui.element(label: fixture.recordName) != nil }
        XCTAssertTrue(listed, "档案行必须出现")
        try await ui.selectMenu(label: L10n.History.moreActions, title: L10n.History.sharePointCloud)

        let presented = try await ui.waitFor { ui.presentedActivityViewController() != nil }
        XCTAssertTrue(presented, "分享面板必须真的呈现出来")
        let activity = try XCTUnwrap(ui.presentedActivityViewController())

        ui.controller.presentedViewController?.dismiss(animated: false)
        let dismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed, "分享面板必须先关掉")
        // 用户取消：没有错误。
        activity.completionWithItemsHandler?(nil, false, nil, nil)

        // 取消不是失败：给满与正向用例同样的等待预算，失败提示仍然必须不出现。
        let appeared = try await ui.waitFor { ui.element(label: L10n.History.shareFailureTitle) != nil }
        XCTAssertFalse(appeared, "用户取消分享不算失败")
    }

    /// 回归：归档详情「分享点云」失败同样必须说出来。
    @MainActor
    func testArchiveDetailShareFailureIsReportedToTheUser() async throws {
        let fixture = try ArchiveShareFixture()
        defer { fixture.cleanUp() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanArchiveDetailView(recordID: fixture.recordName, historyStore: fixture.store)
        })

        let loaded = try await ui.waitFor { ui.element(identifier: "archiveDetail.sharePointCloud") != nil }
        XCTAssertTrue(loaded, "归档详情必须加载出来")
        XCTAssertTrue(
            try XCTUnwrap(ui.element(identifier: "archiveDetail.sharePointCloud")).accessibilityActivate(),
            "点分享点云必须真的打开分享面板"
        )

        let presented = try await ui.waitFor { ui.presentedActivityViewController() != nil }
        XCTAssertTrue(presented, "分享面板必须真的呈现出来")
        let activity = try XCTUnwrap(ui.presentedActivityViewController())
        XCTAssertNotNil(
            activity.completionWithItemsHandler,
            "分享面板必须接上完成回调，否则 UIKit 报的失败无从上报"
        )

        ui.controller.presentedViewController?.dismiss(animated: false)
        let dismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed, "分享面板必须先关掉")
        activity.completionWithItemsHandler?(nil, false, nil, ArchiveShareFixture.makeFailure())

        let reported = try await ui.waitFor { ui.element(label: L10n.History.shareFailureTitle) != nil }
        XCTAssertTrue(reported, "分享失败必须提示用户（当前 AX 标签：\(ui.accessibilityLabels())）")
    }

    /// 回归：点云预览里的「分享点云」失败同样必须说出来。
    ///
    /// 点云预览从档案列表与归档详情都能打开（预览 → 顶栏导出），
    /// 走的是同一个 `ShareSheet`；不带完成回调时 UIKit 的失败同样被丢弃。
    @MainActor
    func testPointCloudViewerShareFailureIsReportedToTheUser() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("point-cloud-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("share-viewer.ply")
        var points: [ColoredPoint] = []
        for index in 0..<64 {
            points.append(ColoredPoint(
                pos: SIMD3<Float>(Float(index % 8) * 0.1, Float(index / 8) * 0.1, 0),
                r: 0.4, g: 0.6, b: 0.3))
        }
        try PLYPointCloudWriter.write(points: points, treeID: "PC-SHARE",
                                     scanDate: "2026-10-29 12:00:00", gpsLat: 0, gpsLon: 0, to: source)

        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(PointCloudView(plyFileURL: source, onClose: {}))

        // 顶栏的分享按钮要等点云真的读进来才可用（读不出来时按钮是禁用的）。
        let loaded = try await ui.waitFor {
            ui.element(label: L10n.PointCloud.pointCountAccessibility("\(points.count)")) != nil
        }
        XCTAssertTrue(loaded, "点云预览必须真的把点云读出来")
        let share = try await ui.waitFor { ui.element(identifier: "pointCloud.share") != nil }
        XCTAssertTrue(share, "点云预览的分享按钮必须出现")
        XCTAssertTrue(
            try XCTUnwrap(ui.element(identifier: "pointCloud.share")).accessibilityActivate(),
            "点分享点云必须真的打开分享面板"
        )

        let presented = try await ui.waitFor { ui.presentedActivityViewController() != nil }
        XCTAssertTrue(presented, "分享面板必须真的呈现出来")
        let activity = try XCTUnwrap(ui.presentedActivityViewController())
        XCTAssertNotNil(
            activity.completionWithItemsHandler,
            "分享面板必须接上完成回调，否则 UIKit 报的失败无从上报"
        )

        // 真实顺序：分享面板自己关掉，完成回调随后才来。
        ui.controller.presentedViewController?.dismiss(animated: false)
        let dismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed, "分享面板必须先关掉")
        activity.completionWithItemsHandler?(nil, false, nil, ArchiveShareFixture.makeFailure())

        let reported = try await ui.waitFor { ui.element(label: L10n.PointCloud.shareFailureTitle) != nil }
        XCTAssertTrue(reported, "分享失败必须提示用户（当前 AX 标签：\(ui.accessibilityLabels())）")
    }

    /// 当前语言对应 lproj 里的文案。
    ///
    /// 运行时语言由设备决定（当前模拟器是中文）；把界面文案与**当前语言**的
    /// lproj 值对齐，才能证明界面确实用了本地化结果，而不是某一处写死的字符串。
    private func currentLocaleString(forKey key: String) throws -> String {
        let language = Locale.preferredLanguages.first ?? "zh-Hans-CN"
        let code = language.lowercased().hasPrefix("zh") ? "zh" : "en"
        let bundle = try XCTUnwrap(
            Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)),
            "Missing \(code) localization bundle for preferred language \(language)"
        )
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    // MARK: - 详情打开期间的档案变化（生产刷新完成之后）

    /// 回归：详情开着的时候档案被删掉 —— 生产刷新完成后，
    /// 页面必须说「这条记录已经不在档案里了」，
    /// 不能继续把旧读数当成当前有效结果，更不能用 0 冒充一次成功读取。
    ///
    /// 走的是真实链路：真实文件 → 真实仓储 → 真实 ScanHistoryStore →
    /// 真实档案行 → 真实归档详情；刷新用生产入口（档案页下拉刷新调的就是它）。
    @MainActor
    func testArchiveDetailStopsShowingDeletedArchiveReadingAfterProductionRefresh() async throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        try fixture.writeArchive(baseName: "T-20-a", treeID: "T-20", fruitCount: 12, yieldKg: 3.5)
        // 同树的另一份：删掉 T-20-a 之后它还在，返回时不能被它顶替。
        try fixture.writeArchive(baseName: "T-20-b", treeID: "T-20", fruitCount: 4, yieldKg: 1.0)
        let store = ScanHistoryStore(repository: ScanRepository(scansDirectory: fixture.directory))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanHistoryView(historyStore: store, tagStore: fixture.tagStore)
        })

        // 打开详情：走真实档案行 → 归档详情。
        let appeared = try await ui.waitFor { ui.element(label: "T-20-a.ply") != nil }
        XCTAssertTrue(appeared, "档案行必须出现")
        let row = try XCTUnwrap(ui.element(label: "T-20-a.ply"))
        XCTAssertTrue(row.accessibilityActivate(), "点档案行要能进详情")
        let opened = try await ui.waitFor { ui.element(label: L10n.History.detailReadingTitle) != nil }
        XCTAssertTrue(opened, "点行必须进入归档详情")
        // 原读数确实在页面上（下面要证明它被撤掉）。
        XCTAssertNotNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(12)),
            "详情要显示这次读数；AX 标签：\(ui.accessibilityLabels())"
        )
        XCTAssertNotNil(
            ui.element(label: String(format: "%.1f", 3.5 as Float)),
            "详情要显示这次产量；AX 标签：\(ui.accessibilityLabels())"
        )

        // 档案被删掉：走生产删除入口（连带清掉 companion，并触发生产刷新）。
        guard case .success(let records) = store.archiveRepository.loadHistoryRecords(),
              let record = records.first(where: { $0.id == "T-20-a.ply" }) else {
            XCTFail("应当读得到刚写的档案")
            return
        }
        let deletion = await store.deleteRecordsWithResult([record])
        XCTAssertTrue(deletion.isComplete, "生产删除必须把档案清干净")
        // 生产刷新完成（档案页下拉刷新用的就是这个入口）。
        await store.reloadRecords()

        let refreshed = try await ui.waitFor(timeout: 10) {
            ui.element(label: L10n.History.detailUnavailableTitle) != nil
        }
        XCTAssertTrue(
            refreshed,
            "档案删掉后详情必须说读不到，而不是继续挂着旧读数；AX 标签：\(ui.accessibilityLabels())"
        )
        // 旧读数必须撤掉。
        XCTAssertNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(12)),
            "旧读数不能继续显示为当前有效结果"
        )
        XCTAssertNil(ui.element(label: String(format: "%.1f", 3.5 as Float)), "旧产量不能继续显示")
        // 不能用 0 冒充一次成功读取。
        XCTAssertNil(ui.element(label: L10n.Dashboard.fruitCountLabel(0)), "不能把 0 果当成读到了")
        XCTAssertNil(ui.element(label: String(format: "%.1f", 0.0 as Float)), "不能把 0.0 kg 当成读到了")
        // 说清是「这条记录不在了」，不是泛泛的失败。
        XCTAssertNotNil(
            ui.element(label: ArchiveDetailRefreshFixture.recordMissingMessage),
            "要说清这条记录已经不在档案里了；AX 标签：\(ui.accessibilityLabels())"
        )
        // 详情仍然是详情页（不是被换成列表）。
        XCTAssertNil(ui.element(label: "T-20-b.ply"), "详情还开着，下面的列表不该继续暴露元素")
        // 删除后返回：不能恢复到同树的另一份。
        XCTAssertEqual(
            ScanHistoryRestoreTarget.resolve(
                openedRecordID: "T-20-a.ply",
                availableRecordIDs: store.scanFiles.map(\.id)
            ),
            .none,
            "删掉的档案返回时不得恢复到同树的另一份"
        )
        XCTAssertTrue(
            store.scanFiles.contains { $0.id == "T-20-b.ply" },
            "同树的另一份必须还在（否则这条断言说明不了问题）"
        )
    }

    /// 回归：只缺 companion（结果文件与清单）时，档案本身还在 ——
    /// 详情要保留这一条的身份，但读数必须说读不到；
    /// 这与「整个档案不在了」是两件事，不能混成一句话。
    @MainActor
    func testArchiveDetailKeepsIdentityButReportsMissingCompanionAfterProductionRefresh() async throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        let archive = try fixture.writeArchive(
            baseName: "T-21-a",
            treeID: "T-21",
            fruitCount: 9,
            yieldKg: 2.25,
            exportRevision: "rev-1",
            manifestMode: .matching
        )
        let store = ScanHistoryStore(repository: ScanRepository(scansDirectory: fixture.directory))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanHistoryView(historyStore: store, tagStore: fixture.tagStore)
        })

        let appeared = try await ui.waitFor { ui.element(label: "T-21-a.ply") != nil }
        XCTAssertTrue(appeared, "档案行必须出现")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: "T-21-a.ply")).accessibilityActivate())
        let opened = try await ui.waitFor { ui.element(label: L10n.History.detailReadingTitle) != nil }
        XCTAssertTrue(opened, "点行必须进入归档详情")
        XCTAssertNotNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(9)),
            "详情要显示这次读数；AX 标签：\(ui.accessibilityLabels())"
        )

        // 只拿掉 companion：点云还在，档案本身没有消失。
        fixture.removeCompanion(archive)
        await store.reloadRecords()

        let refreshed = try await ui.waitFor(timeout: 10) {
            ui.element(label: L10n.History.detailReadingTitle) != nil &&
                ui.element(label: L10n.Dashboard.fruitCountLabel(9)) == nil
        }
        XCTAssertTrue(
            refreshed,
            "只缺 companion 后读数必须变成读不到；AX 标签：\(ui.accessibilityLabels())"
        )
        // 身份还在：还是这一条档案，不是「记录不在了」。
        XCTAssertNotNil(
            ui.element(label: "T-21-a.ply"),
            "档案本身还在，详情必须继续显示这一条；AX 标签：\(ui.accessibilityLabels())"
        )
        XCTAssertNil(
            ui.element(label: L10n.History.detailUnavailableTitle),
            "只缺 companion 不等于整个档案不在了"
        )
        // 读不到就说读不到，不能用 0 冒充。
        XCTAssertNil(ui.element(label: L10n.Dashboard.fruitCountLabel(0)), "不能把 0 果当成读到了")
        XCTAssertNil(ui.element(label: String(format: "%.1f", 0.0 as Float)), "不能把 0.0 kg 当成读到了")
        // 读数位本身要写明「读不到」，不能只是「那个数字不见了」。
        // （区分「整页读不出来」与「读数读不到」靠的是这两个标题：
        //   删除 → 只剩「这条归档读不出来」；只缺 companion → 「这次读数」仍在。）
        XCTAssertNotNil(
            ui.element(label: L10n.History.detailResultUnavailable),
            "读数位必须写明读不到；AX 标签：\(ui.accessibilityLabels())"
        )
        // 文件层面：点云还在但结果没写全 —— 完整性与「有没有估产」是两件事。
        XCTAssertNotNil(
            ui.element(label: L10n.History.integrityIncomplete),
            "完整性要写「结果没写全」；AX 标签：\(ui.accessibilityLabels())"
        )
        // 记录本身没有被当成「不在了」。
        XCTAssertTrue(
            store.scanFiles.contains { $0.id == "T-21-a.ply" },
            "点云还在，这条记录必须还在档案里"
        )
    }

    /// 回归：同一 record.id、同一路径被换成**另一份有效档案**，
    /// 生产刷新完成后，已经展示的详情必须跟着换 ——
    /// 而且这条替换**不改变记录总数**，所以不能只靠「条数变了」来发现变化。
    @MainActor
    func testArchiveDetailShowsReplacedArchiveReadingWhenRecordCountIsUnchanged() async throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        let archive = try fixture.writeArchive(
            baseName: "T-22-a",
            treeID: "T-22",
            fruitCount: 12,
            yieldKg: 3.5
        )
        try fixture.writeArchive(baseName: "T-22-b", treeID: "T-22", fruitCount: 4, yieldKg: 1.0)
        let store = ScanHistoryStore(repository: ScanRepository(scansDirectory: fixture.directory))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanHistoryView(historyStore: store, tagStore: fixture.tagStore)
        })

        let appeared = try await ui.waitFor { ui.element(label: "T-22-a.ply") != nil }
        XCTAssertTrue(appeared, "档案行必须出现")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: "T-22-a.ply")).accessibilityActivate())
        let opened = try await ui.waitFor { ui.element(label: L10n.History.detailReadingTitle) != nil }
        XCTAssertTrue(opened, "点行必须进入归档详情")
        XCTAssertNotNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(12)),
            "详情要显示这次读数；AX 标签：\(ui.accessibilityLabels())"
        )
        let countBefore = store.scanFiles.count
        XCTAssertEqual(countBefore, 2, "夹具应当有两份档案")

        // 同一路径、同一 record.id，换成另一份有效档案。
        fixture.removeArchive(archive)
        try fixture.writeArchive(
            baseName: "T-22-a",
            treeID: "T-22",
            fruitCount: 7,
            yieldKg: 1.2,
            fruitType: "pear",
            confidence: "medium",
            pointCount: 9
        )
        await store.reloadRecords()
        XCTAssertEqual(
            store.scanFiles.count,
            countBefore,
            "这一条替换不能改变记录总数（否则证明不了「不能只看条数」）"
        )

        let refreshed = try await ui.waitFor(timeout: 10) {
            ui.element(label: L10n.Dashboard.fruitCountLabel(7)) != nil
        }
        XCTAssertTrue(
            refreshed,
            "替换后详情必须显示新档案的读数；AX 标签：\(ui.accessibilityLabels())"
        )
        // 旧读数必须撤掉：不能继续显示替换前那份的数。
        XCTAssertNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(12)),
            "旧读数不能继续显示"
        )
        XCTAssertNil(ui.element(label: String(format: "%.1f", 3.5 as Float)), "旧产量不能继续显示")
        // 新的可靠性也要跟着换（原来 high，现在 medium）。
        XCTAssertNotNil(
            ui.element(label: "medium"),
            "可靠性必须跟着新档案走；AX 标签：\(ui.accessibilityLabels())"
        )
        XCTAssertNil(ui.element(label: "high"), "旧可靠性不能继续显示")
        // 详情仍然是同一个详情页（列表还被盖着）。
        XCTAssertNil(ui.element(label: "T-22-b.ply"), "详情还开着，下面的列表不该继续暴露元素")
    }

    /// 回归：替换成**清单对不上**的档案（revision 不一致），
    /// 不能继续信任旧缓存里的读数 —— 可靠结果失败关闭，诊断保留。
    @MainActor
    func testArchiveDetailStopsTrustingReadingWhenReplacementManifestDoesNotMatch() async throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        let archive = try fixture.writeArchive(
            baseName: "T-23-a",
            treeID: "T-23",
            fruitCount: 11,
            yieldKg: 4.4,
            exportRevision: "rev-1",
            manifestMode: .matching
        )
        let store = ScanHistoryStore(repository: ScanRepository(scansDirectory: fixture.directory))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanHistoryView(historyStore: store, tagStore: fixture.tagStore)
        })

        let appeared = try await ui.waitFor { ui.element(label: "T-23-a.ply") != nil }
        XCTAssertTrue(appeared, "档案行必须出现")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: "T-23-a.ply")).accessibilityActivate())
        let opened = try await ui.waitFor { ui.element(label: L10n.History.detailReadingTitle) != nil }
        XCTAssertTrue(opened, "点行必须进入归档详情")
        XCTAssertNotNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(11)),
            "详情要显示这次读数；AX 标签：\(ui.accessibilityLabels())"
        )

        // 换成清单对不上的档案：结果文件的 revision 与清单不一致。
        fixture.removeArchive(archive)
        try fixture.writeArchive(
            baseName: "T-23-a",
            treeID: "T-23",
            fruitCount: 21,
            yieldKg: 8.8,
            exportRevision: "rev-2",
            manifestMode: .revisionMismatch
        )
        await store.reloadRecords()

        let refreshed = try await ui.waitFor(timeout: 10) {
            ui.element(label: L10n.History.integrityInvalid) != nil
        }
        XCTAssertTrue(
            refreshed,
            "清单对不上时完整性必须写「无法核对」；AX 标签：\(ui.accessibilityLabels())"
        )
        // 旧读数不得继续被当成有效读数。
        XCTAssertNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(11)),
            "清单对不上之后不能继续显示旧读数"
        )
        XCTAssertNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(21)),
            "清单对不上的新档案也不能被当成有效读数"
        )
        XCTAssertNil(ui.element(label: L10n.Dashboard.fruitCountLabel(0)), "不能把 0 果当成读到了")
        XCTAssertNil(ui.element(label: String(format: "%.1f", 0.0 as Float)), "不能把 0.0 kg 当成读到了")
        // 诊断保留：读数位要说读不到。
        XCTAssertNotNil(
            ui.element(label: L10n.History.detailResultUnavailable),
            "读数位必须说读不到；AX 标签：\(ui.accessibilityLabels())"
        )
        // 这条档案本身还在（没有被当成删掉），但不可核对。
        XCTAssertTrue(
            store.scanFiles.contains { $0.id == "T-23-a.ply" },
            "档案还在，只是核对不过"
        )
        XCTAssertEqual(
            store.scanFiles.first { $0.id == "T-23-a.ply" }?.persistenceState,
            .invalid,
            "核对不过的档案必须标成无法核对"
        )
    }

    /// 回归：晚到的旧读取不得覆盖变化后的新状态。
    ///
    /// 这里用**生产锁**造出真实的先后：详情打开时的第一次读被档案锁挡住，
    /// 期间档案被删掉并完成生产刷新（页面已经变成「读不到」），
    /// 之后锁一放，第一次读才回来 —— 它必须被丢弃：
    /// 页面不能退回「读到了，只是这次没读出数」这种旧状态。
    ///
    /// 锁走的是生产公开入口（`ScanRepository.withScanTransaction`），
    /// 读走的是生产读取器；没有注入假状态，也没有重建详情。
    @MainActor
    func testArchiveDetailKeepsNewerStateWhenLateReadReturnsAfterArchiveChanged() async throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        let archive = try fixture.writeArchive(
            baseName: "T-25-a",
            treeID: "T-25",
            fruitCount: 8,
            yieldKg: 2.4
        )
        let repository = ScanRepository(scansDirectory: fixture.directory)
        let store = ScanHistoryStore(repository: repository)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)

        // 占住这条档案的锁：详情页的第一次读会卡在这里。
        // （锁必须等档案行加载出来之后再占：档案列表自己读每份档案时也要这把锁。）
        let acquired = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        ui.mount(NavigationStack {
            ScanHistoryView(historyStore: store, tagStore: fixture.tagStore)
        })
        let appeared = try await ui.waitFor { ui.element(label: "T-25-a.ply") != nil }
        XCTAssertTrue(appeared, "档案行必须出现")

        DispatchQueue(label: "archive-detail-lock-holder").async {
            try? repository.withScanTransaction(at: archive.plyURL) {
                acquired.signal()
                // 有界等待：拿不到锁就报错，不能把整个测试套件挂住。
                if release.wait(timeout: .now() + 60) == .timedOut {
                    XCTFail("档案锁的持有者没有按时退出")
                }
            }
        }
        XCTAssertEqual(
            acquired.wait(timeout: .now() + 10),
            .success,
            "没能拿到这条档案的锁（生产档案锁没能被占住，这一轮就证明不了任何事）"
        )
        defer { release.signal() }
        XCTAssertTrue(try XCTUnwrap(ui.element(label: "T-25-a.ply")).accessibilityActivate())

        // 第一次读已经在途（被锁挡住）：页面停在「正在读取」。
        let inFlight = try await ui.waitFor(timeout: 10) {
            ui.element(label: L10n.History.detailLoading) != nil
        }
        XCTAssertTrue(inFlight, "第一次读应当在途；AX 标签：\(ui.accessibilityLabels())")

        // 档案被删掉并完成生产刷新（直接拿掉文件：生产删除入口要等同一把锁）。
        fixture.removeArchive(archive)
        await store.reloadRecords()
        let refreshed = try await ui.waitFor(timeout: 10) {
            ui.element(label: L10n.History.detailUnavailableTitle) != nil
        }
        XCTAssertTrue(
            refreshed,
            "刷新完成后详情必须说读不到；AX 标签：\(ui.accessibilityLabels())"
        )

        // 锁一放：晚到的第一次读回来了，它不能把页面退回旧状态。
        release.signal()
        var sawStaleState = false
        for _ in 0..<250 {
            if ui.element(label: L10n.History.detailReadingTitle) != nil {
                sawStaleState = true
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(
            sawStaleState,
            "晚到的旧读取不得覆盖新状态；AX 标签：\(ui.accessibilityLabels())"
        )
        XCTAssertNotNil(
            ui.element(label: ArchiveDetailRefreshFixture.recordMissingMessage),
            "页面必须仍然说这条记录不在了；AX 标签：\(ui.accessibilityLabels())"
        )
        XCTAssertNil(ui.element(label: L10n.Dashboard.fruitCountLabel(8)), "旧读数不能被回填")
    }

    /// 回归：替换成**清单记的源点云摘要对不上**的档案 ——
    /// 清单核对不过就不能继续信任旧缓存里的读数；可靠结果失败关闭，诊断保留。
    @MainActor
    func testArchiveDetailStopsTrustingReadingWhenReplacementSourceDigestDoesNotMatch() async throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        let archive = try fixture.writeArchive(
            baseName: "T-26-a",
            treeID: "T-26",
            fruitCount: 5,
            yieldKg: 1.8,
            exportRevision: "rev-1",
            manifestMode: .matching
        )
        let store = ScanHistoryStore(repository: ScanRepository(scansDirectory: fixture.directory))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(NavigationStack {
            ScanHistoryView(historyStore: store, tagStore: fixture.tagStore)
        })

        let appeared = try await ui.waitFor { ui.element(label: "T-26-a.ply") != nil }
        XCTAssertTrue(appeared, "档案行必须出现")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: "T-26-a.ply")).accessibilityActivate())
        let opened = try await ui.waitFor { ui.element(label: L10n.History.detailReadingTitle) != nil }
        XCTAssertTrue(opened, "点行必须进入归档详情")
        XCTAssertNotNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(5)),
            "详情要显示这次读数；AX 标签：\(ui.accessibilityLabels())"
        )

        // 换成清单记的源点云摘要对不上的档案：清单说这份点云是另一个文件。
        fixture.removeArchive(archive)
        try fixture.writeArchive(
            baseName: "T-26-a",
            treeID: "T-26",
            fruitCount: 13,
            yieldKg: 5.5,
            exportRevision: "rev-2",
            manifestMode: .sourceDigestMismatch
        )
        await store.reloadRecords()

        let refreshed = try await ui.waitFor(timeout: 10) {
            ui.element(label: L10n.History.integrityInvalid) != nil
        }
        XCTAssertTrue(
            refreshed,
            "源点云摘要对不上时完整性必须写「无法核对」；AX 标签：\(ui.accessibilityLabels())"
        )
        // 旧读数不得继续被当成有效读数，新读数也不得被当成有效的。
        XCTAssertNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(5)),
            "源摘要对不上之后不能继续显示旧读数"
        )
        XCTAssertNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(13)),
            "源摘要对不上的新档案也不能被当成有效读数"
        )
        XCTAssertNil(ui.element(label: L10n.Dashboard.fruitCountLabel(0)), "不能把 0 果当成读到了")
        XCTAssertNil(ui.element(label: String(format: "%.1f", 0.0 as Float)), "不能把 0.0 kg 当成读到了")
        // 读数位要说读不到。
        XCTAssertNotNil(
            ui.element(label: L10n.History.detailResultUnavailable),
            "读数位必须说读不到；AX 标签：\(ui.accessibilityLabels())"
        )
        // 档案还在，但核对不过。
        XCTAssertTrue(
            store.scanFiles.contains { $0.id == "T-26-a.ply" },
            "档案还在，只是核对不过"
        )
        XCTAssertEqual(
            store.scanFiles.first { $0.id == "T-26-a.ply" }?.persistenceState,
            .invalid,
            "核对不过的档案必须标成无法核对"
        )
    }

    /// 回归：详情开着的时候档案被删掉，随即关闭再重开 ——
    /// 重开的详情不能把旧读数回填回来（取消必须真的作废在途读取）。
    @MainActor
    func testArchiveDetailReopenedAfterDeletionDoesNotRefillOldReading() async throws {
        let fixture = try ArchiveDetailRefreshFixture()
        defer { fixture.cleanUp() }
        try fixture.writeArchive(baseName: "T-24-a", treeID: "T-24", fruitCount: 6, yieldKg: 2.0)
        let store = ScanHistoryStore(repository: ScanRepository(scansDirectory: fixture.directory))
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)

        func mountDetail() {
            ui.mount(NavigationStack {
                ScanArchiveDetailView(recordID: "T-24-a.ply", historyStore: store)
            })
        }

        mountDetail()
        let opened = try await ui.waitFor {
            ui.element(label: L10n.Dashboard.fruitCountLabel(6)) != nil
        }
        XCTAssertTrue(opened, "详情要显示这次读数；AX 标签：\(ui.accessibilityLabels())")

        // 档案被删掉并刷新。
        guard case .success(let records) = store.archiveRepository.loadHistoryRecords(),
              let record = records.first(where: { $0.id == "T-24-a.ply" }) else {
            XCTFail("应当读得到刚写的档案")
            return
        }
        _ = await store.deleteRecordsWithResult([record])
        await store.reloadRecords()

        // 快速关闭再重开：不能回填旧读数。
        ui.mount(NavigationStack { EmptyView() })
        mountDetail()
        let reopened = try await ui.waitFor(timeout: 10) {
            ui.element(label: L10n.History.detailUnavailableTitle) != nil
        }
        XCTAssertTrue(
            reopened,
            "重开的详情必须说读不到，不能回填旧读数；AX 标签：\(ui.accessibilityLabels())"
        )
        XCTAssertNil(
            ui.element(label: L10n.Dashboard.fruitCountLabel(6)),
            "旧读数不能被回填"
        )
    }

    /// 回归：返回档案列表时，焦点与滚动锚点要放回**同一条**存档 ——
    /// 而且这条存档要是已经不在了，就**什么都不放回**，
    /// 不能悄悄换成另一条（同树的另一份档案也不行）。
    ///
    /// 分层说明（无障碍焦点）：
    /// - XCUITest **没有**焦点 API（XCTest 头文件里没有任何 focus 符号）；
    /// - 宿主里 `UIAccessibility.focusedElement(using:)` 即使在 UIKit 自己
    ///   用 `.layoutChanged` 移动过焦点之后仍然返回 nil ——
    ///   没有辅助功能在跑时，系统没有焦点所有者可问。
    /// 因此焦点这一层交付的是：**放回哪一条**的决定（这里逐条断言）+
    ///   UI 测试里可读的那部分状态（筛选 / 身份 / 位置 / AX 树）。
    ///   VoiceOver 实读仍然未验证。
    @MainActor
    func testArchiveRestoreTargetIsTheOpenedArchiveAndNeverAnotherOne() throws {
        // 刚打开的那一条还在 → 就放回那一条。
        XCTAssertEqual(
            ScanHistoryRestoreTarget.resolve(openedRecordID: "T-07.ply", availableRecordIDs: ["T-07.ply", "T-01.ply"]),
            .restore("T-07.ply")
        )
        // 刚打开的那一条已经不在了 → 什么都不放回（不能悄悄换成同树的另一份）。
        XCTAssertEqual(
            ScanHistoryRestoreTarget.resolve(openedRecordID: "T-07.ply", availableRecordIDs: ["T-01.ply"]),
            .none
        )
        XCTAssertEqual(
            ScanHistoryRestoreTarget.resolve(openedRecordID: nil, availableRecordIDs: ["T-01.ply"]),
            .none
        )
        // 同树的另一份档案不算「那一条」。
        XCTAssertEqual(
            ScanHistoryRestoreTarget.resolve(openedRecordID: "T-07-a.ply", availableRecordIDs: ["T-07-b.ply"]),
            .none
        )
    }

    /// 回归：结果没写全的记录，读数位要写清「不可用」，
    /// 不能读成 0，也不能只留一横让人以为是「有读数」。
    @MainActor
    func testHistoryRowStatesUnavailableMetricsInsteadOfZeroOrDash() async throws {
        let now = Date()
        let record = ScanFileRecord(
            id: "no-estimate.ply", treeID: "QA-NO-ESTIMATE",
            fileURL: URL(fileURLWithPath: "/tmp/no-estimate.ply"), scanDate: now,
            fruitCount: 0, yieldKg: 0, gpsLat: 31.23, gpsLon: 121.47,
            confidence: "high", persistenceState: .incomplete
        )
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(ScanHistoryRow(record: record, onPreview: {}, onShare: {}, onRescan: {},
                                onMarkReview: {}, onDelete: {}))
        let ready = try await ui.waitFor { ui.element(label: "no-estimate.ply") != nil }
        XCTAssertTrue(ready)
        let element = try XCTUnwrap(ui.element(label: "no-estimate.ply"))
        let value = element.accessibilityValue ?? ""
        let unavailable = NSLocalizedString("history.row.metrics_unavailable", value: "Metrics Unavailable", comment: "")
        XCTAssertTrue(value.contains(unavailable),
                      "结果没写全时要说「\(unavailable)」：\(value)")
        XCTAssertFalse(value.contains("0.0"), "不可用的读数不能被读成 0：\(value)")
    }

    /// 回归：一行里的同一个动作只出现一次。
    /// 「预览点云」既是行内按钮、又是「更多」菜单里的条目 —— 同一个动作出现两次，
    /// 读屏要念两遍，眼睛也要在两个地方找同一个入口。
    @MainActor
    func testHistoryRowOffersEachActionOnlyOnce() async throws {
        let record = makeRecord(id: "history-single-action", treeID: "UI-HISTORY-ONCE", scanDate: Date(), yieldKg: 4.2)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        var previews = 0
        var shares = 0
        ui.mount(ScrollView {
            ScanHistoryRow(record: record, onPreview: { previews += 1 }, onShare: { shares += 1 },
                           onRescan: {}, onMarkReview: {}, onDelete: {})
                .padding(24)
        }.workspacePage(background: Design.Colors.Workspace.surface))

        let previewLabel = L10n.History.previewPointCloud
        /* 收敛后：行内只有「打开这条归档」与尾部一个更多入口，
           所有动作都在那个菜单里，同一个动作不出现两次。 */
        XCTAssertNil(ui.element(label: previewLabel), "预览点云不该再是行内按钮")

        // 宿主的 AX 树要等一拍才建好：先等入口出现，再去开菜单。
        let ready = try await ui.waitFor { ui.element(label: L10n.History.moreActions) != nil }
        XCTAssertTrue(ready, "尾部更多入口必须出现")

        let (_, actions) = try await ui.menuActions(label: L10n.History.moreActions)
        let titles = actions.map(\.title)
        let listed = String(describing: titles)
        XCTAssertTrue(titles.contains(previewLabel), listed)
        XCTAssertTrue(titles.contains(L10n.History.rescanTree), listed)
        XCTAssertTrue(titles.contains(L10n.History.sharePointCloud), listed)
        XCTAssertTrue(titles.contains(L10n.History.markReview), listed)
        XCTAssertTrue(titles.contains(L10n.History.deleteRecord), listed)
        XCTAssertEqual(titles.count, 5, "菜单里每个动作只出现一次：\(listed)")

        /* 能力不能只是「在菜单里」：点它就得真的接上回调。
           （动作从行内收进菜单后，这条断言一度只剩「菜单里有这一项」，
             回调接线就没人守了 —— 那是能力被悄悄拿掉。）
           两项都从**同一次**菜单呈现里派发：宿主里菜单一关，AX 树会被清空，
           再开第二次菜单并不可靠。 */
        UIButton(type: .system).sendAction(try XCTUnwrap(actions.first { $0.title == previewLabel }))
        XCTAssertEqual(previews, 1, "预览点云的回调必须仍然接上")
        UIButton(type: .system).sendAction(try XCTUnwrap(actions.first { $0.title == L10n.History.sharePointCloud }))
        XCTAssertEqual(shares, 1, "分享点云的回调必须仍然接上")
    }

    // MARK: - 档案行版式（原型档案页 → 原生）

    /// 回归：档案行按已认可的原型档案页排版 —— 树号独占一行、读数独立右列、
    /// 状态词跟读数走；存档身份与果数是这次扫描的事实行。
    @MainActor
    func testArchiveRowShowsReadingColumnStatusWordAndArchiveIdentity() async throws {
        let fileName = "orchard-north-20261025-1645-ab12cd.ply"
        let record = ScanFileRecord(
            id: fileName,
            treeID: "T-01",
            fileURL: URL(fileURLWithPath: "/tmp/\(fileName)"),
            scanDate: Date(),
            fruitCount: 8,
            yieldKg: 12.3,
            fruitType: "苹果",
            confidence: "high"
        )
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(ScanHistoryRow(record: record, plotName: "北坡",
                                onPreview: {}, onShare: {}, onRescan: {},
                                onMarkReview: {}, onDelete: {}))

        let ready = try await ui.waitFor { ui.element(label: fileName) != nil }
        XCTAssertTrue(ready)
        let row = try XCTUnwrap(ui.element(label: fileName))
        let value = row.accessibilityValue ?? ""

        // 读数列：数值 + 单位
        XCTAssertTrue(value.contains("12.3"), "读数要在行里：\(value)")
        XCTAssertTrue(value.contains("kg"), "单位要跟着读数：\(value)")
        // 状态词：这条记录自己的落盘完整性结论（不声称高置信度）
        XCTAssertTrue(
            value.contains(NSLocalizedString("history.integrity.complete.title", value: "Result Complete", comment: "")),
            "状态词要跟着读数：\(value)"
        )
        // 上下文行：树当前归属的地块
        XCTAssertTrue(value.contains("北坡"), "地块要出现在行里：\(value)")
        // 事实行：存档身份 + 果数 + 果实种类
        XCTAssertTrue(value.contains(fileName), "存档身份要出现在行里：\(value)")
        XCTAssertTrue(value.contains(L10n.History.fruitCount(8)), "果数要出现在行里：\(value)")
        XCTAssertTrue(value.contains("苹果"), "果实种类要出现在行里：\(value)")

        // 字阶：与原型档案页一致（读数 24 / 树号 16 / 辅助信息 13）
        XCTAssertEqual(InstrumentArchiveRowMetrics.reading, 24)
        XCTAssertEqual(InstrumentArchiveRowMetrics.identity, 16)
        XCTAssertEqual(InstrumentArchiveRowMetrics.supporting, 13)
    }

    /// 回归：真实 0 与「不可用」必须是两件事。
    /// 结果没写全的记录不能被读成 0；完整但估产为 0 的记录不能被读成不可用。
    @MainActor
    func testArchiveRowKeepsRealZeroDistinctFromUnavailableReading() async throws {
        let unavailable = NSLocalizedString("history.row.metrics_unavailable", value: "Metrics Unavailable", comment: "")
        let zero = makeRecord(id: "zero", treeID: "T-ZERO", scanDate: Date(), fruitCount: 0, yieldKg: 0)
        let broken = makeRecord(id: "broken", treeID: "T-BROKEN", scanDate: Date(),
                                fruitCount: 0, yieldKg: 0, persistenceState: .incomplete)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(VStack(alignment: .leading, spacing: 0) {
            ScanHistoryRow(record: zero, onPreview: {}, onShare: {}, onRescan: {},
                            onMarkReview: {}, onDelete: {})
            ScanHistoryRow(record: broken, onPreview: {}, onShare: {}, onRescan: {},
                            onMarkReview: {}, onDelete: {})
        })
        let ready = try await ui.waitFor {
            ui.element(label: "zero.ply") != nil && ui.element(label: "broken.ply") != nil
        }
        XCTAssertTrue(ready)

        let zeroValue = try XCTUnwrap(ui.element(label: "zero.ply")).accessibilityValue ?? ""
        XCTAssertTrue(zeroValue.contains("0.0"), "真实 0 仍然是读数：\(zeroValue)")
        XCTAssertTrue(zeroValue.contains("kg"), zeroValue)
        XCTAssertFalse(zeroValue.contains(unavailable), "真实 0 不是不可用：\(zeroValue)")

        let brokenValue = try XCTUnwrap(ui.element(label: "broken.ply")).accessibilityValue ?? ""
        XCTAssertTrue(brokenValue.contains(unavailable), "结果没写全要说不可用：\(brokenValue)")
        XCTAssertFalse(brokenValue.contains("0.0"), "不可用不能被读成 0：\(brokenValue)")
    }

    /// 回归：档案版式是**显式变体**。
    /// 首页、分析页、对比页继续用紧凑行，档案页改版不会改到它们。
    @MainActor
    func testArchiveRowVariantIsExplicitAndKeepsOtherCallersCompact() async throws {
        let compact = makeRecord(id: "compact", treeID: "T-COMPACT", scanDate: Date(), yieldKg: 3.3)
        let archive = makeRecord(id: "archive", treeID: "T-ARCHIVE", scanDate: Date(), yieldKg: 3.3)
        XCTAssertEqual(InstrumentScanRow(record: compact).layout, .compact,
                       "共享行默认仍是紧凑行")

        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(VStack(alignment: .leading, spacing: 0) {
            InstrumentScanRow(record: compact)
            InstrumentScanRow(record: archive, layout: .archive, plotName: "南坡")
        })
        let ready = try await ui.waitFor {
            ui.element(label: "T-COMPACT") != nil && ui.element(label: "T-ARCHIVE") != nil
        }
        XCTAssertTrue(ready, "两种版式都要能单独认出")

        let compactValue = try XCTUnwrap(ui.element(label: "T-COMPACT")).accessibilityValue ?? ""
        let archiveValue = try XCTUnwrap(ui.element(label: "T-ARCHIVE")).accessibilityValue ?? ""
        // 档案版式多说两件事：当前地块与存档身份；紧凑版式不受影响。
        XCTAssertTrue(archiveValue.contains("南坡"), archiveValue)
        XCTAssertTrue(archiveValue.contains(archive.id), archiveValue)
        XCTAssertFalse(compactValue.contains("南坡"), "紧凑版式不应带地块：\(compactValue)")
        XCTAssertFalse(compactValue.contains(compact.id), "紧凑版式不应带存档身份：\(compactValue)")
    }

    /// 回归：档案行在受支持的机型宽度、横屏与辅助字号下不横向溢出，
    /// 尾部唯一入口始终够得着（44pt）。
    @MainActor
    func testArchiveRowFitsSupportedWidthsLandscapeAndAccessibilitySizes() async throws {
        let longTreeID = "ORCHARD-NORTH-BLOCK-07-TREE-0213"
        let longFileName = "orchard_north_block07_20261025_164512_a1b2c3d4.ply"
        let records = [
            ScanFileRecord(id: longFileName, treeID: longTreeID,
                           fileURL: URL(fileURLWithPath: "/tmp/\(longFileName)"),
                           scanDate: Date(), fruitCount: 24, yieldKg: 12.3,
                           fruitType: "苹果", confidence: "high"),
            ScanFileRecord(id: "no-result.ply", treeID: "T-02",
                           fileURL: URL(fileURLWithPath: "/tmp/no-result.ply"),
                           scanDate: Date(), fruitCount: 0, yieldKg: 0,
                           persistenceState: .incomplete)
        ]
        let sizes: [(String, CGSize)] = [
            ("375", CGSize(width: 375, height: 812)),
            ("390", CGSize(width: 390, height: 844)),
            ("430", CGSize(width: 430, height: 932)),
            ("landscape-844", CGSize(width: 844, height: 390)),
            ("ipad-split-507", CGSize(width: 507, height: 1024))
        ]
        var defaultRowHeight: CGFloat = 0

        for (name, size) in sizes {
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            ui.window.frame = CGRect(origin: .zero, size: size)
            ui.mount(ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(records) { record in
                        ScanHistoryRow(record: record, onOpen: {}, plotName: "北坡",
                                       onPreview: {}, onShare: {}, onRescan: {},
                                       onMarkReview: {}, onDelete: {})
                    }
                }
                .padding(.horizontal, 20)
            }.workspacePage(background: Design.Colors.Workspace.surface))

            let ready = try await ui.waitFor { ui.element(label: longFileName) != nil }
            XCTAssertTrue(ready, "\(name): 档案行必须出现")
            let row = try XCTUnwrap(ui.element(label: longFileName))
            XCTAssertLessThanOrEqual(row.accessibilityFrame.maxX, size.width + 0.5,
                                     "\(name): 行不得横向溢出 \(row.accessibilityFrame)")
            XCTAssertGreaterThanOrEqual(row.accessibilityFrame.minX, -0.5,
                                        "\(name): 行不得越过左边界")
            if name == "390" { defaultRowHeight = row.accessibilityFrame.height }

            let more = try XCTUnwrap(ui.element(label: L10n.History.moreActions))
            XCTAssertGreaterThanOrEqual(more.accessibilityFrame.width, 43.5, "\(name): 入口宽度")
            XCTAssertGreaterThanOrEqual(more.accessibilityFrame.height, 43.5, "\(name): 入口高度")
            XCTAssertLessThanOrEqual(more.accessibilityFrame.maxX, size.width + 0.5,
                                     "\(name): 入口不得横向溢出")
            // 焦点顺序：先读身份，再读尾部入口。
            let order = ui.elements
            let rowIndex = order.firstIndex { $0 === row }
            let moreIndex = order.firstIndex { $0 === more }
            XCTAssertNotNil(rowIndex)
            XCTAssertNotNil(moreIndex)
            if let rowIndex, let moreIndex {
                XCTAssertLessThan(rowIndex, moreIndex, "\(name): 焦点顺序应为身份在前、入口在后")
            }
            // 语义：身份是按钮，入口也是按钮。
            XCTAssertTrue(row.accessibilityTraits.contains(.button), "\(name): 身份行应是按钮")

            try await writeArchiveRowScreenshot(ui, name: "archive-row-\(name)")
        }

        // 辅助字号：文字随系统放大（行更高），读数列改到身份下面一行，仍不横向溢出。
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(records) { record in
                    ScanHistoryRow(record: record, onOpen: {}, plotName: "北坡",
                                   onPreview: {}, onShare: {}, onRescan: {},
                                   onMarkReview: {}, onDelete: {})
                }
            }
            .padding(.horizontal, 20)
        }.workspacePage(background: Design.Colors.Workspace.surface)
            .dynamicTypeSize(.accessibility5))
        let ready = try await ui.waitFor { ui.element(label: longFileName) != nil }
        XCTAssertTrue(ready, "辅助字号下档案行必须出现")
        let scaled = try XCTUnwrap(ui.element(label: longFileName))
        XCTAssertLessThanOrEqual(scaled.accessibilityFrame.maxX, 390.5,
                                 "辅助字号下行不得横向溢出 \(scaled.accessibilityFrame)")
        XCTAssertGreaterThan(scaled.accessibilityFrame.height, defaultRowHeight,
                             "辅助字号下行应当更高（字随系统放大）")
        try await writeArchiveRowScreenshot(ui, name: "archive-row-accessibility5")
    }

    // MARK: - 档案搜索与日期分组

    /// 造一条**与生产同形**的档案：`id` 就是存档文件名（带 `.ply`），
    /// 行上的标签与朗读里的存档编号都是它 —— 搜索要匹配的就是这两个身份。
    private func archiveRecord(
        _ stem: String,
        treeID: String,
        scanDate: Date,
        yieldKg: Float = 1.5
    ) -> ScanFileRecord {
        let name = stem + ".ply"
        return ScanFileRecord(
            id: name,
            treeID: treeID,
            fileURL: URL(fileURLWithPath: "/tmp/" + name),
            scanDate: scanDate,
            fruitCount: 12,
            yieldKg: yieldKg
        )
    }

    /// 回归：搜索**两个身份**都匹配 —— 树号与存档编号。
    ///
    /// 只搜一个都不算数：树号是人抄的，存档编号是机器给的，
    /// 用户找一份档案时手里可能只有其中之一。
    /// 大小写与首尾空白也不该影响命中：这两样都是常见手误。
    func testArchiveSearchMatchesTreeNumberAndRecordNumberIgnoringWhitespaceAndCase() {
        let records = [
            archiveRecord("T-07_20261020_090000_lat31_lon121", treeID: "T-07", scanDate: Date()),
            archiveRecord("T-08_20261021_090000_lat31_lon121", treeID: "T-08", scanDate: Date())
        ]

        // 树号：大小写、首尾空白、换行都不影响命中。
        XCTAssertEqual(ScanHistorySearch.filter(records, query: "t-07").map(\.id),
                       [records[0].id])
        XCTAssertEqual(ScanHistorySearch.filter(records, query: "  T-07  ").map(\.id),
                       [records[0].id])
        XCTAssertEqual(ScanHistorySearch.filter(records, query: "t-07\n").map(\.id),
                       [records[0].id])

        // 存档编号：只给编号片段也命中。
        XCTAssertEqual(ScanHistorySearch.filter(records, query: "20261020").map(\.id),
                       [records[0].id])
        XCTAssertEqual(ScanHistorySearch.filter(records, query: "LAT31_LON121").count, 2)

        // 空查询 = 不过滤（不是「什么都不匹配」）。
        XCTAssertEqual(ScanHistorySearch.filter(records, query: "").count, 2)
        XCTAssertEqual(ScanHistorySearch.filter(records, query: "   ").count, 2)

        // 不命中就是真的不命中。
        XCTAssertTrue(ScanHistorySearch.filter(records, query: "T-99").isEmpty)
    }

    /// 回归：搜索只动**内存里的档案元数据**，不逐键读 PLY。
    ///
    /// 证据：被匹配的档案指向一个**不存在的文件** —— 如果搜索真的去读点云，
    /// 这一条要么被跳过、要么读不到；它照样能命中，说明搜索压根没碰磁盘。
    func testArchiveSearchDoesNotRequireTheArchiveFilesToExist() {
        let name = "T-42_20261020_090000_lat31_lon121.ply"
        let missing = URL(fileURLWithPath: "/tmp/fts-missing-\(UUID().uuidString).ply")
        let record = ScanFileRecord(id: name, treeID: "T-42", fileURL: missing,
                                    scanDate: Date(), fruitCount: 3, yieldKg: 1.5)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertTrue(ScanHistorySearch.matches(record, query: "T-42"))
        XCTAssertTrue(ScanHistorySearch.matches(record, query: "20261020"))
        XCTAssertEqual(ScanHistorySearch.filter([record], query: "t-42").count, 1)
    }

    /// 回归：分组按 **Calendar 的那一天**判定，时钟与日历都可注入。
    ///
    /// 「今天」不是「相差 24 小时」：跨午夜的那一份属于昨天；
    /// 时区换了，同一个时刻可能属于不同的一天。两件事都必须成立。
    func testArchiveDateGroupingUsesCalendarDaysWithInjectedClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        func moment(_ components: DateComponents) throws -> Date {
            try XCTUnwrap(calendar.date(from: components))
        }
        let now = try moment(DateComponents(year: 2026, month: 10, day: 27, hour: 10))
        let todayMorning = try moment(DateComponents(year: 2026, month: 10, day: 27, hour: 9))
        let yesterdayLate = try moment(DateComponents(year: 2026, month: 10, day: 26, hour: 23, minute: 30))
        let earlier = try moment(DateComponents(year: 2026, month: 10, day: 20, hour: 8))
        let future = try moment(DateComponents(year: 2026, month: 10, day: 29, hour: 8))

        let groups = ScanHistoryDateGrouping.group([
            archiveRecord("today", treeID: "T-1", scanDate: todayMorning),
            archiveRecord("yesterday", treeID: "T-2", scanDate: yesterdayLate),
            archiveRecord("earlier", treeID: "T-3", scanDate: earlier),
            archiveRecord("future", treeID: "T-4", scanDate: future)
        ], now: now, calendar: calendar)

        XCTAssertEqual(groups.map(\.kind), [.today, .yesterday, .earlier, .invalidDate])
        XCTAssertEqual(groups.map { $0.records.count }, [1, 1, 1, 1])

        // 相差不到 24 小时，也可能已经是昨天：判定看的是**那一天**，不是时长。
        let twentyHoursAgo = try XCTUnwrap(calendar.date(byAdding: .hour, value: -20, to: now))
        let crossed = ScanHistoryDateGrouping.group(
            [archiveRecord("crossed", treeID: "T-5", scanDate: twentyHoursAgo)],
            now: now, calendar: calendar)
        XCTAssertEqual(crossed.map(\.kind), [.yesterday])

        // 同一个绝对时刻，时区不同就落在不同的一段。
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let instant = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 17)))
        let shanghaiNow = now
        let utcNow = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 10)))
        let record = archiveRecord("instant", treeID: "T-6", scanDate: instant)
        XCTAssertEqual(ScanHistoryDateGrouping.group([record], now: shanghaiNow, calendar: calendar)
            .map(\.kind), [.today])
        XCTAssertEqual(ScanHistoryDateGrouping.group([record], now: utcNow, calendar: utc)
            .map(\.kind), [.yesterday])
    }

    /// 回归：组内顺序**稳定**，且档案身份（record.id）不被改写。
    func testArchiveDateGroupingKeepsStableOrderAndRecordIdentity() throws {
        let moment = Date(timeIntervalSince1970: 1_792_300_000)
        let records = [
            archiveRecord("b", treeID: "T-B", scanDate: moment),
            archiveRecord("a", treeID: "T-A", scanDate: moment),
            archiveRecord("c", treeID: "T-C", scanDate: moment.addingTimeInterval(-60))
        ]
        let group = try XCTUnwrap(ScanHistoryDateGrouping.group(
            records, now: moment.addingTimeInterval(3600), calendar: Calendar(identifier: .gregorian)
        ).first)
        // 同一时刻按存档编号升序；更早的排在后面 —— 顺序不随输入顺序抖动。
        XCTAssertEqual(group.records.map(\.id), ["a.ply", "b.ply", "c.ply"])
        // 分组只影响呈现：身份一个都不改。
        XCTAssertEqual(Set(group.records.map(\.id)), Set(records.map(\.id)))
        // 空段不出现。
        XCTAssertEqual(ScanHistoryDateGrouping.group([], now: moment).count, 0)
    }

    /// 回归：「没有匹配」与「档案是空的」是**两件事**。
    func testArchiveSearchDistinguishesNoMatchFromEmptyArchive() {
        let records = [archiveRecord("a", treeID: "T-A", scanDate: Date())]
        XCTAssertTrue(ScanHistorySearch.filter(records, query: "zzz").isEmpty,
                      "没有匹配就是空结果")
        XCTAssertEqual(ScanHistorySearch.filter(records, query: "").count, 1,
                       "空查询是不过滤，不是空结果")
        XCTAssertTrue(ScanHistorySearch.filter([], query: "").isEmpty,
                      "档案本身为空就是空结果")
    }

    /// 回归（真实原生视图）：搜索框真的把档案筛掉，清除后真的都回来。
    @MainActor
    func testArchiveSearchFieldFiltersRowsAndClearRestoresThem() async throws {
        let suite = "ArchiveSearch-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tags = TagStore(defaults: defaults)
        tags.addPlot(name: "北坡", colorHex: "285E49")
        for tree in ["T-01", "T-02"] {
            tags.createOrUpdateAssignment(treeId: tree, plotId: tags.plots.first?.id,
                                          tagIds: [], status: .scanned)
        }
        await tags.waitForPendingSave()

        let now = Date()
        let records = [
            archiveRecord("T-01_20261020_090000_lat31_lon121", treeID: "T-01", scanDate: now),
            archiveRecord("T-02_20261021_090000_lat31_lon121", treeID: "T-02", scanDate: now)
        ]
        let store = ScanHistoryStore(recordsLoader: { .success(records) })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(ScanHistoryView(historyStore: store, tagStore: tags)
            .workspacePage(background: Design.Colors.Workspace.surface))

        let ready = try await ui.waitFor {
            ui.element(label: records[0].id) != nil && ui.element(label: records[1].id) != nil
        }
        XCTAssertTrue(ready, "两条档案都要先出现")

        // 搜索框必须在（有档案时才摆）。
        let field = try await searchField(in: ui)
        // 按树号搜。
        field.insertText("T-02")
        let filtered = try await ui.waitFor {
            ui.element(label: records[1].id) != nil && ui.element(label: records[0].id) == nil
        }
        XCTAssertTrue(filtered, "按树号搜索后只应剩下匹配的那一条")

        // 按存档编号搜（另一种身份）。
        field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
        field.insertText("20261020")
        let byRecordID = try await ui.waitFor {
            ui.element(label: records[0].id) != nil && ui.element(label: records[1].id) == nil
        }
        XCTAssertTrue(byRecordID, "按存档编号搜索后只应剩下匹配的那一条")

        // 清除：档案都回来。
        let clear = try XCTUnwrap(ui.element(label: L10n.History.clearSearch), "有查询时必须有清除入口")
        XCTAssertTrue(clear.accessibilityActivate())
        let restored = try await ui.waitFor {
            ui.element(label: records[0].id) != nil && ui.element(label: records[1].id) != nil
        }
        XCTAssertTrue(restored, "清除搜索后档案必须都回来")
        // 空查询时清除入口隐藏。
        XCTAssertNil(ui.element(label: L10n.History.clearSearch))
    }

    /// 回归（真实原生视图）：搜索与地块/状态筛选是**交集**，
    /// 而且清除搜索**保留**两个筛选。
    @MainActor
    func testArchiveSearchIntersectsPlotFilterAndClearKeepsBothFilters() async throws {
        let suite = "ArchiveSearchFilters-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tags = TagStore(defaults: defaults)
        tags.addPlot(name: "北坡", colorHex: "285E49")
        tags.addPlot(name: "南坡", colorHex: "6F8F63")
        guard let north = tags.plots.first(where: { $0.name == "北坡" })?.id,
              let south = tags.plots.first(where: { $0.name == "南坡" })?.id else {
            return XCTFail("必须造出两个地块")
        }
        tags.createOrUpdateAssignment(treeId: "T-01", plotId: north, tagIds: [], status: .scanned)
        tags.createOrUpdateAssignment(treeId: "T-02", plotId: south, tagIds: [], status: .reviewing)
        tags.createOrUpdateAssignment(treeId: "T-03", plotId: north, tagIds: [], status: .reviewing)
        await tags.waitForPendingSave()

        let now = Date()
        let records = [
            archiveRecord("T-01_20261020_090000_lat31_lon121", treeID: "T-01", scanDate: now),
            archiveRecord("T-02_20261021_090000_lat31_lon121", treeID: "T-02", scanDate: now),
            archiveRecord("T-03_20261021_090000_lat31_lon121", treeID: "T-03", scanDate: now)
        ]
        let store = ScanHistoryStore(recordsLoader: { .success(records) })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(ScanHistoryView(historyStore: store, tagStore: tags)
            .workspacePage(background: Design.Colors.Workspace.surface))

        let ready = try await ui.waitFor {
            ui.element(label: records[0].id) != nil && ui.element(label: records[1].id) != nil
        }
        XCTAssertTrue(ready)

        // 先选地块：北坡只剩一条。
        try await ui.selectMenu(label: L10n.History.allPlots, title: "北坡")
        try await ui.selectMenu(label: L10n.History.allStatuses, title: L10n.History.statusName(for: .scanned))
        let scoped = try await ui.waitFor {
            ui.element(label: records[0].id) != nil && ui.element(label: records[1].id) == nil && ui.element(label: records[2].id) == nil
        }
        XCTAssertTrue(scoped, "地块筛选后只剩北坡那条")

        // 再搜一个**在南坡**的树号：查询命中了，但交集被地块筛选排空。
        let field = try await searchField(in: ui)
        field.insertText("T-02")
        let excluded = try await ui.waitFor {
            ui.element(label: L10n.History.searchExcludedTitle) != nil
        }
        XCTAssertTrue(excluded, "搜索与地块筛选是交集：命中的那条不在当前地块内")
        XCTAssertNil(ui.element(label: L10n.History.searchNoMatchTitle),
                     "查询命中过就不能说「没有匹配的记录」")
        XCTAssertNil(ui.element(label: L10n.History.filteredEmptyTitle),
                     "有搜索词时走搜索专属文案，不是筛选文案")

        // 清除搜索：地块筛选**保留**，北坡那条回来。
        let clear = try XCTUnwrap(ui.element(label: L10n.History.clearSearch))
        XCTAssertTrue(clear.accessibilityActivate())
        let back = try await ui.waitFor {
            ui.element(label: records[0].id) != nil && ui.element(label: records[1].id) == nil && ui.element(label: records[2].id) == nil
        }
        XCTAssertTrue(back, "清除搜索后回到地块筛选的结果")
        XCTAssertNotNil(ui.element(label: "北坡"), "清除搜索不能把地块筛选一起清掉")
        XCTAssertNil(ui.element(label: L10n.History.allPlots))
        XCTAssertNotNil(ui.element(label: L10n.History.statusName(for: .scanned)))
        XCTAssertNil(ui.element(label: L10n.History.allStatuses))
    }

    /// 回归（真实原生视图）：查询**命中了**档案，但当前地块/状态筛选把它们都排空时，
    /// 页面不能说「没有树号或记录号包含 …」——
    /// 那条记录明明就在档案里，是筛选把它挡住了。
    ///
    /// 修前行为：这里显示的是 `searchNoMatchTitle`（说记录不存在），也没有「清除筛选」的出口。
    @MainActor
    func testArchiveSearchExplainsThatFiltersExcludedTheMatchingRecords() async throws {
        let suite = "ArchiveSearchExcluded-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tags = TagStore(defaults: defaults)
        tags.addPlot(name: "北坡", colorHex: "285E49")
        tags.addPlot(name: "南坡", colorHex: "6F8F63")
        guard let north = tags.plots.first(where: { $0.name == "北坡" })?.id,
              let south = tags.plots.first(where: { $0.name == "南坡" })?.id else {
            return XCTFail("必须造出两个地块")
        }
        tags.createOrUpdateAssignment(treeId: "T-01", plotId: north, tagIds: [], status: .scanned)
        tags.createOrUpdateAssignment(treeId: "T-02", plotId: south, tagIds: [], status: .reviewing)
        await tags.waitForPendingSave()

        let now = Date()
        let records = [
            archiveRecord("T-01_20261020_090000_lat31_lon121", treeID: "T-01", scanDate: now),
            archiveRecord("T-02_20261021_090000_lat31_lon121", treeID: "T-02", scanDate: now)
        ]
        let store = ScanHistoryStore(recordsLoader: { .success(records) })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(ScanHistoryView(historyStore: store, tagStore: tags)
            .workspacePage(background: Design.Colors.Workspace.surface))

        let ready = try await ui.waitFor {
            ui.element(label: records[0].id) != nil && ui.element(label: records[1].id) != nil
        }
        XCTAssertTrue(ready)

        // 先选地块：北坡只剩一条。
        try await ui.selectMenu(label: L10n.History.allPlots, title: "北坡")
        try await ui.selectMenu(label: L10n.History.allStatuses, title: L10n.History.statusName(for: .scanned))
        let scoped = try await ui.waitFor {
            ui.element(label: records[0].id) != nil && ui.element(label: records[1].id) == nil
        }
        XCTAssertTrue(scoped, "地块筛选后只剩北坡那条")

        // 再搜一个**在南坡**的树号：查询命中了 T-02，交集却是空的。
        let field = try await searchField(in: ui)
        field.insertText("T-02")
        let excluded = try await ui.waitFor {
            ui.element(label: L10n.History.searchExcludedTitle) != nil
        }
        XCTAssertTrue(excluded,
                      "查询命中了 T-02，却被地块筛选排空：文案必须说清是筛选排掉的")
        XCTAssertNil(ui.element(label: L10n.History.searchNoMatchTitle),
                     "查询命中过就不能说「没有匹配的记录」")
        XCTAssertNotEqual(L10n.History.searchExcludedTitle, L10n.History.searchNoMatchTitle)
        XCTAssertNotEqual(L10n.History.searchExcludedTitle, L10n.History.filteredEmptyTitle)
        // 文案带查询词，并说清是筛选排掉的（不是「没有这条记录」）。
        XCTAssertTrue(ui.accessibilityLabels().contains(L10n.History.searchExcludedMessage("T-02")),
                      "排除文案要带查询词")
        XCTAssertFalse(ui.accessibilityLabels().contains(L10n.History.searchNoMatchMessage("T-02")),
                       "不能说「没有树号或记录号包含查询词」")

        // 出口：清除筛选（**不动搜索**）。
        let clearFilters = try XCTUnwrap(ui.element(identifier: "historyEmpty.clearFilters"),
                                         "筛选排空时必须有清除筛选的出口")
        XCTAssertTrue(clearFilters.accessibilityActivate())
        let restored = try await ui.waitFor {
            ui.element(label: records[1].id) != nil
        }
        XCTAssertTrue(restored, "清除筛选后，查询命中的那条必须回来")
        // 查询**保留**：筛选清掉了，搜索词还在。
        let kept = try await searchField(in: ui)
        XCTAssertEqual(kept.text, "T-02", "清除筛选不能把搜索词一起清掉")
        XCTAssertNotNil(ui.element(label: L10n.History.allPlots))
        XCTAssertNotNil(ui.element(label: L10n.History.allStatuses))
    }

    @MainActor
    func testCorruptTreeSurveyOffersRecoveryWithoutUnlockingOrdinaryImport() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("positions.geojson")
        let original = Data("broken tree survey".utf8)
        try original.write(to: url)
        let catalog = TreeSurveyCatalog(fileURL: url)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(NavigationStack { TreeSurveyCatalogView(catalog: catalog) }
            .environment(\.dynamicTypeSize, .accessibility3))
        let ready = try await ui.waitFor { ui.element(identifier: "treeSurvey.recover") != nil }
        XCTAssertTrue(ready, "读取失败后必须提供 App 内的显式恢复入口")
        let recovery = try XCTUnwrap(ui.element(identifier: "treeSurvey.recover"))
        XCTAssertFalse(recovery.accessibilityTraits.contains(.notEnabled))
        XCTAssertTrue(try XCTUnwrap(ui.element(identifier: "treeSurvey.import")).accessibilityTraits.contains(.notEnabled))
        XCTAssertNotNil(catalog.loadError)
        XCTAssertTrue(catalog.points.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original, "仅打开恢复入口不能覆盖原档")
        let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first {
            $0.bounds.width > 200 && $0.contentSize.height > $0.bounds.height
        })
        let revealed = try await ui.reveal("从文件恢复树位档案", in: scroll)
        let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: nil)
            .intersection(ui.window.convert(ui.window.bounds, to: nil))
        XCTAssertTrue(viewport.insetBy(dx: -0.5, dy: -0.5).contains(revealed.accessibilityFrame))
        XCTAssertGreaterThanOrEqual(revealed.accessibilityFrame.height, 44)
        try await ui.attach(to: self, phase: "tree-survey-corrupt-accessibility-recovery")
    }

    @MainActor
    func testTreeSurveyRecoveryPreviewRequiresExplicitConfirmationBeforeSaving() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("positions.geojson")
        let original = Data("broken tree survey".utf8)
        try original.write(to: url)
        let catalog = TreeSurveyCatalog(fileURL: url)
        let snapshot = try catalog.prepareRecovery()
        let points = [TreeSurveyPoint(treeID: "QA-TREE-001", longitude: 121, latitude: 31,
            horizontalAccuracyMeters: 0.1, method: .totalStation,
            measuredAt: "2026-01-01T00:00:00Z", sourceNote: "UI fixture")]
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        var backup: URL?
        var saveError: Error?
        ui.mount(TreeSurveyImportPreview(batch: TreeSurveyImport(points: points, recovery: snapshot), catalog: catalog) { imported, confirmed in
            do { backup = try catalog.recover(imported, from: snapshot, confirmed: confirmed) }
            catch { saveError = error }
        }.environment(\.dynamicTypeSize, .accessibility3))
        let ready = try await ui.waitFor { ui.element(label: "保存") != nil }
        XCTAssertTrue(ready)
        XCTAssertTrue(try XCTUnwrap(ui.element(label: "保存")).accessibilityTraits.contains(.notEnabled))
        XCTAssertEqual(try Data(contentsOf: url), original)
        let toggle = try XCTUnwrap(ui.element(identifier: "treeSurvey.confirmRecovery"))
        if let control = toggle as? UISwitch {
            control.setOn(true, animated: false)
            control.sendActions(for: .valueChanged)
        } else { XCTAssertTrue(toggle.accessibilityActivate()) }
        let enabled = try await ui.waitFor {
            ui.element(label: "保存")?.accessibilityTraits.contains(.notEnabled) == false
        }
        XCTAssertTrue(enabled)
        try await ui.attach(to: self, phase: "tree-survey-recovery-confirmed-accessibility")
        XCTAssertTrue(try XCTUnwrap(ui.element(label: "保存")).accessibilityActivate())
        let saved = try await ui.waitFor { backup != nil || saveError != nil }
        XCTAssertTrue(saved)
        XCTAssertNil(saveError)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backup)), original)
        XCTAssertEqual(TreeSurveyCatalog(fileURL: url).points, points)
    }

    @MainActor
    func testTreeSurveyRecoveryPickerCancellationAndInvalidSelectionKeepOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("positions.geojson")
        let original = Data("broken original".utf8)
        try original.write(to: url)
        let invalid = folder.appendingPathComponent("invalid.geojson")
        try Data("bad import".utf8).write(to: invalid)
        let catalog = TreeSurveyCatalog(fileURL: url)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(NavigationStack { TreeSurveyCatalogView(catalog: catalog) })
        func picker(in controller: UIViewController) -> UIDocumentPickerViewController? {
            if let current = controller as? UIDocumentPickerViewController { return current }
            if let presented = controller.presentedViewController, let found = picker(in: presented) { return found }
            return controller.children.lazy.compactMap { picker(in: $0) }.first
        }
        func openPicker() async throws -> UIDocumentPickerViewController {
            let ready = try await ui.waitFor { ui.element(identifier: "treeSurvey.recover") != nil }
            XCTAssertTrue(ready)
            XCTAssertTrue(try XCTUnwrap(ui.element(identifier: "treeSurvey.recover")).accessibilityActivate())
            let presented = try await ui.waitFor({ picker(in: ui.controller) != nil }, timeout: 10)
            XCTAssertTrue(presented)
            try await ui.waitForSheetReady()
            return try XCTUnwrap(picker(in: ui.controller))
        }
        let cancelled = try await openPicker()
        try XCTUnwrap(cancelled.delegate).documentPickerWasCancelled?(cancelled)
        // UIKit normally dismisses its picker around these delegate callbacks.
        cancelled.dismiss(animated: false)
        let closed = try await ui.waitFor { ui.controller.presentedViewController == nil }
        XCTAssertTrue(closed)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertTrue(catalog.points.isEmpty)
        let selecting = try await openPicker()
        // Drive the real native picker's public delegate with invocation-owned
        // files. This covers production importer callbacks, not Files-app taps.
        try XCTUnwrap(selecting.delegate).documentPicker?(selecting, didPickDocumentsAt: [invalid])
        selecting.dismiss(animated: false)
        let failed = try await ui.waitFor {
            ui.controller.presentedViewController == nil && ui.element(identifier: "treeSurvey.operationError") != nil
        }
        XCTAssertTrue(failed, "最新导入错误不能被旧的档案读取错误遮住")
        XCTAssertNotNil(ui.element(identifier: "treeSurvey.error"))
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertNotNil(catalog.loadError)
        XCTAssertTrue(catalog.points.isEmpty)
        try await ui.attach(to: self, phase: "tree-survey-invalid-import-keeps-original")
    }

    @MainActor
    @available(iOS 17, *)
    func testOrchardMapRemainsUsableInNarrowShortWindow() async throws {
        let record = ScanFileRecord(id: "map-layout", treeID: "QA-TREE-WITH-A-LONG-IDENTITY-001",
            fileURL: URL(fileURLWithPath: "/tmp/map-layout.ply"), scanDate: Date(),
            fruitCount: 12, yieldKg: 1.5, gpsLat: 31, gpsLon: 121)
        let store = ScanHistoryStore(recordsLoader: { .success([record]) })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 500)
        ui.mount(OrchardMapView(historyStore: store))
        let ready = try await ui.waitFor {
            !store.isLoading && ui.elements.contains { $0 is MKMapView }
        }
        XCTAssertTrue(ready)
        let map = try XCTUnwrap(ui.elements.compactMap { $0 as? MKMapView }.first)
        var viewport = map.convert(map.bounds, to: ui.window).intersection(ui.window.bounds)
        var ancestor = map.superview
        while let current = ancestor {
            if let scroll = current as? UIScrollView {
                viewport = viewport.intersection(scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: ui.window))
            }
            ancestor = current.superview
        }
        try await ui.attach(to: self, phase: "orchard-map-narrow-short")
        XCTAssertGreaterThanOrEqual(viewport.width, 120, "地图必须能容纳真实44pt标记及上下文")
        XCTAssertGreaterThanOrEqual(viewport.height, 120)
    }

    @MainActor
    @available(iOS 17, *)
    func testOrchardMapFullPageMixedRecordsAndLongTreeStayOperableAtAccessibilitySizes() async throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 874, height: 402), CGSize(width: 744, height: 650)] {
            let records = [
                ScanFileRecord(id: "map-low", treeID: "QA-TREE-WITH-A-LONG-IDENTITY-001",
                    fileURL: URL(fileURLWithPath: "/tmp/map-low.ply"), scanDate: Date(),
                    fruitCount: 12, yieldKg: 1.5, gpsLat: 31, gpsLon: 121),
                ScanFileRecord(id: "map-high", treeID: "QA-HIGH", fileURL: URL(fileURLWithPath: "/tmp/map-high.ply"),
                    scanDate: Date(), fruitCount: 40, yieldKg: 50, gpsLat: 31.001, gpsLon: 121.001),
                ScanFileRecord(id: "map-no-gps", treeID: "QA-NO-GPS", fileURL: URL(fileURLWithPath: "/tmp/map-no-gps.ply"), scanDate: Date())
            ]
            let store = ScanHistoryStore(recordsLoader: { .success(records) })
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            ui.window.frame = CGRect(origin: .zero, size: size)
            ui.mount(OrchardMapView(historyStore: store).environment(\.dynamicTypeSize, .accessibility5))
            let ready = try await ui.waitFor { !store.isLoading && ui.elements.contains { $0 is MKMapView } }
            XCTAssertTrue(ready)
            let map = try XCTUnwrap(ui.elements.compactMap { $0 as? MKMapView }.first)
            func panelScroll() throws -> UIScrollView {
                try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.filter { scroll in
                    var ancestor = scroll.superview
                    while let current = ancestor {
                        if current is MKMapView { return false }
                        ancestor = current.superview
                    }
                    return scroll.bounds.width > 200
                }.max { $0.contentSize.height < $1.contentSize.height })
            }
            func reveal(_ label: String) async throws -> NSObject {
                let scroll = try panelScroll()
                XCTAssertGreaterThanOrEqual(scroll.bounds.height, 120, "完整页面必须给操作区留下可滚动空间")
                let control = try await ui.reveal(label, in: scroll)
                let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: nil)
                    .intersection(ui.window.convert(ui.window.bounds, to: nil))
                XCTAssertTrue(viewport.insetBy(dx: -0.5, dy: -0.5).contains(control.accessibilityFrame), label)
                XCTAssertGreaterThanOrEqual(control.accessibilityFrame.height + 0.001, 44, label)
                return control
            }
            try await ui.attach(to: self, phase: "orchard-mixed-AX5-\(Int(size.width))-entry")
            let scroll = try panelScroll()
            XCTAssertGreaterThanOrEqual(scroll.bounds.height, 120)
            guard scroll.bounds.height >= 120 else { continue }
            let annotationReady = try await ui.waitFor {
                map.annotations.contains { abs($0.coordinate.latitude - 31) < 0.000001 }
            }
            XCTAssertTrue(annotationReady)
            map.selectAnnotation(try XCTUnwrap(map.annotations.first { abs($0.coordinate.latitude - 31) < 0.000001 }), animated: false)
            let presentation = OrchardMapPresentation()
            let selected = try await ui.waitFor { ui.element(label: presentation.closeDetails) != nil }
            XCTAssertTrue(selected)
            let close = try await reveal(presentation.closeDetails)
            try await ui.attach(to: self, phase: "orchard-mixed-AX5-\(Int(size.width))-long-tree")
            XCTAssertTrue(close.accessibilityActivate())
            let medium = try await reveal(presentation.yieldLevelLabel(.medium))
            XCTAssertTrue(medium.accessibilityActivate())
            let cleared = try await ui.waitFor { ui.element(label: presentation.clearFilter) != nil }
            XCTAssertTrue(cleared)
            XCTAssertNil(ui.element(label: presentation.closeDetails))
            let clear = try await reveal(presentation.clearFilter)
            try await ui.attach(to: self, phase: "orchard-mixed-AX5-\(Int(size.width))-empty-filter")
            XCTAssertTrue(clear.accessibilityActivate())
            let restored = try await ui.waitFor { ui.element(label: presentation.clearFilter) == nil }
            XCTAssertTrue(restored)
            let archive = try await reveal(presentation.archiveActionTitle)
            XCTAssertTrue(archive.accessibilityActivate())
            let opened = try await ui.waitFor { ui.controller.presentedViewController != nil && ui.element(label: L10n.Common.done) != nil }
            XCTAssertTrue(opened)
            try await ui.waitForSheetReady()
            XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.done)).accessibilityActivate())
            let returned = try await ui.waitFor { ui.controller.presentedViewController == nil }
            XCTAssertTrue(returned)
            XCTAssertNotNil(ui.element(label: presentation.closeMap))
        }
    }

    @MainActor
    @available(iOS 17, *)
    func testOrchardMapEmptyAndUnlocatedFallbackActionsPreserveArchiveAndReturn() async throws {
        let unlocated = ScanFileRecord(id: "without-location.ply", treeID: "QA-NO-GPS",
            fileURL: URL(fileURLWithPath: "/tmp/without-location.ply"), scanDate: Date())
        for records in [[ScanFileRecord](), [unlocated]] {
            let store = ScanHistoryStore(recordsLoader: { .success(records) })
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            var starts = 0
            ui.mount(OrchardMapView(onStartScan: { starts += 1 }, historyStore: store)
                .environment(\.dynamicTypeSize, .accessibility5))
            let ready = try await ui.waitFor { !store.isLoading && ui.element(identifier: "orchard.map.openArchive") != nil }
            XCTAssertTrue(ready)
            XCTAssertFalse(ui.elements.contains { $0 is MKMapView }, "无定位记录不能补造坐标")
            let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.bounds.width > 200 })
            func reveal(_ identifier: String) async throws -> NSObject {
                let label = try XCTUnwrap(ui.element(identifier: identifier)?.accessibilityLabel)
                let action = try await ui.reveal(label, in: scroll)
                let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: nil)
                    .intersection(ui.window.convert(ui.window.bounds, to: nil))
                XCTAssertTrue(viewport.insetBy(dx: -0.5, dy: -0.5).contains(action.accessibilityFrame))
                return action
            }
            let archive = try await reveal("orchard.map.openArchive")
            try await ui.attach(to: self, phase: "orchard-empty-AX5-actions-\(records.count)")
            XCTAssertTrue(archive.accessibilityActivate())
            let opened = try await ui.waitFor { ui.controller.presentedViewController != nil && ui.element(label: L10n.Common.done) != nil }
            XCTAssertTrue(opened)
            try await ui.waitForSheetReady()
            if records.isEmpty {
                let startReady = try await ui.waitFor { ui.element(label: L10n.History.startScan) != nil }
                XCTAssertTrue(startReady)
                XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.History.startScan)).accessibilityActivate())
                let handedOff = try await ui.waitFor { starts == 1 && ui.controller.presentedViewController == nil }
                XCTAssertTrue(handedOff, "档案的开始扫描必须关闭子页并交接一次")
            } else {
                let historyReady = try await ui.waitFor {
                    ui.elements.compactMap { $0 as? UIScrollView }.contains { $0.refreshControl != nil }
                }
                XCTAssertTrue(historyReady)
                let historyScroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.refreshControl != nil })
                let row = try await ui.reveal(unlocated.fileURL.lastPathComponent, in: historyScroll)
                let historyViewport = historyScroll.convert(historyScroll.bounds.inset(by: historyScroll.adjustedContentInset), to: nil)
                    .intersection(ui.window.convert(ui.window.bounds, to: nil))
                XCTAssertTrue(historyViewport.insetBy(dx: -0.5, dy: -0.5).contains(row.accessibilityFrame))
                XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.done)).accessibilityActivate())
                let returned = try await ui.waitFor { ui.controller.presentedViewController == nil }
                XCTAssertTrue(returned)
                let start = try await reveal("orchard.map.startScan")
                XCTAssertTrue(start.accessibilityActivate())
                XCTAssertEqual(starts, 1)
            }
            XCTAssertEqual(store.scanFiles, records)
        }
    }

    /// 回归（真实原生视图）：三种「看不到记录」必须分开说 ——
    /// 档案是空的、搜索没命中、筛选没命中，各有各的话。
    @MainActor
    func testArchiveEmptyArchiveAndSearchNoMatchUseDistinctStates() async throws {
        let suite = "ArchiveEmptyStates-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tags = TagStore(defaults: defaults)

        // 1) 档案一条都没有：空档案文案，**不摆搜索框**。
        let emptyStore = ScanHistoryStore(recordsLoader: { .success([]) })
        let emptyUI = try RootLaunchUIHarness()
        defer { emptyUI.close() }
        emptyUI.mount(ScanHistoryView(historyStore: emptyStore, tagStore: tags)
            .workspacePage(background: Design.Colors.Workspace.surface))
        let emptyReady = try await emptyUI.waitFor {
            emptyUI.element(label: L10n.History.emptyTitle) != nil
        }
        XCTAssertTrue(emptyReady, "档案为空时必须说清楚")
        XCTAssertTrue(emptyUI.elements.compactMap { $0 as? UITextField }
            .allSatisfy { $0.accessibilityLabel != L10n.History.searchFieldLabel },
                      "一条记录都没有时不摆搜索框")

        // 2) 有档案但搜索没命中：搜索专属文案 + 清除搜索。
        let record = archiveRecord("T-01_20261020_090000_lat31_lon121", treeID: "T-01", scanDate: Date())
        let store = ScanHistoryStore(recordsLoader: { .success([record]) })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(ScanHistoryView(historyStore: store, tagStore: tags)
            .workspacePage(background: Design.Colors.Workspace.surface))
        let ready = try await ui.waitFor { ui.element(label: record.id) != nil }
        XCTAssertTrue(ready)
        let field = try await searchField(in: ui)
        field.insertText("ZZZ")
        let noMatch = try await ui.waitFor {
            ui.element(label: L10n.History.searchNoMatchTitle) != nil
        }
        XCTAssertTrue(noMatch, "搜索没命中必须有自己的文案")
        XCTAssertNotEqual(L10n.History.searchNoMatchTitle, L10n.History.filteredEmptyTitle)
        XCTAssertNotEqual(L10n.History.searchNoMatchTitle, L10n.History.emptyTitle)
        // 文案里说清是哪个条件筛空的。
        let message = ui.accessibilityLabels().first { $0.contains("ZZZ") }
        XCTAssertNotNil(message, "无匹配文案要带上搜索词")
        // 有「清除搜索」这个动作。
        XCTAssertNotNil(ui.element(label: L10n.History.clearSearch))
        // 空态里那个出口（不是搜索框里的叉）：激活后档案回来。
        let exit = try XCTUnwrap(ui.element(identifier: "historyEmpty.clearSearch"),
                                 "没命中时必须有一个清搜索的出口")
        XCTAssertTrue(exit.accessibilityActivate())
        let back = try await ui.waitFor { ui.element(label: record.id) != nil }
        XCTAssertTrue(back, "清除搜索后档案必须回来")
    }

    /// 回归（真实原生视图）：刷新后列表结果随数据变化，
    /// 而 query 与筛选**保持不变**。
    @MainActor
    func testArchiveSearchSurvivesRefreshAndFollowsNewRecords() async throws {
        let suite = "ArchiveSearchRefresh-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tags = TagStore(defaults: defaults)
        let now = Date()
        let first = archiveRecord("T-01_20261020_090000_lat31_lon121", treeID: "T-01", scanDate: now)
        let second = archiveRecord("T-02_20261021_090000_lat31_lon121", treeID: "T-02", scanDate: now)
        let third = archiveRecord("T-03_20261022_090000_lat31_lon121", treeID: "T-03", scanDate: now)
        // 第一次加载两条，刷新后三条：结果必须跟着数据走。
        let sequence = DashboardHistorySequence([.success([first, second]), .success([first, second, third])])
        let store = ScanHistoryStore(recordsLoader: { await sequence.load() })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(ScanHistoryView(historyStore: store, tagStore: tags)
            .workspacePage(background: Design.Colors.Workspace.surface))

        let ready = try await ui.waitFor {
            ui.element(label: first.id) != nil && ui.element(label: second.id) != nil
        }
        XCTAssertTrue(ready)
        let field = try await searchField(in: ui)
        field.insertText("T-0")
        let filtered = try await ui.waitFor {
            ui.element(label: first.id) != nil && ui.element(label: second.id) != nil
        }
        XCTAssertTrue(filtered)
        XCTAssertNil(ui.element(label: third.id), "还没刷新的档案不该出现")

        // 刷新（走生产刷新入口）。
        await store.reloadRecords()
        let refreshed = try await ui.waitFor { ui.element(label: third.id) != nil }
        XCTAssertTrue(refreshed, "刷新后新增的档案必须出现在结果里")
        XCTAssertNotNil(ui.element(label: first.id))
        XCTAssertNotNil(ui.element(label: second.id))
        // 查询词还在：刷新不该把搜索条件清掉。
        let after = try await searchField(in: ui)
        XCTAssertEqual(after.text, "T-0", "刷新后搜索词必须还在")
    }

    /// 回归（真实原生视图）：档案按真实扫描日期分成今天/昨天/更早，
    /// 组标题带这一段有几份。
    @MainActor
    func testArchiveDateGroupHeadersRenderWithCounts() async throws {
        let suite = "ArchiveGroups-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tags = TagStore(defaults: defaults)
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let earlier = calendar.date(byAdding: .day, value: -5, to: now) ?? now
        let records = [
            archiveRecord("today-1", treeID: "T-01", scanDate: now),
            archiveRecord("today-2", treeID: "T-02", scanDate: now),
            archiveRecord("yesterday", treeID: "T-03", scanDate: yesterday),
            archiveRecord("earlier", treeID: "T-04", scanDate: earlier)
        ]
        let store = ScanHistoryStore(recordsLoader: { .success(records) })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(ScanHistoryView(historyStore: store, tagStore: tags)
            .workspacePage(background: Design.Colors.Workspace.surface))

        func header(_ title: String, _ count: Int) -> String {
            String.localizedStringWithFormat(L10n.History.groupCountFormat, title, count)
        }
        let ready = try await ui.waitFor {
            ui.element(label: header(L10n.History.groupToday, 2)) != nil &&
                ui.element(label: header(L10n.History.groupYesterday, 1)) != nil &&
                ui.element(label: header(L10n.History.groupEarlier, 1)) != nil
        }
        XCTAssertTrue(ready, "今天/昨天/更早三段都要出现，并写清各有几份")
        // 四条档案都在（分组不吞档案）。
        for record in records {
            XCTAssertNotNil(ui.element(label: record.id), "档案必须还在：\(record.id)")
        }
        // 顺序：今天在前，更早在后。
        let order = ui.accessibilityLabels()
        let todayIndex = order.firstIndex { $0 == header(L10n.History.groupToday, 2) }
        let yesterdayIndex = order.firstIndex { $0 == header(L10n.History.groupYesterday, 1) }
        let earlierIndex = order.firstIndex { $0 == header(L10n.History.groupEarlier, 1) }
        XCTAssertNotNil(todayIndex)
        XCTAssertNotNil(yesterdayIndex)
        XCTAssertNotNil(earlierIndex)
        if let todayIndex, let yesterdayIndex, let earlierIndex {
            XCTAssertLessThan(todayIndex, yesterdayIndex)
            XCTAssertLessThan(yesterdayIndex, earlierIndex)
        }
    }

    /// 回归：搜索框与组标题在受支持的机型宽度、横屏与 iPad 分屏下不横向溢出，
    /// 清除入口始终够得着（44pt）；辅助字号下同样不溢出。
    @MainActor
    func testArchiveSearchFieldAndGroupHeadersFitSupportedWidthsAndAccessibilitySizes() async throws {
        let suite = "ArchiveSearchLayout-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tags = TagStore(defaults: defaults)
        let now = Date()
        let records = [
            archiveRecord("T-01_20261020_090000_lat31_lon121", treeID: "T-01", scanDate: now),
            archiveRecord("T-02_20261021_090000_lat31_lon121", treeID: "T-02", scanDate: now)
        ]
        let store = ScanHistoryStore(recordsLoader: { .success(records) })
        let sizes: [(String, CGSize)] = [
            ("375", CGSize(width: 375, height: 812)),
            ("390", CGSize(width: 390, height: 844)),
            ("430", CGSize(width: 430, height: 932)),
            ("landscape-844", CGSize(width: 844, height: 390)),
            ("ipad-split-507", CGSize(width: 507, height: 1024))
        ]
        for (name, size) in sizes {
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            ui.window.frame = CGRect(origin: .zero, size: size)
            ui.mount(ScanHistoryView(historyStore: store, tagStore: tags)
                .workspacePage(background: Design.Colors.Workspace.surface))
            let ready = try await ui.waitFor { ui.element(label: records[0].id) != nil }
            XCTAssertTrue(ready, "\(name): 档案必须出现")

            let field = try await searchField(in: ui)
            // 输入框的无障碍矩形就是控件本体：不能横向溢出，也不能越过左边界。
            XCTAssertLessThanOrEqual(field.accessibilityFrame.maxX, size.width + 0.5,
                                     "\(name): 搜索框不得横向溢出 \(field.accessibilityFrame)")
            XCTAssertGreaterThanOrEqual(field.accessibilityFrame.minX, -0.5,
                                        "\(name): 搜索框不得越过左边界")

            // 清除入口：只有查询非空时出现，且够得着。
            // 它与输入框同在这一行，所以它的高度也就是**整行**的高度。
            field.insertText("T-01")
            let clearReady = try await ui.waitFor { ui.element(label: L10n.History.clearSearch) != nil }
            XCTAssertTrue(clearReady, "\(name): 清除入口必须出现")
            let clear = try XCTUnwrap(ui.element(label: L10n.History.clearSearch))
            XCTAssertGreaterThanOrEqual(clear.accessibilityFrame.width, 43.5, "\(name): 清除入口宽度")
            XCTAssertGreaterThanOrEqual(clear.accessibilityFrame.height, 43.5,
                                        "\(name): 搜索行高度（清除入口同在这一行）")
            XCTAssertLessThanOrEqual(clear.accessibilityFrame.maxX, size.width + 0.5,
                                     "\(name): 清除入口不得横向溢出")
        }

        // 辅助字号：搜索框与组标题同样不横向溢出。
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        ui.mount(ScanHistoryView(historyStore: store, tagStore: tags)
            .workspacePage(background: Design.Colors.Workspace.surface)
            .dynamicTypeSize(.accessibility5))
        let ready = try await ui.waitFor { ui.element(label: records[0].id) != nil }
        XCTAssertTrue(ready, "辅助字号下档案必须出现")
        let field = try await searchField(in: ui)
        XCTAssertLessThanOrEqual(field.accessibilityFrame.maxX, 390.5,
                                 "辅助字号下搜索框不得横向溢出")
        XCTAssertGreaterThanOrEqual(field.accessibilityFrame.height, 21.5,
                                    "辅助字号下输入框仍在（字号放大只会更高）")
        let header = String.localizedStringWithFormat(L10n.History.groupCountFormat,
                                                      L10n.History.groupToday, 2)
        let headerReady = try await ui.waitFor { ui.element(label: header) != nil }
        XCTAssertTrue(headerReady, "辅助字号下组标题必须出现")
    }

    /// 找到档案页的搜索框（按无障碍标签认，不靠索引）。
    @MainActor
    private func searchField(in ui: RootLaunchUIHarness) async throws -> UITextField {
        let ready = try await ui.waitFor {
            ui.elements.compactMap { $0 as? UITextField }
                .contains { $0.accessibilityLabel == L10n.History.searchFieldLabel }
        }
        XCTAssertTrue(ready, "档案页必须有搜索框")
        return try XCTUnwrap(ui.elements.compactMap { $0 as? UITextField }
            .first { $0.accessibilityLabel == L10n.History.searchFieldLabel })
    }

    /// 回归：档案行的版式是**真的**落在纸上 ——
    /// 读数是独立右列（右缘对齐）、数字用的是 24pt 的字、身份与读数之间是分开的列。
    ///
    /// 只看朗读值与常量是不够的：把读数挪回身份列、把字号改成 13pt，测试照样绿。
    @MainActor
    func testArchiveRowLaysOutReadingAsSeparateRightColumnAtPrototypeTypeScale() throws {
        let record = ScanFileRecord(
            id: "layout.ply", treeID: "T-1",
            fileURL: URL(fileURLWithPath: "/tmp/layout.ply"),
            scanDate: Date(), fruitCount: 8, yieldKg: 12.3, confidence: "high"
        )
        let width: CGFloat = 320
        let ink = try XCTUnwrap(renderInk(InstrumentScanRow(record: record, layout: .archive), width: width))

        // 1) 读数右缘与内容右缘对齐：它是一列右对齐的数字，不是跟着身份走的行内文字。
        let rightmost = try XCTUnwrap(ink.rightmostInkX)
        XCTAssertGreaterThanOrEqual(CGFloat(rightmost) / ink.scale, width - 3,
                                    "读数应当贴着右缘，实际右缘 \(CGFloat(rightmost) / ink.scale)pt")

        // 2) 读数列里有一处**高**笔画：那是被真正画出来的 24pt 数字（13pt 的笔画只有 ~9pt 高）。
        let tallest = ink.tallestInkHeight(inRightBandPoints: 90)
        XCTAssertGreaterThanOrEqual(CGFloat(tallest) / ink.scale, 14,
                                    "读数应当是 24pt 的大字，实际最高笔画 \(CGFloat(tallest) / ink.scale)pt")

        // 3) 身份与读数之间是空白列：两者是分开的列，不是同一段文字。
        XCTAssertGreaterThanOrEqual(CGFloat(ink.gapBeforeRightmostRun) / ink.scale, 20,
                                    "读数与身份之间应当有空列，实际 \(CGFloat(ink.gapBeforeRightmostRun) / ink.scale)pt")
    }

    /// 离屏渲染一个视图，量出墨迹（深色笔画）的几何。
    ///
    /// 用来把版式断言变成机器可判的：只读朗读值与常量的话，
    /// 把读数挪回身份列、把字号改小，测试照样会绿。
    @MainActor
    private func renderInk(_ view: some View, width: CGFloat) -> ArchiveRowInk? {
        let renderer = ImageRenderer(content: view.frame(width: width))
        renderer.scale = 2
        renderer.render { _, _ in }
        guard let cgImage = renderer.cgImage else { return nil }
        let widthPx = cgImage.width
        let heightPx = cgImage.height
        var pixels = [UInt8](repeating: 255, count: widthPx * heightPx * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base,
                    width: widthPx,
                    height: heightPx,
                    bitsPerComponent: 8,
                    bytesPerRow: widthPx * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: widthPx, height: heightPx))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: widthPx, height: heightPx))
        }
        var counts = [Int](repeating: 0, count: widthPx)
        var tops = [Int](repeating: 0, count: widthPx)
        var bottoms = [Int](repeating: -1, count: widthPx)
        for y in 0..<heightPx {
            for x in 0..<widthPx {
                let offset = (y * widthPx + x) * 4
                let luminance = (Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3
                if luminance < 220 {
                    counts[x] += 1
                    if bottoms[x] < 0 { tops[x] = y }
                    bottoms[x] = y
                }
            }
        }
        return ArchiveRowInk(
            scale: 2,
            columnInkCount: counts,
            columnInkTop: tops,
            columnInkBottom: bottoms
        )
    }

    /// 把窗口截图写到临时目录，供交付前人工审阅（渲染只在宿主内完成）。
    @MainActor
    private func writeArchiveRowScreenshot(_ ui: RootLaunchUIHarness, name: String) async throws {
        try await Task.sleep(nanoseconds: 350_000_000)
        ui.window.layoutIfNeeded()
        CATransaction.flush()
        let image = UIGraphicsImageRenderer(bounds: ui.window.bounds).image { _ in
            ui.window.drawHierarchy(in: ui.window.bounds, afterScreenUpdates: true)
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fts-archive-row-shots", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        let data = try XCTUnwrap(image.pngData())
        try data.write(to: url)
        print("ARCHIVE_ROW_SHOT \(url.path)")
    }

    @MainActor
    func testHistoryRendersNativeRecordAndRecoveryStatesAtSupportedConstraints() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "HistoryVisual-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tags = TagStore(defaults: defaults)
        tags.addPlot(name: "东坡 · A区", colorHex: "285E49")
        tags.createOrUpdateAssignment(treeId: "T012", plotId: tags.plots.first?.id, tagIds: [], status: .scanned)
        await tags.waitForPendingSave()
        let now = Date(timeIntervalSince1970: 1_792_300_000)
        func record(_ id: String, state: ScanPersistenceState, reason: String? = nil) throws -> ScanFileRecord {
            let url = directory.appendingPathComponent(id + ".ply")
            try PLYPointCloudWriter.write(points: [ColoredPoint(pos: SIMD3<Float>(0, 1, 0), r: 0.3, g: 0.7, b: 0.2)],
                                          treeID: id, scanDate: "2026-10-18 10:00:00", gpsLat: 0, gpsLon: 0, to: url)
            return ScanFileRecord(id: url.lastPathComponent, treeID: id, fileURL: url, scanDate: now,
                                  fruitCount: 16, yieldKg: 4.2, confidence: "HIGH", fileSizeBytes: 1_240,
                                  persistenceState: state, persistenceFailureReason: reason)
        }
        let complete = try record("T012", state: .complete)
        let recovery = try record("T013", state: .incomplete, reason: "orphanPLYDetected")
        let damaged = try record("T014", state: .invalid, reason: "scanResultRevisionMismatch")
        let longIdentifier = try record("UI-HISTORY-CANCEL", state: .incomplete, reason: "orphanPLYDetected")
        let originals = try archiveBytes(in: directory)
        let layouts: [(String, CGSize, DynamicTypeSize)] = [
            ("phone", CGSize(width: 402, height: 874), .large),
            ("landscape", CGSize(width: 874, height: 402), .large),
            ("tablet", CGSize(width: 1024, height: 1366), .large),
            ("accessibility", CGSize(width: 402, height: 874), .accessibility3),
            ("landscape-accessibility", CGSize(width: 874, height: 402), .accessibility3)
        ]
        for (layout, size, textSize) in layouts {
            for name in ["records", "long-identifier", "recovery", "damaged", "stale", "empty", "filtered", "failure", "loading", "delete-confirmation"] {
                let records = name == "empty" || name == "failure" || name == "loading" ? [] :
                    name == "long-identifier" ? [longIdentifier] : name == "recovery" ? [recovery] : name == "damaged" ? [complete, damaged] :
                    name == "delete-confirmation" || name == "filtered" ? [complete] : [complete, recovery]
                let sequence = DashboardHistorySequence(name == "stale" ? [.success(records), .failure(.directoryUnavailable)] :
                                                            name == "failure" ? [.failure(.directoryUnavailable)] : [.success(records)])
                let gate = HistoryVisualLoadGate()
                let store = ScanHistoryStore(recordsLoader: {
                    if name == "loading" { return await gate.load() }
                    return await sequence.load()
                })
                if name == "stale" { await store.reloadRecords() }
                let ui = try RootLaunchUIHarness()
                ui.window.frame = CGRect(origin: .zero, size: size)
                var starts = 0
                var imports = 0
                ui.mount(HistorySheetView(onStartScan: { starts += 1 }, onRescanTree: { _ in }, onImportFile: { imports += 1 },
                                         historyStore: store, tagStore: tags)
                    .workspacePage(background: Design.Colors.Workspace.surface)
                    .dynamicTypeSize(textSize)
                    .environment(\.horizontalSizeClass, layout == "tablet" ? .regular : .compact)
                    .environment(\.verticalSizeClass, layout.hasPrefix("landscape") ? .compact : .regular))
                let ready = try await ui.waitFor {
                    name == "loading" ? store.isLoading : !store.isLoading &&
                        ((name == "stale" || name == "failure") ? store.loadFailure != nil : store.scanFiles == records)
                }
                XCTAssertTrue(ready)
                if name == "filtered" {
                    try await ui.selectMenu(label: L10n.History.allStatuses, title: L10n.History.statusName(for: .reviewing))
                    let filtered = try await ui.waitFor { ui.element(label: L10n.History.filteredEmptyTitle) != nil }
                    XCTAssertTrue(filtered)
                }
                if name == "delete-confirmation" {
                    try await ui.selectMenu(label: L10n.History.moreActions, title: L10n.History.deleteRecord)
                    let opened = try await ui.waitFor { ui.element(label: L10n.Common.cancel) != nil }
                    XCTAssertTrue(opened)
                }
                try await ui.attach(to: self, phase: "History-\(name)-\(layout)-synthetic")
                if textSize.isAccessibilitySize, name != "loading", name != "delete-confirmation",
                   let scroll = ui.elements.compactMap({ $0 as? UIScrollView }).first(where: { $0.refreshControl != nil }) ??
                    ui.elements.compactMap({ $0 as? UIScrollView }).max(by: { $0.bounds.height < $1.bounds.height }) {
                    let target = name == "empty" ? L10n.History.importPLY : name == "failure" ?
                        NSLocalizedString("history.load.retry", value: "重试", comment: "") : name == "filtered" ? L10n.History.filteredEmptyTitle :
                        L10n.History.moreActions
                    _ = try await ui.reveal(target, in: scroll)
                    try await ui.attach(to: self, phase: "History-\(name)-\(layout)-bottom-synthetic")
                    if name == "empty" {
                        for label in [L10n.History.startScan, L10n.History.importPLY] {
                            let button = try await ui.reveal(label, in: scroll)
                            XCTAssertGreaterThanOrEqual(button.accessibilityFrame.height, 43.5)
                            XCTAssertTrue(button.accessibilityActivate())
                        }
                        XCTAssertEqual(starts, 1)
                        XCTAssertEqual(imports, 1)
                    } else if name == "failure" {
                        let before = await sequence.loadCount
                        let retry = try await ui.reveal(target, in: scroll)
                        XCTAssertTrue(retry.accessibilityActivate())
                        let deadline = Date().addingTimeInterval(3)
                        while await sequence.loadCount == before, Date() < deadline {
                            try await Task.sleep(nanoseconds: 20_000_000)
                        }
                        let count = await sequence.loadCount
                        XCTAssertEqual(count, before + 1)
                    }
                }
                if name == "delete-confirmation" {
                    // UIKit alert action representations do not implement accessibilityActivate.
                    // This renderer checks the real dialog and dismisses its host; simulator
                    // touch acceptance separately verifies the production Cancel button.
                    try ui.dismissSystemAlert()
                    let closed = try await ui.waitFor { ui.element(label: L10n.Common.cancel) == nil }
                    XCTAssertTrue(closed)
                }
                ui.close()
                await gate.finish()
                XCTAssertEqual(try archiveBytes(in: directory), originals)
                XCTAssertEqual(store.scanFiles, name == "loading" ? [] : records)
            }
        }
        await tags.waitForPendingSave()
        XCTAssertEqual(tags.assignments.count, 1)
    }

    @MainActor
    func testHistoryDamageFeedbackLeavesAUsableRecordViewportAtCompactLargeText() async throws {
        let damaged = makeRecord(id: "damaged-viewport", treeID: "T014", scanDate: Date(),
                                 yieldKg: 42, persistenceState: .invalid)
        let store = ScanHistoryStore(recordsLoader: { .success([damaged]) })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
        var rescans: [String] = []
        ui.mount(HistorySheetView(onRescanTree: { rescans.append($0) }, historyStore: store)
            .workspacePage(background: Design.Colors.Workspace.surface)
            .dynamicTypeSize(.accessibility3)
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.verticalSizeClass, .compact))
        let ready = try await ui.waitFor { !store.isLoading && store.scanFiles == [damaged] }
        XCTAssertTrue(ready)
        try await ui.attach(to: self, phase: "History-record-viewport-landscape-accessibility-synthetic")
        let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.refreshControl != nil })
        XCTAssertGreaterThanOrEqual(scroll.bounds.inset(by: scroll.adjustedContentInset).height, 100,
                                    "Damage feedback and filters must not collapse the record reading area")
        let more = try await ui.reveal(L10n.History.moreActions, in: scroll)
        XCTAssertGreaterThanOrEqual(more.accessibilityFrame.height, 43.5)
        try await ui.selectMenu(label: L10n.History.moreActions, title: L10n.History.rescanTree)
        XCTAssertEqual(rescans, [damaged.treeID])
        XCTAssertEqual(store.scanFiles, [damaged])
        try await ui.attach(to: self, phase: "History-record-revealed-landscape-accessibility-synthetic")
    }

    /// 证据（真实原生视图）：横屏 + 辅助字号下，**记录本身**与它的操作入口要真的在可视矩形里，
    /// 而且那个入口点得动。
    ///
    /// 既有那条断言量的是 ScrollView 的可视高度（402pt），不是留给记录行的高度 ——
    /// 这里量的是「像素在不在屏上」：
    /// 1) 真实滚动视口 = 滚动容器扣除 inset 后的可见矩形，再与窗口求交
    ///    （本窗口实测：874×402、上下 inset 116/34 → 有效内容视口 252pt）；
    /// 2) 辅助字号下记录行实测高约 300pt —— **比视口还高**，整行不可能同时露出来，
    ///    所以量的是「操作入口整块落在视口内」+「那一行在视口里还剩多少」；
    /// 3) 入口激活后菜单真的能派发动作，且派发的是**这一行**的动作。
    ///
    /// AX 节点「在树里」不等于「在屏上」：这里量的是矩形。
    @MainActor
    func testArchiveRecordStaysVisibleAndOperableInLandscapeAtAccessibilityTextSize() async throws {
        let suite = "ArchiveReachability-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tags = TagStore(defaults: defaults)
        let now = Date()
        let records = (1...3).map { index in
            archiveRecord("T-0\(index)_2026102\(index)_090000_lat31_lon121",
                          treeID: "T-0\(index)", scanDate: now)
        }
        let store = ScanHistoryStore(recordsLoader: { .success(records) })
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
        var rescans: [String] = []
        ui.mount(HistorySheetView(onRescanTree: { rescans.append($0) }, historyStore: store, tagStore: tags)
            .workspacePage(background: Design.Colors.Workspace.surface)
            .dynamicTypeSize(.accessibility3)
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.verticalSizeClass, .compact))
        let ready = try await ui.waitFor { !store.isLoading && store.scanFiles.count == records.count }
        XCTAssertTrue(ready)
        let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first { $0.refreshControl != nil })

        // 真实可视矩形：滚动容器扣除 inset 后的可见区域，再与窗口求交（屏幕坐标）。
        func viewport() -> CGRect {
            let content = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: nil)
            let screen = ui.window.convert(ui.window.bounds, to: nil)
            return content.intersection(screen)
        }
        XCTAssertGreaterThanOrEqual(viewport().height, 100,
                                    "横屏 + 辅助字号下，内容可视区不能被控件挤没")

        // 记录的操作入口：滚到它**整块**落在可视矩形里（不是「AX 树里有」）。
        let more = try await ui.reveal(L10n.History.moreActions, in: scroll)
        let moreFrame = more.accessibilityFrame
        XCTAssertTrue(viewport().contains(moreFrame),
                      "记录的操作入口必须整块落在真实可视矩形里，而不是只存在于无障碍树里")
        try await ui.attach(to: self, phase: "Archive-record-action-visible-landscape-accessibility")

        // 入口属于哪一行：按**纵向**归属（行的 AX 矩形不含尾部操作列，横向包含不成立）。
        let ownerCandidate = records.first { record in
            guard let frame = ui.element(label: record.id)?.accessibilityFrame, frame != .zero else { return false }
            return frame.minY <= moreFrame.midY && moreFrame.midY <= frame.maxY
        }
        let owner = try XCTUnwrap(ownerCandidate, "操作入口必须属于屏幕上的一条记录")
        let ownerFrame = try XCTUnwrap(ui.element(label: owner.id)?.accessibilityFrame)
        let visible = viewport().intersection(ownerFrame)
        XCTAssertGreaterThanOrEqual(visible.height, 44,
                                    "记录行必须真的露出可读可点的一块，不能只靠 AX 节点存在")
        XCTAssertGreaterThanOrEqual(visible.width, 44)

        // 点得动：激活后菜单真的出现，派发的动作属于这一行。
        XCTAssertTrue(more.accessibilityActivate())
        let (_, actions) = try await ui.visibleMenuActions()
        let rescan = try XCTUnwrap(actions.first { $0.title == L10n.History.rescanTree })
        UIButton(type: .system).sendAction(rescan)
        let fired = try await ui.waitFor { !rescans.isEmpty }
        XCTAssertTrue(fired, "点得动的入口必须真的派发动作")
        XCTAssertEqual(rescans, [owner.treeID])
        try await ui.attach(to: self, phase: "Archive-record-operable-landscape-accessibility")
    }

    @MainActor
    func testStartChromeKeepsActionsAndReadingAreaInCompactLargeText() async throws {
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.window.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
        var cancelled = 0
        var backed = 0
        var launched = 0
        ui.mount(StartViewLayout(currentStep: 5, totalSteps: 5, canGoBack: true, canGoNext: true,
                                 isLaunchingScan: false,
                                 header: StartFlowToolHeaderContent(imageName: "FeatureQuickScan", title: "启动扫描",
                                                                    subtitle: "确认信息后进入 LiDAR 采集", icon: "viewfinder",
                                                                    accent: Design.Colors.Workspace.accent),
                                 onCancel: { cancelled += 1 }, onBack: { backed += 1 }, onNext: { launched += 1 }) {
            VStack(alignment: .leading, spacing: 24) {
                StartStepHeader(step: 5, totalSteps: 5, title: L10n.StartSetup.text(.confirmationTitle),
                                subtitle: L10n.StartSetup.text(.confirmationSubtitle))
                ForEach(0..<5) { index in Text("T013 · \(index)").font(.body) }
            }
        }
            .dynamicTypeSize(.accessibility3)
            .environment(\.horizontalSizeClass, .compact)
            .environment(\.verticalSizeClass, .compact))
        try await ui.attach(to: self, phase: "Start-actions-landscape-accessibility-synthetic")
        for label in [L10n.StartFlow.cancel, L10n.StartFlow.previous, L10n.StartFlow.launch] {
            let action = try XCTUnwrap(ui.element(label: label))
            XCTAssertGreaterThanOrEqual(action.accessibilityFrame.width, 43.5, label)
            XCTAssertGreaterThanOrEqual(action.accessibilityFrame.height, 43.5, label)
            XCTAssertTrue(ui.window.bounds.insetBy(dx: -0.5, dy: -0.5).contains(action.accessibilityFrame),
                          "\(label) must remain inside window: \(action.accessibilityFrame)")
            XCTAssertTrue(action.accessibilityActivate())
        }
        let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first)
        XCTAssertGreaterThanOrEqual(scroll.bounds.inset(by: scroll.adjustedContentInset).height, 100,
                                    "Large-text controls must leave a usable reading area")
        XCTAssertEqual(cancelled, 1)
        XCTAssertEqual(backed, 1)
        XCTAssertEqual(launched, 1)
    }

    @MainActor
    func testStartAndQuickScanRenderNativeStepsAtSupportedConstraints() async throws {
        let suite = "StartVisual-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults)
        let tags = TagStore(defaults: defaults)
        tags.addPlot(name: "东坡 · 试验地块 A", colorHex: "285E49")
        tags.addTag(name: "试验组", colorHex: "94621C")
        tags.addTag(name: "待复核", colorHex: "3A677A")
        await tags.waitForPendingSave()
        let emptySuite = "StartEmptyVisual-\(UUID())"
        let emptyDefaults = try XCTUnwrap(UserDefaults(suiteName: emptySuite))
        defer { emptyDefaults.removePersistentDomain(forName: emptySuite) }
        let emptyTags = TagStore(defaults: emptyDefaults)
        let layouts: [(String, CGSize, DynamicTypeSize)] = [
            ("phone", CGSize(width: 402, height: 874), .large),
            ("landscape", CGSize(width: 874, height: 402), .large),
            ("tablet", CGSize(width: 1024, height: 1366), .large),
            ("accessibility", CGSize(width: 402, height: 874), .accessibility3),
            ("landscape-accessibility", CGSize(width: 874, height: 402), .accessibility3)
        ]
        for (layout, size, textSize) in layouts {
            for name in ["id", "plots", "season", "tags", "confirm", "empty-plots", "empty-tags", "quick", "quick-invalid"] {
                let ui = try RootLaunchUIHarness()
                ui.window.frame = CGRect(origin: .zero, size: size)
                let content: AnyView
                if name.hasPrefix("quick") {
                    content = AnyView(QuickScanView(settings: settings, onLaunchScan: { _ in XCTFail("Rendering must not launch") }))
                } else {
                    content = AnyView(StartView(settings: settings,
                                                tagStore: name.hasPrefix("empty") ? emptyTags : tags,
                                                onLaunchScan: { _ in XCTFail("Rendering must not launch") }))
                }
                ui.mount(content.dynamicTypeSize(textSize)
                    .environment(\.horizontalSizeClass, layout == "tablet" ? .regular : .compact)
                    .environment(\.verticalSizeClass, layout.hasPrefix("landscape") ? .compact : .regular))
                let step = ["id": 1, "plots": 2, "season": 3, "tags": 4, "confirm": 5,
                            "empty-plots": 2, "empty-tags": 4][name] ?? 1
                if name.hasPrefix("quick") {
                    let ready = try await ui.waitFor { ui.elements.contains { $0 is UITextField } }
                    XCTAssertTrue(ready)
                    let field = try XCTUnwrap(ui.elements.compactMap { $0 as? UITextField }.first)
                    field.selectedTextRange = field.textRange(from: field.beginningOfDocument, to: field.endOfDocument)
                    field.insertText(name == "quick-invalid" ? "../bad" : "T013")
                    let updated = try await ui.waitFor { field.text == (name == "quick-invalid" ? "../bad" : "T013") }
                    XCTAssertTrue(updated)
                    XCTAssertEqual(ui.element(label: L10n.QuickScan.launch)?.accessibilityTraits.contains(.notEnabled),
                                   name == "quick-invalid")
                } else if step > 1 {
                    try await ui.advanceStart(to: step, treeID: "T013")
                }
                try await ui.attach(to: self, phase: "Start-\(name)-\(layout)-synthetic")
                var actionLabels = name.hasPrefix("quick") ? [L10n.QuickScan.close, L10n.QuickScan.launch] :
                    [L10n.StartFlow.cancel, step == 5 ? L10n.StartFlow.launch : L10n.StartFlow.next]
                if !name.hasPrefix("quick"), step > 1 { actionLabels.append(L10n.StartFlow.previous) }
                for label in actionLabels {
                    let action = try XCTUnwrap(ui.element(label: label), "\(name) \(layout): \(label)")
                    XCTAssertGreaterThanOrEqual(action.accessibilityFrame.width, 43.5, label)
                    XCTAssertGreaterThanOrEqual(action.accessibilityFrame.height, 43.5, label)
                    XCTAssertTrue(ui.window.bounds.insetBy(dx: -0.5, dy: -0.5).contains(action.accessibilityFrame),
                                  "\(name) \(layout): fixed action must stay inside window: \(action.accessibilityFrame)")
                }
                if textSize.isAccessibilitySize,
                   let scroll = ui.elements.compactMap({ $0 as? UIScrollView }).first {
                    let bottom = max(-scroll.adjustedContentInset.top,
                                     scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                    let finalLabel: String
                    switch name {
                    case "id": finalLabel = L10n.StartSetup.text(.identifierNote)
                    case "plots": finalLabel = L10n.StartSetup.text(.plotAdd)
                    case "season": finalLabel = L10n.StartSetup.text(.seasonNote)
                    case "tags": finalLabel = L10n.StartSetup.text(.tagsAdd)
                    case "confirm": finalLabel = L10n.StartSetup.text(.confirmationNote)
                    case "empty-plots": finalLabel = L10n.StartSetup.text(.plotCreate)
                    case "empty-tags": finalLabel = L10n.StartSetup.text(.tagsCreate)
                    default: finalLabel = L10n.QuickScan.gpsUnavailable
                    }
                    let visible = try await ui.waitFor {
                        guard let frame = ui.element(label: finalLabel)?.accessibilityFrame else { return false }
                        let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: nil)
                        return viewport.insetBy(dx: -0.5, dy: -0.5).contains(frame)
                    }
                    XCTAssertTrue(visible, "\(name) \(layout): last content must be readable above fixed actions")
                    try await ui.attach(to: self, phase: "Start-\(name)-\(layout)-bottom-synthetic")
                }
                ui.close()
            }
        }
        await tags.waitForPendingSave()
        await emptyTags.waitForPendingSave()
        XCTAssertEqual(tags.plots.count, 1)
        XCTAssertEqual(tags.tags.count, 2)
        XCTAssertTrue(tags.assignments.isEmpty)
    }

    /// 回归：主页的产量读数必须跟系统语言和辅助字号走。
    /// 之前它用 `String(format:)` 固定小数点（de-DE 上与分析页显示成两个样），
    /// 并且锁死 38pt，用户把字号放大时这个数也不长。
    @MainActor
    func testHomeYieldDatumFollowsLocaleAndDynamicType() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("synthetic-locale.ply")
        try PLYPointCloudWriter.write(points: [ColoredPoint(pos: SIMD3<Float>(0, 1, 0), r: 0.4, g: 0.6, b: 0.3)],
                                      treeID: "SYNTHETIC-LOCALE", scanDate: "2026-10-19 00:00:00",
                                      gpsLat: 31.23, gpsLon: 121.47, to: source)
        let now = Date()
        let record = ScanFileRecord(id: "LOCALE1", treeID: "界面样例LOCALE1", fileURL: source, scanDate: now,
                                    fruitCount: 18, yieldKg: 4.2, gpsLat: 31.23, gpsLon: 121.47,
                                    confidence: "high", persistenceState: .complete)
        let aggregation = DashboardAggregationStore(now: { now }, notificationCenter: NotificationCenter())
        await aggregation.updateRecords([record])?.value

        func mount(locale: String, size: DynamicTypeSize) throws -> RootLaunchUIHarness {
            let ui = try RootLaunchUIHarness()
            ui.mount(DashboardHomeLayoutView(aggregation: aggregation, onSettingsTap: {}, onHistoryTap: {},
                                              onStartScan: {}, onQuickScan: {}, onQuickAction: { _ in }, onScanTap: { _ in })
                .dynamicTypeSize(size)
                .environment(\.locale, Locale(identifier: locale)))
            return ui
        }

        for (locale, expected) in [("en_US", "4.2"), ("de_DE", "4,2")] {
            let ui = try mount(locale: locale, size: .large)
            let ready = try await ui.waitFor {
                ui.elements.contains { ($0.accessibilityLabel ?? "").contains(expected) }
            }
            XCTAssertTrue(ready, "产量读数应按 locale 显示：\(locale) → \(expected)")
            ui.close()
        }

        var heights: [CGFloat] = []
        for size in [DynamicTypeSize.large, .accessibility3] {
            let ui = try mount(locale: "en_US", size: size)
            _ = try await ui.waitFor { ui.elements.contains { ($0.accessibilityLabel ?? "").contains("4.2") } }
            let element = ui.elements.first { ($0.accessibilityLabel ?? "").contains("4.2") }
            heights.append(element?.accessibilityFrame.height ?? 0)
            ui.close()
        }
        XCTAssertGreaterThan(heights[1], heights[0] * 1.2,
                             "辅助字号下产量读数的高度应明显增大：\(heights)")
    }

    @MainActor
    func testHomeWorkspaceRendersRecordStatesAndTabsAtSupportedConstraints() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("synthetic-layout.ply")
        var points: [ColoredPoint] = []
        for index in 0..<512 {
            points.append(ColoredPoint(pos: SIMD3<Float>(Float(index % 8) * 0.1,
                                                         Float(index / 64) * 0.1,
                                                         Float((index / 8) % 8) * 0.1),
                                       r: 0.4, g: 0.6, b: 0.3))
        }
        try PLYPointCloudWriter.write(points: points, treeID: "SYNTHETIC-HOME-LAYOUT",
                                      scanDate: "2026-10-19 00:00:00", gpsLat: 0, gpsLon: 0, to: source)
        let sourceBytes = try Data(contentsOf: source)
        let now = Date()
        func record(_ id: String, located: Bool, state: ScanPersistenceState = .complete) -> ScanFileRecord {
            ScanFileRecord(id: id, treeID: "界面样例\(id)", fileURL: source, scanDate: now,
                           fruitCount: 18, yieldKg: 4.2, gpsLat: located ? 31.23 : 0,
                           gpsLon: located ? 121.47 : 0, confidence: "high", persistenceState: state)
        }
        let complete = record("T012", located: true)
        let unlocated = record("T013", located: false)
        let incomplete = record("T014", located: false, state: .incomplete)
        let cases: [(String, AppMode, [ScanFileRecord])] = [
            ("empty-orchard", .scan, []), ("empty-archive", .history, []),
            ("empty-analysis", .analytics, []), ("located", .scan, [complete]),
            ("unlocated", .scan, [unlocated]), ("incomplete", .scan, [incomplete]),
            ("archive", .history, [complete, unlocated, incomplete]),
            ("analysis", .analytics, [complete, unlocated, incomplete])
        ]
        let layouts: [(String, CGSize, DynamicTypeSize)] = [
            ("phone", CGSize(width: 402, height: 874), .large),
            ("landscape", CGSize(width: 874, height: 402), .large),
            ("tablet", CGSize(width: 1024, height: 1366), .large),
            ("accessibility", CGSize(width: 402, height: 874), .accessibility3),
            ("landscape-accessibility", CGSize(width: 874, height: 402), .accessibility3)
        ]
        for (layout, size, textSize) in layouts {
            for (name, mode, records) in cases {
                let aggregation = DashboardAggregationStore(now: { now }, notificationCenter: NotificationCenter())
                await aggregation.updateRecords(records)?.value
                var starts = 0
                var quickStarts = 0
                let ui = try RootLaunchUIHarness()
                ui.window.frame = CGRect(origin: .zero, size: size)
                ui.mount(DashboardHomeLayoutView(aggregation: aggregation, onSettingsTap: {}, onHistoryTap: {},
                                                  onStartScan: { starts += 1 }, onQuickScan: { quickStarts += 1 },
                                                  onQuickAction: { _ in }, onScanTap: { _ in })
                    .dynamicTypeSize(textSize)
                    .environment(\.horizontalSizeClass, layout == "tablet" ? .regular : .compact)
                    .environment(\.verticalSizeClass, layout.hasPrefix("landscape") ? .compact : .regular))
                let label = mode == .scan ? L10n.Dashboard.scanMode : mode == .history ? WorkspaceText.archive : WorkspaceText.analysis
                let ready = try await ui.waitFor { ui.element(label: label) != nil }
                XCTAssertTrue(ready)
                if mode != .scan { XCTAssertTrue(try XCTUnwrap(ui.element(label: label)).accessibilityActivate()) }
                let selected = try await ui.waitFor { ui.element(label: label)?.accessibilityTraits.contains(.selected) == true }
                XCTAssertTrue(selected)
                try await ui.attach(to: self, phase: "Home-\(name)-\(layout)-synthetic")
                for title in [L10n.Dashboard.scanMode, WorkspaceText.archive, WorkspaceText.analysis] {
                    let tab = try XCTUnwrap(ui.element(label: title))
                    XCTAssertGreaterThanOrEqual(tab.accessibilityFrame.width, 43.5)
                    XCTAssertGreaterThanOrEqual(tab.accessibilityFrame.height, 43.5)
                    XCTAssertTrue(ui.window.bounds.contains(tab.accessibilityFrame), "\(layout): tab must stay reachable")
                }
                if textSize.isAccessibilitySize, mode != .scan || layout == "landscape-accessibility",
                   let scroll = ui.elements.compactMap({ $0 as? UIScrollView }).first {
                    let bottom = max(-scroll.adjustedContentInset.top,
                                     scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
                    ui.window.layoutIfNeeded()
                    if mode == .scan {
                        let viewport = scroll.convert(scroll.bounds.inset(by: scroll.adjustedContentInset), to: nil)
                            .insetBy(dx: -0.5, dy: -0.5)
                        for title in [L10n.Dashboard.startScan, L10n.Dashboard.quickCapture] {
                            let revealed = try await ui.waitFor {
                                guard let frame = ui.element(label: title)?.accessibilityFrame else { return false }
                                return viewport.contains(frame)
                            }
                            XCTAssertTrue(revealed)
                            let action = try XCTUnwrap(ui.element(label: title))
                            XCTAssertTrue(viewport.contains(action.accessibilityFrame), "Compact large-text scan action must be scrollable into view")
                            XCTAssertTrue(action.accessibilityActivate())
                        }
                        XCTAssertEqual(starts, 1)
                        XCTAssertEqual(quickStarts, 1)
                    }
                    try await ui.attach(to: self, phase: "Home-\(name)-\(layout)-bottom-synthetic")
                }
                ui.close()
                XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
                XCTAssertEqual(aggregation.snapshot.records, records)
            }
        }
    }

    @MainActor
    func testScanChromeRendersNativeStatesAndKeepsGuidanceBelowReadings() async throws {
        let layouts: [(String, CGSize, DynamicTypeSize)] = [
            ("phone", CGSize(width: 402, height: 874), .large),
            ("landscape", CGSize(width: 874, height: 402), .large),
            ("tablet", CGSize(width: 1024, height: 1366), .large),
            ("accessibility", CGSize(width: 402, height: 874), .accessibility3),
            ("landscape-accessibility", CGSize(width: 874, height: 402), .accessibility3)
        ]
        let states = ["ready", "recording", "tracking-lost", "sparse-depth", "paused",
                      "requirements", "guide", "measurement", "camera-denied", "lidar-unavailable",
                      "coverage-complete", "notice"]
        let actions = ScanScannerInterfaceActions(
            onCloseGuide: {}, onStartRecording: {}, onToggleGuide: {}, onToggleRecording: {},
            onToggleMeasurement: {}, onRequestCancelScan: {}, onResumeRecording: {}, onFinishScan: {},
            onClearMeasurement: {}, onRetryResultPersistence: {}, onDismissResult: {}, onDismissResultToHome: {}
        )
        for (layout, size, textSize) in layouts {
            for state in states {
                let hud = ScanHUDState()
                hud.update(pointCount: state == "ready" ? 0 : 12_345, coveragePercent: 68,
                           scanCompletion: ScanCompletion(overall: 0.68, voxelCount: 420,
                                                          scanDuration: 45, discoveryTrend: .increasing),
                           visionModelStatus: "CoreML", visionModelDetail: "FruitDetector.mlmodelc",
                           depthRuntimeStatus: "LiDAR", exportablePointStatus: "Ready",
                           processedImageFrames: 24, detectedFruitCount: 18, fusionStatus: "扫描中",
                           guidanceHint: state == "tracking-lost" ? .trackingLost : state == "sparse-depth" ? .sparseDepth : .none)
                let measurement = MetalMeasurementController()
                if state == "measurement" { measurement.activate() }
                let ui = try RootLaunchUIHarness()
                ui.window.frame = CGRect(origin: .zero, size: size)
                ui.mount(ScanChromeFixture(state: state, hud: hud, quality: ScanQualityMonitor(),
                                          measurement: measurement, actions: actions)
                    .dynamicTypeSize(textSize)
                    .environment(\.horizontalSizeClass, layout == "tablet" ? .regular : .compact)
                    .environment(\.verticalSizeClass, layout.hasPrefix("landscape") ? .compact : .regular))
                try await ui.attach(to: self, phase: "Scan-\(state)-\(layout)-synthetic")
                if ["tracking-lost", "sparse-depth"].contains(state) {
                    let hint: ScanGuidanceHint = state == "tracking-lost" ? .trackingLost : .sparseDepth
                    let warning = try XCTUnwrap(ui.element(label: hint.title))
                    let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first)
                    let viewport = scroll.convert(scroll.bounds, to: nil)
                    XCTAssertTrue(warning.accessibilityFrame.intersects(viewport),
                                  "\(layout): critical guidance must be inside the actual information viewport")
                    if layout == "phone" {
                        let metric = try XCTUnwrap(ui.elements.filter {
                            $0.accessibilityLabel?.hasPrefix(L10n.ScanHUD.quality) == true
                        }.max { $0.accessibilityFrame.maxY < $1.accessibilityFrame.maxY })
                        XCTAssertGreaterThanOrEqual(warning.accessibilityFrame.minY, metric.accessibilityFrame.maxY,
                                                    "Guidance must flow below the actual status readings, not cover them")
                    }
                }
                let fixedActions: [String]
                switch state {
                case "guide":
                    fixedActions = [L10n.ScanGuidance.text(.closeGuideAccessibility), L10n.ScanGuidance.text(.start)]
                case "measurement":
                    fixedActions = [L10n.PointCloud.closeMeasurementAccessibility]
                    XCTAssertNil(ui.element(label: L10n.ScanControls.text(.cancel)), "Measurement owns the interaction surface")
                case "camera-denied":
                    fixedActions = [L10n.ScanReadiness.openSettings, L10n.ScanReadiness.back]
                case "lidar-unavailable":
                    fixedActions = [L10n.ScanReadiness.back]
                default: fixedActions = []
                }
                for label in fixedActions {
                    let action = try XCTUnwrap(ui.element(label: label))
                    XCTAssertGreaterThanOrEqual(action.accessibilityFrame.width, 43.5)
                    XCTAssertGreaterThanOrEqual(action.accessibilityFrame.height, 43.5)
                    XCTAssertTrue(ui.window.bounds.insetBy(dx: -0.5, dy: -0.5).contains(action.accessibilityFrame),
                                  "\(layout) \(state) \(label) must remain fully in the window: \(action.accessibilityFrame)")
                }
                if state == "notice" || state == "coverage-complete" {
                    let label = state == "notice" ? L10n.ScanExport.requirementsHint : L10n.Scan.coverageComplete
                    let message = try XCTUnwrap(ui.element(label: label))
                    let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first)
                    let viewport = scroll.convert(scroll.bounds, to: nil).insetBy(dx: -0.5, dy: -0.5)
                    XCTAssertTrue(viewport.contains(message.accessibilityFrame),
                                  "\(layout) \(state): complete transient message must be visible above controls: \(message.accessibilityFrame) in \(viewport)")
                }
                if layout == "landscape-accessibility", state == "recording" {
                    let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first)
                    scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
                    hud.update(guidanceHint: .trackingLost)
                    let revealed = try await ui.waitFor {
                        guard let warning = ui.element(label: ScanGuidanceHint.trackingLost.title) else { return false }
                        return warning.accessibilityFrame.intersects(scroll.convert(scroll.bounds, to: nil))
                    }
                    XCTAssertTrue(revealed, "A new critical hint must return from scrolled readings to the visible viewport")
                    try await ui.attach(to: self, phase: "Scan-guidance-arrival-\(layout)-synthetic")
                }
                ui.close()
            }
        }
    }

    @MainActor
    func testScanChromeControlsKeepCallbacksAndDiagnosticsReachable() async throws {
        for textSize: DynamicTypeSize in [.large, .accessibility3] {
            let hud = ScanHUDState()
            hud.update(pointCount: 12_345, coveragePercent: 68,
                       visionModelStatus: "CoreML", visionModelDetail: "FruitDetector.mlmodelc",
                       depthRuntimeStatus: "LiDAR", exportablePointStatus: "Ready",
                       processedImageFrames: 24, detectedFruitCount: 18, fusionStatus: "扫描中")
            let quality = ScanQualityMonitor()
            let measurement = MetalMeasurementController()
            var counts: [String: Int] = [:]
            func record(_ name: String) { counts[name, default: 0] += 1 }
            let actions = ScanScannerInterfaceActions(
                onCloseGuide: { record("close-guide") }, onStartRecording: { record("start-guide") },
                onToggleGuide: { record("guide") }, onToggleRecording: { record("record") },
                onToggleMeasurement: { record("measure"); measurement.activate() },
                onRequestCancelScan: { record("cancel") }, onResumeRecording: { record("resume") },
                onFinishScan: { record("finish") },
                onClearMeasurement: { record("stop-measure"); measurement.deactivate() },
                onRetryResultPersistence: {}, onDismissResult: {}, onDismissResultToHome: {}
            )
            for state in ["ready", "recording", "paused", "requirements", "guide", "camera-denied", "lidar-unavailable"] {
                hud.update(pointCount: state == "ready" ? 0 : 12_345)
                let ui = try RootLaunchUIHarness()
                ui.window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
                ui.mount(ScanChromeFixture(state: state, hud: hud, quality: quality,
                                          measurement: measurement, actions: actions,
                                          onOpenSettings: { record("settings") })
                    .dynamicTypeSize(textSize)
                    .environment(\.horizontalSizeClass, .compact)
                    .environment(\.verticalSizeClass, .regular))

                func activate(_ label: String) throws {
                    let button = try XCTUnwrap(ui.element(label: label), "\(state) must expose \(label)")
                    XCTAssertFalse(button.accessibilityTraits.contains(.notEnabled))
                    XCTAssertGreaterThanOrEqual(button.accessibilityFrame.width, 43.5)
                    XCTAssertGreaterThanOrEqual(button.accessibilityFrame.height, 43.5)
                    XCTAssertTrue(button.accessibilityFrame.intersects(ui.window.bounds),
                                  "\(state) \(textSize) \(label) frame \(button.accessibilityFrame) must be in \(ui.window.bounds)")
                    XCTAssertTrue(button.accessibilityActivate())
                }
                let expectedLabel = state == "guide" ? L10n.ScanGuidance.text(.closeGuideAccessibility)
                    : ["camera-denied", "lidar-unavailable"].contains(state) ? L10n.ScanReadiness.back
                    : L10n.ScanControls.text(.cancel)
                let mounted = try await ui.waitFor { ui.element(label: expectedLabel) != nil }
                XCTAssertTrue(mounted)

                switch state {
                case "ready":
                    try activate(L10n.ScanControls.text(.guide))
                    try activate(L10n.ScanControls.text(.startRecording))
                    try activate(L10n.ScanExport.requirementsAction)
                    try activate(L10n.ScanControls.text(.cancel))
                case "recording":
                    try activate(L10n.ScanControls.text(.stopRecording))
                    try activate(L10n.ScanControls.text(.finish))
                    try activate(L10n.ScanControls.text(.cancel))
                case "paused":
                    try activate(L10n.ScanPostCapture.resumeAction)
                    try activate(L10n.ScanControls.text(.rerecord))
                    try activate(L10n.ScanControls.text(.finish))
                    try activate(L10n.ScanControls.text(.cancel))
                    try activate(L10n.ScanControls.text(.measure))
                    let active = try await ui.waitFor {
                        measurement.isActive && ui.element(label: L10n.PointCloud.closeMeasurementAccessibility) != nil
                    }
                    XCTAssertTrue(active)
                    try activate(L10n.PointCloud.closeMeasurementAccessibility)
                    let stopped = try await ui.waitFor {
                        !measurement.isActive && ui.element(label: L10n.ScanPostCapture.resumeAction) != nil
                    }
                    XCTAssertTrue(stopped)

                    if ui.element(label: L10n.ScanHUD.diagnosticsTitle)?.accessibilityFrame.intersects(ui.window.bounds) != true {
                        _ = try await ui.scrollToControl(label: L10n.ScanHUD.diagnosticsTitle)
                    }
                    try activate(L10n.ScanHUD.diagnosticsTitle)
                    let presentation = ScanStatusBarPresentation(hudState: hud, qualityMonitor: quality)
                    let expected = [
                        L10n.ScanHUD.points: ScanHUDValueFormatter.pointCount(hud.pointCount),
                        L10n.ScanHUD.vision: presentation.visionStatusText,
                        L10n.ScanHUD.model: presentation.visionDetailText,
                        L10n.ScanHUD.depth: presentation.depthStatusText,
                        L10n.ScanHUD.pointCloud: presentation.pointCloudStatusText,
                        L10n.ScanHUD.frames: presentation.processedFrameText,
                        L10n.ScanHUD.fusion: presentation.fusionStatusText,
                        L10n.ScanHUD.density: ScanHUDValueFormatter.pointDensity(quality.pointDensity),
                        L10n.ScanHUD.lighting: quality.lightLevel.description
                    ]
                    let diagnosticsReady = try await ui.waitFor { ui.element(label: L10n.ScanHUD.model) != nil }
                    XCTAssertTrue(diagnosticsReady)
                    for (label, value) in expected {
                        XCTAssertTrue(ui.elements.contains { $0.accessibilityLabel == label && $0.accessibilityValue == value },
                                      "Expanded diagnostics must preserve \(label): \(value)")
                    }
                    try await ui.attach(to: self, phase: "Scan-diagnostics-\(textSize)-synthetic")
                case "requirements":
                    try activate(L10n.ScanExport.requirementsAction)
                case "guide":
                    try activate(L10n.ScanGuidance.text(.closeGuideAccessibility))
                    try activate(L10n.ScanGuidance.text(.start))
                case "camera-denied":
                    try activate(L10n.ScanReadiness.openSettings)
                    try activate(L10n.ScanReadiness.back)
                case "lidar-unavailable":
                    try activate(L10n.ScanReadiness.back)
                default: XCTFail("Unexpected fixture state")
                }
                ui.close()
            }
            XCTAssertEqual(counts, ["guide": 1, "record": 3, "finish": 4, "cancel": 5,
                                    "resume": 1, "measure": 1, "stop-measure": 1,
                                    "close-guide": 1, "start-guide": 1, "settings": 1])
        }
    }

    @MainActor
    func testPointCloudWorkspaceRendersNativePhoneLandscapeTabletAndAccessibility() async throws {
        let fixturePath = ProcessInfo.processInfo.environment["FRUIT_POINT_CLOUD_FIXTURE"]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source: URL
        let count: Int
        let origin: String
        if let fixturePath {
            source = URL(fileURLWithPath: fixturePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            count = 60_000
            origin = "public-uav"
        } else {
            source = directory.appendingPathComponent("synthetic-controls.ply")
            var points: [ColoredPoint] = []
            for index in 0..<512 {
                let x = Float(index % 8) * Float(0.1)
                let y = Float(index / 64) * Float(0.1)
                let z = Float((index / 8) % 8) * Float(0.1)
                points.append(ColoredPoint(pos: SIMD3<Float>(x, y, z), r: 0.4, g: 0.6, b: 0.3))
            }
            try PLYPointCloudWriter.write(points: points, treeID: "SYNTHETIC-CONTROLS",
                                          scanDate: "2026-10-18 00:00:00", gpsLat: 0, gpsLon: 0, to: source)
            count = points.count
            origin = "synthetic"
        }
        let sourceBytes = try Data(contentsOf: source)
        let configurations: [(String, CGSize, DynamicTypeSize)] = [
            ("phone", CGSize(width: 402, height: 874), .large),
            ("landscape", CGSize(width: 874, height: 402), .large),
            ("tablet", CGSize(width: 1024, height: 1366), .large),
            ("accessibility", CGSize(width: 402, height: 874), .accessibility3),
            ("landscape-accessibility", CGSize(width: 874, height: 402), .accessibility3)
        ]
        func scrollToolsToBottom(_ ui: RootLaunchUIHarness) async throws {
            let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first)
            let bottom = max(-scroll.adjustedContentInset.top,
                             scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            scroll.layoutIfNeeded()
            let controlsReady = try await ui.waitFor { ui.element(label: L10n.PointCloud.measure) != nil }
            XCTAssertTrue(controlsReady, "The actual tools scroller must expose measurement")
        }
        for (name, size, textSize) in configurations {
            let ui = try RootLaunchUIHarness()
            ui.window.frame = CGRect(origin: .zero, size: size)
            ui.mount(PointCloudView(plyFileURL: source, onClose: {},
                                    treeID: origin == "public-uav" ? "公开果园点云 · UAV 样本" : "合成控件样例")
                .dynamicTypeSize(textSize)
                .environment(\.horizontalSizeClass, name == "tablet" ? .regular : .compact)
                .environment(\.verticalSizeClass, name.hasPrefix("landscape") ? .compact : .regular))
            let loaded = try await ui.waitFor {
                ui.element(label: L10n.PointCloud.pointCountAccessibility(count.formatted())) != nil
            }
            XCTAssertTrue(loaded, "Production point-cloud view must load the fixture at \(name)")
            try await ui.attach(to: self, phase: "PointCloud-\(name)-\(origin)")
            let tools = try XCTUnwrap(ui.element(label: L10n.PointCloud.toolsTitle))
            XCTAssertTrue(tools.accessibilityActivate())
            let toolsPresented = try await ui.waitFor { ui.controller.presentedViewController != nil }
            XCTAssertTrue(toolsPresented)
            if textSize.isAccessibilitySize {
                let readingsVisible = try await ui.waitFor {
                    ui.elements.contains { $0.accessibilityLabel?.hasPrefix(L10n.PointCloud.footprintAccessibility("")) == true }
                }
                XCTAssertTrue(readingsVisible, "The tools sheet must inherit the actual accessibility text size and expose full bounds")
            }
            try await ui.attach(to: self, phase: "PointCloud-tools-\(name)-\(origin)")
            XCTAssertTrue(try XCTUnwrap(ui.element(label: PointCloudViewMode.top.displayName)).accessibilityActivate())
            XCTAssertTrue(try XCTUnwrap(ui.element(label: PointCloudColorMode.density.displayName)).accessibilityActivate())
            try await scrollToolsToBottom(ui)
            try await ui.attach(to: self, phase: "PointCloud-tools-bottom-\(name)-\(origin)")
            for label in [L10n.PointCloud.reset, L10n.PointCloud.zoomIn, L10n.PointCloud.zoomOut] {
                XCTAssertTrue(try XCTUnwrap(ui.element(label: label)).accessibilityActivate())
            }
            XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.Common.done)).accessibilityActivate())
            let toolsDismissed = try await ui.waitFor { ui.controller.presentedViewController == nil }
            XCTAssertTrue(toolsDismissed)
            let updated = try await ui.waitFor {
                ui.element(label: L10n.PointCloud.toolsTitle)?.accessibilityValue == "\(PointCloudViewMode.top.displayName)，\(PointCloudColorMode.density.displayName)"
            }
            XCTAssertTrue(updated, "The entry must reflect actual view and color selection")
            XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.PointCloud.toolsTitle)).accessibilityActivate())
            let reopened = try await ui.waitFor { ui.controller.presentedViewController != nil }
            XCTAssertTrue(reopened)
            try await scrollToolsToBottom(ui)
            XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.PointCloud.measure)).accessibilityActivate())
            let measurementStarted = try await ui.waitFor {
                ui.controller.presentedViewController == nil && ui.element(label: L10n.PointCloud.closeMeasurementAccessibility) != nil
            }
            XCTAssertTrue(measurementStarted, "Measuring must dismiss tools and expose the point cloud")
            XCTAssertNil(ui.element(label: L10n.PointCloud.toolsTitle), "Ordinary controls must not cover the measurement prompt")
            try await ui.attach(to: self, phase: "PointCloud-measuring-\(name)-\(origin)")
            XCTAssertTrue(try XCTUnwrap(ui.element(label: L10n.PointCloud.closeMeasurementAccessibility)).accessibilityActivate())
            let measurementStopped = try await ui.waitFor {
                ui.element(label: L10n.PointCloud.closeMeasurementAccessibility) == nil
            }
            XCTAssertTrue(measurementStopped)
            XCTAssertNotNil(ui.element(label: L10n.PointCloud.toolsTitle))
            XCTAssertNotNil(ui.element(label: L10n.PointCloud.closePreviewAccessibility))
            XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
            ui.close()
        }
    }

    @MainActor
    func testCalibrationFormUsesRootHistoryAndExcludesIncompleteScans() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let controller = UIHostingController(rootView: AnyView(EmptyView()))
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        for isComplete in [true, false] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let pointCloud = directory.appendingPathComponent("root-calibration-ui.ply")
            try PLYPointCloudWriter.write(
                points: [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)],
                treeID: "ROOT-CALIBRATION-UI", scanDate: "2026-10-02 00:00:00", gpsLat: 0, gpsLon: 0,
                to: pointCloud
            )
            if isComplete {
                try JSONSerialization.data(withJSONObject: [
                    "fruitCount": 2, "yieldKg": 0.4, "fruitType": "apple", "confidence": "medium"
                ]).write(to: directory.appendingPathComponent("root-calibration-ui_result.json"))
            }
            let pointCloudBytes = try Data(contentsOf: pointCloud)
            let dependencies = AppDependencies(scanRepository: ScanRepository(scansDirectory: directory))
            await dependencies.historyStore.reloadRecords()
            controller.rootView = AnyView(
                AddCalibrationRecordView(scanSource: dependencies.calibrationScanSource()) { _ in
                    XCTFail("Rendering must not save a calibration record")
                }
                .id(isComplete)
            )
            controller.view.setNeedsLayout()
            window.layoutIfNeeded()
            // Reuse one foreground window and let each root installation settle.
            try await Task.sleep(nanoseconds: 100_000_000)
            var text = ""
            let deadline = Date().addingTimeInterval(3)
            repeat {
                controller.view.layoutIfNeeded()
                text = renderedAccessibilityText(in: controller.view)
                if !dependencies.historyStore.isLoading,
                   text.contains(L10n.Calibration.addNavigationTitle) { break }
                try await Task.sleep(nanoseconds: 20_000_000)
            } while Date() < deadline
            XCTAssertTrue(text.contains(L10n.Calibration.addNavigationTitle))
            XCTAssertEqual(text.contains(L10n.Calibration.recentScanPicker), isComplete,
                           "Only complete records from the injected root should enable recent scan import: \(text)")
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            })
            attachment.name = isComplete ? "RootCalibration-Complete" : "RootCalibration-Incomplete"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(try Data(contentsOf: pointCloud), pointCloudBytes)
        }
    }

    @MainActor
    func testDashboardHistoryAndBatchRoutesUseRootRepositoryRecords() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixtureID = String(UUID().uuidString.prefix(8))
        let source = directory.appendingPathComponent("root-ui-\(fixtureID).ply")
        let treeID = "ROOT-UI-\(fixtureID)"
        try PLYPointCloudWriter.write(
            points: [ColoredPoint(pos: SIMD3<Float>(1, 2, 3), r: 1, g: 0, b: 0)],
            treeID: treeID, scanDate: "2026-10-01 00:00:00", gpsLat: 0, gpsLon: 0, to: source
        )
        // A synthetic legacy archive exercises the existing compatibility reader.
        let metadata = directory.appendingPathComponent("root-ui-\(fixtureID)_result.json")
        try JSONSerialization.data(withJSONObject: [
            "fruitCount": 2, "yieldKg": 0.4, "fruitType": "apple", "confidence": "medium"
        ]).write(to: metadata)
        let repository = ScanRepository(scansDirectory: directory)
        let dependencies = AppDependencies(scanRepository: repository)
        let record = try XCTUnwrap(repository.readVerifiedRecord(at: source))
        XCTAssertEqual(record.summary.treeID, treeID)
        await dependencies.historyStore.reloadRecords()
        let sourceBytes = try Data(contentsOf: source)
        let metadataBytes = try Data(contentsOf: metadata)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })

        for route in [AppNavigation.history, .batchExport] {
            let suiteName = "RootHistoryRoutingTests-\(UUID().uuidString)"
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let router = NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter())
            router.handle(route)
            let controller = UIHostingController(rootView:
                DashboardView(router: router, historyStore: dependencies.historyStore)
                    .environmentObject(dependencies)
            )
            let previousKeyWindow = scene.keyWindow
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            defer {
                controller.presentedViewController?.dismiss(animated: false)
                window.isHidden = true
                window.rootViewController = nil
                previousKeyWindow?.makeKey()
            }

            var sheetText = ""
            let expectedIdentity = route == .history ? source.lastPathComponent : treeID
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline {
                if let sheet = controller.presentedViewController {
                    sheet.view.layoutIfNeeded()
                    sheetText = renderedAccessibilityText(in: sheet.view)
                    if sheetText.contains(expectedIdentity), sheet.transitionCoordinator == nil,
                       !sheet.isBeingPresented { break }
                }
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertNotNil(controller.presentedViewController, "The actual dashboard route must present its sheet")
            XCTAssertTrue(sheetText.contains(expectedIdentity), "\(route) must use the injected archive, not the global history: \(sheetText)")
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                XCTAssertTrue(window.drawHierarchy(in: window.bounds, afterScreenUpdates: true))
            })
            attachment.name = "RootHistoryRoute-\(route.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            controller.presentedViewController?.dismiss(animated: false)
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes)
        XCTAssertEqual(try Data(contentsOf: metadata), metadataBytes)
    }

    @MainActor
    func testHistoryRefreshControlLoadsFailurePreservesRecordsAndRecovers() async throws {
        let original = makeRecord(id: "refresh-original", treeID: "REFRESH-ORIGINAL",
                                  scanDate: Date(), fruitCount: 7, yieldKg: 1.25)
        let updated = makeRecord(id: "refresh-updated", treeID: "REFRESH-UPDATED",
                                 scanDate: Date(), fruitCount: 9, yieldKg: 2.5)
        let probe = HistoryRefreshLoadProbe(initialRecord: original)
        addTeardownBlock { await probe.finishPending(with: .cancelled) }
        let store = ScanHistoryStore(recordsLoader: { await probe.load() })
        let suiteName = "HistoryRefreshControlTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tagStore = TagStore(defaults: defaults)
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        ui.mount(Color.clear.sheet(isPresented: .constant(true)) {
            NavigationStack {
                ScanHistoryView(historyStore: store, tagStore: tagStore)
            }
        })
        let loaded = try await ui.waitFor {
            !store.isLoading && store.scanFiles == [original]
                && ui.element(label: original.fileURL.lastPathComponent) != nil
        }
        XCTAssertTrue(loaded, "The production sheet must finish its initial history load")
        func historyScrollView() throws -> UIScrollView {
            let matches = ui.elements.compactMap { $0 as? UIScrollView }.filter { scroll in
                let text = renderedAccessibilityText(in: scroll)
                return text.contains(original.fileURL.lastPathComponent) || text.contains(updated.fileURL.lastPathComponent)
            }
            XCTAssertEqual(matches.count, 1, "Identify the scroll view by its actual history rows, not an unrelated navigation scroll")
            return try XCTUnwrap(matches.first)
        }
        let scrollMetadata: [[String: Any]] = ui.elements.compactMap { $0 as? UIScrollView }.map { scroll in
            ["class": NSStringFromClass(type(of: scroll)), "frame": String(describing: scroll.frame),
             "contentHeight": scroll.contentSize.height, "hasRefreshControl": scroll.refreshControl != nil,
             "containsHistoryRow": renderedAccessibilityText(in: scroll).contains(original.fileURL.lastPathComponent)]
        }
        let scrollAttachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: scrollMetadata, options: [.prettyPrinted, .sortedKeys]),
                                             uniformTypeIdentifier: "public.json")
        scrollAttachment.name = "HistoryRefresh-scroll-identification"
        scrollAttachment.lifetime = .keepAlways
        add(scrollAttachment)
        func installedRefreshControl() throws -> UIRefreshControl {
            XCTAssertEqual(ui.elements.compactMap { $0 as? UIScrollView }.filter { $0.refreshControl != nil }.count, 1,
                           "Only the history list may own refresh; the horizontal filters must not share its action")
            let scroll = try historyScrollView()
            XCTAssertTrue(scroll.isScrollEnabled)
            let control = try XCTUnwrap(scroll.refreshControl)
            XCTAssertTrue(control.window === ui.window, "The event must target the currently installed control")
            return control
        }
        func waitForSuspendedLoad(_ control: UIRefreshControl, requestCount: Int) async throws {
            let deadline = Date().addingTimeInterval(3)
            while await probe.pendingCount == 0, Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            let pending = await probe.pendingCount
            let requests = await probe.requestCount
            XCTAssertEqual(pending, 1, "One production refresh must await its loader")
            XCTAssertEqual(requests, requestCount)
            XCTAssertTrue(store.isLoading)
            XCTAssertTrue(control.isRefreshing, "The indicator must remain active while the loader is suspended")
        }
        func attachRefreshState(_ phase: String, control: UIRefreshControl) async throws {
            let current = try historyScrollView()
            let metadata: [String: Any] = [
                "phase": phase,
                "requests": await probe.requestCount,
                "pending": await probe.pendingCount,
                "completionWasCancelled": await probe.completionWasCancelled,
                "isLoading": store.isLoading,
                "hasLoadFailure": store.loadFailure != nil,
                "recordIDs": store.scanFiles.map(\.id),
                "controlRefreshing": control.isRefreshing,
                "controlInWindow": control.window === ui.window,
                "controlStillCurrent": current.refreshControl === control,
                "contentOffsetY": current.contentOffset.y,
                "contentInsetTop": current.adjustedContentInset.top,
                "alwaysBounceVertical": current.alwaysBounceVertical,
                "bounces": current.bounces,
                "contentHeight": current.contentSize.height,
                "scrollHeight": current.bounds.height,
                "refreshControlHeight": control.bounds.height
            ]
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]),
                                           uniformTypeIdentifier: "public.json")
            attachment.name = "HistoryRefresh-\(phase)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func beginRefresh(_ control: UIRefreshControl) throws {
            let scroll = try XCTUnwrap(ui.elements.compactMap { $0 as? UIScrollView }.first {
                $0.refreshControl === control
            })
            control.beginRefreshing()
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top), animated: false)
            scroll.layoutIfNeeded()
            control.sendActions(for: .valueChanged)
        }
        let control = try installedRefreshControl()
        let staleMessage = String(format: NSLocalizedString(
            "history.load.failure.stale_message_format",
            value: "The scans folder couldn’t be read. Showing %d records from the last successful load.",
            comment: ""
        ), 1)

        // Exercise the installed UIKit control's public event. This diagnoses
        // the production refresh binding; native touch acceptance is separate.
        try beginRefresh(control)
        try await waitForSuspendedLoad(control, requestCount: 2)
        try await attachRefreshState("failure-inflight", control: control)
        XCTAssertEqual(store.scanFiles, [original])
        await probe.finishPending(with: .failure(.directoryUnavailable))
        let failed = try await ui.waitFor {
            !store.isLoading && store.loadFailure == .directoryUnavailable
                && !control.isRefreshing
                && self.renderedAccessibilityText(in: ui.controller.presentedViewController?.view ?? ui.controller.view)
                    .contains(staleMessage)
        }
        try await attachRefreshState("failure-completed", control: control)
        XCTAssertTrue(failed, "Refresh must await the failed load, end its indicator, and explain the cached record")
        XCTAssertEqual(store.scanFiles, [original])

        let retryControl = try installedRefreshControl()
        try beginRefresh(retryControl)
        try await waitForSuspendedLoad(retryControl, requestCount: 3)
        try await attachRefreshState("recovery-inflight", control: retryControl)
        XCTAssertEqual(store.scanFiles, [original])
        XCTAssertEqual(store.loadFailure, .directoryUnavailable)
        await probe.finishPending(with: .success([updated]))
        let recovered = try await ui.waitFor {
            !store.isLoading && store.loadFailure == nil && store.scanFiles == [updated]
                && !retryControl.isRefreshing
                && ui.element(label: updated.fileURL.lastPathComponent) != nil
                && ui.element(label: original.fileURL.lastPathComponent) == nil
        }
        try await attachRefreshState("recovery-completed", control: retryControl)
        XCTAssertTrue(recovered, "A second refresh must publish the new snapshot and clear the failure")
        let cancelledCompletions = await probe.completionWasCancelled
        XCTAssertEqual(cancelledCompletions, [false, false])
        try await ui.attach(to: self, phase: "history-refresh-control-recovered")
    }

    @MainActor
    private func renderedAccessibilityText(in root: NSObject) -> String {
        var visited = Set<ObjectIdentifier>()
        func text(in object: NSObject, depth: Int = 0) -> [String] {
            guard depth < 32, visited.insert(ObjectIdentifier(object)).inserted else { return [] }
            var values = [object.accessibilityLabel, object.accessibilityValue].compactMap { $0 }
            let count = object.accessibilityElementCount()
            if count > 0 && count < 100 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject {
                        values += text(in: child, depth: depth + 1)
                    }
                }
            }
            if let view = object as? UIView {
                values += view.subviews.flatMap { text(in: $0, depth: depth + 1) }
            }
            return values
        }
        return text(in: root).joined(separator: " | ")
    }

    @MainActor
    func testRecentScanCardDoesNotPresentMissingResultAsZeroYield() {
        let record = makeRecord(
            id: "missing-result",
            treeID: "UI-INCOMPLETE",
            scanDate: Date(),
            fruitCount: 0,
            yieldKg: 0,
            persistenceState: .incomplete
        )
        let text = recentScanCardAccessibilityText(record: record)

        XCTAssertTrue(
            text.contains(NSLocalizedString("history.integrity.incomplete.title", value: "Recovery Needed", comment: "")),
            "An incomplete archive must expose its recovery state: \(text)"
        )
        XCTAssertFalse(text.contains("0.0 kg"), "Missing results must not be shown as a measured zero")
    }

    @MainActor
    func testRecentScanCardHidesDamagedResultMetricsInCompactLayout() {
        let record = makeRecord(
            id: "damaged-result",
            treeID: "UI-INVALID",
            scanDate: Date(),
            fruitCount: 99,
            yieldKg: 42.5,
            persistenceState: .invalid
        )
        let text = accessibilityText(in: RecentScanCard(record: record, compactLandscape: true))

        XCTAssertTrue(text.contains(NSLocalizedString("history.integrity.invalid.title", value: "Result Damaged", comment: "")))
        XCTAssertFalse(text.contains("42.5 kg"), "Unverified stored values must remain unavailable")
        XCTAssertFalse(text.contains(L10n.Dashboard.fruitCountLabel(99)))
    }

    @MainActor
    func testRecentScanCardPreservesCompleteZeroYield() {
        let record = makeRecord(id: "complete-zero", treeID: "ZERO", scanDate: Date(), fruitCount: 0, yieldKg: 0)
        let text = recentScanCardAccessibilityText(record: record)

        XCTAssertTrue(text.contains("0.0 kg"), "A verified zero result must remain visible")
        XCTAssertTrue(text.contains(L10n.Dashboard.fruitCountLabel(0)))
        XCTAssertFalse(text.contains(NSLocalizedString("history.row.metrics_unavailable", value: "Metrics Unavailable", comment: "")))
    }

    @MainActor
    func testRecentScansButtonExposesIncompleteState() {
        let record = makeRecord(id: "missing-button", treeID: "MISSING", scanDate: Date(), yieldKg: 0, persistenceState: .incomplete)
        let text = accessibilityText(in: RecentScansSection(scans: [record]))

        XCTAssertTrue(
            text.contains(NSLocalizedString("history.integrity.incomplete.title", value: "Recovery Needed", comment: "")),
            "The actionable dashboard row must retain its integrity state: \(text)"
        )
        XCTAssertTrue(text.contains(NSLocalizedString("history.row.metrics_unavailable", value: "Metrics Unavailable", comment: "")))
        XCTAssertFalse(text.contains("0.0 kg"))
    }

    @MainActor
    private func recentScanCardAccessibilityText(record: ScanFileRecord) -> String {
        accessibilityText(in: RecentScanCard(record: record))
    }

    @MainActor
    private func accessibilityText<Content: View>(in content: Content) -> String {
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 220))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        let result = renderedAccessibilityText(in: window)
        window.resignKey()
        XCTAssertFalse(result.isEmpty, "The rendered card must expose accessible content")
        return result
    }

    @MainActor
    func testSharedDashboardToolPresentationRendersAtAccessibilityTextSize() {
        let rootView = ScrollView {
            VStack(spacing: 16) {
                DashboardToolHeader(
                    imageName: "FeatureImportFile",
                    title: "Import Point Cloud",
                    subtitle: "Choose an existing PLY scan for preview, comparison, and export.",
                    icon: "square.and.arrow.down",
                    accent: Design.Colors.harvest
                )

                DashboardSheetEmptyState(
                    icon: "clock.arrow.circlepath",
                    imageName: "FeatureScanHistory",
                    title: "No Scan Records",
                    message: "Complete a scan or import a PLY file, then review, share, or recover it here.",
                    primaryAction: DashboardSheetAction(
                        title: "Start Scanning",
                        icon: "viewfinder",
                        action: {}
                    ),
                    secondaryAction: DashboardSheetAction(
                        title: "Import PLY",
                        icon: "square.and.arrow.down",
                        action: {}
                    ),
                    outerPadding: false
                )
            }
            .padding(16)
        }
        .frame(width: 390, height: 844)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.colorScheme, .dark)

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.backgroundColor = .black
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        var didDraw = false
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
            .image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }

        XCTAssertTrue(didDraw)
        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "SharedDashboardToolPresentation-AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.resignKey()
    }

    func testNextTreeNavigationWaitsForActiveScanDismissal() {
        var state = PostScanNavigationState()

        XCTAssertNil(state.transition(for: .nextTreeRequested))
        XCTAssertEqual(state.transition(for: .activeScanDismissed), .startScan)
    }

    func testNormalScanDismissalDoesNotOpenNextTreeSetup() {
        var state = PostScanNavigationState()

        XCTAssertNil(state.transition(for: .activeScanDismissed))
    }

    func testNextTreeNavigationConsumesRepeatedRequestsOnce() {
        var state = PostScanNavigationState()

        XCTAssertNil(state.transition(for: .nextTreeRequested))
        XCTAssertNil(state.transition(for: .nextTreeRequested))
        XCTAssertEqual(state.transition(for: .activeScanDismissed), .startScan)
        XCTAssertNil(
            state.transition(for: .activeScanDismissed),
            "A late or repeated dismissal must not reopen the scan setup"
        )
    }

    func testScanLaunchPresentationWaitsForSourceDismissal() {
        var state = ScanLaunchPresentationState<String>()

        XCTAssertFalse(state.hasPendingRequest)
        XCTAssertNil(state.transition(for: .requestQueued("scan-a")))
        XCTAssertTrue(state.hasPendingRequest)
        XCTAssertEqual(state.transition(for: .sourceDismissed), "scan-a")
        XCTAssertFalse(state.hasPendingRequest)
    }

    func testScanLaunchPresentationIgnoresEmptyAndRepeatedDismissals() {
        var state = ScanLaunchPresentationState<String>()

        XCTAssertNil(state.transition(for: .sourceDismissed))
        XCTAssertNil(state.transition(for: .requestQueued("scan-a")))
        XCTAssertEqual(state.transition(for: .sourceDismissed), "scan-a")
        XCTAssertNil(
            state.transition(for: .sourceDismissed),
            "A repeated dismissal must not present the consumed scan request again"
        )
        XCTAssertFalse(state.hasPendingRequest)
    }

    func testScanLaunchPresentationUsesLatestRapidRequest() {
        var state = ScanLaunchPresentationState<String>()

        XCTAssertNil(state.transition(for: .requestQueued("scan-a")))
        XCTAssertNil(state.transition(for: .requestQueued("scan-b")))

        XCTAssertEqual(
            state.transition(for: .sourceDismissed),
            "scan-b",
            "The latest explicit launch request must replace an unpresented request"
        )
        XCTAssertNil(state.transition(for: .sourceDismissed))
        XCTAssertFalse(state.hasPendingRequest)
    }

    func testSheetStartScanHandoffWaitsForSheetDismissal() {
        var state = DashboardSheetScanHandoffState()

        XCTAssertNil(state.transition(for: .startScanRequested))
        XCTAssertEqual(state.transition(for: .sheetDismissed), .startScan)
    }

    func testSheetStartScanHandoffIgnoresDismissalWithoutRequest() {
        var state = DashboardSheetScanHandoffState()

        XCTAssertNil(state.transition(for: .sheetDismissed))
    }

    func testSheetStartScanHandoffConsumesRapidRequestsOnce() {
        var state = DashboardSheetScanHandoffState()

        XCTAssertNil(state.transition(for: .startScanRequested))
        XCTAssertNil(state.transition(for: .startScanRequested))
        XCTAssertEqual(state.transition(for: .sheetDismissed), .startScan)
        XCTAssertNil(
            state.transition(for: .sheetDismissed),
            "A repeated or late dismissal must not reopen the scan setup"
        )
    }

    func testImportFileHandoffUsesDistinctDestinationsWithinTheSheetLane() {
        let sourceDestinations: [DashboardDestination] = [
            .scanHistory,
            .pointCloud(nil),
            .batchExport
        ]
        let importDestination = DashboardDestination.importFile

        XCTAssertFalse(importDestination.isFullScreen)
        for sourceDestination in sourceDestinations {
            XCTAssertFalse(sourceDestination.isFullScreen)
            XCTAssertNotEqual(sourceDestination.id, importDestination.id)
        }
    }

    func testExternalNavigationPresentsOnlyWhenDashboardIsIdle() {
        XCTAssertEqual(
            DashboardExternalNavigationPolicy.disposition(
                for: .history,
                destination: nil,
                hasPendingScanRequest: false,
                hasActiveScanRequest: false
            ),
            .present
        )

        let blockedStates: [(DashboardDestination?, Bool, Bool)] = [
            (.settings, false, false),
            (nil, true, false),
            (nil, false, true)
        ]
        for state in blockedStates {
            XCTAssertEqual(
                DashboardExternalNavigationPolicy.disposition(
                    for: .history,
                    destination: state.0,
                    hasPendingScanRequest: state.1,
                    hasActiveScanRequest: state.2
                ),
                .deferUntilIdle
            )
        }
    }

    func testExternalNavigationRecognizesAlreadySatisfiedFlows() {
        XCTAssertEqual(
            DashboardExternalNavigationPolicy.disposition(
                for: .history,
                destination: .scanHistory,
                hasPendingScanRequest: false,
                hasActiveScanRequest: false
            ),
            .alreadySatisfied
        )
        XCTAssertEqual(
            DashboardExternalNavigationPolicy.disposition(
                for: .scanner,
                destination: .startScan,
                hasPendingScanRequest: false,
                hasActiveScanRequest: false
            ),
            .alreadySatisfied
        )

        let scannerPhases: [(Bool, Bool)] = [
            (true, false),
            (false, true)
        ]
        for phase in scannerPhases {
            XCTAssertEqual(
                DashboardExternalNavigationPolicy.disposition(
                    for: .scanner,
                    destination: nil,
                    hasPendingScanRequest: phase.0,
                    hasActiveScanRequest: phase.1
                ),
                .alreadySatisfied
            )
        }
    }

    @MainActor
    func testNavigationRouterKeepsLatestRequestUntilConsumptionIsAllowed() {
        let suiteName = "NavigationRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let router = NavigationRouter(
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        router.handle(.history)
        XCTAssertNil(router.takePendingDestination(if: false))
        XCTAssertEqual(router.pendingDestination?.rawValue, AppNavigation.history.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppNavigation.defaultsKey), AppNavigation.history.rawValue)

        router.handle(.map)
        XCTAssertEqual(defaults.string(forKey: AppNavigation.defaultsKey), AppNavigation.map.rawValue)
        XCTAssertEqual(
            router.takePendingDestination(if: true)?.rawValue,
            AppNavigation.map.rawValue
        )
        XCTAssertNil(router.pendingDestination)
        XCTAssertNil(defaults.string(forKey: AppNavigation.defaultsKey))
    }

    @MainActor
    func testNavigationRouterPreservesANewerPersistedRequestWhenConsumingOlderMemoryState() {
        let suiteName = "NavigationRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let router = NavigationRouter(
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        router.handle(.history)
        defaults.set(AppNavigation.map.rawValue, forKey: AppNavigation.defaultsKey)

        XCTAssertEqual(
            router.takePendingDestination(if: true)?.rawValue,
            AppNavigation.history.rawValue
        )
        XCTAssertEqual(defaults.string(forKey: AppNavigation.defaultsKey), AppNavigation.map.rawValue)

        router.consumePendingUserDefaults()
        XCTAssertEqual(router.pendingDestination?.rawValue, AppNavigation.map.rawValue)
        XCTAssertEqual(
            router.takePendingDestination(if: true)?.rawValue,
            AppNavigation.map.rawValue
        )
        XCTAssertNil(defaults.string(forKey: AppNavigation.defaultsKey))
    }

    @MainActor
    func testScanLaunchSubmissionGateDeliversSynchronously() {
        let gate = ScanLaunchSubmissionGate()
        var events: [String] = []

        let accepted = gate.submit(
            makeRequest: {
                events.append("build")
                return "request"
            },
            deliver: { request in
                events.append("deliver:\(request)")
            }
        )
        events.append("return")

        XCTAssertTrue(accepted)
        XCTAssertTrue(gate.isSubmitting)
        XCTAssertEqual(events, ["build", "deliver:request", "return"])
    }

    @MainActor
    func testScanLaunchSubmissionGateRejectsDuplicateSubmission() {
        let gate = ScanLaunchSubmissionGate()
        var delivered: [Int] = []

        XCTAssertTrue(gate.submit(makeRequest: { 1 }, deliver: { delivered.append($0) }))
        XCTAssertFalse(gate.submit(makeRequest: { 2 }, deliver: { delivered.append($0) }))

        XCTAssertEqual(delivered, [1])
    }

    @MainActor
    func testScanLaunchSubmissionGateDoesNotLockAfterInvalidRequest() {
        let gate = ScanLaunchSubmissionGate()

        let accepted = gate.submit(
            makeRequest: { nil as Int? },
            deliver: { _ in XCTFail("Invalid requests must not be delivered") }
        )

        XCTAssertFalse(accepted)
        XCTAssertFalse(gate.isSubmitting)
    }

    func testStartScanSelectionDropsUnavailablePlotAndTagIDs() {
        let availablePlot = Plot(name: "North Block")
        let availableTag = GroupTag(name: "Priority")
        let stalePlotID = UUID()
        let staleTagID = UUID()

        let snapshot = StartScanSelectionPolicy.snapshot(
            selectedPlotId: stalePlotID,
            selectedTagIds: [availableTag.id, staleTagID],
            availablePlots: [availablePlot],
            availableTags: [availableTag]
        )

        XCTAssertNil(snapshot.plotId)
        XCTAssertEqual(snapshot.tagIds, [availableTag.id])
    }

    func testStartScanSelectionKeepsAvailablePlotAndUsesTagCatalogOrder() {
        let plot = Plot(name: "South Block")
        let firstTag = GroupTag(name: "First")
        let secondTag = GroupTag(name: "Second")

        let snapshot = StartScanSelectionPolicy.snapshot(
            selectedPlotId: plot.id,
            selectedTagIds: [firstTag.id, secondTag.id],
            availablePlots: [plot],
            availableTags: [secondTag, firstTag]
        )

        XCTAssertEqual(snapshot.plotId, plot.id)
        XCTAssertEqual(snapshot.tagIds, [secondTag.id, firstTag.id])
    }

    func testGPSLocationPolicyRejectsStaleInaccurateAndInvalidFixes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let good = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            altitude: 0,
            horizontalAccuracy: GPSLocationPolicy.maximumHorizontalAccuracy,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(-GPSLocationPolicy.maximumLocationAge)
        )
        let stale = CLLocation(
            coordinate: good.coordinate,
            altitude: 0,
            horizontalAccuracy: 4,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(-GPSLocationPolicy.maximumLocationAge - 0.1)
        )
        let inaccurate = CLLocation(
            coordinate: good.coordinate,
            altitude: 0,
            horizontalAccuracy: GPSLocationPolicy.maximumHorizontalAccuracy + 0.1,
            verticalAccuracy: 5,
            timestamp: now
        )
        let invalidAccuracy = CLLocation(
            coordinate: good.coordinate,
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: 5,
            timestamp: now
        )
        let invalidCoordinate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 91, longitude: 181),
            altitude: 0,
            horizontalAccuracy: 1,
            verticalAccuracy: 5,
            timestamp: now
        )
        let future = CLLocation(
            coordinate: good.coordinate,
            altitude: 0,
            horizontalAccuracy: 1,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(
                GPSLocationPolicy.maximumFutureTimestampSkew + 0.1
            )
        )

        XCTAssertTrue(GPSLocationPolicy.isAcceptable(good, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(stale, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(inaccurate, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(invalidAccuracy, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(invalidCoordinate, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(future, at: now))
    }

    func testGPSLocationPolicyChoosesMostAccurateThenNewestFix() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lessAccurate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.1, longitude: 121.1),
            altitude: 0,
            horizontalAccuracy: 7,
            verticalAccuracy: 5,
            timestamp: now
        )
        let olderAccurate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.2, longitude: 121.2),
            altitude: 0,
            horizontalAccuracy: 3,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(-2)
        )
        let newerAccurate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.3, longitude: 121.3),
            altitude: 0,
            horizontalAccuracy: 3,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(-1)
        )

        let best = try XCTUnwrap(
            GPSLocationPolicy.bestLocation(
                from: [lessAccurate, olderAccurate, newerAccurate],
                at: now
            )
        )

        XCTAssertEqual(best.coordinate.latitude, newerAccurate.coordinate.latitude)
        XCTAssertEqual(best.coordinate.longitude, newerAccurate.coordinate.longitude)
    }

    func testGPSLocationPolicySnapshotDropsFixAfterItExpires() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),
            altitude: 0,
            horizontalAccuracy: 4,
            verticalAccuracy: 5,
            timestamp: timestamp
        )

        let freshSnapshot = try XCTUnwrap(
            GPSLocationPolicy.snapshot(
                from: location,
                at: timestamp.addingTimeInterval(5)
            )
        )
        let expiredSnapshot = GPSLocationPolicy.snapshot(
            from: location,
            at: timestamp.addingTimeInterval(GPSLocationPolicy.maximumLocationAge + 1)
        )

        XCTAssertEqual(freshSnapshot.latitude, -33.8688, accuracy: 0.000_001)
        XCTAssertEqual(freshSnapshot.longitude, 151.2093, accuracy: 0.000_001)
        XCTAssertEqual(freshSnapshot.horizontalAccuracy, 4)
        XCTAssertNil(expiredSnapshot)
    }

    @MainActor
    func testQuickScanTreeIdentifierDraftUsesLatestValidValueSynchronously() {
        let draft = QuickScanTreeIdentifierDraft(value: "Q1000")

        draft.value = "  TREE-NEW  "

        XCTAssertEqual(draft.normalizedValue, "TREE-NEW")
        XCTAssertEqual(draft.validatedValue, "TREE-NEW")
        XCTAssertTrue(draft.isValid)
    }

    @MainActor
    func testQuickScanTreeIdentifierDraftRejectsLatestInvalidValueSynchronously() {
        let draft = QuickScanTreeIdentifierDraft(value: "Q1000")

        draft.value = " .. "

        XCTAssertEqual(draft.normalizedValue, "..")
        XCTAssertEqual(draft.validationIssue, .pathMarker)
        XCTAssertNil(draft.validatedValue)
        XCTAssertFalse(draft.isValid)
    }

    @MainActor
    func testQuickScanTreeIdentifierDraftKeepsFinalRapidUpdate() {
        let draft = QuickScanTreeIdentifierDraft(value: "Q1000")

        draft.value = "TREE-A"
        draft.value = "TREE-B"
        draft.value = "TREE-C"

        XCTAssertEqual(draft.validatedValue, "TREE-C")
    }

    func testStartTreeIdentifierDraftUsesLatestValidValueSynchronously() {
        var draft = StartTreeIdentifierDraft(value: "TREE-OLD")

        draft.value = "  TREE-NEW  "

        XCTAssertEqual(draft.normalizedValue, "TREE-NEW")
        XCTAssertEqual(draft.validatedValue, "TREE-NEW")
        XCTAssertTrue(draft.isValid)
    }

    func testStartTreeIdentifierDraftRejectsLatestInvalidValueSynchronously() {
        var draft = StartTreeIdentifierDraft(value: "TREE-OLD")

        draft.value = " .. "

        XCTAssertEqual(draft.normalizedValue, "..")
        XCTAssertEqual(draft.validationIssue, .pathMarker)
        XCTAssertNil(draft.validatedValue)
        XCTAssertFalse(draft.isValid)
    }

    func testStartTreeIdentifierDraftRejectsEmptyValueSynchronously() {
        var draft = StartTreeIdentifierDraft(value: "TREE-OLD")

        draft.value = "   "

        XCTAssertEqual(draft.validationIssue, .empty)
        XCTAssertNil(draft.validatedValue)
        XCTAssertFalse(draft.isValid)
    }

    func testStartTreeIdentifierDraftKeepsFinalRapidUpdate() {
        var draft = StartTreeIdentifierDraft(value: "TREE-OLD")

        draft.value = "TREE-A"
        draft.value = "TREE-B"
        draft.value = "TREE-C"

        XCTAssertEqual(draft.validatedValue, "TREE-C")
    }

    @MainActor
    func testNavigationRouterReceivesRequestPostedAfterInitialization() {
        let suiteName = "NavigationRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let notificationCenter = NotificationCenter()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let router = NavigationRouter(
            defaults: defaults,
            notificationCenter: notificationCenter
        )

        defaults.set(AppNavigation.history.rawValue, forKey: AppNavigation.defaultsKey)
        notificationCenter.post(
            name: AppNavigation.notificationName,
            object: AppNavigation.history.rawValue
        )

        XCTAssertEqual(router.pendingDestination?.rawValue, AppNavigation.history.rawValue)
        XCTAssertEqual(
            defaults.string(forKey: AppNavigation.defaultsKey),
            AppNavigation.history.rawValue
        )
        XCTAssertEqual(
            router.takePendingDestination(if: true)?.rawValue,
            AppNavigation.history.rawValue
        )
        XCTAssertNil(defaults.string(forKey: AppNavigation.defaultsKey))
    }

    @MainActor
    func testNavigationRouterConsumesPersistedColdStartRequest() {
        let suiteName = "NavigationRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppNavigation.map.rawValue, forKey: AppNavigation.defaultsKey)

        let router = NavigationRouter(
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        XCTAssertEqual(router.pendingDestination?.rawValue, AppNavigation.map.rawValue)
        XCTAssertEqual(defaults.string(forKey: AppNavigation.defaultsKey), AppNavigation.map.rawValue)
        XCTAssertEqual(
            router.takePendingDestination(if: true)?.rawValue,
            AppNavigation.map.rawValue
        )
        XCTAssertNil(defaults.string(forKey: AppNavigation.defaultsKey))
    }

    @MainActor
    func testNavigationRouterDropsInvalidPersistedColdStartRequest() {
        let suiteName = "NavigationRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("not-a-navigation-target", forKey: AppNavigation.defaultsKey)

        let router = NavigationRouter(
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        XCTAssertNil(router.pendingDestination)
        XCTAssertNil(defaults.string(forKey: AppNavigation.defaultsKey))
    }

    @MainActor
    func testNavigationRouterIgnoresInvalidNotificationAndClearsMatchingPersistedRequest() {
        let suiteName = "NavigationRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let notificationCenter = NotificationCenter()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let router = NavigationRouter(
            defaults: defaults,
            notificationCenter: notificationCenter
        )

        defaults.set("not-a-navigation-target", forKey: AppNavigation.defaultsKey)
        notificationCenter.post(
            name: AppNavigation.notificationName,
            object: "not-a-navigation-target"
        )

        XCTAssertNil(router.pendingDestination)
        XCTAssertNil(defaults.string(forKey: AppNavigation.defaultsKey))
    }

    func testDashboardAggregationUsesExplicitDayAndCalendarWithoutChangingReportOrTrends() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 172_800 + 3_600)
        let records = [
            makeRecord(id: "today", treeID: "A", scanDate: now, yieldKg: 2),
            makeRecord(id: "zero", treeID: " A ", scanDate: now.addingTimeInterval(60), yieldKg: 0),
            makeRecord(id: "prior", treeID: "B", scanDate: now.addingTimeInterval(-7_200), yieldKg: 7),
            makeRecord(id: "raw", treeID: "C", scanDate: now, yieldKg: 99, persistenceState: .incomplete),
            makeRecord(id: "bad", treeID: "D", scanDate: now, yieldKg: 99, persistenceState: .invalid)
        ]
        let input = DashboardAggregationInput(records: records, context: .init(now: now, calendar: calendar))
        let today = DashboardAggregationSnapshot(input: input)
        XCTAssertEqual(today.daily.scanCount, 2)
        XCTAssertEqual(today.daily.treeCount, 2, "Daily counts preserve original, unnormalized tree names")
        XCTAssertEqual(today.daily.yieldKg, 2)
        XCTAssertEqual(today.report.totalTrees, 2)
        XCTAssertEqual(today.report.totalYield, 7, "Latest normalized A is a complete zero")
        XCTAssertEqual(today.report.latestRecordsByTree.map(\.id), ["zero", "prior"])
        XCTAssertEqual(today.trends.records.map(\.id), ["prior", "today", "zero"])
        XCTAssertEqual(today.records, records)
        XCTAssertEqual(today.recentRecords.map(\.id), ["today", "zero", "prior"])

        calendar.timeZone = TimeZone(secondsFromGMT: -8 * 3_600)!
        let shifted = DashboardAggregationSnapshot(input: .init(records: records, context: .init(now: now, calendar: calendar)))
        XCTAssertEqual(shifted.daily.scanCount, 3)
        XCTAssertEqual(shifted.daily.yieldKg, 9)
        XCTAssertEqual(shifted.report, today.report)
        XCTAssertEqual(shifted.trends, today.trends)
        let tomorrow = DashboardAggregationSnapshot(input: .init(records: records, context: .init(now: now.addingTimeInterval(86_400), calendar: calendar)))
        XCTAssertEqual(tomorrow.daily.scanCount, 0)
        XCTAssertEqual(tomorrow.report, today.report)
    }

    @MainActor
    func testDashboardAggregationRejectsCancelledLateResultsAndPublishesCoherentSnapshot() async throws {
        let now = Date()
        let probe = DashboardAggregationProbe()
        defer { Task { await probe.finishAll() } }
        let store = DashboardAggregationStore(now: { now }, notificationCenter: NotificationCenter(), builder: { await probe.build($0) })
        var publications: [DashboardAggregationSnapshot] = []
        let subscription = store.$snapshot.dropFirst().sink { publications.append($0) }
        defer { subscription.cancel() }
        let old = makeRecord(id: "old", treeID: "OLD", scanDate: now, fruitCount: 1, yieldKg: 1)
        let new = makeRecord(id: "new", treeID: "NEW", scanDate: now, fruitCount: 8, yieldKg: 4)
        let first = try XCTUnwrap(store.updateRecords([old]))
        try await waitForAggregation { await probe.count == 1 }
        let second = try XCTUnwrap(store.updateRecords([new]))
        try await waitForAggregation { await probe.count == 2 }
        XCTAssertTrue(store.snapshot.records.isEmpty, "Pending work cannot publish partial metrics")
        await probe.finish(1)
        await second.value
        XCTAssertEqual(store.snapshot.records, [new])
        XCTAssertEqual(store.snapshot.daily.yieldKg, 4)
        XCTAssertEqual(store.snapshot.report.totalFruit, 8)
        XCTAssertEqual(store.snapshot.trends.records, [new])
        await probe.finish(0)
        await first.value
        XCTAssertEqual(store.snapshot.records, [new])
        XCTAssertEqual(publications.count, 1)
        let cancelled = await probe.cancelledRequests
        XCTAssertTrue(cancelled.contains(0))
    }

    @MainActor
    func testDashboardAggregationReleasesOwnerAndCancelsSuspendedBuilder() async throws {
        let probe = DashboardAggregationProbe()
        defer { Task { await probe.finishAll() } }
        var owner: DashboardAggregationStore? = DashboardAggregationStore(notificationCenter: NotificationCenter(), builder: { await probe.build($0) })
        weak var weakOwner = owner
        let task = try XCTUnwrap(owner?.updateRecords([makeRecord(id: "pending", treeID: "P", scanDate: Date(), yieldKg: 1)]))
        try await waitForAggregation { await probe.count == 1 }
        owner = nil
        XCTAssertNil(weakOwner, "The suspended builder must not retain its owner")
        await probe.finishAll()
        await task.value
        let cancelled = await probe.cancelledRequests
        XCTAssertEqual(cancelled, [0])
    }

    @MainActor
    func testDashboardAggregationRefreshesDayAndTimeZoneNotificationsWithoutHistoryChanges() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var now = Date(timeIntervalSince1970: 172_800 + 3_600)
        let center = NotificationCenter()
        let store = DashboardAggregationStore(now: { now }, calendar: { calendar }, notificationCenter: center)
        let records = [makeRecord(id: "record", treeID: "A", scanDate: now, yieldKg: 2)]
        await store.updateRecords(records)?.value
        XCTAssertEqual(store.snapshot.daily.scanCount, 1)
        now = now.addingTimeInterval(86_400)
        center.post(name: .NSCalendarDayChanged, object: nil)
        try await waitForAggregation { store.snapshot.daily.scanCount == 0 }
        XCTAssertEqual(store.snapshot.records, records)
        XCTAssertEqual(store.snapshot.report.totalYield, 2)

        calendar.timeZone = TimeZone(secondsFromGMT: -8 * 3_600)!
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        try await waitForAggregation { store.snapshot.context.calendar.timeZone == calendar.timeZone }
        XCTAssertEqual(store.snapshot.daily.scanCount, 0)
        now = now.addingTimeInterval(-86_400)
        await store.refreshTimeContext()?.value
        XCTAssertEqual(store.snapshot.daily.scanCount, 1, "Foreground/clock rollback must use the new day context")
        XCTAssertNil(store.refreshTimeContext(), "Same context does not schedule duplicate work")
        XCTAssertNil(store.updateRecords(records))
    }

    @MainActor
    func testDashboardAggregationDayRefreshRejectsOldSameRecordsResult() async throws {
        var now = Date(timeIntervalSince1970: 172_800 + 3_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let probe = DashboardAggregationProbe()
        defer { Task { await probe.finishAll() } }
        let store = DashboardAggregationStore(now: { now }, calendar: { calendar }, notificationCenter: NotificationCenter(), builder: { await probe.build($0) })
        let records = [makeRecord(id: "same", treeID: "A", scanDate: now, yieldKg: 2)]
        let first = try XCTUnwrap(store.updateRecords(records))
        try await waitForAggregation { await probe.count == 1 }
        now = now.addingTimeInterval(86_400)
        let second = try XCTUnwrap(store.refreshTimeContext())
        try await waitForAggregation { await probe.count == 2 }
        await probe.finish(1)
        await second.value
        let accepted = store.snapshot
        XCTAssertEqual(accepted.daily.scanCount, 0)
        await probe.finish(0)
        await first.value
        XCTAssertEqual(store.snapshot, accepted)
    }

    @MainActor
    func testHistoryAggregationRetainsPublishedDataDuringRefreshFailureAndCancellation() async throws {
        let now = Date()
        let old = makeRecord(id: "accepted", treeID: "A", scanDate: now, yieldKg: 1)
        let new = makeRecord(id: "reloaded", treeID: "B", scanDate: now, yieldKg: 3)
        let sequence = DashboardHistorySequence([.success([old]), .failure(.directoryUnavailable), .cancelled, .success([new]), .success([])])
        let history = ScanHistoryStore(recordsLoader: { await sequence.load() })
        await history.reloadRecords()
        try await waitForAggregation { history.dashboardAggregation.snapshot.records == [old] }
        let accepted = history.dashboardAggregation.snapshot
        await history.reloadRecords()
        XCTAssertEqual(history.loadFailure, .directoryUnavailable)
        XCTAssertEqual(history.dashboardAggregation.snapshot, accepted)
        await history.reloadRecords()
        XCTAssertEqual(history.dashboardAggregation.snapshot, accepted)
        await history.reloadRecords()
        try await waitForAggregation { history.dashboardAggregation.snapshot.records == [new] }
        XCTAssertEqual(history.dashboardAggregation.snapshot.daily.yieldKg, 3)
        await history.reloadRecords()
        try await waitForAggregation { history.dashboardAggregation.snapshot.records.isEmpty }
        XCTAssertEqual(history.dashboardAggregation.snapshot.daily.scanCount, 0)
        XCTAssertTrue(history.dashboardAggregation.snapshot.report.isEmpty)
        XCTAssertTrue(history.dashboardAggregation.snapshot.trends.isEmpty)
    }

    @MainActor
    func testMountedDashboardReportAndTrendsConsumeTheirHistoryPublishedSnapshot() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        let now = Date()
        let old = makeRecord(id: "old-62", treeID: "AGG62-OLD", scanDate: now, fruitCount: 2, yieldKg: 1.2)
        let new = makeRecord(id: "new-62", treeID: "AGG62-NEW", scanDate: now, fruitCount: 7, yieldKg: 3.4)
        let sequence = DashboardHistorySequence([.success([old])])
        let probe = DashboardAggregationProbe()
        defer { Task { await probe.finishAll() } }
        let aggregation = DashboardAggregationStore(now: { now }, notificationCenter: NotificationCenter(), builder: { await probe.build($0) })
        let history = ScanHistoryStore(recordsLoader: { await sequence.load() }, dashboardAggregation: aggregation)
        let dashboard = DashboardView(router: NavigationRouter(defaults: fixture.defaults, notificationCenter: NotificationCenter()), historyStore: history)
        ui.mount(dashboard.environmentObject(fixture.root))
        try await waitForAggregation { await probe.count == 1 }
        await probe.finish(0)
        let initial = try await ui.waitFor { self.renderedAccessibilityText(in: ui.controller.view).contains(old.treeID) }
        XCTAssertTrue(initial)
        try await ui.attach(to: self, phase: "Aggregation62-home")
        ui.mount(dashboard.environmentObject(fixture.root))
        let rebuilt = try await ui.waitFor { self.renderedAccessibilityText(in: ui.controller.view).contains(old.treeID) }
        XCTAssertTrue(rebuilt)
        let countAfterRebuild = await probe.count
        XCTAssertEqual(countAfterRebuild, 1, "Same history and day do not rebuild on a View value replacement")

        await sequence.replace(with: .success([new]))
        await history.reloadRecords()
        try await waitForAggregation { await probe.count == 2 }
        XCTAssertEqual(history.scanFiles, [new])
        XCTAssertEqual(aggregation.snapshot.records, [old])
        ui.mount(dashboard.sheetView(for: .yieldReport).environment(\.locale, Locale(identifier: "en_US_POSIX")))
        let pending = try await ui.waitFor { self.renderedAccessibilityText(in: ui.controller.view).contains(old.treeID) }
        XCTAssertTrue(pending, "Report must use the published aggregate, even while history has newer records")
        XCTAssertFalse(renderedAccessibilityText(in: ui.controller.view).contains(new.treeID))
        await probe.finish(1)
        let reportUpdated = try await ui.waitFor { self.renderedAccessibilityText(in: ui.controller.view).contains(new.treeID) }
        XCTAssertTrue(reportUpdated)
        XCTAssertFalse(renderedAccessibilityText(in: ui.controller.view).contains(old.treeID))
        try await ui.attach(to: self, phase: "Aggregation62-report")

        ui.mount(dashboard.sheetView(for: .trends).environment(\.locale, Locale(identifier: "en_US_POSIX")))
        let trendsUpdated = try await ui.waitFor { self.renderedAccessibilityText(in: ui.controller.view).contains(new.treeID) }
        XCTAssertTrue(trendsUpdated)
        try await ui.attach(to: self, phase: "Aggregation62-trends")
        await sequence.replace(with: .success([]))
        await history.reloadRecords()
        try await waitForAggregation { await probe.count == 3 }
        XCTAssertTrue(renderedAccessibilityText(in: ui.controller.view).contains(new.treeID))
        await probe.finish(2)
        let emptyTitle = TrendsPresentation().emptyTitle
        let empty = try await ui.waitFor { self.renderedAccessibilityText(in: ui.controller.view).contains(emptyTitle) }
        XCTAssertTrue(empty)
        XCTAssertFalse(renderedAccessibilityText(in: ui.controller.view).contains(new.treeID))
        try await ui.attach(to: self, phase: "Aggregation62-empty")
        await fixture.verifyStandard()
    }

    @MainActor
    func testMountedDashboardForegroundRefreshUsesNewDayWithoutHistoryChange() async throws {
        let fixture = try await RootClassificationFixture()
        defer { fixture.cleanup() }
        let ui = try RootLaunchUIHarness()
        defer { ui.close() }
        var now = Date(timeIntervalSince1970: 172_800 + 3_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let record = makeRecord(id: "foreground", treeID: "AGG62-DAY", scanDate: now, yieldKg: 2)
        let aggregation = DashboardAggregationStore(now: { now }, calendar: { calendar }, notificationCenter: NotificationCenter())
        let history = ScanHistoryStore(recordsLoader: { .success([record]) }, dashboardAggregation: aggregation)
        let scene = DashboardSceneFixture()
        let dashboard = DashboardView(router: NavigationRouter(defaults: fixture.defaults, notificationCenter: NotificationCenter()), historyStore: history)
        ui.mount(DashboardSceneHarness(scene: scene, dashboard: dashboard, dependencies: fixture.root))
        let initial = try await ui.waitFor { aggregation.snapshot.daily.scanCount == 1 }
        XCTAssertTrue(initial)
        now = now.addingTimeInterval(86_400)
        scene.phase = .active
        let refreshed = try await ui.waitFor { aggregation.snapshot.daily.scanCount == 0 }
        XCTAssertTrue(refreshed, "Mounted production onChange must refresh the day after foreground entry")
        XCTAssertEqual(history.scanFiles, [record])
        XCTAssertEqual(aggregation.snapshot.report.totalYield, 2)
        XCTAssertTrue(renderedAccessibilityText(in: ui.controller.view).contains(record.treeID))
        await fixture.verifyStandard()
    }

    @MainActor
    private func waitForAggregation(_ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        } while Date() < deadline
        XCTFail("Aggregation did not reach its production publication boundary")
    }

    func testSummaryCountsOnlyTodaysRecordsAndUniqueTrees() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        let records = [
            makeRecord(id: "scan-1", treeID: "T-001", scanDate: now, yieldKg: 4.25),
            makeRecord(id: "scan-2", treeID: "T-001", scanDate: now, yieldKg: 2.75),
            makeRecord(id: "scan-3", treeID: "T-002", scanDate: now, yieldKg: 3.0),
            makeRecord(id: "scan-4", treeID: "T-999", scanDate: yesterday, yieldKg: 99.0)
        ]

        let summary = DashboardDailySummary(records: records, calendar: calendar)

        XCTAssertEqual(summary.scanCount, 3)
        XCTAssertEqual(summary.treeCount, 2)
        XCTAssertEqual(summary.yieldKg, 10.0, accuracy: 0.001)
    }

    func testSummaryIsZeroForEmptyRecords() {
        let summary = DashboardDailySummary(records: [])

        XCTAssertEqual(summary.scanCount, 0)
        XCTAssertEqual(summary.treeCount, 0)
        XCTAssertEqual(summary.yieldKg, 0, accuracy: 0.001)
    }

    func testYieldReportDataIncludesOnlyCompleteRecordsAndPreservesOrder() {
        let records = [
            makeRecord(
                id: "complete-a",
                treeID: "A",
                scanDate: Date(timeIntervalSince1970: 4),
                fruitCount: 12,
                yieldKg: 3.5
            ),
            makeRecord(
                id: "incomplete",
                treeID: "B",
                scanDate: Date(timeIntervalSince1970: 3),
                fruitCount: 99,
                yieldKg: 99,
                persistenceState: .incomplete
            ),
            makeRecord(
                id: "invalid",
                treeID: "C",
                scanDate: Date(timeIntervalSince1970: 2),
                fruitCount: 88,
                yieldKg: 88,
                persistenceState: .invalid
            ),
            makeRecord(
                id: "complete-b",
                treeID: "D",
                scanDate: Date(timeIntervalSince1970: 1),
                fruitCount: 8,
                yieldKg: 2
            )
        ]

        let report = YieldReportData(records: records)

        XCTAssertEqual(report.completeRecords.map(\.id), ["complete-a", "complete-b"])
        XCTAssertEqual(report.latestRecordsByTree.map(\.id), ["complete-a", "complete-b"])
        XCTAssertEqual(report.totalScans, 2)
        XCTAssertEqual(report.totalTrees, 2)
        XCTAssertEqual(report.totalYield ?? -1, 5.5, accuracy: 0.001)
        XCTAssertEqual(report.averageYield ?? -1, 2.75, accuracy: 0.001)
        XCTAssertEqual(report.totalFruit, 20)
        XCTAssertFalse(report.isEmpty)
    }

    func testYieldReportDataIsEmptyWhenOnlyIncompleteRecordsExist() {
        let records = [
            makeRecord(
                id: "incomplete",
                treeID: "A",
                scanDate: Date(),
                fruitCount: 99,
                yieldKg: 99,
                persistenceState: .incomplete
            ),
            makeRecord(
                id: "invalid",
                treeID: "B",
                scanDate: Date(),
                fruitCount: 88,
                yieldKg: 88,
                persistenceState: .invalid
            )
        ]

        let report = YieldReportData(records: records)

        XCTAssertTrue(report.isEmpty)
        XCTAssertTrue(report.completeRecords.isEmpty)
        XCTAssertTrue(report.latestRecordsByTree.isEmpty)
        XCTAssertTrue(report.visibleRecords.isEmpty)
        XCTAssertEqual(report.totalScans, 0)
        XCTAssertEqual(report.totalTrees, 0)
        XCTAssertEqual(report.totalYield ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(report.averageYield ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(report.totalFruit, 0)
    }

    func testYieldReportDataLimitsRowsAfterFilteringIncompleteRecords() {
        let completeRecords = (0..<22).map { index in
            makeRecord(
                id: "complete-\(index)",
                treeID: "T-\(index)",
                scanDate: Date(timeIntervalSince1970: TimeInterval(100 - index)),
                yieldKg: 1
            )
        }
        let incompleteRecords = (0..<8).map { index in
            makeRecord(
                id: "incomplete-\(index)",
                treeID: "I-\(index)",
                scanDate: Date(timeIntervalSince1970: TimeInterval(200 - index)),
                yieldKg: 99,
                persistenceState: .incomplete
            )
        }

        let report = YieldReportData(records: incompleteRecords + completeRecords)

        XCTAssertEqual(report.totalScans, 22)
        XCTAssertEqual(report.totalTrees, 22)
        XCTAssertEqual(report.visibleRecords.count, 20)
        XCTAssertEqual(report.visibleRecords.first?.id, "complete-0")
        XCTAssertEqual(report.visibleRecords.last?.id, "complete-19")
    }

    func testYieldReportDataUsesLatestCompleteRecordPerTreeForTotals() {
        let report = YieldReportData(records: [
            makeRecord(
                id: "tree-a-old",
                treeID: " A ",
                scanDate: Date(timeIntervalSince1970: 100),
                fruitCount: 10,
                yieldKg: 2
            ),
            makeRecord(
                id: "tree-b",
                treeID: "B",
                scanDate: Date(timeIntervalSince1970: 200),
                fruitCount: 20,
                yieldKg: 4
            ),
            makeRecord(
                id: "tree-a-new",
                treeID: "A",
                scanDate: Date(timeIntervalSince1970: 300),
                fruitCount: 15,
                yieldKg: 3
            ),
            makeRecord(
                id: "tree-a-incomplete-newest",
                treeID: "A",
                scanDate: Date(timeIntervalSince1970: 400),
                fruitCount: 999,
                yieldKg: 999,
                persistenceState: .incomplete
            )
        ])

        XCTAssertEqual(report.completeRecords.count, 3)
        XCTAssertEqual(report.totalScans, 3)
        XCTAssertEqual(report.totalTrees, 2)
        XCTAssertEqual(report.latestRecordsByTree.map(\.id), ["tree-a-new", "tree-b"])
        XCTAssertEqual(report.visibleRecords.map(\.id), ["tree-a-new", "tree-b"])
        XCTAssertEqual(report.totalYield ?? -1, 7, accuracy: 0.001)
        XCTAssertEqual(report.averageYield ?? -1, 3.5, accuracy: 0.001)
        XCTAssertEqual(report.totalFruit, 35)
    }

    func testYieldReportDataDoesNotOverflowLargeTotals() {
        let scanDate = Date(timeIntervalSince1970: 100)
        let countOverflow = YieldReportData(records: [
            makeRecord(id: "max-count", treeID: "A", scanDate: scanDate, fruitCount: .max, yieldKg: 1),
            makeRecord(id: "extra-count", treeID: "B", scanDate: scanDate, fruitCount: 1, yieldKg: 1)
        ])
        XCTAssertNil(countOverflow.totalFruit)
        XCTAssertEqual(countOverflow.totalYield, 2)

        let yieldOverflow = YieldReportData(records: [
            makeRecord(id: "max-yield-a", treeID: "A", scanDate: scanDate, fruitCount: 1, yieldKg: .greatestFiniteMagnitude),
            makeRecord(id: "max-yield-b", treeID: "B", scanDate: scanDate, fruitCount: 1, yieldKg: .greatestFiniteMagnitude)
        ])
        XCTAssertNil(yieldOverflow.totalYield)
        XCTAssertNil(yieldOverflow.averageYield)
        XCTAssertEqual(yieldOverflow.totalFruit, 2)
    }

    func testYieldReportDataUsesStableTieBreakForSameTreeAndTimestamp() {
        let scanDate = Date(timeIntervalSince1970: 100)
        let report = YieldReportData(records: [
            makeRecord(
                id: "scan-b",
                treeID: "A",
                scanDate: scanDate,
                fruitCount: 20,
                yieldKg: 2
            ),
            makeRecord(
                id: "scan-a",
                treeID: "A",
                scanDate: scanDate,
                fruitCount: 10,
                yieldKg: 1
            )
        ])

        XCTAssertEqual(report.totalScans, 2)
        XCTAssertEqual(report.totalTrees, 1)
        XCTAssertEqual(report.latestRecordsByTree.map(\.id), ["scan-a"])
        XCTAssertEqual(report.totalYield ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(report.totalFruit, 10)
    }

    func testYieldReportDataKeepsLatestCompleteZeroYieldPerTree() {
        let report = YieldReportData(records: [
            makeRecord(
                id: "older-positive",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 100),
                fruitCount: 12,
                yieldKg: 3
            ),
            makeRecord(
                id: "latest-zero",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 200),
                fruitCount: 0,
                yieldKg: 0
            ),
            makeRecord(
                id: "incomplete-newest",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 300),
                fruitCount: 99,
                yieldKg: 99,
                persistenceState: .incomplete
            )
        ])

        XCTAssertEqual(report.totalScans, 2)
        XCTAssertEqual(report.totalTrees, 1)
        XCTAssertEqual(report.latestRecordsByTree.map(\.id), ["latest-zero"])
        XCTAssertEqual(report.visibleRecords.map(\.id), ["latest-zero"])
        XCTAssertEqual(report.totalYield ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(report.averageYield ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(report.totalFruit, 0)
    }

    func testTrendsDataIncludesOnlyCompleteRecordsAndSortsChronologically() {
        let oldestDate = Date(timeIntervalSince1970: 100)
        let middleDate = Date(timeIntervalSince1970: 200)
        let newestDate = Date(timeIntervalSince1970: 300)
        let records = [
            makeRecord(
                id: "complete-newer",
                treeID: "T-002",
                scanDate: newestDate,
                fruitCount: 42,
                yieldKg: 8.4
            ),
            makeRecord(
                id: "incomplete",
                treeID: "T-ERR-1",
                scanDate: middleDate,
                fruitCount: 999,
                yieldKg: 99,
                persistenceState: .incomplete
            ),
            makeRecord(
                id: "invalid",
                treeID: "T-ERR-2",
                scanDate: oldestDate,
                fruitCount: 888,
                yieldKg: 88,
                persistenceState: .invalid
            ),
            makeRecord(id: "complete-older", treeID: "T-001", scanDate: oldestDate, fruitCount: 13, yieldKg: 2.5)
        ]

        let trendsData = TrendsData(records: records)

        XCTAssertEqual(trendsData.records.map(\.id), ["complete-older", "complete-newer"])
        XCTAssertEqual(trendsData.maxYield, 8.4, accuracy: 0.001)
        XCTAssertFalse(trendsData.isEmpty)
    }

    func testTrendsDataIsEmptyWhenOnlyIncompleteRecordsExist() {
        let trendsData = TrendsData(records: [
            makeRecord(
                id: "incomplete",
                treeID: "T-ERR",
                scanDate: Date(),
                fruitCount: 999,
                yieldKg: 99,
                persistenceState: .incomplete
            )
        ])

        XCTAssertTrue(trendsData.records.isEmpty)
        XCTAssertEqual(trendsData.maxYield, 1, accuracy: 0.001)
        XCTAssertTrue(trendsData.isEmpty)
    }

    func testTrendsDataUsesOneAsMinimumScaleForZeroYieldCompleteRecords() {
        let trendsData = TrendsData(records: [
            makeRecord(id: "complete", treeID: "T-001", scanDate: Date(), fruitCount: 0, yieldKg: 0)
        ])

        XCTAssertEqual(trendsData.records.map(\.id), ["complete"])
        XCTAssertEqual(trendsData.maxYield, 1, accuracy: 0.001)
        XCTAssertFalse(trendsData.isEmpty)
    }

    func testOrchardMapDataIncludesOnlyCompleteLocatedRecords() throws {
        let records = [
            makeRecord(
                id: "complete",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 100),
                fruitCount: 21,
                yieldKg: 4.25,
                gpsLat: 31.2304,
                gpsLon: 121.4737,
                confidence: "high"
            ),
            makeRecord(
                id: "incomplete",
                treeID: "T-ERR-1",
                scanDate: Date(timeIntervalSince1970: 200),
                yieldKg: 0,
                gpsLat: 31.2315,
                gpsLon: 121.4748,
                persistenceState: .incomplete
            ),
            makeRecord(
                id: "invalid",
                treeID: "T-ERR-2",
                scanDate: Date(timeIntervalSince1970: 300),
                yieldKg: 0,
                gpsLat: 31.2326,
                gpsLon: 121.4759,
                persistenceState: .invalid
            ),
            makeRecord(
                id: "unlocated",
                treeID: "T-002",
                scanDate: Date(timeIntervalSince1970: 400),
                yieldKg: 8
            )
        ]

        let mapData = OrchardMapData(records: records)
        let tree = try XCTUnwrap(mapData.trees.first)

        XCTAssertEqual(mapData.trees.map(\.id), ["complete"])
        XCTAssertEqual(tree.treeID, "T-001")
        XCTAssertEqual(tree.coordinate.latitude, 31.2304, accuracy: 0.000001)
        XCTAssertEqual(tree.coordinate.longitude, 121.4737, accuracy: 0.000001)
        XCTAssertEqual(tree.weight, 4.25, accuracy: 0.001)
        XCTAssertEqual(tree.fruitCount, 21)
        XCTAssertEqual(tree.confidence, "high")
    }

    func testOrchardMapDataIsEmptyWhenOnlyIncompleteLocatedRecordsExist() {
        let mapData = OrchardMapData(records: [
            makeRecord(
                id: "incomplete",
                treeID: "T-ERR",
                scanDate: Date(),
                yieldKg: 0,
                gpsLat: 31.2315,
                gpsLon: 121.4748,
                persistenceState: .incomplete
            )
        ])

        XCTAssertTrue(mapData.trees.isEmpty)
    }

    func testOrchardMapDataKeepsCompleteZeroYieldRecordsAsLowYield() throws {
        let mapData = OrchardMapData(records: [
            makeRecord(
                id: "complete-zero",
                treeID: "T-003",
                scanDate: Date(),
                fruitCount: 0,
                yieldKg: 0,
                gpsLat: 31.2337,
                gpsLon: 121.4770
            )
        ])

        let tree = try XCTUnwrap(mapData.trees.first)
        XCTAssertEqual(tree.yieldLevel, .low)
        XCTAssertEqual(tree.weight, 0, accuracy: 0.001)
    }

    func testOrchardMapDataKeepsOnlyLatestLocatedCompleteScanPerTree() {
        let records = [
            makeRecord(
                id: "tree-1-older",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 100),
                fruitCount: 10,
                yieldKg: 3,
                gpsLat: 31.1,
                gpsLon: 121.1
            ),
            makeRecord(
                id: "tree-2-latest",
                treeID: "T-002",
                scanDate: Date(timeIntervalSince1970: 400),
                fruitCount: 30,
                yieldKg: 7,
                gpsLat: 31.4,
                gpsLon: 121.4
            ),
            makeRecord(
                id: "tree-1-newer",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 300),
                fruitCount: 20,
                yieldKg: 5,
                gpsLat: 31.3,
                gpsLon: 121.3
            ),
            makeRecord(
                id: "tree-1-incomplete-newest",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 500),
                fruitCount: 99,
                yieldKg: 99,
                gpsLat: 31.5,
                gpsLon: 121.5,
                persistenceState: .incomplete
            )
        ]

        let trees = OrchardMapData(records: records).trees

        XCTAssertEqual(trees.map(\.id), ["tree-2-latest", "tree-1-newer"])
        XCTAssertEqual(trees.map(\.treeID), ["T-002", "T-001"])
        XCTAssertEqual(trees.last?.fruitCount, 20)
        XCTAssertEqual(trees.last?.weight ?? -1, 5, accuracy: 0.001)
    }

    func testOrchardMapDataUsesStableTieBreakForSameTreeAndTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let mapData = OrchardMapData(records: [
            makeRecord(
                id: "scan-b",
                treeID: "T-001",
                scanDate: timestamp,
                yieldKg: 2,
                gpsLat: 31.2,
                gpsLon: 121.2
            ),
            makeRecord(
                id: "scan-a",
                treeID: "T-001",
                scanDate: timestamp,
                yieldKg: 1,
                gpsLat: 31.1,
                gpsLon: 121.1
            )
        ])

        XCTAssertEqual(mapData.trees.map(\.id), ["scan-a"])
    }

    func testOrchardMapDataAcceptsAZeroCoordinateComponentButNotMissingLocation() {
        let mapData = OrchardMapData(records: [
            makeRecord(
                id: "equator",
                treeID: "T-EQUATOR",
                scanDate: Date(timeIntervalSince1970: 300),
                yieldKg: 1,
                gpsLat: 0,
                gpsLon: 121.5
            ),
            makeRecord(
                id: "prime-meridian",
                treeID: "T-PRIME",
                scanDate: Date(timeIntervalSince1970: 200),
                yieldKg: 1,
                gpsLat: 31.5,
                gpsLon: 0
            ),
            makeRecord(
                id: "missing",
                treeID: "T-MISSING",
                scanDate: Date(timeIntervalSince1970: 100),
                yieldKg: 1
            )
        ])

        XCTAssertEqual(mapData.trees.map(\.id), ["equator", "prime-meridian"])
    }

    func testAnalyticsRecordPresentationLocalizesEnglishAndChineseCopy() throws {
        let record = makeRecord(
            id: "localized-record",
            treeID: "TREE-17",
            scanDate: Date(timeIntervalSince1970: 1_786_397_400),
            fruitCount: 12,
            yieldKg: 3.5
        )
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let english = DashboardAnalyticsRecordPresentation(
            record: record,
            bundle: try localizationBundle(language: "en"),
            locale: Locale(identifier: "en_US"),
            timeZone: timeZone
        )
        let chinese = DashboardAnalyticsRecordPresentation(
            record: record,
            bundle: try localizationBundle(language: "zh"),
            locale: Locale(identifier: "zh_CN"),
            timeZone: timeZone
        )

        XCTAssertEqual(english.treeID, "TREE-17")
        XCTAssertEqual(english.yieldValueText, "3.5")
        XCTAssertEqual(english.yieldText, "3.5 kg")
        XCTAssertEqual(english.fruitCountText, "12 fruits")
        XCTAssertFalse(english.rowAccessibilityLabel.contains("个"))
        XCTAssertTrue(english.rowAccessibilityLabel.contains("Tree TREE-17"))
        XCTAssertTrue(english.trendAccessibilityLabel.contains("yield 3.5 kg"))

        XCTAssertEqual(chinese.yieldText, "3.5 kg")
        XCTAssertEqual(chinese.fruitCountText, "12 个果实")
        XCTAssertTrue(chinese.rowAccessibilityLabel.contains("树体 TREE-17"))
        XCTAssertTrue(chinese.trendAccessibilityLabel.contains("产量3.5 kg"))
        XCTAssertNotEqual(english.dateText, chinese.dateText)

        XCTAssertEqual(record.fruitCount, 12)
        XCTAssertEqual(record.yieldKg, 3.5, accuracy: 0.001)
        XCTAssertEqual(record.scanDate, Date(timeIntervalSince1970: 1_786_397_400))
    }

    func testAnalyticsRecordPresentationUsesLocalizedFruitPluralization() throws {
        let bundle = try localizationBundle(language: "en")
        let oneFruit = DashboardAnalyticsRecordPresentation(
            record: makeRecord(
                id: "one-fruit",
                treeID: "T-1",
                scanDate: Date(timeIntervalSince1970: 0),
                fruitCount: 1,
                yieldKg: 0
            ),
            bundle: bundle,
            locale: Locale(identifier: "en_US")
        )
        let multipleFruit = DashboardAnalyticsRecordPresentation(
            record: makeRecord(
                id: "two-fruit",
                treeID: "T-2",
                scanDate: Date(timeIntervalSince1970: 0),
                fruitCount: 2,
                yieldKg: 0
            ),
            bundle: bundle,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertEqual(oneFruit.fruitCountText, "1 fruit")
        XCTAssertEqual(multipleFruit.fruitCountText, "2 fruits")
    }

    func testAnalyticsRecordPresentationUsesRegionalNumberFormatting() throws {
        let presentation = DashboardAnalyticsRecordPresentation(
            record: makeRecord(
                id: "regional-number",
                treeID: "T-3",
                scanDate: Date(timeIntervalSince1970: 0),
                yieldKg: 12.5
            ),
            bundle: try localizationBundle(language: "en"),
            locale: Locale(identifier: "de_DE")
        )

        XCTAssertEqual(presentation.yieldValueText, "12,5")
        XCTAssertEqual(presentation.yieldText, "12,5 kg")
    }

    func testAnalyticsRecordLayoutStacksOnlyAtAccessibilitySizes() {
        XCTAssertEqual(DashboardAnalyticsRecordLayout(dynamicTypeSize: .large), .horizontal)
        XCTAssertEqual(DashboardAnalyticsRecordLayout(dynamicTypeSize: .xxxLarge), .horizontal)
        XCTAssertEqual(DashboardAnalyticsRecordLayout(dynamicTypeSize: .accessibility1), .stacked)
        XCTAssertEqual(DashboardAnalyticsRecordLayout(dynamicTypeSize: .accessibility5), .stacked)
    }

    func testOrchardMapChromeCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "orchard_map.chrome.close_accessibility": "Close Orchard Map",
                "orchard_map.chrome.clear_filter_accessibility": "Clear yield filter",
                "orchard_map.chrome.tree_count_one": "%d tree",
                "orchard_map.chrome.tree_count_other": "%d trees",
                "orchard_map.chrome.filter_high": "High Yield",
                "orchard_map.chrome.filter_medium": "Medium Yield",
                "orchard_map.chrome.filter_low": "Low Yield"
            ],
            "zh": [
                "orchard_map.chrome.close_accessibility": "关闭果园地图",
                "orchard_map.chrome.clear_filter_accessibility": "清除产量筛选",
                "orchard_map.chrome.tree_count_one": "%d 棵果树",
                "orchard_map.chrome.tree_count_other": "%d 棵果树",
                "orchard_map.chrome.filter_high": "高产",
                "orchard_map.chrome.filter_medium": "中产",
                "orchard_map.chrome.filter_low": "低产"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let bundle = try mapChromeLocalizationBundle(language: language)
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    bundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testOrchardMapChromePresentationLocalizesCountsAndFilterLabels() throws {
        let englishBundle = try mapChromeLocalizationBundle(language: "en")
        let chineseBundle = try mapChromeLocalizationBundle(language: "zh")
        let oneTree = OrchardMapChromePresentation(treeCount: 1, bundle: englishBundle)
        let manyTrees = OrchardMapChromePresentation(treeCount: 12, bundle: englishBundle)
        let chinese = OrchardMapChromePresentation(treeCount: 12, bundle: chineseBundle)

        XCTAssertEqual(oneTree.treeCountText, "1 tree")
        XCTAssertEqual(manyTrees.treeCountText, "12 trees")
        XCTAssertEqual(manyTrees.closeAccessibilityLabel, "Close Orchard Map")
        XCTAssertEqual(manyTrees.clearFilterAccessibilityLabel, "Clear yield filter")
        XCTAssertEqual(manyTrees.filterLabel(for: .high), "High Yield")
        XCTAssertEqual(manyTrees.filterLabel(for: .medium), "Medium Yield")
        XCTAssertEqual(manyTrees.filterLabel(for: .low), "Low Yield")

        XCTAssertEqual(chinese.treeCountText, "12 棵果树")
        XCTAssertEqual(chinese.filterLabel(for: .high), "高产")
        XCTAssertEqual(chinese.filterLabel(for: .medium), "中产")
        XCTAssertEqual(chinese.filterLabel(for: .low), "低产")
    }

    func testOrchardMapYieldFilterSelectionSupportsSelectSwitchAndRepeatedClear() {
        let selected = OrchardMapYieldFilterSelection.next(current: nil, tapping: .high)
        let switched = OrchardMapYieldFilterSelection.next(current: selected, tapping: .medium)
        let cleared = OrchardMapYieldFilterSelection.next(current: switched, tapping: .medium)

        XCTAssertEqual(selected, .high)
        XCTAssertEqual(switched, .medium)
        XCTAssertNil(cleared)
    }

    func testOrchardMapLegendLayoutStacksOnlyAtAccessibilitySizes() {
        XCTAssertEqual(OrchardMapLegendLayout(dynamicTypeSize: .large), .horizontal)
        XCTAssertEqual(OrchardMapLegendLayout(dynamicTypeSize: .xxxLarge), .horizontal)
        XCTAssertEqual(OrchardMapLegendLayout(dynamicTypeSize: .accessibility1), .stacked)
        XCTAssertEqual(OrchardMapLegendLayout(dynamicTypeSize: .accessibility5), .stacked)
    }

    func testOrchardTreeCountCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "orchard_map.summary.title": "Orchard Trees",
                "orchard_map.summary.tree_count_one": "%d tree",
                "orchard_map.summary.tree_count_other": "%d trees",
                "orchard_map.summary.level_high": "High Yield",
                "orchard_map.summary.level_medium": "Medium Yield",
                "orchard_map.summary.level_low": "Low Yield"
            ],
            "zh": [
                "orchard_map.summary.title": "园区树木",
                "orchard_map.summary.tree_count_one": "%d 棵果树",
                "orchard_map.summary.tree_count_other": "%d 棵果树",
                "orchard_map.summary.level_high": "高产",
                "orchard_map.summary.level_medium": "中产",
                "orchard_map.summary.level_low": "低产"
            ]
        ]
        for (language, expectedValues) in expectedCopy {
            let bundle = try localizationBundle(language: language)
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), expectedValue)
            }
        }
    }

    func testOrchardTreeCountPresentationPreservesYieldLevelCounts() throws {
        let records = [
            makeRecord(id: "high", treeID: "H", scanDate: Date(), yieldKg: 50, gpsLat: 1, gpsLon: 1),
            makeRecord(id: "medium", treeID: "M", scanDate: Date(), yieldKg: 40, gpsLat: 2, gpsLon: 2),
            makeRecord(id: "low-a", treeID: "L1", scanDate: Date(), yieldKg: 20, gpsLat: 3, gpsLon: 3),
            makeRecord(id: "low-b", treeID: "L2", scanDate: Date(), yieldKg: 0, gpsLat: 4, gpsLon: 4)
        ]
        let summary = TreeYieldSummary(trees: OrchardMapData(records: records).trees)
        let presentation = OrchardTreeCountPresentation(
            summary: summary,
            bundle: try localizationBundle(language: "en")
        )
        XCTAssertEqual(summary.totalCount, 4)
        XCTAssertEqual(summary.count(for: .high), 1)
        XCTAssertEqual(summary.count(for: .medium), 1)
        XCTAssertEqual(summary.count(for: .low), 2)
        XCTAssertEqual(presentation.title, "Orchard Trees")
        XCTAssertEqual(presentation.totalCountText, "4 trees")
        XCTAssertEqual(presentation.high, .init(label: "High Yield", countText: "1 tree"))
        XCTAssertEqual(presentation.medium, .init(label: "Medium Yield", countText: "1 tree"))
        XCTAssertEqual(presentation.low, .init(label: "Low Yield", countText: "2 trees"))
    }

    func testOrchardTreeCountPresentationKeepsZeroCountsVisible() throws {
        let presentation = OrchardTreeCountPresentation(
            summary: TreeYieldSummary(trees: []),
            bundle: try localizationBundle(language: "zh")
        )
        XCTAssertEqual(presentation.totalCountText, "0 棵果树")
        XCTAssertEqual(presentation.high, .init(label: "高产", countText: "0 棵果树"))
        XCTAssertEqual(presentation.medium, .init(label: "中产", countText: "0 棵果树"))
        XCTAssertEqual(presentation.low, .init(label: "低产", countText: "0 棵果树"))
    }

    func testOrchardTreeCountLayoutStacksAtAccessibilitySizes() {
        XCTAssertEqual(OrchardTreeCountLayout(dynamicTypeSize: .large), .horizontal)
        XCTAssertEqual(OrchardTreeCountLayout(dynamicTypeSize: .accessibility1), .stacked)
        XCTAssertEqual(OrchardTreeCountLayout(dynamicTypeSize: .accessibility5), .stacked)
    }

    func testOrchardTreePinCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "orchard_map.pin.tree_label": "Tree %@",
                "orchard_map.pin.level_high": "High yield",
                "orchard_map.pin.level_medium": "Medium yield",
                "orchard_map.pin.level_low": "Low yield",
                "orchard_map.pin.selected_value": "%@, selected"
            ],
            "zh": [
                "orchard_map.pin.tree_label": "果树 %@",
                "orchard_map.pin.level_high": "高产",
                "orchard_map.pin.level_medium": "中产",
                "orchard_map.pin.level_low": "低产",
                "orchard_map.pin.selected_value": "%@，已选中"
            ]
        ]
        for (language, expectedValues) in expectedCopy {
            let bundle = try localizationBundle(language: language)
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), expectedValue)
            }
        }
    }

    func testOrchardTreePinPresentationUsesDistinctYieldSymbols() throws {
        let bundle = try localizationBundle(language: "en")
        let cases: [(yieldKg: Float, symbol: String, value: String)] = [
            (50, "arrow.up.circle.fill", "High yield"),
            (40, "minus.circle.fill", "Medium yield"),
            (20, "arrow.down.circle.fill", "Low yield")
        ]
        let presentations = try cases.enumerated().map { index, item in
            OrchardTreePinPresentation(
                tree: try makePinTree(id: "pin-\(index)", treeID: "T-\(index)", yieldKg: item.yieldKg),
                isSelected: false,
                bundle: bundle
            )
        }
        XCTAssertEqual(presentations.map(\.symbolName), cases.map(\.symbol))
        XCTAssertEqual(presentations.map(\.accessibilityValue), cases.map(\.value))
        XCTAssertEqual(Set(presentations.map(\.symbolName)).count, 3)
    }

    func testOrchardTreePinPresentationAnnouncesSelection() throws {
        let tree = try makePinTree(id: "medium", treeID: "T-017", yieldKg: 40)
        let bundle = try localizationBundle(language: "en")
        let unselected = OrchardTreePinPresentation(tree: tree, isSelected: false, bundle: bundle)
        let selected = OrchardTreePinPresentation(tree: tree, isSelected: true, bundle: bundle)
        XCTAssertEqual(unselected.accessibilityLabel, "Tree T-017")
        XCTAssertEqual(unselected.accessibilityValue, "Medium yield")
        XCTAssertEqual(selected.accessibilityValue, "Medium yield, selected")
        XCTAssertEqual(selected.symbolName, unselected.symbolName)
    }

    func testOrchardTreePinPresentationLocalizesZeroYieldTree() throws {
        let tree = try makePinTree(id: "zero", treeID: "T-000", yieldKg: 0)
        let bundle = try localizationBundle(language: "zh")
        let unselected = OrchardTreePinPresentation(tree: tree, isSelected: false, bundle: bundle)
        let selected = OrchardTreePinPresentation(tree: tree, isSelected: true, bundle: bundle)
        XCTAssertEqual(unselected.symbolName, "arrow.down.circle.fill")
        XCTAssertEqual(unselected.accessibilityLabel, "果树 T-000")
        XCTAssertEqual(unselected.accessibilityValue, "低产")
        XCTAssertEqual(selected.accessibilityValue, "低产，已选中")
    }

    @MainActor
    func testOrchardTreeMapPinUsesRecommendedInteractionSize() throws {
        let tree = try makePinTree(id: "size", treeID: "T-SIZE", yieldKg: 50)
        for isSelected in [false, true] {
            let hostingController = UIHostingController(rootView: TreeMapPin(tree: tree, isSelected: isSelected))
            let size = hostingController.sizeThatFits(in: CGSize(width: 100, height: 100))
            XCTAssertEqual(size.width, 44, accuracy: 0.5)
            XCTAssertEqual(size.height, 44, accuracy: 0.5)
        }
    }

    private func makePinTree(id: String, treeID: String, yieldKg: Float) throws -> TreeAnnotation {
        try XCTUnwrap(
            OrchardMapData(records: [
                makeRecord(
                    id: id,
                    treeID: treeID,
                    scanDate: Date(),
                    yieldKg: yieldKg,
                    gpsLat: 31.2304,
                    gpsLon: 121.4737
                )
            ]).trees.first
        )
    }

    private func makeRecord(
        id: String,
        treeID: String,
        scanDate: Date,
        fruitCount: Int = 0,
        yieldKg: Float,
        gpsLat: Double = 0,
        gpsLon: Double = 0,
        confidence: String = "",
        persistenceState: ScanPersistenceState = .complete
    ) -> ScanFileRecord {
        ScanFileRecord(
            id: id,
            treeID: treeID,
            fileURL: URL(fileURLWithPath: "/tmp/\(id).ply"),
            scanDate: scanDate,
            fruitCount: fruitCount,
            yieldKg: yieldKg,
            gpsLat: gpsLat,
            gpsLon: gpsLon,
            confidence: confidence,
            persistenceState: persistenceState
        )
    }

    private func localizationBundle(language: String) throws -> Bundle {
        try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
            "Missing \(language) localization bundle"
        )
    }

    private func mapChromeLocalizationBundle(language: String) throws -> Bundle {
        try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
            "Missing \(language) localization bundle"
        )
    }
}

final class BatchExportShareLifecycleTests: XCTestCase {
    @MainActor
    func testShareSheetWithoutCompletionKeepsLegacyCallersUnchanged() {
        let controller = ShareSheet(items: ["test-export"]).makeActivityViewController()

        XCTAssertNil(controller.completionWithItemsHandler)
    }

    @MainActor
    func testShareSheetForwardsActivityFailure() async {
        let callback = expectation(description: "Share completion callback")
        callback.assertForOverFulfill = true
        var receivedResult: ShareActivityResult?
        let sheet = ShareSheet(items: ["test-export"]) { result in
            XCTAssertTrue(Thread.isMainThread)
            receivedResult = result
            callback.fulfill()
        }
        let controller = await makePreparedActivityViewController(for: sheet)
        let error = NSError(
            domain: "BatchExportShareLifecycleTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Mock sharing failure"]
        )

        controller.completionWithItemsHandler?(nil, false, nil, error)
        XCTAssertNil(receivedResult, "Sharing completion must leave the UIKit callback before updating the view")
        await fulfillment(of: [callback], timeout: 1)

        XCTAssertEqual(
            receivedResult,
            ShareActivityResult(completed: false, errorDescription: "Mock sharing failure")
        )
    }

    @MainActor
    func testShareSheetForwardsUserCancellationWithoutError() async {
        let callback = expectation(description: "Share cancellation callback")
        callback.assertForOverFulfill = true
        var receivedResult: ShareActivityResult?
        let sheet = ShareSheet(items: ["test-export"]) { result in
            XCTAssertTrue(Thread.isMainThread)
            receivedResult = result
            callback.fulfill()
        }
        let controller = await makePreparedActivityViewController(for: sheet)

        controller.completionWithItemsHandler?(nil, false, nil, nil)
        XCTAssertNil(receivedResult, "User cancellation must be forwarded asynchronously")
        await fulfillment(of: [callback], timeout: 1)

        XCTAssertEqual(
            receivedResult,
            ShareActivityResult(completed: false, errorDescription: nil)
        )
    }

    @MainActor
    private func makePreparedActivityViewController(for sheet: ShareSheet) async -> UIActivityViewController {
        let controller = sheet.makeActivityViewController()
        // A real completion follows an interactive share sheet. Let UIKit's
        // initial main-queue work finish before injecting that event; keep the
        // completion's own one-second deadline independent of cold startup.
        let ready = expectation(description: "Share controller main-queue preparation")
        DispatchQueue.main.async {
            ready.fulfill()
        }
        await fulfillment(of: [ready], timeout: 5)
        return controller
    }

    func testCurrentExportActivityErrorRequiresFailureFeedback() {
        let url = URL(fileURLWithPath: "/tmp/current-export.csv")
        let result = ShareActivityResult(completed: false, errorDescription: "failure")

        XCTAssertTrue(
            BatchExportShareCompletionPolicy.shouldPresentFailure(
                for: result,
                sharedURL: url,
                currentExportURL: url
            )
        )
    }

    func testUserCancellationDoesNotRequireFailureFeedback() {
        let url = URL(fileURLWithPath: "/tmp/current-export.csv")
        let result = ShareActivityResult(completed: false, errorDescription: nil)

        XCTAssertFalse(
            BatchExportShareCompletionPolicy.shouldPresentFailure(
                for: result,
                sharedURL: url,
                currentExportURL: url
            )
        )
    }

    func testLateActivityErrorForReplacedExportIsIgnored() {
        let staleURL = URL(fileURLWithPath: "/tmp/stale-export.csv")
        let currentURL = URL(fileURLWithPath: "/tmp/current-export.csv")
        let result = ShareActivityResult(completed: false, errorDescription: "failure")

        XCTAssertFalse(
            BatchExportShareCompletionPolicy.shouldPresentFailure(
                for: result,
                sharedURL: staleURL,
                currentExportURL: currentURL
            )
        )
    }

    func testLateActivityErrorAfterExportTeardownIsIgnored() {
        let staleURL = URL(fileURLWithPath: "/tmp/stale-export.csv")
        let result = ShareActivityResult(completed: false, errorDescription: "failure")

        XCTAssertFalse(
            BatchExportShareCompletionPolicy.shouldPresentFailure(
                for: result,
                sharedURL: staleURL,
                currentExportURL: nil
            )
        )
    }

    func testShareFailureCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "export.share_failure_title": "Unable to Share",
                "export.share_failure_message": "The sharing service could not complete the operation. Try again or choose another sharing option."
            ],
            "zh": [
                "export.share_failure_title": "分享失败",
                "export.share_failure_message": "分享服务未能完成操作。请重试，或选择其他分享方式。"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }
}

final class DashboardSharedComponentsTests: XCTestCase {
    @MainActor
    func testSharedEmptyConsumersKeepActionsReachableAtCompactAccessibilitySize() async throws {
        let suite = "SharedEmptyConsumers-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tags = TagStore(defaults: defaults)
        for name in ["pointcloud", "report", "trends", "plots"] {
            let store = ScanHistoryStore(recordsLoader: { .success([]) })
            let ui = try RootLaunchUIHarness()
            defer { ui.close() }
            ui.window.frame = CGRect(x: 0, y: 0, width: 874, height: 402)
            var activations = 0
            let content: AnyView
            let labels: [String]
            switch name {
            case "pointcloud":
                content = AnyView(PointCloudSheet(onStartScan: { activations += 1 }, onImportFile: { activations += 1 }, historyStore: store))
                labels = [L10n.PointCloud.newScan, L10n.PointCloud.importPLY]
            case "report":
                content = AnyView(YieldReportSheet(onStartScan: { activations += 1 }, historyStore: store))
                labels = [YieldReportPresentation().startScan]
            case "trends":
                content = AnyView(TrendsSheet(onStartScan: { activations += 1 }, historyStore: store))
                labels = [TrendsPresentation().startScan]
            default:
                content = AnyView(TagManagementView(tagStore: tags))
                labels = [L10n.TagManagement.addPlot]
            }
            ui.mount(content.dynamicTypeSize(.accessibility5)
                .environment(\.horizontalSizeClass, .compact)
                .environment(\.verticalSizeClass, .compact))
            let ready = try await ui.waitFor { ui.element(label: labels.last!) != nil && !store.isLoading }
            XCTAssertTrue(ready, name)
            try await ui.attach(to: self, phase: "Shared-empty-\(name)-compact-AX5-top")
            for label in labels {
                // The plot toolbar has the same label; inspect the lower empty-state action.
                func action() -> NSObject? {
                    ui.elements.filter { $0.accessibilityLabel == label && $0.accessibilityTraits.contains(.button) }
                        .max { $0.accessibilityFrame.minY < $1.accessibilityFrame.minY }
                }
                let scroll = ui.elements.compactMap { $0 as? UIScrollView }
                    .filter { $0.bounds.height > 100 && $0.contentSize.height > $0.bounds.height + 1 }
                    .max { $0.bounds.height < $1.bounds.height }
                let visible = try await ui.waitFor {
                    guard let frame = action()?.accessibilityFrame, frame.width > 0, frame.height > 0 else { return false }
                    let viewport = scroll.map { $0.convert($0.bounds.inset(by: $0.adjustedContentInset), to: nil) } ?? ui.window.bounds
                    if viewport.insetBy(dx: -0.5, dy: -0.5).contains(frame) { return true }
                    if let scroll {
                        let lower = -scroll.adjustedContentInset.top
                        let upper = max(lower, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                        scroll.setContentOffset(CGPoint(x: 0, y: min(upper, max(lower, scroll.contentOffset.y + frame.midY - viewport.midY))), animated: false)
                    }
                    return false
                }
                XCTAssertTrue(visible, "\(name): \(label) must be reachable in the real consumer viewport")
                try await ui.attach(to: self, phase: "Shared-empty-\(name)-compact-AX5-action")
                if visible {
                    let button = try XCTUnwrap(action())
                    XCTAssertGreaterThanOrEqual(button.accessibilityFrame.height, 43.5)
                    XCTAssertTrue(button.accessibilityActivate())
                    if name == "plots" {
                        let opened = try await ui.waitFor { ui.element(label: L10n.TagManagement.cancel) != nil }
                        XCTAssertTrue(opened)
                    }
                }
            }
            if name != "plots" { XCTAssertEqual(activations, labels.count) }
            XCTAssertTrue(store.scanFiles.isEmpty)
            XCTAssertTrue(tags.plots.isEmpty)
        }
    }

    @MainActor
    func testSharedHeaderAndEmptyStateRenderAtLargestAccessibilityTextSize() {
        let fixtures = [
            (
                language: "en",
                headerTitle: "Historical Comparison and Orchard Analytics",
                headerSubtitle: "Review complete LiDAR scans, compare reliable yield evidence, and choose the next field action without losing context.",
                emptyTitle: "Two Complete Scans Are Required Before Comparison",
                emptyMessage: "Complete and save another LiDAR scan. The comparison will then show yield, fruit count, confidence, and scan date for both records.",
                primaryAction: "Start a New LiDAR Scan",
                secondaryAction: "Import an Existing PLY File"
            ),
            (
                language: "zh",
                headerTitle: "历史扫描对比与果园分析",
                headerSubtitle: "查看完整 LiDAR 扫描、比较可靠产量证据，并在不丢失当前上下文的情况下选择下一步现场操作。",
                emptyTitle: "至少需要两条完整扫描才能进行对比",
                emptyMessage: "请再完成并保存一次 LiDAR 扫描。之后可以并排查看两条记录的产量、果数、置信度和扫描日期。",
                primaryAction: "开始新的 LiDAR 扫描",
                secondaryAction: "导入已有 PLY 文件"
            )
        ]

        for fixture in fixtures {
            let view = sharedComponentsFixture(
                headerTitle: fixture.headerTitle,
                headerSubtitle: fixture.headerSubtitle,
                emptyTitle: fixture.emptyTitle,
                emptyMessage: fixture.emptyMessage,
                primaryAction: fixture.primaryAction,
                secondaryAction: fixture.secondaryAction
            )
            .environment(\.dynamicTypeSize, .accessibility5)

            attachRender(
                of: AnyView(view),
                size: CGSize(width: 390, height: 3_600),
                name: "DashboardSharedComponents-\(fixture.language)-AX5"
            )
        }
    }

    @MainActor
    func testSharedHeaderAndEmptyStateKeepCompactStandardLayout() {
        let view = sharedComponentsFixture(
            headerTitle: "Historical Comparison",
            headerSubtitle: "Compare complete scans side by side.",
            emptyTitle: "No Complete Scans",
            emptyMessage: "Complete a scan or import a PLY file to continue.",
            primaryAction: "Start Scanning",
            secondaryAction: "Import PLY"
        )
        .environment(\.dynamicTypeSize, .large)

        attachRender(
            of: AnyView(view),
            size: CGSize(width: 390, height: 1_200),
            name: "DashboardSharedComponents-en-Large"
        )
    }

    private func sharedComponentsFixture(
        headerTitle: String,
        headerSubtitle: String,
        emptyTitle: String,
        emptyMessage: String,
        primaryAction: String,
        secondaryAction: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            DashboardToolHeader(
                imageName: "FeatureCompare",
                title: headerTitle,
                subtitle: headerSubtitle,
                icon: "arrow.left.arrow.right"
            )

            DashboardSheetEmptyState(
                icon: "clock.arrow.circlepath",
                imageName: "FeatureScanHistory",
                title: emptyTitle,
                message: emptyMessage,
                primaryAction: DashboardSheetAction(
                    title: primaryAction,
                    icon: "viewfinder",
                    action: {}
                ),
                secondaryAction: DashboardSheetAction(
                    title: secondaryAction,
                    icon: "square.and.arrow.down",
                    action: {}
                ),
                outerPadding: false
            )

            DashboardSheetEmptyState(
                icon: "tray",
                title: emptyTitle,
                message: emptyMessage,
                primaryAction: DashboardSheetAction(
                    title: primaryAction,
                    icon: "plus",
                    action: {}
                ),
                outerPadding: false
            )

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.colorScheme, .dark)
    }

    @MainActor
    private func attachRender(of view: AnyView, size: CGSize, name: String) {
        let renderer = ImageRenderer(
            content: view.frame(width: size.width, height: size.height, alignment: .top)
        )
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        guard let renderedImage = renderer.uiImage else {
            return XCTFail("Unable to render \(name)")
        }

        XCTAssertEqual(renderedImage.size, size)
        assertImageHasVisibleContent(renderedImage, name: name)
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertImageHasVisibleContent(_ image: UIImage, name: String) {
        let sampleSize = CGSize(width: 64, height: 64)
        let sample = UIGraphicsImageRenderer(size: sampleSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: sampleSize))
        }
        guard let cgImage = sample.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return XCTFail("Unable to inspect rendered pixels for \(name)")
        }

        let byteCount = CFDataGetLength(data)
        var colors = Set<UInt32>()
        for offset in stride(from: 0, to: byteCount - 3, by: 4) {
            let color = UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
            colors.insert(color)
            if colors.count > 8 { break }
        }

        XCTAssertGreaterThan(colors.count, 8, "\(name) rendered without visible component content")
    }
}

final class QuickScanLocalizationTests: XCTestCase {

    func testQuickScanCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "quick_scan.navigation_title": "Quick Scan",
                "quick_scan.header_title": "Quick Capture",
                "quick_scan.header_subtitle": "Tree ID is auto-generated. Confirm field status, then scan.",
                "quick_scan.close": "Close",
                "quick_scan.gps_available": "Current location recorded",
                "quick_scan.gps_unavailable": "GPS not locked. You can still scan.",
                "quick_scan.launching": "Starting...",
                "quick_scan.launch": "Start Quick Scan",
                "quick_scan.tree_id": "Tree ID",
                "quick_scan.tree_id_valid": "Available",
                "quick_scan.tree_id_invalid": "Invalid",
                "quick_scan.tree_id_required": "Required",
                "quick_scan.tree_id_placeholder": "Auto-generated",
                "quick_scan.tree_id_empty_error": "Enter a tree ID",
                "quick_scan.tree_id_too_long_error": "Tree ID must be no more than %d characters",
                "quick_scan.tree_id_path_marker_error": "Tree ID cannot be a path marker",
                "quick_scan.tree_id_forbidden_error": "Tree ID cannot contain /, \\, :, or line breaks"
            ],
            "zh": [
                "quick_scan.navigation_title": "快速扫描",
                "quick_scan.header_title": "快速采集",
                "quick_scan.header_subtitle": "自动生成树编号，只确认现场状态后直接进入扫描。",
                "quick_scan.close": "关闭",
                "quick_scan.gps_available": "已记录当前位置",
                "quick_scan.gps_unavailable": "未锁定 GPS，仍可先扫描",
                "quick_scan.launching": "启动中...",
                "quick_scan.launch": "开始快速扫描",
                "quick_scan.tree_id": "树编号",
                "quick_scan.tree_id_valid": "可用",
                "quick_scan.tree_id_invalid": "无效",
                "quick_scan.tree_id_required": "必填",
                "quick_scan.tree_id_placeholder": "自动生成",
                "quick_scan.tree_id_empty_error": "请输入果树编号",
                "quick_scan.tree_id_too_long_error": "编号最多 %d 个字符",
                "quick_scan.tree_id_path_marker_error": "编号不能使用路径标记",
                "quick_scan.tree_id_forbidden_error": "编号不能包含 /、\\、: 或换行"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testQuickScanMapsEveryTreeIdentifierIssueToDisplayableCopy() {
        let messages = [
            L10n.QuickScan.validationError(for: .empty),
            L10n.QuickScan.validationError(for: .tooLong(maximumCharacterCount: 64)),
            L10n.QuickScan.validationError(for: .pathMarker),
            L10n.QuickScan.validationError(for: .forbiddenCharacters)
        ]

        XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(messages[1].contains("64"))
    }
}

final class StartFlowChromeLocalizationTests: XCTestCase {
    func testStartFlowChromeCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "start.flow.cancel": "Cancel",
                "start.flow.navigation_title": "New Scan",
                "start.flow.previous": "Previous",
                "start.flow.next": "Next",
                "start.flow.launching": "Starting...",
                "start.flow.launch": "Start Scanning",
                "start.flow.progress.identifier": "ID",
                "start.flow.progress.plot": "Plot",
                "start.flow.progress.season": "Season",
                "start.flow.progress.tags": "Tags",
                "start.flow.progress.confirmation": "Confirm",
                "start.flow.step_count_format": "%1$d / %2$d",
                "start.flow.step_count_accessibility_format": "Step %1$d of %2$d",
                "start.flow.step_header_format": "Step %1$d/%2$d",
                "start.flow.progress_accessibility_format": "Step %1$d of %2$d: %3$@"
            ],
            "zh": [
                "start.flow.cancel": "取消",
                "start.flow.navigation_title": "新建扫描",
                "start.flow.previous": "上一步",
                "start.flow.next": "下一步",
                "start.flow.launching": "启动中...",
                "start.flow.launch": "开始扫描",
                "start.flow.progress.identifier": "编号",
                "start.flow.progress.plot": "地块",
                "start.flow.progress.season": "季节",
                "start.flow.progress.tags": "标签",
                "start.flow.progress.confirmation": "确认",
                "start.flow.step_count_format": "%1$d / %2$d",
                "start.flow.step_count_accessibility_format": "第 %1$d 步，共 %2$d 步",
                "start.flow.step_header_format": "步骤 %1$d/%2$d",
                "start.flow.progress_accessibility_format": "第 %1$d 步，共 %2$d 步：%3$@"
            ]
        ]

        let productionKeys = Set(L10n.StartFlow.Key.allCases.map(\.rawValue))

        for (language, expectedValues) in expectedCopy {
            XCTAssertEqual(Set(expectedValues.keys), productionKeys)
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testStartFlowChromeFormatsProgressForEveryLocale() throws {
        let expected: [String: (header: String, count: String, progress: String)] = [
            "en": ("Step 2/5", "Step 2 of 5", "Step 2 of 5: Plot"),
            "zh": ("步骤 2/5", "第 2 步，共 5 步", "第 2 步，共 5 步：地块")
        ]

        for (language, copy) in expected {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            let plot = L10n.StartFlow.text(.progressPlot, in: localizedBundle)

            XCTAssertEqual(L10n.StartFlow.stepHeader(step: 2, totalSteps: 5, in: localizedBundle), copy.header)
            XCTAssertEqual(L10n.StartFlow.stepCountAccessibility(currentStep: 2, totalSteps: 5, in: localizedBundle), copy.count)
            XCTAssertEqual(
                L10n.StartFlow.progressAccessibility(
                    currentStep: 2,
                    totalSteps: 5,
                    label: plot,
                    in: localizedBundle
                ),
                copy.progress
            )
        }
    }

    func testStartFlowChromeStacksControlsAtAccessibilityTextSizes() {
        XCTAssertFalse(StartFlowChromeLayoutPolicy(isAccessibilitySize: false).stacksVertically)
        XCTAssertTrue(StartFlowChromeLayoutPolicy(isAccessibilitySize: true).stacksVertically)
    }
}

final class StartSetupLocalizationTests: XCTestCase {

    func testStartSetupCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "start.setup.identifier.title": "Tree ID",
                "start.setup.identifier.tool_subtitle": "Use one ID to track this tree across scans.",
                "start.setup.identifier.subtitle": "Used in records, exports, and comparisons. Match the ID used in the orchard.",
                "start.setup.identifier.note": "The ID is saved in scan records and exports. It does not affect point-cloud capture.",
                "start.setup.identifier.field_label": "ID",
                "start.setup.identifier.placeholder": "Example: T001",
                "start.setup.identifier.status.available": "Available",
                "start.setup.identifier.status.invalid": "Invalid",
                "start.setup.identifier.status.required": "Required",
                "start.setup.identifier.error.empty": "Enter a tree ID",
                "start.setup.identifier.error.too_long": "Tree ID must be no more than %d characters",
                "start.setup.identifier.error.path_marker": "Tree ID cannot be a path marker",
                "start.setup.identifier.error.forbidden": "Tree ID cannot contain /, \\, :, or line breaks",
                "start.setup.plot.tool_title": "Plot Assignment",
                "start.setup.plot.tool_subtitle": "Assign a plot for filtering and summaries.",
                "start.setup.plot.title": "Plot",
                "start.setup.plot.subtitle": "Optional. Used to filter and summarize scans by plot.",
                "start.setup.plot.empty.title": "No plots yet",
                "start.setup.plot.empty.message": "You can skip this scan and manage plots later in Plot & Tag Management.",
                "start.setup.plot.create": "Create Plot",
                "start.setup.plot.none.title": "Do Not Assign",
                "start.setup.plot.none.subtitle": "Assign the plot after the scan",
                "start.setup.plot.assigned_subtitle": "Assign to this plot",
                "start.setup.plot.add": "Add Plot",
                "start.setup.season.title": "Estimation Stage",
                "start.setup.season.tool_subtitle": "Mature fusion is ready; canopy calibration pending.",
                "start.setup.season.subtitle": "Only mature-stage estimation currently has reliable inputs.",
                "start.setup.season.note": "Non-mature canopy estimation requires calibration with measured weights before it can report evidence-based yield.",
                "start.setup.season.mature.title": "Mature Stage",
                "start.setup.season.mature.subtitle": "RGB + LiDAR fruit fusion",
                "start.setup.season.off.title": "Non-Mature Stage (Calibration Pending)",
                "start.setup.season.off.subtitle": "Canopy regression lacks measured coefficients and cannot be selected yet",
                "start.setup.season.calibration_pending": "Calibration Pending",
                "start.setup.tags.tool_title": "Tag Groups",
                "start.setup.tags.tool_subtitle": "Group varieties, trials, or management status.",
                "start.setup.tags.title": "Tags",
                "start.setup.tags.subtitle": "Optional. Mark varieties, trial groups, or management status.",
                "start.setup.tags.empty.title": "No tags yet",
                "start.setup.tags.empty.message": "Tags are optional and do not affect scanning.",
                "start.setup.tags.create": "Create Tag",
                "start.setup.tags.add": "Add",
                "start.setup.tags.selected_count": "Selected tags: %d",
                "start.setup.confirmation.tool_title": "Start Scan",
                "start.setup.confirmation.tool_subtitle": "Review details, then start LiDAR capture.",
                "start.setup.confirmation.title": "Pre-Scan Check",
                "start.setup.confirmation.subtitle": "Confirm the ID, grouping, and location status.",
                "start.setup.confirmation.unassigned": "Unassigned",
                "start.setup.confirmation.season.mature": "Mature Stage (RGB + LiDAR Fusion)",
                "start.setup.confirmation.season.off": "Non-Mature Stage (Calibration Pending)",
                "start.setup.confirmation.none": "None",
                "start.setup.confirmation.tag_separator": ", ",
                "start.setup.confirmation.gps.available": "Acquired",
                "start.setup.confirmation.gps.pending": "Not locked (optional)",
                "start.setup.confirmation.note": "After starting, move slowly around the tree and keep the canopy and fruit steadily in view."
            ],
            "zh": [
                "start.setup.identifier.title": "果树编号",
                "start.setup.identifier.tool_subtitle": "先建立可追踪的树体档案，后续记录会自动归到这个编号。",
                "start.setup.identifier.subtitle": "用于记录、导出和后续对比，建议与果园现场编号一致。",
                "start.setup.identifier.note": "编号会写入扫描记录和导出文件，不会影响点云采集本身。",
                "start.setup.identifier.field_label": "编号",
                "start.setup.identifier.placeholder": "例：T001",
                "start.setup.identifier.status.available": "可用",
                "start.setup.identifier.status.invalid": "无效",
                "start.setup.identifier.status.required": "必填",
                "start.setup.identifier.error.empty": "请输入果树编号",
                "start.setup.identifier.error.too_long": "编号最多 %d 个字符",
                "start.setup.identifier.error.path_marker": "编号不能使用路径标记",
                "start.setup.identifier.error.forbidden": "编号不能包含 /、\\、: 或换行",
                "start.setup.plot.tool_title": "地块归档",
                "start.setup.plot.tool_subtitle": "把扫描挂到对应地块，便于之后按区域筛选和汇总。",
                "start.setup.plot.title": "地块",
                "start.setup.plot.subtitle": "可选。用于后续按地块筛选和汇总。",
                "start.setup.plot.empty.title": "还没有地块",
                "start.setup.plot.empty.message": "这次扫描可以跳过，之后也能在标签管理中维护。",
                "start.setup.plot.create": "创建地块",
                "start.setup.plot.none.title": "暂不分配",
                "start.setup.plot.none.subtitle": "扫描完成后再归档到地块",
                "start.setup.plot.assigned_subtitle": "分配到该地块",
                "start.setup.plot.add": "添加地块",
                "start.setup.season.title": "估算阶段",
                "start.setup.season.tool_subtitle": "当前开放成熟期融合估算；冠层回归完成实测标定后开放。",
                "start.setup.season.subtitle": "当前仅开放已具备可靠输入的成熟期估算。",
                "start.setup.season.note": "非成熟期冠层路线需先用真实称重数据完成模型标定，避免输出缺乏依据的产量。",
                "start.setup.season.mature.title": "成熟期",
                "start.setup.season.mature.subtitle": "RGB + LiDAR 果实融合估算",
                "start.setup.season.off.title": "非成熟期（待标定）",
                "start.setup.season.off.subtitle": "冠层回归尚缺实测系数，暂不可选择",
                "start.setup.season.calibration_pending": "待标定",
                "start.setup.tags.tool_title": "标签分组",
                "start.setup.tags.tool_subtitle": "用标签标记品种、试验组或管理状态，方便后续复盘。",
                "start.setup.tags.title": "标签",
                "start.setup.tags.subtitle": "可选。用于标记品种、试验组或管理状态。",
                "start.setup.tags.empty.title": "还没有标签",
                "start.setup.tags.empty.message": "标签可以跳过，不会影响扫描。",
                "start.setup.tags.create": "创建标签",
                "start.setup.tags.add": "添加",
                "start.setup.tags.selected_count": "已选 %d 个标签",
                "start.setup.confirmation.tool_title": "启动扫描",
                "start.setup.confirmation.tool_subtitle": "确认信息后进入 LiDAR 采集，请围绕树体缓慢移动。",
                "start.setup.confirmation.title": "启动前检查",
                "start.setup.confirmation.subtitle": "确认编号、分组和定位状态。",
                "start.setup.confirmation.unassigned": "未分配",
                "start.setup.confirmation.season.mature": "成熟期（RGB + LiDAR 融合）",
                "start.setup.confirmation.season.off": "非成熟期（待标定）",
                "start.setup.confirmation.none": "无",
                "start.setup.confirmation.tag_separator": "、",
                "start.setup.confirmation.gps.available": "已获取",
                "start.setup.confirmation.gps.pending": "未锁定（可选）",
                "start.setup.confirmation.note": "开始后请围绕树体缓慢移动，尽量让树冠与果实进入稳定视野。"
            ]
        ]

        let productionKeys = Set(L10n.StartSetup.Key.allCases.map(\.rawValue))

        for (language, expectedValues) in expectedCopy {
            XCTAssertEqual(productionKeys, Set(expectedValues.keys))
            let localizedBundle = try localizedBundle(language)

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testStartSetupFormatsDynamicCopyInBothLanguages() throws {
        let english = try localizedBundle("en")
        let chinese = try localizedBundle("zh")

        XCTAssertEqual(L10n.StartSetup.selectedTagCount(3, in: english), "Selected tags: 3")
        XCTAssertEqual(L10n.StartSetup.selectedTagCount(3, in: chinese), "已选 3 个标签")
        XCTAssertEqual(
            L10n.StartSetup.tagSummary(names: ["A", "B", "C"], remainingCount: 2, in: english),
            "A, B, C +2"
        )
        XCTAssertEqual(
            L10n.StartSetup.tagSummary(names: ["甲", "乙", "丙"], remainingCount: 2, in: chinese),
            "甲、乙、丙 +2"
        )
    }

    func testStartSetupMapsEveryTreeIdentifierIssueInBothLanguages() throws {
        let issues: [TreeIdentifierPolicy.ValidationIssue] = [
            .empty,
            .tooLong(maximumCharacterCount: 64),
            .pathMarker,
            .forbiddenCharacters
        ]

        for language in ["en", "zh"] {
            let bundle = try localizedBundle(language)
            let messages = issues.map { L10n.StartSetup.validationError(for: $0, in: bundle) }
            XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
            XCTAssertTrue(messages[1].contains("64"))
        }
    }

    private func localizedBundle(_ language: String) throws -> Bundle {
        try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
            "Missing \(language) localization bundle"
        )
    }
}

final class DashboardHomeLocalizationTests: XCTestCase {

    func testDashboardHomeCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "dashboard.history_accessibility_label": "Scan history",
                "dashboard.history_accessibility_one": "Scan history, 1 record",
                "dashboard.history_accessibility_count": "Scan history, %d records",
                "dashboard.settings_accessibility_label": "Settings",
                "dashboard.today_scans": "Today's Scans",
                "dashboard.total_yield": "Total Yield",
                "dashboard.recent_scans": "Recent Scans",
                "dashboard.no_scans": "No scan records yet",
                "dashboard.workbench_title": "Orchard Scan Workbench",
                "dashboard.workbench_subtitle": "LiDAR Capture · Point Clouds · Yield",
                "dashboard.field_mode": "Field",
                "dashboard.today": "Today",
                "dashboard.yield": "Yield",
                "dashboard.trees": "Trees",
                "dashboard.scan_unit_one": "scan",
                "dashboard.scan_unit_other": "scans",
                "dashboard.tree_unit_one": "tree",
                "dashboard.tree_unit_other": "trees",
                "dashboard.start_scan": "Start Scan",
                "dashboard.quick_capture": "Quick Scan",
                "dashboard.tools": "Tools",
                "dashboard.mode.scan": "Scan",
                "dashboard.mode.history": "Records",
                "dashboard.mode.analytics": "Analytics",
                "dashboard.action.calibration.title": "Calibration",
                "dashboard.action.calibration.description": "Fruit size and clustering",
                "dashboard.action.import_file.title": "Import PLY",
                "dashboard.action.import_file.description": "Add an existing scan",
                "dashboard.action.scan_history.title": "Scan History",
                "dashboard.action.scan_history.description": "View, delete, and share records",
                "dashboard.action.point_cloud.title": "Point Clouds",
                "dashboard.action.point_cloud.description": "Open recent point clouds",
                "dashboard.action.tag_management.title": "Plots & Tags",
                "dashboard.action.tag_management.description": "Manage plots, tags, and status",
                "dashboard.action.batch_export.title": "Batch Export",
                "dashboard.action.batch_export.description": "Export multiple records",
                "dashboard.action.yield_report.title": "Yield Report",
                "dashboard.action.yield_report.description": "Fruit counts and weight",
                "dashboard.action.compare.title": "Compare Trees",
                "dashboard.action.compare.description": "Compare scan results",
                "dashboard.action.trends.title": "Trends",
                "dashboard.action.trends.description": "Track yield changes",
                "dashboard.action.map.title": "Orchard Map",
                "dashboard.action.map.description": "View trees by location",
                "dashboard.quick_action_accessibility": "%@, %@",
                "dashboard.view_all": "View All",
                "dashboard.view_point_cloud_accessibility": "View point cloud for %@",
                "dashboard.empty_description": "Your recent trees, yields, and point clouds will appear here.",
                "dashboard.start_first_scan": "Start First Scan",
                "dashboard.fruit_count_one": "%d fruit",
                "dashboard.fruit_count_other": "%d fruits",
                "dashboard.analytics.yield_format": "%@ kg",
                "dashboard.analytics.record_accessibility": "Tree %@, %@, %@, %@",
                "dashboard.analytics.trend_accessibility": "%@, yield %@",
                "dashboard.today_overview": "Today’s Overview",
                "dashboard.tree_ids": "Tree IDs"
            ],
            "zh": [
                "dashboard.history_accessibility_label": "扫描历史",
                "dashboard.history_accessibility_one": "扫描历史，1条记录",
                "dashboard.history_accessibility_count": "扫描历史，%d条记录",
                "dashboard.settings_accessibility_label": "设置",
                "dashboard.today_scans": "扫描数量",
                "dashboard.total_yield": "总产量",
                "dashboard.recent_scans": "最近扫描",
                "dashboard.no_scans": "还没有扫描记录",
                "dashboard.workbench_title": "果园扫描工作台",
                "dashboard.workbench_subtitle": "LiDAR 采集 · 点云记录 · 产量分析",
                "dashboard.field_mode": "现场",
                "dashboard.today": "今日",
                "dashboard.yield": "产量",
                "dashboard.trees": "树体",
                "dashboard.scan_unit_one": "次",
                "dashboard.scan_unit_other": "次",
                "dashboard.tree_unit_one": "棵",
                "dashboard.tree_unit_other": "棵",
                "dashboard.start_scan": "新建扫描",
                "dashboard.quick_capture": "快速采集",
                "dashboard.tools": "功能",
                "dashboard.mode.scan": "扫描",
                "dashboard.mode.history": "历史",
                "dashboard.mode.analytics": "分析",
                "dashboard.action.calibration.title": "校准参数",
                "dashboard.action.calibration.description": "水果尺寸、聚类与误差记录",
                "dashboard.action.import_file.title": "导入点云",
                "dashboard.action.import_file.description": "加入已有 PLY 扫描文件",
                "dashboard.action.scan_history.title": "扫描记录",
                "dashboard.action.scan_history.description": "查看、删除和分享记录",
                "dashboard.action.point_cloud.title": "点云查看",
                "dashboard.action.point_cloud.description": "打开最近或指定点云",
                "dashboard.action.tag_management.title": "地块标签",
                "dashboard.action.tag_management.description": "维护地块、标签和状态",
                "dashboard.action.batch_export.title": "批量导出",
                "dashboard.action.batch_export.description": "导出多条扫描数据",
                "dashboard.action.yield_report.title": "产量报告",
                "dashboard.action.yield_report.description": "汇总果数和重量",
                "dashboard.action.compare.title": "树体对比",
                "dashboard.action.compare.description": "横向比较扫描结果",
                "dashboard.action.trends.title": "趋势",
                "dashboard.action.trends.description": "观察产量变化",
                "dashboard.action.map.title": "果园地图",
                "dashboard.action.map.description": "按位置查看树体",
                "dashboard.quick_action_accessibility": "%@，%@",
                "dashboard.view_all": "查看全部",
                "dashboard.view_point_cloud_accessibility": "查看 %@ 点云",
                "dashboard.empty_description": "完成第一次扫描后，这里会显示最近树体、产量和点云入口。",
                "dashboard.start_first_scan": "开始第一次扫描",
                "dashboard.fruit_count_one": "%d 个果实",
                "dashboard.fruit_count_other": "%d 个果实",
                "dashboard.analytics.yield_format": "%@ kg",
                "dashboard.analytics.record_accessibility": "树体 %@，%@，%@，%@",
                "dashboard.analytics.trend_accessibility": "%@，产量%@",
                "dashboard.today_overview": "今日概览",
                "dashboard.tree_ids": "树木数量"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testDashboardHomeFormatsDynamicAndAccessibilityCopy() {
        let emptyHistory = L10n.Dashboard.scanHistoryAccessibilityLabel(recordCount: 0)
        let oneHistory = L10n.Dashboard.scanHistoryAccessibilityLabel(recordCount: 1)
        let multipleHistory = L10n.Dashboard.scanHistoryAccessibilityLabel(recordCount: 12)
        let quickAction = L10n.Dashboard.quickActionAccessibilityLabel(
            title: "Action Title",
            description: "Action Description"
        )
        let oneScanUnit = L10n.Dashboard.scanCountUnit(1)
        let multipleScanUnit = L10n.Dashboard.scanCountUnit(12)
        let oneTreeUnit = L10n.Dashboard.treeCountUnit(1)
        let multipleTreeUnit = L10n.Dashboard.treeCountUnit(12)
        let pointCloud = L10n.Dashboard.viewPointCloudAccessibilityLabel(treeID: "TREE-17")
        let oneFruit = L10n.Dashboard.fruitCountLabel(1)
        let multipleFruit = L10n.Dashboard.fruitCountLabel(12)

        XCTAssertFalse(emptyHistory.isEmpty)
        XCTAssertNotEqual(emptyHistory, oneHistory)
        XCTAssertTrue(oneHistory.contains("1"))
        XCTAssertTrue(multipleHistory.contains("12"))
        XCTAssertTrue(quickAction.contains("Action Title"))
        XCTAssertTrue(quickAction.contains("Action Description"))
        XCTAssertEqual(oneScanUnit, NSLocalizedString("dashboard.scan_unit_one", comment: ""))
        XCTAssertEqual(multipleScanUnit, NSLocalizedString("dashboard.scan_unit_other", comment: ""))
        XCTAssertEqual(oneTreeUnit, NSLocalizedString("dashboard.tree_unit_one", comment: ""))
        XCTAssertEqual(multipleTreeUnit, NSLocalizedString("dashboard.tree_unit_other", comment: ""))
        XCTAssertTrue(pointCloud.contains("TREE-17"))
        XCTAssertTrue(oneFruit.contains("1"))
        XCTAssertTrue(multipleFruit.contains("12"))
        XCTAssertNotEqual(oneFruit, multipleFruit)
    }

    func testDashboardHomeModesUseLocalizedCopy() {
        XCTAssertEqual(AppMode.scan.title, L10n.Dashboard.scanMode)
        XCTAssertEqual(AppMode.history.title, L10n.Dashboard.historyMode)
        XCTAssertEqual(AppMode.analytics.title, L10n.Dashboard.analyticsMode)
    }
}

final class DashboardMetricGridTests: XCTestCase {
    func testGridUsesOneColumnOnlyForAccessibilityTextSizes() {
        XCTAssertEqual(DashboardSheetMetricGridLayout(dynamicTypeSize: .large), .twoColumns)
        XCTAssertEqual(DashboardSheetMetricGridLayout(dynamicTypeSize: .xxxLarge), .twoColumns)
        XCTAssertEqual(DashboardSheetMetricGridLayout(dynamicTypeSize: .accessibility1), .singleColumn)
        XCTAssertEqual(DashboardSheetMetricGridLayout(dynamicTypeSize: .accessibility5), .singleColumn)
    }

    @MainActor
    func testGridRendersEnglishAndChineseAtLargestAccessibilityTextSize() {
        let localizedItems: [(language: String, items: [DashboardSheetMetric])] = [
            ("en", [
                .init(title: "Completed Scans", value: "1,234", unit: "scans"),
                .init(title: "Total Yield", value: "9,876.5", unit: "kg"),
                .init(title: "Average Yield", value: "8.0", unit: "kg"),
                .init(title: "Detected Fruit", value: "12,345", unit: "fruits")
            ]),
            ("zh", [
                .init(title: "完成扫描", value: "1,234", unit: "次"),
                .init(title: "总产量", value: "9,876.5", unit: "kg"),
                .init(title: "平均产量", value: "8.0", unit: "kg"),
                .init(title: "检测果实", value: "12,345", unit: "个")
            ])
        ]
        for localizedGrid in localizedItems {
            let rootView = ScrollView {
                DashboardSheetMetricGrid(items: localizedGrid.items)
                    .padding(Design.Space.lg)
            }
            .frame(width: 390, height: 844)
            .background(Design.Colors.Dark.bgDeep)
            .environment(\.dynamicTypeSize, .accessibility5)
            .environment(\.locale, Locale(identifier: localizedGrid.language))
            .environment(\.colorScheme, .dark)
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            var didDraw = false
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }
            XCTAssertTrue(didDraw)
            XCTAssertEqual(image.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: image)
            attachment.name = "DashboardMetricGrid-\(localizedGrid.language)-AX5"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.resignKey()
        }
    }
}

final class OrchardMapEmptyStateTests: XCTestCase {
    func testCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "title": "No Located Scans",
                "message": "Complete scans with GPS appear on the orchard map so you can view reliable yield distribution.",
                "startScanTitle": "Start Scanning"
            ],
            "zh": [
                "title": "暂无定位扫描",
                "message": "带 GPS 的完整扫描记录会显示在果园地图中，用于查看可靠产量分布。",
                "startScanTitle": "开始扫描"
            ]
        ]
        for (language, expectedValues) in expectedCopy {
            let bundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            let presentation = OrchardMapEmptyStatePresentation(bundle: bundle)
            XCTAssertEqual(presentation.title, expectedValues["title"])
            XCTAssertEqual(presentation.message, expectedValues["message"])
            XCTAssertEqual(presentation.startScanTitle, expectedValues["startScanTitle"])
        }
    }

    func testAdaptiveLayoutStacksOnlyAtAccessibilitySizes() {
        XCTAssertEqual(
            DashboardSheetEmptyStateLayout(dynamicTypeSize: .large, adaptsForAccessibility: true),
            .horizontal
        )
        XCTAssertEqual(
            DashboardSheetEmptyStateLayout(dynamicTypeSize: .accessibility1, adaptsForAccessibility: true),
            .stacked
        )
        XCTAssertEqual(
            DashboardSheetEmptyStateLayout(dynamicTypeSize: .accessibility5, adaptsForAccessibility: false),
            .horizontal
        )
    }

    @MainActor
    func testEmptyStateRendersEnglishAndChineseAtLargestAccessibilityTextSize() throws {
        for language in ["en", "zh"] {
            let bundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            let emptyState = OrchardMapEmptyState(onStartScan: {}, bundle: bundle)
                .environment(\.dynamicTypeSize, .accessibility5)
                .environment(\.locale, Locale(identifier: language))
            let rootView = emptyState
                .frame(width: 390, height: 844)
                .environment(\.colorScheme, .dark)
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            var didDraw = false
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }
            XCTAssertTrue(didDraw)
            XCTAssertEqual(image.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: image)
            attachment.name = "OrchardMapEmptyState-\(language)-AX5"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.resignKey()
        }
    }
}

final class YieldReportPresentationTests: XCTestCase {
    func testCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "yield_report.title": "Yield Report",
                "yield_report.done": "Done",
                "yield_report.done_hint": "Closes the yield report.",
                "yield_report.empty_title": "No Reliable Yield Data",
                "yield_report.empty_message": "Complete and save a scan to summarize yield, fruit count, and averages by tree.",
                "yield_report.start_scan": "Start Scanning",
                "yield_report.header_subtitle": "Summarize fruit count, weight, and each tree's scan result for post-harvest review.",
                "yield_report.tree_details": "Tree Details",
                "yield_report.metric.scans": "Scans",
                "yield_report.metric.total_yield": "Total Yield",
                "yield_report.metric.average_yield": "Average",
                "yield_report.metric.fruit": "Fruit",
                "yield_report.unit.scan_one": "scan",
                "yield_report.unit.scan_other": "scans",
                "yield_report.unit.fruit_one": "fruit",
                "yield_report.unit.fruit_other": "fruits",
                "yield_report.unit.kilograms": "kg"
            ],
            "zh": [
                "yield_report.title": "产量报告",
                "yield_report.done": "完成",
                "yield_report.done_hint": "关闭产量报告。",
                "yield_report.empty_title": "暂无可靠产量数据",
                "yield_report.empty_message": "完成扫描并保存完整结果后，这里会按树体汇总产量、果数和平均值。",
                "yield_report.start_scan": "开始扫描",
                "yield_report.header_subtitle": "汇总果数、重量和每棵树的扫描结果，适合采收后复核。",
                "yield_report.tree_details": "树体明细",
                "yield_report.metric.scans": "扫描",
                "yield_report.metric.total_yield": "总产量",
                "yield_report.metric.average_yield": "平均",
                "yield_report.metric.fruit": "果实",
                "yield_report.unit.scan_one": "次",
                "yield_report.unit.scan_other": "次",
                "yield_report.unit.fruit_one": "个",
                "yield_report.unit.fruit_other": "个",
                "yield_report.unit.kilograms": "kg"
            ]
        ]
        for (language, expectedValues) in expectedCopy {
            let bundle = try localizedBundle(language)
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), expectedValue)
            }
        }
    }

    func testMetricsUseLocalizedGroupingAndPluralUnits() throws {
        let english = YieldReportPresentation(bundle: try localizedBundle("en"))
        let chinese = YieldReportPresentation(bundle: try localizedBundle("zh"))
        XCTAssertEqual(
            english.metricPresentations(
                totalScans: 1_234,
                totalYield: 9_876.5,
                averageYield: 8,
                totalFruit: 12_345,
                locale: Locale(identifier: "en_US")
            ),
            [
                .init(title: "Scans", value: "1,234", unit: "scans"),
                .init(title: "Total Yield", value: "9,876.5", unit: "kg"),
                .init(title: "Average", value: "8.0", unit: "kg"),
                .init(title: "Fruit", value: "12,345", unit: "fruits")
            ]
        )
        XCTAssertEqual(
            chinese.metricPresentations(
                totalScans: 1_234,
                totalYield: 9_876.5,
                averageYield: 8,
                totalFruit: 12_345,
                locale: Locale(identifier: "zh_CN")
            ),
            [
                .init(title: "扫描", value: "1,234", unit: "次"),
                .init(title: "总产量", value: "9,876.5", unit: "kg"),
                .init(title: "平均", value: "8.0", unit: "kg"),
                .init(title: "果实", value: "12,345", unit: "个")
            ]
        )
    }

    private func localizedBundle(_ language: String) throws -> Bundle {
        try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        )
    }
}

final class TrendsPresentationTests: XCTestCase {
    func testCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "trends.title": "Trends",
                "trends.done": "Done",
                "trends.done_hint": "Closes the trends view.",
                "trends.empty_title": "No Reliable Trend Data",
                "trends.empty_message": "Complete and save at least one scan to chart yield changes over time.",
                "trends.start_scan": "Start Scanning",
                "trends.header_subtitle": "Review yield and fruit count over time to support harvest timing decisions.",
                "trends.chart_title": "Yield Trend",
                "trends.records_title": "Records",
                "trends.unit.fruit_one": "fruit",
                "trends.unit.fruit_other": "fruits",
                "trends.unit.kilograms": "kg"
            ],
            "zh": [
                "trends.title": "趋势",
                "trends.done": "完成",
                "trends.done_hint": "关闭趋势视图。",
                "trends.empty_title": "暂无可靠趋势数据",
                "trends.empty_message": "至少完成一次扫描并保存完整结果后，才能显示产量随时间变化。",
                "trends.start_scan": "开始扫描",
                "trends.header_subtitle": "按时间查看产量和果数变化，辅助判断采收节奏。",
                "trends.chart_title": "产量趋势",
                "trends.records_title": "记录",
                "trends.unit.fruit_one": "个",
                "trends.unit.fruit_other": "个",
                "trends.unit.kilograms": "kg"
            ]
        ]
        for (language, expectedValues) in expectedCopy {
            let bundle = try localizedBundle(language)
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), expectedValue)
            }
        }
    }

    func testRecordPresentationUsesRegionalDatesGroupingAndPluralUnits() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 6
        components.day = 1
        let date = try XCTUnwrap(components.date)
        let record = ScanFileRecord(
            id: "record-many",
            treeID: "TREE-1234",
            fileURL: URL(fileURLWithPath: "/tmp/record-many.ply"),
            scanDate: date,
            fruitCount: 1_234,
            yieldKg: 9_876.5
        )
        let english = TrendsPresentation(bundle: try localizedBundle("en"))
            .recordPresentation(for: record, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(english.chartDate, "06/01")
        XCTAssertEqual(english.recordDate, "06/01/2026")
        XCTAssertEqual(english.yieldText, "9,876.5 kg")
        XCTAssertEqual(english.fruitText, "1,234 fruits")
        let chinese = TrendsPresentation(bundle: try localizedBundle("zh"))
            .recordPresentation(for: record, locale: Locale(identifier: "zh_CN"))
        XCTAssertEqual(chinese.recordDate, "2026/06/01")
        XCTAssertEqual(chinese.fruitText, "1,234 个")
    }

    private func localizedBundle(_ language: String) throws -> Bundle {
        try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        )
    }
}

final class BatchExportHeaderLocalizationTests: XCTestCase {
    func testBatchExportHeaderCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "export.navigation_title": "Batch Export",
                "export.header_title": "Batch Export",
                "export.header_subtitle": "Select multiple scan records and export fields, yield, and plot tags.",
                "export.close": "Close",
                "export.select_all": "Select All",
                "export.deselect_all": "Deselect All",
                "export.selection_progress": "Export record selection",
                "export.selection_summary_one": "Selected %d of 1 exportable record",
                "export.selection_summary_other": "Selected %d of %d exportable records",
                "export.selection_summary_compact": "%d of %d selected",
                "export.selected_metrics_one": "%.1f kg · 1 fruit",
                "export.selected_metrics_other": "%.1f kg · %d fruits",
                "export.selected_metrics_compact_one": "%.1f kg · 1 fruit",
                "export.selected_metrics_compact_other": "%.1f kg · %d fruits",
                "export.unavailable_summary_one": "1 record is incomplete or invalid and won't be exported",
                "export.unavailable_summary_other": "%d records are incomplete or invalid and won't be exported",
                "export.unavailable_summary_compact_one": "1 unavailable",
                "export.unavailable_summary_compact_other": "%d unavailable"
            ],
            "zh": [
                "export.navigation_title": "批次导出",
                "export.header_title": "批量导出",
                "export.header_subtitle": "选择多条扫描记录，导出字段、产量和地块标签。",
                "export.close": "关闭",
                "export.select_all": "全选",
                "export.deselect_all": "取消全选",
                "export.selection_progress": "导出记录选择进度",
                "export.selection_summary_one": "已选择 %d / 1 条可导出记录",
                "export.selection_summary_other": "已选择 %d / %d 条可导出记录",
                "export.selection_summary_compact": "已选 %d / %d",
                "export.selected_metrics_one": "%.1f kg · 1 个果实",
                "export.selected_metrics_other": "%.1f kg · %d 个果实",
                "export.selected_metrics_compact_one": "%.1f kg · 1 果",
                "export.selected_metrics_compact_other": "%.1f kg · %d 果",
                "export.unavailable_summary_one": "1 条记录未完整保存或数据无效，未纳入导出",
                "export.unavailable_summary_other": "%d 条记录未完整保存或数据无效，未纳入导出",
                "export.unavailable_summary_compact_one": "1 条不可导出",
                "export.unavailable_summary_compact_other": "%d 条不可导出"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testBatchExportHeaderFormatsSingularPluralAndMetricCopy() throws {
        let englishBundle = try XCTUnwrap(
            Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        )
        let chineseBundle = try XCTUnwrap(
            Bundle.main.path(forResource: "zh", ofType: "lproj").flatMap(Bundle.init(path:))
        )

        XCTAssertEqual(
            L10n.Export.selectionSummary(selectedCount: 1, totalCount: 1, bundle: englishBundle),
            "Selected 1 of 1 exportable record"
        )
        XCTAssertEqual(
            L10n.Export.selectionSummary(selectedCount: 0, totalCount: 0, bundle: englishBundle),
            "Selected 0 of 0 exportable records"
        )
        XCTAssertEqual(
            L10n.Export.selectionSummary(selectedCount: 2, totalCount: 5, bundle: englishBundle),
            "Selected 2 of 5 exportable records"
        )
        XCTAssertEqual(
            L10n.Export.compactSelectionSummary(selectedCount: 2, totalCount: 5, bundle: englishBundle),
            "2 of 5 selected"
        )
        XCTAssertEqual(
            L10n.Export.selectedMetrics(totalYield: 1.25, totalFruitCount: 1, bundle: englishBundle),
            "1.2 kg · 1 fruit"
        )
        XCTAssertEqual(
            L10n.Export.selectedMetrics(totalYield: 8.75, totalFruitCount: 12, bundle: englishBundle),
            "8.8 kg · 12 fruits"
        )
        XCTAssertEqual(
            L10n.Export.compactSelectedMetrics(totalYield: 8.75, totalFruitCount: 12, bundle: englishBundle),
            "8.8 kg · 12 fruits"
        )
        XCTAssertEqual(
            L10n.Export.unavailableSummary(count: 1, bundle: englishBundle),
            "1 record is incomplete or invalid and won't be exported"
        )
        XCTAssertEqual(
            L10n.Export.unavailableSummary(count: 3, bundle: englishBundle),
            "3 records are incomplete or invalid and won't be exported"
        )
        XCTAssertEqual(
            L10n.Export.compactUnavailableSummary(count: 1, bundle: englishBundle),
            "1 unavailable"
        )
        XCTAssertEqual(
            L10n.Export.compactUnavailableSummary(count: 3, bundle: englishBundle),
            "3 unavailable"
        )

        XCTAssertEqual(
            L10n.Export.selectionSummary(selectedCount: 2, totalCount: 5, bundle: chineseBundle),
            "已选择 2 / 5 条可导出记录"
        )
        XCTAssertEqual(
            L10n.Export.selectionSummary(selectedCount: 0, totalCount: 0, bundle: chineseBundle),
            "已选择 0 / 0 条可导出记录"
        )
        XCTAssertEqual(
            L10n.Export.compactSelectionSummary(selectedCount: 2, totalCount: 5, bundle: chineseBundle),
            "已选 2 / 5"
        )
        XCTAssertEqual(
            L10n.Export.selectedMetrics(totalYield: 8.75, totalFruitCount: 12, bundle: chineseBundle),
            "8.8 kg · 12 个果实"
        )
        XCTAssertEqual(
            L10n.Export.compactSelectedMetrics(totalYield: 8.75, totalFruitCount: 12, bundle: chineseBundle),
            "8.8 kg · 12 果"
        )
        XCTAssertEqual(
            L10n.Export.unavailableSummary(count: 3, bundle: chineseBundle),
            "3 条记录未完整保存或数据无效，未纳入导出"
        )
        XCTAssertEqual(
            L10n.Export.compactUnavailableSummary(count: 3, bundle: chineseBundle),
            "3 条不可导出"
        )
        XCTAssertEqual(
            L10n.Export.compactUnavailableSummary(count: 1, bundle: chineseBundle),
            "1 条不可导出"
        )
    }

    @MainActor
    func testBatchExportHeaderRendersAtStandardAndAccessibilityTextSizes() {
        let cases: [(name: String, size: DynamicTypeSize)] = [
            ("Large", .large),
            ("AX5", .accessibility5)
        ]

        for testCase in cases {
            let header = BatchExportHeaderBar(
                selectedCount: 2,
                totalCount: 5,
                unavailableCount: 2,
                totalYield: 8.75,
                totalFruitCount: 12
            )
            .environment(\.dynamicTypeSize, testCase.size)

            let rootView = VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
            }
            .frame(width: 390, height: 844, alignment: .top)
            .background(Design.Colors.Dark.bgDeep)
            .environment(\.colorScheme, .dark)

            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            var didDraw = false
            let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
                .image { _ in
                    didDraw = hostingController.view.drawHierarchy(
                        in: hostingController.view.bounds,
                        afterScreenUpdates: true
                    )
                }

            XCTAssertTrue(didDraw)
            XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: renderedImage)
            attachment.name = "BatchExportHeader-\(Locale.preferredLanguages.first ?? "unknown")-\(testCase.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.resignKey()
        }
    }
}

final class BatchExportEmptyStateLocalizationTests: XCTestCase {
    func testBatchExportEmptyStateCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "export.empty.title": "No Records to Export",
                "export.empty.message": "Scan or import a PLY file, then select records here for CSV or Excel-compatible export.",
                "export.empty.message_compact": "Scan or import a PLY file to add exportable records.",
                "export.empty.start_scan": "Start Scan",
                "export.empty.start_scan_hint": "Open scan setup to create an exportable scan record.",
                "export.empty.import_ply": "Import PLY",
                "export.empty.import_ply_hint": "Open file import to add an existing point cloud to Scan History."
            ],
            "zh": [
                "export.empty.title": "暂无可导出的记录",
                "export.empty.message": "扫描或导入 PLY 文件后，可在这里批量选择并导出 CSV 或 Excel 兼容表格。",
                "export.empty.message_compact": "扫描或导入 PLY 文件以添加可导出记录。",
                "export.empty.start_scan": "开始扫描",
                "export.empty.start_scan_hint": "打开扫描设置，创建可导出的扫描记录。",
                "export.empty.import_ply": "导入 PLY",
                "export.empty.import_ply_hint": "打开文件导入，将已有点云加入扫描记录。"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    @MainActor
    func testBatchExportContentRendersProductionEmptyPathAtStandardAndAccessibilityTextSizes() {
        let cases: [(name: String, size: DynamicTypeSize)] = [
            ("Large", .large),
            ("AX5", .accessibility5)
        ]

        for testCase in cases {
            let content = BatchExportContentView(
                records: [],
                selectedRecords: [],
                exportFormat: .constant(.csv),
                exportOptions: .constant(BatchExportService.ExportOptions()),
                exportedURL: nil,
                isExporting: false,
                onStartScan: {},
                onImportFile: {},
                onToggleSelection: { _ in },
                onOptionsChanged: {},
                onShareExport: {},
                onClearExport: {},
                onPrimaryAction: {}
            )
            .environment(\.dynamicTypeSize, testCase.size)

            let rootView = content
                .frame(width: 390, height: 844, alignment: .top)
                .background(Design.Colors.Dark.bgDeep)
                .environment(\.colorScheme, .dark)

            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            var didDraw = false
            let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
                .image { _ in
                    didDraw = hostingController.view.drawHierarchy(
                        in: hostingController.view.bounds,
                        afterScreenUpdates: true
                    )
                }

            XCTAssertTrue(didDraw)
            XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: renderedImage)
            attachment.name = "BatchExportEmpty-\(Locale.preferredLanguages.first ?? "unknown")-\(testCase.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.resignKey()
        }
    }
}

final class BatchExportCompletionPanelLocalizationTests: XCTestCase {
    func testBatchExportCompletionCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "export.completion.title": "Export Complete",
                "export.completion.file": "Exported file: %@",
                "export.completion.share": "Share",
                "export.completion.share_hint": "Open the share sheet for the exported file.",
                "export.completion.dismiss": "Dismiss",
                "export.completion.dismiss_hint": "Remove this completion status and delete the temporary export file."
            ],
            "zh": [
                "export.completion.title": "导出完成",
                "export.completion.file": "导出文件：%@",
                "export.completion.share": "分享",
                "export.completion.share_hint": "打开已导出文件的分享面板。",
                "export.completion.dismiss": "收起",
                "export.completion.dismiss_hint": "移除此完成状态，并删除临时导出文件。"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    @MainActor
    func testBatchExportCompletionPanelRendersAtStandardAndAccessibilityTextSizes() {
        let cases: [(name: String, size: DynamicTypeSize)] = [
            ("Large", .large),
            ("AX5", .accessibility5)
        ]
        let exportedURL = URL(
            fileURLWithPath: "/tmp/orchard-batch-export-2026-08-09-long-filename-for-accessibility.csv"
        )

        for testCase in cases {
            let panel = BatchExportCompletionPanel(
                url: exportedURL,
                onShare: {},
                onClear: {}
            )
            .environment(\.dynamicTypeSize, testCase.size)
            .padding(Design.Space.md)

            let rootView = panel
                .frame(width: 390, height: 844, alignment: .top)
                .background(Design.Colors.Dark.bgDeep)
                .environment(\.colorScheme, .dark)

            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            var didDraw = false
            let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
                .image { _ in
                    didDraw = hostingController.view.drawHierarchy(
                        in: hostingController.view.bounds,
                        afterScreenUpdates: true
                    )
                }

            XCTAssertTrue(didDraw)
            XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: renderedImage)
            attachment.name = "BatchExportCompletion-\(Locale.preferredLanguages.first ?? "unknown")-\(testCase.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.resignKey()
        }
    }
}

final class BatchExportPrimaryButtonLocalizationTests: XCTestCase {
    func testBatchExportPrimaryActionCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "export.primary.cancel": "Cancel Export",
                "export.primary.cancel_hint": "Stop the current export.",
                "export.primary.export_one": "Export 1 Record",
                "export.primary.export_count": "Export %d Records",
                "export.primary.export_hint": "Create an export file for the selected records and open the share sheet.",
                "export.primary.reexport_one": "Re-export 1 Record",
                "export.primary.reexport_count": "Re-export %d Records",
                "export.primary.reexport_hint": "Replace the temporary export using the current records and options."
            ],
            "zh": [
                "export.primary.cancel": "取消导出",
                "export.primary.cancel_hint": "停止当前导出。",
                "export.primary.export_one": "导出 1 条记录",
                "export.primary.export_count": "导出 %d 条记录",
                "export.primary.export_hint": "为所选记录创建导出文件并打开分享面板。",
                "export.primary.reexport_one": "重新导出 1 条记录",
                "export.primary.reexport_count": "重新导出 %d 条记录",
                "export.primary.reexport_hint": "使用当前记录和选项替换临时导出文件。"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testBatchExportPrimaryActionTitlesPreserveZeroSingularPluralAndReexportStates() {
        let zeroRecords = L10n.Export.primaryExportTitle(recordCount: 0)
        let oneRecord = L10n.Export.primaryExportTitle(recordCount: 1)
        let multipleRecords = L10n.Export.primaryExportTitle(recordCount: 12)
        let repeatedExport = L10n.Export.primaryReexportTitle(recordCount: 12)

        XCTAssertTrue(zeroRecords.contains("0"))
        XCTAssertTrue(oneRecord.contains("1"))
        XCTAssertTrue(multipleRecords.contains("12"))
        XCTAssertTrue(repeatedExport.contains("12"))
        XCTAssertNotEqual(zeroRecords, oneRecord)
        XCTAssertNotEqual(oneRecord, multipleRecords)
        XCTAssertNotEqual(multipleRecords, repeatedExport)
        XCTAssertNotEqual(L10n.Export.primaryCancel, repeatedExport)
    }

    @MainActor
    func testBatchExportPrimaryActionRendersEveryStateAtStandardAndAccessibilityTextSizes() {
        let cases: [(name: String, size: DynamicTypeSize)] = [
            ("Large", .large),
            ("AX5", .accessibility5)
        ]

        for testCase in cases {
            let buttons = VStack(spacing: Design.Space.md) {
                BatchExportPrimaryButton(selectedCount: 1, isExporting: false, hasCompletedExport: false, action: {})
                BatchExportPrimaryButton(selectedCount: 12, isExporting: false, hasCompletedExport: false, action: {})
                BatchExportPrimaryButton(selectedCount: 12, isExporting: false, hasCompletedExport: true, action: {})
                BatchExportPrimaryButton(selectedCount: 12, isExporting: true, hasCompletedExport: false, action: {})
            }
            .environment(\.dynamicTypeSize, testCase.size)
            .padding(Design.Space.md)

            let rootView = buttons
                .frame(width: 390, height: 844, alignment: .top)
                .background(Design.Colors.Dark.bgDeep)
                .environment(\.colorScheme, .dark)
            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            var didDraw = false
            let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }
            XCTAssertTrue(didDraw)
            XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: renderedImage)
            attachment.name = "BatchExportPrimaryAction-\(Locale.preferredLanguages.first ?? "unknown")-\(testCase.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.resignKey()
        }
    }
}

final class BatchExportNavigationChromeLocalizationTests: XCTestCase {
    @MainActor
    func testBatchExportGroupingUsesLightWorkspaceWhenSystemIsDark() async throws {
        let record = ScanFileRecord(
            id: "appearance-record",
            treeID: "APPEARANCE",
            fileURL: URL(fileURLWithPath: "/tmp/appearance-record.ply"),
            scanDate: Date(timeIntervalSince1970: 1_700_000_000),
            fruitCount: 12,
            yieldKg: 3.4
        )
        let store = ScanHistoryStore(recordsLoader: { .success([record]) })
        await store.reloadRecords()
        let suiteName = "BatchExportAppearanceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = UIHostingController(rootView:
            Color.clear.sheet(isPresented: .constant(true)) {
                BatchExportView(store: store, tagStore: TagStore(defaults: defaults))
            }
        )
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
        )
        let previousKeyWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        defer {
            controller.presentedViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }

        func segmentedControls(in view: UIView) -> [UISegmentedControl] {
            (view as? UISegmentedControl).map { [$0] } ?? view.subviews.flatMap(segmentedControls)
        }
        let sheet = try XCTUnwrap(controller.presentedViewController)
        let grouping = try XCTUnwrap(segmentedControls(in: sheet.view).first)
        XCTAssertEqual(grouping.numberOfSegments, 4)
        XCTAssertEqual(grouping.selectedSegmentIndex, 0)
        XCTAssertEqual(
            grouping.traitCollection.userInterfaceStyle, .light,
            "System grouping labels must use light appearance on the daylight workspace surface"
        )

        var didDraw = false
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        XCTAssertTrue(didDraw, "The actual export page must render in a foreground scene")
        let attachment = XCTAttachment(image: image)
        attachment.name = "BatchExport-LightSystem-Appearance"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testBatchExportNavigationCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "export.navigation_title": "Batch Export",
                "export.close": "Close",
                "export.navigation.close_hint": "Close batch export. An active export will be cancelled.",
                "export.select_all": "Select All",
                "export.navigation.select_all_hint": "Select all available records for export.",
                "export.deselect_all": "Deselect All",
                "export.navigation.deselect_all_hint": "Clear the current export selection."
            ],
            "zh": [
                "export.navigation_title": "批次导出",
                "export.close": "关闭",
                "export.navigation.close_hint": "关闭批量导出；正在进行的导出会被取消。",
                "export.select_all": "全选",
                "export.navigation.select_all_hint": "选择全部可导出记录。",
                "export.deselect_all": "取消全选",
                "export.navigation.deselect_all_hint": "清除当前导出选择。"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    @MainActor
    func testBatchExportNavigationRendersAtLargeAndAccessibilityTextSizes() async throws {
        let record = ScanFileRecord(
            id: "navigation-record",
            treeID: "TREE-001",
            fileURL: URL(fileURLWithPath: "/tmp/navigation-record.ply"),
            scanDate: Date(timeIntervalSince1970: 1_700_000_000),
            fruitCount: 12,
            yieldKg: 3.4
        )
        let store = ScanHistoryStore(recordsLoader: { .success([record]) })
        await store.reloadRecords()

        let suiteName = "BatchExportNavigationChromeTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let tagStore = TagStore(defaults: defaults)

        for (size, name) in [(DynamicTypeSize.large, "Large"), (.accessibility5, "AX5")] {
            let view = BatchExportView(store: store, tagStore: tagStore)
                .environment(\.dynamicTypeSize, size)
                .environment(\.colorScheme, .dark)
            let hostingController = UIHostingController(rootView: view)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            var didDraw = false
            let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }
            XCTAssertTrue(didDraw)
            XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: renderedImage)
            attachment.name = "BatchExportNavigation-\(Locale.preferredLanguages.first ?? "unknown")-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.resignKey()
        }
    }
}

final class BatchExportFailureFeedbackTests: XCTestCase {
    func testBatchExportFailureCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "export.failure.title": "Couldn’t Export Records",
                "export.failure.cancel": "Cancel",
                "export.failure.retry": "Try Again",
                "export.failure.no_records_recovery": "Select at least one complete record and try again.",
                "export.failure.out_of_space": "There isn’t enough available storage to create the export. Free up space and try again.",
                "export.failure.file_write": "The export file couldn’t be written. Check available storage and try again.",
                "export.failure.generic": "The export couldn’t be completed. Try again; if the problem continues, choose another format.",
                "export.no_records": "No records to export"
            ],
            "zh": [
                "export.failure.title": "无法导出记录",
                "export.failure.cancel": "取消",
                "export.failure.retry": "重试",
                "export.failure.no_records_recovery": "请选择至少一条完整记录后重试。",
                "export.failure.out_of_space": "可用存储空间不足，无法创建导出文件。请释放空间后重试。",
                "export.failure.file_write": "无法写入导出文件。请检查可用存储空间后重试。",
                "export.failure.generic": "导出未能完成。请重试；如果问题持续，可改用其他导出格式。",
                "export.no_records": "没有可导出的记录"
            ]
        ]
        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testBatchExportFailureClassifiesErrorsAndProvidesRecoveryCopy() {
        let noRecords = BatchExportFailurePresentation(error: BatchExportError.noRecords)
        let aggregate = BatchExportFailurePresentation(error: BatchExportError.aggregateOutOfRange)
        let inconsistent = BatchExportFailurePresentation(error: BatchExportError.inconsistentRecord)
        let outOfSpace = BatchExportFailurePresentation(error: CocoaError(.fileWriteOutOfSpace))
        let fileWrite = BatchExportFailurePresentation(error: CocoaError(.fileWriteNoPermission))
        let generic = BatchExportFailurePresentation(error: NSError(domain: "BatchExportFailureTests", code: 1))
        let wrappedOutOfSpace = BatchExportFailurePresentation(
            error: NSError(
                domain: "BatchExportFailureTests",
                code: 2,
                userInfo: [NSUnderlyingErrorKey: CocoaError(.fileWriteOutOfSpace)]
            )
        )

        XCTAssertEqual(noRecords.kind, .noRecords)
        XCTAssertEqual(aggregate.kind, .aggregateOutOfRange)
        XCTAssertEqual(inconsistent.kind, .inconsistentRecord)
        XCTAssertFalse(inconsistent.message.isEmpty)
        XCTAssertEqual(outOfSpace.kind, .outOfSpace)
        XCTAssertEqual(fileWrite.kind, .fileWrite)
        XCTAssertEqual(generic.kind, .generic)
        XCTAssertEqual(wrappedOutOfSpace.kind, .outOfSpace)
        XCTAssertEqual(BatchExportError.noRecords.errorDescription, L10n.Export.noRecords)
        XCTAssertEqual(BatchExportError.noRecords.recoverySuggestion, L10n.Export.noRecordsRecovery)
        XCTAssertTrue([noRecords, aggregate, outOfSpace, fileWrite, generic].allSatisfy { !$0.message.isEmpty })
        XCTAssertEqual(Set([noRecords.message, aggregate.message, outOfSpace.message, fileWrite.message, generic.message]).count, 5)
    }

    @MainActor
    func testBatchExportFailureAlertRendersAtLargeAndAccessibilityTextSizes() async throws {
        for (size, name) in [(DynamicTypeSize.large, "Large"), (.accessibility5, "AX5")] {
            let rootView = BatchExportFailureAlertHarness(
                failure: BatchExportFailurePresentation(error: CocoaError(.fileWriteOutOfSpace))
            ) {
                Color.black.ignoresSafeArea()
            }
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, .dark)

            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let sceneDiagnostics = UIApplication.shared.connectedScenes.map { scene in
                let windows = (scene as? UIWindowScene)?.windows.map { window in
                    "hidden=\(window.isHidden),key=\(window.isKeyWindow),root=\(String(describing: window.rootViewController))"
                }.joined(separator: "; ") ?? "not a UIWindowScene"
                return "type=\(type(of: scene)),state=\(scene.activationState.rawValue),role=\(scene.session.role.rawValue),windows=[\(windows)]"
            }.sorted().joined(separator: "\n")
            let sceneAttachment = XCTAttachment(string: "applicationState=\(UIApplication.shared.applicationState.rawValue)\n\(sceneDiagnostics)")
            sceneAttachment.name = "BatchExportFailure-SceneState-\(name)"
            sceneAttachment.lifetime = .keepAlways
            add(sceneAttachment)
            let foreground = expectation(for: NSPredicate { _, _ in
                UIApplication.shared.applicationState == .active && UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .contains { $0.activationState == .foregroundActive }
            }, evaluatedWith: nil)
            await fulfillment(of: [foreground], timeout: 5)
            let windowScene = try XCTUnwrap(
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first { $0.activationState == .foregroundActive }
            )
            let window = UIWindow(windowScene: windowScene)
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))

            let alertController = try XCTUnwrap(hostingController.presentedViewController as? UIAlertController)
            XCTAssertEqual(alertController.title, L10n.Export.failureTitle)
            XCTAssertEqual(alertController.message, L10n.Export.outOfSpaceRecovery)
            XCTAssertEqual(alertController.actions.count, 2)
            XCTAssertEqual(Set(alertController.actions.compactMap(\.title)), Set([L10n.Export.failureCancel, L10n.Export.failureRetry]))

            var didDraw = false
            let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            XCTAssertTrue(didDraw)
            XCTAssertEqual(renderedImage.size.width, window.bounds.width, accuracy: 1)
            XCTAssertEqual(renderedImage.size.height, window.bounds.height, accuracy: 1)
            let attachment = XCTAttachment(image: renderedImage)
            attachment.name = "BatchExportFailure-\(Locale.preferredLanguages.first ?? "unknown")-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            alertController.dismiss(animated: false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            window.isHidden = true
            window.rootViewController = nil
        }
    }
}

private struct PointCloudDismissalTestHost: View {
    let historyStore: ScanHistoryStore
    @State private var isPresented = false
    @State private var didPresent = false

    var body: some View {
        Text("PREVIEW-HOST")
            .sheet(isPresented: $isPresented) {
                PointCloudSheet(historyStore: historyStore)
            }
            .onAppear {
                guard !didPresent else { return }
                didPresent = true
                isPresented = true
            }
    }
}

private struct BatchExportFailureAlertHarness<Content: View>: View {
    @State private var failure: BatchExportFailurePresentation?
    private let content: Content

    init(failure: BatchExportFailurePresentation, @ViewBuilder content: () -> Content) {
        _failure = State(initialValue: failure)
        self.content = content()
    }

    var body: some View {
        content.batchExportFailureAlert(failure: $failure, onRetry: {})
    }
}

/// 归档详情刷新回归用的夹具：自有临时目录 + 隔离的标签存储。
///
/// 档案用**生产写入器**（PLYPointCloudWriter）和生产读取器认得的伴随文件格式写出来，
/// 详情页读到的是真实档案；全程不碰用户档案，也不碰默认模拟器数据。
@MainActor
private final class ArchiveDetailRefreshFixture {
    struct Files {
        let plyURL: URL
        let metadataURL: URL
        let manifestURL: URL
    }

    /// 完成清单怎么写。
    enum ManifestMode: Equatable {
        /// 不写清单（旧格式档案）。
        case none
        /// 清单与结果文件一致（事务式档案，核对得过）。
        case matching
        /// 清单的 revision 与结果文件不一致（核对不过）。
        case revisionMismatch
        /// 清单记的源点云摘要与实际点云不一致（核对不过）。
        case sourceDigestMismatch
    }

    enum FixtureError: Error {
        case defaultsUnavailable
    }

    /// 详情页「这条记录已经不在档案里了」的文案（与生产同一个 key）。
    static let recordMissingMessage = NSLocalizedString(
        "history.detail.record_missing",
        value: "这条记录已经不在档案里了。",
        comment: ""
    )

    let directory: URL
    let tagStore: TagStore
    private let suiteName: String

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-detail-refresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "archive-detail-refresh-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw FixtureError.defaultsUnavailable
        }
        tagStore = TagStore(defaults: defaults)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// 写一份真实档案：点云 + 结果 JSON（+ 可选完成清单）。
    @discardableResult
    func writeArchive(
        baseName: String,
        treeID: String,
        scanDate: String = "2026-10-20 10:00:00",
        fruitCount: Int,
        yieldKg: Float,
        fruitType: String = "apple",
        confidence: String = "high",
        exportRevision: String? = nil,
        manifestMode: ManifestMode = .none,
        pointCount: Int = 4
    ) throws -> Files {
        let plyURL = directory.appendingPathComponent("\(baseName).ply")
        let metadataURL = directory.appendingPathComponent("\(baseName)_result.json")
        let manifestURL = directory.appendingPathComponent("\(baseName)_complete.json")
        let points = (0..<max(1, pointCount)).map { index in
            ColoredPoint(
                pos: SIMD3<Float>(Float(index) * 0.25, 1, 0),
                r: 0.3,
                g: 0.7,
                b: 0.2
            )
        }
        try PLYPointCloudWriter.write(
            points: points,
            treeID: treeID,
            scanDate: scanDate,
            gpsLat: 31.23,
            gpsLon: 121.47,
            to: plyURL
        )
        var metadata: [String: Any] = [
            "fruitCount": fruitCount,
            "yieldKg": yieldKg,
            "fruitType": fruitType,
            "confidence": confidence
        ]
        if let exportRevision {
            metadata["exportRevision"] = exportRevision
        }
        try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            .write(to: metadataURL)

        switch manifestMode {
        case .none:
            try? FileManager.default.removeItem(at: manifestURL)
        case .matching, .revisionMismatch, .sourceDigestMismatch:
            let revision = exportRevision ?? "rev-1"
            let manifestRevision = manifestMode == .revisionMismatch ? "rev-other" : revision
            let sourceDigest = manifestMode == .sourceDigestMismatch
                ? String(repeating: "0", count: 64)
                : try ScanCompanionIntegrity.digestFile(at: plyURL)
            let manifest: [String: Any] = [
                "schemaVersion": 3,
                "scanID": baseName,
                "exportRevision": manifestRevision,
                "requiredFiles": [metadataURL.lastPathComponent],
                "fileSHA256": [
                    metadataURL.lastPathComponent: try ScanCompanionIntegrity.digestFile(at: metadataURL)
                ],
                "sourcePLYFilename": plyURL.lastPathComponent,
                "sourcePLYSHA256": sourceDigest
            ]
            try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                .write(to: manifestURL)
        }
        return Files(plyURL: plyURL, metadataURL: metadataURL, manifestURL: manifestURL)
    }

    /// 只拿掉伴随文件（结果 JSON 与完成清单）：点云还在，档案本身没有消失。
    func removeCompanion(_ files: Files) {
        try? FileManager.default.removeItem(at: files.metadataURL)
        try? FileManager.default.removeItem(at: files.manifestURL)
    }

    /// 整个档案拿掉。
    func removeArchive(_ files: Files) {
        try? FileManager.default.removeItem(at: files.plyURL)
        removeCompanion(files)
    }
}

/// 档案分享回归用的夹具：自有临时目录 + 隔离的标签存储。
///
/// 档案用**生产写入器**（PLYPointCloudWriter）写出来，档案页读到的是真实记录；
/// 全程不碰用户档案，也不碰默认模拟器数据。
@MainActor
private final class ArchiveShareFixture {
    enum FixtureError: Error {
        case defaultsUnavailable
    }

    let directory: URL
    let store: ScanHistoryStore
    let tagStore: TagStore
    let recordName: String
    private let suiteName: String

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("archive-share-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "archive-share-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw FixtureError.defaultsUnavailable
        }
        tagStore = TagStore(defaults: defaults)
        recordName = "T-40-a.ply"
        try PLYPointCloudWriter.write(
            points: [ColoredPoint(pos: SIMD3<Float>(0, 1, 0), r: 0.3, g: 0.7, b: 0.2)],
            treeID: "T-40", scanDate: "2026-10-29 12:00:00", gpsLat: 0, gpsLon: 0,
            to: directory.appendingPathComponent(recordName)
        )
        store = ScanHistoryStore(repository: ScanRepository(scansDirectory: directory))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// 一次真实的分享失败：接收方打不开这个文件，UIKit 会把这样的错误交回完成回调。
    static func makeFailure() -> NSError {
        NSError(
            domain: "ArchiveShareFixture",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "The receiving app cannot open this file."]
        )
    }
}

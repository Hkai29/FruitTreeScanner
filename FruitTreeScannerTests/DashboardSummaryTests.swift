import Combine
import CoreLocation
import MapKit
import SwiftUI
import UIKit
import XCTest
import SwiftUI
import UIKit
@testable import FruitTreeScanner

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
        visit(window)
        var current: UIViewController? = controller
        while let root = current {
            visit(root.view)
            current = root.presentedViewController
        }
        return result
    }

    func element(label: String) -> NSObject? {
        let matches = elements.filter { $0.accessibilityLabel == label }
        return matches.first { $0.accessibilityTraits.contains(.button) } ?? matches.first
    }

    var categoryPicker: NSObject? {
        elements.first {
            $0 is UIButton &&
                $0.accessibilityLabel?.contains(L10n.FruitCategoryVerification.selectedAccessibilityLabel) == true &&
                $0.accessibilityValue != nil
        }
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

    func waitFor(_ condition: () -> Bool) async throws -> Bool {
        func settled(_ current: UIViewController) -> Bool {
            current.transitionCoordinator == nil && !current.isBeingPresented && !current.isBeingDismissed &&
                current.children.allSatisfy(settled) && (current.presentedViewController.map(settled) ?? true)
        }
        let deadline = Date().addingTimeInterval(3)
        repeat {
            window.layoutIfNeeded()
            if settled(controller) && condition() { return true }
            try await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        return false
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
        let text = XCTAttachment(string: elements.compactMap {
            guard let label = $0.accessibilityLabel else { return nil }
            return String(describing: type(of: $0)) + " [" + String($0.accessibilityTraits.rawValue) +
                "] control=" + String($0 is UIControl) + " " + label + " = " + ($0.accessibilityValue ?? "")
        }.joined(separator: "\n"))
        text.name = "RootLaunch-\(phase)-accessibility"
        text.lifetime = .keepAlways
        test.add(text)
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

final class DashboardSummaryTests: XCTestCase {
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
            let text = XCTAttachment(string: elements(in: window).compactMap {
                guard let label = $0.accessibilityLabel else { return nil }
                return String(describing: type(of: $0)) + " [" + String($0.accessibilityTraits.rawValue) + "] " +
                    label + " = " + ($0.accessibilityValue ?? "")
            }.joined(separator: "\n"))
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
        let controller = UIHostingController(rootView: dashboard.sheetView(for: .pointCloud(initialURL)))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
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

        func selectedLabels(in object: NSObject) -> [String] {
            var visited = Set<ObjectIdentifier>()
            func visit(_ object: NSObject, depth: Int = 0) -> [String] {
                guard depth < 32, visited.insert(ObjectIdentifier(object)).inserted else { return [] }
                var labels = object.accessibilityTraits.contains(.selected)
                    ? [object.accessibilityLabel].compactMap { $0 } : []
                let count = object.accessibilityElementCount()
                if count > 0 && count < 100 {
                    for index in 0..<count {
                        if let child = object.accessibilityElement(at: index) as? NSObject {
                            labels += visit(child, depth: depth + 1)
                        }
                    }
                }
                if let view = object as? UIView {
                    labels += view.subviews.flatMap { visit($0, depth: depth + 1) }
                }
                return labels
            }
            return visit(object)
        }
        func waitForText(_ expected: String, selected: String? = nil) async throws -> String {
            var text = ""
            let deadline = Date().addingTimeInterval(3)
            repeat {
                controller.view.layoutIfNeeded()
                text = renderedAccessibilityText(in: controller.view)
                if !dependencies.historyStore.isLoading, text.contains(expected),
                   selected.map({ selectedLabels(in: controller.view).contains($0) }) ?? true { break }
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
        }
        let initialText = try await waitForText(initialTreeID, selected: initialTreeID)
        attach("RootPreview-Initial")
        XCTAssertTrue(initialText.contains(initialTreeID), "Preview must use the Dashboard root archive: \(initialText)")
        XCTAssertEqual(try Data(contentsOf: initialURL), initialBytes)
        guard initialText.contains(initialTreeID) else { return }
        XCTAssertTrue(selectedLabels(in: controller.view).contains(initialTreeID))

        try PLYPointCloudWriter.write(points: points, treeID: nextTreeID,
                                      scanDate: "2026-10-02 00:00:00", gpsLat: 0, gpsLon: 0, to: nextURL)
        let nextBytes = try Data(contentsOf: nextURL)
        await dependencies.historyStore.reloadRecords()
        XCTAssertEqual(dependencies.historyStore.scanFiles.first?.fileURL, nextURL)
        let refreshedText = try await waitForText(nextTreeID, selected: initialTreeID)
        XCTAssertTrue(refreshedText.contains(nextTreeID))
        XCTAssertTrue(selectedLabels(in: controller.view).contains(initialTreeID), "A new newest record must not replace the explicit selection")
        XCTAssertEqual(try Data(contentsOf: initialURL), initialBytes)
        XCTAssertEqual(try Data(contentsOf: nextURL), nextBytes)

        // Remove only temporary test-owned sources; this is not user archive deletion.
        try FileManager.default.removeItem(at: initialURL)
        await dependencies.historyStore.reloadRecords()
        let fallbackText = try await waitForText(nextTreeID, selected: nextTreeID)
        XCTAssertTrue(fallbackText.contains(nextTreeID))
        XCTAssertFalse(fallbackText.contains(initialTreeID))
        XCTAssertTrue(selectedLabels(in: controller.view).contains(nextTreeID), "A missing selection must fall back within the same root")
        XCTAssertEqual(try Data(contentsOf: nextURL), nextBytes)
        attach("RootPreview-Fallback")

        try FileManager.default.removeItem(at: nextURL)
        await dependencies.historyStore.reloadRecords()
        let emptyText = try await waitForText(L10n.PointCloud.emptyTitle)
        XCTAssertTrue(emptyText.contains(L10n.PointCloud.emptyTitle))
        XCTAssertTrue(emptyText.contains(L10n.PointCloud.newScan))
        XCTAssertTrue(emptyText.contains(L10n.PointCloud.importPLY))
        XCTAssertFalse(emptyText.contains(nextTreeID))
        attach("RootPreview-Empty")
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
        var receivedResult: ShareActivityResult?
        let sheet = ShareSheet(items: ["test-export"]) { result in
            receivedResult = result
            callback.fulfill()
        }
        let controller = sheet.makeActivityViewController()
        let error = NSError(
            domain: "BatchExportShareLifecycleTests",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Mock sharing failure"]
        )

        controller.completionWithItemsHandler?(nil, false, nil, error)
        await fulfillment(of: [callback], timeout: 1)

        XCTAssertEqual(
            receivedResult,
            ShareActivityResult(completed: false, errorDescription: "Mock sharing failure")
        )
    }

    @MainActor
    func testShareSheetForwardsUserCancellationWithoutError() async {
        let callback = expectation(description: "Share cancellation callback")
        var receivedResult: ShareActivityResult?
        let sheet = ShareSheet(items: ["test-export"]) { result in
            receivedResult = result
            callback.fulfill()
        }
        let controller = sheet.makeActivityViewController()

        controller.completionWithItemsHandler?(nil, false, nil, nil)
        await fulfillment(of: [callback], timeout: 1)

        XCTAssertEqual(
            receivedResult,
            ShareActivityResult(completed: false, errorDescription: nil)
        )
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
                "start.setup.confirmation.gps.pending": "Acquiring...",
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
                "start.setup.confirmation.gps.pending": "获取中...",
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
                "dashboard.mode.scan": "Scanning",
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
                "dashboard.tree_ids": "树编号"
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
    func testBatchExportGroupingUsesDarkAppearanceWhenSystemIsLight() async throws {
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
        window.overrideUserInterfaceStyle = .light
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
            grouping.traitCollection.userInterfaceStyle, .dark,
            "System grouping labels must use dark appearance on the fixed dark export surface"
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

// GPSRecorder.swift
// GPS 坐标采集（写入 PLY header）

import CoreLocation
import Combine

struct GPSLocationSnapshot: Equatable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: CLLocationAccuracy
    let timestamp: Date
}

enum GPSLocationPolicy {
    /// Tree-level map pins are not useful when the reported uncertainty is wider
    /// than typical orchard spacing. Unreliable fixes are omitted instead of
    /// being persisted as if they were precise tree locations.
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 8.0
    static let maximumLocationAge: TimeInterval = 12.0
    static let maximumFutureTimestampSkew: TimeInterval = 1.0
    static let maximumSampleCount = 12

    static func isAcceptable(_ location: CLLocation, at now: Date) -> Bool {
        let coordinate = location.coordinate
        guard CLLocationCoordinate2DIsValid(coordinate),
              coordinate.latitude.isFinite,
              coordinate.longitude.isFinite,
              location.horizontalAccuracy.isFinite,
              location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= maximumHorizontalAccuracy
        else {
            return false
        }

        let age = now.timeIntervalSince(location.timestamp)
        return age >= -maximumFutureTimestampSkew && age <= maximumLocationAge
    }

    static func bestLocation(from locations: [CLLocation], at now: Date) -> CLLocation? {
        locations
            .filter { isAcceptable($0, at: now) }
            .min { lhs, rhs in
                if lhs.horizontalAccuracy == rhs.horizontalAccuracy {
                    return lhs.timestamp > rhs.timestamp
                }
                return lhs.horizontalAccuracy < rhs.horizontalAccuracy
            }
    }
}

enum GPSRecorderStatus: Equatable {
    case requestingPermission
    case locating
    case preciseLocationRequired
    case permissionDenied
    case accuracyInsufficient(CLLocationAccuracy)
    case ready(CLLocationAccuracy)
    case unavailable

    var message: String {
        switch self {
        case .requestingPermission:
            return "等待定位授权"
        case .locating:
            return "正在获取高精度位置"
        case .preciseLocationRequired:
            return "请在系统设置中开启精确位置"
        case .permissionDenied:
            return "定位权限未开启"
        case .accuracyInsufficient(let accuracy):
            return "定位精度不足（±\(Int(ceil(accuracy))) m）"
        case .ready(let accuracy):
            return "已获取（±\(Int(ceil(accuracy))) m）"
        case .unavailable:
            return "定位暂不可用"
        }
    }

    var isAvailable: Bool {
        if case .ready = self { return true }
        return false
    }
}

final class GPSRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let sampleLock = NSLock()
    private var acceptedLocations: [CLLocation] = []

    @Published private(set) var latitude: Double = 0.0
    @Published private(set) var longitude: Double = 0.0
    @Published private(set) var horizontalAccuracy: CLLocationAccuracy?
    @Published private(set) var status: GPSRecorderStatus = .requestingPermission

    var isAvailable: Bool { status.isAvailable }
    var statusMessage: String { status.message }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.requestWhenInUseAuthorization()
    }

    deinit {
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            if manager.accuracyAuthorization == .reducedAccuracy {
                publishUnavailable(status: .preciseLocationRequired)
            } else {
                publishUnavailable(status: .locating)
            }
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            clearAcceptedLocations()
            publishUnavailable(status: .permissionDenied)
        case .notDetermined:
            publishUnavailable(status: .requestingPermission)
            manager.requestWhenInUseAuthorization()
        @unknown default:
            publishUnavailable(status: .unavailable)
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard manager.accuracyAuthorization == .fullAccuracy else {
            clearAcceptedLocations()
            publishUnavailable(status: .preciseLocationRequired)
            return
        }

        let now = Date()
        let acceptable = locations.filter { GPSLocationPolicy.isAcceptable($0, at: now) }
        let best = storeAndSelectBest(acceptable, at: now)

        if let best {
            publish(best)
            return
        }

        guard let latest = locations.last else {
            publishUnavailable(status: .locating)
            return
        }

        let age = now.timeIntervalSince(latest.timestamp)
        if latest.horizontalAccuracy.isFinite,
           latest.horizontalAccuracy >= 0,
           age >= -GPSLocationPolicy.maximumFutureTimestampSkew,
           age <= GPSLocationPolicy.maximumLocationAge {
            publishUnavailable(status: .accuracyInsufficient(latest.horizontalAccuracy))
        } else {
            publishUnavailable(status: .locating)
        }
    }

    func reliableLocationSnapshot(at now: Date = Date()) -> GPSLocationSnapshot? {
        guard manager.accuracyAuthorization == .fullAccuracy,
              let location = selectBestStoredLocation(at: now)
        else {
            return nil
        }

        return GPSLocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.gps.error("GPS error: \(error.localizedDescription)")
        if let locationError = error as? CLError, locationError.code == .locationUnknown {
            if reliableLocationSnapshot() == nil {
                publishUnavailable(status: .locating)
            }
            return
        }
        clearAcceptedLocations()
        publishUnavailable(status: .unavailable)
    }

    private func storeAndSelectBest(_ locations: [CLLocation], at now: Date) -> CLLocation? {
        sampleLock.lock()
        defer { sampleLock.unlock() }

        acceptedLocations.append(contentsOf: locations)
        acceptedLocations = Array(
            acceptedLocations
                .filter { GPSLocationPolicy.isAcceptable($0, at: now) }
                .suffix(GPSLocationPolicy.maximumSampleCount)
        )
        return GPSLocationPolicy.bestLocation(from: acceptedLocations, at: now)
    }

    private func selectBestStoredLocation(at now: Date) -> CLLocation? {
        sampleLock.lock()
        defer { sampleLock.unlock() }

        acceptedLocations = Array(
            acceptedLocations
                .filter { GPSLocationPolicy.isAcceptable($0, at: now) }
                .suffix(GPSLocationPolicy.maximumSampleCount)
        )
        return GPSLocationPolicy.bestLocation(from: acceptedLocations, at: now)
    }

    private func clearAcceptedLocations() {
        sampleLock.lock()
        acceptedLocations.removeAll(keepingCapacity: true)
        sampleLock.unlock()
    }

    private func publish(_ location: CLLocation) {
        onMain { [weak self] in
            guard let self else { return }
            self.latitude = location.coordinate.latitude
            self.longitude = location.coordinate.longitude
            self.horizontalAccuracy = location.horizontalAccuracy
            self.status = .ready(location.horizontalAccuracy)
        }
    }

    private func publishUnavailable(status: GPSRecorderStatus) {
        onMain { [weak self] in
            guard let self else { return }
            self.latitude = 0
            self.longitude = 0
            self.horizontalAccuracy = nil
            self.status = status
        }
    }

    private func onMain(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }
}

// GPSRecorder.swift
// GPS 坐标采集（写入 PLY header）

import CoreLocation
import Combine

struct GPSLocationSnapshot: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: CLLocationAccuracy
    let timestamp: Date
}

enum GPSLocationPolicy {
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 8
    static let maximumLocationAge: TimeInterval = 12
    static let maximumFutureTimestampSkew: TimeInterval = 1
    static let maximumStoredSampleCount = 12

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

    static func snapshot(from location: CLLocation?, at now: Date) -> GPSLocationSnapshot? {
        guard let location, isAcceptable(location, at: now) else { return nil }
        return GPSLocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
    }
}

final class GPSRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let sampleLock = NSLock()
    private var acceptedLocations: [CLLocation] = []

    @Published private(set) var latitude: Double = 0
    @Published private(set) var longitude: Double = 0
    @Published private(set) var horizontalAccuracy: CLLocationAccuracy?
    @Published private(set) var isAvailable = false

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
        case .denied, .restricted:
            manager.stopUpdatingLocation()
            clearAcceptedLocations()
            publishUnavailable()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        @unknown default:
            clearAcceptedLocations()
            publishUnavailable()
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard manager.accuracyAuthorization == .fullAccuracy else {
            clearAcceptedLocations()
            publishUnavailable()
            return
        }

        let now = Date()
        guard let location = storeAndSelectBest(locations, at: now) else {
            publishUnavailable()
            return
        }
        publish(location)
    }

    func reliableLocationSnapshot(at now: Date = Date()) -> GPSLocationSnapshot? {
        guard manager.accuracyAuthorization == .fullAccuracy else { return nil }
        sampleLock.lock()
        defer { sampleLock.unlock() }

        acceptedLocations = Array(
            acceptedLocations
                .filter { GPSLocationPolicy.isAcceptable($0, at: now) }
                .suffix(GPSLocationPolicy.maximumStoredSampleCount)
        )
        return GPSLocationPolicy.snapshot(
            from: GPSLocationPolicy.bestLocation(from: acceptedLocations, at: now),
            at: now
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.gps.error("GPS error: \(error.localizedDescription)")
        if let locationError = error as? CLError,
           locationError.code == .locationUnknown,
           reliableLocationSnapshot() != nil {
            return
        }
        clearAcceptedLocations()
        publishUnavailable()
    }

    private func storeAndSelectBest(_ locations: [CLLocation], at now: Date) -> CLLocation? {
        sampleLock.lock()
        defer { sampleLock.unlock() }

        acceptedLocations.append(
            contentsOf: locations.filter { GPSLocationPolicy.isAcceptable($0, at: now) }
        )
        acceptedLocations = Array(
            acceptedLocations
                .filter { GPSLocationPolicy.isAcceptable($0, at: now) }
                .suffix(GPSLocationPolicy.maximumStoredSampleCount)
        )
        return GPSLocationPolicy.bestLocation(from: acceptedLocations, at: now)
    }

    private func clearAcceptedLocations() {
        sampleLock.lock()
        acceptedLocations.removeAll(keepingCapacity: true)
        sampleLock.unlock()
    }

    private func publish(_ location: CLLocation) {
        publishOnMain { [weak self] in
            guard let self else { return }
            self.latitude = location.coordinate.latitude
            self.longitude = location.coordinate.longitude
            self.horizontalAccuracy = location.horizontalAccuracy
            self.isAvailable = true
        }
    }

    private func publishUnavailable() {
        publishOnMain { [weak self] in
            guard let self else { return }
            self.latitude = 0
            self.longitude = 0
            self.horizontalAccuracy = nil
            self.isAvailable = false
        }
    }

    private func publishOnMain(_ operation: @escaping () -> Void) {
        if Thread.isMainThread {
            operation()
        } else {
            DispatchQueue.main.async(execute: operation)
        }
    }
}

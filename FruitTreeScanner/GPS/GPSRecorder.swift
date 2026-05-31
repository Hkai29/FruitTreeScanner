// GPSRecorder.swift
// GPS 坐标采集（写入 PLY header）

import CoreLocation
import Combine

class GPSRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastPublishedLocation: CLLocation?
    private var lastPublishTime = Date.distantPast
    private let minimumPublishInterval: TimeInterval = 2.0
    private let minimumPublishDistance: CLLocationDistance = 3.0

    @Published var latitude: Double = 0.0
    @Published var longitude: Double = 0.0
    @Published var isAvailable: Bool = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = minimumPublishDistance
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            DispatchQueue.main.async { self.isAvailable = false }
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let now = Date()
        if let lastPublishedLocation {
            let movedEnough = loc.distance(from: lastPublishedLocation) >= minimumPublishDistance
            let waitedEnough = now.timeIntervalSince(lastPublishTime) >= minimumPublishInterval
            guard movedEnough || waitedEnough || !isAvailable else { return }
        }

        lastPublishedLocation = loc
        lastPublishTime = now
        DispatchQueue.main.async {
            self.latitude = loc.coordinate.latitude
            self.longitude = loc.coordinate.longitude
            if !self.isAvailable {
                self.isAvailable = true
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("GPS error: \(error.localizedDescription)")
        #endif
        DispatchQueue.main.async { self.isAvailable = false }
    }
}

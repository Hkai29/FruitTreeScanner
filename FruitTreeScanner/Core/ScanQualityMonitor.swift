// ScanQualityMonitor.swift
// 扫描质量监控系统

import Foundation
import ARKit
import SwiftUI

struct ScanQualitySample {
    let pointDensity: Float
    let trackingState: ARCamera.TrackingState
    let scanAngle: Float
    let ambientIntensity: CGFloat?
}

struct ScanQualitySnapshot {
    var pointDensity: Float = 0
    var lightLevel: ScanQualityMonitor.LightLevel = .normal
    var scanAngle: Float = 0
    var trackingState: ARCamera.TrackingState = .notAvailable
    var qualityScore: Float = 0

    fileprivate func isEffectivelyEqual(to other: ScanQualitySnapshot) -> Bool {
        abs(pointDensity - other.pointDensity) < 0.001 &&
        lightLevel == other.lightLevel &&
        abs(scanAngle - other.scanAngle) < 0.001 &&
        String(describing: trackingState) == String(describing: other.trackingState) &&
        abs(qualityScore - other.qualityScore) < 0.001
    }
}

class ScanQualityMonitor: ObservableObject {
    @Published private(set) var snapshot = ScanQualitySnapshot()

    private var lastUpdateTime: TimeInterval = 0
    private let minimumUpdateInterval: TimeInterval = 0.25
    
    enum LightLevel: Equatable {
        case tooDark
        case dark
        case normal
        case bright
        case tooBright
        
        var description: String {
            switch self {
            case .tooDark: return "过暗"
            case .dark: return "偏暗"
            case .normal: return "正常"
            case .bright: return "偏亮"
            case .tooBright: return "过曝"
            }
        }
        
        var color: Color {
            switch self {
            case .tooDark, .tooBright: return .red
            case .dark, .bright: return .orange
            case .normal: return .green
            }
        }
    }
    
    func update(with sample: ScanQualitySample) {
        let now = CACurrentMediaTime()
        guard now - lastUpdateTime >= minimumUpdateInterval else { return }
        lastUpdateTime = now

        var next = snapshot
        if let ambientIntensity = sample.ambientIntensity {
            let nextLightLevel = Self.lightLevel(for: ambientIntensity)
            if next.lightLevel != nextLightLevel {
                next.lightLevel = nextLightLevel
            }
        }
        if abs(next.pointDensity - sample.pointDensity) >= 5 {
            next.pointDensity = sample.pointDensity
        }
        if String(describing: next.trackingState) != String(describing: sample.trackingState) {
            next.trackingState = sample.trackingState
        }
        if abs(next.scanAngle - sample.scanAngle) >= 1 {
            next.scanAngle = sample.scanAngle
        }

        let nextQualityScore = Self.makeQualityScore(
            pointDensity: next.pointDensity,
            lightLevel: next.lightLevel,
            scanAngle: next.scanAngle,
            trackingState: next.trackingState
        )
        if abs(next.qualityScore - nextQualityScore) >= 1 {
            next.qualityScore = nextQualityScore
        }

        if !snapshot.isEffectivelyEqual(to: next) {
            snapshot = next
        }
    }

    private static func lightLevel(for ambientIntensity: CGFloat) -> LightLevel {
        switch ambientIntensity {
        case ..<120: return .tooDark
        case 120..<450: return .dark
        case 450..<1_600: return .normal
        case 1_600..<2_800: return .bright
        default: return .tooBright
        }
    }
    
    func calculateOverallQuality() -> Float {
        snapshot.qualityScore
    }

    var pointDensity: Float { snapshot.pointDensity }
    var lightLevel: LightLevel { snapshot.lightLevel }
    var scanAngle: Float { snapshot.scanAngle }
    var trackingState: ARCamera.TrackingState { snapshot.trackingState }
    var qualityScore: Float { snapshot.qualityScore }

    private static func makeQualityScore(
        pointDensity: Float,
        lightLevel: LightLevel,
        scanAngle: Float,
        trackingState: ARCamera.TrackingState
    ) -> Float {
        var score: Float = 0
        
        let densityScore = min(pointDensity / 500, 1.0) * 30
        score += densityScore
        
        let lightScore: Float = {
            switch lightLevel {
            case .normal: return 25
            case .dark, .bright: return 15
            case .tooDark, .tooBright: return 5
            }
        }()
        score += lightScore
        
        let angleScore: Float = scanAngle < 60.0 ? 20.0 : (scanAngle < 80.0 ? 10.0 : 5.0)
        score += angleScore
        
        let trackingScore: Float = {
            switch trackingState {
            case .normal: return 25
            case .limited(_): return 10
            case .notAvailable: return 0
            @unknown default: return 10
            }
        }()
        score += trackingScore
        
        return score
    }
    
    func getQualityStatus() -> String {
        let score = snapshot.qualityScore
        switch score {
        case 0..<30: return "差"
        case 30..<50: return "一般"
        case 50..<70: return "良好"
        case 70..<90: return "优秀"
        default: return "极佳"
        }
    }
}

extension CVPixelBuffer {
    func toUIImage() -> UIImage? {
        let ciImage = CIImage(cvImageBuffer: self)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

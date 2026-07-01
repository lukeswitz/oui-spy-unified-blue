//
//  OuiSpyLiveActivityAttributes.swift
//  Shared between Runner and OuiSpyLiveActivity targets
//
//  Created by Luke on 5/13/26.
//

import ActivityKit
import Foundation

struct OuiSpyLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var mode: EngineMode
        var uniqueCount: Int
        var flockCount: Int
        var droneCount: Int
        var detectorHits: Int
        var distanceKm: Double
        var speedKmh: Double
        var targetMac: String
        var rssi: Int
        var intervalMs: Int
        var robotType: String
        var exploitStatus: String
        var isImperial: Bool = false
        var activeLabel: String = ""

        /// Title text: prefer the app-supplied multi-engine label (e.g.
        /// "WiGLE+Flock+Drone") so every active radio path shows; fall back to
        /// the single-mode label for older payloads.
        var displayLabel: String {
            activeLabel.isEmpty ? mode.label : activeLabel.uppercased()
        }

        var distanceDisplay: String {
            if isImperial {
                let mi = distanceKm * 0.621371
                return String(format: "%.1fmi", mi)
            }
            return String(format: "%.1fkm", distanceKm)
        }

        var distanceValueOnly: String {
            if isImperial {
                return String(format: "%.1f", distanceKm * 0.621371)
            }
            return String(format: "%.1f", distanceKm)
        }

        var distanceUnitLabel: String { isImperial ? "mi" : "km" }

        var speedDisplay: String {
            if isImperial {
                return String(format: "%.0f", speedKmh * 0.621371)
            }
            return String(format: "%.0f", speedKmh)
        }

        init(
            mode: EngineMode,
            uniqueCount: Int,
            flockCount: Int,
            droneCount: Int,
            detectorHits: Int,
            distanceKm: Double,
            speedKmh: Double,
            targetMac: String,
            rssi: Int,
            intervalMs: Int,
            robotType: String,
            exploitStatus: String,
            isImperial: Bool = false,
            activeLabel: String = ""
        ) {
            self.mode = mode
            self.uniqueCount = uniqueCount
            self.flockCount = flockCount
            self.droneCount = droneCount
            self.detectorHits = detectorHits
            self.distanceKm = distanceKm
            self.speedKmh = speedKmh
            self.targetMac = targetMac
            self.rssi = rssi
            self.intervalMs = intervalMs
            self.robotType = robotType
            self.exploitStatus = exploitStatus
            self.isImperial = isImperial
            self.activeLabel = activeLabel
        }

        // Backward-compatible decoder: tolerate ContentState payloads written
        // before `isImperial` was added (resumed Activities after app upgrade).
        private enum CodingKeys: String, CodingKey {
            case mode, uniqueCount, flockCount, droneCount, detectorHits,
                 distanceKm, speedKmh, targetMac, rssi, intervalMs,
                 robotType, exploitStatus, isImperial, activeLabel
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mode = try c.decode(EngineMode.self, forKey: .mode)
            uniqueCount = try c.decode(Int.self, forKey: .uniqueCount)
            flockCount = try c.decode(Int.self, forKey: .flockCount)
            droneCount = try c.decode(Int.self, forKey: .droneCount)
            detectorHits = try c.decode(Int.self, forKey: .detectorHits)
            distanceKm = try c.decode(Double.self, forKey: .distanceKm)
            speedKmh = try c.decode(Double.self, forKey: .speedKmh)
            targetMac = try c.decode(String.self, forKey: .targetMac)
            rssi = try c.decode(Int.self, forKey: .rssi)
            intervalMs = try c.decode(Int.self, forKey: .intervalMs)
            robotType = try c.decode(String.self, forKey: .robotType)
            exploitStatus = try c.decode(String.self, forKey: .exploitStatus)
            isImperial = try c.decodeIfPresent(Bool.self, forKey: .isImperial) ?? false
            activeLabel = try c.decodeIfPresent(String.self, forKey: .activeLabel) ?? ""
        }
    }

    enum EngineMode: String, Codable, Hashable {
        case detector
        case flockBle
        case flockWifi
        case flockDual
        case foxhunter
        case skySpy
        case uniPwn
        case wardrive
        case wardriveFlock

        var sfSymbol: String {
            switch self {
            case .detector:      return "sensor.tag.radiowaves.forward"
            case .flockBle:      return "video.fill"
            case .flockWifi:     return "video.badge.waveform.fill"
            case .flockDual:     return "video.badge.waveform.fill"
            case .foxhunter:     return "scope"
            case .skySpy:        return "airplane"
            case .uniPwn:        return "cpu"
            case .wardrive:      return "wifi"
            case .wardriveFlock: return "antenna.radiowaves.left.and.right"
            }
        }

        var label: String {
            switch self {
            case .detector:      return "DETECTOR"
            case .flockBle:      return "FLOCK BLE"
            case .flockWifi:     return "FLOCK WiFi"
            case .flockDual:     return "FLOCK WiFi+BLE"
            case .foxhunter:     return "FOXHUNT"
            case .skySpy:        return "SKY SPY"
            case .uniPwn:        return "UNIPWN"
            case .wardrive:      return "WARDRIVE"
            case .wardriveFlock: return "WIGLE+FLOCK"
            }
        }

        var color: (Double, Double, Double) {
            switch self {
            case .detector:      return (0.29, 0.62, 1.00)
            case .flockBle:      return (0.70, 0.29, 1.00)
            case .flockWifi:     return (1.00, 0.29, 0.54)
            case .flockDual:     return (0.85, 0.29, 0.77)
            case .foxhunter:     return (0.29, 1.00, 0.54)
            case .skySpy:        return (0.29, 1.00, 0.92)
            case .uniPwn:        return (1.00, 0.29, 0.29)
            case .wardrive:      return (1.00, 0.55, 0.29)
            case .wardriveFlock: return (1.00, 0.42, 0.62)
            }
        }
    }
}

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
        var wifiCount: Int = 0
        var bleCount: Int = 0
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
        var lastAlert: String = ""
        var lastAlertDetail: String = ""
        var lastAlertAt: Double = 0
        var alertKinds: [String: Int] = [:]

        var sortedAlertKinds: [(key: String, value: Int)] {
            alertKinds.filter { $0.value > 0 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        }

        static func alertKindSymbol(_ kind: String) -> String {
            switch kind {
            case "flock":          return "video.badge.waveform.fill"
            case "detector":       return "sensor.tag.radiowaves.forward"
            case "foxhunt":        return "scope"
            case "drone":          return "airplane"
            case "finder":         return "tag.fill"
            case "beacon":         return "dot.radiowaves.right"
            case "signage":        return "display"
            case "wearable":       return "applewatch"
            case "surveillance":   return "eye.fill"
            case "hacking":        return "terminal.fill"
            case "lawEnforcement": return "shield.fill"
            case "vehicle":        return "car.fill"
            case "glasses":        return "eyeglasses"
            case "audio":          return "headphones"
            case "camera":         return "video.fill"
            case "thermostat":     return "thermometer.medium"
            case "lock":           return "lock.fill"
            case "health":         return "heart.fill"
            case "home":           return "house.fill"
            case "isp":            return "wifi.router.fill"
            case "mesh":           return "point.3.connected.trianglepath.dotted"
            case "phone":          return "iphone"
            default:               return "exclamationmark.triangle.fill"
            }
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
            wifiCount: Int = 0,
            bleCount: Int = 0,
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
            lastAlert: String = "",
            lastAlertDetail: String = "",
            lastAlertAt: Double = 0,
            alertKinds: [String: Int] = [:]
        ) {
            self.mode = mode
            self.uniqueCount = uniqueCount
            self.wifiCount = wifiCount
            self.bleCount = bleCount
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
            self.lastAlert = lastAlert
            self.lastAlertDetail = lastAlertDetail
            self.lastAlertAt = lastAlertAt
            self.alertKinds = alertKinds
        }

        // Backward-compatible decoder: tolerate ContentState payloads written
        // before `isImperial` was added (resumed Activities after app upgrade).
        private enum CodingKeys: String, CodingKey {
            case mode, uniqueCount, wifiCount, bleCount, flockCount, droneCount,
                 detectorHits, distanceKm, speedKmh, targetMac, rssi, intervalMs,
                 robotType, exploitStatus, isImperial,
                 lastAlert, lastAlertDetail, lastAlertAt, alertKinds
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            mode = try c.decode(EngineMode.self, forKey: .mode)
            uniqueCount = try c.decode(Int.self, forKey: .uniqueCount)
            wifiCount = try c.decodeIfPresent(Int.self, forKey: .wifiCount) ?? 0
            bleCount = try c.decodeIfPresent(Int.self, forKey: .bleCount) ?? 0
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
            lastAlert = try c.decodeIfPresent(String.self, forKey: .lastAlert) ?? ""
            lastAlertDetail = try c.decodeIfPresent(String.self, forKey: .lastAlertDetail) ?? ""
            lastAlertAt = try c.decodeIfPresent(Double.self, forKey: .lastAlertAt) ?? 0
            alertKinds = try c.decodeIfPresent([String: Int].self, forKey: .alertKinds) ?? [:]
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

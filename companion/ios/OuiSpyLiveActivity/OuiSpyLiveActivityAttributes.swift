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
    }

    enum EngineMode: String, Codable, Hashable {
        case detector
        case flockBle
        case flockWifi
        case foxhunter
        case skySpy
        case uniPwn
        case wardrive

        var sfSymbol: String {
            switch self {
            case .detector:  return "sensor.tag.radiowaves.forward"
            case .flockBle:  return "video.fill"
            case .flockWifi: return "video.badge.waveform.fill"
            case .foxhunter: return "scope"
            case .skySpy:    return "airplane"
            case .uniPwn:    return "cpu"
            case .wardrive:  return "wifi"
            }
        }

        var label: String {
            switch self {
            case .detector:  return "DETECTOR"
            case .flockBle:  return "FLOCK BLE"
            case .flockWifi: return "FLOCK WiFi"
            case .foxhunter: return "FOXHUNT"
            case .skySpy:    return "SKY SPY"
            case .uniPwn:    return "UNIPWN"
            case .wardrive:  return "WARDRIVE"
            }
        }

        var color: (Double, Double, Double) {
            switch self {
            case .detector:  return (0.29, 0.62, 1.00)
            case .flockBle:  return (0.70, 0.29, 1.00)
            case .flockWifi: return (1.00, 0.29, 0.54)
            case .foxhunter: return (0.29, 1.00, 0.54)
            case .skySpy:    return (0.29, 1.00, 0.92)
            case .uniPwn:    return (1.00, 0.29, 0.29)
            case .wardrive:  return (1.00, 0.55, 0.29)
            }
        }
    }
}

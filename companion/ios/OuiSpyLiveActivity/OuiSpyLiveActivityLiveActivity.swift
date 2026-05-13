//
//  OuiSpyLiveActivityLiveActivity.swift
//  OuiSpyLiveActivity
//
//  Created by Luke on 5/13/26.
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget

struct OuiSpyLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OuiSpyLiveActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding(12)
                .activityBackgroundTint(Color(red: 0.031, green: 0.035, blue: 0.055))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeading(state: context.state)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: context.state)
                }
            } compactLeading: {
                CompactLeading(state: context.state)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                MinimalView(state: context.state)
            }
            .keylineTint(engineColor(context.state.mode))
        }
    }
}

// MARK: - Engine Color Helper

private func engineColor(_ mode: OuiSpyLiveActivityAttributes.EngineMode) -> Color {
    let c = mode.color
    return Color(red: c.0, green: c.1, blue: c.2)
}

// MARK: - Compact Views

private struct CompactLeading: View {
    let state: OuiSpyLiveActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.mode.sfSymbol)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(engineColor(state.mode))
    }
}

private struct CompactTrailing: View {
    let state: OuiSpyLiveActivityAttributes.ContentState

    var body: some View {
        switch state.mode {
        case .foxhunter:
            Text("\(state.rssi)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(rssiColor(state.rssi))
        case .uniPwn:
            Text(String(state.exploitStatus.prefix(3)).uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(engineColor(state.mode))
        default:
            Text("\(state.uniqueCount)")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
    }
}

private struct MinimalView: View {
    let state: OuiSpyLiveActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.mode.sfSymbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(engineColor(state.mode))
    }
}

// MARK: - Expanded Views

private struct ExpandedLeading: View {
    let state: OuiSpyLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: state.mode.sfSymbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(engineColor(state.mode))
            Text(state.mode.label)
                .font(.system(size: 8, weight: .heavy))
                .foregroundColor(.gray)
                .tracking(2)
        }
    }
}

private struct ExpandedTrailing: View {
    let state: OuiSpyLiveActivityAttributes.ContentState

    var body: some View {
        switch state.mode {
        case .foxhunter:
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(state.rssi)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(rssiColor(state.rssi))
                Text("dBm")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.gray)
                    .tracking(1)
            }
        case .uniPwn:
            VStack(alignment: .trailing, spacing: 2) {
                Text(state.exploitStatus.uppercased())
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(engineColor(state.mode))
                Text(state.robotType)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)
            }
        default:
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(state.uniqueCount)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Text("UNIQUE")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundColor(.gray)
                    .tracking(1)
            }
        }
    }
}

private struct ExpandedCenter: View {
    let state: OuiSpyLiveActivityAttributes.ContentState

    var body: some View {
        switch state.mode {
        case .foxhunter:
            Text(formatMac(state.targetMac))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.7))
        default:
            EmptyView()
        }
    }
}

private struct ExpandedBottom: View {
    let state: OuiSpyLiveActivityAttributes.ContentState

    var body: some View {
        switch state.mode {
        case .wardrive:
            HStack(spacing: 12) {
                StatPill(icon: "wifi", value: "\(state.uniqueCount)", color: engineColor(.wardrive))
                if state.flockCount > 0 {
                    StatPill(icon: "video.fill", value: "\(state.flockCount)", color: engineColor(.flockBle))
                }
                if state.droneCount > 0 {
                    StatPill(icon: "airplane", value: "\(state.droneCount)", color: engineColor(.skySpy))
                }
                if state.detectorHits > 0 {
                    StatPill(icon: "sensor.tag.radiowaves.forward", value: "\(state.detectorHits)", color: engineColor(.detector))
                }
                StatPill(icon: "road.lanes", value: String(format: "%.1fkm", state.distanceKm), color: .gray)
                if state.speedKmh > 0 {
                    StatPill(icon: "speedometer", value: String(format: "%.0f", state.speedKmh), color: .gray)
                }
            }
        case .flockBle, .flockWifi:
            HStack(spacing: 12) {
                StatPill(icon: "video.fill", value: "\(state.flockCount)", color: engineColor(state.mode))
                StatPill(icon: "wifi", value: "\(state.uniqueCount)", color: .gray)
                StatPill(icon: "road.lanes", value: String(format: "%.1fkm", state.distanceKm), color: .gray)
            }
        case .detector:
            HStack(spacing: 12) {
                StatPill(icon: "sensor.tag.radiowaves.forward", value: "\(state.detectorHits)", color: engineColor(.detector))
                StatPill(icon: "wifi", value: "\(state.uniqueCount)", color: .gray)
            }
        case .skySpy:
            HStack(spacing: 12) {
                StatPill(icon: "airplane", value: "\(state.droneCount)", color: engineColor(.skySpy))
                StatPill(icon: "wifi", value: "\(state.uniqueCount)", color: .gray)
            }
        case .foxhunter:
            RssiBar(rssi: state.rssi)
        case .uniPwn:
            HStack(spacing: 12) {
                StatPill(icon: "cpu", value: state.robotType, color: engineColor(.uniPwn))
                Text(state.exploitStatus)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(engineColor(.uniPwn))
            }
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let state: OuiSpyLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.mode.sfSymbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(engineColor(state.mode))

            VStack(alignment: .leading, spacing: 2) {
                Text("OUI-SPY \(state.mode.label)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(lockScreenSubtitle(state))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            lockScreenTrailing(state)
        }
    }

    @ViewBuilder
    private func lockScreenTrailing(_ s: OuiSpyLiveActivityAttributes.ContentState) -> some View {
        switch s.mode {
        case .foxhunter:
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(s.rssi)")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(rssiColor(s.rssi))
                Text("dBm")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.gray)
            }
        case .uniPwn:
            Text(s.exploitStatus.uppercased())
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(engineColor(s.mode))
        default:
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(s.uniqueCount)")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                lockScreenBadges(s)
            }
        }
    }

    @ViewBuilder
    private func lockScreenBadges(_ s: OuiSpyLiveActivityAttributes.ContentState) -> some View {
        HStack(spacing: 6) {
            if s.flockCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "video.fill").font(.system(size: 8))
                    Text("\(s.flockCount)").font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundColor(engineColor(.flockBle))
            }
            if s.droneCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "airplane").font(.system(size: 8))
                    Text("\(s.droneCount)").font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundColor(engineColor(.skySpy))
            }
            if s.detectorHits > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "sensor.tag.radiowaves.forward").font(.system(size: 8))
                    Text("\(s.detectorHits)").font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundColor(engineColor(.detector))
            }
        }
    }

    private func lockScreenSubtitle(_ s: OuiSpyLiveActivityAttributes.ContentState) -> String {
        switch s.mode {
        case .foxhunter: return formatMac(s.targetMac)
        case .uniPwn:    return s.robotType
        case .wardrive:  return "\(s.uniqueCount) unique \u{00b7} \(String(format: "%.1f", s.distanceKm))km"
        case .flockBle, .flockWifi: return "\(s.flockCount) cameras \u{00b7} \(s.uniqueCount) total"
        case .detector:  return "\(s.detectorHits) watchlist hits"
        case .skySpy:    return "\(s.droneCount) drones detected"
        }
    }
}

// MARK: - Shared Components

private struct StatPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .foregroundColor(color)
    }
}

private struct RssiBar: View {
    let rssi: Int

    var body: some View {
        let normalized = min(max(Double(rssi + 100) / 70.0, 0), 1)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.3))
                RoundedRectangle(cornerRadius: 3)
                    .fill(rssiColor(rssi))
                    .frame(width: geo.size.width * normalized)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Utility

private func rssiColor(_ rssi: Int) -> Color {
    if rssi > -50 { return Color(red: 0.35, green: 0.90, blue: 0.63) }
    if rssi > -65 { return Color(red: 0.90, green: 0.66, blue: 0.35) }
    return Color(red: 0.90, green: 0.35, blue: 0.42)
}

private func formatMac(_ mac: String) -> String {
    if mac.count >= 8 {
        return String(mac.prefix(8)).uppercased()
    }
    return mac.uppercased()
}

// MARK: - Previews

extension OuiSpyLiveActivityAttributes {
    fileprivate static var preview: OuiSpyLiveActivityAttributes {
        OuiSpyLiveActivityAttributes()
    }
}

extension OuiSpyLiveActivityAttributes.ContentState {
    fileprivate static var wardriveSample: OuiSpyLiveActivityAttributes.ContentState {
        OuiSpyLiveActivityAttributes.ContentState(
            mode: .wardrive,
            uniqueCount: 1247,
            flockCount: 3,
            droneCount: 1,
            detectorHits: 0,
            distanceKm: 4.2,
            speedKmh: 35,
            targetMac: "",
            rssi: -100,
            intervalMs: 0,
            robotType: "",
            exploitStatus: ""
        )
    }

    fileprivate static var foxhuntSample: OuiSpyLiveActivityAttributes.ContentState {
        OuiSpyLiveActivityAttributes.ContentState(
            mode: .foxhunter,
            uniqueCount: 42,
            flockCount: 0,
            droneCount: 0,
            detectorHits: 0,
            distanceKm: 0,
            speedKmh: 0,
            targetMac: "70:c9:4e:aa:bb:cc",
            rssi: -58,
            intervalMs: 1200,
            robotType: "",
            exploitStatus: ""
        )
    }
}

#Preview("Notification", as: .content, using: OuiSpyLiveActivityAttributes.preview) {
    OuiSpyLiveActivityLiveActivity()
} contentStates: {
    OuiSpyLiveActivityAttributes.ContentState.wardriveSample
    OuiSpyLiveActivityAttributes.ContentState.foxhuntSample
}

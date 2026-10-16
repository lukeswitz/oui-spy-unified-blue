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
            ActivityContentView(state: context.state)
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
                    VStack(alignment: .leading, spacing: 6) {
                        ExpandedBottom(state: context.state)
                        AlertKindsRow(state: context.state, iconSize: 10, textSize: 11)
                        AlertRow(state: context.state)
                    }
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
        .supplementalActivityFamilies([.small])
    }
}

private struct ActivityContentView: View {
    let state: OuiSpyLiveActivityAttributes.ContentState
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            SmallView(state: state)
                .padding(8)
        default:
            VStack(alignment: .leading, spacing: 8) {
                LockScreenView(state: state)
                AlertKindsRow(state: state, iconSize: 11, textSize: 12)
                AlertRow(state: state)
            }
            .padding(12)
        }
    }
}

private struct SmallView: View {
    let state: OuiSpyLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: state.mode.sfSymbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(engineColor(state.mode))
                Text("\(state.uniqueCount)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
            AlertKindsRow(state: state, iconSize: 12, textSize: 13)
            if !state.lastAlert.isEmpty {
                Text(state.lastAlert)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

private struct AlertKindsRow: View {
    let state: OuiSpyLiveActivityAttributes.ContentState
    let iconSize: CGFloat
    let textSize: CGFloat

    var body: some View {
        let kinds = state.sortedAlertKinds
        if !kinds.isEmpty {
            HStack(spacing: 10) {
                ForEach(kinds.prefix(5), id: \.key) { k in
                    HStack(spacing: 3) {
                        Image(systemName: OuiSpyLiveActivityAttributes.ContentState.alertKindSymbol(k.key))
                            .font(.system(size: iconSize, weight: .bold))
                        Text("\(k.value)")
                            .font(.system(size: textSize, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.orange)
                }
            }
            .lineLimit(1)
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
        switch state.mode {
        case .foxhunter:
            Text("\(state.rssi)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(rssiColor(state.rssi))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        case .uniPwn:
            Image(systemName: state.mode.sfSymbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(engineColor(state.mode))
        default:
            Text("\(state.uniqueCount)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(engineColor(state.mode))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
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
        case .wardrive, .wardriveFlock:
            HStack(spacing: 12) {
                StatPill(icon: "wifi", value: "\(state.uniqueCount)", color: engineColor(.wardrive))
                if state.flockCount > 0 || state.mode == .wardriveFlock {
                    StatPill(icon: "video.fill", value: "\(state.flockCount)", color: engineColor(.flockBle))
                }
                if state.droneCount > 0 {
                    StatPill(icon: "airplane", value: "\(state.droneCount)", color: engineColor(.skySpy))
                }
                if state.detectorHits > 0 {
                    StatPill(icon: "sensor.tag.radiowaves.forward", value: "\(state.detectorHits)", color: engineColor(.detector))
                }
                StatPill(icon: "road.lanes", value: state.distanceDisplay, color: .gray)
                if state.speedKmh > 0 {
                    StatPill(icon: "speedometer", value: state.speedDisplay, color: .gray)
                }
            }
        case .flockBle, .flockWifi, .flockDual:
            HStack(spacing: 12) {
                StatPill(icon: "video.fill", value: "\(state.flockCount)", color: engineColor(state.mode))
                if state.mode == .flockDual {
                    StatPill(icon: "wifi", value: "BLE", color: engineColor(.flockBle))
                    StatPill(icon: "antenna.radiowaves.left.and.right", value: "WiFi", color: engineColor(.flockWifi))
                }
                StatPill(icon: "number", value: "\(state.uniqueCount)", color: .gray)
                StatPill(icon: "road.lanes", value: state.distanceDisplay, color: .gray)
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

private struct AlertRow: View {
    let state: OuiSpyLiveActivityAttributes.ContentState

    var body: some View {
        if !state.lastAlert.isEmpty {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(state.lastAlert)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        if state.lastAlertAt > 0 {
                            Text(Date(timeIntervalSince1970: state.lastAlertAt), style: .relative)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 70, alignment: .trailing)
                        }
                    }
                    if !state.lastAlertDetail.isEmpty {
                        Text(state.lastAlertDetail)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.65))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
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
                Text(lockScreenSubtitle(state))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)
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
        case .wardrive, .wardriveFlock:
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        Image(systemName: "wifi").font(.system(size: 12))
                        Text("\(s.wifiCount)")
                            .font(.system(size: 19, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(engineColor(.wardrive))
                    HStack(spacing: 3) {
                        Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 12))
                        Text("\(s.bleCount)")
                            .font(.system(size: 19, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(engineColor(.flockBle))
                }
                lockScreenBadges(s)
            }
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
        default:
            // Aggregate every active engine's count so the subtitle reflects
            // all running radios, not just the primary mode.
            var parts: [String] = []
            if s.mode != .wardrive && s.mode != .wardriveFlock && s.uniqueCount > 0 {
                parts.append("\(s.uniqueCount) unique")
            }
            if s.flockCount > 0 { parts.append("\(s.flockCount) cameras") }
            if s.droneCount > 0 { parts.append("\(s.droneCount) drones") }
            if s.detectorHits > 0 { parts.append("\(s.detectorHits) hits") }
            if s.distanceKm > 0 { parts.append("\(s.distanceValueOnly)\(s.distanceUnitLabel)") }
            return parts.isEmpty ? "Scanning" : parts.joined(separator: " \u{00b7} ")
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
            wifiCount: 892,
            bleCount: 355,
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

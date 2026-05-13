import ActivityKit
import Flutter
import Foundation

/// Handles the `tech.colonelpanic.ouispy/live_activity` method channel.
/// Bridges Flutter calls to ActivityKit for starting/updating/ending Live Activities.
@available(iOS 16.2, *)
class LiveActivityHandler {
    static let channelName = "tech.colonelpanic.ouispy/live_activity"

    private var currentActivity: Activity<OuiSpyLiveActivityAttributes>?

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { result(FlutterError(code: "DISPOSED", message: nil, details: nil)); return }

            switch call.method {
            case "isSupported":
                result(ActivityAuthorizationInfo().areActivitiesEnabled)

            case "startActivity":
                self.handleStart(call: call, result: result)

            case "updateActivity":
                self.handleUpdate(call: call, result: result)

            case "endActivity":
                self.handleEnd(call: call, result: result)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func handleStart(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary", details: nil))
            return
        }

        let state = contentState(from: args)
        let attributes = OuiSpyLiveActivityAttributes()

        do {
            let content = ActivityContent(state: state, staleDate: nil)
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            currentActivity = activity
            result(activity.id)
        } catch {
            result(FlutterError(code: "START_FAILED", message: error.localizedDescription, details: nil))
        }
    }

    private func handleUpdate(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Expected dictionary", details: nil))
            return
        }

        let state = contentState(from: args)
        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            await currentActivity?.update(content)
            result(nil)
        }
    }

    private func handleEnd(call: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            await currentActivity?.end(nil, dismissalPolicy: .immediate)
            currentActivity = nil
            result(nil)
        }
    }

    private func contentState(from args: [String: Any]) -> OuiSpyLiveActivityAttributes.ContentState {
        let modeStr = args["mode"] as? String ?? "wardrive"
        let mode = OuiSpyLiveActivityAttributes.EngineMode(rawValue: modeStr) ?? .wardrive

        return OuiSpyLiveActivityAttributes.ContentState(
            mode: mode,
            uniqueCount: args["uniqueCount"] as? Int ?? 0,
            flockCount: args["flockCount"] as? Int ?? 0,
            droneCount: args["droneCount"] as? Int ?? 0,
            detectorHits: args["detectorHits"] as? Int ?? 0,
            distanceKm: args["distanceKm"] as? Double ?? 0,
            speedKmh: args["speedKmh"] as? Double ?? 0,
            targetMac: args["targetMac"] as? String ?? "",
            rssi: args["rssi"] as? Int ?? -100,
            intervalMs: args["intervalMs"] as? Int ?? 0,
            robotType: args["robotType"] as? String ?? "",
            exploitStatus: args["exploitStatus"] as? String ?? ""
        )
    }
}

/// Fallback for iOS < 16.1 — all calls are no-ops.
class LiveActivityHandlerLegacy {
    static let channelName = "tech.colonelpanic.ouispy/live_activity"

    func register(with messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "isSupported":
                result(false)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
}

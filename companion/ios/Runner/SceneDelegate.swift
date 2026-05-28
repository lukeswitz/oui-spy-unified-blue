import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    override func sceneDidDisconnect(_ scene: UIScene) {
        if #available(iOS 16.2, *) {
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                await LiveActivityHandler.endAllActivitiesNow()
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 1.5)
        }
        super.sceneDidDisconnect(scene)
    }
}

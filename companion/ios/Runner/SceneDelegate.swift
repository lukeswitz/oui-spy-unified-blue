import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    override func sceneDidDisconnect(_ scene: UIScene) {
        if #available(iOS 16.2, *) {
            Task { await LiveActivityHandler.endAllActivitiesNow() }
        }
        super.sceneDidDisconnect(scene)
    }
}

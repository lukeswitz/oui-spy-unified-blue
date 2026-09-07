import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
    override func sceneDidDisconnect(_ scene: UIScene) {
        if #available(iOS 16.2, *) {
            LiveActivityHandler.endAllActivitiesBlocking()
        }
        super.sceneDidDisconnect(scene)
    }
}

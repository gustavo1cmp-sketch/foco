import Flutter
import UIKit
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)
        FocoPlugin.register(with: registrar(forPlugin: "FocoPlugin")!)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}

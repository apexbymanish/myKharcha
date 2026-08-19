import SwiftUI
import KharchaKit

@main
struct KharchaApp: App {
    @UIApplicationDelegateAdaptor(AppBootstrap.self) private var bootstrap

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

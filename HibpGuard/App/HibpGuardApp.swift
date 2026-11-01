import SwiftUI

@main
@MainActor
struct HibpGuardApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup { RootView(container: container) }
    }
}

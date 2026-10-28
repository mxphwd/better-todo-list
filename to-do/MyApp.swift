import Observation
import SwiftUI

@MainActor
@Observable
final class AppNavigationState {
    var isShowingAbout = false
}

@main
struct MyApp: App {
    @State private var appState = AppNavigationState()

    var body: some Scene {
        WindowGroup("Focus") {
            ContentView(appState: appState)
        }
        .defaultSize(width: 560, height: 520)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About to-do") {
                    appState.isShowingAbout = true
                }
            }
        }
    }
}

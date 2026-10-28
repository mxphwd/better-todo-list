import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup("Focus") {
            ContentView()
        }
        .defaultSize(width: 560, height: 520)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

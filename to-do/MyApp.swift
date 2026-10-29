import Observation
import SwiftUI

@MainActor
@Observable
final class AppNavigationState {
    var isShowingAbout = false
    var listNames: [String] = []
    var requestedListIndex = 0
    var listSelectionRevision = 0

    func selectList(at index: Int) {
        requestedListIndex = index
        listSelectionRevision += 1
    }
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

            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .textFormatting) {}
            CommandGroup(replacing: .help) {}

            CommandGroup(replacing: .sidebar) {}
            CommandGroup(replacing: .toolbar) {}

            CommandMenu("Lists") {
                ForEach(
                    Array(appState.listNames.prefix(9).enumerated()),
                    id: \.offset
                ) { index, name in
                    Button(name) {
                        appState.selectList(at: index)
                    }
                    .keyboardShortcut(
                        KeyEquivalent(Character(String(index + 1))),
                        modifiers: .control
                    )
                }
            }
        }
    }
}

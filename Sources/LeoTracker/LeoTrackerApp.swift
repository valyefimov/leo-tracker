import SwiftUI

@main
struct LeoTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().frame(minWidth: 860, minHeight: 620)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1050, height: 720)
        .commands { CommandGroup(replacing: .newItem) { } }
    }
}

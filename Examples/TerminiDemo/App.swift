import SwiftUI
import Termini

@main
struct TerminiDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 700)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}

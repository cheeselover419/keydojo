import SwiftUI

@main
struct KeyDojoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("KeyDojo").font(.largeTitle.bold())
            Text("VS Code and terminal without a mouse").foregroundStyle(.secondary)
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

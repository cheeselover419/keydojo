import SwiftUI

@main
struct KeyDojoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

enum Training: String {
    case terminal = "Terminal"
    case vscode = "VS Code"
}

struct ContentView: View {
    @State private var training: Training?

    var body: some View {
        Group {
            if let training {
                TrainingView(training: training) { self.training = nil }
            } else {
                StartView { training = $0 }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}

struct StartView: View {
    let choose: (Training) -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("KeyDojo").font(.largeTitle.bold())
                Text("Choose a training").foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                choice(.terminal, key: "t", icon: "terminal")
                choice(.vscode, key: "v", icon: "chevron.left.forwardslash.chevron.right")
            }
        }
        .padding()
    }

    private func choice(_ training: Training, key: Character, icon: String) -> some View {
        Button { choose(training) } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 32))
                Text(training.rawValue).font(.title3)
                Text(String(key).uppercased())
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary))
            }
            .frame(width: 160, height: 140)
        }
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
    }
}

struct TrainingView: View {
    let training: Training
    let back: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(training.rawValue).font(.largeTitle.bold())
            Button("Back (Esc)", action: back)
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }
}

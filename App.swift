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
    case terminal = "Терминал"
    case vscode = "VS Code"
}

enum Screen: Equatable {
    case start
    case lessons(Training)
    case exercise(Int)
}

struct ContentView: View {
    @State private var screen = Screen.start

    var body: some View {
        Group {
            switch screen {
            case .start:
                StartView { screen = .lessons($0) }
            case .lessons(.terminal):
                LessonListView(lessons: terminalLessons, open: { screen = .exercise($0) }, back: { screen = .start })
            case .lessons(.vscode):
                PlaceholderView(title: Training.vscode.rawValue) { screen = .start }
            case .exercise(let i):
                ExerciseView(lesson: terminalLessons[i]) { screen = .lessons(.terminal) }
            }
        }
        .frame(minWidth: 760, minHeight: 640)
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary))
    }
}

struct StartView: View {
    let choose: (Training) -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("KeyDojo").font(.largeTitle.bold())
                Text("Выбери тренировку").foregroundStyle(.secondary)
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
                KeyCap(text: String(key).uppercased())
            }
            .frame(width: 160, height: 140)
        }
        .keyboardShortcut(KeyEquivalent(key), modifiers: [])
    }
}

struct LessonListView: View {
    let lessons: [Lesson]
    let open: (Int) -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Training.terminal.rawValue).font(.largeTitle.bold())
            Text("Выбери тренировку цифрой").foregroundStyle(.secondary)
            ForEach(lessons.indices, id: \.self) { i in
                Button { open(i) } label: {
                    HStack(spacing: 14) {
                        KeyCap(text: "\(i + 1)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lessons[i].title).font(.headline)
                            Text(lessons[i].subtitle).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(lessons[i].exercises.count) упр.").foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
            }
            Spacer()
            Button("Назад (Esc)", action: back).keyboardShortcut(.cancelAction)
        }
        .padding(28)
    }
}

struct PlaceholderView: View {
    let title: String
    let back: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.largeTitle.bold())
            Text("Скоро").foregroundStyle(.secondary)
            Button("Назад (Esc)", action: back).keyboardShortcut(.cancelAction)
        }
        .padding()
    }
}

final class LessonRunner: ObservableObject {
    let lesson: Lesson
    @Published var index = 0
    @Published var term = Terminal()
    @Published var solved = false
    @Published var showHint = false
    @Published var finished = false

    init(_ lesson: Lesson) {
        self.lesson = lesson
        reset()
    }

    var exercise: Exercise { lesson.exercises[index] }

    func reset() {
        let t = Terminal()
        exercise.setup(t)
        t.resetChecks()
        term = t
        solved = false
        showHint = false
    }

    func next() {
        if index + 1 < lesson.exercises.count {
            index += 1
            reset()
        } else {
            finished = true
        }
    }

    // false: клавишу обрабатывает система (например ⌘Q)
    func handle(_ key: Key, back: () -> Void) -> Bool {
        let own = ["cmd+r", "cmd+/"].contains(key.name) || Terminal.cmdKeys.contains(key.name)
        if key.name.hasPrefix("cmd+") && !own { return false }
        if finished {
            if key.name == "enter" || key.name == "esc" { back() }
            return true
        }
        switch key.name {
        case "cmd+r": reset(); return true
        case "cmd+/": showHint.toggle(); return true
        default: break
        }
        if solved {
            if key.name == "enter" { next() } else if key.name == "esc" { back() }
            return true
        }
        if key.name == "esc", term.mode == .shell, term.search == nil {
            back()
            return true
        }
        term.handle(key)
        if exercise.check(term) { solved = true }
        return true
    }
}

struct ExerciseView: View {
    @StateObject private var runner: LessonRunner
    let back: () -> Void

    init(lesson: Lesson, back: @escaping () -> Void) {
        _runner = StateObject(wrappedValue: LessonRunner(lesson))
        self.back = back
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if runner.finished {
                Spacer()
                VStack(spacing: 8) {
                    Text("Тренировка «\(runner.lesson.title)» пройдена").font(.title.bold())
                    Text("Enter — к списку тренировок").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack {
                    Text(runner.lesson.title).font(.headline)
                    Spacer()
                    Text("\(runner.index + 1) / \(runner.lesson.exercises.count)").foregroundStyle(.secondary)
                }
                Text(LocalizedStringKey(runner.exercise.task))
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                if runner.showHint {
                    Text(LocalizedStringKey("Подсказка: " + runner.exercise.hint))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TerminalScreen(term: runner.term)
                if runner.solved {
                    Text("✓ Готово! Enter — следующее упражнение").bold().foregroundColor(.green)
                } else {
                    Text("⌘/ подсказка    ⌘R заново    Esc к списку").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(KeyCatcher { runner.handle($0, back: back) })
    }
}

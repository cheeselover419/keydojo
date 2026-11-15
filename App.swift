import SwiftUI

@main
struct KeyDojoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

enum Training {
    case terminal, vscode

    var title: String { self == .terminal ? tr("Терминал", "Terminal") : "VS Code" }
}

enum Screen: Equatable {
    case start
    case lessons(Training)
    case exercise(Int)
    case stats
}

struct ContentView: View {
    @State private var screen = Screen.start
    @AppStorage("lang") private var lang = Lang.ru

    var body: some View {
        Group {
            switch screen {
            case .start:
                StartView(choose: { screen = .lessons($0) }, stats: { screen = .stats })
            case .lessons(.terminal):
                LessonListView(lessons: terminalLessons, open: { screen = .exercise($0) }, back: { screen = .start })
            case .lessons(.vscode):
                PlaceholderView(title: Training.vscode.title) { screen = .start }
            case .exercise(let i):
                ExerciseView(lesson: terminalLessons[i]) { screen = .lessons(.terminal) }
            case .stats:
                StatsView(lessons: terminalLessons) { screen = .start }
            }
        }
        .id(lang)
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
    let stats: () -> Void
    @State private var settings = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("KeyDojo").font(.largeTitle.bold())
                Text(tr("Выбери тренировку", "Choose a training")).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                choice(.terminal, key: "t", icon: "terminal")
                choice(.vscode, key: "v", icon: "chevron.left.forwardslash.chevron.right")
            }
            Button(action: stats) {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                    Text(tr("Статистика", "Statistics"))
                    KeyCap(text: "S")
                }
            }
            .keyboardShortcut("s", modifiers: [])
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button { settings.toggle() } label: {
                Image(systemName: "gearshape").font(.title2)
            }
            .buttonStyle(.plain)
            .help(tr("Настройки (⌘,)", "Settings (⌘,)"))
            .keyboardShortcut(",", modifiers: .command)
            .popover(isPresented: $settings, arrowEdge: .bottom) { SettingsView() }
            .padding(16)
        }
    }

    private func choice(_ training: Training, key: Character, icon: String) -> some View {
        Button { choose(training) } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 32))
                Text(training.title).font(.title3)
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
            Text(Training.terminal.title).font(.largeTitle.bold())
            Text(tr("Выбери тренировку цифрой", "Choose a training by number")).foregroundStyle(.secondary)
            ForEach(lessons.indices, id: \.self) { i in
                Button { open(i) } label: {
                    HStack(spacing: 14) {
                        KeyCap(text: "\(i + 1)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lessons[i].title).font(.headline)
                            Text(lessons[i].subtitle).foregroundStyle(.secondary)
                        }
                        Spacer()
                        let done = Stats.shared.lesson(lessons[i].id).completed
                        if done > 0 {
                            Text("✓ \(done)").foregroundColor(.green).help(tr("Сколько раз пройдена", "Times completed"))
                        }
                        Text(tr("\(lessons[i].exercises.count) упр.", "\(lessons[i].exercises.count) ex.")).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
            }
            Spacer()
            Button(tr("Назад (Esc)", "Back (Esc)"), action: back).keyboardShortcut(.cancelAction)
        }
        .padding(28)
    }
}

struct SettingsView: View {
    @AppStorage("lang") private var lang = Lang.ru

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("Язык", "Language")).font(.headline)
            Picker("", selection: $lang) {
                ForEach(Lang.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        }
        .padding(16)
    }
}

struct PlaceholderView: View {
    let title: String
    let back: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(title).font(.largeTitle.bold())
            Text(tr("Скоро", "Coming soon")).foregroundStyle(.secondary)
            Button(tr("Назад (Esc)", "Back (Esc)"), action: back).keyboardShortcut(.cancelAction)
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
    let start = Date()
    private var hinted: Set<Int> = []   // подсказку считаем один раз на упражнение

    init(_ lesson: Lesson) {
        self.lesson = lesson
        reset()
        Stats.shared.started(lesson.id)
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
            Stats.shared.completed(lesson.id, time: Date().timeIntervalSince(start))
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
        case "cmd+/":
            showHint.toggle()
            if showHint, !solved, hinted.insert(index).inserted { Stats.shared.hint(lesson.id, index) }
            return true
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
        if exercise.check(term) {
            solved = true
            Stats.shared.solved(lesson.id, index)
        }
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
                    Text(tr("Тренировка «\(runner.lesson.title)» пройдена", "Training “\(runner.lesson.title)” completed")).font(.title.bold())
                    Text(tr("Enter — к списку тренировок", "Enter — back to trainings")).foregroundStyle(.secondary)
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(tr("Подсказка", "Hint")).font(.caption).foregroundStyle(.secondary)
                        Text(runner.exercise.hint)
                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                        if !runner.exercise.note.isEmpty {
                            Text(LocalizedStringKey(runner.exercise.note))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
                }
                TerminalScreen(term: runner.term)
                if runner.solved {
                    Text(tr("✓ Готово! Enter — следующее упражнение", "✓ Done! Enter — next exercise")).bold().foregroundColor(.green)
                } else {
                    Text(tr("⌘/ подсказка    ⌘R заново    Esc к списку", "⌘/ hint    ⌘R restart    Esc to list")).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .background(KeyCatcher { runner.handle($0, back: back) })
        .onDisappear { Stats.shared.addTime(Date().timeIntervalSince(runner.start)) }
    }
}

struct StatsView: View {
    let lessons: [Lesson]
    let back: () -> Void
    @ObservedObject private var stats = Stats.shared
    @State private var selected: Int?

    var body: some View {
        if let i = selected { detail(lessons[i]) } else { overview }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Статистика", "Statistics")).font(.largeTitle.bold())
            HStack(spacing: 12) {
                tile("\(stats.completed)", tr("тренировок пройдено", "trainings completed"))
                tile("\(stats.solved)", tr("упражнений решено", "exercises solved"))
                tile(duration(stats.time), tr("в упражнениях", "in exercises"))
                tile("\(stats.days)", tr("дней занятий", "days of practice"))
            }
            Text(tr("Цифра — подробнее о тренировке", "Number — training details")).foregroundStyle(.secondary).padding(.top, 8)
            ForEach(lessons.indices, id: \.self) { i in
                let s = stats.lesson(lessons[i].id)
                Button { selected = i } label: {
                    HStack(spacing: 14) {
                        KeyCap(text: "\(i + 1)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(lessons[i].title).font(.headline)
                            Text(tr("решено \(s.solvedCount) из \(lessons[i].exercises.count) упр., подсказок \(s.hints)",
                                    "solved \(s.solvedCount) of \(lessons[i].exercises.count) ex., hints \(s.hints)"))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            if s.completed > 0 {
                                Text(tr("пройдена \(times(s.completed))", "completed \(times(s.completed))"))
                            } else {
                                Text(tr("не пройдена", "not completed")).foregroundStyle(.secondary)
                            }
                            if let best = s.bestTime, let last = s.lastCompleted {
                                Text(tr("лучшее \(clock(best)) · \(shortDate(last))", "best \(clock(best)) · \(shortDate(last))"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: [])
            }
            Spacer()
            Button(tr("Назад (Esc)", "Back (Esc)"), action: back).keyboardShortcut(.cancelAction)
        }
        .padding(28)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title.bold())
            Text(label).font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
    }

    private func detail(_ lesson: Lesson) -> some View {
        let s = stats.lesson(lesson.id)
        return VStack(alignment: .leading, spacing: 12) {
            Text(lesson.title).font(.largeTitle.bold())
            Text(tr("Начата \(times(s.started)), пройдена \(times(s.completed))", "Started \(times(s.started)), completed \(times(s.completed))")
                 + (s.bestTime.map { tr(", лучшее время \(clock($0))", ", best time \(clock($0))") } ?? ""))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lesson.exercises.indices, id: \.self) { i in
                        let e = s.exercise(i)
                        HStack(spacing: 12) {
                            Text("\(i + 1)").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                            Text(LocalizedStringKey(lesson.exercises[i].task)).lineLimit(1)
                            Spacer()
                            Text("✓ \(e.solved)").foregroundColor(e.solved > 0 ? .green : .secondary)
                                .help(tr("Сколько раз решено", "Times solved"))
                            Text("? \(e.hints)").foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                                .help(tr("Сколько раз открыта подсказка", "Times hint was shown"))
                        }
                    }
                }
            }
            Button(tr("Назад (Esc)", "Back (Esc)")) { selected = nil }.keyboardShortcut(.cancelAction)
        }
        .padding(28)
    }
}

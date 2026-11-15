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
    case levels(Int)
    case exercise(Int, Int)
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
                LessonListView(courses: terminalCourses, open: { screen = .levels($0) }, back: { screen = .start })
            case .levels(let i):
                LevelListView(course: terminalCourses[i], open: { screen = .exercise(i, $0) }, back: { screen = .lessons(.terminal) })
            case .lessons(.vscode):
                PlaceholderView(title: Training.vscode.title) { screen = .start }
            case .exercise(let i, let level):
                ExerciseView(lesson: terminalCourses[i].levels[level]) { screen = .levels(i) }
            case .stats:
                StatsView(courses: terminalCourses) { screen = .start }
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
    let courses: [Course]
    let open: (Int) -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Training.terminal.title).font(.largeTitle.bold())
            Text(tr("Выбери тренировку цифрой", "Choose a training by number")).foregroundStyle(.secondary)
            ForEach(courses.indices, id: \.self) { i in
                let c = courses[i]
                Button { open(i) } label: {
                    HStack(spacing: 14) {
                        KeyCap(text: "\(i + 1)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).font(.headline)
                            Text(c.subtitle).foregroundStyle(.secondary)
                        }
                        Spacer()
                        LevelMarks(course: c)
                        Text(tr("\(c.levels.map(\.exercises.count).reduce(0, +)) упр.", "\(c.levels.map(\.exercises.count).reduce(0, +)) ex."))
                            .foregroundStyle(.secondary)
                            .frame(width: 64, alignment: .trailing)
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

// три кружка: какие уровни пройдены
struct LevelMarks: View {
    let course: Course

    var body: some View {
        HStack(spacing: 4) {
            ForEach(course.levels.indices, id: \.self) { n in
                Image(systemName: Stats.shared.lesson(course.levels[n].id).completed > 0 ? "circle.fill" : "circle")
                    .font(.caption)
                    .foregroundColor(Stats.shared.lesson(course.levels[n].id).completed > 0 ? .green : .secondary)
            }
        }
        .help(tr("Пройденные уровни", "Completed levels"))
    }
}

struct LevelListView: View {
    let course: Course
    let open: (Int) -> Void
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(course.title).font(.largeTitle.bold())
            Text(tr("Выбери уровень цифрой", "Choose a level by number")).foregroundStyle(.secondary)
            ForEach(course.levels.indices, id: \.self) { n in
                let lesson = course.levels[n]
                let s = Stats.shared.lesson(lesson.id)
                Button { open(n) } label: {
                    HStack(spacing: 14) {
                        KeyCap(text: "\(n + 1)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(levelName(n)).font(.headline)
                            Text(levelInfo(n)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if s.completed > 0 {
                            Text("✓ \(s.completed)").foregroundColor(.green).help(tr("Сколько раз пройден", "Times completed"))
                        }
                        Text(tr("\(lesson.exercises.count) упр.", "\(lesson.exercises.count) ex.")).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(n + 1)")), modifiers: [])
            }
            Spacer()
            Button(tr("Назад (Esc)", "Back (Esc)"), action: back).keyboardShortcut(.cancelAction)
        }
        .padding(28)
    }

    private func levelInfo(_ n: Int) -> String {
        [tr("Основные команды, в задании сказано, что набрать", "The basics, the task says what to type"),
         tr("Задание без готовой команды, нужно вспомнить самому", "No ready command in the task, recall it yourself"),
         tr("Несколько шагов и сочетания команд", "Several steps and combined commands")][n]
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
                    Text(tr("Уровень: \(levelName(runner.lesson.level))", "Level: \(levelName(runner.lesson.level))")).font(.title3)
                    Text(tr("Enter — к выбору уровня", "Enter — back to levels")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack {
                    Text("\(runner.lesson.title) · \(levelName(runner.lesson.level))").font(.headline)
                    Spacer()
                    Text("\(runner.index + 1) / \(runner.lesson.exercises.count)").foregroundStyle(.secondary)
                }
                Text(LocalizedStringKey(runner.exercise.task))
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                if runner.showHint {
                    VStack(alignment: .leading, spacing: 6) {
                        HintSteps(hint: runner.exercise.hint)
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
    let courses: [Course]
    let back: () -> Void
    @ObservedObject private var stats = Stats.shared
    @State private var selected: Int?

    var body: some View {
        if let i = selected { detail(courses[i]) } else { overview }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Статистика", "Statistics")).font(.largeTitle.bold())
            HStack(spacing: 12) {
                tile("\(stats.completed)", tr("уровней пройдено", "levels completed"))
                tile("\(stats.solved)", tr("упражнений решено", "exercises solved"))
                tile(duration(stats.time), tr("в упражнениях", "in exercises"))
                tile("\(stats.days)", tr("дней занятий", "days of practice"))
            }
            Text(tr("Цифра — подробнее о тренировке", "Number — training details")).foregroundStyle(.secondary).padding(.top, 8)
            ForEach(courses.indices, id: \.self) { i in
                let c = courses[i]
                let all = c.levels.map { stats.lesson($0.id) }
                let total = c.levels.map(\.exercises.count).reduce(0, +)
                Button { selected = i } label: {
                    HStack(spacing: 14) {
                        KeyCap(text: "\(i + 1)")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.title).font(.headline)
                            Text(tr("решено \(all.map(\.solvedCount).reduce(0, +)) из \(total) упр., подсказок \(all.map(\.hints).reduce(0, +))",
                                    "solved \(all.map(\.solvedCount).reduce(0, +)) of \(total) ex., hints \(all.map(\.hints).reduce(0, +))"))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        LevelMarks(course: c)
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

    private func detail(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(course.title).font(.largeTitle.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(course.levels.indices, id: \.self) { n in
                        let lesson = course.levels[n]
                        let s = stats.lesson(lesson.id)
                        Text(levelName(n)).font(.title3.bold()).padding(.top, n == 0 ? 0 : 12)
                        Text(tr("Начат \(times(s.started)), пройден \(times(s.completed))", "Started \(times(s.started)), completed \(times(s.completed))")
                             + (s.bestTime.map { tr(", лучшее время \(clock($0))", ", best time \(clock($0))") } ?? ""))
                            .foregroundStyle(.secondary)
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
            }
            Button(tr("Назад (Esc)", "Back (Esc)")) { selected = nil }.keyboardShortcut(.cancelAction)
        }
        .padding(28)
    }
}

// шаги подсказки пишутся через «  →  », показываем их нумерованным списком,
// чтобы стрелку не приняли за часть команды
struct HintSteps: View {
    let hint: String

    var body: some View {
        let steps = hint.components(separatedBy: "  →  ")
        VStack(alignment: .leading, spacing: 4) {
            Text(steps.count > 1 ? tr("Подсказка: по шагам, каждый отдельно", "Hint: step by step, one at a time") : tr("Подсказка", "Hint"))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(steps.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if steps.count > 1 {
                        Text("\(i + 1).").foregroundStyle(.secondary).frame(minWidth: 24, alignment: .trailing)
                    }
                    Text(steps[i])
                }
                .font(.system(.title3, design: .monospaced).weight(.semibold))
            }
        }
    }
}

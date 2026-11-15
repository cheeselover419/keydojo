import SwiftUI

@main
struct KeyDojoApp: App {
    init() { KeySound.shared.start() }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(tr("О программе KeyDojo", "About KeyDojo")) { showAbout() }
            }
        }
    }
}

// имя из учётной записи macOS: первое слово полного имени, иначе логин
let userName: String = NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()

// стандартная панель с ссылкой на GitHub, как в KeyMeter
func showAbout() {
    let center = NSMutableParagraphStyle()
    center.alignment = .center
    let credits = NSAttributedString(string: "github.com/cheeselover419", attributes: [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: center,
        .link: URL(string: "https://github.com/cheeselover419")!,
    ])
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
}

enum Training {
    case terminal, vscode, typing

    var title: String {
        switch self {
        case .terminal: tr("Терминал", "Terminal")
        case .vscode: "VS Code"
        case .typing: tr("Скорость печати", "Typing speed")
        }
    }
}

enum Screen: Equatable {
    case start
    case lessons(Training)
    case levels(Int)
    case exercise(Int, Int)
    case exam
    case examRun(Int, ExamMode)
    case stats
}

struct ContentView: View {
    @State private var screen = Screen.start
    @State private var settings = false
    @AppStorage("lang") private var lang = Lang.ru

    var body: some View {
        Group {
            switch screen {
            case .start:
                StartView(choose: { screen = .lessons($0) }, stats: { screen = .stats }, settings: $settings)
            case .lessons(.terminal):
                LessonListView(courses: terminalCourses, open: { screen = .levels($0) }, exam: { screen = .exam }, back: { screen = .start })
            case .exam:
                ExamSetupView(start: { screen = .examRun($0, $1) }, back: { screen = .lessons(.terminal) })
            case .examRun(let level, let mode):
                ExamView(level: level, mode: mode) { screen = .exam }
            case .levels(let i):
                LevelListView(course: terminalCourses[i], open: { screen = .exercise(i, $0) }, back: { screen = .lessons(.terminal) })
            case .lessons(let training):
                PlaceholderView(title: training.title) { screen = .start }
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
    @Binding var settings: Bool

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("KeyDojo").font(.largeTitle.bold())
                Text(tr("Привет, \(userName)!", "Hi, \(userName)!")).font(.title2)
                Text(tr("Выбери тренировку", "Choose a training")).foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                choice(.terminal, key: "t", icon: "terminal")
                choice(.vscode, key: "v", icon: "chevron.left.forwardslash.chevron.right")
                choice(.typing, key: "p", icon: "keyboard")
            }
            HStack(spacing: 16) {
                Button(action: stats) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar")
                        Text(tr("Статистика", "Statistics"))
                        KeyCap(text: "S")
                    }
                }
                .keyboardShortcut("s", modifiers: [])
                Button { settings.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                        Text(tr("Настройки", "Settings"))
                        KeyCap(text: "⌘S")
                    }
                }
                .keyboardShortcut("s", modifiers: .command)
                .popover(isPresented: $settings, arrowEdge: .bottom) { SettingsView { settings = false } }
                Button(action: showAbout) {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                        Text(tr("О программе", "About"))
                        KeyCap(text: "I")
                    }
                }
                .keyboardShortcut("i", modifiers: [])
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    let exam: () -> Void
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
            Button(action: exam) {
                HStack(spacing: 14) {
                    KeyCap(text: "E")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Экзамен", "Exam")).font(.headline)
                        Text(tr("Случайные вопросы из всех тренировок, без подсказок", "Random questions from all trainings, no hints")).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("e", modifiers: [])
            .padding(.top, 8)
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
    let close: () -> Void
    @AppStorage("lang") private var lang = Lang.ru
    @AppStorage("keySound") private var keySound = true
    @AppStorage("keySoundPack") private var pack = SoundPack.clack
    @State private var confirmReset = false
    @State private var resetDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Язык", "Language")).font(.headline)
            row("L", icon: "globe", lang.name) { switchLang() }

            Text(tr("Звук", "Sound")).font(.headline).padding(.top, 8)
            row("S", icon: keySound ? "speaker.wave.2" : "speaker.slash",
                keySound ? tr("Звук клавиш включён", "Key sound on") : tr("Звук клавиш выключен", "Key sound off")) { keySound.toggle() }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(Array(SoundPack.allCases.enumerated()), id: \.element) { i, p in
                    row("\(i + 1)", icon: pack == p ? "largecircle.fill.circle" : "circle", p.rawValue, selected: pack == p) {
                        pack = p
                        if keySound { KeySound.shared.play() }
                    }
                }
            }
            .disabled(!keySound)

            Text(tr("Статистика", "Statistics")).font(.headline).padding(.top, 8)
            if confirmReset {
                Text(tr("Сбросить всю статистику? Это нельзя отменить.", "Reset all statistics? This can't be undone."))
                    .foregroundStyle(.red)
                row("Enter", icon: "trash", tr("Сбросить", "Reset")) { reset() }
                row("Esc", icon: "xmark", tr("Отмена", "Cancel")) { confirmReset = false }
            } else {
                row("R", icon: resetDone ? "checkmark" : "trash",
                    resetDone ? tr("Статистика сброшена", "Statistics reset") : tr("Сбросить статистику", "Reset statistics")) {
                    confirmReset = true
                    resetDone = false
                }
            }

            Text(tr("Esc или ⌘S — закрыть", "Esc or ⌘S to close"))
                .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
        }
        .padding(16)
        .frame(width: 340)
        .background(KeyCatcher { key in
            if confirmReset {
                switch key.name {
                case "enter": reset()
                case "esc": confirmReset = false
                case "cmd+s": close()
                default: break
                }
                return true
            }
            if keySound, let n = Int(key.name), (1...SoundPack.allCases.count).contains(n) {
                pack = SoundPack.allCases[n - 1]
                return true
            }
            switch key.name {
            case "r": confirmReset = true; resetDone = false
            case "l": switchLang()
            case "s": keySound.toggle()
            case "esc", "cmd+s": close()
            default: return false
            }
            return true
        })
    }

    private func reset() {
        Stats.shared.reset()
        confirmReset = false
        resetDone = true
    }

    private func switchLang() {
        let all = Lang.allCases
        lang = all[(all.firstIndex(of: lang)! + 1) % all.count]
    }

    // кнопка как на стартовом экране: значок, текст и клавиша
    private func row(_ key: String, icon: String, _ title: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 18)
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                KeyCap(text: key)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
        }
        .tint(selected ? .accentColor : nil)
        .buttonStyle(.bordered)
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
    var elapsed: Double?                 // итоговое время, когда тренировка пройдена
    private var hinted: Set<Int> = []   // подсказку считаем один раз на упражнение
    private(set) var skipped: Set<Int> = []

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
            let t = Date().timeIntervalSince(start)
            elapsed = t
            // с пропусками уровень не засчитывается
            if skipped.isEmpty { Stats.shared.completed(lesson.id, time: t) }
        }
    }

    // false: клавишу обрабатывает система (например ⌘Q)
    func handle(_ key: Key, back: () -> Void) -> Bool {
        let own = ["cmd+r", "cmd+/", "cmd+enter"].contains(key.name) || Terminal.cmdKeys.contains(key.name)
        if key.name.hasPrefix("cmd+") && !own { return false }
        if finished {
            if key.name == "enter" || key.name == "esc" { back() }
            return true
        }
        switch key.name {
        case "cmd+r": reset(); return true
        case "cmd+enter":
            if !solved { skipped.insert(index) }
            next()
            return true
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
                    Text(runner.skipped.isEmpty ? tr("Тренировка «\(runner.lesson.title)» пройдена", "Training “\(runner.lesson.title)” completed")
                         : tr("Тренировка «\(runner.lesson.title)» не засчитана: пропущено \(runner.skipped.count)",
                              "Training “\(runner.lesson.title)” not counted: \(runner.skipped.count) skipped")).font(.title.bold())
                    Text(tr("Уровень: \(levelName(runner.lesson.level))", "Level: \(levelName(runner.lesson.level))")).font(.title3)
                    Text(tr("Время: \(clock(runner.elapsed ?? 0))", "Time: \(clock(runner.elapsed ?? 0))")).font(.title3).monospacedDigit()
                    Text(tr("Enter — к выбору уровня", "Enter — back to levels")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                HStack {
                    Text("\(runner.lesson.title) · \(levelName(runner.lesson.level))").font(.headline)
                    Spacer()
                    TimelineView(.periodic(from: runner.start, by: 1)) { ctx in
                        Label(clock(ctx.date.timeIntervalSince(runner.start)), systemImage: "stopwatch").monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    .help(tr("Время на тренировку", "Time spent on this training"))
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
                    Text(tr("⌘/ подсказка    ⌘R заново    ⌘Enter пропустить    Esc к списку", "⌘/ hint    ⌘R restart    ⌘Enter skip    Esc to list")).font(.callout).foregroundStyle(.secondary)
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
    @State private var exams = false

    var body: some View {
        if exams { examDetail } else if let i = selected { detail(courses[i]) } else { overview }
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
            Button { exams = true } label: {
                HStack(spacing: 14) {
                    KeyCap(text: "E")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("Экзамены", "Exams")).font(.headline)
                        Text(tr("сдано \(stats.examsPassed) из \(stats.examsTaken)", "passed \(stats.examsPassed) of \(stats.examsTaken)"))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { n in
                            let passed = examModes.contains { stats.exam(n, $0).passed > 0 }
                            Image(systemName: passed ? "circle.fill" : "circle")
                                .font(.caption)
                                .foregroundColor(passed ? .green : .secondary)
                        }
                    }
                    .help(tr("Уровни, где экзамен сдан", "Levels with a passed exam"))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("e", modifiers: [])
            Spacer()
            Button(tr("Назад (Esc)", "Back (Esc)"), action: back).keyboardShortcut(.cancelAction)
        }
        .padding(28)
    }

    private let examModes: [ExamMode] = [.limited, .full]

    // как подробности тренировки: уровни, в них строки по вариантам
    private var examDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Экзамены", "Exams")).font(.largeTitle.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<3, id: \.self) { n in
                        let all = examModes.map { stats.exam(n, $0) }
                        let best = all.compactMap(\.bestTime).min()
                        Text(levelName(n)).font(.title3.bold()).padding(.top, n == 0 ? 0 : 12)
                        Text(tr("Начат \(times(all.map(\.taken).reduce(0, +))), сдан \(times(all.map(\.passed).reduce(0, +)))",
                                "Started \(times(all.map(\.taken).reduce(0, +))), passed \(times(all.map(\.passed).reduce(0, +)))")
                             + (best.map { tr(", лучшее время \(clock($0))", ", best time \(clock($0))") } ?? ""))
                            .foregroundStyle(.secondary)
                        ForEach(examModes.indices, id: \.self) { i in
                            let e = all[i]
                            HStack(spacing: 12) {
                                Text("\(i + 1)").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary).frame(width: 24, alignment: .trailing)
                                Text(examModes[i].title).lineLimit(1)
                                Spacer()
                                Text("✓ \(e.passed)").foregroundColor(e.passed > 0 ? .green : .secondary)
                                    .help(tr("Сколько раз сдан", "Times passed"))
                                Text("\(e.bestCorrect)/\(ExamRunner.size)").foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                                    .help(tr("Лучший результат", "Best result"))
                            }
                        }
                    }
                }
            }
            Button(tr("Назад (Esc)", "Back (Esc)")) { exams = false }.keyboardShortcut(.cancelAction)
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
    var title: String?
    var font = Font.system(.title3, design: .monospaced).weight(.semibold)

    var body: some View {
        let steps = hint.components(separatedBy: "  →  ")
        VStack(alignment: .leading, spacing: 4) {
            Text((title ?? tr("Подсказка", "Hint")) + (steps.count > 1 ? tr(": по шагам, каждый отдельно", ": step by step, one at a time") : ""))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(steps.indices, id: \.self) { i in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if steps.count > 1 {
                        Text("\(i + 1).").foregroundStyle(.secondary).frame(minWidth: 24, alignment: .trailing)
                    }
                    Text(steps[i])
                }
                .font(font)
            }
        }
    }
}

// MARK: экзамен

struct ExamSetupView: View {
    let start: (Int, ExamMode) -> Void
    let back: () -> Void
    @State private var level: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Экзамен", "Exam")).font(.largeTitle.bold())
            if let level {
                Text(tr("Уровень: \(levelName(level)). Выбери вариант цифрой", "Level: \(levelName(level)). Choose a mode by number")).foregroundStyle(.secondary)
                row(1, ExamMode.limited.title,
                    tr("Экзамен закончится на \(ExamRunner.maxMistakes)-й ошибке", "The exam ends at mistake number \(ExamRunner.maxMistakes)")) { start(level, .limited) }
                row(2, ExamMode.full.title,
                    tr("Все \(ExamRunner.size) вопросов, ошибки считаются, но экзамен не прерывают", "All \(ExamRunner.size) questions, mistakes are counted but don't stop the exam")) { start(level, .full) }
            } else {
                Text(tr("\(ExamRunner.size) случайных вопросов, \(Int(ExamRunner.timeLimit) / 60) минут, подсказок нет. Выбери уровень цифрой", "\(ExamRunner.size) random questions, \(Int(ExamRunner.timeLimit) / 60) minutes, no hints. Choose a level by number")).foregroundStyle(.secondary)
                ForEach(0..<3, id: \.self) { n in
                    row(n + 1, levelName(n), tr("Вопросы из уровня «\(levelName(n))» всех тренировок", "Questions from the “\(levelName(n))” level of every training")) { level = n }
                }
            }
            Text(tr("Ошибка — команда, которая завершилась ошибкой, или пропущенный вопрос.", "A mistake is a command that ends with an error, or a skipped question."))
                .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            Spacer()
            Button(tr("Назад (Esc)", "Back (Esc)")) {
                if level == nil { back() } else { level = nil }
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(28)
    }

    private func row(_ n: Int, _ title: String, _ info: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                KeyCap(text: "\(n)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(info).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [])
    }
}

struct ExamView: View {
    @StateObject private var runner: ExamRunner
    let back: () -> Void
    @State private var selected = 0

    init(level: Int, mode: ExamMode, back: @escaping () -> Void) {
        _runner = StateObject(wrappedValue: ExamRunner(courses: terminalCourses, level: level, mode: mode))
        self.back = back
    }

    var body: some View {
        Group {
            if runner.finished { results } else { question }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in runner.tick() }
        .onChange(of: runner.finished) { done in
            if done {
                Stats.shared.examFinished(level: runner.level, mode: runner.mode, correct: runner.correct,
                                          total: runner.questions.count, time: runner.spent)
            }
        }
        .padding(20)
        .background(KeyCatcher { key in
            if runner.finished { return resultsKey(key) }
            return runner.handle(key) { runner.finished = true }
        })
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("Экзамен · \(levelName(runner.level))", "Exam · \(levelName(runner.level))")).font(.headline)
                Spacer()
                Label(clock(runner.remaining), systemImage: "timer")
                    .monospacedDigit()
                    .foregroundColor(runner.remaining < 60 ? .red : .primary)
                    .help(tr("Осталось времени", "Time left"))
                Text(mistakesText).foregroundColor(runner.mistakes > 0 ? .red : .secondary)
                Text("\(runner.index + 1) / \(runner.questions.count)").foregroundStyle(.secondary)
            }
            Text(runner.question.topic).font(.caption).foregroundStyle(.secondary)
            Text(LocalizedStringKey(runner.question.exercise.task))
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            TerminalScreen(term: runner.term)
            if runner.solved {
                Text(tr("✓ Верно! Enter — следующий вопрос", "✓ Correct! Enter — next question")).bold().foregroundColor(.green)
            } else if runner.noHint {
                Text(tr("На экзамене подсказок нет", "No hints during the exam")).foregroundColor(.orange)
            } else {
                Text(tr("⌘Enter пропустить (это ошибка)    ⌘R заново    Esc завершить", "⌘Enter skip (counts as a mistake)    ⌘R restart    Esc finish"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var mistakesText: String {
        let n = runner.mistakes
        return runner.mode == .limited
            ? tr("ошибок \(n) из \(ExamRunner.maxMistakes)", "mistakes \(n) of \(ExamRunner.maxMistakes)")
            : tr("ошибок \(n)", "mistakes \(n)")
    }

    // ↑↓ листают ответы, Enter и Esc возвращают к выбору экзамена
    private func resultsKey(_ key: Key) -> Bool {
        switch key.name {
        case "up", "k": selected = max(0, selected - 1)
        case "down", "j": selected = min(runner.answers.count - 1, selected + 1)
        case "enter", "esc": back()
        default: return !key.name.hasPrefix("cmd+")
        }
        return true
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.largeTitle.bold())
            Text(tr("Верно \(runner.correct) из \(runner.questions.count), ошибок \(runner.mistakes), время \(clock(runner.spent))",
                    "Correct \(runner.correct) of \(runner.questions.count), mistakes \(runner.mistakes), time \(clock(runner.spent))"))
                .font(.title3)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(runner.answers.indices, id: \.self) { i in
                            answerRow(i).id(i)
                        }
                    }
                }
                .onChange(of: selected) { i in withAnimation { proxy.scrollTo(i, anchor: .center) } }
            }
            Text(tr("↑↓ листать ответы    Enter — к выбору экзамена", "↑↓ scroll answers    Enter — back to exams")).font(.callout).foregroundStyle(.secondary)
        }
    }

    private var title: String {
        if runner.timeUp { return tr("Время вышло", "Time is up") }
        if runner.failedByLimit { return tr("Экзамен не сдан: \(ExamRunner.maxMistakes) ошибки", "Exam failed: \(ExamRunner.maxMistakes) mistakes") }
        return runner.correct == runner.questions.count ? tr("Экзамен сдан без ошибок", "Exam passed with no mistakes")
            : runner.mistakes == 0 && runner.correct < runner.questions.count ? tr("Экзамен завершён досрочно", "Exam finished early")
            : tr("Экзамен завершён", "Exam finished")
    }

    private func answerRow(_ i: Int) -> some View {
        let a = runner.answers[i]
        let reached = i <= runner.index
        let (mark, color): (String, Color) = a.solved ? ("✓", .green) : reached ? ("✗", .red) : ("—", .secondary)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(mark).bold().foregroundColor(color).frame(width: 18)
                Text("\(i + 1).").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(a.question.topic).font(.caption).foregroundStyle(.secondary)
                    Text(LocalizedStringKey(a.question.exercise.task)).fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if !reached {
                    Text(tr("Не дошёл до этого вопроса", "Didn't get to this question")).foregroundStyle(.secondary)
                } else if a.commands.isEmpty {
                    Text(a.skipped ? tr("Пропущен", "Skipped") : tr("Команд не было", "No commands")).foregroundColor(a.skipped ? .red : .secondary)
                } else {
                    Text(tr("Твои команды", "Your commands")).font(.caption).foregroundStyle(.secondary)
                    ForEach(a.commands.indices, id: \.self) { c in
                        let cmd = a.commands[c]
                        HStack(spacing: 8) {
                            Text(cmd.failed ? "✗" : "·").foregroundColor(cmd.failed ? .red : .secondary)
                            Text(cmd.line).font(.system(.body, design: .monospaced)).foregroundColor(cmd.failed ? .red : .primary)
                        }
                    }
                    if a.skipped { Text(tr("Потом пропущен", "Then skipped")).foregroundColor(.red) }
                }
                if !a.solved {
                    HintSteps(hint: a.question.exercise.hint, title: tr("Правильный ответ", "Correct answer"),
                              font: .system(.body, design: .monospaced).weight(.semibold))
                    if !a.question.exercise.note.isEmpty {
                        Text(LocalizedStringKey(a.question.exercise.note)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.leading, 46)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(i == selected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06)))
    }
}

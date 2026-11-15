import Foundation
import Combine

enum ExamMode {
    case limited   // заканчивается после maxMistakes ошибок
    case full      // проходится до конца

    var title: String {
        self == .limited ? tr("До \(ExamRunner.maxMistakes) ошибок", "Up to \(ExamRunner.maxMistakes) mistakes") : tr("Полный", "Full")
    }
}

struct ExamQuestion {
    let topic: String
    let exercise: Exercise
}

struct ExamAnswer {
    let question: ExamQuestion
    var commands: [(line: String, failed: Bool)] = []
    var solved = false
    var skipped = false

    var mistakes: Int { commands.filter(\.failed).count + (skipped ? 1 : 0) }
}

// ошибка — команда, завершившаяся ошибкой, или пропущенный вопрос
final class ExamRunner: ObservableObject {
    static let size = 10
    static let maxMistakes = 3
    static let timeLimit: Double = 15 * 60

    let level: Int
    let mode: ExamMode
    let questions: [ExamQuestion]
    @Published var index = 0
    @Published var term = Terminal()
    @Published var answers: [ExamAnswer] = []
    @Published var solved = false
    @Published var finished = false {
        didSet { if finished && endedAt == nil { endedAt = Date() } }
    }
    @Published var noHint = false
    @Published var remaining = ExamRunner.timeLimit
    @Published var timeUp = false
    let start = Date()
    private(set) var endedAt: Date?
    private var logged = 0

    // вопросы случайные из всех тренировок выбранного уровня
    init(courses: [Course], level: Int, mode: ExamMode) {
        self.level = level
        self.mode = mode
        let pool = courses.flatMap { c in c.levels[level].exercises.map { ExamQuestion(topic: c.title, exercise: $0) } }
        questions = Array(pool.shuffled().prefix(Self.size))
        answers = questions.map { ExamAnswer(question: $0) }
        reset()
    }

    var question: ExamQuestion { questions[index] }
    var mistakes: Int { answers.map(\.mistakes).reduce(0, +) }
    var correct: Int { answers.filter(\.solved).count }
    var failedByLimit: Bool { mode == .limited && mistakes >= Self.maxMistakes }
    var spent: Double { (endedAt ?? Date()).timeIntervalSince(start) }

    // вызывается раз в секунду, по истечении времени экзамен заканчивается
    func tick(now: Date = Date()) {
        guard !finished else { return }
        remaining = max(0, Self.timeLimit - now.timeIntervalSince(start))
        if remaining == 0 {
            timeUp = true
            finished = true
        }
    }

    // ⌘R: задание заново, сделанные ошибки остаются
    func reset() {
        let t = Terminal()
        question.exercise.setup(t)
        t.resetChecks()
        term = t
        logged = 0
    }

    func next() {
        guard index + 1 < questions.count else { finished = true; return }
        index += 1
        solved = false
        reset()
    }

    func skip() {
        answers[index].skipped = true
        if failedByLimit { finished = true } else { next() }
    }

    // false: клавишу обрабатывает система (например ⌘Q)
    func handle(_ key: Key, finish: () -> Void) -> Bool {
        let own = ["cmd+r", "cmd+/", "cmd+enter"].contains(key.name) || Terminal.cmdKeys.contains(key.name)
        if key.name.hasPrefix("cmd+") && !own { return false }
        noHint = false
        switch key.name {
        case "cmd+/": noHint = true; return true
        case "cmd+r": if !solved { reset() }; return true
        case "cmd+enter": if solved { next() } else { skip() }; return true
        default: break
        }
        if solved {
            if key.name == "enter" { next() }
            return true
        }
        if key.name == "esc", term.mode == .shell, term.search == nil {
            finish()
            return true
        }
        term.handle(key)
        answers[index].commands += term.commandLog.dropFirst(logged)
        logged = term.commandLog.count
        if question.exercise.check(term) {
            answers[index].solved = true
            solved = true
        } else if failedByLimit {
            finished = true
        }
        return true
    }
}

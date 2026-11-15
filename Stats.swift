import Foundation

struct ExerciseStats: Codable {
    var solved = 0
    var hints = 0
}

struct LessonStats: Codable {
    var started = 0
    var completed = 0
    var bestTime: Double?
    var lastCompleted: Date?
    var exercises: [String: ExerciseStats] = [:]   // ключ — номер упражнения

    func exercise(_ i: Int) -> ExerciseStats { exercises[String(i)] ?? ExerciseStats() }
    var solvedCount: Int { exercises.values.filter { $0.solved > 0 }.count }
    var hints: Int { exercises.values.reduce(0) { $0 + $1.hints } }
}

struct ExamStats: Codable {
    var taken = 0
    var passed = 0          // все вопросы решены
    var bestCorrect = 0
    var bestTime: Double?   // среди сданных
}

struct TypingRun: Codable {
    var date: Date
    var cpm: Int
    var accuracy: Int
}

struct TypingStats: Codable {
    var runs = 0
    var bestCpm = 0
    var cpmSum = 0
    var accuracySum = 0
    var history: [TypingRun] = []   // каждая попытка, для графика

    init() {}

    // статистика до графика без истории тоже читается
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        runs = try c.decodeIfPresent(Int.self, forKey: .runs) ?? 0
        bestCpm = try c.decodeIfPresent(Int.self, forKey: .bestCpm) ?? 0
        cpmSum = try c.decodeIfPresent(Int.self, forKey: .cpmSum) ?? 0
        accuracySum = try c.decodeIfPresent(Int.self, forKey: .accuracySum) ?? 0
        history = try c.decodeIfPresent([TypingRun].self, forKey: .history) ?? []
    }

    var averageCpm: Int { runs > 0 ? cpmSum / runs : 0 }
    var averageAccuracy: Int { runs > 0 ? accuracySum / runs : 0 }
}

// статистика хранится в UserDefaults в JSON
final class Stats: ObservableObject {
    static let shared = Stats()

    private struct Store: Codable {
        var lessons: [String: LessonStats] = [:]
        var days: Set<String> = []     // дни занятий, yyyy-MM-dd
        var time: Double = 0           // секунд в упражнениях
        var exams: [String: ExamStats] = [:]   // ключ — уровень и вариант, «0.full»
        var typing: [String: TypingStats] = [:]   // ключ — режим и время, «ru.30», «code.60»

        init() {}

        // старая статистика без экзаменов тоже читается
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            lessons = try c.decodeIfPresent([String: LessonStats].self, forKey: .lessons) ?? [:]
            days = try c.decodeIfPresent(Set<String>.self, forKey: .days) ?? []
            time = try c.decodeIfPresent(Double.self, forKey: .time) ?? 0
            exams = try c.decodeIfPresent([String: ExamStats].self, forKey: .exams) ?? [:]
            typing = try c.decodeIfPresent([String: TypingStats].self, forKey: .typing) ?? [:]
        }
    }

    @Published private var data: Store

    private init() {
        let saved = UserDefaults.standard.data(forKey: "stats")
        data = saved.flatMap { try? JSONDecoder().decode(Store.self, from: $0) } ?? Store()
    }

    func lesson(_ id: String) -> LessonStats { data.lessons[id] ?? LessonStats() }
    var days: Int { data.days.count }
    var time: Double { data.time }
    var completed: Int { data.lessons.values.reduce(0) { $0 + $1.completed } }
    var solved: Int { data.lessons.values.reduce(0) { $0 + $1.exercises.values.reduce(0) { $0 + $1.solved } } }

    func exam(_ level: Int, _ mode: ExamMode) -> ExamStats { data.exams[examKey(level, mode)] ?? ExamStats() }
    var examsTaken: Int { data.exams.values.reduce(0) { $0 + $1.taken } }
    var examsPassed: Int { data.exams.values.reduce(0) { $0 + $1.passed } }

    func examFinished(level: Int, mode: ExamMode, correct: Int, total: Int, time: Double) {
        let key = examKey(level, mode)
        var e = data.exams[key] ?? ExamStats()
        e.taken += 1
        e.bestCorrect = max(e.bestCorrect, correct)
        if correct == total {
            e.passed += 1
            e.bestTime = min(e.bestTime ?? time, time)
        }
        data.exams[key] = e
        markDay()
        save()
    }

    func typing(_ mode: TypingMode, _ duration: Double) -> TypingStats { data.typing[typingKey(mode, duration)] ?? TypingStats() }
    var typingRuns: Int { data.typing.values.reduce(0) { $0 + $1.runs } }
    var typingBest: Int { data.typing.values.map(\.bestCpm).max() ?? 0 }

    func typingFinished(mode: TypingMode, duration: Double, cpm: Int, accuracy: Int) {
        let key = typingKey(mode, duration)
        var t = data.typing[key] ?? TypingStats()
        t.runs += 1
        t.bestCpm = max(t.bestCpm, cpm)
        t.cpmSum += cpm
        t.accuracySum += accuracy
        t.history.append(TypingRun(date: Date(), cpm: cpm, accuracy: accuracy))
        data.typing[key] = t
        markDay()
        save()
    }

    private func typingKey(_ mode: TypingMode, _ duration: Double) -> String { "\(mode.rawValue).\(Int(duration))" }

    private func examKey(_ level: Int, _ mode: ExamMode) -> String { "\(level).\(mode == .limited ? "limited" : "full")" }

    func started(_ id: String) {
        update(id) { $0.started += 1 }
    }

    func solved(_ id: String, _ i: Int) {
        update(id) { $0.exercises[String(i), default: ExerciseStats()].solved += 1 }
    }

    func hint(_ id: String, _ i: Int) {
        update(id) { $0.exercises[String(i), default: ExerciseStats()].hints += 1 }
    }

    func completed(_ id: String, time: Double) {
        update(id) {
            $0.completed += 1
            $0.bestTime = min($0.bestTime ?? time, time)
            $0.lastCompleted = Date()
        }
    }

    func reset() {
        data = Store()
        save()
    }

    func addTime(_ t: Double) {
        data.time += t
        save()
    }

    private func update(_ id: String, _ change: (inout LessonStats) -> Void) {
        change(&data.lessons[id, default: LessonStats()])
        markDay()
        save()
    }

    private func markDay() {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        data.days.insert(f.string(from: Date()))
    }

    private func save() {
        if let d = try? JSONEncoder().encode(data) { UserDefaults.standard.set(d, forKey: "stats") }
    }
}

// 75 → «1:15», 4000 → «1:06:40»
func clock(_ t: Double) -> String {
    let s = Int(t.rounded())
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

// 4000 → «1 ч 6 мин»
func duration(_ t: Double) -> String {
    let m = Int(t) / 60
    if m < 60 { return tr("\(m) мин", "\(m) min") }
    return tr("\(m / 60) ч \(m % 60) мин", "\(m / 60) h \(m % 60) min")
}

func shortDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: Lang.current == .en ? "en_US" : "ru_RU")
    f.dateStyle = .medium
    return f.string(from: d)
}

// 1 раз, 2 раза, 5 раз
func times(_ n: Int) -> String {
    if Lang.current == .en { return n == 1 ? "1 time" : "\(n) times" }
    let few = (2...4).contains(n % 10) && !(12...14).contains(n % 100)
    return "\(n) " + (few ? "раза" : "раз")
}

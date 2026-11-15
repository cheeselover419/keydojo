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

// статистика хранится в UserDefaults в JSON
final class Stats: ObservableObject {
    static let shared = Stats()

    private struct Store: Codable {
        var lessons: [String: LessonStats] = [:]
        var days: Set<String> = []     // дни занятий, yyyy-MM-dd
        var time: Double = 0           // секунд в упражнениях
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

    func addTime(_ t: Double) {
        data.time += t
        save()
    }

    private func update(_ id: String, _ change: (inout LessonStats) -> Void) {
        change(&data.lessons[id, default: LessonStats()])
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        data.days.insert(f.string(from: Date()))
        save()
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

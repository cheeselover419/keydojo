import SwiftUI
import Charts

func secondsName(_ d: Double) -> String { tr("\(Int(d)) секунд", "\(Int(d)) seconds") }

struct TypingSetupView: View {
    let start: (TypingMode, Double) -> Void
    let back: () -> Void
    @State private var mode: TypingMode?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Training.typing.title).font(.largeTitle.bold())
            if let mode {
                Text(tr("Режим: \(mode.name). Выбери время цифрой", "Mode: \(mode.name). Choose the time by number")).foregroundStyle(.secondary)
                ForEach(TypingRunner.durations.indices, id: \.self) { i in
                    numberRow(i + 1, secondsName(TypingRunner.durations[i]),
                              tr("Таймер начнётся с первой нажатой буквы", "The timer starts with the first letter you type")) {
                        start(mode, TypingRunner.durations[i])
                    }
                }
            } else {
                Text(tr("Выбери режим цифрой", "Choose a mode by number")).foregroundStyle(.secondary)
                ForEach(TypingMode.allCases.indices, id: \.self) { i in
                    let m = TypingMode.allCases[i]
                    numberRow(i + 1, m.name, info(m)) { mode = m }
                }
            }
            Text(tr("Скорость — верно набранные знаки в минуту, точность — доля нажатий без ошибки.",
                    "Speed is correctly typed characters per minute, accuracy is the share of keystrokes without a mistake."))
                .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            Spacer()
            Button(tr("Назад (Esc)", "Back (Esc)")) {
                if mode == nil { back() } else { mode = nil }
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(28)
    }

    private func info(_ m: TypingMode) -> String {
        switch m {
        case .ru: tr("Случайные частые слова, русская раскладка", "Random common words, Russian layout")
        case .en: tr("Случайные частые слова, английская раскладка", "Random common words, English layout")
        case .terminal: tr("Команды терминала: git, grep, find, |, &&, английская раскладка", "Terminal commands: git, grep, find, |, &&, English layout")
        case .python: tr("Короткие строки кода на Python, английская раскладка", "Short lines of Python code, English layout")
        }
    }
}

func numberRow(_ n: Int, _ title: String, _ info: String, action: @escaping () -> Void) -> some View {
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

// Enter после итогов начинает новый заход с новыми словами
struct TypingView: View {
    let mode: TypingMode
    let duration: Double
    let back: () -> Void
    @State private var attempt = 0

    var body: some View {
        TypingSession(mode: mode, duration: duration, again: { attempt += 1 }, back: back).id(attempt)
    }
}

private struct TypingSession: View {
    @StateObject private var runner: TypingRunner
    let again: () -> Void
    let back: () -> Void

    init(mode: TypingMode, duration: Double, again: @escaping () -> Void, back: @escaping () -> Void) {
        _runner = StateObject(wrappedValue: TypingRunner(mode: mode, duration: duration))
        self.again = again
        self.back = back
    }

    var body: some View {
        Group {
            if runner.finished { results } else { typing }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()) { _ in runner.tick() }
        .onChange(of: runner.finished) { done in
            if done && runner.keystrokes > 0 {
                Stats.shared.typingFinished(mode: runner.mode, duration: runner.duration, cpm: runner.cpm, accuracy: runner.accuracy)
            }
        }
        .background(KeyCatcher { key in
            switch key.name {
            case "esc": back()
            case "enter" where runner.finished: again()
            default: return runner.handle(key)
            }
            return true
        })
    }

    private var typing: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("\(Training.typing.title) · \(runner.mode.name)").font(.headline)
                Spacer()
                Text(tr("\(runner.cpm) зн/мин", "\(runner.cpm) cpm")).monospacedDigit().foregroundStyle(.secondary)
                Text("\(runner.accuracy)%").monospacedDigit().foregroundStyle(.secondary)
                    .help(tr("Точность", "Accuracy"))
                Label(clock(Double(runner.secondsLeft)), systemImage: "timer").monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 10) {
                let first = runner.currentLine
                ForEach(first..<min(first + 3, runner.lines.count), id: \.self) { i in
                    line(runner.lines[i])
                }
            }
            .font(.system(size: 24, design: .monospaced))
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            if runner.wrongLayout {
                Text(runner.mode.layout == .ru ? tr("Похоже, включена не та раскладка: переключи на русскую", "Looks like the wrong layout: switch to Russian")
                                        : tr("Похоже, включена не та раскладка: переключи на английскую", "Looks like the wrong layout: switch to English"))
                    .foregroundColor(.orange)
            } else {
                Text(runner.started == nil ? tr("Начни печатать, таймер запустится сам    Esc назад", "Start typing, the timer starts by itself    Esc back")
                                           : tr("Backspace исправить    Esc прервать (не засчитывается)", "Backspace to fix    Esc to stop (not counted)"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // верные буквы обычным цветом, ошибки красным, ещё не набранные серым, курсор подчёркнут
    private func line(_ r: Range<Int>) -> Text {
        r.reduce(Text("")) { text, i in
            let expected = runner.target[i]
            var t: Text
            if i < runner.typed.count {
                let ok = runner.typed[i] == expected
                t = Text(!ok && expected == " " ? "_" : String(expected)).foregroundColor(ok ? .primary : .red)
            } else {
                t = Text(String(expected)).foregroundColor(.secondary)
                if i == runner.typed.count { t = t.underline(true, color: .accentColor) }
            }
            return text + t
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Время вышло", "Time is up")).font(.largeTitle.bold())
            Text("\(runner.mode.name) · \(secondsName(runner.duration))").foregroundStyle(.secondary)
            HStack(spacing: 12) {
                tile("\(runner.cpm)", tr("знаков в минуту", "characters per minute"))
                tile("\(runner.cpm / 5)", tr("слов в минуту", "words per minute"))
                tile("\(runner.accuracy)%", tr("точность", "accuracy"))
                tile("\(runner.mistakes)", tr("ошибок", "mistakes"))
            }
            Text(tr("Слово в минуту считается как 5 знаков.", "A word per minute is counted as 5 characters.")).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(tr("Enter ещё раз    Esc назад", "Enter again    Esc back")).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}

// скорость или точность по попыткам, линия на каждое время захода
struct TypingChart: View {
    let mode: TypingMode
    let accuracy: Bool
    @ObservedObject private var stats = Stats.shared

    var body: some View {
        let series = TypingRunner.durations.map { (secondsName($0), stats.typing(mode, $0).history) }
        let unit = accuracy ? tr("точность, %", "accuracy, %") : tr("зн/мин", "cpm")
        if series.allSatisfy({ $0.1.isEmpty }) {
            Text(tr("График появится после первой попытки", "The chart appears after the first attempt"))
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(series, id: \.0) { name, runs in
                    ForEach(runs.indices, id: \.self) { i in
                        let y = accuracy ? runs[i].accuracy : runs[i].cpm
                        LineMark(x: .value(tr("Попытка", "Attempt"), i + 1), y: .value(unit, y))
                            .foregroundStyle(by: .value(tr("Время", "Time"), name))
                        PointMark(x: .value(tr("Попытка", "Attempt"), i + 1), y: .value(unit, y))
                            .foregroundStyle(by: .value(tr("Время", "Time"), name))
                    }
                }
            }
            .chartXAxisLabel(tr("попытка", "attempt"))
            .chartYAxisLabel(unit)
            .frame(height: 180)
        }
    }
}

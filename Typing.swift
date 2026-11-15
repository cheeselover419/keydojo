import Foundation

// тренажёр печати: случайные частые слова, заход на 30 или 60 секунд
final class TypingRunner: ObservableObject {
    static let durations: [Double] = [30, 60]

    let lang: Lang
    let duration: Double
    let target: [Character]
    let lines: [Range<Int>]   // строки по словам для показа
    @Published private(set) var typed: [Character] = []
    @Published private(set) var started: Date?
    @Published private(set) var secondsLeft: Int
    @Published var finished = false
    @Published private(set) var wrongLayout = false
    private(set) var keystrokes = 0
    private(set) var mistakes = 0
    private(set) var correctChars = 0
    // знаков в минуту по верно набранным, считается один раз в конце захода
    private(set) var cpm = 0
    private var now = Date()

    init(lang: Lang, duration: Double, words count: Int = 400) {
        self.lang = lang
        self.duration = duration
        secondsLeft = Int(duration)
        let list = typingWords(lang)
        target = Array((0..<count).map { _ in list.randomElement()! }.joined(separator: " "))
        lines = Self.wrap(target, width: 42)
    }

    static func wrap(_ text: [Character], width: Int) -> [Range<Int>] {
        var lines: [Range<Int>] = []
        var start = 0, lastSpace = -1
        for i in text.indices {
            if text[i] == " " { lastSpace = i }
            if i - start >= width && lastSpace >= start {
                lines.append(start..<lastSpace + 1)
                start = lastSpace + 1
            }
        }
        if start < text.count { lines.append(start..<text.count) }
        return lines
    }

    var currentLine: Int { lines.firstIndex { $0.contains(typed.count) } ?? max(0, lines.count - 1) }

    var elapsed: Double { started.map { min(duration, now.timeIntervalSince($0)) } ?? 0 }
    var remaining: Double { duration - elapsed }
    var accuracy: Int { keystrokes > 0 ? Int((Double(keystrokes - mistakes) * 100 / Double(keystrokes)).rounded()) : 100 }

    // экран перерисовывается только когда меняется секунда на таймере
    func tick(now: Date = Date()) {
        guard started != nil, !finished else { return }
        self.now = now
        let left = Int(remaining.rounded(.up))
        if left != secondsLeft { secondsLeft = left }
        if elapsed >= duration {
            cpm = Int(Double(correctChars) * 60 / duration)
            finished = true
        }
    }

    // true, если нажатие обработано
    func handle(_ key: Key, now: Date = Date()) -> Bool {
        guard !finished else { return false }
        if key.name == "backspace" {
            if let c = typed.popLast(), c == target[typed.count] { correctChars -= 1 }
            return true
        }
        guard let text = key.printable, !key.name.contains("+") else { return false }
        for c in text where typed.count < target.count {
            if started == nil { started = now; self.now = now }
            let expected = target[typed.count]
            keystrokes += 1
            if c == expected { correctChars += 1 } else { mistakes += 1 }
            wrongLayout = c != expected && c.isLetter && Self.alphabet(c) != Self.alphabet(expected)
            typed.append(c)
        }
        return true
    }

    private static func alphabet(_ c: Character) -> Lang? {
        guard let s = c.lowercased().unicodeScalars.first else { return nil }
        if ("a"..."z").contains(s) { return .en }
        if ("а"..."я").contains(s) || s == "ё" { return .ru }
        return nil
    }
}

func typingWords(_ lang: Lang) -> [String] {
    (lang == .ru ? ruWords : enWords).split(separator: " ").map(String.init)
}

private let ruWords = """
и в не на я он с что а по это она к но они мы как из у то за вы так же от бы для о ты все его да ну или мне \
уже было вот был если только меня нет когда даже ни может себя чтобы есть сказал очень здесь там надо раз \
человек время год день жизнь рука дело глаз слово место лицо друг голова сторона дом работа вопрос город земля \
конец вид система часть мир случай ребенок сила образ закон война голос история машина решение деньги вода \
отец мать книга дверь путь утро ночь вечер свет окно стол улица школа язык мысль власть страна точка неделя \
новый большой хороший первый последний другой каждый молодой главный белый старый высокий простой важный \
русский полный общий быстрый живой ясный тихий черный красный долгий легкий трудный свободный летний \
делать знать мочь сказать говорить стать видеть хотеть идти дать думать жить смотреть стоять понять \
сидеть взять найти любить работать читать писать играть помнить ждать слушать спросить ответить начать \
сейчас потом тогда всегда снова теперь вдруг сразу почти совсем вместе далеко быстро хорошо плохо просто \
можно нужно нельзя опять скоро рано поздно завтра вчера сегодня никогда иногда часто редко внизу наверху \
один два три пять десять сто второй много мало немного больше меньше лучше хуже весь самый который \
этот тот свой наш ваш такой какой где куда откуда почему зачем через после перед между около против \
файл код строка ключ клавиша экран палец текст скорость печать команда папка проект ошибка тест сервер
"""

private let enWords = """
the be to of and a in that have it for not on with he as you do at this but his by from they we say her she \
or an will my one all would there their what so up out if about who get which go me when make can like time \
no just him know take people into year your good some could them see other than then now look only come its \
over think also back after use two how our work first well way even new want because any these give day most \
us is was are were been has had did said made went found long down little world still own home hand high place \
small large next early young important few public bad same able great old right big night point life house \
water room mother area money story fact month lot study book eye job word business issue side kind head far \
black white open run move live hold bring write read play stand learn change lead understand watch follow \
stop create speak spend grow walk win offer remember love consider appear buy wait serve die send expect build \
stay fall cut reach kill remain always never often again here today soon later once quickly slowly \
file code line key screen finger text speed type command folder project error test server branch commit
"""

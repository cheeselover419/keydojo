import Foundation

// что набираем; rawValue — ключ в статистике
enum TypingMode: String, CaseIterable {
    case ru, en, terminal, python

    var name: String {
        switch self {
        case .ru: "Русский"
        case .en: "English"
        case .terminal: tr("Терминал", "Terminal")
        case .python: "Python"
        }
    }

    // раскладка, на которой набирается текст
    var layout: Lang { self == .ru ? .ru : .en }
}

// тренажёр печати: случайные слова или строки кода, заход на 30 или 60 секунд
final class TypingRunner: ObservableObject {
    static let durations: [Double] = [30, 60]

    let mode: TypingMode
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
    // знаков в минуту по верно набранным: при нажатии и один раз в конце захода
    @Published private(set) var cpm = 0
    private var now = Date()

    init(mode: TypingMode, duration: Double, words count: Int = 400) {
        self.mode = mode
        self.duration = duration
        secondsLeft = Int(duration)
        let list = typingWords(mode)
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
            updateCpm(now)
            return true
        }
        guard let text = key.printable, !key.name.contains("+") else { return false }
        for c in text where typed.count < target.count {
            if started == nil { started = now; self.now = now }
            let expected = target[typed.count]
            keystrokes += 1
            if c == expected { correctChars += 1 } else { mistakes += 1 }
            wrongLayout = c != expected && c.isLetter && Self.alphabet(c) != mode.layout
            typed.append(c)
        }
        updateCpm(now)
        return true
    }

    // в первые секунды скорость прыгает, поэтому не меньше секунды
    private func updateCpm(_ now: Date) {
        guard let started else { return }
        cpm = Int(Double(correctChars) * 60 / max(1, min(duration, now.timeIntervalSince(started))))
    }

    private static func alphabet(_ c: Character) -> Lang? {
        guard let s = c.lowercased().unicodeScalars.first else { return nil }
        if ("a"..."z").contains(s) { return .en }
        if ("а"..."я").contains(s) || s == "ё" { return .ru }
        return nil
    }
}

func typingWords(_ mode: TypingMode) -> [String] {
    switch mode {
    case .ru: ruWords.split(separator: " ").map(String.init)
    case .en: enWords.split(separator: " ").map(String.init)
    case .terminal: shellLines.split(separator: "\n").map(String.init)
    case .python: pythonLines.split(separator: "\n").map(String.init)
    }
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

// команды терминала, по одной на строку
private let shellLines = #"""
ls -la
cd ~/projects
mkdir -p src/utils
cp -r app app-copy
mv draft.txt final.txt
rm -rf build
cat notes.txt | grep TODO
grep -rn "TODO" src
grep -i error app.log | wc -l
find . -name "*.py"
tail -f /var/log/system.log
head -n 20 data.csv
echo "Hello" > hello.txt
echo $HOME
chmod +x run.sh
./run.sh && echo ok
ps aux | grep python
kill -9 1234
export PATH="$HOME/bin:$PATH"
tar -czf backup.tar.gz src
ssh user@server.com
curl -s https://example.com
git status
git add .
git commit -m "fix bug"
git push origin main
git checkout -b feature
git log --oneline -5
git diff HEAD~1
pip install requests
python3 -m venv .venv
source .venv/bin/activate
python3 main.py --verbose
du -sh * | sort -h
history | grep ssh
cd .. && ls
open .
ls -lh ~/Downloads
cd - && pwd
touch index.html style.css
rm *.log
wc -l *.py
sort names.txt | uniq -c
grep -v "^#" config.ini
find src -type f | wc -l
cat ~/.zshrc
which python3
brew install wget
git pull --rebase
git stash && git stash pop
git branch -d old-feature
"""#

// короткие строки на Python без отступов, по одной на строку
private let pythonLines = #"""
import os
import sys
from pathlib import Path
from collections import Counter
x = 42
name = "world"
items = [1, 2, 3]
point = (3, 4)
ages = {"anna": 20, "ivan": 25}
print("Hello, world!")
print(f"Hi, {name}!")
def add(a, b):
return a + b
def greet(name="world"):
for i in range(10):
for key, value in ages.items():
while n > 0:
if x % 2 == 0:
elif x < 0:
else:
n -= 1
total += price * count
squares = [i * i for i in range(10)]
evens = [n for n in items if n % 2 == 0]
words = text.split()
line = line.strip().lower()
result = ", ".join(words)
count = len(items)
items.append(4)
data.sort(key=lambda d: d["age"])
with open("data.txt") as f:
lines = f.readlines()
try:
except ValueError as e:
raise TypeError("bad type")
class User:
def __init__(self, name):
self.name = name
return self.name.title()
if __name__ == "__main__":
main()
assert add(2, 2) == 4
x, y = y, x
nums = list(map(int, input().split()))
print(max(nums), min(nums), sum(nums))
words = sorted(set(words))
counts = Counter(text.split())
path = Path("data") / "input.txt"
is_even = lambda n: n % 2 == 0
print(*items, sep=", ")
matrix = [[0] * 3 for _ in range(3)]
first, *rest = items
for i, item in enumerate(items, start=1):
if not items:
break
continue
"""#

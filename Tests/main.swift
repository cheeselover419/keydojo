import Foundation

// решения всех упражнений: каждое должно засчитываться, но не до ввода
func k(_ n: String, _ t: String = "") -> Key { Key(name: n, text: t) }
func typed(_ s: String) -> [Key] { s.map { c in k(c == " " ? "space" : String(c).lowercased(), String(c)) } }
func cmd(_ s: String) -> [Key] { typed(s) + [k("enter")] }
let E = k("enter"), ESC = k("esc")

let solutions: [[[Key]]] = [
  [cmd("pwd"), cmd("ls"), cmd("ls -la"), cmd("cd projects"), cmd("cd .."), cmd("cd ../.."), cmd("cd /"), cmd("cd"), cmd("cd -")],
  [cmd("mkdir homework"), cmd("mkdir -p site/css/img"), cmd("touch todo.txt"), cmd("cp notes.txt notes-backup.txt"),
   cmd("cp -r projects/app app-copy"), cmd("mv draft.txt final.txt"), cmd("mv Downloads/photo.jpg Desktop/"),
   cmd("rm old.log"), cmd("rm -r trash"), cmd("rmdir empty")],
  [cmd("cat notes.txt"), cmd("head -n 5 projects/app/app.log"), cmd("tail -3 projects/app/app.log"), cmd("wc -l projects/app/app.log"),
   cmd("less projects/app/app.log") + typed("/ERROR") + [E, k("n","n"), k("q","q")],
   cmd("tail -f projects/app/app.log") + [k("ctrl+c")]],
  [cmd("echo \"Hello\" > hello.txt"), cmd("echo World >> hello.txt"),
   cmd("nano todo.txt") + typed("buy milk") + [k("ctrl+o"), E, k("ctrl+x")],
   cmd("nano list.txt") + [k("down"), k("ctrl+k"), k("ctrl+x"), k("y","y"), E],
   cmd("nano config.txt") + [k("ctrl+w")] + typed("port") + [E, k("ctrl+e"), k("backspace"), k("backspace"), k("backspace"), k("backspace")] + typed("3000") + [k("ctrl+o"), E, k("ctrl+x")],
   cmd("nano steps.txt") + [k("down"), k("down"), k("ctrl+k"), k("up"), k("ctrl+u"), k("ctrl+o"), E, k("ctrl+x")],
   cmd("vim vim.txt") + typed("ihello") + [ESC] + typed(":wq") + [E],
   cmd("vim important.txt") + typed("iblah") + [ESC] + typed(":q") + [E] + typed(":q!") + [E]],
  [cmd("find . -name utils.py"), cmd("find projects -name \"*.py\""), cmd("grep ERROR projects/app/app.log"),
   cmd("grep -rn TODO projects"), cmd("grep -i warn projects/app/app.log"), cmd("ls | grep txt"),
   cmd("grep ERROR projects/app/app.log | wc -l")],
  [typed("cd Doc") + [k("tab"), E], [k("up"), k("up"), E], [k("ctrl+r")] + typed("grep") + [E],
   [k("ctrl+a")] + typed("l") + [E], [k("ctrl+e")] + typed(".txt") + [E], [k("opt+left"), k("opt+left")],
   [k("ctrl+w")], [k("ctrl+u")], [k("ctrl+c")], [k("ctrl+l")], [k("cmd+t")], [k("cmd+shift+]")], [k("cmd+shift+[")], [k("cmd+w")]],
]

var fails = 0
for (li, lesson) in terminalLessons.enumerated() {
  for (ei, ex) in lesson.exercises.enumerated() {
    let t = Terminal(); ex.setup(t); t.resetChecks()
    let before = ex.check(t)
    var solvedAt: Int? = nil
    for (i, key) in solutions[li][ei].enumerated() { t.handle(key); if solvedAt == nil && ex.check(t) { solvedAt = i } }
    let ok = !before && solvedAt != nil
    if !ok { fails += 1 }
    print(ok ? "ok  " : "FAIL", "\(li+1).\(ei+1)", ex.task.prefix(50), before ? "(решено до ввода!)" : "")
    if !ok { print(t.lines.suffix(8).joined(separator: "\n")) }
  }
}
// другие правильные решения (true) и то, что засчитываться не должно (false)
let alternatives: [(Int, Int, [Key], Bool)] = [
  (1,3, cmd("ls -al"), true), (1,3, cmd("ls -a"), false),
  (1,4, cmd("cd ./projects"), true), (1,4, cmd("cd ~/projects"), true), (1,4, cmd("cd /Users/student/projects"), true),
  (1,6, cmd("cd ..") + cmd("cd .."), false),
  (1,8, cmd("cd $HOME"), true), (1,9, cmd("cd ~/projects/app"), false),
  (2,4, cmd("cat notes.txt > notes-backup.txt"), true), (2,5, cmd("cp -R projects/app app-copy"), true),
  (2,9, cmd("rm -rf trash"), true), (2,9, cmd("rm trash/*") + cmd("rmdir trash"), true),
  (3,2, cmd("cat projects/app/app.log | head -n 5"), true), (3,2, cmd("head -5 < projects/app/app.log"), true),
  (3,4, cmd("cat projects/app/app.log | wc -l"), true), (3,4, cmd("wc -l < projects/app/app.log"), true),
  (3,5, cmd("less projects/app/app.log") + typed("/error") + [E, k("q","q")], false),
  (4,3, cmd("nano todo.txt") + typed("buy milk") + [k("ctrl+x"), k("y","y"), E], true),
  (4,3, cmd("nano todo.txt") + typed("buy milk") + [k("ctrl+x"), k("n","n")], false),
  (4,7, cmd("vim vim.txt") + typed("ihello") + [ESC] + typed(":x") + [E], true),
  (5,2, cmd("find projects -name '*.py'"), true),
  (5,3, cmd("cat projects/app/app.log | grep ERROR"), true),
  (5,4, cmd("grep -r -n TODO projects"), true),
  (5,6, cmd("ls|grep txt"), true),
  (5,7, cmd("grep -c ERROR projects/app/app.log"), false),
  (5,7, cmd("cat projects/app/app.log | grep ERROR | wc -l"), true),
  (6,1, cmd("cd Documents"), false), (6,2, cmd("ls -la ~/projects"), false),
  (6,7, [k("opt+backspace")], true),
]
for (l, e, keys, expect) in alternatives {
  let ex = terminalLessons[l-1].exercises[e-1]
  let t = Terminal(); ex.setup(t); t.resetChecks()
  var got = false
  for key in keys { t.handle(key); if ex.check(t) { got = true } }
  if got != expect { fails += 1 }
  print(got == expect ? "ok  " : "FAIL", "\(l).\(e) другое решение →", got ? "засчитано" : "не засчитано")
}

// разбор команд: строка → ожидаемые последние строки вывода
let shellCases: [(String, [String])] = [
  ("mkdir test && cd test && pwd", ["/Users/student/test"]),
  ("cd nowhere && pwd", ["cd: no such file or directory: nowhere"]),
  ("cd nowhere || echo fail", ["fail"]),
  ("cd projects; pwd", ["/Users/student/projects"]),
  ("grep zzz notes.txt && echo found || echo none", ["none"]),
  ("echo $HOME ${USER}", ["/Users/student student"]),
  ("echo '$HOME' \"$USER\"", ["$HOME student"]),
  ("echo ~ \"~\"", ["/Users/student ~"]),
  ("cd \"~\"", ["cd: no such file or directory: ~"]),
  ("cd projects Documents", ["cd: string not in pwd: projects"]),
  ("wc -l < notes.txt", ["       4"]),
  ("cat < nowhere", ["zsh: no such file or directory: nowhere"]),
  ("ls trash/*.tmp", ["trash/a.tmp  trash/b.tmp  trash/c.tmp"]),
  ("cp notes.txt notes.txt", ["cp: notes.txt and notes.txt are identical (not copied)."]),
  ("head -n abc notes.txt", ["head: illegal line count -- abc"]),
  ("&& ls", ["zsh: parse error near `&&'"]),
  ("ls ;", ["Desktop  Documents  Downloads  draft.txt  empty  notes.txt  old.log  projects  trash"]),
]
for (line, expect) in shellCases {
  let t = Terminal()
  t.run(line)
  let got = Array(t.lines.suffix(expect.count))
  if got != expect { fails += 1 }
  print(got == expect ? "ok  " : "FAIL", line, got == expect ? "" : "→ \(got)")
}

// vim: gg
do {
  let t = Terminal(); t.fs.put("~/a.txt", "b\n"); t.run("vim a.txt")
  for key in typed("oc") + [ESC] + typed("ggOa") + [ESC] + typed(":wq") + [E] { t.handle(key) }
  let ok = t.text("~/a.txt") == "a\nb\nc\n"
  if !ok { fails += 1 }
  print(ok ? "ok  " : "FAIL", "vim gg")
}

// решения среднего и сложного уровней: [тренировка][уровень][упражнение]
let L = "projects/app/app.log"
let bs = k("backspace")
let levelSolutions: [[[[Key]]]] = [
  [ // навигация
    [cmd("cd projects/app/src"), cmd("cd ../../site"), cmd("ls -l projects/app"), cmd("ls -a ~"),
     cmd("cd /Applications/Terminal.app") + cmd("cd -"), cmd("pwd") + cmd("cd")],
    [cmd("cd projects && ls && cd .."), cmd("ls Desktop Documents Downloads"), cmd("cd $HOME"), cmd("ls ~/*.txt"),
     cmd("cd ~/Documents") + cmd("cd ../projects/app/tests")],
  ],
  [ // файлы
    [cmd("touch a.txt b.txt c.txt"), cmd("mkdir backup") + cmd("cp notes.txt draft.txt backup/"), cmd("mv trash/*.tmp Desktop/"),
     cmd("cp .zshrc Documents/zshrc-backup"), cmd("mv projects/site projects/website"), cmd("rm Downloads/*")],
    [cmd("mkdir release && cp -r projects/app release/ && cd release/app"), cmd("mkdir backup") + cmd("cp -r projects backup/projects-2026"),
     cmd("mkdir Documents/texts") + cmd("mv notes.txt draft.txt Documents/texts/") + cmd("rm old.log"),
     cmd("touch ~/todo.md"), cmd("rm trash/*") + cmd("rmdir trash")],
  ],
  [ // просмотр
    [cmd("cat notes.txt draft.txt"), cmd("wc -w notes.txt"), cmd("tail -n 1 \(L)"), cmd("head -n 8 \(L) | tail -n 4"),
     cmd("less \(L)") + [k("g","G"), k("q","q")], cmd("less \(L)") + typed("/ERROR") + [E, k("n","n"), k("q","q")]],
    [cmd("ls | wc -l"), cmd("head -n 3 \(L) > top.txt"), cmd("head -n 10 \(L) | tail -n 1"), cmd("wc -l notes.txt draft.txt"),
     cmd("tail -f \(L)") + [k("ctrl+c"), k("ctrl+l")]],
  ],
  [ // редактирование
    [cmd("echo one > list.txt") + cmd("echo two >> list.txt") + cmd("echo three >> list.txt"), cmd("> hello.txt"),
     cmd("nano notes.txt") + Array(repeating: k("down"), count: 4) + typed("- finish KeyDojo") + [k("ctrl+o"), E, k("ctrl+x")],
     cmd("nano steps.txt") + [k("ctrl+k"), k("ctrl+k"), k("down"), k("ctrl+u"), k("ctrl+o"), E, k("ctrl+x")],
     cmd("vim list.txt") + typed("jdd:wq") + [E], cmd("vim list.txt") + typed("opears") + [ESC] + typed(":wq") + [E]],
    [cmd("nano config.txt") + [k("ctrl+w")] + typed("debug") + [E, k("ctrl+e")] + Array(repeating: bs, count: 4) + typed("false")
       + [k("ctrl+w")] + typed("port") + [E, k("ctrl+e")] + Array(repeating: bs, count: 4) + typed("3000") + [k("ctrl+o"), E, k("ctrl+x")],
     cmd("vim config.txt") + typed("Gotimeout=30") + [ESC] + typed(":wq") + [E],
     cmd("vim config.txt") + typed("Gggdd:wq") + [E],
     cmd("cat a.txt b.txt > ab.txt"),
     cmd("nano notes.txt") + [k("ctrl+o")] + Array(repeating: bs, count: 9) + typed("notes2.txt") + [E, k("ctrl+x")]],
  ],
  [ // поиск
    [cmd("find projects -type d"), cmd("find . -name \"*.txt\""), cmd("grep -v INFO \(L)"), cmd("grep -rl greet projects"),
     cmd("grep -c GET \(L)"), cmd("find . -name \"*test*\"")],
    [cmd("grep ERROR \(L) > errors.txt"), cmd("grep -E \"ERROR|WARN\" \(L)"), cmd("find projects -name \"*.py\" | wc -l"),
     cmd("grep -rn TODO projects | grep -v css"), cmd("grep -ril hello .")],
  ],
  [ // горячие клавиши
    [typed("cd pr") + [k("tab")] + typed("ap") + [k("tab")] + typed("sr") + [k("tab"), E],
     [k("opt+left"), k("ctrl+w")], [k("ctrl+k")], [k("ctrl+r")] + typed("mkdir") + [ESC] + typed("2") + [E],
     [k("cmd+t")] + cmd("cd projects") + [k("cmd+shift+[")], [k("up")] + typed(" | wc -l") + [E]],
    [[k("opt+left"), k("ctrl+w"), k("ctrl+w")], [k("up"), k("up"), k("up"), E, k("up"), k("up"), k("up"), E],
     [k("cmd+shift+]"), k("cmd+w"), k("cmd+shift+["), k("cmd+w"), k("cmd+shift+["), k("cmd+w")],
     cmd("tail -f \(L)") + [k("ctrl+c"), k("ctrl+l"), k("up"), E],
     [k("opt+left"), k("ctrl+w")] + typed("FIXME ") + [E]],
  ],
]
for (ci, course) in terminalCourses.enumerated() {
  for n in 1...2 {
    for (ei, ex) in course.levels[n].exercises.enumerated() {
      let t = Terminal(); ex.setup(t); t.resetChecks()
      let before = ex.check(t)
      var solved = false
      for key in levelSolutions[ci][n - 1][ei] { t.handle(key); if ex.check(t) { solved = true } }
      let ok = !before && solved
      if !ok { fails += 1 }
      print(ok ? "ok  " : "FAIL", "\(ci + 1).\(levelName(n)).\(ei + 1)", ex.task.prefix(50), before ? "(решено до ввода!)" : "")
      if !ok { print(t.lines.suffix(6).joined(separator: "\n")) }
    }
  }
}

// экзамен
func check(_ ok: Bool, _ name: String, _ group: String = "экзамен") {
  if !ok { fails += 1 }
  print(ok ? "ok  " : "FAIL", group + ":", name)
}
do {
  let courses = terminalCourses
  for level in 0...2 {
    let r = ExamRunner(courses: courses, level: level, mode: .full)
    let pool = Set(courses.flatMap { $0.levels[level].exercises.map(\.task) })
    let tasks = r.questions.map(\.exercise.task)
    check(tasks.count == ExamRunner.size && Set(tasks).count == tasks.count && tasks.allSatisfy(pool.contains), "уровень \(level + 1): 10 разных вопросов своего уровня")
  }
  let runs = (0..<5).map { _ in ExamRunner(courses: courses, level: 0, mode: .full).questions.map(\.exercise.task) }
  check(Set(runs.map { $0.joined(separator: "|") }).count > 1, "вопросы каждый раз разные")

  // в горячих клавишах foo не всегда ошибка: дописывается к готовой строке или уходит в tail -f
  let shell = courses.filter { $0.levels[0].id != "hotkeys" }
  let lim = ExamRunner(courses: shell, level: 0, mode: .limited)
  for _ in 0..<2 { cmd("foo").forEach { _ = lim.handle($0) {} } }
  check(!lim.finished && lim.mistakes == 2, "две ошибки — экзамен продолжается")
  cmd("foo").forEach { _ = lim.handle($0) {} }
  check(lim.finished && lim.failedByLimit, "третья ошибка завершает экзамен")
  check(lim.answers[0].commands.count == 3 && lim.answers[0].commands.allSatisfy(\.failed), "ошибочные команды записаны")

  let full = ExamRunner(courses: shell, level: 0, mode: .full)
  for _ in 0..<3 { cmd("foo").forEach { _ = full.handle($0) {} } }
  check(!full.finished && full.mistakes == 3, "полный режим не прерывается на 3 ошибках")
  _ = full.handle(k("cmd+/")) {}
  check(full.noHint, "подсказка на экзамене не показывается")
  for _ in 0..<ExamRunner.size { _ = full.handle(k("cmd+enter")) {} }
  check(full.finished && full.mistakes == 3 + ExamRunner.size && full.answers.allSatisfy(\.skipped), "пропуски считаются ошибками")

  // решение вопроса: берём ответ из решений лёгкого уровня
  var answers: [String: [Key]] = [:]
  for (li, lesson) in terminalLessons.enumerated() {
    for (ei, ex) in lesson.exercises.enumerated() { answers[ex.task] = solutions[li][ei] }
  }
  let ok = ExamRunner(courses: shell, level: 0, mode: .limited)
  for key in answers[ok.question.exercise.task]! { _ = ok.handle(key) {} }
  check(ok.solved && ok.answers[0].solved, "правильный ответ засчитан")
  _ = ok.handle(E) {}
  check(ok.index == 1 && !ok.solved, "Enter — следующий вопрос")
  let timed = ExamRunner(courses: courses, level: 1, mode: .full)
  timed.tick(now: timed.start.addingTimeInterval(60))
  check(!timed.finished && Int(timed.remaining) == Int(ExamRunner.timeLimit) - 60, "таймер отсчитывает оставшееся время")
  timed.tick(now: timed.start.addingTimeInterval(ExamRunner.timeLimit + 1))
  check(timed.finished && timed.timeUp && timed.remaining == 0, "через 15 минут экзамен заканчивается")
  _ = ok.handle(k("cmd+right")) {}
  check(ok.index == 1 && !ok.answers[1].skipped, "⌘→ больше не пропускает вопрос")
  var esc = false
  _ = ok.handle(ESC) { esc = true }
  check(esc, "Esc завершает экзамен")
}

// nano: Ctrl+K на последней пустой строке ничего не вырезает
do {
  let t = Terminal()
  (cmd("nano draft.txt") + [k("ctrl+k"), k("ctrl+k"), k("ctrl+k"), k("ctrl+u"), k("ctrl+o"), E, k("ctrl+x")] + cmd("wc -l draft.txt")).forEach(t.handle)
  let ok = t.lines.last?.hasPrefix("       1 ") == true
  if !ok { fails += 1 }
  print(ok ? "ok  " : "FAIL", "nano: Ctrl+K в конце файла не добавляет пустых строк")
}

// тренажёр печати
do {
  let r = TypingRunner(mode: .ru, duration: 30, words: 50)
  let t0 = Date()
  let word = String(r.target.prefix { $0 != " " })
  check(r.lines.allSatisfy { $0.count <= 43 } && r.lines.first?.lowerBound == 0 && r.lines.last?.upperBound == r.target.count, "строки покрывают весь текст", "печать")
  check(typingWords(.ru).count > 200 && typingWords(.en).count > 200, "слов больше 200", "печать")
  for m in [TypingMode.terminal, .python] {
    let w = typingWords(m)
    check(w.count > 40 && Set(w).count == w.count && w.allSatisfy { !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespaces) }, "\(m.name): больше 40 разных строк без лишних пробелов", "печать")
  }
  check(Set(typingWords(.terminal)).isDisjoint(with: typingWords(.python)), "терминал и Python не смешаны", "печать")
  let code = TypingRunner(mode: .python, duration: 30, words: 20)
  _ = code.handle(k(";", "ж"))
  check(code.wrongLayout, "в режиме кода русская буква — не та раскладка", "печать")
  _ = code.handle(k("backspace"))
  for c in code.target.prefix(40) { _ = code.handle(k("a", String(c))) }
  check(code.correctChars == 40, "строки кода набираются со всеми символами", "печать")
  _ = r.handle(k("space", " "), now: t0)
  check(r.mistakes == 1 && r.started == t0, "таймер стартует с первого нажатия, неверная буква — ошибка", "печать")
  _ = r.handle(k("backspace"))
  check(r.typed.isEmpty && r.mistakes == 1, "Backspace стирает, ошибка остаётся", "печать")
  for c in word { _ = r.handle(k("a", String(c))) }
  check(r.correctChars == word.count && r.keystrokes == word.count + 1, "верные буквы засчитаны", "печать")
  _ = r.handle(k("f", "a"))
  check(r.wrongLayout, "латинская буква в русском тексте — не та раскладка", "печать")
  check(!r.handle(k("cmd+r")) && !r.handle(k("enter")), "⌘ и Enter не печатают", "печать")
  r.tick(now: t0.addingTimeInterval(15))
  check(!r.finished && r.secondsLeft == 15, "таймер идёт", "печать")
  _ = r.handle(k("backspace"), now: t0.addingTimeInterval(15))
  check(r.cpm == word.count * 4, "скорость пересчитывается при нажатии", "печать")
  check(r.correctChars == word.count, "Backspace по ошибке не трогает верные буквы", "печать")
  _ = r.handle(k("backspace"))
  check(r.correctChars == word.count - 1, "Backspace по верной букве убирает её из счёта", "печать")
  r.tick(now: t0.addingTimeInterval(31))
  check(r.finished && r.remaining == 0 && r.secondsLeft == 0 && !r.handle(k("a", "ф")), "через 30 секунд заход закончен", "печать")
  check(r.cpm == (word.count - 1) * 2, "скорость в знаках в минуту в конце", "печать")
}

print("провалено:", fails)
if fails > 0 { exit(1) }

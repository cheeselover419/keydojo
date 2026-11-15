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

print("провалено:", fails)
if fails > 0 { exit(1) }

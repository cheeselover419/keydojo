import Foundation

struct Exercise {
    let task: String
    let hint: String
    var setup: (Terminal) -> Void = { _ in }
    let check: (Terminal) -> Bool
}

struct Lesson {
    let title: String
    let subtitle: String
    let exercises: [Exercise]
}

// помощники для заготовок и проверок, пути считаются от домашней папки
extension Terminal {
    func node(_ p: String) -> FSNode? { fs.node(fs.absolute(p, cwd: FileSystem.home)) }
    func isDir(_ p: String) -> Bool { node(p)?.isDir == true }
    func isFile(_ p: String) -> Bool { node(p).map { !$0.isDir } ?? false }
    func exists(_ p: String) -> Bool { node(p) != nil }
    func text(_ p: String) -> String? { node(p).flatMap { $0.isDir ? nil : $0.content } }
    func at(_ p: String) -> Bool { cwd == fs.absolute(p, cwd: FileSystem.home) }
    func used(_ key: String) -> Bool { events.contains("key:" + key) }

    var lastName: String { String(lastCommand.split(separator: " ").first ?? "") }
    var lastFlags: Set<Character> {
        Set(lastCommand.split(separator: " ").filter { $0.hasPrefix("-") }.flatMap { $0.dropFirst() })
    }

    func go(_ p: String) {
        tabs[current].oldpwd = cwd
        cwd = fs.absolute(p, cwd: FileSystem.home)
    }

    func typeInput(_ s: String, cursor pos: Int? = nil) {
        input = s
        cursor = pos ?? s.count
    }
}

private let log = "projects/app/app.log"

let terminalLessons = [navigation, files, viewing, editing, searching, hotkeys]

private let navigation = Lesson(title: "Навигация", subtitle: "pwd, ls, cd", exercises: [
    Exercise(task: "Узнай, в какой папке ты сейчас находишься.",
             hint: "`pwd` (print working directory)",
             check: { $0.lastName == "pwd" }),
    Exercise(task: "Посмотри, что лежит в текущей папке.",
             hint: "`ls`",
             check: { $0.lastName == "ls" && !$0.lastOutput.isEmpty }),
    Exercise(task: "Покажи все файлы в подробном виде, включая скрытые (их имена начинаются с точки).",
             hint: "`ls -la`: `-l` подробно, `-a` все файлы",
             check: { $0.lastName == "ls" && $0.lastFlags.isSuperset(of: ["l", "a"]) }),
    Exercise(task: "Перейди в папку `projects`.",
             hint: "`cd projects`",
             check: { $0.at("~/projects") }),
    Exercise(task: "Ты в `~/projects/app/src`. Поднимись на одну папку вверх.",
             hint: "`cd ..`",
             setup: { $0.go("~/projects/app/src") },
             check: { $0.at("~/projects/app") }),
    Exercise(task: "Ты снова в `~/projects/app/src`. Поднимись сразу на две папки вверх одной командой.",
             hint: "`cd ../..`",
             setup: { $0.go("~/projects/app/src") },
             check: { $0.at("~/projects") && $0.tabs[$0.current].oldpwd == FileSystem.home + "/projects/app/src" }),
    Exercise(task: "Перейди в корень диска.",
             hint: "`cd /`",
             check: { $0.at("/") }),
    Exercise(task: "Ты в `/usr/local`. Вернись в домашнюю папку.",
             hint: "`cd ~` или просто `cd`",
             setup: { $0.go("/usr/local") },
             check: { $0.at("~") }),
    Exercise(task: "До этого ты был в `~/projects/app`, а сейчас в `~/Documents`. Вернись в предыдущую папку, не набирая путь.",
             hint: "`cd -`",
             setup: { $0.go("~/projects/app"); $0.go("~/Documents") },
             check: { $0.at("~/projects/app") && $0.lastCommand == "cd -" }),
])

private let files = Lesson(title: "Файлы и папки", subtitle: "mkdir, touch, cp, mv, rm", exercises: [
    Exercise(task: "Создай папку `homework`.",
             hint: "`mkdir homework`",
             check: { $0.isDir("~/homework") }),
    Exercise(task: "Создай одной командой вложенные папки `site/css/img`.",
             hint: "`mkdir -p site/css/img`: `-p` создаёт все папки на пути",
             check: { $0.isDir("~/site/css/img") }),
    Exercise(task: "Создай пустой файл `todo.txt`.",
             hint: "`touch todo.txt`",
             check: { $0.isFile("~/todo.txt") }),
    Exercise(task: "Сделай копию `notes.txt` под именем `notes-backup.txt`.",
             hint: "`cp notes.txt notes-backup.txt`",
             check: { $0.text("~/notes-backup.txt") != nil && $0.text("~/notes-backup.txt") == $0.text("~/notes.txt") }),
    Exercise(task: "Скопируй папку `projects/app` целиком в `app-copy`.",
             hint: "`cp -r projects/app app-copy`: без `-r` папки не копируются",
             check: { $0.isFile("~/app-copy/README.md") && $0.isDir("~/projects/app") }),
    Exercise(task: "Переименуй `draft.txt` в `final.txt`.",
             hint: "`mv draft.txt final.txt`",
             check: { $0.isFile("~/final.txt") && !$0.exists("~/draft.txt") }),
    Exercise(task: "Перемести `photo.jpg` из `Downloads` в `Desktop`.",
             hint: "`mv Downloads/photo.jpg Desktop/`",
             check: { $0.isFile("~/Desktop/photo.jpg") && !$0.exists("~/Downloads/photo.jpg") }),
    Exercise(task: "Удали файл `old.log`.",
             hint: "`rm old.log`",
             check: { !$0.exists("~/old.log") }),
    Exercise(task: "Удали папку `trash` вместе со всем, что в ней лежит.",
             hint: "`rm -r trash`",
             check: { !$0.exists("~/trash") }),
    Exercise(task: "Удали пустую папку `empty`.",
             hint: "`rmdir empty`: удаляет только пустые папки, это безопаснее `rm -r`",
             check: { !$0.exists("~/empty") }),
])

private let viewing = Lesson(title: "Просмотр файлов", subtitle: "cat, head, tail, less, wc", exercises: [
    Exercise(task: "Выведи содержимое файла `notes.txt`.",
             hint: "`cat notes.txt`",
             check: { $0.lastName == "cat" && $0.lastCommand.contains("notes.txt") && !$0.lastOutput.isEmpty }),
    Exercise(task: "Покажи первые 5 строк файла `\(log)`.",
             hint: "`head -n 5 \(log)`",
             check: { $0.lastName == "head" && $0.lastOutput.count == 5 }),
    Exercise(task: "Покажи последние 3 строки файла `\(log)`.",
             hint: "`tail -n 3 \(log)`",
             check: { $0.lastName == "tail" && $0.lastOutput.count == 3 }),
    Exercise(task: "Посчитай, сколько строк в файле `\(log)`.",
             hint: "`wc -l \(log)`",
             check: { $0.lastName == "wc" && $0.lastFlags.contains("l") && $0.lastOutput.first?.contains("20") == true }),
    Exercise(task: "Открой `\(log)` в `less`, найди слово `ERROR` и выйди.",
             hint: "`less \(log)`, внутри `/ERROR` и `Enter`, `n` ищет дальше, `q` выходит",
             check: { $0.events.contains("less:search:ERROR") && $0.events.contains("less:quit") }),
    Exercise(task: "Запусти слежение за логом `\(log)`, а потом останови его.",
             hint: "`tail -f \(log)`, остановить: `Ctrl+C`",
             check: { $0.events.contains("tailf") && $0.events.contains("interrupt") }),
])

private let config = (1...30).map { i -> String in
    switch i {
    case 1: return "# server settings"
    case 22: return "port=8080"
    default: return "option\(i)=value\(i)"
    }
}.joined(separator: "\n") + "\n"

private let editing = Lesson(title: "Редактирование текста", subtitle: "echo, nano, vim", exercises: [
    Exercise(task: "Одной командой запиши в файл `hello.txt` строку `Hello`.",
             hint: "`echo \"Hello\" > hello.txt`: `>` перезаписывает файл",
             check: { $0.text("~/hello.txt")?.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello" }),
    Exercise(task: "Допиши в конец `hello.txt` строку `World`, не стирая то, что там уже есть.",
             hint: "`echo \"World\" >> hello.txt`: `>>` дописывает в конец",
             setup: { $0.fs.put("~/hello.txt", "Hello\n") },
             check: { $0.text("~/hello.txt")?.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello\nWorld" }),
    Exercise(task: "Открой `todo.txt` в nano, напиши `buy milk`, сохрани и выйди.",
             hint: "`nano todo.txt`, набери текст, `Ctrl+O` и `Enter` сохраняют, `Ctrl+X` выходит",
             check: { $0.text("~/todo.txt")?.contains("buy milk") == true && $0.mode == .shell }),
    Exercise(task: "В `list.txt` удали строку `trash` целиком, сохрани и выйди.",
             hint: "`nano list.txt`, стрелкой на строку `trash`, `Ctrl+K` вырезает строку, `Ctrl+O`, `Enter`, `Ctrl+X`",
             setup: { $0.fs.put("~/list.txt", "apples\ntrash\npears\n") },
             check: { $0.text("~/list.txt") == "apples\npears\n" && $0.mode == .shell }),
    Exercise(task: "В длинном `config.txt` найди через поиск строку с `port` и замени `8080` на `3000`. Сохрани и выйди.",
             hint: "`nano config.txt`, `Ctrl+W`, набери `port`, `Enter`. `Ctrl+E` в конец строки, сотри число, впиши новое",
             setup: { $0.fs.put("~/config.txt", config) },
             check: {
                 let t = $0.text("~/config.txt") ?? ""
                 return t.contains("port=3000\n") && !t.contains("8080") && $0.events.contains("nano:search") && $0.mode == .shell
             }),
    Exercise(task: "В `steps.txt` строки перепутаны. Перенеси `2. save` на место перед `3. close`, сохрани и выйди.",
             hint: "`nano steps.txt`, встань на `2. save`, `Ctrl+K`, затем встань на `3. close` и `Ctrl+U` вставит строку над ней",
             setup: { $0.fs.put("~/steps.txt", "1. open\n3. close\n2. save\n") },
             check: { $0.text("~/steps.txt") == "1. open\n2. save\n3. close\n" && $0.mode == .shell }),
    Exercise(task: "Открой `vim.txt` в vim, напиши `hello`, сохрани и выйди.",
             hint: "`vim vim.txt`, `i` включает ввод, набери текст, `Esc`, затем `:wq` и `Enter`",
             check: { $0.text("~/vim.txt")?.contains("hello") == true && $0.mode == .shell }),
    Exercise(task: "Открой `important.txt` в vim, напечатай что-нибудь, а потом выйди без сохранения.",
             hint: "`vim important.txt`, `i`, напечатай, `Esc`, затем `:q!` и `Enter`",
             setup: { $0.fs.put("~/important.txt", "do not change this file\n") },
             check: {
                 $0.text("~/important.txt") == "do not change this file\n" && $0.events.contains("vim:modified")
                     && $0.events.contains("vim:forcequit") && $0.mode == .shell
             }),
])

private let searching = Lesson(title: "Поиск", subtitle: "find, grep, |", exercises: [
    Exercise(task: "Найди, где лежит файл `utils.py`, начиная с домашней папки.",
             hint: "`find . -name utils.py`",
             check: { $0.lastName == "find" && $0.lastOutput.contains { $0.hasSuffix("/utils.py") } }),
    Exercise(task: "Найди все файлы `.py` в папке `projects`.",
             hint: "`find projects -name \"*.py\"`: шаблон в кавычках, иначе zsh раскроет его сам",
             check: { $0.lastName == "find" && $0.lastOutput.count == 3 && $0.lastOutput.allSatisfy { $0.hasSuffix(".py") } }),
    Exercise(task: "Выведи строки с `ERROR` из `\(log)`.",
             hint: "`grep ERROR \(log)`",
             check: { $0.lastName == "grep" && $0.lastOutput.count == 3 }),
    Exercise(task: "Найди `TODO` во всех файлах папки `projects` и покажи номера строк.",
             hint: "`grep -rn TODO projects`: `-r` по всем вложенным файлам, `-n` номера строк",
             check: { $0.lastName == "grep" && $0.lastFlags.isSuperset(of: ["r", "n"]) && $0.lastOutput.count == 4 }),
    Exercise(task: "Найди в `\(log)` слово `warn` без учёта регистра.",
             hint: "`grep -i warn \(log)`",
             check: { $0.lastName == "grep" && $0.lastFlags.contains("i") && $0.lastOutput.count == 4 }),
    Exercise(task: "Покажи в домашней папке только те имена, где есть `txt`: передай вывод `ls` в `grep`.",
             hint: "`ls | grep txt`",
             check: { $0.lastCommand.contains("|") && $0.lastOutput == ["draft.txt", "notes.txt"] }),
    Exercise(task: "Посчитай, сколько строк с `ERROR` в `\(log)`, используя `grep` и `wc`.",
             hint: "`grep ERROR \(log) | wc -l`",
             check: { $0.lastCommand.contains("|") && $0.lastOutput.first?.trimmingCharacters(in: .whitespaces) == "3" }),
])

private let hotkeys = Lesson(title: "Горячие клавиши", subtitle: "Tab, история, курсор, вкладки", exercises: [
    Exercise(task: "Набери `cd Doc`, нажми `Tab`, чтобы терминал дописал имя папки, и выполни команду.",
             hint: "`Tab` дописывает имена файлов и папок",
             check: { $0.at("~/Documents") && $0.used("tab") }),
    Exercise(task: "Выполни ещё раз команду `ls -la ~/projects`, не набирая её: найди её в истории.",
             hint: "`↑` листает историю назад, `↓` вперёд",
             setup: { $0.tabs[0].history = ["pwd", "ls -la ~/projects", "cat notes.txt"] },
             check: { $0.lastCommand == "ls -la ~/projects" && $0.lastTypedChars == 0 }),
    Exercise(task: "Где-то в истории есть команда с `grep`. Найди её поиском по истории и выполни.",
             hint: "`Ctrl+R`, набери `grep`, `Enter`. Повторный `Ctrl+R` ищет дальше",
             setup: { $0.tabs[0].history = ["cd projects", "grep -rn TODO projects", "ls", "pwd", "cat notes.txt", "mkdir test", "ls -la"] },
             check: { $0.lastCommand.contains("grep") && $0.events.contains("usedsearch") }),
    Exercise(task: "Курсор в конце строки `s -la`. Прыгни в начало строки, допиши `l` и выполни `ls -la`.",
             hint: "`Ctrl+A` в начало строки",
             setup: { $0.typeInput("s -la") },
             check: { $0.lastCommand == "ls -la" && $0.used("ctrl+a") }),
    Exercise(task: "Курсор в начале строки `cat notes`. Прыгни в конец, допиши `.txt` и выполни.",
             hint: "`Ctrl+E` в конец строки",
             setup: { $0.typeInput("cat notes", cursor: 0) },
             check: { $0.lastCommand == "cat notes.txt" && $0.used("ctrl+e") }),
    Exercise(task: "Поставь курсор на начало слова `hello`, двигаясь по словам.",
             hint: "`⌥←` на слово влево, `⌥→` вправо",
             setup: { $0.typeInput("echo hello world") },
             check: { $0.input == "echo hello world" && $0.cursor == 5 && $0.used("opt+left") }),
    Exercise(task: "Сотри последнее слово `Documents` одним сочетанием.",
             hint: "`Ctrl+W` стирает слово перед курсором",
             setup: { $0.typeInput("ls -la Documents") },
             check: { $0.input == "ls -la " && $0.used("ctrl+w") }),
    Exercise(task: "Передумал запускать опасную команду. Сотри всю строку целиком.",
             hint: "`Ctrl+U` стирает строку",
             setup: { $0.typeInput("rm -rf projects") },
             check: { $0.input.isEmpty && $0.used("ctrl+u") && $0.exists("~/projects") }),
    Exercise(task: "Команда следит за логом и не завершается. Прерви её.",
             hint: "`Ctrl+C` прерывает команду",
             setup: { $0.run("tail -f \(log)") },
             check: { $0.mode == .shell && $0.used("ctrl+c") }),
    Exercise(task: "Очисти экран терминала.",
             hint: "`Ctrl+L` (или `⌘K` в Terminal.app)",
             setup: { t in ["ls", "cat notes.txt", "pwd", "ls projects"].forEach { t.run($0) } },
             check: { $0.lines.isEmpty && ($0.used("ctrl+l") || $0.used("cmd+k")) }),
    Exercise(task: "Открой новую вкладку терминала.",
             hint: "`⌘T`",
             check: { $0.tabs.count == 2 && $0.used("cmd+t") }),
    Exercise(task: "Открыто три вкладки, ты в первой. Перейди на следующую.",
             hint: "`⌘⇧]` следующая вкладка, `⌘⇧[` предыдущая",
             setup: { $0.tabs = [TermTab(), TermTab(), TermTab()] },
             check: { $0.current == 1 && $0.used("cmd+shift+]") }),
    Exercise(task: "Ты в третьей вкладке. Перейди на предыдущую.",
             hint: "`⌘⇧[`",
             setup: { $0.tabs = [TermTab(), TermTab(), TermTab()]; $0.current = 2 },
             check: { $0.current == 1 && $0.used("cmd+shift+[") }),
    Exercise(task: "Закрой текущую вкладку.",
             hint: "`⌘W`",
             setup: { $0.tabs = [TermTab(), TermTab()]; $0.current = 1 },
             check: { $0.tabs.count == 1 && $0.used("cmd+w") }),
])

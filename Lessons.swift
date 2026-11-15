import Foundation

struct Exercise {
    let task: String
    let hint: String        // что набрать или нажать
    var note = ""           // пояснение под командой
    var setup: (Terminal) -> Void = { _ in }
    let check: (Terminal) -> Bool
}

struct Lesson {
    let id: String          // ключ для статистики, не переводится
    let title: String
    let subtitle: String
    let exercises: [Exercise]
    var level = 0           // 0 лёгкий, 1 средний, 2 сложный
}

// тренировка из трёх уровней
struct Course {
    let title: String
    let subtitle: String
    let levels: [Lesson]
}

func levelName(_ n: Int) -> String { [tr("Лёгкий", "Easy"), tr("Средний", "Medium"), tr("Сложный", "Hard")][n] }

// помощники для заготовок и проверок, пути считаются от домашней папки
extension Terminal {
    func node(_ p: String) -> FSNode? { fs.node(fs.absolute(p, cwd: FileSystem.home)) }
    func isDir(_ p: String) -> Bool { node(p)?.isDir == true }
    func isFile(_ p: String) -> Bool { node(p).map { !$0.isDir } ?? false }
    func exists(_ p: String) -> Bool { node(p) != nil }
    func text(_ p: String) -> String? { node(p).flatMap { $0.isDir ? nil : $0.content } }
    func at(_ p: String) -> Bool { cwd == fs.absolute(p, cwd: FileSystem.home) }
    func used(_ key: String) -> Bool { events.contains("key:" + key) }

    func ran(_ name: String) -> Bool { lastNames.contains(name) }
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

// пересобираются при каждом обращении, чтобы тексты были на текущем языке
var terminalLessons: [Lesson] { [navigation, files, viewing, editing, searching, hotkeys] }

var terminalCourses: [Course] {
    let more: [[[Exercise]]] = [
        [navigationMedium, navigationHard], [filesMedium, filesHard], [viewingMedium, viewingHard],
        [editingMedium, editingHard], [searchingMedium, searchingHard], [hotkeysMedium, hotkeysHard],
    ]
    return zip(terminalLessons, more).map { easy, rest in
        Course(title: easy.title, subtitle: easy.subtitle, levels: [easy] + rest.enumerated().map { n, ex in
            Lesson(id: easy.id + (n == 0 ? ".medium" : ".hard"), title: easy.title, subtitle: easy.subtitle, exercises: ex, level: n + 1)
        })
    }
}

private var navigation: Lesson { Lesson(id: "navigation", title: tr("Навигация", "Navigation"), subtitle: "pwd, ls, cd", exercises: [
    Exercise(task: tr("Узнай, в какой папке ты сейчас находишься.", "Find out which folder you are in."),
             hint: "pwd",
             note: tr("pwd = print working directory, показывает полный путь к текущей папке.", "pwd = print working directory, shows the full path to the current folder."),
             check: { $0.ran("pwd") }),
    Exercise(task: tr("Посмотри, что лежит в текущей папке.", "See what is in the current folder."),
             hint: "ls",
             check: { $0.ran("ls") && !$0.lastOutput.isEmpty }),
    Exercise(task: tr("Покажи все файлы в подробном виде, включая скрытые (их имена начинаются с точки).", "Show all files in long format, including hidden ones (their names start with a dot)."),
             hint: "ls -la",
             note: tr("`-l` подробный список, `-a` все файлы, включая скрытые. Флаги можно склеивать: `-la` = `-l -a`.", "`-l` long listing, `-a` all files, including hidden. Flags can be combined: `-la` = `-l -a`."),
             check: { $0.ran("ls") && $0.lastFlags.isSuperset(of: ["l", "a"]) }),
    Exercise(task: tr("Перейди в папку `projects`.", "Go to the `projects` folder."),
             hint: "cd projects",
             check: { $0.at("~/projects") }),
    Exercise(task: tr("Ты в `~/projects/app/src`. Поднимись на одну папку вверх.", "You are in `~/projects/app/src`. Go up one folder."),
             hint: "cd ..",
             note: tr("`..` означает папку уровнем выше.", "`..` means the parent folder."),
             setup: { $0.go("~/projects/app/src") },
             check: { $0.at("~/projects/app") }),
    Exercise(task: tr("Ты снова в `~/projects/app/src`. Поднимись сразу на две папки вверх одной командой.", "You are in `~/projects/app/src` again. Go up two folders with one command."),
             hint: "cd ../..",
             note: tr("Каждое `..` поднимает на одну папку вверх.", "Each `..` goes up one folder."),
             setup: { $0.go("~/projects/app/src") },
             check: { $0.at("~/projects") && $0.tabs[$0.current].oldpwd == FileSystem.home + "/projects/app/src" }),
    Exercise(task: tr("Перейди в корень диска.", "Go to the root of the disk."),
             hint: "cd /",
             note: tr("`/` — корень диска, самая верхняя папка.", "`/` is the root of the disk, the topmost folder."),
             check: { $0.at("/") }),
    Exercise(task: tr("Ты в `/usr/local`. Вернись в домашнюю папку.", "You are in `/usr/local`. Go back to your home folder."),
             hint: "cd",
             note: tr("`cd` без аргументов, `cd ~` и `cd $HOME` ведут в домашнюю папку.", "`cd` with no arguments, `cd ~` and `cd $HOME` all go to the home folder."),
             setup: { $0.go("/usr/local") },
             check: { $0.at("~") }),
    Exercise(task: tr("До этого ты был в `~/projects/app`, а сейчас в `~/Documents`. Вернись в предыдущую папку, не набирая путь.", "You were in `~/projects/app` and now you are in `~/Documents`. Go back to the previous folder without typing the path."),
             hint: "cd -",
             note: tr("`-` означает предыдущую папку.", "`-` means the previous folder."),
             setup: { $0.go("~/projects/app"); $0.go("~/Documents") },
             check: { $0.at("~/projects/app") && $0.lastCommand == "cd -" }),
]) }

private var files: Lesson { Lesson(id: "files", title: tr("Файлы и папки", "Files and folders"), subtitle: "mkdir, touch, cp, mv, rm", exercises: [
    Exercise(task: tr("Создай папку `homework`.", "Create a folder `homework`."),
             hint: "mkdir homework",
             note: tr("mkdir = make directory.", "mkdir = make directory."),
             check: { $0.isDir("~/homework") }),
    Exercise(task: tr("Создай одной командой вложенные папки `site/css/img`.", "Create nested folders `site/css/img` with one command."),
             hint: "mkdir -p site/css/img",
             note: tr("`-p` создаёт все недостающие папки на пути.", "`-p` creates all missing folders along the path."),
             check: { $0.isDir("~/site/css/img") }),
    Exercise(task: tr("Создай пустой файл `todo.txt`.", "Create an empty file `todo.txt`."),
             hint: "touch todo.txt",
             note: tr("`touch` создаёт пустой файл, если его нет.", "`touch` creates an empty file if it does not exist."),
             check: { $0.isFile("~/todo.txt") }),
    Exercise(task: tr("Сделай копию `notes.txt` под именем `notes-backup.txt`.", "Copy `notes.txt` to `notes-backup.txt`."),
             hint: "cp notes.txt notes-backup.txt",
             note: tr("Сначала что копировать, потом куда.", "First what to copy, then where."),
             check: { $0.text("~/notes-backup.txt") != nil && $0.text("~/notes-backup.txt") == $0.text("~/notes.txt") }),
    Exercise(task: tr("Скопируй папку `projects/app` целиком в `app-copy`.", "Copy the whole `projects/app` folder to `app-copy`."),
             hint: "cp -r projects/app app-copy",
             note: tr("`-r` (recursive) копирует папку со всем содержимым. Без него папки не копируются.", "`-r` (recursive) copies a folder with everything inside. Folders are not copied without it."),
             check: { $0.isFile("~/app-copy/README.md") && $0.isDir("~/projects/app") }),
    Exercise(task: tr("Переименуй `draft.txt` в `final.txt`.", "Rename `draft.txt` to `final.txt`."),
             hint: "mv draft.txt final.txt",
             note: tr("`mv` и переименовывает, и перемещает.", "`mv` both renames and moves."),
             check: { $0.isFile("~/final.txt") && !$0.exists("~/draft.txt") }),
    Exercise(task: tr("Перемести `photo.jpg` из `Downloads` в `Desktop`.", "Move `photo.jpg` from `Downloads` to `Desktop`."),
             hint: "mv Downloads/photo.jpg Desktop/",
             note: tr("Если в конце указана папка, файл переедет в неё с тем же именем.", "If the last argument is a folder, the file moves into it with the same name."),
             check: { $0.isFile("~/Desktop/photo.jpg") && !$0.exists("~/Downloads/photo.jpg") }),
    Exercise(task: tr("Удали файл `old.log`.", "Delete the file `old.log`."),
             hint: "rm old.log",
             note: tr("Удаление без корзины, вернуть файл нельзя.", "There is no trash bin, the file cannot be restored."),
             check: { !$0.exists("~/old.log") }),
    Exercise(task: tr("Удали папку `trash` вместе со всем, что в ней лежит.", "Delete the `trash` folder with everything in it."),
             hint: "rm -r trash",
             note: tr("`-r` удаляет папку со всем содержимым. `-f` ещё и не спрашивает подтверждений.", "`-r` deletes a folder with all its contents. `-f` also skips confirmations."),
             check: { !$0.exists("~/trash") }),
    Exercise(task: tr("Удали пустую папку `empty`.", "Delete the empty folder `empty`."),
             hint: "rmdir empty",
             note: tr("`rmdir` удаляет только пустые папки, это безопаснее `rm -r`.", "`rmdir` deletes only empty folders, which is safer than `rm -r`."),
             check: { !$0.exists("~/empty") }),
]) }

private var viewing: Lesson { Lesson(id: "viewing", title: tr("Просмотр файлов", "Viewing files"), subtitle: "cat, head, tail, less, wc", exercises: [
    Exercise(task: tr("Выведи содержимое файла `notes.txt`.", "Print the contents of `notes.txt`."),
             hint: "cat notes.txt",
             note: tr("`cat` выводит файл целиком.", "`cat` prints the whole file."),
             check: { $0.ran("cat") && $0.lastCommand.contains("notes.txt") && !$0.lastOutput.isEmpty }),
    Exercise(task: tr("Покажи первые 5 строк файла `\(log)`.", "Show the first 5 lines of `\(log)`."),
             hint: "head -n 5 \(log)",
             note: tr("`-n 5` — сколько строк показать. Без него `head` покажет 10.", "`-n 5` is how many lines to show. Without it `head` shows 10."),
             check: { $0.ran("head") && $0.lastOutput.count == 5 }),
    Exercise(task: tr("Покажи последние 3 строки файла `\(log)`.", "Show the last 3 lines of `\(log)`."),
             hint: "tail -n 3 \(log)",
             note: tr("`tail` показывает конец файла, `-n 3` — последние 3 строки.", "`tail` shows the end of a file, `-n 3` the last 3 lines."),
             check: { $0.ran("tail") && $0.lastOutput.count == 3 }),
    Exercise(task: tr("Посчитай, сколько строк в файле `\(log)`.", "Count the lines in `\(log)`."),
             hint: "wc -l \(log)",
             note: tr("wc = word count, `-l` считает только строки.", "wc = word count, `-l` counts only lines."),
             check: { $0.ran("wc") && $0.lastFlags.contains("l") && $0.lastOutput.first?.contains("20") == true }),
    Exercise(task: tr("Открой `\(log)` в `less`, найди слово `ERROR` и выйди.", "Open `\(log)` in `less`, find the word `ERROR` and quit."),
             hint: "less \(log)  →  /ERROR  →  Enter  →  q",
             note: tr("`/` начинает поиск, `n` переходит к следующему совпадению, `q` выходит.", "`/` starts a search, `n` jumps to the next match, `q` quits."),
             check: { $0.events.contains("less:search:ERROR") && $0.events.contains("less:quit") }),
    Exercise(task: tr("Запусти слежение за логом `\(log)`, а потом останови его.", "Start following the log `\(log)`, then stop it."),
             hint: "tail -f \(log)  →  Ctrl+C",
             note: tr("`-f` (follow) следит за файлом и показывает новые строки. `Ctrl+C` останавливает.", "`-f` (follow) watches the file and shows new lines. `Ctrl+C` stops it."),
             check: { $0.events.contains("tailf") && $0.events.contains("interrupt") }),
]) }

private let config = (1...30).map { i -> String in
    switch i {
    case 1: return "# server settings"
    case 22: return "port=8080"
    default: return "option\(i)=value\(i)"
    }
}.joined(separator: "\n") + "\n"

private var editing: Lesson { Lesson(id: "editing", title: tr("Редактирование текста", "Editing text"), subtitle: "echo, nano, vim", exercises: [
    Exercise(task: tr("Одной командой запиши в файл `hello.txt` строку `Hello`.", "Write the line `Hello` to `hello.txt` with one command."),
             hint: "echo \"Hello\" > hello.txt",
             note: tr("`>` записывает вывод команды в файл и стирает старое содержимое.", "`>` writes the command output to a file, replacing the old contents."),
             check: { $0.text("~/hello.txt")?.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello" }),
    Exercise(task: tr("Допиши в конец `hello.txt` строку `World`, не стирая то, что там уже есть.", "Append the line `World` to `hello.txt` without erasing what is already there."),
             hint: "echo \"World\" >> hello.txt",
             note: tr("`>>` дописывает в конец файла.", "`>>` appends to the end of a file."),
             setup: { $0.fs.put("~/hello.txt", "Hello\n") },
             check: { $0.text("~/hello.txt")?.trimmingCharacters(in: .whitespacesAndNewlines) == "Hello\nWorld" }),
    Exercise(task: tr("Открой `todo.txt` в nano, напиши `buy milk`, сохрани и выйди.", "Open `todo.txt` in nano, type `buy milk`, save and exit."),
             hint: "nano todo.txt  →  buy milk  →  Ctrl+O  →  Enter  →  Ctrl+X",
             note: tr("`Ctrl+O` сохраняет (Enter подтверждает имя файла), `Ctrl+X` выходит.", "`Ctrl+O` saves (Enter confirms the file name), `Ctrl+X` exits."),
             check: { $0.text("~/todo.txt")?.contains("buy milk") == true && $0.mode == .shell }),
    Exercise(task: tr("В `list.txt` удали строку `trash` целиком, сохрани и выйди.", "In `list.txt` delete the whole `trash` line, save and exit."),
             hint: "nano list.txt  →  ↓  →  Ctrl+K  →  Ctrl+O  →  Enter  →  Ctrl+X",
             note: tr("Стрелкой встань на строку `trash`. `Ctrl+K` вырезает строку целиком.", "Use the arrow to move to the `trash` line. `Ctrl+K` cuts the whole line."),
             setup: { $0.fs.put("~/list.txt", "apples\ntrash\npears\n") },
             check: { $0.text("~/list.txt") == "apples\npears\n" && $0.mode == .shell }),
    Exercise(task: tr("В длинном `config.txt` найди через поиск строку с `port` и замени `8080` на `3000`. Сохрани и выйди.", "In the long `config.txt` use search to find the line with `port` and replace `8080` with `3000`. Save and exit."),
             hint: "nano config.txt  →  Ctrl+W  →  port  →  Enter  →  Ctrl+E",
             note: tr("`Ctrl+W` ищет текст, `Ctrl+E` переносит в конец строки. Сотри `8080`, впиши `3000`, сохрани и выйди.", "`Ctrl+W` searches, `Ctrl+E` moves to the end of the line. Erase `8080`, type `3000`, save and exit."),
             setup: { $0.fs.put("~/config.txt", config) },
             check: {
                 let t = $0.text("~/config.txt") ?? ""
                 return t.contains("port=3000\n") && !t.contains("8080") && $0.events.contains("nano:search") && $0.mode == .shell
             }),
    Exercise(task: tr("В `steps.txt` строки перепутаны. Перенеси `2. save` на место перед `3. close`, сохрани и выйди.", "The lines in `steps.txt` are out of order. Move `2. save` before `3. close`, save and exit."),
             hint: "nano steps.txt  →  Ctrl+K  →  Ctrl+U",
             note: tr("Встань на `2. save` и вырежи её `Ctrl+K`. Потом встань на `3. close`: `Ctrl+U` вставит строку над ней.", "Go to `2. save` and cut it with `Ctrl+K`. Then go to `3. close`: `Ctrl+U` pastes the line above it."),
             setup: { $0.fs.put("~/steps.txt", "1. open\n3. close\n2. save\n") },
             check: { $0.text("~/steps.txt") == "1. open\n2. save\n3. close\n" && $0.mode == .shell }),
    Exercise(task: tr("Открой `vim.txt` в vim, напиши `hello`, сохрани и выйди.", "Open `vim.txt` in vim, type `hello`, save and exit."),
             hint: "vim vim.txt  →  i  →  hello  →  Esc  →  :wq  →  Enter",
             note: tr("`i` включает режим ввода, `Esc` выключает. `:wq` = write + quit.", "`i` enters insert mode, `Esc` leaves it. `:wq` = write + quit."),
             check: { $0.text("~/vim.txt")?.contains("hello") == true && $0.mode == .shell }),
    Exercise(task: tr("Открой `important.txt` в vim, напечатай что-нибудь, а потом выйди без сохранения.", "Open `important.txt` in vim, type something, then quit without saving."),
             hint: "vim important.txt  →  i  →  …  →  Esc  →  :q!  →  Enter",
             note: tr("`:q!` выходит без сохранения. Просто `:q` vim не даст, если файл изменён.", "`:q!` quits without saving. Plain `:q` is refused if the file was changed."),
             setup: { $0.fs.put("~/important.txt", "do not change this file\n") },
             check: {
                 $0.text("~/important.txt") == "do not change this file\n" && $0.events.contains("vim:modified")
                     && $0.events.contains("vim:forcequit") && $0.mode == .shell
             }),
]) }

private var searching: Lesson { Lesson(id: "searching", title: tr("Поиск", "Searching"), subtitle: "find, grep, |", exercises: [
    Exercise(task: tr("Найди, где лежит файл `utils.py`, начиная с домашней папки.", "Find where `utils.py` is, starting from the home folder."),
             hint: "find . -name utils.py",
             note: tr("`.` — искать с текущей папки, `-name` — по имени.", "`.` means search from the current folder, `-name` by name."),
             check: { $0.ran("find") && $0.lastOutput.contains { $0.hasSuffix("/utils.py") } }),
    Exercise(task: tr("Найди все файлы `.py` в папке `projects`.", "Find all `.py` files in `projects`."),
             hint: "find projects -name \"*.py\"",
             note: tr("`*` означает любые символы. Шаблон в кавычках, иначе zsh раскроет его сам.", "`*` means any characters. Quote the pattern, otherwise zsh expands it itself."),
             check: { $0.ran("find") && $0.lastOutput.count == 3 && $0.lastOutput.allSatisfy { $0.hasSuffix(".py") } }),
    Exercise(task: tr("Выведи строки с `ERROR` из `\(log)`.", "Print the lines with `ERROR` from `\(log)`."),
             hint: "grep ERROR \(log)",
             note: tr("`grep` выводит строки, где есть искомый текст.", "`grep` prints the lines that contain the text."),
             check: { $0.ran("grep") && $0.lastOutput.count == 3 }),
    Exercise(task: tr("Найди `TODO` во всех файлах папки `projects` и покажи номера строк.", "Find `TODO` in all files in `projects` and show line numbers."),
             hint: "grep -rn TODO projects",
             note: tr("`-r` ищет во всех вложенных файлах, `-n` показывает номера строк.", "`-r` searches all nested files, `-n` shows line numbers."),
             check: { $0.ran("grep") && $0.lastFlags.isSuperset(of: ["r", "n"]) && $0.lastOutput.count == 4 }),
    Exercise(task: tr("Найди в `\(log)` слово `warn` без учёта регистра.", "Find the word `warn` in `\(log)`, ignoring case."),
             hint: "grep -i warn \(log)",
             note: tr("`-i` (ignore case) не различает большие и маленькие буквы.", "`-i` (ignore case) treats upper and lower case the same."),
             check: { $0.ran("grep") && $0.lastFlags.contains("i") && $0.lastOutput.count == 4 }),
    Exercise(task: tr("Покажи в домашней папке только те имена, где есть `txt`: передай вывод `ls` в `grep`.", "In the home folder show only names that contain `txt`: pipe the output of `ls` to `grep`."),
             hint: "ls | grep txt",
             note: tr("`|` передаёт вывод одной команды на вход другой.", "`|` passes the output of one command to the input of another."),
             check: { $0.lastCommand.contains("|") && $0.lastOutput == ["draft.txt", "notes.txt"] }),
    Exercise(task: tr("Посчитай, сколько строк с `ERROR` в `\(log)`, используя `grep` и `wc`.", "Count the lines with `ERROR` in `\(log)` using `grep` and `wc`."),
             hint: "grep ERROR \(log) | wc -l",
             note: tr("`grep` находит строки, `wc -l` их считает.", "`grep` finds the lines, `wc -l` counts them."),
             check: { $0.ran("grep") && $0.ran("wc") && $0.lastOutput.first?.trimmingCharacters(in: .whitespaces) == "3" }),
]) }

private var hotkeys: Lesson { Lesson(id: "hotkeys", title: tr("Горячие клавиши", "Hotkeys"), subtitle: tr("Tab, история, курсор, вкладки", "Tab, history, cursor, tabs"), exercises: [
    Exercise(task: tr("Набери `cd Doc`, нажми `Tab`, чтобы терминал дописал имя папки, и выполни команду.", "Type `cd Doc`, press `Tab` to let the terminal complete the folder name, and run the command."),
             hint: "cd Doc  →  Tab  →  Enter",
             note: tr("`Tab` дописывает имена файлов и папок. Если вариантов несколько, покажет их список.", "`Tab` completes file and folder names. If there are several options, it lists them."),
             check: { $0.at("~/Documents") && $0.used("tab") }),
    Exercise(task: tr("Выполни ещё раз команду `ls -la ~/projects`, не набирая её: найди её в истории.", "Run `ls -la ~/projects` again without typing it: find it in the history."),
             hint: "↑  →  Enter",
             note: tr("`↑` листает историю назад, `↓` вперёд.", "`↑` goes back in history, `↓` forward."),
             setup: { $0.tabs[0].history = ["pwd", "ls -la ~/projects", "cat notes.txt"] },
             check: { $0.lastCommand == "ls -la ~/projects" && $0.lastTypedChars == 0 }),
    Exercise(task: tr("Где-то в истории есть команда с `grep`. Найди её поиском по истории и выполни.", "There is a `grep` command somewhere in the history. Find it with history search and run it."),
             hint: "Ctrl+R  →  grep  →  Enter",
             note: tr("Поиск по истории. Повторный `Ctrl+R` ищет более старую команду.", "History search. Pressing `Ctrl+R` again finds an older command."),
             setup: { $0.tabs[0].history = ["cd projects", "grep -rn TODO projects", "ls", "pwd", "cat notes.txt", "mkdir test", "ls -la"] },
             check: { $0.lastCommand.contains("grep") && $0.events.contains("usedsearch") }),
    Exercise(task: tr("Курсор в конце строки `s -la`. Прыгни в начало строки, допиши `l` и выполни `ls -la`.", "The cursor is at the end of `s -la`. Jump to the start of the line, add `l` and run `ls -la`."),
             hint: "Ctrl+A  →  l  →  Enter",
             note: tr("`Ctrl+A` переносит курсор в начало строки.", "`Ctrl+A` moves the cursor to the start of the line."),
             setup: { $0.typeInput("s -la") },
             check: { $0.lastCommand == "ls -la" && $0.used("ctrl+a") }),
    Exercise(task: tr("Курсор в начале строки `cat notes`. Прыгни в конец, допиши `.txt` и выполни.", "The cursor is at the start of `cat notes`. Jump to the end, add `.txt` and run it."),
             hint: "Ctrl+E  →  .txt  →  Enter",
             note: tr("`Ctrl+E` переносит курсор в конец строки.", "`Ctrl+E` moves the cursor to the end of the line."),
             setup: { $0.typeInput("cat notes", cursor: 0) },
             check: { $0.lastCommand == "cat notes.txt" && $0.used("ctrl+e") }),
    Exercise(task: tr("Поставь курсор на начало слова `hello`, двигаясь по словам.", "Put the cursor at the start of `hello`, moving word by word."),
             hint: "⌥←  ⌥←",
             note: tr("`⌥←` на слово влево, `⌥→` на слово вправо.", "`⌥←` one word left, `⌥→` one word right."),
             setup: { $0.typeInput("echo hello world") },
             check: { $0.input == "echo hello world" && $0.cursor == 5 && $0.used("opt+left") }),
    Exercise(task: tr("Сотри последнее слово `Documents` одним сочетанием.", "Erase the last word `Documents` with one shortcut."),
             hint: "Ctrl+W",
             note: tr("Стирает слово перед курсором. То же делает `⌥⌫`.", "Erases the word before the cursor. `⌥⌫` does the same."),
             setup: { $0.typeInput("ls -la Documents") },
             check: { $0.input == "ls -la " && ($0.used("ctrl+w") || $0.used("opt+backspace")) }),
    Exercise(task: tr("Передумал запускать опасную команду. Сотри всю строку целиком.", "You changed your mind about a dangerous command. Erase the whole line."),
             hint: "Ctrl+U",
             note: tr("Стирает всю строку.", "Erases the whole line."),
             setup: { $0.typeInput("rm -rf projects") },
             check: { $0.input.isEmpty && $0.used("ctrl+u") && $0.exists("~/projects") }),
    Exercise(task: tr("Команда следит за логом и не завершается. Прерви её.", "The command is following a log and never ends. Interrupt it."),
             hint: "Ctrl+C",
             note: tr("Прерывает работающую команду.", "Interrupts the running command."),
             setup: { $0.run("tail -f \(log)") },
             check: { $0.mode == .shell && $0.used("ctrl+c") }),
    Exercise(task: tr("Очисти экран терминала.", "Clear the terminal screen."),
             hint: "Ctrl+L",
             note: tr("Очищает экран. В Terminal.app то же делает `⌘K`.", "Clears the screen. In Terminal.app `⌘K` does the same."),
             setup: { t in ["ls", "cat notes.txt", "pwd", "ls projects"].forEach { t.run($0) } },
             check: { $0.lines.isEmpty && ($0.used("ctrl+l") || $0.used("cmd+k")) }),
    Exercise(task: tr("Открой новую вкладку терминала.", "Open a new terminal tab."),
             hint: "⌘T",
             check: { $0.tabs.count == 2 && $0.used("cmd+t") }),
    Exercise(task: tr("Открыто три вкладки, ты в первой. Перейди на следующую.", "Three tabs are open and you are in the first. Go to the next one."),
             hint: "⌘⇧]",
             note: tr("`⌘⇧]` следующая вкладка, `⌘⇧[` предыдущая.", "`⌘⇧]` next tab, `⌘⇧[` previous tab."),
             setup: { $0.tabs = [TermTab(), TermTab(), TermTab()] },
             check: { $0.current == 1 && $0.used("cmd+shift+]") }),
    Exercise(task: tr("Ты в третьей вкладке. Перейди на предыдущую.", "You are in the third tab. Go to the previous one."),
             hint: "⌘⇧[",
             setup: { $0.tabs = [TermTab(), TermTab(), TermTab()]; $0.current = 2 },
             check: { $0.current == 1 && $0.used("cmd+shift+[") }),
    Exercise(task: tr("Закрой текущую вкладку.", "Close the current tab."),
             hint: "⌘W",
             setup: { $0.tabs = [TermTab(), TermTab()]; $0.current = 1 },
             check: { $0.tabs.count == 1 && $0.used("cmd+w") }),
]) }

// MARK: средний и сложный уровни

private var logLines: [String] { FileSystem.appLog.split(separator: "\n").map(String.init) }

private var navigationMedium: [Exercise] { [
    Exercise(task: tr("Перейди сразу в `~/projects/app/src` одной командой.", "Go straight to `~/projects/app/src` with one command."),
             hint: "cd projects/app/src",
             note: tr("Путь можно указать целиком, через `/`.", "You can give the whole path, separated by `/`."),
             check: { $0.at("~/projects/app/src") && $0.tabs[$0.current].oldpwd == FileSystem.home }),
    Exercise(task: tr("Ты в `~/projects/app/src`. Перейди в `~/projects/site` одной командой по относительному пути.", "You are in `~/projects/app/src`. Go to `~/projects/site` with one command using a relative path."),
             hint: "cd ../../site",
             note: tr("Два раза вверх до `projects`, потом в `site`.", "Twice up to `projects`, then into `site`."),
             setup: { $0.go("~/projects/app/src") },
             check: { $0.at("~/projects/site") && $0.lastCommand.contains("..") && $0.tabs[$0.current].oldpwd == FileSystem.home + "/projects/app/src" }),
    Exercise(task: tr("Не переходя никуда, покажи подробный список файлов в `projects/app`.", "Without changing folders, show a long listing of `projects/app`."),
             hint: "ls -l projects/app",
             note: tr("`ls` принимает путь к папке, переходить в неё не нужно.", "`ls` takes a folder path, you don't need to go there."),
             check: { $0.ran("ls") && $0.lastFlags.contains("l") && $0.at("~") && $0.lastOutput.contains { $0.hasSuffix(" README.md") } }),
    Exercise(task: tr("Ты в корне диска. Не уходя отсюда, покажи скрытые файлы домашней папки.", "You are at the root. Without leaving it, show the hidden files of your home folder."),
             hint: "ls -a ~",
             note: tr("`~` — домашняя папка, её можно передать любой команде.", "`~` is the home folder, you can pass it to any command."),
             setup: { $0.go("/") },
             check: { $0.ran("ls") && $0.at("/") && $0.lastOutput.contains { $0.contains(".zshrc") } }),
    Exercise(task: tr("Загляни в `/Applications/Terminal.app`, а потом вернись туда, где был, не набирая путь.", "Look into `/Applications/Terminal.app`, then go back where you were without typing the path."),
             hint: "cd /Applications/Terminal.app  →  cd -",
             check: { $0.at("~") && $0.lastCommand == "cd -" && $0.tabs[$0.current].oldpwd == "/Applications/Terminal.app" }),
    Exercise(task: tr("Ты где-то в системных папках. Выясни, где именно, а потом вернись домой.", "You are somewhere in system folders. Find out where exactly, then go home."),
             hint: "pwd  →  cd",
             setup: { $0.go("/usr/local/bin") },
             check: { $0.events.contains("cmd:pwd") && $0.at("~") }),
] }

private var navigationHard: [Exercise] { [
    Exercise(task: tr("Одной строкой зайди в `projects`, покажи его содержимое и вернись обратно.", "In one line, go into `projects`, list it and come back."),
             hint: "cd projects && ls && cd ..",
             note: tr("`&&` запускает следующую команду, только если предыдущая прошла без ошибки. Можно и через `;`.", "`&&` runs the next command only if the previous one succeeded. `;` works too."),
             check: { $0.ran("cd") && $0.ran("ls") && $0.at("~") && $0.lastNames.count >= 3 }),
    Exercise(task: tr("Покажи содержимое `Desktop`, `Documents` и `Downloads` одной командой.", "List `Desktop`, `Documents` and `Downloads` with one command."),
             hint: "ls Desktop Documents Downloads",
             note: tr("Если передать `ls` несколько папок, он покажет каждую под своим заголовком.", "Given several folders, `ls` shows each one under its own header."),
             check: { t in t.ran("ls") && ["Desktop:", "Documents:", "Downloads:"].allSatisfy { t.lastOutput.contains($0) } }),
    Exercise(task: tr("Ты в `/tmp`. Вернись домой через переменную окружения с путём к домашней папке.", "You are in `/tmp`. Go home using the environment variable that holds the home path."),
             hint: "cd $HOME",
             note: tr("`$HOME` подставляет путь к домашней папке. Посмотреть его можно командой `echo $HOME`.", "`$HOME` expands to the home path. You can see it with `echo $HOME`."),
             setup: { $0.go("/tmp") },
             check: { $0.at("~") && $0.lastCommand.contains("HOME") }),
    Exercise(task: tr("Ты в корне диска. Не переходя никуда, покажи все `.txt` файлы домашней папки одной командой.", "You are at the root. Without changing folders, list all `.txt` files of your home folder with one command."),
             hint: "ls ~/*.txt",
             note: tr("`*` подставляет любые символы: `*.txt` — все имена, которые кончаются на `.txt`.", "`*` matches any characters: `*.txt` is every name ending with `.txt`."),
             setup: { $0.go("/") },
             check: { t in
                 let out = t.lastOutput.joined(separator: " ")
                 return t.ran("ls") && t.at("/") && out.contains("notes.txt") && out.contains("draft.txt") && !out.contains("projects")
             }),
    Exercise(task: tr("Ты в `/usr/local/bin`. Перейди в `~/Documents`, а оттуда в `~/projects/app/tests` по относительному пути.", "You are in `/usr/local/bin`. Go to `~/Documents`, and from there to `~/projects/app/tests` using a relative path."),
             hint: "cd ~/Documents  →  cd ../projects/app/tests",
             note: tr("Относительный путь начинается не с `/` и не с `~`, а от текущей папки.", "A relative path starts from the current folder, not with `/` or `~`."),
             setup: { $0.go("/usr/local/bin") },
             check: { $0.at("~/projects/app/tests") && $0.tabs[$0.current].oldpwd == FileSystem.home + "/Documents" && $0.lastCommand.contains("..") }),
] }

private var filesMedium: [Exercise] { [
    Exercise(task: tr("Создай одной командой три пустых файла: `a.txt`, `b.txt` и `c.txt`.", "Create three empty files `a.txt`, `b.txt` and `c.txt` with one command."),
             hint: "touch a.txt b.txt c.txt",
             note: tr("Почти все команды принимают сразу несколько имён.", "Most commands accept several names at once."),
             check: { t in ["a", "b", "c"].allSatisfy { t.isFile("~/\($0).txt") } && t.lastNames == ["touch"] }),
    Exercise(task: tr("Создай папку `backup` и одной командой `cp` скопируй в неё `notes.txt` и `draft.txt`.", "Create a `backup` folder and copy `notes.txt` and `draft.txt` into it with one `cp`."),
             hint: "mkdir backup  →  cp notes.txt draft.txt backup/",
             note: tr("Если файлов несколько, последней указывается папка, куда копировать.", "With several files, the last argument is the destination folder."),
             check: { $0.isFile("~/backup/notes.txt") && $0.isFile("~/backup/draft.txt") }),
    Exercise(task: tr("Перемести все `.tmp` файлы из `trash` в `Desktop`.", "Move all `.tmp` files from `trash` to `Desktop`."),
             hint: "mv trash/*.tmp Desktop/",
             note: tr("`*.tmp` подставит все файлы с таким окончанием.", "`*.tmp` expands to every file with that ending."),
             check: { t in ["a", "b", "c"].allSatisfy { t.isFile("~/Desktop/\($0).tmp") } && t.node("~/trash")?.children?.isEmpty == true }),
    Exercise(task: tr("Сделай копию скрытого файла `.zshrc` в папке `Documents` под именем `zshrc-backup`.", "Copy the hidden file `.zshrc` into `Documents` as `zshrc-backup`."),
             hint: "cp .zshrc Documents/zshrc-backup",
             note: tr("Скрытые файлы копируются так же, как обычные: точка — просто часть имени.", "Hidden files copy like any others: the dot is just part of the name."),
             check: { $0.text("~/Documents/zshrc-backup") != nil && $0.text("~/Documents/zshrc-backup") == $0.text("~/.zshrc") }),
    Exercise(task: tr("Переименуй папку `projects/site` в `projects/website`.", "Rename the folder `projects/site` to `projects/website`."),
             hint: "mv projects/site projects/website",
             note: tr("Папки переименовываются так же, как файлы, без `-r`.", "Folders are renamed like files, no `-r` needed."),
             check: { $0.isFile("~/projects/website/index.html") && !$0.exists("~/projects/site") }),
    Exercise(task: tr("Удали все файлы из `Downloads`, но саму папку оставь.", "Delete every file in `Downloads` but keep the folder."),
             hint: "rm Downloads/*",
             check: { $0.node("~/Downloads")?.children?.isEmpty == true }),
] }

private var filesHard: [Exercise] { [
    Exercise(task: tr("Одной строкой создай папку `release`, скопируй в неё папку `projects/app` и перейди в `release/app`.", "In one line, create `release`, copy `projects/app` into it and go to `release/app`."),
             hint: "mkdir release && cp -r projects/app release/ && cd release/app",
             check: { $0.isFile("~/release/app/main.py") && $0.at("~/release/app") && $0.lastNames.count >= 3 }),
    Exercise(task: tr("Сделай резервную копию всей папки `projects` в `~/backup/projects-2026`. Папки `backup` ещё нет.", "Back up the whole `projects` folder to `~/backup/projects-2026`. There is no `backup` folder yet."),
             hint: "mkdir backup  →  cp -r projects backup/projects-2026",
             note: tr("Сначала создай папку назначения: `cp` сам промежуточные папки не создаёт.", "Create the destination first: `cp` doesn't create missing folders."),
             check: { $0.isFile("~/backup/projects-2026/app/src/utils.py") }),
    Exercise(task: tr("Наведи порядок: перемести `notes.txt` и `draft.txt` в новую папку `Documents/texts`, а `old.log` удали.", "Tidy up: move `notes.txt` and `draft.txt` into a new folder `Documents/texts` and delete `old.log`."),
             hint: "mkdir Documents/texts  →  mv notes.txt draft.txt Documents/texts/  →  rm old.log",
             check: { $0.isFile("~/Documents/texts/notes.txt") && $0.isFile("~/Documents/texts/draft.txt") && !$0.exists("~/notes.txt") && !$0.exists("~/draft.txt") && !$0.exists("~/old.log") }),
    Exercise(task: tr("Ты в `~/projects/app/src`. Не уходя отсюда, создай файл `todo.md` в домашней папке.", "You are in `~/projects/app/src`. Without leaving, create `todo.md` in your home folder."),
             hint: "touch ~/todo.md",
             note: tr("Путь через `~` работает из любой папки.", "A path with `~` works from any folder."),
             setup: { $0.go("~/projects/app/src") },
             check: { $0.isFile("~/todo.md") && $0.at("~/projects/app/src") }),
    Exercise(task: tr("Удали папку `trash` командой, которая не умеет удалять непустые папки. Сначала очисти её.", "Delete `trash` with the command that refuses to delete non-empty folders. Empty it first."),
             hint: "rm trash/*  →  rmdir trash",
             note: tr("`rmdir` откажется удалять папку, в которой что-то есть: это защищает от ошибок.", "`rmdir` refuses to delete a folder with something inside: it protects from mistakes."),
             check: { !$0.exists("~/trash") && $0.events.contains("cmd:rmdir") }),
] }

private var viewingMedium: [Exercise] { [
    Exercise(task: tr("Выведи одной командой сразу два файла: `notes.txt` и `draft.txt`.", "Print both `notes.txt` and `draft.txt` with one command."),
             hint: "cat notes.txt draft.txt",
             note: tr("cat = concatenate, «склеить»: файлы выводятся один за другим.", "cat = concatenate: the files are printed one after another."),
             check: { t in
                 let first = { (p: String) in String(t.text(p)?.split(separator: "\n").first ?? "") }
                 return t.ran("cat") && t.lastOutput.contains(first("~/notes.txt")) && t.lastOutput.contains(first("~/draft.txt"))
             }),
    Exercise(task: tr("Посчитай, сколько слов в `notes.txt`.", "Count the words in `notes.txt`."),
             hint: "wc -w notes.txt",
             note: tr("`-w` считает слова, `-l` строки, `-c` байты.", "`-w` counts words, `-l` lines, `-c` bytes."),
             check: { t in
                 let words = t.text("~/notes.txt")?.split(whereSeparator: { $0 == " " || $0 == "\n" }).count ?? -1
                 return t.ran("wc") && t.lastFlags.contains("w") && t.lastOutput.first?.contains(" \(words) ") == true
             }),
    Exercise(task: tr("Покажи только последнюю строку лога `\(log)`.", "Show only the last line of `\(log)`."),
             hint: "tail -n 1 \(log)",
             check: { $0.ran("tail") && $0.lastOutput == [logLines.last!] }),
    Exercise(task: tr("Покажи строки лога с 5-й по 8-ю.", "Show lines 5 to 8 of the log."),
             hint: "head -n 8 \(log) | tail -n 4",
             note: tr("`head` берёт первые 8 строк, `tail` оставляет из них последние 4.", "`head` takes the first 8 lines, `tail` keeps the last 4 of them."),
             check: { $0.lastOutput == Array(logLines[4..<8]) }),
    Exercise(task: tr("Открой лог в `less`, перейди в самый конец файла и выйди.", "Open the log in `less`, jump to the very end and quit."),
             hint: "less \(log)  →  G  →  q",
             note: tr("`G` — в конец, `g` — в начало, пробел — на страницу вниз.", "`G` goes to the end, `g` to the start, space scrolls a page down."),
             check: { $0.events.contains("less:end") && $0.events.contains("less:quit") }),
    Exercise(task: tr("В `less` найди второе по счёту `ERROR` в логе и выйди.", "In `less`, find the second `ERROR` in the log and quit."),
             hint: "less \(log)  →  /ERROR  →  Enter  →  n  →  q",
             note: tr("`n` переходит к следующему совпадению, `N` — к предыдущему.", "`n` jumps to the next match, `N` to the previous one."),
             check: { $0.events.contains("less:search:ERROR") && $0.events.contains("less:next") && $0.events.contains("less:quit") }),
] }

private var viewingHard: [Exercise] { [
    Exercise(task: tr("Посчитай, сколько файлов и папок в домашней папке, не считая скрытых. Ответ — одно число.", "Count the files and folders in your home folder, not counting hidden ones. The answer is one number."),
             hint: "ls | wc -l",
             note: tr("Когда вывод `ls` уходит в `|`, он пишет по одному имени на строку.", "When `ls` output goes into `|`, it prints one name per line."),
             check: { $0.ran("ls") && $0.lastOutput.first?.trimmingCharacters(in: .whitespaces) == "9" }),
    Exercise(task: tr("Сохрани первые 3 строки лога в файл `top.txt`.", "Save the first 3 lines of the log to `top.txt`."),
             hint: "head -n 3 \(log) > top.txt",
             check: { $0.text("~/top.txt") == logLines.prefix(3).joined(separator: "\n") + "\n" }),
    Exercise(task: tr("Покажи 10-ю строку лога, и только её.", "Show the 10th line of the log and nothing else."),
             hint: "head -n 10 \(log) | tail -n 1",
             check: { $0.lastOutput == [logLines[9]] }),
    Exercise(task: tr("Одной командой посчитай, сколько строк в `notes.txt` и `draft.txt` вместе.", "With one command, count the lines in `notes.txt` and `draft.txt` together."),
             hint: "wc -l notes.txt draft.txt",
             note: tr("С несколькими файлами `wc` в конце пишет строку `total` с суммой. Можно и `cat notes.txt draft.txt | wc -l`.", "With several files `wc` adds a `total` line. `cat notes.txt draft.txt | wc -l` works too."),
             check: { $0.ran("wc") && $0.lastOutput.contains { $0.trimmingCharacters(in: .whitespaces) == "5" || $0.hasSuffix(" total") && $0.contains(" 5 ") } }),
    Exercise(task: tr("Запусти слежение за логом, останови его и сразу очисти экран.", "Follow the log, stop it and clear the screen right away."),
             hint: "tail -f \(log)  →  Ctrl+C  →  Ctrl+L",
             check: { $0.events.contains("tailf") && $0.events.contains("interrupt") && $0.lines.isEmpty }),
] }

private let serverConfig = (1...25).map { i -> String in
    switch i {
    case 1: return "# server"
    case 8: return "debug=true"
    case 19: return "port=8080"
    default: return "key\(i)=value\(i)"
    }
}.joined(separator: "\n") + "\n"

private var editingMedium: [Exercise] { [
    Exercise(task: tr("С помощью `echo` создай файл `list.txt` из трёх строк: `one`, `two`, `three`.", "Using `echo`, create `list.txt` with three lines: `one`, `two`, `three`."),
             hint: "echo one > list.txt  →  echo two >> list.txt  →  echo three >> list.txt",
             note: tr("Первая команда с `>` создаёт файл, остальные с `>>` дописывают.", "The first command with `>` creates the file, the others with `>>` append."),
             check: { $0.text("~/list.txt") == "one\ntwo\nthree\n" }),
    Exercise(task: tr("Очисти файл `hello.txt` одной командой: файл должен остаться, но стать пустым.", "Empty `hello.txt` with one command: the file must stay, but be empty."),
             hint: "> hello.txt",
             note: tr("Перенаправление без команды записывает в файл пустоту. Ещё вариант: `echo -n > hello.txt`.", "A redirect with no command writes nothing to the file. Another way: `echo -n > hello.txt`."),
             setup: { $0.fs.put("~/hello.txt", "Hello\nWorld\n") },
             check: { $0.text("~/hello.txt") == "" }),
    Exercise(task: tr("В nano допиши в самый конец `notes.txt` строку `- finish KeyDojo`. Сохрани и выйди.", "In nano, add the line `- finish KeyDojo` to the very end of `notes.txt`. Save and quit."),
             hint: tr("nano notes.txt  →  ↓ до пустой строки  →  - finish KeyDojo  →  Ctrl+O  →  Enter  →  Ctrl+X", "nano notes.txt  →  ↓ to the empty line  →  - finish KeyDojo  →  Ctrl+O  →  Enter  →  Ctrl+X"),
             check: { t in
                 let original = FileSystem.standard().node(FileSystem.home + "/notes.txt")!.content
                 return t.text("~/notes.txt") == original + "- finish KeyDojo\n" && t.mode == .shell
             }),
    Exercise(task: tr("В nano перенеси первые две строки `steps.txt` в конец файла. Сохрани и выйди.", "In nano, move the first two lines of `steps.txt` to the end. Save and quit."),
             hint: "nano steps.txt  →  Ctrl+K  →  Ctrl+K  →  ↓  →  Ctrl+U  →  Ctrl+O  →  Enter  →  Ctrl+X",
             note: tr("Несколько `Ctrl+K` подряд вырезают строки вместе, и `Ctrl+U` вставит их все разом.", "Several `Ctrl+K` in a row cut lines together, and `Ctrl+U` pastes them all at once."),
             setup: { $0.fs.put("~/steps.txt", "a\nb\nc\n") },
             check: { $0.text("~/steps.txt") == "c\na\nb\n" && $0.mode == .shell }),
    Exercise(task: tr("В vim удали строку `trash` из `list.txt`, сохрани и выйди.", "In vim, delete the `trash` line from `list.txt`, save and quit."),
             hint: "vim list.txt  →  j  →  dd  →  :wq  →  Enter",
             note: tr("`j` — строка вниз, `k` — вверх, `dd` удаляет строку целиком.", "`j` moves down, `k` up, `dd` deletes the whole line."),
             setup: { $0.fs.put("~/list.txt", "apples\ntrash\npears\n") },
             check: { $0.text("~/list.txt") == "apples\npears\n" && $0.mode == .shell }),
    Exercise(task: tr("В vim добавь строку `pears` сразу после `apples`, сохрани и выйди.", "In vim, add a `pears` line right after `apples`, save and quit."),
             hint: "vim list.txt  →  o  →  pears  →  Esc  →  :wq  →  Enter",
             note: tr("`o` создаёт новую строку под курсором и включает ввод, `O` — над курсором.", "`o` opens a new line below the cursor in insert mode, `O` above it."),
             setup: { $0.fs.put("~/list.txt", "apples\nbananas\n") },
             check: { $0.text("~/list.txt") == "apples\npears\nbananas\n" && $0.mode == .shell }),
] }

private var editingHard: [Exercise] { [
    Exercise(task: tr("В `config.txt` поменяй `debug=true` на `debug=false`, а `port=8080` на `port=3000`. Сохрани и выйди.", "In `config.txt`, change `debug=true` to `debug=false` and `port=8080` to `port=3000`. Save and quit."),
             hint: "nano config.txt  →  Ctrl+W  →  debug  →  Enter  →  …  →  Ctrl+W  →  port  →  Enter  →  …",
             note: tr("Ищи каждую строку через `Ctrl+W`, а не стрелками.", "Find each line with `Ctrl+W`, not with arrows."),
             setup: { $0.fs.put("~/config.txt", serverConfig) },
             check: {
                 $0.text("~/config.txt") == serverConfig.replacingOccurrences(of: "debug=true", with: "debug=false").replacingOccurrences(of: "port=8080", with: "port=3000")
                     && $0.mode == .shell
             }),
    Exercise(task: tr("Открой `config.txt` в vim, добавь в самый конец строку `timeout=30`, сохрани и выйди.", "Open `config.txt` in vim, add `timeout=30` as the last line, save and quit."),
             hint: "vim config.txt  →  G  →  o  →  timeout=30  →  Esc  →  :wq  →  Enter",
             note: tr("`G` переносит в конец файла.", "`G` jumps to the end of the file."),
             setup: { $0.fs.put("~/config.txt", serverConfig) },
             check: { $0.text("~/config.txt") == serverConfig + "timeout=30\n" && $0.mode == .shell }),
    Exercise(task: tr("Открой `config.txt` в vim, уйди в конец файла, вернись в начало и удали первую строку-комментарий. Сохрани и выйди.", "Open `config.txt` in vim, go to the end, back to the start and delete the first comment line. Save and quit."),
             hint: "vim config.txt  →  G  →  gg  →  dd  →  :wq  →  Enter",
             note: tr("`gg` — в начало файла.", "`gg` jumps to the start of the file."),
             setup: { $0.fs.put("~/config.txt", serverConfig) },
             check: {
                 $0.text("~/config.txt") == String(serverConfig.drop { $0 != "\n" }.dropFirst())
                     && $0.events.contains("vim:G") && $0.events.contains("vim:gg") && $0.mode == .shell
             }),
    Exercise(task: tr("Объедини `a.txt` и `b.txt` в новый файл `ab.txt` одной командой.", "Join `a.txt` and `b.txt` into a new file `ab.txt` with one command."),
             hint: "cat a.txt b.txt > ab.txt",
             setup: { $0.fs.put("~/a.txt", "A\n"); $0.fs.put("~/b.txt", "B\n") },
             check: { $0.text("~/ab.txt") == "A\nB\n" }),
    Exercise(task: tr("Открой `notes.txt` в nano и сохрани его копию под именем `notes2.txt`, не меняя оригинал.", "Open `notes.txt` in nano and save a copy as `notes2.txt` without changing the original."),
             hint: tr("nano notes.txt  →  Ctrl+O  →  сотри имя  →  notes2.txt  →  Enter  →  Ctrl+X", "nano notes.txt  →  Ctrl+O  →  erase the name  →  notes2.txt  →  Enter  →  Ctrl+X"),
             note: tr("В строке `File Name to Write` можно вписать другое имя.", "You can type a different name in the `File Name to Write` prompt."),
             check: { t in
                 let original = FileSystem.standard().node(FileSystem.home + "/notes.txt")!.content
                 return t.text("~/notes2.txt") == original && t.text("~/notes.txt") == original && t.mode == .shell
             }),
] }

private var searchingMedium: [Exercise] { [
    Exercise(task: tr("Найди все папки (не файлы) внутри `projects`.", "Find all folders (not files) inside `projects`."),
             hint: "find projects -type d",
             note: tr("`-type d` — только папки, `-type f` — только файлы.", "`-type d` means folders only, `-type f` files only."),
             check: { $0.ran("find") && $0.lastOutput.count == 5 && $0.lastOutput.allSatisfy { !$0.contains(".") } }),
    Exercise(task: tr("Найди все `.txt` файлы в домашней папке, включая вложенные папки.", "Find all `.txt` files in your home folder, including subfolders."),
             hint: "find . -name \"*.txt\"",
             check: { $0.ran("find") && $0.lastOutput.count == 4 && $0.lastOutput.allSatisfy { $0.hasSuffix(".txt") } }),
    Exercise(task: tr("Выведи строки лога, в которых нет `INFO`.", "Print the log lines that do not contain `INFO`."),
             hint: "grep -v INFO \(log)",
             note: tr("`-v` (invert) показывает строки, где совпадения нет.", "`-v` (invert) shows lines that do not match."),
             check: { $0.ran("grep") && $0.lastOutput.count == 6 && !$0.lastOutput.contains { $0.contains("INFO") } }),
    Exercise(task: tr("Узнай, в каких файлах папки `projects` встречается `greet`. Нужны только имена файлов.", "Find which files in `projects` contain `greet`. File names only."),
             hint: "grep -rl greet projects",
             note: tr("`-l` выводит только имена файлов, где есть совпадение.", "`-l` prints only the names of matching files."),
             check: { $0.ran("grep") && $0.lastOutput.count == 3 && $0.lastOutput.allSatisfy { $0.hasSuffix(".py") } }),
    Exercise(task: tr("Посчитай, сколько в логе строк с запросами `GET`.", "Count the log lines with `GET` requests."),
             hint: "grep -c GET \(log)",
             note: tr("`-c` выводит число совпавших строк. Можно и `grep GET \(log) | wc -l`.", "`-c` prints the number of matching lines. `grep GET \(log) | wc -l` works too."),
             check: { $0.ran("grep") && $0.lastOutput.last?.trimmingCharacters(in: .whitespaces) == "7" }),
    Exercise(task: tr("Найди в домашней папке все файлы, в имени которых есть `test`.", "Find every file in your home folder with `test` in its name."),
             hint: "find . -name \"*test*\"",
             check: { $0.ran("find") && $0.lastOutput.contains { $0.hasSuffix("test_utils.py") } }),
] }

private var searchingHard: [Exercise] { [
    Exercise(task: tr("Найди строки с `ERROR` в логе и сохрани их в файл `errors.txt`.", "Find the `ERROR` lines in the log and save them to `errors.txt`."),
             hint: "grep ERROR \(log) > errors.txt",
             check: { t in
                 let l = t.text("~/errors.txt")?.split(separator: "\n") ?? []
                 return l.count == 3 && l.allSatisfy { $0.contains("ERROR") }
             }),
    Exercise(task: tr("Одной командой `grep` выведи строки лога, где есть `ERROR` или `WARN`.", "With a single `grep`, print the log lines containing `ERROR` or `WARN`."),
             hint: "grep -E \"ERROR|WARN\" \(log)",
             note: tr("`-E` включает расширенные шаблоны: `|` внутри означает «или». Шаблон в кавычках, иначе `|` станет конвейером.", "`-E` enables extended patterns: `|` inside means “or”. Quote the pattern, otherwise `|` becomes a pipe."),
             check: { $0.ran("grep") && $0.lastNames.count == 1 && $0.lastOutput.count == 6 }),
    Exercise(task: tr("Сколько `.py` файлов в папке `projects`? Ответ — одно число.", "How many `.py` files are in `projects`? The answer is one number."),
             hint: "find projects -name \"*.py\" | wc -l",
             check: { $0.ran("find") && $0.lastOutput.first?.trimmingCharacters(in: .whitespaces) == "3" }),
    Exercise(task: tr("Найди все `TODO` в папке `projects`, кроме тех, что в `.css` файлах.", "Find every `TODO` in `projects` except those in `.css` files."),
             hint: "grep -rn TODO projects | grep -v css",
             note: tr("Второй `grep -v` отбрасывает лишние строки из вывода первого.", "The second `grep -v` drops unwanted lines from the first one's output."),
             check: { $0.lastOutput.count == 3 && $0.lastOutput.allSatisfy { $0.contains("TODO") && !$0.contains(".css") } }),
    Exercise(task: tr("Найди во всей домашней папке файлы со словом `hello` в любом регистре. Только имена файлов.", "Find the files anywhere in your home folder containing `hello` in any case. File names only."),
             hint: "grep -ril hello .",
             note: tr("Флаги можно склеивать: `-r` рекурсивно, `-i` без учёта регистра, `-l` только имена.", "Flags can be combined: `-r` recursive, `-i` ignore case, `-l` names only."),
             check: { $0.ran("grep") && $0.lastFlags.isSuperset(of: ["i", "l"]) && $0.lastOutput.count == 3 }),
] }

private var hotkeysMedium: [Exercise] { [
    Exercise(task: tr("Перейди в `projects/app/src`, набирая только первые буквы каждой папки и дописывая остальное через `Tab`.", "Go to `projects/app/src` typing only the first letters of each folder and completing the rest with `Tab`."),
             hint: "cd pr  →  Tab  →  ap  →  Tab  →  sr  →  Tab  →  Enter",
             check: { $0.at("~/projects/app/src") && $0.used("tab") && $0.lastTypedChars < 15 }),
    Exercise(task: tr("Курсор в конце строки. Сотри слово `notes.txt`, не трогая `draft.txt`.", "The cursor is at the end. Delete the word `notes.txt` without touching `draft.txt`."),
             hint: "⌥←  →  Ctrl+W",
             note: tr("Сначала встань перед `draft.txt`, потом сотри слово слева от курсора.", "First move before `draft.txt`, then delete the word to the left of the cursor."),
             setup: { $0.typeInput("cat notes.txt draft.txt") },
             check: { $0.input == "cat draft.txt" && $0.used("opt+left") }),
    Exercise(task: tr("Сотри всё от курсора до конца строки.", "Delete everything from the cursor to the end of the line."),
             hint: "Ctrl+K",
             note: tr("`Ctrl+K` стирает справа от курсора, `Ctrl+U` — всю строку.", "`Ctrl+K` deletes to the right of the cursor, `Ctrl+U` the whole line."),
             setup: { $0.typeInput("ls -la # extra comment", cursor: 6) },
             check: { $0.input == "ls -la" && $0.used("ctrl+k") }),
    Exercise(task: tr("Найди в истории команду с `mkdir`, допиши к имени папки `2` и выполни.", "Find the `mkdir` command in history, append `2` to the folder name and run it."),
             hint: "Ctrl+R  →  mkdir  →  Esc  →  2  →  Enter",
             note: tr("`Esc` или стрелка забирает найденную команду в строку, чтобы её поправить.", "`Esc` or an arrow puts the found command on the line so you can edit it."),
             setup: { $0.tabs[0].history = ["ls", "mkdir test", "cd test", "pwd"] },
             check: { $0.lastCommand == "mkdir test2" && $0.events.contains("usedsearch") }),
    Exercise(task: tr("Открой новую вкладку, перейди в ней в `projects` и вернись в первую вкладку.", "Open a new tab, go to `projects` in it and switch back to the first tab."),
             hint: "⌘T  →  cd projects  →  ⌘⇧[",
             check: { $0.tabs.count == 2 && $0.current == 0 && $0.tabs[1].cwd == FileSystem.home + "/projects" }),
    Exercise(task: tr("Повтори предыдущую команду, добавив в конец `| wc -l`.", "Repeat the previous command with `| wc -l` added at the end."),
             hint: "↑  →  | wc -l  →  Enter",
             setup: { $0.tabs[0].history = ["cd projects", "ls projects/app"] },
             check: { $0.lastCommand == "ls projects/app | wc -l" && $0.lastTypedChars <= 8 }),
] }

private var hotkeysHard: [Exercise] { [
    Exercise(task: tr("Удали из строки слова `two` и `three`, ничего не набирая заново.", "Delete the words `two` and `three` from the line without retyping anything."),
             hint: "⌥←  →  Ctrl+W  →  Ctrl+W",
             note: tr("Встань перед `four`, затем стирай слова слева от курсора.", "Move before `four`, then delete the words to the left of the cursor."),
             setup: { $0.typeInput("echo one two three four") },
             check: { $0.input == "echo one four" && ($0.used("ctrl+w") || $0.used("opt+backspace")) }),
    Exercise(task: tr("Выполни из истории подряд две команды: сначала `cd projects`, потом `ls -la`. Ничего не набирай.", "Run two commands from history in a row: first `cd projects`, then `ls -la`. Don't type anything."),
             hint: "↑ ↑ ↑  →  Enter  →  ↑ ↑ ↑  →  Enter",
             note: tr("После каждой команды история листается заново с конца. Можно и через `Ctrl+R`.", "After each command history starts again from the end. `Ctrl+R` works too."),
             setup: { $0.tabs[0].history = ["cd projects", "ls -la", "pwd"] },
             check: { $0.at("~/projects") && $0.lastCommand == "ls -la" && $0.lastTypedChars == 0 && $0.events.contains("cmd:cd") }),
    Exercise(task: tr("Открыто четыре вкладки. Закрой все, кроме той, где открыта папка `projects`.", "Four tabs are open. Close all of them except the one in `projects`."),
             hint: "⌘⇧[ / ⌘⇧]  →  ⌘W  …",
             note: tr("Переключайся на ненужные вкладки и закрывай их. Папка каждой вкладки видна в заголовке.", "Switch to the tabs you don't need and close them. Each tab's folder is shown in its title."),
             setup: { t in
                 t.tabs = [TermTab(), TermTab(cwd: FileSystem.home + "/Documents"), TermTab(cwd: FileSystem.home + "/projects"), TermTab(cwd: "/tmp")]
                 t.current = 2
             },
             check: { $0.tabs.count == 1 && $0.cwd == FileSystem.home + "/projects" }),
    Exercise(task: tr("Запусти слежение за логом, прерви его, очисти экран и запусти ту же команду снова из истории.", "Follow the log, interrupt it, clear the screen and run the same command again from history."),
             hint: "tail -f \(log)  →  Ctrl+C  →  Ctrl+L  →  ↑  →  Enter",
             check: { $0.used("ctrl+c") && $0.used("ctrl+l") && $0.mode == .running && $0.lastTypedChars == 0 && $0.events.contains("interrupt") }),
    Exercise(task: tr("Замени в команде `TODO` на `FIXME`, перемещаясь по словам, и выполни её.", "Replace `TODO` with `FIXME` in the command, moving by words, and run it."),
             hint: tr("⌥←  →  Ctrl+W  →  FIXME  →  пробел  →  Enter", "⌥←  →  Ctrl+W  →  FIXME  →  space  →  Enter"),
             note: tr("`Ctrl+W` стирает слово вместе с пробелом после него, поэтому пробел нужно вернуть.", "`Ctrl+W` deletes the word along with the space after it, so add the space back."),
             setup: { $0.typeInput("grep -rn TODO projects") },
             check: { $0.lastCommand == "grep -rn FIXME projects" && $0.used("opt+left") }),
] }

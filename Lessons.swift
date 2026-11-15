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

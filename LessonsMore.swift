import Foundation

// темы: git, права доступа, процессы, архивы

extension Terminal {
    // выполняет команды заготовки и прячет их с экрана и из истории
    func quiet(_ cmds: String...) {
        for c in cmds { run(c) }
        lines = []
        tabs[current].history = []
    }

    func perm(_ p: String) -> Int? { node(p)?.mode }
    func setMode(_ p: String, _ m: Int) { node(p)?.mode = m }
    func archiveFiles(_ p: String) -> [String] { node(p)?.archive?.files ?? [] }
    var app: GitRepo? { repo(at: FileSystem.home + "/projects/app") }
    func headFile(_ r: GitRepo?, _ k: String) -> String? { r?.headTree[k] }
    func headMessage(_ r: GitRepo?) -> String? { r.flatMap { r in r.headCommit.map { r.commits[$0].message } } }
    func clean(_ r: GitRepo) -> Bool {
        let c = gitChanges(r)
        return c.staged.isEmpty && c.unstaged.isEmpty && c.untracked.isEmpty
    }
    var first: String { lastOutput.first?.trimmingCharacters(in: .whitespaces) ?? "" }
}

private let readme = "~/projects/app/README.md"

// репозиторий projects/app с тремя коммитами, терминал внутри
private func appRepo(_ t: Terminal) {
    t.gitRepo("projects/app", commits: ["init project", "add utils", "add tests"])
    t.go("projects/app")
}

private func editReadme(_ t: Terminal) {
    t.fs.write(t.fs.absolute(readme, cwd: FileSystem.home), tr("# app\n\nИнструкция по запуску: python3 main.py\n", "# app\n\nHow to run: python3 main.py\n"))
}

// MARK: git

var gitLesson: Lesson { Lesson(id: "git", title: "Git", subtitle: "init, status, add, commit, branch", exercises: [
    Exercise(task: tr("Сделай папку `projects/site` git-репозиторием. Ты уже в ней.", "Turn `projects/site` into a git repository. You are already in it."),
             hint: "git init",
             note: tr("`git init` создаёт скрытую папку `.git`, где git хранит историю.", "`git init` creates a hidden `.git` folder where git keeps the history."),
             setup: { $0.go("projects/site") },
             check: { $0.repo(at: FileSystem.home + "/projects/site") != nil }),
    Exercise(task: tr("Проверь состояние репозитория: что изменено и что ещё не добавлено.", "Check the repository state: what changed and what is not added yet."),
             hint: "git status",
             setup: { appRepo($0); editReadme($0); $0.fs.put("~/projects/app/todo.txt", "") },
             check: { $0.events.contains("git:status") }),
    Exercise(task: tr("Добавь изменённый `README.md` в индекс, чтобы он попал в следующий коммит.", "Stage the changed `README.md` so it goes into the next commit."),
             hint: "git add README.md",
             note: tr("Индекс — то, что войдёт в коммит. `git add` кладёт туда текущую версию файла.", "The index (staging area) is what goes into the commit. `git add` puts the current version of the file there."),
             setup: { appRepo($0); editReadme($0) },
             check: { t in t.app?.index["README.md"] == t.text(readme) }),
    Exercise(task: tr("`README.md` уже в индексе. Сделай коммит с сообщением `fix readme`.", "`README.md` is already staged. Commit with the message `fix readme`."),
             hint: "git commit -m \"fix readme\"",
             note: tr("`-m` — сообщение коммита. Без него git откроет редактор.", "`-m` is the commit message. Without it git opens an editor."),
             setup: { t in appRepo(t); editReadme(t); t.quiet("git add README.md") },
             check: { $0.headMessage($0.app) == "fix readme" }),
    Exercise(task: tr("Добавь в индекс сразу все изменения: и изменённые, и новые файлы.", "Stage all changes at once: both modified and new files."),
             hint: "git add .",
             note: tr("`.` — текущая папка со всем содержимым. Можно и `git add -A`.", "`.` is the current folder with everything in it. `git add -A` works too."),
             setup: { appRepo($0); editReadme($0); $0.fs.put("~/projects/app/todo.txt", "tests\n") },
             check: { t in
                 guard let r = t.app else { return false }
                 let c = t.gitChanges(r)
                 return c.unstaged.isEmpty && c.untracked.isEmpty && c.staged.count == 2
             }),
    Exercise(task: tr("Посмотри историю коммитов.", "Look at the commit history."),
             hint: "git log",
             setup: appRepo,
             check: { $0.events.contains("git:log") && !$0.lastOutput.isEmpty }),
    Exercise(task: tr("Покажи историю кратко: по одной строке на коммит.", "Show the history briefly: one line per commit."),
             hint: "git log --oneline",
             setup: appRepo,
             check: { $0.ran("git") && $0.lastOutput.count == 3 && $0.lastOutput[0].hasSuffix("add tests") }),
    Exercise(task: tr("Создай ветку `feature`.", "Create a branch called `feature`."),
             hint: "git branch feature",
             note: tr("Ветка создаётся от текущего коммита, но ты остаёшься на прежней.", "The branch starts from the current commit, but you stay on the old one."),
             setup: appRepo,
             check: { $0.app?.branches["feature"] != nil }),
    Exercise(task: tr("Перейди на ветку `feature`.", "Switch to the `feature` branch."),
             hint: "git switch feature",
             note: tr("Старый вариант той же команды — `git checkout feature`.", "The older form of the same command is `git checkout feature`."),
             setup: { t in appRepo(t); t.quiet("git branch feature") },
             check: { $0.app?.head == "feature" }),
]) }

var gitMedium: [Exercise] { [
    Exercise(task: tr("Создай ветку `fix` и сразу перейди на неё одной командой.", "Create a branch `fix` and switch to it with one command."),
             hint: "git switch -c fix",
             note: tr("`-c` (create) создаёт ветку. Старый вариант — `git checkout -b fix`.", "`-c` (create) makes the branch. The older form is `git checkout -b fix`."),
             setup: appRepo,
             check: { $0.app?.head == "fix" && !$0.events.contains("git:branch") }),
    Exercise(task: tr("Посмотри, что именно поменялось в файлах, но ещё не добавлено в индекс.", "See exactly what changed in the files but is not staged yet."),
             hint: "git diff",
             note: tr("Строки с `-` удалены, с `+` добавлены.", "Lines with `-` were removed, lines with `+` were added."),
             setup: { appRepo($0); editReadme($0) },
             check: { $0.events.contains("git:diff") && $0.lastOutput.contains { $0.hasPrefix("+") && !$0.hasPrefix("+++") } }),
    Exercise(task: tr("`main.py` случайно попал в индекс. Убери его оттуда, но оставь изменения в самом файле.", "`main.py` got staged by accident. Unstage it but keep the changes in the file."),
             hint: "git restore --staged main.py",
             setup: { t in appRepo(t); t.fs.write(FileSystem.home + "/projects/app/main.py", "print('debug')\n"); t.quiet("git add main.py") },
             check: { t in
                 guard let r = t.app else { return false }
                 return r.index["main.py"] == r.headTree["main.py"] && t.text("~/projects/app/main.py") != r.headTree["main.py"]
             }),
    Exercise(task: tr("Отмени изменения в `README.md`: верни версию из последнего коммита.", "Discard the changes in `README.md`: bring back the version from the last commit."),
             hint: "git restore README.md",
             note: tr("Изменения пропадут насовсем, будь осторожен.", "The changes are gone for good, be careful."),
             setup: { appRepo($0); editReadme($0) },
             check: { t in t.text(readme) != nil && t.text(readme) == t.headFile(t.app, "README.md") }),
    Exercise(task: tr("Закоммить все изменённые файлы одной командой, без отдельного `git add`, с сообщением `update docs`.", "Commit all modified files with one command, without a separate `git add`, with the message `update docs`."),
             hint: "git commit -am \"update docs\"",
             note: tr("`-a` сам добавляет изменённые файлы, которые git уже отслеживает. Новые файлы так не добавятся.", "`-a` stages modified files that git already tracks. New files are not added this way."),
             setup: { t in appRepo(t); editReadme(t); t.fs.write(FileSystem.home + "/projects/app/main.py", "print('hi')\n") },
             check: { t in t.headMessage(t.app) == "update docs" && t.app.map { t.gitChanges($0).unstaged.isEmpty } == true && !t.events.contains("git:add") }),
    Exercise(task: tr("Покажи кратко только последние 2 коммита.", "Briefly show only the last 2 commits."),
             hint: "git log --oneline -2",
             note: tr("`-2` или `-n 2` ограничивает число коммитов.", "`-2` or `-n 2` limits the number of commits."),
             setup: appRepo,
             check: { $0.ran("git") && $0.lastOutput.count == 2 && $0.lastOutput[0].hasSuffix("add tests") }),
    Exercise(task: tr("Удали ветку `old`: она больше не нужна.", "Delete the `old` branch: it is no longer needed."),
             hint: "git branch -d old",
             setup: { t in appRepo(t); t.quiet("git branch old") },
             check: { $0.app != nil && $0.app?.branches["old"] == nil }),
] }

var gitHard: [Exercise] { [
    Exercise(task: tr("Сделай `projects/site` репозиторием, добавь в индекс все файлы и сделай первый коммит `init`.", "Make `projects/site` a repository, stage all files and make the first commit `init`."),
             hint: "cd projects/site  →  git init  →  git add .  →  git commit -m \"init\"",
             check: { t in
                 guard let r = t.repo(at: FileSystem.home + "/projects/site") else { return false }
                 return t.headMessage(r) == "init" && t.clean(r)
             }),
    Exercise(task: tr("Создай ветку `feature` и перейди на неё. Создай там файл `feature.txt` и закоммить его с сообщением `add feature`.", "Create a branch `feature` and switch to it. Create `feature.txt` there and commit it with the message `add feature`."),
             hint: "git switch -c feature  →  touch feature.txt  →  git add feature.txt  →  git commit -m \"add feature\"",
             setup: appRepo,
             check: { t in
                 guard let r = t.app else { return false }
                 return r.head == "feature" && t.headMessage(r) == "add feature" && r.headTree["feature.txt"] != nil && r.tree("main")["feature.txt"] == nil
             }),
    Exercise(task: tr("В ветке `feature` есть новый коммит. Влей её в `main`, ты сейчас на `main`.", "The `feature` branch has a new commit. Merge it into `main`; you are on `main` now."),
             hint: "git merge feature",
             setup: { t in
                 appRepo(t)
                 t.quiet("git switch -c feature", "echo 'def check(): pass' > feature.py", "git add feature.py", "git commit -m \"add feature\"", "git switch main")
             },
             check: { t in t.app?.head == "main" && t.headFile(t.app, "feature.py") != nil }),
    Exercise(task: tr("Ты на ветке `feature`, в `README.md` незаконченные изменения. Спрячь их, переключись на `main` и обратно, затем верни изменения.", "You are on `feature` with unfinished changes in `README.md`. Stash them, switch to `main` and back, then bring the changes back."),
             hint: "git stash  →  git switch main  →  git switch feature  →  git stash pop",
             note: tr("С незакоммиченными изменениями git не даст переключить ветку. `stash` прячет их, `stash pop` возвращает.", "Git won't switch branches with uncommitted changes. `stash` hides them, `stash pop` brings them back."),
             setup: { t in
                 appRepo(t)
                 t.quiet("git switch -c feature", "touch feature.py", "git add feature.py", "git commit -m \"start feature\"")
                 editReadme(t)
             },
             check: { t in
                 guard let r = t.app else { return false }
                 return r.head == "feature" && r.stash.isEmpty && t.events.contains("git:stash")
                     && (t.events.contains("git:switch") || t.events.contains("git:checkout")) && t.gitChanges(r).unstaged.map(\.1) == ["README.md"]
             }),
    Exercise(task: tr("Сколько коммитов в истории? Выведи одно число.", "How many commits are in the history? Print one number."),
             hint: "git log --oneline | wc -l",
             setup: appRepo,
             check: { $0.ran("git") && $0.first == "3" }),
] }

// MARK: права доступа

private func scripts(_ t: Terminal, backup: Int = 0o755, deploy: Int = 0o644, hello: Int = 0o644, secret: Int = 0o600) {
    t.fs.put("~/scripts/deploy.sh", "echo \"Deploying...\"\necho \"Done\"\n")
    t.fs.put("~/scripts/backup.sh", "echo \"Backup done\"\n")
    t.fs.put("~/scripts/hello.sh", "echo \"Hello!\"\n")
    t.fs.put("~/scripts/secret.txt", "password=1234\n")
    for (f, m) in [("deploy.sh", deploy), ("backup.sh", backup), ("hello.sh", hello), ("secret.txt", secret)] { t.setMode("~/scripts/" + f, m) }
}

var permissionsLesson: Lesson { Lesson(id: "permissions", title: tr("Права доступа", "Permissions"), subtitle: "ls -l, chmod, ./script", exercises: [
    Exercise(task: tr("Посмотри права файлов в папке `scripts`.", "Look at the permissions of the files in `scripts`."),
             hint: "ls -l scripts",
             note: tr("`-rwxr-xr-x`: первый знак — тип (`d` папка), дальше по три буквы для владельца, группы и остальных: `r` чтение, `w` запись, `x` запуск.", "`-rwxr-xr-x`: the first char is the type (`d` for folder), then three letters each for owner, group and others: `r` read, `w` write, `x` execute."),
             setup: { scripts($0) },
             check: { $0.ran("ls") && $0.lastFlags.contains("l") && $0.lastOutput.count == 5 }),
    Exercise(task: tr("Сделай `scripts/deploy.sh` исполняемым.", "Make `scripts/deploy.sh` executable."),
             hint: "chmod +x scripts/deploy.sh",
             note: tr("`+x` добавляет право на запуск.", "`+x` adds the execute permission."),
             setup: { scripts($0) },
             check: { ($0.perm("~/scripts/deploy.sh") ?? 0) & 0o100 != 0 }),
    Exercise(task: tr("Запусти скрипт `scripts/backup.sh`.", "Run the `scripts/backup.sh` script."),
             hint: "./scripts/backup.sh",
             note: tr("Скрипт запускается по пути. `./` — текущая папка, без пути zsh станет искать команду с таким именем.", "A script runs by its path. `./` is the current folder; without a path zsh looks for a command with that name."),
             setup: { scripts($0) },
             check: { $0.events.contains("run:backup.sh") }),
    Exercise(task: tr("Сделай `scripts/hello.sh` исполняемым и запусти его.", "Make `scripts/hello.sh` executable and run it."),
             hint: "chmod +x scripts/hello.sh  →  ./scripts/hello.sh",
             setup: { scripts($0) },
             check: { $0.events.contains("run:hello.sh") && ($0.perm("~/scripts/hello.sh") ?? 0) & 0o100 != 0 }),
    Exercise(task: tr("Сделай так, чтобы `scripts/secret.txt` мог читать и менять только владелец: права `600`.", "Let only the owner read and change `scripts/secret.txt`: permissions `600`."),
             hint: "chmod 600 scripts/secret.txt",
             note: tr("Цифры — владелец, группа, остальные. Каждая — сумма: 4 чтение, 2 запись, 1 запуск. 6 = 4 + 2.", "The digits are owner, group, others. Each is a sum: 4 read, 2 write, 1 execute. 6 = 4 + 2."),
             setup: { scripts($0, secret: 0o644) },
             check: { $0.perm("~/scripts/secret.txt") == 0o600 }),
    Exercise(task: tr("Поставь `scripts/deploy.sh` права `755`: владелец может всё, остальные — читать и запускать.", "Set `scripts/deploy.sh` to `755`: the owner can do everything, others can read and execute."),
             hint: "chmod 755 scripts/deploy.sh",
             note: tr("7 = 4 + 2 + 1, 5 = 4 + 1.", "7 = 4 + 2 + 1, 5 = 4 + 1."),
             setup: { scripts($0) },
             check: { $0.perm("~/scripts/deploy.sh") == 0o755 }),
    Exercise(task: tr("Запрети запись в `notes.txt` всем, включая себя.", "Forbid writing to `notes.txt` for everyone, including yourself."),
             hint: "chmod a-w notes.txt",
             note: tr("`a` — все (all), `-w` — убрать запись. Ещё бывают `u` владелец, `g` группа, `o` остальные.", "`a` is all, `-w` removes write. There are also `u` owner, `g` group, `o` others."),
             check: { $0.perm("~/notes.txt").map { $0 & 0o222 == 0 } == true }),
    Exercise(task: tr("Файл `scripts/secret.txt` никто не может прочитать. Дай себе право на чтение и выведи файл.", "Nobody can read `scripts/secret.txt`. Give yourself read permission and print the file."),
             hint: "chmod u+r scripts/secret.txt  →  cat scripts/secret.txt",
             setup: { scripts($0, secret: 0o200) },
             check: { $0.lastOutput == ["password=1234"] }),
]) }

var permissionsMedium: [Exercise] { [
    Exercise(task: tr("Сделай все `.sh` файлы в `scripts` исполняемыми одной командой.", "Make every `.sh` file in `scripts` executable with one command."),
             hint: "chmod +x scripts/*.sh",
             setup: { scripts($0) },
             check: { t in t.lastCommand.contains("*") && ["deploy", "backup", "hello"].allSatisfy { (t.perm("~/scripts/\($0).sh") ?? 0) & 0o100 != 0 } }),
    Exercise(task: tr("Поставь `Documents/report.txt` права: владелец читает и пишет, группа и остальные только читают.", "Set `Documents/report.txt` so the owner reads and writes, group and others only read."),
             hint: "chmod 644 Documents/report.txt",
             setup: { $0.setMode("~/Documents/report.txt", 0o666) },
             check: { $0.perm("~/Documents/report.txt") == 0o644 }),
    Exercise(task: tr("Закрой папку `private` от группы и остальных: доступ только у тебя.", "Close the `private` folder to group and others: access for you only."),
             hint: "chmod 700 private",
             note: tr("Можно и буквами: `chmod go-rwx private`.", "Letters work too: `chmod go-rwx private`."),
             setup: { $0.fs.put("~/private/plans.txt", "...\n") },
             check: { $0.perm("~/private") == 0o700 }),
    Exercise(task: tr("Убери у группы право записи на папку `scripts` и на всё внутри неё.", "Remove the group's write permission on `scripts` and everything inside it."),
             hint: "chmod -R g-w scripts",
             note: tr("`-R` (recursive) применяет права ко всему содержимому папки.", "`-R` (recursive) applies to everything inside the folder."),
             setup: { t in
                 scripts(t, backup: 0o775, deploy: 0o664, hello: 0o664, secret: 0o660)
                 t.setMode("~/scripts", 0o775)
             },
             check: { t in ["", "/deploy.sh", "/backup.sh", "/hello.sh", "/secret.txt"].allSatisfy { (t.perm("~/scripts" + $0) ?? 0o020) & 0o020 == 0 } }),
    Exercise(task: tr("Покажи права самой папки `scripts`, а не её содержимого.", "Show the permissions of the `scripts` folder itself, not its contents."),
             hint: "ls -ld scripts",
             note: tr("`-d` показывает папку как один элемент, не заходя в неё.", "`-d` lists the folder as one entry without going inside."),
             setup: { scripts($0) },
             check: { $0.ran("ls") && $0.lastFlags.isSuperset(of: ["l", "d"]) && $0.lastOutput.count == 1 }),
    Exercise(task: tr("Запусти `scripts/hello.sh` через `sh`, не меняя его права.", "Run `scripts/hello.sh` through `sh` without changing its permissions."),
             hint: "sh scripts/hello.sh",
             note: tr("`sh` читает файл сам, поэтому право на запуск не нужно, хватает чтения.", "`sh` reads the file itself, so no execute permission is needed, read is enough."),
             setup: { scripts($0) },
             check: { $0.events.contains("run:hello.sh") && $0.perm("~/scripts/hello.sh") == 0o644 }),
] }

var permissionsHard: [Exercise] { [
    Exercise(task: tr("Создай скрипт `hi.sh`, который выводит `hi`, сделай его исполняемым и запусти.", "Create a script `hi.sh` that prints `hi`, make it executable and run it."),
             hint: "echo \"echo hi\" > hi.sh  →  chmod +x hi.sh  →  ./hi.sh",
             check: { $0.events.contains("run:hi.sh") && $0.lastOutput == ["hi"] }),
    Exercise(task: tr("Оставь владельцу `scripts/secret.txt` только чтение, остальным — ничего.", "Leave the owner of `scripts/secret.txt` read-only access and nothing for others."),
             hint: "chmod 400 scripts/secret.txt",
             setup: { scripts($0) },
             check: { $0.perm("~/scripts/secret.txt") == 0o400 }),
    Exercise(task: tr("Скопируй `scripts/backup.sh` в новую папку `bin` под именем `backup`, сделай копию исполняемой и запусти её.", "Copy `scripts/backup.sh` into a new folder `bin` as `backup`, make the copy executable and run it."),
             hint: "mkdir bin  →  cp scripts/backup.sh bin/backup  →  chmod +x bin/backup  →  bin/backup",
             note: tr("Если в команде есть `/`, zsh запускает файл по этому пути.", "If the command contains `/`, zsh runs the file at that path."),
             setup: { scripts($0, backup: 0o644) },
             check: { $0.events.contains("run:backup") && $0.isFile("~/bin/backup") }),
    Exercise(task: tr("Одной строкой сделай `scripts/deploy.sh` исполняемым и запусти, только если `chmod` прошёл успешно.", "In one line make `scripts/deploy.sh` executable and run it only if `chmod` succeeded."),
             hint: "chmod +x scripts/deploy.sh && ./scripts/deploy.sh",
             setup: { scripts($0) },
             check: { $0.lastCommand.contains("&&") && $0.events.contains("run:deploy.sh") }),
    Exercise(task: tr("Выведи из подробного списка `scripts` только файлы, которые владелец может запускать.", "From the long listing of `scripts`, print only the files the owner can execute."),
             hint: "ls -l scripts | grep rwx",
             setup: { scripts($0, deploy: 0o744) },
             check: { $0.ran("ls") && $0.lastOutput.count == 2 && $0.lastOutput.allSatisfy { $0.hasSuffix(".sh") } }),
] }

// MARK: процессы

var processesLesson: Lesson { Lesson(id: "processes", title: tr("Процессы", "Processes"), subtitle: "ps, kill, &, jobs, fg", exercises: [
    Exercise(task: tr("Посмотри процессы, запущенные в этом терминале.", "Look at the processes started in this terminal."),
             hint: "ps",
             note: tr("PID — номер процесса, по нему его можно завершить.", "PID is the process number; you can stop the process by it."),
             check: { $0.events.contains("cmd:ps") }),
    Exercise(task: tr("Покажи все процессы системы, включая чужие.", "Show every process in the system, including other users'."),
             hint: "ps aux",
             note: tr("`a` — всех пользователей, `u` — с владельцем, `x` — и без терминала.", "`a` all users, `u` with the owner, `x` including those without a terminal."),
             check: { $0.ran("ps") && $0.lastOutput.count > 6 }),
    Exercise(task: tr("Найди среди всех процессов `python3`.", "Find `python3` among all processes."),
             hint: "ps aux | grep python3",
             setup: { $0.spawn("python3 server.py", pid: 4242) },
             check: { $0.lastOutput.count == 1 && $0.lastOutput[0].contains("4242") }),
    Exercise(task: tr("Заверши процесс с PID `4242`.", "Stop the process with PID `4242`."),
             hint: "kill 4242",
             setup: { $0.spawn("python3 server.py", pid: 4242) },
             check: { !$0.processes.contains { $0.pid == 4242 } }),
    Exercise(task: tr("Запусти `sleep 100` в фоне, чтобы терминал остался свободным.", "Run `sleep 100` in the background so the terminal stays free."),
             hint: "sleep 100 &",
             note: tr("`&` в конце запускает команду в фоне. `[1]` — номер задачи, дальше PID.", "`&` at the end runs the command in the background. `[1]` is the job number, then the PID."),
             check: { t in t.mode == .shell && t.jobs.contains { $0.command == "sleep 100" && !$0.stopped } }),
    Exercise(task: tr("Посмотри список фоновых задач этого терминала.", "List the background jobs of this terminal."),
             hint: "jobs",
             setup: { t in t.spawn("sleep 100", job: true); t.spawn("python3 -m http.server", job: true) },
             check: { $0.events.contains("cmd:jobs") }),
    Exercise(task: tr("Запусти `sleep 100` и прерви его, не дожидаясь конца.", "Run `sleep 100` and interrupt it without waiting."),
             hint: "sleep 100  →  Ctrl+C",
             check: { $0.events.contains("cmd:sleep") && $0.events.contains("interrupt") && $0.mode == .shell }),
    Exercise(task: tr("Запусти `sleep 100` и приостанови его, не завершая.", "Run `sleep 100` and pause it without stopping it."),
             hint: "sleep 100  →  Ctrl+Z",
             note: tr("Ctrl+Z ставит процесс на паузу и возвращает терминал. Он остаётся в списке `jobs`.", "Ctrl+Z pauses the process and gives you the terminal back. It stays in `jobs`."),
             check: { $0.jobs.contains { $0.command == "sleep 100" && $0.stopped } }),
]) }

var processesMedium: [Exercise] { [
    Exercise(task: tr("Верни приостановленную задачу на передний план и заверши её.", "Bring the paused job to the foreground and stop it."),
             hint: "fg  →  Ctrl+C",
             note: tr("`fg` (foreground) — на передний план.", "`fg` brings a job to the foreground."),
             setup: { $0.spawn("sleep 300", job: true, stopped: true) },
             check: { $0.events.contains("cmd:fg") && $0.events.contains("interrupt") && $0.jobs.isEmpty }),
    Exercise(task: tr("Продолжи приостановленную задачу в фоне.", "Resume the paused job in the background."),
             hint: "bg",
             note: tr("`bg` (background) — продолжить в фоне.", "`bg` resumes a job in the background."),
             setup: { $0.spawn("sleep 300", job: true, stopped: true) },
             check: { $0.mode == .shell && $0.jobs.count == 1 && !$0.jobs[0].stopped }),
    Exercise(task: tr("Заверши фоновую задачу № 1 по её номеру, а не по PID.", "Stop background job 1 by its job number, not by PID."),
             hint: "kill %1",
             note: tr("`%1` — номер задачи из `jobs`.", "`%1` is the job number from `jobs`."),
             setup: { $0.spawn("sleep 100", job: true) },
             check: { $0.jobs.isEmpty && $0.lastCommand.contains("%") }),
    Exercise(task: tr("Процесс `4242` не завершается обычным `kill`. Заверши его принудительно.", "Process `4242` ignores a plain `kill`. Stop it by force."),
             hint: "kill -9 4242",
             note: tr("`-9` (SIGKILL) завершает процесс сразу, он не может это перехватить.", "`-9` (SIGKILL) stops the process at once; it can't catch it."),
             setup: { $0.spawn("python3 server.py", pid: 4242, stubborn: true) },
             check: { !$0.processes.contains { $0.pid == 4242 } }),
    Exercise(task: tr("Заверши все процессы `sleep` одной командой по имени.", "Stop every `sleep` process with one command by name."),
             hint: "killall sleep",
             note: tr("`pkill sleep` тоже подойдёт.", "`pkill sleep` works too."),
             setup: { t in for s in ["sleep 100", "sleep 200", "sleep 300"] { t.spawn(s, job: true) } },
             check: { !$0.processes.contains { $0.name == "sleep" } }),
    Exercise(task: tr("Узнай PID процесса `Safari`.", "Find the PID of `Safari`."),
             hint: "pgrep Safari",
             note: tr("Можно и `ps aux | grep Safari`.", "`ps aux | grep Safari` works too."),
             check: { $0.lastOutput.contains { $0.contains("455") } }),
] }

var processesHard: [Exercise] { [
    Exercise(task: tr("Запусти `python3 -m http.server` в фоне, проверь, что он есть в списке задач, и останови его.", "Run `python3 -m http.server` in the background, check it is in the job list and stop it."),
             hint: "python3 -m http.server &  →  jobs  →  kill %1",
             check: { t in t.events.contains("bg:python3") && t.events.contains("cmd:jobs") && !t.processes.contains { $0.name == "python3" } }),
    Exercise(task: tr("Одной строкой запусти в фоне `sleep 100` и `sleep 200` и выведи список задач.", "In one line run `sleep 100` and `sleep 200` in the background and list the jobs."),
             hint: "sleep 100 & sleep 200 & jobs",
             check: { $0.jobs.filter { $0.name == "sleep" }.count == 2 && $0.lastCommand.contains("jobs") && $0.lastOutput.count == 2 }),
    Exercise(task: tr("Сколько процессов `python3` сейчас запущено? Ответ — одно число.", "How many `python3` processes are running? The answer is one number."),
             hint: "pgrep python3 | wc -l",
             setup: { t in t.spawn("python3 bot.py", pid: 3101); t.spawn("python3 server.py", pid: 3102); t.spawn("python3 -m http.server", pid: 3103) },
             check: { $0.first == "3" }),
    Exercise(task: tr("Запусти `sleep 300`, приостанови его, продолжи в фоне и проверь список задач.", "Run `sleep 300`, pause it, resume it in the background and check the job list."),
             hint: "sleep 300  →  Ctrl+Z  →  bg  →  jobs",
             check: { t in t.events.contains("suspend") && t.jobs.contains { $0.command == "sleep 300" && !$0.stopped } && t.lastOutput.contains { $0.contains("running") } }),
    Exercise(task: tr("Останови обе фоновые задачи одной командой `kill`.", "Stop both background jobs with a single `kill` command."),
             hint: "kill %1 %2",
             setup: { t in t.spawn("sleep 100", job: true); t.spawn("sleep 200", job: true) },
             check: { $0.jobs.isEmpty && $0.ran("kill") }),
] }

// MARK: архивы

private func backup(_ t: Terminal) { t.quiet("tar -czf backup.tar.gz projects/app") }

private func photos(_ t: Terminal) {
    for f in ["a.jpg", "b.jpg", "c.jpg"] { t.fs.put("~/photos/" + f, "(\(f))\n") }
    t.quiet("zip -r photos.zip photos", "rm -r photos")
}

var archivesLesson: Lesson { Lesson(id: "archives", title: tr("Архивы", "Archives"), subtitle: "tar, zip, gzip", exercises: [
    Exercise(task: tr("Упакуй папку `projects/site` в сжатый архив `site.tar.gz`.", "Pack `projects/site` into a compressed archive `site.tar.gz`."),
             hint: "tar -czf site.tar.gz projects/site",
             note: tr("`c` — создать, `z` — сжать gzip, `f` — имя архива, оно идёт сразу после флагов.", "`c` create, `z` compress with gzip, `f` archive name, which goes right after the flags."),
             check: { $0.archiveFiles("~/site.tar.gz").contains("projects/site/index.html") }),
    Exercise(task: tr("Посмотри, что лежит в архиве `backup.tar.gz`, не распаковывая его.", "See what is inside `backup.tar.gz` without unpacking it."),
             hint: "tar -tzf backup.tar.gz",
             note: tr("`t` — показать список (table).", "`t` lists the contents (table)."),
             setup: backup,
             check: { $0.ran("tar") && $0.lastOutput.contains("projects/app/main.py") }),
    Exercise(task: tr("Папку `projects/app` удалили, но есть архив `backup.tar.gz`. Распакуй его в текущую папку.", "`projects/app` was deleted, but there is `backup.tar.gz`. Unpack it into the current folder."),
             hint: "tar -xzf backup.tar.gz",
             note: tr("`x` — извлечь (extract).", "`x` extracts."),
             setup: { t in backup(t); t.quiet("rm -r projects/app") },
             check: { $0.isFile("~/projects/app/main.py") }),
    Exercise(task: tr("Сожми папку `Documents` вместе с содержимым в `docs.zip`.", "Compress the `Documents` folder with its contents into `docs.zip`."),
             hint: "zip -r docs.zip Documents",
             note: tr("Без `-r` zip добавит только пустую папку.", "Without `-r` zip adds only an empty folder."),
             check: { $0.archiveFiles("~/docs.zip").contains("Documents/report.txt") }),
    Exercise(task: tr("Распакуй `photos.zip`.", "Unpack `photos.zip`."),
             hint: "unzip photos.zip",
             setup: photos,
             check: { $0.isFile("~/photos/a.jpg") }),
    Exercise(task: tr("Посмотри список файлов в `photos.zip`, не распаковывая.", "List the files in `photos.zip` without unpacking."),
             hint: "unzip -l photos.zip",
             setup: photos,
             check: { $0.ran("unzip") && $0.lastOutput.contains { $0.hasSuffix("photos/a.jpg") } && !$0.exists("~/photos") }),
    Exercise(task: tr("Сожми файл `projects/app/app.log` с помощью `gzip`.", "Compress `projects/app/app.log` with `gzip`."),
             hint: "gzip projects/app/app.log",
             note: tr("`gzip` заменяет файл на сжатый `.gz`.", "`gzip` replaces the file with a compressed `.gz`."),
             check: { $0.isFile("~/projects/app/app.log.gz") && !$0.exists("~/projects/app/app.log") }),
    Exercise(task: tr("Распакуй `old.log.gz`.", "Unpack `old.log.gz`."),
             hint: "gunzip old.log.gz",
             note: tr("Можно и `gzip -d old.log.gz`.", "`gzip -d old.log.gz` works too."),
             setup: { $0.quiet("gzip old.log") },
             check: { $0.isFile("~/old.log") && !$0.exists("~/old.log.gz") }),
]) }

var archivesMedium: [Exercise] { [
    Exercise(task: tr("Распакуй `backup.tar.gz` в новую папку `restore`.", "Unpack `backup.tar.gz` into a new folder `restore`."),
             hint: "mkdir restore  →  tar -xzf backup.tar.gz -C restore",
             note: tr("`-C` — куда распаковать. Папка должна уже существовать.", "`-C` sets where to unpack. The folder must already exist."),
             setup: backup,
             check: { $0.isFile("~/restore/projects/app/main.py") }),
    Exercise(task: tr("Распакуй `photos.zip` в папку `pics`.", "Unpack `photos.zip` into the `pics` folder."),
             hint: "unzip photos.zip -d pics",
             note: tr("`-d` — куда распаковать, unzip сам создаст папку.", "`-d` sets the destination; unzip creates the folder itself."),
             setup: photos,
             check: { $0.isFile("~/pics/photos/a.jpg") }),
    Exercise(task: tr("Упакуй в `texts.tar.gz` только `notes.txt` и `draft.txt`.", "Pack only `notes.txt` and `draft.txt` into `texts.tar.gz`."),
             hint: "tar -czf texts.tar.gz notes.txt draft.txt",
             check: { Set($0.archiveFiles("~/texts.tar.gz")) == ["notes.txt", "draft.txt"] }),
    Exercise(task: tr("Сделай архив `app.tar` из `projects/app` без сжатия.", "Make an uncompressed archive `app.tar` from `projects/app`."),
             hint: "tar -cf app.tar projects/app",
             note: tr("Без `z` архив не сжимается.", "Without `z` the archive is not compressed."),
             check: { $0.node("~/app.tar")?.archive?.kind == "tar" && $0.archiveFiles("~/app.tar").contains("projects/app/main.py") }),
    Exercise(task: tr("Упакуй `projects/site` в `site.tar.gz` так, чтобы tar при упаковке вывел список файлов.", "Pack `projects/site` into `site.tar.gz` so that tar prints the file list while packing."),
             hint: "tar -czvf site.tar.gz projects/site",
             note: tr("`v` (verbose) — подробный вывод.", "`v` (verbose) prints details."),
             check: { !$0.archiveFiles("~/site.tar.gz").isEmpty && $0.lastOutput.contains { $0.hasPrefix("a ") } }),
    Exercise(task: tr("Сожми все `.log` файлы в папке `logs` одной командой.", "Compress every `.log` file in `logs` with one command."),
             hint: "gzip logs/*.log",
             setup: { t in for f in ["mon.log", "tue.log", "wed.log"] { t.fs.put("~/logs/" + f, "ok\n") } },
             check: { t in ["mon", "tue", "wed"].allSatisfy { t.isFile("~/logs/\($0).log.gz") && !t.exists("~/logs/\($0).log") } }),
] }

var archivesHard: [Exercise] { [
    Exercise(task: tr("Сохрани `projects` в `backup.tar.gz`, удали `projects/site` и восстанови его из архива.", "Save `projects` into `backup.tar.gz`, delete `projects/site` and restore it from the archive."),
             hint: "tar -czf backup.tar.gz projects  →  rm -r projects/site  →  tar -xzf backup.tar.gz",
             check: { $0.isFile("~/projects/site/index.html") && $0.events.contains("cmd:rm") && $0.events.contains("extract") }),
    Exercise(task: tr("Перепакуй `photos.zip` в `photos.tar.gz`.", "Repack `photos.zip` into `photos.tar.gz`."),
             hint: "unzip photos.zip  →  tar -czf photos.tar.gz photos",
             setup: photos,
             check: { $0.archiveFiles("~/photos.tar.gz").contains("photos/a.jpg") }),
    Exercise(task: tr("Проверь, есть ли в `backup.tar.gz` файл `main.py`, не распаковывая. Нужна только строка с ним.", "Check whether `backup.tar.gz` has `main.py` without unpacking. Only its line is needed."),
             hint: "tar -tzf backup.tar.gz | grep main.py",
             setup: backup,
             check: { $0.lastOutput == ["projects/app/main.py"] }),
    Exercise(task: tr("Сколько записей (файлов и папок) в архиве `backup.tar.gz`? Ответ — одно число.", "How many entries (files and folders) are in `backup.tar.gz`? The answer is one number."),
             hint: "tar -tzf backup.tar.gz | wc -l",
             setup: backup,
             check: { t in t.ran("tar") && t.first == String(t.node("~/backup.tar.gz")?.archive?.listing.count ?? -1) }),
    Exercise(task: tr("Упакуй все `.txt` файлы домашней папки в `txt.zip` и удали оригиналы, только если упаковка прошла успешно.", "Pack every `.txt` file in your home folder into `txt.zip` and delete the originals only if packing succeeded."),
             hint: "zip txt.zip *.txt && rm *.txt",
             check: { t in Set(t.archiveFiles("~/txt.zip")) == ["notes.txt", "draft.txt"] && !t.exists("~/notes.txt") && !t.exists("~/draft.txt") }),
] }

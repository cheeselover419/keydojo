import Foundation

// процесс в ненастоящей системе; job — номер задачи этого терминала
struct Proc {
    let pid: Int
    let command: String
    var user = "student"
    var job: Int?
    var stopped = false
    var stubborn = false    // не завершается обычным kill, только kill -9

    var name: String { FileSystem.base(String(command.split(separator: " ").first ?? "")).replacingOccurrences(of: "-", with: "") }

    static let system: [Proc] = [
        Proc(pid: 1, command: "/sbin/launchd", user: "root"),
        Proc(pid: 153, command: "WindowServer", user: "_windowserver"),
        Proc(pid: 410, command: "Dock"),
        Proc(pid: 412, command: "Finder"),
        Proc(pid: 455, command: "Safari"),
        Proc(pid: 498, command: "Terminal"),
        Proc(pid: 502, command: "-zsh"),
    ]
}

enum LongRun {
    case long(String)   // работает, пока не остановят
    case done(String)
    case fail
}

extension Terminal {
    var jobs: [Proc] { processes.filter { $0.job != nil }.sorted { $0.job! < $1.job! } }

    // для заготовок упражнений
    @discardableResult
    func spawn(_ command: String, pid: Int? = nil, job: Bool = false, stopped: Bool = false, stubborn: Bool = false) -> Proc {
        let p = Proc(pid: pid ?? nextPid, command: command, job: job ? (jobs.last?.job ?? 0) + 1 : nil, stopped: stopped, stubborn: stubborn)
        if pid == nil { nextPid += 7 }
        processes.append(p)
        return p
    }

    private func update(_ pid: Int, _ change: (inout Proc) -> Void) {
        if let i = processes.firstIndex(where: { $0.pid == pid }) { change(&processes[i]) }
    }

    // Ctrl+Z: процесс останавливается и становится задачей
    func suspend() {
        guard let f = foreground else { return }
        let job = processes.first { $0.pid == f.pid }?.job ?? (jobs.last?.job ?? 0) + 1
        update(f.pid) { $0.stopped = true; $0.job = job }
        lines.append("^Z")
        lines.append("zsh: suspended  \(f.command)")
        mode = .shell
        foreground = nil
        events.insert("suspend")
    }

    func longCheck(_ args: [String]) -> LongRun {
        let rest = Array(args.dropFirst())
        switch args[0] {
        case "sleep":
            guard let a = rest.first, let v = Double(a.trimmingCharacters(in: CharacterSet(charactersIn: "smhd"))), v >= 0 else {
                err("usage: sleep number[unit] ...")
                return .fail
            }
            return v == 0 ? .done("") : .long("")
        case "python3", "python":
            if rest.count >= 2, rest[0] == "-m", rest[1] == "http.server" { return .long("Serving HTTP on :: port 8000 (http://[::]:8000/) ...\n") }
            guard let f = rest.first else {
                err(tr("\(args[0]): интерактивный режим в тренажёре не поддерживается", "\(args[0]): interactive mode is not supported here"))
                return .fail
            }
            guard let n = fs.node(path(f)), !n.isDir else {
                err("\(args[0]): can't open file '\(path(f))': [Errno 2] No such file or directory")
                return .fail
            }
            return f.contains("server") || n.content.contains("serve") ? .long("Serving on http://localhost:8000\n") : .done("")
        case "node":
            guard let f = rest.first, fs.node(path(f)) != nil else {
                err("Error: Cannot find module '\(path(rest.first ?? ""))'")
                return .fail
            }
            return .long("Server listening on http://localhost:3000\n")
        case "tail":
            guard let f = rest.last(where: { !$0.hasPrefix("-") }), fs.node(path(f)) != nil else {
                err("tail: \(rest.last ?? ""): No such file or directory")
                return .fail
            }
            return .long("")
        default:
            return .done("")
        }
    }

    // команда, которая занимает терминал, пока её не остановят
    func longRunning(_ args: [String]) -> String {
        if args[0] == "fg" { return fg(Array(args.dropFirst())) }
        switch longCheck(args) {
        case .long(let o):
            foreground = spawn(args.joined(separator: " "))
            mode = .running
            return o
        case .done(let o): return o
        case .fail: return ""
        }
    }

    // cmd &
    func background(_ tokens: [Token]) -> Bool {
        let args = tokens.map(\.text)
        guard ["sleep", "python3", "python", "node", "tail"].contains(args[0]) else {
            let ok = pipeline(tokens)
            let j = (jobs.last?.job ?? 0) + 1
            lines.append("[\(j)] \(nextPid)")
            lines.append("[\(j)]  + done       \(args.joined(separator: " "))")
            nextPid += 7
            return ok
        }
        events.insert("cmd:" + args[0])
        events.insert("bg:" + args[0])
        lastNames.append(args[0])
        failed = false
        switch longCheck(args) {
        case .long(let o):
            let p = spawn(args.joined(separator: " "), job: true)
            lines.append("[\(p.job!)] \(p.pid)")
            out(o)
            return true
        case .done(let o):
            out(o)
            return true
        case .fail:
            return false
        }
    }

    private func pickJob(_ arg: String?, _ cmd: String) -> Proc? {
        if let a = arg {
            guard a.hasPrefix("%"), let n = Int(a.dropFirst()), let p = jobs.first(where: { $0.job == n }) else {
                err("\(cmd): job not found: \(a)")
                return nil
            }
            return p
        }
        guard let p = jobs.last else { err("\(cmd): no current job"); return nil }
        return p
    }

    func fg(_ rest: [String]) -> String {
        events.insert("cmd:fg")
        guard let p = pickJob(rest.first, "fg") else { return "" }
        update(p.pid) { $0.stopped = false }
        foreground = p
        mode = .running
        return "[\(p.job!)]  + continued  \(p.command)\n"
    }

    func bg(_ rest: [String]) -> String {
        guard let p = pickJob(rest.first ?? jobs.last(where: \.stopped).map { "%\($0.job!)" }, "bg") else { return "" }
        guard p.stopped else { err("bg: job already in background"); return "" }
        update(p.pid) { $0.stopped = false }
        return "[\(p.job!)]  + continued  \(p.command)\n"
    }

    func jobsList() -> String {
        let all = jobs
        return joined(all.enumerated().map { i, p in
            let mark = i == all.count - 1 ? "+" : i == all.count - 2 ? "-" : " "
            return "[\(p.job!)]  \(mark) \(p.stopped ? "suspended" : "running  ")  \(p.command)"
        })
    }

    func ps(_ rest: [String]) -> String {
        let all = rest.contains { $0.contains("a") || $0.contains("e") || $0 == "-A" }
        if all {
            return joined(["USER               PID  %CPU %MEM COMMAND"] + processes.map { p in
                p.user.padding(toLength: 16, withPad: " ", startingAt: 0) + String(format: "%6d", p.pid) + "   0.0  0.1 " + p.command
            })
        }
        let mine = processes.filter { $0.pid == 502 || $0.pid >= 1000 && $0.user == "student" }
        return joined(["  PID TTY           TIME CMD"] + mine.map { String(format: "%5d", $0.pid) + " ttys000    0:00.01 " + $0.command })
    }

    // убить процесс; false, если не получилось
    private func terminate(_ p: Proc, force: Bool, by cmd: String) -> Bool {
        guard p.user == "student", p.pid != 502 else { err("\(cmd): kill \(p.pid) failed: operation not permitted"); return false }
        if p.stubborn && !force { return true }
        processes.removeAll { $0.pid == p.pid }
        if let j = p.job { lines.append("[\(j)]  + \(force ? "killed    " : "terminated")  \(p.command)") }
        return true
    }

    func kill(_ rest: [String]) -> String {
        var force = false
        var targets: [String] = []
        for a in rest {
            if ["-9", "-KILL", "-SIGKILL"].contains(a) { force = true } else if a.hasPrefix("-") && !a.hasPrefix("-%") { continue } else { targets.append(a) }
        }
        if targets.isEmpty { err("kill: not enough arguments"); return "" }
        for t in targets {
            let p: Proc?
            if t.hasPrefix("%") {
                p = Int(t.dropFirst()).flatMap { n in jobs.first { $0.job == n } }
                if p == nil { err("kill: \(t): no such job"); continue }
            } else {
                guard let pid = Int(t) else { err("kill: illegal pid: \(t)"); continue }
                p = processes.first { $0.pid == pid }
                if p == nil { err("kill: kill \(t) failed: no such process"); continue }
            }
            _ = terminate(p!, force: force, by: "kill")
        }
        return ""
    }

    func killByName(_ cmd: String, _ rest: [String]) {
        let force = rest.contains { ["-9", "-KILL"].contains($0) }
        guard let name = rest.last(where: { !$0.hasPrefix("-") }) else { err("usage: \(cmd) [-signal] name"); return }
        let found = processes.filter { $0.user == "student" && $0.pid != 502 && (cmd == "killall" ? $0.name == name : $0.name.contains(name)) }
        if found.isEmpty {
            if cmd == "killall" { err("No matching processes belonging to you were found") } else { failed = true }
            return
        }
        for p in found { _ = terminate(p, force: force, by: cmd) }
    }

    func pgrep(_ rest: [String]) -> String {
        let (f, ops) = split(rest)
        guard let name = ops.first else { err("usage: pgrep [-l] pattern"); return "" }
        let found = processes.filter { $0.name.contains(name) }
        if found.isEmpty { failed = true }
        return joined(found.map { f.contains("l") ? "\($0.pid) \($0.name)" : "\($0.pid)" })
    }

    // MARK: права

    func chmod(_ rest: [String]) {
        let recursive = rest.contains("-R")
        let ops = rest.filter { $0 != "-R" }
        guard ops.count >= 2 else { err("usage: chmod [-fhv] [-R [-H | -L | -P]] mode file ..."); return }
        let m = ops[0]
        var apply: ((Int) -> Int)?
        if m.allSatisfy({ ("0"..."7").contains($0) }), m.count <= 4, let v = Int(m, radix: 8) {
            apply = { _ in v }
        } else {
            var clauses: [(who: Int, op: Character, bits: Int)] = []
            for c in m.split(separator: ",", omittingEmptySubsequences: false) {
                guard let opIndex = c.firstIndex(where: { "+-=".contains($0) }) else { clauses = []; break }
                let who = c[..<opIndex], perms = c[c.index(after: opIndex)...]
                guard who.allSatisfy({ "ugoa".contains($0) }), perms.allSatisfy({ "rwx".contains($0) }) else { clauses = []; break }
                var w = 0
                for ch in who { w |= ["u": 0o700, "g": 0o070, "o": 0o007, "a": 0o777][ch]! }
                if who.isEmpty { w = 0o777 }
                var b = 0
                for ch in perms { b |= ["r": 0o444, "w": 0o222, "x": 0o111][ch]! }
                clauses.append((w, c[opIndex], b & w))
            }
            if !clauses.isEmpty {
                apply = { mode in
                    clauses.reduce(mode) { mode, c in
                        switch c.op {
                        case "+": return mode | c.bits
                        case "-": return mode & ~c.bits
                        default: return mode & ~c.who | c.bits
                        }
                    }
                }
            }
        }
        guard let apply else { err("chmod: Invalid file mode: \(m)"); return }
        for p in ops.dropFirst() {
            guard let n = fs.node(path(p)) else { err("chmod: \(p): No such file or directory"); continue }
            if recursive { walk(n, p) { node, _ in node.mode = apply(node.mode) } } else { n.mode = apply(n.mode) }
        }
        events.insert("chmod")
    }

    // ./script.sh или sh script.sh: каждая строка выполняется как команда
    func script(_ p: String?, needExec: Bool) -> String {
        guard let p else { err(tr("sh: интерактивный режим в тренажёре не поддерживается", "sh: interactive mode is not supported here")); return "" }
        guard let n = fs.node(path(p)) else {
            err(needExec ? "zsh: no such file or directory: \(p)" : "sh: \(p): No such file or directory")
            return ""
        }
        if n.isDir || needExec && n.mode & 0o100 == 0 || n.mode & 0o400 == 0 {
            err(needExec ? "zsh: permission denied: \(p)" : "sh: \(p): Permission denied")
            return ""
        }
        guard scriptDepth < 5 else { err("sh: \(p): too many nested scripts"); return "" }
        events.insert("run:" + FileSystem.base(p))
        let saved = (lastNames, lastOutput, lines.count)
        scriptDepth += 1
        var ok = true
        for line in textLines(n.content) {
            let l = line.trimmingCharacters(in: .whitespaces)
            if l.isEmpty || l.hasPrefix("#") { continue }
            ok = execute(l)
        }
        scriptDepth -= 1
        let printed = Array(lines[saved.2...])
        lines.removeSubrange(saved.2...)
        (lastNames, lastOutput) = (saved.0, saved.1)
        failed = !ok
        return joined(printed)
    }

    // MARK: архивы

    // кладёт копию в папку, папки сливаются, как при распаковке
    private func place(_ node: FSNode, at abs: String) {
        if let old = fs.node(abs), old.isDir, let ch = node.children {
            old.mode = node.mode
            for (k, v) in ch { place(v, at: abs + "/" + k) }
            return
        }
        fs.mkdirs("/" + FileSystem.parts(abs).dropLast().joined(separator: "/"))
        guard let par = fs.parent(abs) else { return }
        par.dir.children?[par.name] = node.clone()
    }

    private func entryPath(_ p: String) -> String {
        var s = p
        while s.hasPrefix("./") { s.removeFirst(2) }
        while s.hasPrefix("/") { s.removeFirst() }
        while s.count > 1 && s.hasSuffix("/") { s.removeLast() }
        return s
    }

    private func saveArchive(_ name: String, _ a: Archive) {
        let abs = path(name)
        if fs.node(abs)?.isDir == true { err("\(name): Is a directory"); return }
        guard fs.write(abs, tr("(архив)\n", "(archive)\n")) else { err("\(name): No such file or directory"); return }
        fs.node(abs)?.archive = a
    }

    private func openArchive(_ name: String, kind: String, _ cmd: String) -> Archive? {
        guard let n = fs.node(path(name)), !n.isDir else { err("\(cmd): Error opening archive: Failed to open '\(name)'"); return nil }
        guard let a = n.archive, a.kind.hasPrefix(kind) else { err("\(cmd): Error opening archive: Unrecognized archive format"); return nil }
        return a
    }

    func tar(_ rest: [String]) -> String {
        var flags = Set<Character>()
        var ops: [String] = []
        var dir: String?
        var i = 0
        if let f = rest.first, !f.hasPrefix("-"), f.allSatisfy({ "cxtzvfj".contains($0) }) { flags = Set(f); i = 1 }
        while i < rest.count {
            let a = rest[i]
            if a == "-C" {
                guard i + 1 < rest.count else { err("tar: Option -C requires an argument"); return "" }
                dir = rest[i + 1]
                i += 2
                continue
            }
            if a.hasPrefix("-") && a.count > 1 { flags.formUnion(a.dropFirst()) } else { ops.append(a) }
            i += 1
        }
        let modes = flags.intersection(["c", "x", "t"])
        guard modes.count == 1 else { err("tar: Must specify one of -c, -r, -t, -u, -x"); return "" }
        guard flags.contains("f"), let name = ops.first else { err("tar: no archive file specified, use -f"); return "" }
        let verbose = flags.contains("v")
        if modes.contains("c") {
            let files = ops.dropFirst()
            guard !files.isEmpty else { err("tar: no files or directories specified"); return "" }
            var a = Archive(kind: flags.contains("z") ? "tar.gz" : "tar", entries: [])
            let self_ = path(name)
            for f in files {
                guard let n = fs.node(path(f)) else { err("tar: \(f): Cannot stat: No such file or directory"); continue }
                if entryPath(f) == "." || entryPath(f).isEmpty, let ch = n.children {
                    for k in ch.keys.sorted() where path(f + "/" + k) != self_ { a.entries.append((k, ch[k]!.clone())) }
                } else {
                    a.entries.append((entryPath(f), n.clone()))
                }
            }
            saveArchive(name, a)
            return verbose ? joined(a.listing.map { "a " + $0 }) : ""
        }
        guard let a = openArchive(name, kind: "tar", "tar") else { return "" }
        if modes.contains("t") { return joined(a.listing) }
        let dest = dir.map { path($0) } ?? cwd
        guard fs.node(dest)?.isDir == true else { err("tar: could not chdir to '\(dir ?? "")'"); return "" }
        for e in a.entries { place(e.node, at: dest + "/" + e.path) }
        events.insert("extract")
        return verbose ? joined(a.listing.map { "x " + $0 }) : ""
    }

    func zip(_ rest: [String]) -> String {
        let (f, ops) = split(rest)
        guard var name = ops.first else { err("zip error: Nothing to do!"); return "" }
        if !name.hasSuffix(".zip") { name += ".zip" }
        var a = fs.node(path(name))?.archive ?? Archive(kind: "zip", entries: [])
        var res: [String] = []
        var added = 0
        for p in ops.dropFirst() where path(p) != path(name) {
            guard let n = fs.node(path(p)) else { res.append("\tzip warning: name not matched: \(p)"); continue }
            let e = entryPath(p)
            let node = n.isDir && !f.contains("r") ? FSNode(dir: [:], mode: n.mode) : n.clone()
            a.entries.removeAll { $0.path == e }
            a.entries.append((e, node))
            added += 1
            res += Archive(kind: "zip", entries: [(e, node)]).listing.map { "  adding: \($0) (\($0.hasSuffix("/") ? "stored 0%" : "deflated 42%"))" }
        }
        guard added > 0 else {
            lines += res
            err("zip error: Nothing to do! (\(name))")
            return ""
        }
        saveArchive(name, a)
        return f.contains("q") ? "" : joined(res)
    }

    func unzip(_ rest: [String]) -> String {
        var ops: [String] = []
        var flags = Set<Character>()
        var dir: String?
        var i = 0
        while i < rest.count {
            if rest[i] == "-d", i + 1 < rest.count { dir = rest[i + 1]; i += 2; continue }
            if rest[i].hasPrefix("-") { flags.formUnion(rest[i].dropFirst()) } else { ops.append(rest[i]) }
            i += 1
        }
        guard var name = ops.first else { err("usage: unzip [-l] file[.zip] [-d exdir]"); return "" }
        if fs.node(path(name)) == nil && !name.hasSuffix(".zip") { name += ".zip" }
        guard let n = fs.node(path(name)), !n.isDir else {
            err("unzip:  cannot find or open \(name), \(name).zip or \(name).ZIP.")
            return ""
        }
        guard let a = n.archive, a.kind == "zip" else { err("unzip: \(name) is not a zip archive"); return "" }
        if flags.contains("l") {
            var res = ["Archive:  \(name)", "  Length      Date    Time    Name", "---------  ---------- -----   ----"]
            var total = 0
            for p in a.listing {
                let size = p.hasSuffix("/") ? 0 : entryNode(a, p)?.content.utf8.count ?? 0
                total += size
                res.append(String(format: "%9d", size) + "  11-15-2026 10:00   " + p)
            }
            res += ["---------                     -------", String(format: "%9d", total) + "                     \(a.listing.count) files"]
            return joined(res)
        }
        let dest = dir.map { path($0) } ?? cwd
        if fs.mkdirs(dest) == nil { err("checkdir:  cannot create extraction directory: \(dir ?? "")"); return "" }
        for e in a.entries { place(e.node, at: dest + "/" + e.path) }
        events.insert("extract")
        let prefix = dir.map { entryPath($0) + "/" } ?? ""
        return joined(["Archive:  \(name)"] + a.listing.map { $0.hasSuffix("/") ? "   creating: \(prefix)\($0)" : "  inflating: \(prefix)\($0)" })
    }

    private func entryNode(_ a: Archive, _ p: String) -> FSNode? {
        for e in a.entries {
            if p == e.path { return e.node }
            if p.hasPrefix(e.path + "/") {
                var n: FSNode? = e.node
                for c in FileSystem.parts(String(p.dropFirst(e.path.count + 1))) { n = n?.children?[c] }
                return n
            }
        }
        return nil
    }

    func gzip(_ rest: [String], unpack: Bool) {
        let (f, files) = split(rest)
        let unpack = unpack || f.contains("d")
        let cmd = unpack ? "gunzip" : "gzip"
        guard !files.isEmpty else { err("usage: \(cmd) [-dk] file ..."); return }
        for p in files {
            let abs = path(p)
            guard let n = fs.node(abs) else { err("\(cmd): can't stat: \(p) (\(p)): No such file or directory"); continue }
            guard !n.isDir else { err("\(cmd): \(p) is a directory -- ignored"); continue }
            if unpack {
                guard p.hasSuffix(".gz") else { err("gunzip: \(p): unknown suffix -- ignored"); continue }
                guard let a = n.archive, a.kind == "gz", let e = a.entries.first else { err("gunzip: \(p): not in gzip format"); continue }
                place(e.node, at: String(abs.dropLast(3)))
            } else {
                guard !p.hasSuffix(".gz") else { err("gzip: \(p): already has .gz suffix -- unchanged"); continue }
                fs.write(abs + ".gz", tr("(сжатый файл)\n", "(compressed file)\n"))
                fs.node(abs + ".gz")?.archive = Archive(kind: "gz", entries: [(FileSystem.base(abs), n.clone())])
            }
            if !f.contains("k") { fs.remove(abs) }
        }
    }
}

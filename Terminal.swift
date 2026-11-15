import Foundation

struct Key {
    let name: String   // "a", "enter", "ctrl+u", "opt+left", "cmd+shift+]"
    let text: String

    var printable: String? {
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({
            $0.value >= 0x20 && $0.value != 0x7F && !(0xF700...0xF8FF).contains($0.value)
        }) else { return nil }
        return text
    }
}

enum TermMode { case shell, running, nano, vim, less }

struct TermTab {
    var cwd = FileSystem.home
    var oldpwd: String?
    var lines: [String] = []
    var history: [String] = []
}

private struct Token {
    var text: String
    var quoted = false
    var op = false
}

final class Terminal: ObservableObject {
    static let cmdKeys: Set<String> = ["cmd+t", "cmd+w", "cmd+shift+]", "cmd+shift+[", "cmd+k"]
    static let commands = ["cat", "cd", "clear", "cp", "echo", "find", "grep", "head", "less", "ls",
                           "mkdir", "mv", "nano", "pwd", "rm", "rmdir", "tail", "touch", "vi", "vim", "wc"]

    let fs = FileSystem.standard()
    @Published var tabs = [TermTab()]
    @Published var current = 0
    @Published var input = ""
    @Published var cursor = 0
    @Published var mode = TermMode.shell
    @Published var search: String?
    @Published var nano: Nano?
    @Published var vim: Vim?
    @Published var less: Less?

    private var historyIndex: Int?
    private var savedInput = ""
    private var searchFrom = 0
    private var typedChars = 0
    private var failed = false

    // для проверки упражнений
    var lastCommand = ""
    var lastOutput: [String] = []
    var lastTypedChars = 0
    var lastNames: [String] = []   // все команды последней строки
    var events: Set<String> = []

    var cwd: String {
        get { tabs[current].cwd }
        set { tabs[current].cwd = newValue }
    }

    var lines: [String] {
        get { tabs[current].lines }
        set { tabs[current].lines = newValue }
    }

    var prompt: String {
        "student@keydojo \(cwd == FileSystem.home ? "~" : FileSystem.base(cwd)) % "
    }

    // ~ здесь не раскрывается: это уже сделал разбор строки, а "~" в кавычках — обычное имя
    func path(_ p: String) -> String { fs.absolute(p, cwd: cwd, tilde: false) }

    func resetChecks() {
        lastCommand = ""
        lastOutput = []
        lastTypedChars = 0
        events = []
    }

    // MARK: клавиши

    func handle(_ key: Key) {
        events.insert("key:" + key.name)
        if mode == .shell, search == nil, Self.cmdKeys.contains(key.name) {
            tabKey(key.name)
            return
        }
        switch mode {
        case .shell:
            if search == nil { shellKey(key) } else { searchKey(key) }
        case .running:
            if key.name == "ctrl+c" {
                lines.append("^C")
                mode = .shell
                events.insert("interrupt")
            }
        case .nano: nanoKey(key)
        case .vim: vimKey(key)
        case .less: lessKey(key)
        }
    }

    private func tabKey(_ name: String) {
        switch name {
        case "cmd+t":
            tabs.append(TermTab(cwd: cwd, history: tabs[current].history))
            current = tabs.count - 1
        case "cmd+w":
            guard tabs.count > 1 else { return }
            // как в macOS: после закрытия выбирается соседняя вкладка справа
            let i = current
            current = min(i, tabs.count - 2)
            tabs.remove(at: i)
        case "cmd+shift+]": current = (current + 1) % tabs.count
        case "cmd+shift+[": current = (current + tabs.count - 1) % tabs.count
        case "cmd+k": lines = []
        default: return
        }
        set([], 0)
        historyIndex = nil
    }

    private func set(_ chars: [Character], _ pos: Int) {
        input = String(chars)
        cursor = pos
    }

    private func wordStart(_ c: [Character], _ pos: Int) -> Int {
        var i = pos
        while i > 0 && c[i - 1] == " " { i -= 1 }
        while i > 0 && c[i - 1] != " " { i -= 1 }
        return i
    }

    private func wordEnd(_ c: [Character], _ pos: Int) -> Int {
        var i = pos
        while i < c.count && c[i] == " " { i += 1 }
        while i < c.count && c[i] != " " { i += 1 }
        return i
    }

    private func shellKey(_ key: Key) {
        var chars = Array(input)
        switch key.name {
        case "enter":
            let line = input
            set([], 0)
            historyIndex = nil
            lastTypedChars = typedChars
            typedChars = 0
            run(line)
        case "backspace":
            guard cursor > 0 else { return }
            chars.remove(at: cursor - 1)
            set(chars, cursor - 1)
        case "delete", "ctrl+d":
            guard cursor < chars.count else { return }
            chars.remove(at: cursor)
            set(chars, cursor)
        case "left", "ctrl+b": cursor = max(0, cursor - 1)
        case "right", "ctrl+f": cursor = min(chars.count, cursor + 1)
        case "ctrl+a", "home": cursor = 0
        case "ctrl+e", "end": cursor = chars.count
        case "opt+left": cursor = wordStart(chars, cursor)
        case "opt+right": cursor = wordEnd(chars, cursor)
        case "ctrl+u": set([], 0)
        case "ctrl+k": set(Array(chars[..<cursor]), cursor)
        case "ctrl+w", "opt+backspace":
            let s = wordStart(chars, cursor)
            chars.removeSubrange(s..<cursor)
            set(chars, s)
        case "ctrl+c":
            lines.append(prompt + input + "^C")
            set([], 0)
            historyIndex = nil
        case "ctrl+l": lines = []
        case "up", "ctrl+p": historyStep(-1)
        case "down", "ctrl+n": historyStep(1)
        case "tab": complete()
        case "ctrl+r":
            search = ""
            searchFrom = tabs[current].history.count
        default:
            guard let t = key.printable else { return }
            chars.insert(contentsOf: t, at: cursor)
            set(chars, cursor + t.count)
            typedChars += t.count
        }
    }

    private func historyStep(_ d: Int) {
        let h = tabs[current].history
        guard !h.isEmpty else { return }
        if d < 0 {
            let i: Int
            if let cur = historyIndex { i = max(0, cur - 1) } else { savedInput = input; i = h.count - 1 }
            historyIndex = i
            set(Array(h[i]), h[i].count)
        } else {
            guard let cur = historyIndex else { return }
            if cur + 1 < h.count {
                historyIndex = cur + 1
                set(Array(h[cur + 1]), h[cur + 1].count)
            } else {
                historyIndex = nil
                set(Array(savedInput), savedInput.count)
            }
        }
    }

    func searchMatch() -> Int? {
        guard let q = search, !q.isEmpty else { return nil }
        let h = tabs[current].history
        var i = min(searchFrom, h.count) - 1
        while i >= 0 {
            if h[i].contains(q) { return i }
            i -= 1
        }
        return nil
    }

    private func searchKey(_ key: Key) {
        let h = tabs[current].history
        switch key.name {
        case "enter":
            if let m = searchMatch() {
                set(Array(h[m]), h[m].count)
                events.insert("usedsearch")
            }
            search = nil
            shellKey(key)
        case "ctrl+r":
            guard let m = searchMatch() else { return }
            let old = searchFrom
            searchFrom = m
            if searchMatch() == nil { searchFrom = old }
        case "esc", "left", "right", "ctrl+a", "ctrl+e":
            if let m = searchMatch() {
                set(Array(h[m]), h[m].count)
                events.insert("usedsearch")
            }
            search = nil
        case "ctrl+c", "ctrl+g": search = nil
        case "backspace":
            if search?.isEmpty == false { search?.removeLast() }
            searchFrom = h.count
        default:
            guard let t = key.printable else { return }
            search? += t
            searchFrom = h.count
        }
    }

    private func complete() {
        let chars = Array(input)
        let before = Array(chars[..<cursor])
        let start = before.lastIndex(of: " ").map { $0 + 1 } ?? 0
        let word = String(before[start...])
        let isCommand = before[..<start].allSatisfy { $0 == " " }
        var dirPart = "", prefix = word
        var names: [String] = []
        var suffix: [String: String] = [:]
        if isCommand && !word.contains("/") {
            names = Self.commands.filter { $0.hasPrefix(word) }
            for n in names { suffix[n] = " " }
        } else {
            if let slash = word.lastIndex(of: "/") {
                dirPart = String(word[...slash])
                prefix = String(word[word.index(after: slash)...])
            }
            guard let ch = fs.node(fs.absolute(dirPart.isEmpty ? "." : dirPart, cwd: cwd))?.children else { return }
            names = ch.keys.filter { $0.hasPrefix(prefix) && (prefix.hasPrefix(".") || !$0.hasPrefix(".")) }.sorted()
            for n in names { suffix[n] = ch[n]!.isDir ? "/" : " " }
        }
        guard !names.isEmpty else { return }
        var insert: String
        if names.count == 1 {
            insert = names[0] + suffix[names[0]]!
        } else {
            insert = names[0]
            for n in names.dropFirst() { while !n.hasPrefix(insert) { insert.removeLast() } }
            if insert.count <= prefix.count {
                lines.append(prompt + input)
                lines.append(names.map { $0 + (suffix[$0] == "/" ? "/" : "") }.joined(separator: "  "))
                return
            }
        }
        let replaced = Array(before[..<start]) + Array(dirPart + insert)
        set(replaced + chars[cursor...], replaced.count)
    }

    // MARK: выполнение команд

    func run(_ raw: String) {
        lines.append(prompt + raw)
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        if tabs[current].history.last != line { tabs[current].history.append(line) }
        lastCommand = line
        lastOutput = []
        lastNames = []
        execute(line)
    }

    private func err(_ line: String) {
        lines.append(line)
        failed = true
    }

    private func out(_ text: String) {
        lines.append(contentsOf: textLines(text))
    }

    private func textLines(_ s: String) -> [String] {
        var l = s.components(separatedBy: "\n")
        if l.last == "" { l.removeLast() }
        return l
    }

    private func joined(_ l: [String]) -> String {
        l.isEmpty ? "" : l.joined(separator: "\n") + "\n"
    }

    private var variables: [String: String] {
        ["HOME": FileSystem.home, "USER": "student", "SHELL": "/bin/zsh", "PWD": cwd,
         "OLDPWD": tabs[current].oldpwd ?? "", "PATH": "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
    }

    // $NAME или ${NAME}: значение и сколько символов занимает имя
    private func variable(_ c: [Character], _ start: Int) -> (value: String, len: Int)? {
        guard start < c.count else { return nil }
        var name = ""
        var len = 0
        if c[start] == "{" {
            guard let close = c[start...].firstIndex(of: "}") else { return nil }
            name = String(c[(start + 1)..<close])
            len = close - start + 1
        } else {
            var i = start
            while i < c.count, c[i] == "_" || c[i].isASCII && (c[i].isLetter || c[i].isNumber && i > start) {
                name.append(c[i])
                i += 1
            }
            len = i - start
        }
        guard !name.isEmpty else { return nil }
        return (variables[name] ?? "", len)
    }

    private func tokenize(_ s: String) -> [Token]? {
        var tokens: [Token] = []
        var cur: Token?
        var quote: Character?
        let chars = Array(s)
        var i = 0
        func flush() {
            if let c = cur { tokens.append(c) }
            cur = nil
        }
        func add(_ str: String, quoted: Bool = false) {
            if cur == nil { cur = Token(text: "") }
            cur!.text += str
            if quoted { cur!.quoted = true }
        }
        func op(_ o: String) {
            flush()
            tokens.append(Token(text: o, op: true))
        }
        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            if c == "$", quote != "'", let v = variable(chars, i + 1) {
                add(v.value, quoted: true)
                i += 1 + v.len
                continue
            }
            if let q = quote {
                if c == q { quote = nil } else { add(String(c)) }
            } else if c == "\"" || c == "'" {
                quote = c
                add("", quoted: true)
            } else if c == "\\", let n = next {
                add(String(n), quoted: true)
                i += 1
            } else if c == " " || c == "\t" {
                flush()
            } else if c == "~", cur == nil, next == nil || next == "/" || next == " " {
                // ~ раскрывается только без кавычек и в начале слова
                add(FileSystem.home)
            } else if c == "|" {
                if next == "|" { op("||"); i += 1 } else { op("|") }
            } else if c == "&", next == "&" {
                op("&&")
                i += 1
            } else if c == ";" {
                op(";")
            } else if c == "<" {
                op("<")
            } else if c == ">" {
                if next == ">" { op(">>"); i += 1 } else { op(">") }
            } else {
                add(String(c))
            }
            i += 1
        }
        if quote != nil { return nil }
        flush()
        return tokens
    }

    private func expand(_ t: Token) -> [String]? {
        guard !t.quoted, t.text.contains("*") || t.text.contains("?") else { return [t.text] }
        let slash = t.text.lastIndex(of: "/")
        let dirPart = slash.map { String(t.text[...$0]) } ?? ""
        let pattern = slash.map { String(t.text[t.text.index(after: $0)...]) } ?? t.text
        guard let ch = fs.node(path(dirPart.isEmpty ? "." : dirPart))?.children else { return nil }
        let found = ch.keys.filter { !$0.hasPrefix(".") && FileSystem.matches(pattern, $0) }.sorted()
        return found.isEmpty ? nil : found.map { dirPart + $0 }
    }

    // строка делится на части по ; && ||, каждая часть — конвейер
    private func execute(_ line: String) {
        guard let tokens = tokenize(line) else { err("zsh: unmatched quote"); return }
        var parts: [(cond: String, tokens: [Token])] = [(";", [])]
        for t in tokens {
            if t.op && [";", "&&", "||"].contains(t.text) {
                parts.append((t.text, []))
            } else {
                parts[parts.count - 1].tokens.append(t)
            }
        }
        for (n, p) in parts.enumerated() where p.tokens.isEmpty {
            let last = n == parts.count - 1
            if last && p.cond == ";" { continue }
            err("zsh: parse error near `\(last ? p.cond : parts[n + 1].cond)'")
            return
        }
        lastNames = []
        var ok = true
        for p in parts where !p.tokens.isEmpty {
            if p.cond == "&&" && !ok { continue }
            if p.cond == "||" && ok { continue }
            ok = pipeline(p.tokens)
            if mode != .shell { return }
        }
    }

    // true, если последняя команда завершилась без ошибки
    private func pipeline(_ tokens: [Token]) -> Bool {
        var segments: [[String]] = [[]]
        var redirect: (path: String, append: Bool)?
        var input: String?
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if t.op && t.text == "|" {
                segments.append([])
            } else if t.op {
                guard i + 1 < tokens.count, !tokens[i + 1].op else { err("zsh: parse error near `\\n'"); return false }
                let target = tokens[i + 1].text
                if t.text == "<" {
                    guard let n = fs.node(path(target)), !n.isDir else {
                        err("zsh: no such file or directory: \(target)")
                        return false
                    }
                    input = n.content
                } else {
                    redirect = (target, t.text == ">>")
                }
                i += 1
            } else {
                guard let words = expand(t) else { err("zsh: no matches found: \(t.text)"); return false }
                segments[segments.count - 1] += words
            }
            i += 1
        }
        // "> файл" без команды делает файл пустым
        if segments == [[]], let r = redirect {
            if !fs.write(path(r.path), "", append: r.append) { err("zsh: no such file or directory: \(r.path)") }
            return !failed
        }
        if segments.contains(where: { $0.isEmpty }) { err("zsh: parse error near `|'"); return false }
        for s in segments { events.insert("cmd:" + s[0]) }
        lastNames += segments.map { $0[0] }

        failed = false
        if segments.count == 1, redirect == nil {
            let args = segments[0]
            let arg = args.dropFirst().first
            switch args[0] {
            case "clear": lines = []; return true
            case "nano": openNano(arg); return !failed
            case "vim", "vi": openVim(arg); return !failed
            case "less", "more": openLess(arg, text: input); return !failed
            case "tail" where args.contains("-f"):
                out(command(args, stdin: input, tty: true))
                if !failed {
                    mode = .running
                    events.insert("tailf")
                }
                return !failed
            default: break
            }
        }

        var data = input
        for (n, args) in segments.enumerated() {
            let last = n == segments.count - 1
            if last, n > 0, redirect == nil, ["less", "more"].contains(args[0]) {
                openLess(args.dropFirst().first, text: data)
                return true
            }
            failed = false
            data = command(args, stdin: data, tty: last && redirect == nil)
        }
        let result = data ?? ""
        if let r = redirect {
            let abs = path(r.path)
            if fs.node(abs)?.isDir == true {
                err("zsh: is a directory: \(r.path)")
            } else if !fs.write(abs, result, append: r.append) {
                err("zsh: no such file or directory: \(r.path)")
            }
        } else {
            out(result)
            lastOutput = textLines(result)
        }
        return !failed
    }

    private func split(_ args: [String]) -> (flags: Set<Character>, rest: [String]) {
        var f = Set<Character>()
        var r: [String] = []
        for a in args {
            if a.hasPrefix("-") && a.count > 1 { f.formUnion(a.dropFirst()) } else { r.append(a) }
        }
        return (f, r)
    }

    private func command(_ args: [String], stdin: String?, tty: Bool) -> String {
        let rest = Array(args.dropFirst())
        switch args[0] {
        case "pwd": return cwd + "\n"
        case "ls": return ls(rest, tty: tty)
        case "cd": return cd(rest)
        case "mkdir": mkdir(rest)
        case "touch": touch(rest)
        case "cp": copy(rest, move: false)
        case "mv": copy(rest, move: true)
        case "rm": rm(rest)
        case "rmdir": rmdir(rest)
        case "cat": return cat(rest, stdin)
        case "head", "tail": return headTail(args[0], rest, stdin)
        case "wc": return wc(rest, stdin)
        case "echo": return echo(rest)
        case "find": return find(rest)
        case "grep": return grep(rest, stdin)
        case "clear": lines = []
        case "nano", "vim", "vi", "less", "more": err(tr("\(args[0]): в тренажёре запускай отдельно, без | и >", "\(args[0]): run it on its own here, without | and >"))
        default: err("zsh: command not found: \(args[0])")
        }
        return ""
    }

    private func readFile(_ p: String, _ cmd: String) -> String? {
        guard let n = fs.node(path(p)) else { err("\(cmd): \(p): No such file or directory"); return nil }
        guard !n.isDir else { err("\(cmd): \(p): Is a directory"); return nil }
        return n.content
    }

    private func ls(_ args: [String], tty: Bool) -> String {
        let (f, paths) = split(args)
        let all = f.contains("a"), long = f.contains("l")
        let targets = paths.isEmpty ? ["."] : paths
        var res: [String] = []
        var files: [String] = []
        var dirs: [(String, FSNode, [String: FSNode])] = []
        for p in targets {
            guard let n = fs.node(path(p)) else { err("ls: \(p): No such file or directory"); continue }
            if let ch = n.children { dirs.append((p, n, ch)) } else { files.append(long ? longLine(p, n) : p) }
        }
        if !files.isEmpty { res += tty && !long ? [files.joined(separator: "  ")] : files }
        for (p, n, ch) in dirs {
            if targets.count > 1 {
                if !res.isEmpty { res.append("") }
                res.append("\(p):")
            }
            var names = ch.keys.filter { all || !$0.hasPrefix(".") }.sorted()
            if all { names = [".", ".."] + names }
            if long {
                res.append("total \(names.count * 8)")
                for name in names { res.append(longLine(name, ch[name] ?? n)) }
            } else if tty {
                if !names.isEmpty { res.append(names.joined(separator: "  ")) }
            } else {
                res += names
            }
        }
        return joined(res)
    }

    private func longLine(_ name: String, _ n: FSNode) -> String {
        let size = String(n.children.map { 64 + 32 * $0.count } ?? n.content.utf8.count)
        let pad = String(repeating: " ", count: max(0, 6 - size.count))
        return "\(n.isDir ? "drwxr-xr-x" : "-rw-r--r--")  1 student  staff \(pad)\(size) Nov 15 10:00 \(name)"
    }

    private func cd(_ args: [String]) -> String {
        if args.count == 2 { err("cd: string not in pwd: \(args[0])"); return "" }
        if args.count > 2 { err("cd: too many arguments"); return "" }
        var target = args.first ?? FileSystem.home
        var show = false
        if target == "-" {
            guard let old = tabs[current].oldpwd else { err("cd: OLDPWD not set"); return "" }
            target = old
            show = true
        }
        let abs = path(target)
        guard let n = fs.node(abs) else { err("cd: no such file or directory: \(target)"); return "" }
        guard n.isDir else { err("cd: not a directory: \(target)"); return "" }
        tabs[current].oldpwd = cwd
        cwd = abs
        return show ? FileSystem.pretty(abs) + "\n" : ""
    }

    private func mkdir(_ args: [String]) {
        let (f, names) = split(args)
        if names.isEmpty { err("usage: mkdir [-pv] [-m mode] directory_name ..."); return }
        for p in names {
            let abs = path(p)
            if let n = fs.node(abs) {
                if !(f.contains("p") && n.isDir) { err("mkdir: \(p): File exists") }
            } else if f.contains("p") {
                if fs.mkdirs(abs) == nil { err("mkdir: \(p): Not a directory") }
            } else if let par = fs.parent(abs) {
                par.dir.children?[par.name] = FSNode()
            } else {
                err("mkdir: \(p): No such file or directory")
            }
        }
    }

    private func touch(_ args: [String]) {
        if args.isEmpty { err("usage: touch file ..."); return }
        for p in split(args).rest {
            let abs = path(p)
            if fs.node(abs) != nil { continue }
            if !fs.write(abs, "") { err("touch: \(p): No such file or directory") }
        }
    }

    private func copy(_ args: [String], move: Bool) {
        let (f, ops) = split(args)
        let cmd = move ? "mv" : "cp"
        guard ops.count >= 2, let dst = ops.last else {
            err(move ? "usage: mv source target" : "usage: cp [-R] source_file target_file")
            return
        }
        let dstAbs = path(dst)
        let dstIsDir = fs.node(dstAbs)?.isDir == true
        let srcs = ops.dropLast()
        if srcs.count > 1 && !dstIsDir { err("\(cmd): \(dst) is not a directory"); return }
        for src in srcs {
            let srcAbs = path(src)
            guard let node = fs.node(srcAbs) else { err("\(cmd): \(src): No such file or directory"); continue }
            if node.isDir && !move && !(f.contains("r") || f.contains("R")) {
                err("cp: \(src) is a directory (not copied).")
                continue
            }
            let target = fs.absolute(dstIsDir ? dstAbs + "/" + FileSystem.base(srcAbs) : dstAbs, cwd: "/")
            if target == srcAbs && !move {
                err("cp: \(src) and \(dst) are identical (not copied).")
                continue
            }
            if target == srcAbs || target.hasPrefix(srcAbs + "/") || srcAbs == "/" {
                err("\(cmd): \(src): Invalid argument")
                continue
            }
            guard let par = fs.parent(target) else { err("\(cmd): \(dst): No such file or directory"); continue }
            if move { fs.remove(srcAbs) }
            par.dir.children?[par.name] = move ? node : node.clone()
        }
    }

    private func rm(_ args: [String]) {
        let (f, ps) = split(args)
        let rec = f.contains("r") || f.contains("R"), force = f.contains("f")
        if ps.isEmpty { err("usage: rm [-f | -i] [-dIPRrvWx] file ..."); return }
        for p in ps {
            if p == "." || p == ".." { err("rm: \".\" and \"..\" may not be removed"); continue }
            let abs = path(p)
            guard let n = fs.node(abs) else {
                if !force { err("rm: \(p): No such file or directory") }
                continue
            }
            if abs == "/" { err("rm: \"/\" may not be removed"); continue }
            if n.isDir && !rec { err("rm: \(p): is a directory"); continue }
            fs.remove(abs)
        }
    }

    private func rmdir(_ args: [String]) {
        if args.isEmpty { err("usage: rmdir directory ..."); return }
        for p in args {
            let abs = path(p)
            guard let n = fs.node(abs) else { err("rmdir: \(p): No such file or directory"); continue }
            guard let ch = n.children else { err("rmdir: \(p): Not a directory"); continue }
            guard ch.isEmpty else { err("rmdir: \(p): Directory not empty"); continue }
            fs.remove(abs)
        }
    }

    private func cat(_ args: [String], _ stdin: String?) -> String {
        if args.isEmpty { return stdin ?? "" }
        return args.compactMap { readFile($0, "cat") }.joined()
    }

    private func headTail(_ name: String, _ args: [String], _ stdin: String?) -> String {
        var count = 10
        var files: [String] = []
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "-n", i + 1 < args.count {
                guard let v = Int(args[i + 1]), v >= 0 else {
                    err(name == "head" ? "head: illegal line count -- \(args[i + 1])" : "tail: illegal offset -- \(args[i + 1])")
                    return ""
                }
                count = v
                i += 2
                continue
            }
            if a.hasPrefix("-n"), let v = Int(a.dropFirst(2)) {
                count = v
            } else if a == "-f" {
            } else if a.hasPrefix("-"), let v = Int(a.dropFirst()) {
                count = v
            } else {
                files.append(a)
            }
            i += 1
        }
        let text: String
        if let p = files.first {
            guard let t = readFile(p, name) else { return "" }
            text = t
        } else {
            text = stdin ?? ""
        }
        let l = textLines(text)
        return joined(name == "head" ? Array(l.prefix(count)) : Array(l.suffix(count)))
    }

    private func wc(_ args: [String], _ stdin: String?) -> String {
        let (f, files) = split(args)
        func counts(_ text: String) -> [Int] {
            let l = text.filter { $0 == "\n" }.count
            let w = text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
            var cols: [Int] = []
            if f.isEmpty || f.contains("l") { cols.append(l) }
            if f.isEmpty || f.contains("w") { cols.append(w) }
            if f.isEmpty || f.contains("c") { cols.append(text.utf8.count) }
            return cols
        }
        func row(_ cols: [Int], _ label: String) -> String {
            cols.map { v -> String in
                let t = String(v)
                return String(repeating: " ", count: max(0, 8 - t.count)) + t
            }.joined() + label
        }
        if files.isEmpty { return row(counts(stdin ?? ""), "") + "\n" }
        var rows: [String] = []
        var total: [Int]?
        for p in files {
            guard let t = readFile(p, "wc") else { continue }
            let c = counts(t)
            rows.append(row(c, " " + p))
            total = total.map { zip($0, c).map(+) } ?? c
        }
        if files.count > 1, let total { rows.append(row(total, " total")) }
        return joined(rows)
    }

    private func echo(_ args: [String]) -> String {
        var a = args
        var newline = true
        if a.first == "-n" {
            newline = false
            a.removeFirst()
        }
        return a.joined(separator: " ") + (newline ? "\n" : "")
    }

    private func walk(_ n: FSNode, _ p: String, _ visit: (FSNode, String) -> Void) {
        visit(n, p)
        guard let ch = n.children else { return }
        for k in ch.keys.sorted() { walk(ch[k]!, p.hasSuffix("/") ? p + k : p + "/" + k, visit) }
    }

    private func find(_ args: [String]) -> String {
        var start = "."
        var i = 0
        if let f = args.first, !f.hasPrefix("-") {
            start = f
            i = 1
        }
        var name: String?
        var ignoreCase = false
        var type: String?
        while i < args.count {
            let a = args[i]
            guard i + 1 < args.count else { err("find: \(a): requires additional arguments"); return "" }
            switch a {
            case "-name": name = args[i + 1]
            case "-iname": name = args[i + 1]; ignoreCase = true
            case "-type": type = args[i + 1]
            default: err("find: \(a): unknown primary or operator"); return ""
            }
            i += 2
        }
        guard let root = fs.node(path(start)) else { err("find: \(start): No such file or directory"); return "" }
        var res: [String] = []
        walk(root, start) { n, p in
            let okName = name.map { FileSystem.matches($0, FileSystem.base(p), ignoreCase: ignoreCase) } ?? true
            let okType = type.map { $0 == "d" ? n.isDir : !n.isDir } ?? true
            if okName && okType { res.append(p) }
        }
        return joined(res)
    }

    private func grep(_ args: [String], _ stdin: String?) -> String {
        let (f, ops) = split(args)
        guard let pattern = ops.first else { err("usage: grep [-cilnrvE] pattern [file ...]"); return "" }
        let rec = f.contains("r") || f.contains("R"), num = f.contains("n")
        let ic = f.contains("i"), inv = f.contains("v"), count = f.contains("c"), names = f.contains("l")
        var regex: NSRegularExpression?
        if f.contains("E") {
            guard let r = try? NSRegularExpression(pattern: pattern, options: ic ? [.caseInsensitive] : []) else {
                err("grep: invalid regular expression")
                return ""
            }
            regex = r
        }
        func hit(_ line: String) -> Bool {
            if let regex { return regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil }
            return ic ? line.lowercased().contains(pattern.lowercased()) : line.contains(pattern)
        }
        var res: [String] = []
        var found = false
        func scan(_ text: String, _ label: String?) {
            let prefix = label.map { $0 + ":" } ?? ""
            var matched: [String] = []
            for (k, line) in textLines(text).enumerated() where hit(line) != inv {
                matched.append(prefix + (num ? "\(k + 1):" : "") + line)
            }
            if !matched.isEmpty { found = true }
            if names {
                if !matched.isEmpty { res.append(label ?? "(standard input)") }
            } else if count {
                res.append(prefix + String(matched.count))
            } else {
                res += matched
            }
        }
        var files = Array(ops.dropFirst())
        if files.isEmpty && !rec {
            scan(stdin ?? "", nil)
        } else {
            if files.isEmpty { files = ["."] }
            let multi = rec || files.count > 1
            for p in files {
                guard let n = fs.node(path(p)) else { err("grep: \(p): No such file or directory"); continue }
                if n.isDir {
                    guard rec else { err("grep: \(p): Is a directory"); continue }
                    walk(n, p) { node, fp in if !node.isDir { scan(node.content, fp) } }
                } else {
                    // для -l имя файла нужно и без -r
                    scan(n.content, multi || names ? p : nil)
                }
            }
        }
        if !found { failed = true }
        return joined(res)
    }

    // MARK: nano

    private func openNano(_ p: String?) {
        var text = ""
        if let p, let n = fs.node(path(p)) {
            guard !n.isDir else { err("nano: \(p) is a directory"); return }
            text = n.content
        }
        var buf = Buffer(text)
        // как в настоящем nano: после последней строки файла есть пустая
        if buf.lines.last != "" { buf.lines.append("") }
        nano = Nano(name: p ?? "", buf: buf)
        mode = .nano
    }

    private func closeNano() {
        nano = nil
        mode = .shell
        events.insert("nano:exit")
    }

    private func nanoKey(_ key: Key) {
        guard var n = nano else { return }
        defer { if mode == .nano { nano = n } }

        if let p = n.prompt {
            switch p {
            case .confirm:
                if key.name == "y" {
                    n.prompt = .save(n.name, exit: true)
                } else if key.name == "n" {
                    closeNano()
                } else if key.name == "ctrl+c" {
                    n.prompt = nil
                }
            case .save(var text, let exit):
                switch key.name {
                case "enter":
                    n.prompt = nil
                    guard !text.isEmpty, fs.write(fs.absolute(text, cwd: cwd), n.text) else {
                        n.message = "[ Error writing \(text) ]"
                        return
                    }
                    n.name = text
                    n.modified = false
                    n.message = "[ Wrote \(n.text.filter { $0 == "\n" }.count) lines ]"
                    events.insert("nano:save")
                    if exit { closeNano() }
                case "ctrl+c":
                    n.prompt = nil
                    n.message = "[ Cancelled ]"
                case "backspace":
                    if !text.isEmpty { text.removeLast() }
                    n.prompt = .save(text, exit: exit)
                default:
                    if let t = key.printable { n.prompt = .save(text + t, exit: exit) }
                }
            case .search(var q):
                switch key.name {
                case "enter":
                    n.prompt = nil
                    if q.isEmpty { q = n.lastSearch }
                    n.lastSearch = q
                    events.insert("nano:search")
                    if !n.buf.find(q, after: true) { n.message = "[ \"\(q)\" not found ]" }
                case "ctrl+c":
                    n.prompt = nil
                    n.message = "[ Cancelled ]"
                case "backspace":
                    if !q.isEmpty { q.removeLast() }
                    n.prompt = .search(q)
                default:
                    if let t = key.printable { n.prompt = .search(q + t) }
                }
            }
            return
        }

        n.message = nil
        let chain = n.cutChain
        n.cutChain = false
        switch key.name {
        case "ctrl+o": n.prompt = .save(n.name, exit: false)
        case "ctrl+x":
            if n.modified { n.prompt = .confirm } else { closeNano() }
        case "ctrl+w": n.prompt = .search("")
        case "ctrl+k":
            let line = n.buf.lines.remove(at: n.buf.row)
            n.cut = chain ? n.cut + [line] : [line]
            if n.buf.lines.isEmpty { n.buf.lines = [""] }
            n.buf.row = min(n.buf.row, n.buf.lines.count - 1)
            n.buf.col = 0
            n.modified = true
            n.cutChain = true
        case "ctrl+u":
            guard !n.cut.isEmpty else { return }
            n.buf.lines.insert(contentsOf: n.cut, at: n.buf.row)
            n.buf.row += n.cut.count
            n.buf.col = 0
            n.modified = true
        case "enter": n.buf.newline(); n.modified = true
        case "backspace": n.buf.backspace(); n.modified = true
        case "delete", "ctrl+d": n.buf.deleteForward(); n.modified = true
        case "left", "right", "up", "down": n.buf.move(key.name)
        case "ctrl+a", "home": n.buf.col = 0
        case "ctrl+e", "end": n.buf.col = n.buf.lines[n.buf.row].count
        default:
            guard let t = key.printable else { return }
            n.buf.insert(t)
            n.modified = true
        }
    }

    // MARK: vim

    private func openVim(_ p: String?) {
        var text = ""
        var message: String?
        if let p {
            if let n = fs.node(path(p)) {
                guard !n.isDir else { err("vim: \(p) is a directory"); return }
                text = n.content
                message = "\"\(p)\" \(textLines(text).count)L, \(text.utf8.count)B"
            } else {
                message = "\"\(p)\" [New]"
            }
        }
        vim = Vim(name: p ?? "", buf: Buffer(text), message: message)
        mode = .vim
    }

    private func closeVim() {
        vim = nil
        mode = .shell
    }

    @discardableResult
    private func vimWrite(_ v: inout Vim) -> Bool {
        guard !v.name.isEmpty else { v.message = "E32: No file name"; return false }
        let text = v.buf.text
        guard fs.write(path(v.name), text) else {
            v.message = "\"\(v.name)\" E212: Can't open file for writing"
            return false
        }
        v.modified = false
        v.message = "\"\(v.name)\" \(v.buf.lines.count)L, \(text.utf8.count)B written"
        events.insert("vim:write")
        return true
    }

    // true, если нужно закрыть редактор
    private func vimCommand(_ v: inout Vim, _ c: String) -> Bool {
        switch c {
        case "": break
        case "w": vimWrite(&v)
        case "q":
            if v.modified {
                v.message = "E37: No write since last change (add ! to override)"
            } else {
                events.insert("vim:quit")
                return true
            }
        case "q!":
            events.insert("vim:forcequit")
            return true
        case "wq", "x", "wq!":
            if vimWrite(&v) {
                events.insert("vim:quit")
                return true
            }
        default: v.message = "E492: Not an editor command: \(c)"
        }
        return false
    }

    private func vimKey(_ key: Key) {
        guard var v = vim else { return }
        defer {
            if v.modified { events.insert("vim:modified") }
            if mode == .vim { vim = v }
        }
        switch v.vmode {
        case .insert:
            switch key.name {
            case "esc", "ctrl+c", "ctrl+[":
                v.vmode = .normal
                v.buf.col = max(0, v.buf.col - 1)
            case "enter": v.buf.newline(); v.modified = true
            case "backspace": v.buf.backspace(); v.modified = true
            case "left", "right", "up", "down": v.buf.move(key.name)
            default:
                guard let t = key.printable else { return }
                v.buf.insert(t)
                v.modified = true
            }
        case .command(var c):
            switch key.name {
            case "esc", "ctrl+c": v.vmode = .normal
            case "enter":
                v.vmode = .normal
                if vimCommand(&v, c.trimmingCharacters(in: .whitespaces)) { closeVim() }
            case "backspace":
                if c.isEmpty {
                    v.vmode = .normal
                } else {
                    c.removeLast()
                    v.vmode = .command(c)
                }
            default:
                if let t = key.printable { v.vmode = .command(c + t) }
            }
        case .normal:
            v.message = nil
            let len = v.buf.lines[v.buf.row].count
            let d = v.pendingD, g = v.pendingG
            v.pendingD = false
            v.pendingG = false
            switch key.printable ?? key.name {
            case "i": v.vmode = .insert
            case "a": v.buf.col = min(v.buf.col + 1, len); v.vmode = .insert
            case "A": v.buf.col = len; v.vmode = .insert
            case "I": v.buf.col = 0; v.vmode = .insert
            case "o":
                v.buf.lines.insert("", at: v.buf.row + 1)
                v.buf.row += 1
                v.buf.col = 0
                v.vmode = .insert
                v.modified = true
            case "O":
                v.buf.lines.insert("", at: v.buf.row)
                v.buf.col = 0
                v.vmode = .insert
                v.modified = true
            case "h", "left", "backspace": v.buf.col = max(0, v.buf.col - 1)
            case "l", "right", " ": v.buf.col += 1
            case "j", "down": v.buf.move("down")
            case "k", "up": v.buf.move("up")
            case "0": v.buf.col = 0
            case "$": v.buf.col = len
            case "G":
                v.buf.row = v.buf.lines.count - 1
                v.buf.col = 0
                events.insert("vim:G")
            case "g":
                if g {
                    v.buf.row = 0
                    v.buf.col = 0
                    events.insert("vim:gg")
                } else {
                    v.pendingG = true
                }
            case "x":
                if v.buf.col < len {
                    v.buf.deleteForward()
                    v.modified = true
                }
            case "d":
                if d {
                    v.buf.lines.remove(at: v.buf.row)
                    if v.buf.lines.isEmpty { v.buf.lines = [""] }
                    v.buf.row = min(v.buf.row, v.buf.lines.count - 1)
                    v.buf.col = 0
                    v.modified = true
                } else {
                    v.pendingD = true
                }
            case ":": v.vmode = .command("")
            default: break
            }
            if v.vmode == .normal {
                v.buf.col = min(v.buf.col, max(0, v.buf.lines[v.buf.row].count - 1))
            }
        }
    }

    // MARK: less

    private func openLess(_ p: String?, text: String?) {
        let content: String
        if let p {
            guard let n = fs.node(path(p)) else { err("\(p): No such file or directory"); return }
            guard !n.isDir else { err("\(p) is a directory"); return }
            content = n.content
        } else if let text {
            content = text
        } else {
            err("Missing filename (\"less --help\" for help)")
            return
        }
        less = Less(lines: textLines(content))
        mode = .less
    }

    private func lessKey(_ key: Key) {
        guard var l = less else { return }
        defer { if mode == .less { less = l } }

        if var p = l.prompt {
            switch key.name {
            case "enter":
                l.prompt = nil
                if !p.isEmpty { l.query = p }
                events.insert("less:search:" + l.query)
                if !l.find(from: l.top, forward: true) { l.message = "Pattern not found  (press RETURN)" }
            case "esc", "ctrl+c": l.prompt = nil
            case "backspace":
                if p.isEmpty {
                    l.prompt = nil
                } else {
                    p.removeLast()
                    l.prompt = p
                }
            default:
                if let t = key.printable { l.prompt = p + t }
            }
            return
        }

        l.message = nil
        if key.name == "q" {
            less = nil
            mode = .shell
            events.insert("less:quit")
            return
        }
        let page = Less.height - 1
        switch key.printable ?? key.name {
        case " ", "f", "pagedown", "ctrl+f": l.top = min(l.maxTop, l.top + page)
        case "b", "pageup", "ctrl+b": l.top = max(0, l.top - page)
        case "j", "down", "enter", "e": l.top = min(max(l.maxTop, l.top), l.top + 1)
        case "k", "up", "y": l.top = max(0, l.top - 1)
        case "g", "<": l.top = 0
        case "G", ">":
            l.top = l.maxTop
            events.insert("less:end")
        case "/": l.prompt = ""
        case "n" where l.query.isEmpty, "N" where l.query.isEmpty:
            l.message = "No previous regular expression"
        case "n":
            if l.find(from: l.top + 1, forward: true) {
                events.insert("less:next")
            } else {
                l.message = "Pattern not found  (press RETURN)"
            }
        case "N":
            if !l.find(from: l.top - 1, forward: false) { l.message = "Pattern not found  (press RETURN)" }
        default: break
        }
    }
}

// MARK: редакторы

struct Buffer {
    var lines: [String]
    var row = 0
    var col = 0

    init(_ text: String) {
        var l = text.components(separatedBy: "\n")
        if l.count > 1, l.last == "" { l.removeLast() }
        lines = l
    }

    var text: String { lines.joined(separator: "\n") + "\n" }

    mutating func insert(_ s: String) {
        var l = Array(lines[row])
        l.insert(contentsOf: s, at: col)
        lines[row] = String(l)
        col += s.count
    }

    mutating func newline() {
        let l = Array(lines[row])
        lines[row] = String(l[..<col])
        lines.insert(String(l[col...]), at: row + 1)
        row += 1
        col = 0
    }

    mutating func backspace() {
        if col > 0 {
            var l = Array(lines[row])
            l.remove(at: col - 1)
            lines[row] = String(l)
            col -= 1
        } else if row > 0 {
            col = lines[row - 1].count
            lines[row - 1] += lines[row]
            lines.remove(at: row)
            row -= 1
        }
    }

    mutating func deleteForward() {
        var l = Array(lines[row])
        if col < l.count {
            l.remove(at: col)
            lines[row] = String(l)
        } else if row + 1 < lines.count {
            lines[row] += lines[row + 1]
            lines.remove(at: row + 1)
        }
    }

    mutating func move(_ dir: String) {
        switch dir {
        case "left":
            if col > 0 { col -= 1 } else if row > 0 { row -= 1; col = lines[row].count }
        case "right":
            if col < lines[row].count { col += 1 } else if row + 1 < lines.count { row += 1; col = 0 }
        case "up":
            if row > 0 { row -= 1; col = min(col, lines[row].count) }
        case "down":
            if row + 1 < lines.count { row += 1; col = min(col, lines[row].count) }
        default: break
        }
    }

    // поиск без учёта регистра с переходом в начало файла
    mutating func find(_ q: String, after: Bool) -> Bool {
        guard !q.isEmpty else { return false }
        let needle = Array(q.lowercased())
        for step in 0...lines.count {
            let r = (row + step) % lines.count
            let hay = Array(lines[r].lowercased())
            let from = step == 0 ? col + (after ? 1 : 0) : 0
            guard needle.count <= hay.count, from <= hay.count - needle.count else { continue }
            for i in from...(hay.count - needle.count) where Array(hay[i..<i + needle.count]) == needle {
                row = r
                col = i
                return true
            }
        }
        return false
    }
}

struct Nano {
    enum Prompt { case save(String, exit: Bool), search(String), confirm }
    var name: String
    var buf: Buffer
    var modified = false
    var cut: [String] = []
    var cutChain = false
    var prompt: Prompt?
    var message: String?
    var lastSearch = ""

    var text: String {
        var l = buf.lines
        if l.last == "" { l.removeLast() }
        return l.isEmpty ? "" : l.joined(separator: "\n") + "\n"
    }
}

struct Vim {
    enum VMode: Equatable { case normal, insert, command(String) }
    var name: String
    var buf: Buffer
    var message: String?
    var vmode = VMode.normal
    var modified = false
    var pendingD = false
    var pendingG = false
}

struct Less {
    static let height = 20
    var lines: [String]
    var top = 0
    var query = ""
    var prompt: String?
    var message: String?

    var maxTop: Int { max(0, lines.count - Less.height) }

    mutating func find(from: Int, forward: Bool) -> Bool {
        guard !query.isEmpty, !lines.isEmpty else { return false }
        let range = forward ? Array(max(0, from)..<lines.count) : Array((0...max(0, min(from, lines.count - 1))).reversed())
        guard let i = range.first(where: { lines[$0].contains(query) }) else { return false }
        top = i
        return true
    }
}

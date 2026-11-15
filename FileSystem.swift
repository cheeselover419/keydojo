import Foundation

final class FSNode {
    var children: [String: FSNode]?
    var content: String
    var mode: Int                       // права, 0o755
    var archive: Archive?               // если файл — архив

    init(dir: [String: FSNode] = [:], mode: Int = 0o755) {
        children = dir
        content = ""
        self.mode = mode
    }

    init(file: String, mode: Int = 0o644) {
        children = nil
        content = file
        self.mode = mode
    }

    var isDir: Bool { children != nil }

    func clone() -> FSNode {
        let n = children.map { FSNode(dir: $0.mapValues { $0.clone() }, mode: mode) } ?? FSNode(file: content, mode: mode)
        n.archive = archive?.clone()
        return n
    }

    // rwxr-xr-x
    var permissions: String {
        (0..<9).map { i in mode & (0o400 >> i) != 0 ? Array("rwx")[i % 3] : "-" }.map(String.init).joined()
    }
}

// содержимое архива: пути внутри него и копии файлов и папок
struct Archive {
    var kind: String                    // tar, tar.gz, zip, gz
    var entries: [(path: String, node: FSNode)]

    func clone() -> Archive { Archive(kind: kind, entries: entries.map { ($0.path, $0.node.clone()) }) }

    // все пути, папки со слешем в конце, как в tar -t
    var listing: [String] {
        var res: [String] = []
        func add(_ p: String, _ n: FSNode) {
            guard let ch = n.children else { res.append(p); return }
            res.append(p + "/")
            for k in ch.keys.sorted() { add(p + "/" + k, ch[k]!) }
        }
        for e in entries { add(e.path, e.node) }
        return res
    }

    var files: [String] { listing.filter { !$0.hasSuffix("/") } }
}

// ненастоящая файловая система, на диск ничего не пишется
final class FileSystem {
    static let home = "/Users/student"
    let root = FSNode()

    static func parts(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    static func base(_ path: String) -> String { parts(path).last ?? "/" }

    static func pretty(_ abs: String) -> String {
        if abs == home { return "~" }
        if abs.hasPrefix(home + "/") { return "~" + abs.dropFirst(home.count) }
        return abs
    }

    static func matches(_ pattern: String, _ name: String, ignoreCase: Bool = false) -> Bool {
        NSPredicate(format: ignoreCase ? "SELF LIKE[c] %@" : "SELF LIKE %@", pattern).evaluate(with: name)
    }

    func absolute(_ path: String, cwd: String, tilde: Bool = true) -> String {
        var p = path
        if tilde && p == "~" { p = Self.home } else if tilde && p.hasPrefix("~/") { p = Self.home + p.dropFirst() }
        if !p.hasPrefix("/") { p = cwd + "/" + p }
        var out: [String] = []
        for c in Self.parts(p) {
            if c == "." { continue }
            if c == ".." { _ = out.popLast(); continue }
            out.append(c)
        }
        return "/" + out.joined(separator: "/")
    }

    func node(_ abs: String) -> FSNode? {
        var n = root
        for c in Self.parts(abs) {
            guard let next = n.children?[c] else { return nil }
            n = next
        }
        return n
    }

    func parent(_ abs: String) -> (dir: FSNode, name: String)? {
        var comps = Self.parts(abs)
        guard let name = comps.popLast(),
              let p = node("/" + comps.joined(separator: "/")), p.isDir else { return nil }
        return (p, name)
    }

    // nil, если по пути встретился файл
    @discardableResult
    func mkdirs(_ abs: String) -> FSNode? {
        var n = root
        for c in Self.parts(abs) {
            if let next = n.children?[c] {
                guard next.isDir else { return nil }
                n = next
            } else {
                let d = FSNode()
                n.children?[c] = d
                n = d
            }
        }
        return n
    }

    @discardableResult
    func write(_ abs: String, _ text: String, append: Bool = false) -> Bool {
        guard let p = parent(abs) else { return false }
        if let old = p.dir.children?[p.name] {
            guard !old.isDir else { return false }
            old.content = append ? old.content + text : text
        } else {
            p.dir.children?[p.name] = FSNode(file: text)
        }
        return true
    }

    func remove(_ abs: String) {
        guard let p = parent(abs) else { return }
        p.dir.children?[p.name] = nil
    }

    // для заготовок: создаёт папки по пути и файл
    func put(_ path: String, _ text: String) {
        let abs = absolute(path, cwd: Self.home)
        mkdirs("/" + Self.parts(abs).dropLast().joined(separator: "/"))
        write(abs, text)
    }

    static func standard() -> FileSystem {
        let fs = FileSystem()
        for d in ["/Applications/Safari.app", "/Applications/Terminal.app", "/Library", "/System",
                  "/Users/Shared", "/tmp", "/usr/bin", "/usr/local/bin", "~/Desktop", "~/empty"] {
            fs.mkdirs(fs.absolute(d, cwd: home))
        }
        fs.put("/etc/hosts", "127.0.0.1 localhost\n")
        fs.put("~/.zshrc", "export PATH=\"/usr/local/bin:$PATH\"\nalias ll=\"ls -la\"\n")
        fs.put("~/.gitconfig", "[user]\n    name = student\n")
        fs.put("~/notes.txt", tr("""
            Заметки
            - выучить горячие клавиши терминала
            - разобраться с nano и vim
            - меньше трогать мышь

            """, """
            Notes
            - learn terminal shortcuts
            - figure out nano and vim
            - touch the mouse less

            """))
        fs.put("~/draft.txt", tr("черновик\n", "draft\n"))
        fs.put("~/old.log", tr("старый лог\n", "old log\n"))
        for f in ["a.tmp", "b.tmp", "c.tmp"] { fs.put("~/trash/" + f, "") }
        fs.put("~/Documents/report.txt", tr("Отчёт за неделю\n", "Weekly report\n"))
        fs.put("~/Documents/ideas.txt", tr("Идеи\n", "Ideas\n"))
        fs.put("~/Downloads/photo.jpg", tr("(картинка)\n", "(image)\n"))
        fs.put("~/Downloads/installer.dmg", tr("(образ)\n", "(disk image)\n"))
        fs.put("~/Desktop/screenshot.png", tr("(скриншот)\n", "(screenshot)\n"))
        fs.put("~/projects/app/README.md", tr("""
            # app

            Учебный проект.

            TODO: написать инструкцию по запуску

            """, """
            # app

            Practice project.

            TODO: write how to run it

            """))
        fs.put("~/projects/app/main.py", """
            from src.utils import greet

            # TODO: \(tr("обработать ошибки", "handle errors"))
            print(greet("world"))

            """)
        fs.put("~/projects/app/src/utils.py", """
            def greet(name):
                # TODO: \(tr("добавить тесты", "add tests"))
                return f"Hello, {name}!"

            """)
        fs.put("~/projects/app/tests/test_utils.py", """
            from src.utils import greet


            def test_greet():
                assert greet("Bob") == "Hello, Bob!"

            """)
        fs.put("~/projects/app/app.log", appLog)
        fs.put("~/projects/site/index.html", "<h1>Hello</h1>\n")
        fs.put("~/projects/site/style.css", "/* TODO: \(tr("тёмная тема", "dark theme")) */\nbody { margin: 0; }\n")
        return fs
    }

    static let appLog = """
        2026-11-15 09:00:01 INFO  server started on port 8080
        2026-11-15 09:00:02 INFO  connected to database
        2026-11-15 09:01:15 INFO  GET /index.html 200
        2026-11-15 09:01:16 INFO  GET /style.css 200
        2026-11-15 09:02:40 WARN  slow query: 1200 ms
        2026-11-15 09:03:05 INFO  GET /api/users 200
        2026-11-15 09:03:06 ERROR database timeout
        2026-11-15 09:03:07 INFO  retrying connection
        2026-11-15 09:03:09 INFO  connected to database
        2026-11-15 09:05:30 WARN  disk usage 85%
        2026-11-15 09:06:12 INFO  GET /api/orders 200
        2026-11-15 09:07:44 ERROR null pointer in OrderService
        2026-11-15 09:07:45 INFO  POST /api/orders 500
        2026-11-15 09:08:01 INFO  GET /index.html 200
        2026-11-15 09:09:20 WARN  memory usage 90%
        2026-11-15 09:10:02 INFO  GET /api/users 200
        2026-11-15 09:11:33 ERROR failed to send email
        2026-11-15 09:12:00 INFO  cache cleared (warning: 2 keys expired)
        2026-11-15 09:12:30 INFO  GET /about.html 200
        2026-11-15 09:13:00 INFO  server is healthy

        """
}

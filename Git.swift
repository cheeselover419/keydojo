import Foundation

struct GitCommit {
    let hash: String
    let message: String
    let parents: [Int]
    let tree: [String: String]   // путь от корня репозитория → содержимое

    var short: String { String(hash.prefix(7)) }
}

// ненастоящий git: коммиты, ветки, индекс и stash в памяти
final class GitRepo {
    let root: String
    var commits: [GitCommit] = []
    var branches: [String: Int] = [:]
    var head = "main"
    var index: [String: String] = [:]
    var stash: [(index: [String: String], work: [String: String], message: String)] = []

    init(root: String) { self.root = root }

    var headCommit: Int? { branches[head] }
    var headTree: [String: String] { headCommit.map { commits[$0].tree } ?? [:] }

    func tree(_ branch: String) -> [String: String] { branches[branch].map { commits[$0].tree } ?? [:] }

    func ancestors(_ c: Int) -> Set<Int> {
        var seen: Set<Int> = []
        var todo = [c]
        while let x = todo.popLast() {
            if seen.insert(x).inserted { todo += commits[x].parents }
        }
        return seen
    }

    // история от HEAD, новые сверху
    var log: [Int] { headCommit.map { ancestors($0).sorted(by: >) } ?? [] }

    func addCommit(_ message: String, parents: [Int]) -> Int {
        var h: UInt64 = 0xcbf29ce484222325
        var hex = ""
        for salt in 0..<3 {
            for b in "\(root)\(commits.count)\(message)\(salt)".utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
            hex += String(format: "%016llx", h)
        }
        commits.append(GitCommit(hash: String(hex.prefix(40)), message: message, parents: parents, tree: index))
        branches[head] = commits.count - 1
        return commits.count - 1
    }
}

extension Terminal {
    // репозиторий, в котором находится текущая папка
    func repo(at dir: String? = nil) -> GitRepo? {
        var p = dir ?? cwd
        while true {
            if let r = repos[p], fs.node(p == "/" ? "/.git" : p + "/.git")?.isDir == true { return r }
            if p == "/" { return nil }
            p = "/" + FileSystem.parts(p).dropLast().joined(separator: "/")
        }
    }

    // для заготовок: репозиторий с коммитами; каждый следующий дописывает строку в CHANGELOG.md
    @discardableResult
    func gitRepo(_ dir: String, commits: [String]) -> GitRepo {
        let abs = fs.absolute(dir, cwd: FileSystem.home)
        fs.mkdirs(abs + "/.git")
        let r = GitRepo(root: abs)
        repos[abs] = r
        for (i, m) in commits.enumerated() {
            if i > 0 || commits.count > 1 { fs.write(abs + "/CHANGELOG.md", "- \(m)\n", append: true) }
            r.index = work(r)
            _ = r.addCommit(m, parents: r.headCommit.map { [$0] } ?? [])
        }
        return r
    }

    func work(_ r: GitRepo) -> [String: String] {
        var res: [String: String] = [:]
        func visit(_ n: FSNode, _ rel: String) {
            guard let ch = n.children else { res[rel] = n.content; return }
            for (k, v) in ch where !(rel.isEmpty && k == ".git") { visit(v, rel.isEmpty ? k : rel + "/" + k) }
        }
        if let n = fs.node(r.root) { visit(n, "") }
        return res
    }

    private func writeWork(_ r: GitRepo, _ rel: String, _ text: String?) {
        let abs = r.root + "/" + rel
        if let text {
            fs.mkdirs("/" + FileSystem.parts(abs).dropLast().joined(separator: "/"))
            fs.write(abs, text)
        } else {
            fs.remove(abs)
        }
    }

    private func applyTree(_ r: GitRepo, from: [String: String], to: [String: String]) {
        for k in from.keys where to[k] == nil { writeWork(r, k, nil) }
        for (k, v) in to { writeWork(r, k, v) }
    }

    private func rel(_ r: GitRepo, _ p: String) -> String? {
        let abs = path(p)
        if abs == r.root { return "" }
        return abs.hasPrefix(r.root + "/") ? String(abs.dropFirst(r.root.count + 1)) : nil
    }

    private func matching(_ keys: some Sequence<String>, _ rel: String) -> [String] {
        Set(keys).filter { rel.isEmpty || $0 == rel || $0.hasPrefix(rel + "/") }.sorted()
    }

    func gitChanges(_ r: GitRepo) -> (staged: [(String, String)], unstaged: [(String, String)], untracked: [String]) {
        let w = work(r), head = r.headTree
        var staged: [(String, String)] = []
        for k in Set(head.keys).union(r.index.keys).sorted() where head[k] != r.index[k] {
            staged.append((head[k] == nil ? "new file" : r.index[k] == nil ? "deleted" : "modified", k))
        }
        let unstaged = r.index.keys.sorted().filter { w[$0] != r.index[$0] }.map { (w[$0] == nil ? "deleted" : "modified", $0) }
        return (staged, unstaged, w.keys.filter { r.index[$0] == nil }.sorted())
    }

    private func dirty(_ r: GitRepo) -> Bool {
        let c = gitChanges(r)
        return !c.staged.isEmpty || !c.unstaged.isEmpty
    }

    func git(_ rest: [String]) -> String {
        guard let sub = rest.first else { return "usage: git <command> [<args>]\n" }
        events.insert("git:" + sub)
        let args = Array(rest.dropFirst())
        if sub == "init" { return gitInit() }
        if sub == "--version" || sub == "version" { return "git version 2.39.5\n" }
        guard let r = repo() else { err("fatal: not a git repository (or any of the parent directories): .git"); return "" }
        switch sub {
        case "status": return gitStatus(r, short: args.contains("-s") || args.contains("--short"))
        case "add": gitAdd(r, args)
        case "commit": return gitCommit(r, args)
        case "log": return gitLog(r, args)
        case "branch": return gitBranch(r, args)
        case "switch", "checkout": return gitSwitch(r, sub, args)
        case "diff": return gitDiff(r, args)
        case "restore": gitRestore(r, args)
        case "merge": return gitMerge(r, args)
        case "stash": return gitStash(r, args)
        default: err("git: '\(sub)' is not a git command. See 'git --help'.")
        }
        return ""
    }

    private func gitInit() -> String {
        if let r = repos[cwd], fs.node(cwd + "/.git") != nil { return "Reinitialized existing Git repository in \(r.root)/.git/\n" }
        fs.mkdirs(cwd + "/.git")
        repos[cwd] = GitRepo(root: cwd)
        return "Initialized empty Git repository in \(cwd)/.git/\n"
    }

    private func gitStatus(_ r: GitRepo, short: Bool) -> String {
        let c = gitChanges(r)
        if short {
            var rows: [String: (Character, Character)] = [:]
            for (kind, k) in c.staged { rows[k] = (Array(kind)[0] == "n" ? "A" : Array(kind)[0] == "d" ? "D" : "M", " ") }
            for (kind, k) in c.unstaged { rows[k] = (rows[k]?.0 ?? " ", kind == "deleted" ? "D" : "M") }
            return joined(rows.keys.sorted().map { "\(rows[$0]!.0)\(rows[$0]!.1) \($0)" } + c.untracked.map { "?? " + $0 })
        }
        func row(_ kind: String, _ k: String) -> String { "        " + (kind + ":").padding(toLength: 12, withPad: " ", startingAt: 0) + k }
        var res = ["On branch \(r.head)"]
        if r.commits.isEmpty { res += ["", "No commits yet"] }
        if !c.staged.isEmpty {
            res += ["", "Changes to be committed:", "  (use \"git restore --staged <file>...\" to unstage)"] + c.staged.map(row)
        }
        if !c.unstaged.isEmpty {
            res += ["", "Changes not staged for commit:", "  (use \"git add <file>...\" to update what will be committed)",
                    "  (use \"git restore <file>...\" to discard changes in working directory)"] + c.unstaged.map(row)
        }
        if !c.untracked.isEmpty {
            res += ["", "Untracked files:", "  (use \"git add <file>...\" to include in what will be committed)"] + c.untracked.map { "        " + $0 }
        }
        res.append("")
        if !c.staged.isEmpty {
            res.removeLast()
        } else if !c.unstaged.isEmpty {
            res.append("no changes added to commit (use \"git add\" and/or \"git commit -a\")")
        } else if !c.untracked.isEmpty {
            res.append("nothing added to commit but untracked files present (use \"git add\" to track)")
        } else {
            res.append(r.commits.isEmpty ? "nothing to commit (create/copy files and use \"git add\" to track)" : "nothing to commit, working tree clean")
        }
        return joined(res)
    }

    private func gitAdd(_ r: GitRepo, _ args: [String]) {
        let all = args.contains("-A") || args.contains("--all")
        let paths = args.filter { !$0.hasPrefix("-") }
        if paths.isEmpty && !all {
            err("Nothing specified, nothing added.")
            err("hint: Maybe you wanted to say 'git add .'?")
            return
        }
        let w = work(r)
        for p in all && paths.isEmpty ? [r.root] : paths {
            guard let rp = rel(r, p) else { err("fatal: \(p): '\(p)' is outside repository at '\(r.root)'"); return }
            let keys = matching(Set(w.keys).union(r.index.keys), rp)
            if keys.isEmpty { err("fatal: pathspec '\(p)' did not match any files"); return }
            for k in keys { r.index[k] = w[k] }
        }
    }

    private func gitCommit(_ r: GitRepo, _ args: [String]) -> String {
        var message: String?
        var all = false
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--all" { all = true } else if a.hasPrefix("--message=") { message = String(a.dropFirst(10)) } else if a.hasPrefix("-") && !a.hasPrefix("--") {
                if a.contains("a") { all = true }
                if a.contains("m") {
                    guard i + 1 < args.count else { err("error: switch `m' requires a value"); return "" }
                    message = args[i + 1]
                    i += 1
                }
            }
            i += 1
        }
        guard let message, !message.isEmpty else {
            err(tr("Aborting commit: в тренажёре редактор не открывается, добавь -m \"сообщение\"", "Aborting commit: no editor here, add -m \"message\""))
            return ""
        }
        if all {
            let w = work(r)
            for k in r.index.keys { r.index[k] = w[k] }
        }
        let old = r.headTree
        guard r.index != old else {
            failed = true
            let c = gitChanges(r)
            return joined(["On branch \(r.head)"] + (c.unstaged.isEmpty && c.untracked.isEmpty ? ["nothing to commit, working tree clean"]
                : ["no changes added to commit (use \"git add\" and/or \"git commit -a\")"]))
        }
        let rootCommit = r.commits.isEmpty
        let n = r.addCommit(message, parents: r.headCommit.map { [$0] } ?? [])
        let changed = Set(old.keys).union(r.index.keys).filter { old[$0] != r.index[$0] }.count
        return joined(["[\(r.head)\(rootCommit ? " (root-commit)" : "") \(r.commits[n].short)] \(message)",
                       " \(changed) file\(changed == 1 ? "" : "s") changed"])
    }

    private func gitLog(_ r: GitRepo, _ args: [String]) -> String {
        guard r.headCommit != nil else { err("fatal: your current branch '\(r.head)' does not have any commits yet"); return "" }
        var limit = Int.max
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "-n", i + 1 < args.count, let v = Int(args[i + 1]) { limit = v; i += 1 } else if a.hasPrefix("--max-count="), let v = Int(a.dropFirst(12)) { limit = v } else if a.hasPrefix("-"), let v = Int(a.dropFirst()) { limit = v }
            i += 1
        }
        let oneline = args.contains("--oneline")
        var res: [String] = []
        for c in r.log.prefix(limit) {
            let names = r.branches.filter { $0.value == c }.keys.sorted { a, _ in a == r.head }
            var decor = names.map { $0 == r.head ? "HEAD -> " + $0 : $0 }.joined(separator: ", ")
            if !decor.isEmpty { decor = "(\(decor))" }
            let commit = r.commits[c]
            if oneline {
                res.append([commit.short, decor, commit.message].filter { !$0.isEmpty }.joined(separator: " "))
            } else {
                if !res.isEmpty { res.append("") }
                res += ["commit \(commit.hash)\(decor.isEmpty ? "" : " " + decor)", "Author: student <student@keydojo.local>",
                        String(format: "Date:   Sun Nov 15 10:%02d:00 2026 +0300", c % 60), "", "    " + commit.message]
            }
        }
        return joined(res)
    }

    private func gitBranch(_ r: GitRepo, _ args: [String]) -> String {
        let names = args.filter { !$0.hasPrefix("-") }
        if args.contains("-d") || args.contains("-D") {
            guard let n = names.first else { err("fatal: branch name required"); return "" }
            guard let c = r.branches[n] else { err("error: branch '\(n)' not found."); return "" }
            guard n != r.head else { err("error: cannot delete branch '\(n)' used by worktree at '\(r.root)'"); return "" }
            r.branches[n] = nil
            return "Deleted branch \(n) (was \(r.commits[c].short)).\n"
        }
        guard let n = names.first else {
            return joined(r.branches.keys.sorted().map { ($0 == r.head ? "* " : "  ") + $0 })
        }
        guard let c = r.headCommit else { err("fatal: not a valid object name: '\(r.head)'"); return "" }
        guard r.branches[n] == nil else { err("fatal: a branch named '\(n)' already exists"); return "" }
        r.branches[n] = c
        return ""
    }

    private func gitSwitch(_ r: GitRepo, _ sub: String, _ args: [String]) -> String {
        let create = args.contains("-c") || args.contains("-b")
        let names = args.filter { !$0.hasPrefix("-") }
        // git checkout -- файл: вернуть файл из индекса
        if sub == "checkout", args.contains("--") || names.first.map({ r.branches[$0] == nil && rel(r, $0).map { r.index[$0] != nil } == true }) == true {
            gitRestore(r, names)
            return ""
        }
        guard let name = names.first else { err("fatal: missing branch or commit argument"); return "" }
        if create {
            guard r.branches[name] == nil else { err("fatal: a branch named '\(name)' already exists"); return "" }
            if let c = r.headCommit { r.branches[name] = c }
            r.head = name
            return "Switched to a new branch '\(name)'\n"
        }
        guard let target = r.branches[name] else {
            err(sub == "switch" ? "fatal: invalid reference: \(name)" : "error: pathspec '\(name)' did not match any file(s) known to git")
            return ""
        }
        if name == r.head { return "Already on '\(name)'\n" }
        if target != r.headCommit && dirty(r) {
            let c = gitChanges(r)
            err("error: Your local changes to the following files would be overwritten by checkout:")
            for k in Set((c.staged + c.unstaged).map(\.1)).sorted() { err("        " + k) }
            err("Please commit your changes or stash them before you switch branches.")
            err("Aborting")
            return ""
        }
        applyTree(r, from: r.headTree, to: r.commits[target].tree)
        r.index = r.commits[target].tree
        r.head = name
        return "Switched to branch '\(name)'\n"
    }

    // построчная разница через наибольшую общую подпоследовательность
    private func diffLines(_ a: [String], _ b: [String]) -> [String] {
        var t = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var res: [String] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i] == b[j] { res.append(" " + a[i]); i += 1; j += 1 } else if j < b.count, i == a.count || t[i][j + 1] >= t[i + 1][j] { res.append("+" + b[j]); j += 1 } else { res.append("-" + a[i]); i += 1 }
        }
        return res
    }

    private func gitDiff(_ r: GitRepo, _ args: [String]) -> String {
        let staged = args.contains("--staged") || args.contains("--cached")
        let w = work(r)
        let old = staged ? r.headTree : r.index
        let new = staged ? r.index : r.index.mapValues { _ in "" }.reduce(into: [String: String]()) { $0[$1.key] = w[$1.key] }
        var keys = Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }
        let paths = args.filter { !$0.hasPrefix("-") }.compactMap { rel(r, $0) }
        if !paths.isEmpty { keys = keys.filter { k in paths.contains { $0.isEmpty || k == $0 || k.hasPrefix($0 + "/") } } }
        var res: [String] = []
        for k in keys.sorted() {
            res += ["diff --git a/\(k) b/\(k)"]
            if old[k] == nil { res.append("new file mode 100644") }
            if new[k] == nil { res.append("deleted file mode 100644") }
            res += [old[k] == nil ? "--- /dev/null" : "--- a/\(k)", new[k] == nil ? "+++ /dev/null" : "+++ b/\(k)"]
            let a = textLines(old[k] ?? ""), b = textLines(new[k] ?? "")
            res.append("@@ -1,\(a.count) +1,\(b.count) @@")
            res += diffLines(a, b)
        }
        return joined(res)
    }

    private func gitRestore(_ r: GitRepo, _ args: [String]) {
        let staged = args.contains("--staged") || args.contains("-S")
        let paths = args.filter { !$0.hasPrefix("-") }
        guard !paths.isEmpty else { err("fatal: you must specify path(s) to restore"); return }
        for p in paths {
            guard let rp = rel(r, p) else { err("error: pathspec '\(p)' did not match any file(s) known to git"); continue }
            let keys = staged ? matching(Set(r.headTree.keys).union(r.index.keys), rp) : matching(r.index.keys, rp)
            if keys.isEmpty { err("error: pathspec '\(p)' did not match any file(s) known to git"); continue }
            for k in keys {
                if staged { r.index[k] = r.headTree[k] } else { writeWork(r, k, r.index[k]) }
            }
        }
    }

    private func gitMerge(_ r: GitRepo, _ args: [String]) -> String {
        guard let name = args.first(where: { !$0.hasPrefix("-") }) else { err("fatal: No remote for the current branch."); return "" }
        guard let target = r.branches[name], let cur = r.headCommit else { err("merge: \(name) - not something we can merge"); return "" }
        let mine = r.ancestors(cur), theirs = r.ancestors(target)
        if mine.contains(target) { return "Already up to date.\n" }
        if dirty(r) {
            err("error: Your local changes to the following files would be overwritten by merge.")
            err("Aborting")
            return ""
        }
        let headTree = r.headTree, targetTree = r.commits[target].tree
        let changed = Set(headTree.keys).union(targetTree.keys).filter { headTree[$0] != targetTree[$0] }.count
        if theirs.contains(cur) {
            applyTree(r, from: headTree, to: targetTree)
            r.index = targetTree
            r.branches[r.head] = target
            return joined(["Updating \(r.commits[cur].short)..\(r.commits[target].short)", "Fast-forward", " \(changed) file\(changed == 1 ? "" : "s") changed"])
        }
        let base = mine.intersection(theirs).max().map { r.commits[$0].tree } ?? [:]
        var merged = headTree
        for (k, v) in targetTree where base[k] != v { merged[k] = v }
        for k in base.keys where targetTree[k] == nil && headTree[k] == base[k] { merged[k] = nil }
        applyTree(r, from: headTree, to: merged)
        r.index = merged
        _ = r.addCommit("Merge branch '\(name)'", parents: [cur, target])
        return joined(["Merge made by the 'ort' strategy.", " \(changed) file\(changed == 1 ? "" : "s") changed"])
    }

    private func gitStash(_ r: GitRepo, _ args: [String]) -> String {
        let cmd = args.first ?? "push"
        let tracked = Set(r.headTree.keys).union(r.index.keys)
        switch cmd {
        case "push", "save":
            guard dirty(r) else { return "No local changes to save\n" }
            let w = work(r)
            let top = r.headCommit.map { "\(r.commits[$0].short) \(r.commits[$0].message)" } ?? ""
            let message = "WIP on \(r.head): \(top)"
            r.stash.append((r.index, w.filter { tracked.contains($0.key) }, message))
            for k in tracked { writeWork(r, k, r.headTree[k]) }
            r.index = r.headTree
            return "Saved working directory and index state \(message)\n"
        case "pop", "apply":
            guard let s = r.stash.last else { err("No stash entries found."); return "" }
            for k in tracked.union(s.work.keys) { writeWork(r, k, s.work[k]) }
            r.index = s.index
            if cmd == "pop" {
                r.stash.removeLast()
                return "Dropped refs/stash@{0}\n"
            }
            return ""
        case "list":
            return joined(r.stash.indices.reversed().map { "stash@{\(r.stash.count - 1 - $0)}: \(r.stash[$0].message)" })
        case "drop":
            guard !r.stash.isEmpty else { err("No stash entries found."); return "" }
            r.stash.removeLast()
            return "Dropped refs/stash@{0}\n"
        default:
            err("error: unknown subcommand: \(cmd)")
            return ""
        }
    }
}

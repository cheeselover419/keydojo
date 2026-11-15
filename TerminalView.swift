import SwiftUI
import AppKit

extension Key {
    private static let codes: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o",
        32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 50: "`",
        36: "enter", 76: "enter", 48: "tab", 49: "space", 51: "backspace", 117: "delete", 53: "esc",
        123: "left", 124: "right", 125: "down", 126: "up", 115: "home", 119: "end",
        116: "pageup", 121: "pagedown",
    ]

    // имя по коду клавиши, чтобы сочетания работали и в русской раскладке
    init(_ e: NSEvent) {
        let f = e.modifierFlags
        let base = Self.codes[e.keyCode] ?? (e.charactersIgnoringModifiers ?? "")
        var mods = ""
        if f.contains(.control) { mods += "ctrl+" }
        if f.contains(.option) { mods += "opt+" }
        if f.contains(.command) { mods += "cmd+" }
        if !mods.isEmpty && f.contains(.shift) { mods += "shift+" }
        let text = f.contains(.control) || f.contains(.command) ? "" : (e.characters ?? "")
        self.init(name: mods + base, text: text)
    }
}

final class KeyView: NSView {
    var onKey: ((Key) -> Bool)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { self.window?.makeFirstResponder(self) }
    }

    override func keyDown(with e: NSEvent) {
        if onKey?(Key(e)) != true { super.keyDown(with: e) }
    }

    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        let k = Key(e)
        guard k.name.hasPrefix("cmd+") || k.name.hasPrefix("ctrl+") else { return false }
        return onKey?(k) ?? false
    }
}

struct KeyCatcher: NSViewRepresentable {
    let onKey: (Key) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let v = KeyView()
        v.onKey = onKey
        return v
    }

    func updateNSView(_ v: KeyView, context: Context) {
        v.onKey = onKey
    }
}

enum Term {
    static let bg = Color(white: 0.11)
    static let fg = Color(white: 0.9)
    static let dim = Color(white: 0.45)
}

extension View {
    func inverted() -> some View { foregroundColor(Term.bg).background(Term.fg) }
}

struct CursorLine: View {
    var prefix = ""
    let text: String
    let pos: Int

    var body: some View {
        let chars = Array(text)
        let p = min(pos, chars.count)
        return HStack(spacing: 0) {
            Text(prefix + String(chars[..<p]))
            Text(p < chars.count ? String(chars[p]) : " ").foregroundColor(Term.bg).background(Term.fg)
            Text(p < chars.count ? String(chars[(p + 1)...]) : "")
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }
}

struct TerminalScreen: View {
    @ObservedObject var term: Terminal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if term.tabs.count > 1 { tabBar }
            Group {
                if term.mode == .nano, let n = term.nano {
                    NanoView(n: n)
                } else if term.mode == .vim, let v = term.vim {
                    VimView(v: v)
                } else if term.mode == .less, let l = term.less {
                    LessView(l: l)
                } else {
                    shell
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .font(.system(size: 13, design: .monospaced))
        .foregroundColor(Term.fg)
        .background(Term.bg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tabBar: some View {
        HStack(spacing: 1) {
            ForEach(term.tabs.indices, id: \.self) { i in
                Text("\(i + 1): \(FileSystem.pretty(term.tabs[i].cwd))")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .foregroundColor(i == term.current ? Term.fg : Term.dim)
                    .background(i == term.current ? Term.bg : Color(white: 0.2))
            }
        }
        .background(Color(white: 0.3))
    }

    private var shell: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(term.lines.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    inputLine.id("input")
                }
            }
            .onChange(of: term.lines.count) { _ in proxy.scrollTo("input", anchor: .bottom) }
            .onChange(of: term.current) { _ in proxy.scrollTo("input", anchor: .bottom) }
        }
    }

    @ViewBuilder private var inputLine: some View {
        if term.mode == .running {
            CursorLine(text: "", pos: 0)
        } else if let q = term.search {
            let match = term.searchMatch().map { term.tabs[term.current].history[$0] } ?? ""
            CursorLine(prefix: "(reverse-i-search)`\(q)': ", text: match, pos: 0)
        } else {
            CursorLine(prefix: term.prompt, text: term.input, pos: term.cursor)
        }
    }
}

struct EditorRows: View {
    let lines: [String]
    let row: Int
    let col: Int
    let height: Int
    var cursor = true
    var tilde = false

    var body: some View {
        let top = row >= height ? row - height + 1 : 0
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<height, id: \.self) { i in
                let r = top + i
                if r < lines.count {
                    if cursor && r == row {
                        CursorLine(text: lines[r], pos: col)
                    } else {
                        Text(lines[r].isEmpty ? " " : lines[r]).lineLimit(1)
                    }
                } else {
                    Text(tilde ? "~" : " ").foregroundColor(Color(red: 0.4, green: 0.5, blue: 1))
                }
            }
        }
    }
}

struct NanoView: View {
    let n: Nano

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("  GNU nano 7.2")
                Spacer()
                Text(n.name.isEmpty ? "New Buffer" : n.name)
                Spacer()
                Text(n.modified ? "Modified  " : "          ")
            }
            .inverted()
            EditorRows(lines: n.buf.lines, row: n.buf.row, col: n.buf.col, height: Less.height - 2,
                       cursor: n.prompt == nil)
            status
            Text("^G Help      ^O Write Out  ^W Where Is   ^K Cut         ^X Exit")
            Text("^C Cancel    ^U Paste      ^A Line Start ^E Line End    ^R Read File")
        }
    }

    @ViewBuilder private var status: some View {
        switch n.prompt {
        case .save(let t, _)?:
            CursorLine(prefix: "File Name to Write: ", text: t, pos: t.count)
        case .search(let q)?:
            CursorLine(prefix: "Search: ", text: q, pos: q.count)
        case .confirm?:
            Text("Save modified buffer?   Y Yes    N No    ^C Cancel")
        case nil:
            HStack {
                Spacer()
                if let m = n.message { Text(m).inverted() } else { Text(" ") }
                Spacer()
            }
        }
    }
}

struct VimView: View {
    let v: Vim

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorRows(lines: v.buf.lines, row: v.buf.row, col: v.buf.col, height: Less.height + 1,
                       cursor: !isCommand, tilde: true)
            switch v.vmode {
            case .command(let c): CursorLine(prefix: ":", text: c, pos: c.count)
            case .insert: Text("-- INSERT --").bold()
            case .normal: Text(v.message ?? " ").lineLimit(1)
            }
        }
    }

    private var isCommand: Bool {
        if case .command = v.vmode { return true }
        return false
    }
}

struct LessView: View {
    let l: Less

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<Less.height, id: \.self) { i in
                let r = l.top + i
                if r < l.lines.count {
                    let line = l.lines[r]
                    Text(line.isEmpty ? " " : line)
                        .lineLimit(1)
                        .background(!l.query.isEmpty && line.contains(l.query) ? Color.yellow.opacity(0.3) : .clear)
                } else {
                    Text("~").foregroundColor(Term.dim)
                }
            }
            if let p = l.prompt {
                CursorLine(prefix: "/", text: p, pos: p.count)
            } else if let m = l.message {
                Text(m).inverted()
            } else if l.top + Less.height >= l.lines.count {
                HStack(spacing: 0) {
                    Text("(END)").inverted()
                    CursorLine(text: "", pos: 0)
                }
            } else {
                CursorLine(prefix: ":", text: "", pos: 0)
            }
        }
    }
}

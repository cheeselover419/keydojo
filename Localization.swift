import Foundation

enum Lang: String, CaseIterable {
    case ru, en

    var name: String { self == .ru ? "Русский" : "English" }

    static var current: Lang {
        Lang(rawValue: UserDefaults.standard.string(forKey: "lang") ?? "") ?? .ru
    }
}

// строка на текущем языке
func tr(_ ru: String, _ en: String) -> String { Lang.current == .en ? en : ru }

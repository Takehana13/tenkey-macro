import CoreGraphics

enum KeyNames {
    static let keypadCodes: Set<Int> = [65, 67, 69, 71, 75, 76, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89, 91, 92]

    static func isKeypad(_ code: Int) -> Bool { keypadCodes.contains(code) }

    private static let names: [Int: String] = [
        // テンキー
        82: "テンキー0", 83: "テンキー1", 84: "テンキー2", 85: "テンキー3", 86: "テンキー4",
        87: "テンキー5", 88: "テンキー6", 89: "テンキー7", 91: "テンキー8", 92: "テンキー9",
        65: "テンキー.", 67: "テンキー*", 69: "テンキー+", 71: "テンキーClear",
        75: "テンキー/", 76: "テンキーEnter", 78: "テンキー-", 81: "テンキー=",
        // 英字
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J",
        40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T",
        32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        // 数字列
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
        // 記号
        27: "-", 24: "^/=", 33: "@/[", 30: "[/]", 41: ";", 39: ":/'", 42: "]/\\", 43: ",", 47: ".",
        44: "/", 50: "`", 93: "¥", 94: "_",
        // 特殊キー
        36: "Return", 48: "Tab", 49: "Space", 51: "Delete", 53: "Esc", 117: "⌦",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        102: "英数", 104: "かな",
        // ファンクション
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    private static let topDigits: [Character: Int] = [
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
    ]
    private static let padKeys: [Character: Int] = [
        "0": 82, "1": 83, "2": 84, "3": 85, "4": 86, "5": 87, "6": 88, "7": 89, "8": 91, "9": 92,
        ".": 65, "-": 78, "+": 69, "*": 67, "/": 75,
    ]
    /// US/JIS 配列で同じ位置にある記号だけ
    private static let otherKeys: [Character: Int] = [
        ".": 47, ",": 43, "-": 27, "/": 44, " ": 49,
    ]
    private static let letterCodes: [Character: Int] = [
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
        "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17,
        "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6,
    ]

    /// 1 文字を打つためのキーコードと Shift の要否。キーで打てない文字は nil（直接文字として送る）。
    static func keyStroke(for ch: Character, useKeypad: Bool) -> (code: Int, shift: Bool)? {
        if useKeypad, let c = padKeys[ch] { return (c, false) }
        if let c = topDigits[ch] ?? otherKeys[ch] { return (c, false) }
        let lower = Character(ch.lowercased())
        if let c = letterCodes[lower] { return (c, ch != lower) }
        return nil
    }

    static func name(for code: Int) -> String {
        names[code] ?? "キー#\(code)"
    }

    static func modifierSymbols(_ flags: UInt64) -> String {
        let f = CGEventFlags(rawValue: flags)
        var s = ""
        if f.contains(.maskControl) { s += "⌃" }
        if f.contains(.maskAlternate) { s += "⌥" }
        if f.contains(.maskShift) { s += "⇧" }
        if f.contains(.maskCommand) { s += "⌘" }
        return s
    }
}

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

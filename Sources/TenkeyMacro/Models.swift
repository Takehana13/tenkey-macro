import Foundation
import CoreGraphics

/// キー + 修飾キー（⌘⌃⌥⇧のみ。テンキーフラグは無視）
struct Hotkey: Codable, Hashable {
    var keyCode: Int
    var modifiers: UInt64

    static let modifierMask: UInt64 =
        CGEventFlags.maskCommand.rawValue |
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskShift.rawValue

    init(keyCode: Int, modifiers: UInt64 = 0) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Hotkey.modifierMask
    }

    var display: String {
        KeyNames.modifierSymbols(modifiers) + KeyNames.name(for: keyCode)
    }
}

enum StepKind: String, Codable, CaseIterable, Identifiable {
    case click, mouseDown, mouseUp, mouseMove, mouseDrag, scroll, typeText, keyTap, keyDown, keyUp, wait

    var id: String { rawValue }

    var label: String {
        switch self {
        case .click: return "クリック"
        case .mouseDown: return "マウス押す"
        case .mouseUp: return "マウス離す"
        case .mouseMove: return "マウス移動"
        case .mouseDrag: return "ドラッグ移動"
        case .scroll: return "スクロール"
        case .typeText: return "文字入力"
        case .keyTap: return "キー入力"
        case .keyDown: return "キー押す"
        case .keyUp: return "キー離す"
        case .wait: return "待機のみ"
        }
    }

    var usesPosition: Bool { [.click, .mouseDown, .mouseUp, .mouseMove, .mouseDrag].contains(self) }
    var usesButton: Bool { [.click, .mouseDown, .mouseUp, .mouseDrag].contains(self) }
    var usesKey: Bool { [.keyTap, .keyDown, .keyUp].contains(self) }
}

enum MouseButton: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var label: String { self == .left ? "左" : "右" }
}

struct MacroStep: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: StepKind
    /// このステップを実行する前の待ち時間（ミリ秒）
    var delayMs: Int = 0
    /// 画面座標（左上原点、ポイント単位）
    var x: Double = 0
    var y: Double = 0
    var button: MouseButton = .left
    var clickCount: Int = 1
    var keyCode: Int = 0
    var flags: UInt64 = 0
    var scrollX: Int = 0
    var scrollY: Int = 0
    /// 文字入力ステップで入力する文字列（例: "100"）
    var text: String = ""
    /// 文字入力で数字・「.」「-」をテンキーから送る
    var useKeypad: Bool = true

    init(kind: StepKind) {
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, delayMs, x, y, button, clickCount, keyCode, flags, scrollX, scrollY, text, useKeypad
    }

    // 古い保存ファイル（項目が足りないもの）も読めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decodeIfPresent(StepKind.self, forKey: .kind) ?? .wait
        delayMs = try c.decodeIfPresent(Int.self, forKey: .delayMs) ?? 0
        x = try c.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(Double.self, forKey: .y) ?? 0
        button = try c.decodeIfPresent(MouseButton.self, forKey: .button) ?? .left
        clickCount = try c.decodeIfPresent(Int.self, forKey: .clickCount) ?? 1
        keyCode = try c.decodeIfPresent(Int.self, forKey: .keyCode) ?? 0
        flags = try c.decodeIfPresent(UInt64.self, forKey: .flags) ?? 0
        scrollX = try c.decodeIfPresent(Int.self, forKey: .scrollX) ?? 0
        scrollY = try c.decodeIfPresent(Int.self, forKey: .scrollY) ?? 0
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        useKeypad = try c.decodeIfPresent(Bool.self, forKey: .useKeypad) ?? true
    }

    /// 同じ内容で新しい ID を持つコピー
    func duplicated() -> MacroStep {
        var s = self
        s.id = UUID()
        return s
    }
}

struct Macro: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var hotkey: Hotkey?
    var enabled = true
    var repeatCount = 1
    var speed = 1.0
    var restoreCursor = true
    var steps: [MacroStep] = []

    init(name: String, steps: [MacroStep] = []) {
        self.name = name
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey {
        case id, name, hotkey, enabled, repeatCount, speed, restoreCursor, steps
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "マクロ"
        hotkey = try c.decodeIfPresent(Hotkey.self, forKey: .hotkey)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        repeatCount = try c.decodeIfPresent(Int.self, forKey: .repeatCount) ?? 1
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1.0
        restoreCursor = try c.decodeIfPresent(Bool.self, forKey: .restoreCursor) ?? true
        steps = try c.decodeIfPresent([MacroStep].self, forKey: .steps) ?? []
    }
}

struct AppSettings: Codable, Equatable {
    /// ホットキー全体の ON/OFF
    var hotkeysEnabled = true
    /// ホットキーとして使ったキーを他のアプリに渡さない
    var consumeHotkey = true
    /// 記録時にマウス移動（クリックを伴わない移動）も記録する
    var recordMouseMoves = false
    /// 再生中の緊急停止キー
    var stopKey: Hotkey? = Hotkey(keyCode: 53) // Esc
    /// 記録停止キー
    var recordStopKey: Hotkey? = Hotkey(keyCode: 53) // Esc
    /// ホットキー ON/OFF 切替キー
    var toggleKey: Hotkey? = nil

    init() {}

    enum CodingKeys: String, CodingKey {
        case hotkeysEnabled, consumeHotkey, recordMouseMoves, stopKey, recordStopKey, toggleKey
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        hotkeysEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeysEnabled) ?? d.hotkeysEnabled
        consumeHotkey = try c.decodeIfPresent(Bool.self, forKey: .consumeHotkey) ?? d.consumeHotkey
        recordMouseMoves = try c.decodeIfPresent(Bool.self, forKey: .recordMouseMoves) ?? d.recordMouseMoves
        stopKey = c.contains(.stopKey) ? try c.decodeIfPresent(Hotkey.self, forKey: .stopKey) : d.stopKey
        recordStopKey = c.contains(.recordStopKey) ? try c.decodeIfPresent(Hotkey.self, forKey: .recordStopKey) : d.recordStopKey
        toggleKey = c.contains(.toggleKey) ? try c.decodeIfPresent(Hotkey.self, forKey: .toggleKey) : d.toggleKey
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(hotkeysEnabled, forKey: .hotkeysEnabled)
        try c.encode(consumeHotkey, forKey: .consumeHotkey)
        try c.encode(recordMouseMoves, forKey: .recordMouseMoves)
        // nil も明示的に書き出す（解除した状態を保存するため）
        try c.encode(stopKey, forKey: .stopKey)
        try c.encode(recordStopKey, forKey: .recordStopKey)
        try c.encode(toggleKey, forKey: .toggleKey)
    }
}

struct SaveFile: Codable {
    var version = 1
    var settings: AppSettings?
    var macros: [Macro]
}

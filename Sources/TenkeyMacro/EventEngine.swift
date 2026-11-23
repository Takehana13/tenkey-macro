import Cocoa

/// システム全体のキーボード・マウス入力を監視する（イベントタップ）。
/// ・ホットキーでマクロ再生 ・操作の記録 ・キー割り当て時の取得 を担当する。
/// タップは専用スレッドで動かし、画面の描画などで入力が遅れないようにしている。
final class EventEngine {
    static let shared = EventEngine()
    let player = Player()

    private let lock = NSLock()
    private var tap: CFMachPort?

    // lock で保護
    private var hotkeyMap: [Hotkey: Macro] = [:]
    private var settings = AppSettings()
    private var recording = false
    private var recorded: [MacroStep] = []
    private var lastRecordNs: UInt64 = 0
    private var captureHandler: ((Int, UInt64) -> Void)?
    private var consumedKeyUps = Set<Int>()

    /// 記録停止キーが押された（メインスレッドで呼ばれる）
    var onRecordStopRequested: (() -> Void)?
    /// ON/OFF 切替キーが押された（メインスレッドで呼ばれる）
    var onToggleRequested: (() -> Void)?

    var isRunning: Bool { tap != nil }

    // MARK: - 起動

    func start() -> Bool {
        if tap != nil { return true }
        let types: [CGEventType] = [
            .keyDown, .keyUp,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel,
        ]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        tap = newTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: newTap, enable: true)
            CFRunLoopRun()
        }
        thread.name = "TenkeyMacro.eventTap"
        thread.qualityOfService = .userInteractive
        thread.start()
        return true
    }

    // MARK: - 設定反映

    func update(macros: [Macro], settings: AppSettings) {
        var map: [Hotkey: Macro] = [:]
        for m in macros where m.enabled {
            if let hk = m.hotkey, map[hk] == nil { map[hk] = m }
        }
        lock.lock()
        hotkeyMap = map
        self.settings = settings
        lock.unlock()
    }

    // MARK: - 記録

    func beginRecording() {
        lock.lock()
        recorded = []
        lastRecordNs = 0
        recording = true
        lock.unlock()
    }

    /// 記録を終了して手順を返す。rects（このアプリのウィンドウ位置）内で終わるマウス操作は
    /// 「停止ボタンを押した操作」なので末尾から取り除く。
    func endRecording(excluding rects: [CGRect]) -> [MacroStep] {
        lock.lock()
        recording = false
        var steps = recorded
        recorded = []
        lock.unlock()

        while let last = steps.last, last.kind.usesPosition,
              rects.contains(where: { $0.contains(CGPoint(x: last.x, y: last.y)) }) {
            steps.removeLast()
        }
        return Recorder.simplify(steps)
    }

    // MARK: - キー取得（ホットキー割り当て用）

    func captureNextKey(_ handler: @escaping (_ keyCode: Int, _ flags: UInt64) -> Void) {
        lock.lock(); captureHandler = handler; lock.unlock()
    }

    func cancelCapture() {
        lock.lock(); captureHandler = nil; lock.unlock()
    }

    // MARK: - イベント処理（タップスレッド）

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        // 自分が再生で送ったイベントは素通し
        if event.getIntegerValueField(.eventSourceUserData) == Player.magic { return pass }

        lock.lock()
        defer { lock.unlock() }

        switch type {
        case .keyDown:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let rawFlags = event.flags.rawValue
            let hk = Hotkey(keyCode: code, modifiers: rawFlags)
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

            // キー割り当て待ち
            if let handler = captureHandler {
                if !isRepeat {
                    captureHandler = nil
                    consumedKeyUps.insert(code)
                    DispatchQueue.main.async { handler(code, rawFlags) }
                }
                return nil
            }

            // 記録中
            if recording {
                if hk == settings.recordStopKey {
                    if !isRepeat {
                        consumedKeyUps.insert(code)
                        let cb = onRecordStopRequested
                        DispatchQueue.main.async { cb?() }
                    }
                    return nil
                }
                if !isRepeat { appendRecorded(type: type, event: event) }
                return pass
            }

            // 緊急停止
            if player.isPlaying, hk == settings.stopKey {
                player.stop()
                consumedKeyUps.insert(code)
                return nil
            }

            // ON/OFF 切替
            if hk == settings.toggleKey {
                if !isRepeat {
                    consumedKeyUps.insert(code)
                    let cb = onToggleRequested
                    DispatchQueue.main.async { cb?() }
                }
                return nil
            }

            // マクロ実行
            if settings.hotkeysEnabled, let macro = hotkeyMap[hk] {
                if !isRepeat {
                    if !player.play(macro) {
                        // 再生中の連打は無視（二重発注防止）
                        DispatchQueue.main.async { NSSound.beep() }
                    }
                }
                if settings.consumeHotkey {
                    consumedKeyUps.insert(code)
                    return nil
                }
            }
            return pass

        case .keyUp:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            if consumedKeyUps.remove(code) != nil { return nil }
            if recording { appendRecorded(type: type, event: event) }
            return pass

        default:
            if recording { appendRecorded(type: type, event: event) }
            return pass
        }
    }

    /// lock を持った状態で呼ぶこと
    private func appendRecorded(type: CGEventType, event: CGEvent) {
        let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        let loc = event.location
        var step: MacroStep

        func mouse(_ kind: StepKind, _ button: MouseButton) -> MacroStep {
            var s = MacroStep(kind: kind)
            s.x = loc.x.rounded()
            s.y = loc.y.rounded()
            s.button = button
            s.clickCount = max(1, Int(event.getIntegerValueField(.mouseEventClickState)))
            s.flags = event.flags.rawValue & Hotkey.modifierMask
            return s
        }

        switch type {
        case .leftMouseDown: step = mouse(.mouseDown, .left)
        case .leftMouseUp: step = mouse(.mouseUp, .left)
        case .rightMouseDown: step = mouse(.mouseDown, .right)
        case .rightMouseUp: step = mouse(.mouseUp, .right)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged:
            let isMove = type == .mouseMoved
            if isMove && !settings.recordMouseMoves { return }
            // 細かすぎる移動は間引く（16ms 未満の連続移動は捨てる）
            if let last = recorded.last, last.kind == (isMove ? .mouseMove : .mouseDrag),
               now - lastRecordNs < 16_000_000 { return }
            step = mouse(isMove ? .mouseMove : .mouseDrag, type == .rightMouseDragged ? .right : .left)
        case .scrollWheel:
            step = MacroStep(kind: .scroll)
            step.x = loc.x.rounded(); step.y = loc.y.rounded()
            step.scrollY = Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            step.scrollX = Int(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        case .keyDown, .keyUp:
            step = MacroStep(kind: type == .keyDown ? .keyDown : .keyUp)
            step.keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            step.flags = event.flags.rawValue & Hotkey.modifierMask
        default:
            return
        }

        step.delayMs = lastRecordNs == 0 ? 0 : Int((now - lastRecordNs) / 1_000_000)
        lastRecordNs = now
        recorded.append(step)
    }
}

private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let engine = Unmanaged<EventEngine>.fromOpaque(refcon).takeUnretainedValue()
    return engine.handle(type: type, event: event)
}

/// 記録した生のイベント列を、編集しやすい形にまとめる。
enum Recorder {
    static func simplify(_ input: [MacroStep]) -> [MacroStep] {
        // 1) 記録開始前に押されていたキー/ボタンの「離す」だけが残ったものを除く
        var pressedKeys = Set<Int>()
        var pressedButtons = Set<MouseButton>()
        var cleaned: [MacroStep] = []
        var carryDelay = 0
        for var s in input {
            switch s.kind {
            case .keyDown: pressedKeys.insert(s.keyCode)
            case .keyUp:
                if pressedKeys.remove(s.keyCode) == nil { carryDelay += s.delayMs; continue }
            case .mouseDown: pressedButtons.insert(s.button)
            case .mouseUp:
                if pressedButtons.remove(s.button) == nil { carryDelay += s.delayMs; continue }
            default: break
            }
            s.delayMs += carryDelay
            carryDelay = 0
            cleaned.append(s)
        }
        if let first = cleaned.first, first.delayMs != 0 { cleaned[0].delayMs = 0 }

        // 2) 押す→離す をまとめて「クリック」「キー入力」にする
        var out: [MacroStep] = []
        for s in cleaned {
            if s.kind == .mouseUp, let last = out.last, last.kind == .mouseDown,
               last.button == s.button, near(last, s) {
                out.removeLast()
                // ダブルクリック：直前の同じ位置のクリックに回数をまとめる
                if last.clickCount >= 2, let prev = out.last, prev.kind == .click,
                   prev.button == last.button, near(prev, last) {
                    out[out.count - 1].clickCount = last.clickCount
                    continue
                }
                var c = last
                c.kind = .click
                c.clickCount = 1
                out.append(c)
                continue
            }
            if s.kind == .keyUp, let last = out.last, last.kind == .keyDown, last.keyCode == s.keyCode {
                out[out.count - 1].kind = .keyTap
                continue
            }
            out.append(s)
        }

        // 3) 続けて打った数字（と「.」「-」）を 1 つの「文字入力」にまとめる
        var merged: [MacroStep] = []
        for s in out {
            guard s.kind == .keyTap, s.flags & Hotkey.modifierMask == 0,
                  let ch = typedChar(s.keyCode) else {
                merged.append(s)
                continue
            }
            if let last = merged.last, last.kind == .typeText,
               last.useKeypad == KeyNames.isKeypad(s.keyCode) {
                merged[merged.count - 1].text.append(ch)
            } else {
                var t = MacroStep(kind: .typeText)
                t.delayMs = s.delayMs
                t.text = String(ch)
                t.useKeypad = KeyNames.isKeypad(s.keyCode)
                merged.append(t)
            }
        }
        return merged
    }

    /// 数字入力としてまとめる対象のキー
    private static func typedChar(_ code: Int) -> Character? {
        let map: [Int: Character] = [
            82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9", 65: ".", 78: "-",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 47: ".",
        ]
        return map[code]
    }

    private static func near(_ a: MacroStep, _ b: MacroStep) -> Bool {
        abs(a.x - b.x) < 4 && abs(a.y - b.y) < 4
    }
}

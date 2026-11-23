import Foundation
import CoreGraphics

/// マクロを再生する。専用スレッドで動き、同時に 1 つしか再生しない（二重発注防止）。
final class Player {
    /// このアプリが送ったイベントの目印（記録・ホットキー判定から除外するため）
    static let magic: Int64 = 0x544B_4D43

    /// マウスの押す/離すの間などに入れるごく短い間隔（秒）。アプリ側の取りこぼし防止。
    private static let microGap: TimeInterval = 0.008

    private let lock = NSLock()
    private var playing = false
    private var cancelFlag = false
    private let queue = DispatchQueue(label: "TenkeyMacro.player", qos: .userInteractive)

    /// 再生状態の変化（メインスレッドで呼ばれる）。再生中のマクロ ID、終了時は nil。
    var onStateChange: ((UUID?) -> Void)?

    var isPlaying: Bool {
        lock.lock(); defer { lock.unlock() }
        return playing
    }

    /// 再生を開始する。すでに再生中なら何もせず false を返す。
    @discardableResult
    func play(_ macro: Macro) -> Bool {
        lock.lock()
        if playing { lock.unlock(); return false }
        playing = true
        cancelFlag = false
        lock.unlock()

        DispatchQueue.main.async { self.onStateChange?(macro.id) }
        queue.async {
            self.run(macro)
            self.lock.lock(); self.playing = false; self.lock.unlock()
            DispatchQueue.main.async { self.onStateChange?(nil) }
        }
        return true
    }

    func stop() {
        lock.lock(); cancelFlag = true; lock.unlock()
    }

    private var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelFlag
    }

    // MARK: - 実行

    private func run(_ macro: Macro) {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = Player.magic
        let startPos = CGEvent(source: nil)?.location
        let speed = max(0.1, macro.speed)

        outer: for _ in 0..<max(1, macro.repeatCount) {
            for step in macro.steps {
                if !wait(seconds: Double(max(0, step.delayMs)) / 1000.0 / speed) { break outer }
                perform(step, source: source)
            }
        }

        if macro.restoreCursor, let p = startPos {
            postMouse(.mouseMoved, at: p, button: .left, clickState: 0, flags: [], source: source)
        }
    }

    /// 指定秒数待つ。途中で停止されたら false。
    private func wait(seconds: TimeInterval) -> Bool {
        if cancelled { return false }
        guard seconds > 0 else { return true }
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return !cancelled }
            Thread.sleep(forTimeInterval: min(remaining, 0.01))
            if cancelled { return false }
        }
    }

    private func perform(_ step: MacroStep, source: CGEventSource?) {
        let pt = CGPoint(x: step.x, y: step.y)
        let flags = CGEventFlags(rawValue: step.flags)
        let btn: CGMouseButton = step.button == .left ? .left : .right
        let downType: CGEventType = step.button == .left ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = step.button == .left ? .leftMouseUp : .rightMouseUp

        switch step.kind {
        case .mouseMove:
            postMouse(.mouseMoved, at: pt, button: .left, clickState: 0, flags: flags, source: source)
        case .mouseDrag:
            let t: CGEventType = step.button == .left ? .leftMouseDragged : .rightMouseDragged
            postMouse(t, at: pt, button: btn, clickState: 1, flags: flags, source: source)
        case .mouseDown:
            postMouse(downType, at: pt, button: btn, clickState: max(1, step.clickCount), flags: flags, source: source)
        case .mouseUp:
            postMouse(upType, at: pt, button: btn, clickState: max(1, step.clickCount), flags: flags, source: source)
        case .click:
            postMouse(.mouseMoved, at: pt, button: .left, clickState: 0, flags: flags, source: source)
            Thread.sleep(forTimeInterval: Player.microGap)
            let count = max(1, step.clickCount)
            for n in 1...count {
                postMouse(downType, at: pt, button: btn, clickState: n, flags: flags, source: source)
                Thread.sleep(forTimeInterval: Player.microGap)
                postMouse(upType, at: pt, button: btn, clickState: n, flags: flags, source: source)
                if n < count { Thread.sleep(forTimeInterval: Player.microGap) }
            }
        case .scroll:
            if let e = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                               wheel1: Int32(step.scrollY), wheel2: Int32(step.scrollX), wheel3: 0) {
                mark(e)
                e.post(tap: .cghidEventTap)
            }
        case .keyDown:
            postKey(step.keyCode, down: true, flags: step.flags, source: source)
        case .keyUp:
            postKey(step.keyCode, down: false, flags: step.flags, source: source)
        case .keyTap:
            postKey(step.keyCode, down: true, flags: step.flags, source: source)
            Thread.sleep(forTimeInterval: Player.microGap)
            postKey(step.keyCode, down: false, flags: step.flags, source: source)
        case .wait:
            break
        }
    }

    private func mark(_ e: CGEvent) {
        e.setIntegerValueField(.eventSourceUserData, value: Player.magic)
    }

    private func postMouse(_ type: CGEventType, at pt: CGPoint, button: CGMouseButton,
                           clickState: Int, flags: CGEventFlags, source: CGEventSource?) {
        guard let e = CGEvent(mouseEventSource: source, mouseType: type,
                              mouseCursorPosition: pt, mouseButton: button) else { return }
        if clickState > 0 {
            e.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        }
        e.flags = CGEventFlags(rawValue: flags.rawValue & Hotkey.modifierMask)
        mark(e)
        e.post(tap: .cghidEventTap)
    }

    private func postKey(_ code: Int, down: Bool, flags: UInt64, source: CGEventSource?) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down) else { return }
        var f = flags & Hotkey.modifierMask
        if KeyNames.isKeypad(code) { f |= CGEventFlags.maskNumericPad.rawValue }
        e.flags = CGEventFlags(rawValue: f)
        mark(e)
        e.post(tap: .cghidEventTap)
    }
}

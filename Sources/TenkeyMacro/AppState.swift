import Cocoa
import SwiftUI
import UniformTypeIdentifiers
import ApplicationServices

final class AppState: ObservableObject {
    @Published var macros: [Macro] = [] { didSet { changed() } }
    @Published var settings = AppSettings() { didSet { changed() } }
    @Published var selection: UUID?

    @Published var isRecording = false
    @Published var playingID: UUID?
    @Published var trusted = false
    @Published var engineRunning = false
    @Published var message = ""
    /// 今キー入力待ちになっている欄の識別子
    @Published var capturingID: String?

    private var recordTarget: UUID?
    private var saveWork: DispatchWorkItem?
    private var permissionTimer: Timer?
    private var loading = false
    private let engine = EventEngine.shared

    static var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TenkeyMacro", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("macros.json")
    }

    init() {
        load()
        engine.player.onStateChange = { [weak self] id in self?.playingID = id }
        engine.onRecordStopRequested = { [weak self] in self?.stopRecording() }
        engine.onToggleRequested = { [weak self] in
            guard let self else { return }
            self.settings.hotkeysEnabled.toggle()
            self.message = self.settings.hotkeysEnabled ? "ホットキー ON" : "ホットキー OFF"
            NSSound(named: self.settings.hotkeysEnabled ? "Tink" : "Pop")?.play()
        }
        engine.update(macros: macros, settings: settings)

        // 初回はアクセシビリティ許可のダイアログを出す
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(opts)
        tryStartEngine()
        if !engineRunning {
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
                guard let self else { t.invalidate(); return }
                self.trusted = AXIsProcessTrusted()
                self.tryStartEngine()
                if self.engineRunning { t.invalidate() }
            }
        }
    }

    private func tryStartEngine() {
        guard !engineRunning else { return }
        if engine.start() {
            engineRunning = true
            trusted = true
            message = "準備完了"
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 保存

    private func changed() {
        engine.update(macros: macros, settings: settings)
        guard !loading else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func load() {
        loading = true
        defer { loading = false }
        guard let data = try? Data(contentsOf: Self.storeURL),
              let file = try? JSONDecoder().decode(SaveFile.self, from: data) else { return }
        macros = file.macros
        if let s = file.settings { settings = s }
        selection = macros.first?.id
    }

    func save() {
        let file = SaveFile(settings: settings, macros: macros)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(file).write(to: Self.storeURL, options: .atomic)
        } catch {
            message = "保存に失敗しました: \(error.localizedDescription)"
        }
    }

    func exportMacros() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "テンキーマクロ.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(SaveFile(settings: settings, macros: macros)).write(to: url, options: .atomic)
            message = "\(macros.count) 個のマクロを書き出しました"
        } catch {
            message = "書き出しに失敗しました: \(error.localizedDescription)"
        }
    }

    func importMacros() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try JSONDecoder().decode(SaveFile.self, from: Data(contentsOf: url))
            var added = 0
            var hotkeyConflicts = 0
            var list = macros
            for var m in file.macros {
                if list.contains(where: { $0.id == m.id }) { m.id = UUID() }
                if let hk = m.hotkey, list.contains(where: { $0.hotkey == hk }) {
                    m.hotkey = nil
                    hotkeyConflicts += 1
                }
                list.append(m)
                added += 1
            }
            macros = list
            message = "\(added) 個のマクロを読み込みました" +
                (hotkeyConflicts > 0 ? "（\(hotkeyConflicts) 個はホットキーが重複したため解除）" : "")
        } catch {
            message = "読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: - マクロ操作

    func binding(for id: UUID) -> Binding<Macro>? {
        guard macros.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { self.macros.first(where: { $0.id == id }) ?? Macro(name: "") },
            set: { newValue in
                if let i = self.macros.firstIndex(where: { $0.id == id }) { self.macros[i] = newValue }
            }
        )
    }

    func newMacro() {
        let m = Macro(name: "マクロ \(macros.count + 1)")
        macros.append(m)
        selection = m.id
    }

    func deleteSelected() {
        guard let id = selection, let i = macros.firstIndex(where: { $0.id == id }) else { return }
        let name = macros[i].name
        let alert = NSAlert()
        alert.messageText = "「\(name)」を削除しますか？"
        alert.informativeText = "この操作は取り消せません。"
        alert.addButton(withTitle: "削除")
        alert.addButton(withTitle: "キャンセル")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        macros.remove(at: i)
        selection = macros.indices.contains(i) ? macros[i].id : macros.last?.id
    }

    func duplicateSelected() {
        guard let id = selection, let i = macros.firstIndex(where: { $0.id == id }) else { return }
        var m = macros[i]
        m.id = UUID()
        m.name += " のコピー"
        m.hotkey = nil
        m.steps = m.steps.map { $0.duplicated() }
        macros.insert(m, at: i + 1)
        selection = m.id
    }

    func play(_ id: UUID) {
        guard engineRunning else { message = "アクセシビリティの許可が必要です"; return }
        guard let m = macros.first(where: { $0.id == id }) else { return }
        if !engine.player.play(m) { NSSound.beep() }
    }

    func stopPlayback() { engine.player.stop() }

    // MARK: - 記録

    /// target が nil なら新しいマクロとして記録、指定ありならそのマクロの手順を置き換える
    func startRecording(into target: UUID?) {
        guard engineRunning else { message = "アクセシビリティの許可が必要です"; return }
        guard !isRecording else { return }
        recordTarget = target
        engine.beginRecording()
        isRecording = true
        let stopName = settings.recordStopKey?.display ?? "停止ボタン"
        message = "記録中… \(stopName) で停止"
    }

    func stopRecording() {
        guard isRecording else { return }
        let rects = NSApp.windows.filter { $0.isVisible }.map { Self.cgRect(of: $0.frame) }
        let steps = engine.endRecording(excluding: rects)
        isRecording = false
        NSApp.activate(ignoringOtherApps: true)

        guard !steps.isEmpty else { message = "操作が記録されませんでした"; return }
        if let id = recordTarget, let i = macros.firstIndex(where: { $0.id == id }) {
            macros[i].steps = steps
            selection = id
            message = "「\(macros[i].name)」を再記録しました（\(steps.count) ステップ）"
        } else {
            let m = Macro(name: "記録 \(macros.count + 1)", steps: steps)
            macros.append(m)
            selection = m.id
            message = "新しいマクロを記録しました（\(steps.count) ステップ）"
        }
    }

    /// Cocoa 座標（左下原点）→ CG 座標（左上原点）
    static func cgRect(of r: NSRect) -> CGRect {
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }

    // MARK: - キー取得

    func beginCapture(_ id: String, apply: @escaping (_ keyCode: Int, _ flags: UInt64) -> Void) {
        guard engineRunning else {
            let alert = NSAlert()
            alert.messageText = "キーを設定できません"
            alert.informativeText = "アクセシビリティの許可がまだ有効になっていないため、キー入力を受け取れません。\n\nシステム設定 → プライバシーとセキュリティ → アクセシビリティ で「TenkeyMacro」をオンにしてください。すでに一覧にある場合は、一度「−」で削除してから「＋」で /Applications/TenkeyMacro.app を追加し直してください。"
            alert.addButton(withTitle: "システム設定を開く")
            alert.addButton(withTitle: "閉じる")
            if alert.runModal() == .alertFirstButtonReturn { openAccessibilitySettings() }
            return
        }
        if capturingID == id { cancelCapture(); return }
        capturingID = id
        message = "割り当てるキーを押してください（もう一度クリックで取り消し）"
        engine.captureNextKey { [weak self] code, flags in
            self?.capturingID = nil
            self?.message = ""
            apply(code, flags)
        }
    }

    func cancelCapture() {
        engine.cancelCapture()
        capturingID = nil
        message = ""
    }

    /// マクロにホットキーを割り当てる。同じキーを使っている別マクロからは外す。
    func assignHotkey(_ hk: Hotkey?, to id: UUID) {
        var list = macros
        if let hk {
            if [settings.stopKey, settings.recordStopKey, settings.toggleKey].contains(hk) {
                message = "\(hk.display) は停止/切替キーにも使われています（再生中・記録中はそちらが優先）"
            }
            for i in list.indices where list[i].id != id && list[i].hotkey == hk {
                list[i].hotkey = nil
                message = "\(hk.display) は「\(list[i].name)」から外して付け替えました"
            }
        }
        if let i = list.firstIndex(where: { $0.id == id }) { list[i].hotkey = hk }
        macros = list
    }

    // MARK: - 座標取得

    /// 3 秒後のマウス位置を返す
    func capturePosition(_ apply: @escaping (CGPoint) -> Void) {
        func tick(_ n: Int) {
            if n == 0 {
                if let p = CGEvent(source: nil)?.location {
                    apply(CGPoint(x: p.x.rounded(), y: p.y.rounded()))
                    message = "座標を取得しました: (\(Int(p.x)), \(Int(p.y)))"
                    NSSound(named: "Tink")?.play()
                }
                return
            }
            message = "\(n) 秒後のマウス位置を取得します… 目的の場所にカーソルを置いてください"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick(n - 1) }
        }
        tick(3)
    }
}

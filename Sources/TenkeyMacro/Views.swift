import SwiftUI

// MARK: - メイン画面

struct ContentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            if !app.engineRunning { PermissionBanner() }
            if app.isRecording { RecordingBanner() }

            NavigationSplitView {
                List(selection: $app.selection) {
                    ForEach(app.macros) { m in
                        MacroRow(macro: m).tag(m.id)
                    }
                    .onMove { app.macros.move(fromOffsets: $0, toOffset: $1) }
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Button { app.newMacro() } label: { Image(systemName: "plus") }
                            .help("空のマクロを追加")
                        Button { app.deleteSelected() } label: { Image(systemName: "minus") }
                            .help("選択中のマクロを削除")
                            .disabled(app.selection == nil)
                        Button { app.duplicateSelected() } label: { Image(systemName: "plus.square.on.square") }
                            .help("選択中のマクロを複製")
                            .disabled(app.selection == nil)
                        Spacer()
                    }
                    .buttonStyle(.borderless)
                    .padding(8)
                }
            } detail: {
                if let id = app.selection, let binding = app.binding(for: id) {
                    MacroEditorView(macro: binding)
                        .id(id)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "keyboard").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("左のリストからマクロを選ぶか、「記録」で新しく作成します")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            StatusBar()
        }
        .toolbar {
            ToolbarItemGroup {
                if app.isRecording {
                    Button { app.stopRecording() } label: {
                        Label("記録停止", systemImage: "stop.circle.fill")
                    }
                    .tint(.red)
                } else {
                    Button { app.startRecording(into: nil) } label: {
                        Label("新規記録", systemImage: "record.circle")
                    }
                    .help("新しいマクロとして操作を記録します")
                }
                if app.playingID != nil {
                    Button { app.stopPlayback() } label: { Label("再生停止", systemImage: "stop.fill") }
                }
                Divider()
                Button { app.importMacros() } label: { Label("読み込み", systemImage: "square.and.arrow.down") }
                    .help("JSON ファイルからマクロを追加で読み込みます")
                Button { app.exportMacros() } label: { Label("書き出し", systemImage: "square.and.arrow.up") }
                    .help("全マクロを JSON ファイルに書き出します")
                Toggle(isOn: $app.settings.hotkeysEnabled) {
                    Label(app.settings.hotkeysEnabled ? "ホットキー ON" : "ホットキー OFF",
                          systemImage: app.settings.hotkeysEnabled ? "bolt.fill" : "bolt.slash")
                }
                .toggleStyle(.button)
                .help("全ホットキーの有効/無効")
                SettingsLink { Label("設定", systemImage: "gearshape") }
            }
        }
    }
}

struct MacroRow: View {
    @EnvironmentObject var app: AppState
    let macro: Macro

    var body: some View {
        HStack {
            if app.playingID == macro.id {
                Image(systemName: "play.fill").foregroundStyle(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(macro.name.isEmpty ? "(無題)" : macro.name)
                    .foregroundStyle(macro.enabled ? .primary : .secondary)
                Text("\(macro.steps.count) ステップ")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let hk = macro.hotkey {
                Text(hk.display)
                    .font(.caption.monospaced())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(macro.enabled ? 0.2 : 0.07)))
            }
        }
        .padding(.vertical, 2)
    }
}

struct PermissionBanner: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text("キー監視とマウス操作には「アクセシビリティ」の許可が必要です。システム設定でこのアプリをオンにしてください（自動で検出します）。")
                .font(.callout)
            Spacer()
            Button("システム設定を開く") { app.openAccessibilitySettings() }
        }
        .padding(10)
        .background(Color.yellow.opacity(0.15))
    }
}

struct RecordingBanner: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack {
            Image(systemName: "record.circle.fill").foregroundStyle(.red)
            Text("記録中 — 操作したいアプリで操作してください。\(app.settings.recordStopKey.map { "\($0.display) キーで停止" } ?? "停止ボタンで停止")")
                .font(.callout.bold())
            Spacer()
            Button("記録停止") { app.stopRecording() }
        }
        .padding(10)
        .background(Color.red.opacity(0.15))
    }
}

struct StatusBar: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        HStack {
            Circle()
                .fill(app.engineRunning ? (app.settings.hotkeysEnabled ? Color.green : Color.orange) : Color.red)
                .frame(width: 8, height: 8)
            Text(app.engineRunning ? (app.settings.hotkeysEnabled ? "ホットキー待機中" : "ホットキー停止中") : "未許可")
                .font(.caption)
            Divider().frame(height: 12)
            Text(app.message).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.bar)
    }
}

// MARK: - マクロ編集

struct MacroEditorView: View {
    @EnvironmentObject var app: AppState
    @Binding var macro: Macro
    @State private var selectedStep: UUID?
    @State private var bulkDelay = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(14)
            Divider()
            stepToolbar.padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            if macro.steps.isEmpty {
                Text("ステップがありません。「再記録」で操作を記録するか、「ステップ追加」で手動で作成します。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedStep) {
                    ForEach($macro.steps) { $step in
                        StepRow(step: $step,
                                index: macro.steps.firstIndex(where: { $0.id == step.id }) ?? 0,
                                onMove: { moveStep(step.id, by: $0) },
                                onDuplicate: { duplicateStep(step.id) },
                                onDelete: { deleteStep(step.id) })
                            .tag(step.id)
                    }
                    .onMove { macro.steps.move(fromOffsets: $0, toOffset: $1) }
                }
            }
        }
    }

    private var header: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("名前")
                TextField("マクロ名", text: $macro.name).frame(maxWidth: 320)
            }
            GridRow {
                Text("ホットキー")
                HStack {
                    let capId = "macro-\(macro.id)"
                    Button(app.capturingID == capId ? "キーを押してください…" : (macro.hotkey?.display ?? "未設定（クリックして設定）")) {
                        app.beginCapture(capId) { code, flags in
                            app.assignHotkey(Hotkey(keyCode: code, modifiers: flags), to: macro.id)
                        }
                    }
                    .frame(minWidth: 200)
                    if macro.hotkey != nil {
                        Button("解除") { app.assignHotkey(nil, to: macro.id) }
                    }
                    Toggle("有効", isOn: $macro.enabled).padding(.leading, 12)
                }
            }
            GridRow {
                Text("再生")
                HStack(spacing: 16) {
                    Stepper("繰り返し \(macro.repeatCount) 回", value: $macro.repeatCount, in: 1...999)
                    Picker("速度", selection: $macro.speed) {
                        Text("0.5倍").tag(0.5)
                        Text("1倍").tag(1.0)
                        Text("2倍").tag(2.0)
                        Text("4倍").tag(4.0)
                        Text("10倍").tag(10.0)
                    }
                    .frame(width: 130)
                    Toggle("再生後マウスを元の位置に戻す", isOn: $macro.restoreCursor)
                }
            }
            GridRow {
                Text("")
                HStack {
                    if app.playingID == macro.id {
                        Button { app.stopPlayback() } label: { Label("停止", systemImage: "stop.fill") }
                    } else {
                        Button { app.play(macro.id) } label: { Label("テスト再生", systemImage: "play.fill") }
                            .disabled(macro.steps.isEmpty || app.isRecording)
                    }
                    Button { app.startRecording(into: macro.id) } label: { Label("再記録", systemImage: "record.circle") }
                        .disabled(app.isRecording)
                        .help("このマクロの手順を記録し直します（今の手順は置き換わります）")
                }
            }
        }
    }

    private var stepToolbar: some View {
        HStack {
            Menu {
                ForEach(StepKind.allCases) { k in
                    Button(k.label) { addStep(k) }
                }
            } label: { Label("ステップ追加", systemImage: "plus") }
            .fixedSize()
            .help("選択中のステップの後ろ（未選択なら末尾）に追加")

            Spacer()

            Text("全ステップの待機を")
            TextField("", value: $bulkDelay, format: .number).frame(width: 50)
            Text("ms に")
            Button("一括設定") {
                for i in macro.steps.indices { macro.steps[i].delayMs = i == 0 ? 0 : max(0, bulkDelay) }
            }
            .help("先頭ステップは 0ms、それ以外を指定値にします。記録したマクロを速くしたいときに")
            Text("合計 \(totalMs) ms").foregroundStyle(.secondary).font(.caption).padding(.leading, 8)
        }
    }

    private var totalMs: Int { macro.steps.reduce(0) { $0 + $1.delayMs } }

    private func index(of id: UUID) -> Int? { macro.steps.firstIndex(where: { $0.id == id }) }

    private func addStep(_ kind: StepKind) {
        var s = MacroStep(kind: kind)
        s.delayMs = macro.steps.isEmpty ? 0 : 30
        if kind.usesPosition, let p = CGEvent(source: nil)?.location {
            s.x = p.x.rounded(); s.y = p.y.rounded()
        }
        if kind.usesKey { s.keyCode = 76 } // テンキーEnter
        if let sel = selectedStep, let i = index(of: sel) {
            macro.steps.insert(s, at: i + 1)
        } else {
            macro.steps.append(s)
        }
        selectedStep = s.id
    }

    private func moveStep(_ id: UUID, by offset: Int) {
        guard let i = index(of: id) else { return }
        let j = i + offset
        guard macro.steps.indices.contains(j) else { return }
        macro.steps.swapAt(i, j)
    }

    private func duplicateStep(_ id: UUID) {
        guard let i = index(of: id) else { return }
        let s = macro.steps[i].duplicated()
        macro.steps.insert(s, at: i + 1)
        selectedStep = s.id
    }

    private func deleteStep(_ id: UUID) {
        guard let i = index(of: id) else { return }
        macro.steps.remove(at: i)
    }
}

struct StepRow: View {
    @EnvironmentObject var app: AppState
    @Binding var step: MacroStep
    let index: Int
    let onMove: (Int) -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Picker("", selection: $step.kind) {
                ForEach(StepKind.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 120)

            Text("待機")
            TextField("", value: $step.delayMs, format: .number)
                .frame(width: 56)
                .multilineTextAlignment(.trailing)
            Text("ms")

            Divider().frame(height: 16)
            detail
            Spacer(minLength: 8)

            Group {
                Button { onMove(-1) } label: { Image(systemName: "arrow.up") }.help("上へ")
                Button { onMove(1) } label: { Image(systemName: "arrow.down") }.help("下へ")
                Button(action: onDuplicate) { Image(systemName: "plus.square.on.square") }.help("複製")
                Button(action: onDelete) { Image(systemName: "trash") }.help("削除")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var detail: some View {
        if step.kind.usesPosition {
            HStack(spacing: 4) {
                Text("X")
                TextField("", value: $step.x, format: .number.grouping(.never)).frame(width: 56)
                Text("Y")
                TextField("", value: $step.y, format: .number.grouping(.never)).frame(width: 56)
                Button {
                    app.capturePosition { p in step.x = p.x; step.y = p.y }
                } label: { Image(systemName: "scope") }
                .help("3 秒後のマウス位置を取得")
                if step.kind.usesButton {
                    Picker("", selection: $step.button) {
                        ForEach(MouseButton.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 70)
                }
                if step.kind == .click {
                    Stepper("\(step.clickCount)回", value: $step.clickCount, in: 1...3).fixedSize()
                }
                if step.flags & Hotkey.modifierMask != 0 {
                    Text("+" + KeyNames.modifierSymbols(step.flags)).foregroundStyle(.secondary)
                }
            }
        } else if step.kind.usesKey {
            let capId = "step-\(step.id)"
            Button(app.capturingID == capId ? "キーを押してください…"
                   : KeyNames.modifierSymbols(step.flags) + KeyNames.name(for: step.keyCode)) {
                app.beginCapture(capId) { code, flags in
                    step.keyCode = code
                    step.flags = flags & Hotkey.modifierMask
                }
            }
            .frame(minWidth: 140)
            .help("クリックしてから押したキーに変更（修飾キーも可）")
        } else if step.kind == .scroll {
            HStack(spacing: 4) {
                Text("縦")
                TextField("", value: $step.scrollY, format: .number).frame(width: 50)
                Text("横")
                TextField("", value: $step.scrollX, format: .number).frame(width: 50)
            }
        } else {
            Text("待機時間だけ待ちます").foregroundStyle(.secondary)
        }
    }
}

// MARK: - 設定

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Form {
            Section("特別なキー") {
                keyRow("再生の緊急停止", id: "set-stop", value: $app.settings.stopKey)
                keyRow("記録の停止", id: "set-recstop", value: $app.settings.recordStopKey)
                keyRow("ホットキー ON/OFF 切替", id: "set-toggle", value: $app.settings.toggleKey)
            }
            Section("動作") {
                Toggle("ホットキーを有効にする", isOn: $app.settings.hotkeysEnabled)
                Toggle("ホットキーに使ったキーを他のアプリに送らない", isOn: $app.settings.consumeHotkey)
                Text("オンのとき、例えばテンキー1をマクロに割り当てると、売買アプリには「1」が入力されません。")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("記録時にマウスの移動も記録する", isOn: $app.settings.recordMouseMoves)
                Text("通常はオフ（クリック位置だけ記録）がおすすめです。ドラッグは常に記録されます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("保存場所") {
                Text(AppState.storeURL.path).font(.caption).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 460)
    }

    private func keyRow(_ title: String, id: String, value: Binding<Hotkey?>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(app.capturingID == id ? "キーを押してください…" : (value.wrappedValue?.display ?? "なし")) {
                app.beginCapture(id) { code, flags in
                    value.wrappedValue = Hotkey(keyCode: code, modifiers: flags)
                }
            }
            .frame(minWidth: 160)
            if value.wrappedValue != nil {
                Button("解除") { value.wrappedValue = nil }
            }
        }
    }
}

// MARK: - メニューバー

struct MenuBarContent: View {
    @EnvironmentObject var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle("ホットキー有効", isOn: $app.settings.hotkeysEnabled)
        if app.playingID != nil {
            Button("再生停止") { app.stopPlayback() }
        }
        if app.isRecording {
            Button("記録停止") { app.stopRecording() }
        }
        Divider()
        Button("ウィンドウを開く") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("設定…") }
        Divider()
        Button("テンキーマクロを終了") { NSApp.terminate(nil) }
    }
}

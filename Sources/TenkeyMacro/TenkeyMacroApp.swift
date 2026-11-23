import SwiftUI

@main
struct TenkeyMacroApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        Window("テンキーマクロ", id: "main") {
            ContentView()
                .environmentObject(app)
                .frame(minWidth: 960, minHeight: 540)
        }

        Settings {
            SettingsView().environmentObject(app)
        }

        MenuBarExtra {
            MenuBarContent().environmentObject(app)
        } label: {
            Image(systemName: app.isRecording ? "record.circle"
                  : (app.playingID != nil ? "play.circle.fill"
                     : (app.settings.hotkeysEnabled ? "keyboard.fill" : "keyboard")))
        }
    }
}

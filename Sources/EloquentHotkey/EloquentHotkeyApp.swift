import SwiftUI

@main
struct EloquentHotkeyApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            Button(model.isListening ? "Stop Dictation" : "Start Dictation") {
                model.toggleDictation()
            }

            Divider()

            Button("Paste Last Result") {
                model.pasteLastResult()
            }
            .disabled(model.lastText.isEmpty)

            Button("Copy Last Result") {
                model.copyLastResult()
            }
            .disabled(model.lastText.isEmpty)

            if !model.lastText.isEmpty {
                Divider()
                Text(model.lastText)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text(model.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button("Settings…") {
                AppCommands.openSettings()
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        } label: {
            Label(
                "EloquentHotkey",
                systemImage: model.isListening ? "waveform.circle.fill" : "waveform.circle"
            )
        }

        Settings {
            SettingsView(model: model)
                .frame(width: 520)
                .padding(20)
        }
    }
}

enum AppCommands {
    @MainActor
    static func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

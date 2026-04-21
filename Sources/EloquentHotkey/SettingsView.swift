import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Input") {
                Picker("Microphone", selection: $model.selectedMicrophoneID) {
                    ForEach(model.availableMicrophones) { microphone in
                        Text(microphone.name).tag(microphone.id)
                    }
                }

                Button("Refresh Microphones") {
                    model.refreshMicrophones()
                }
            }

            Section("Shortcut") {
                ShortcutRecorderRow(
                    shortcut: model.hotkey,
                    onChange: { model.updateHotkey($0) }
                )

                HStack {
                    Text("Current shortcut")
                    Spacer()
                    Text(model.hotkey.displayString)
                        .foregroundStyle(.secondary)
                }

                Button("Reset to Default Shortcut") {
                    model.resetHotkey()
                }

                if !model.hotkeyRegistrationSucceeded {
                    Text("That shortcut could not be registered. Try a different combination.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Behavior") {
                Toggle("Auto-paste after dictation", isOn: $model.autoPasteEnabled)
                Toggle("Clean up filler words and spacing", isOn: $model.cleanupEnabled)

                HStack {
                    Text("Silence timeout")
                    Spacer()
                    Text(String(format: "%.1f s", model.silenceTimeout))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.silenceTimeout, in: 0.6...3.0, step: 0.1)

                HStack {
                    Text("Maximum recording length")
                    Spacer()
                    Text(String(format: "%.0f s", model.maxDuration))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.maxDuration, in: 10...120, step: 5)
            }

            Section("Recovery") {
                Text("The app always keeps the last result on your clipboard, and you can also use the menu bar actions to copy or paste it again if the original field misses focus.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Copy Last Result") {
                        model.copyLastResult()
                    }
                    .disabled(model.lastText.isEmpty)

                    Button("Paste Last Result") {
                        model.pasteLastResult()
                    }
                    .disabled(model.lastText.isEmpty)
                }
            }
        }
    }
}

struct ShortcutRecorderRow: View {
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void

    @StateObject private var recorder = ShortcutRecorderState()

    var body: some View {
        HStack(alignment: .top) {
            Text("Global hotkey")
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button(recorder.isRecording ? "Press a shortcut…" : shortcut.displayString) {
                    recorder.beginRecording(onChange: onChange)
                }

                Text(recorder.isRecording ? "Press a new shortcut or Esc to cancel." : "Choose a keyboard shortcut for starting or stopping dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            recorder.stopRecording()
        }
    }
}

final class ShortcutRecorderState: ObservableObject {
    @Published private(set) var isRecording = false

    private var monitor: Any?

    func beginRecording(onChange: @escaping (Shortcut) -> Void) {
        stopRecording()
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isRecording else {
                return event
            }

            if event.keyCode == UInt16(kVK_Escape) {
                self.stopRecording()
                return nil
            }

            guard let shortcut = Shortcut.from(event: event) else {
                return nil
            }

            self.stopRecording()
            onChange(shortcut)
            return nil
        }
    }

    func stopRecording() {
        isRecording = false

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

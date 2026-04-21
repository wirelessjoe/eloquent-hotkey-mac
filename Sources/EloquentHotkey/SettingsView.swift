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
                    onChange: { model.updateHotkey($0) },
                    onRecordingChange: { model.setHotkeyMonitoringEnabled(!$0) }
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
                    Text("That shortcut is inactive. Make sure Accessibility access is enabled, then try again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Behavior") {
                Toggle("Auto-paste after dictation", isOn: $model.autoPasteEnabled)
                Toggle("Clean up filler words and spacing", isOn: $model.cleanupEnabled)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cleanup engine")
                        Spacer()
                        Text(model.cleanupEngineStatus.headline)
                            .foregroundStyle(model.cleanupEngineStatus.isAppleIntelligenceActive ? .green : .secondary)
                    }

                    Text(model.cleanupEngineStatus.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Refresh Model Status") {
                        model.refreshCleanupEngineStatus()
                    }
                    .font(.caption)
                }

                HStack {
                    Text("Silence timeout (manual start)")
                    Spacer()
                    Text(String(format: "%.1f s", model.silenceTimeout))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.silenceTimeout, in: 0.6...3.0, step: 0.1)
                Text("Press-and-hold dictation stops when you release the shortcut. This timeout only applies when you start dictation from the menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Maximum recording length")
                    Spacer()
                    Text(String(format: "%.0f s", model.maxDuration))
                        .foregroundStyle(.secondary)
                }
                Slider(value: $model.maxDuration, in: 10...120, step: 5)
            }

            Section("Recovery") {
                Text("The app saves the last result locally so you can paste it again without replacing your clipboard. Use Copy Last Result only when you intentionally want the transcript on your clipboard.")
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
        .onAppear {
            model.refreshCleanupEngineStatus()
        }
    }
}

struct ShortcutRecorderRow: View {
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void
    let onRecordingChange: (Bool) -> Void

    @StateObject private var recorder = ShortcutRecorderState()

    var body: some View {
        HStack(alignment: .top) {
            Text("Global hotkey")
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Button(recorder.isRecording ? "Press a shortcut…" : shortcut.displayString) {
                    recorder.beginRecording(onChange: onChange, onRecordingChange: onRecordingChange)
                }

                Text(recorder.isRecording ? "Press a new shortcut, or press Fn by itself. Press Esc to cancel." : "Choose a press-and-hold shortcut for dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            recorder.stopRecording(onRecordingChange: onRecordingChange)
        }
    }
}

final class ShortcutRecorderState: ObservableObject {
    @Published private(set) var isRecording = false

    private var monitor: Any?

    func beginRecording(
        onChange: @escaping (Shortcut) -> Void,
        onRecordingChange: @escaping (Bool) -> Void
    ) {
        stopRecording(onRecordingChange: onRecordingChange)
        isRecording = true
        onRecordingChange(true)

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.isRecording else {
                return event
            }

            if event.type == .keyDown, event.keyCode == UInt16(kVK_Escape) {
                self.stopRecording(onRecordingChange: onRecordingChange)
                return nil
            }

            guard let shortcut = Shortcut.from(event: event) else {
                return event.type == .flagsChanged ? event : nil
            }

            self.stopRecording(onRecordingChange: onRecordingChange)
            onChange(shortcut)
            return nil
        }
    }

    func stopRecording(onRecordingChange: ((Bool) -> Void)? = nil) {
        let wasRecording = isRecording
        isRecording = false

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        if wasRecording {
            onRecordingChange?(false)
        }
    }
}

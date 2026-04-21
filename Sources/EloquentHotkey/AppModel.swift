@preconcurrency import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var availableMicrophones: [MicrophoneOption] = []
    @Published private(set) var isListening = false
    @Published private(set) var lastText: String
    @Published private(set) var statusMessage: String = "Ready"
    @Published private(set) var hotkeyRegistrationSucceeded = true

    @Published var selectedMicrophoneID: String {
        didSet {
            defaults.set(selectedMicrophoneID, forKey: Defaults.selectedMicrophoneID)
        }
    }

    @Published var autoPasteEnabled: Bool {
        didSet {
            defaults.set(autoPasteEnabled, forKey: Defaults.autoPasteEnabled)
        }
    }

    @Published var cleanupEnabled: Bool {
        didSet {
            defaults.set(cleanupEnabled, forKey: Defaults.cleanupEnabled)
        }
    }

    @Published var silenceTimeout: Double {
        didSet {
            defaults.set(silenceTimeout, forKey: Defaults.silenceTimeout)
        }
    }

    @Published var maxDuration: Double {
        didSet {
            defaults.set(maxDuration, forKey: Defaults.maxDuration)
        }
    }

    @Published var hotkey: Shortcut {
        didSet {
            defaults.set(Int(hotkey.keyCode), forKey: Defaults.hotkeyKeyCode)
            defaults.set(Int(hotkey.modifiers), forKey: Defaults.hotkeyModifiers)
            registerHotkey()
        }
    }

    private enum Defaults {
        static let selectedMicrophoneID = "selectedMicrophoneID"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let cleanupEnabled = "cleanupEnabled"
        static let silenceTimeout = "silenceTimeout"
        static let maxDuration = "maxDuration"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let lastText = "lastText"
    }

    private let defaults = UserDefaults.standard
    private let textPolisher = TextPolisher()
    private let hotkeyManager = GlobalHotkeyManager()

    private var activeDictation: DictationController?
    private var dictationTask: Task<Void, Never>?
    private var workspaceObserver: NSObjectProtocol?
    private var lastExternalApplication: NSRunningApplication?

    init() {
        self.lastText = defaults.string(forKey: Defaults.lastText) ?? ""
        self.selectedMicrophoneID = defaults.string(forKey: Defaults.selectedMicrophoneID) ?? AudioDeviceManager.systemDefaultID
        self.autoPasteEnabled = defaults.object(forKey: Defaults.autoPasteEnabled) as? Bool ?? true
        self.cleanupEnabled = defaults.object(forKey: Defaults.cleanupEnabled) as? Bool ?? true
        self.silenceTimeout = defaults.object(forKey: Defaults.silenceTimeout) as? Double ?? 1.2
        self.maxDuration = defaults.object(forKey: Defaults.maxDuration) as? Double ?? 45

        let savedKeyCode = defaults.object(forKey: Defaults.hotkeyKeyCode) as? Int
        let savedModifiers = defaults.object(forKey: Defaults.hotkeyModifiers) as? Int
        if let savedKeyCode, let savedModifiers {
            self.hotkey = Shortcut(
                keyCode: UInt32(savedKeyCode),
                modifiers: UInt32(savedModifiers)
            )
        } else {
            self.hotkey = .defaultValue
        }

        refreshMicrophones()
        lastExternalApplication = currentTargetApplication()

        hotkeyManager.onKeyPress = { [weak self] in
            Task { @MainActor in
                self?.toggleDictation()
            }
        }

        observeActiveApplications()

        DispatchQueue.main.async { [weak self] in
            self?.registerHotkey()
        }
    }

    var selectedMicrophoneName: String {
        availableMicrophones.first(where: { $0.id == selectedMicrophoneID })?.name ?? "System Default"
    }

    func refreshMicrophones() {
        availableMicrophones = AudioDeviceManager.availableMicrophones()
        if !availableMicrophones.contains(where: { $0.id == selectedMicrophoneID }) {
            selectedMicrophoneID = AudioDeviceManager.systemDefaultID
        }
    }

    func updateHotkey(_ newHotkey: Shortcut) {
        hotkey = newHotkey
        statusMessage = "Shortcut updated to \(newHotkey.displayString)."
    }

    func resetHotkey() {
        hotkey = .defaultValue
        statusMessage = "Shortcut reset to \(hotkey.displayString)."
    }

    func toggleDictation() {
        if isListening {
            stopDictation()
        } else {
            startDictation()
        }
    }

    func copyLastResult() {
        guard !lastText.isEmpty else {
            return
        }

        ClipboardManager.copy(lastText)
        statusMessage = "Last result copied to the clipboard."
    }

    func pasteLastResult() {
        guard !lastText.isEmpty else {
            return
        }

        ClipboardManager.copy(lastText)

        Task {
            let pasted = await AutoPasteController.paste(
                into: currentTargetApplication()
            )

            await MainActor.run {
                statusMessage = pasted
                    ? "Last result pasted."
                    : "Could not paste automatically. The text is still on your clipboard."
            }
        }
    }

    private func startDictation() {
        guard !isListening else {
            return
        }

        statusMessage = "Listening with \(selectedMicrophoneName)…"
        isListening = true
        NSSound.beep()

        let targetApplication = currentTargetApplication()
        let config = DictationConfiguration(
            microphoneID: selectedMicrophoneID == AudioDeviceManager.systemDefaultID ? nil : selectedMicrophoneID,
            silenceTimeout: silenceTimeout,
            maxDuration: maxDuration
        )
        let dictation = DictationController(configuration: config)

        activeDictation = dictation
        dictationTask?.cancel()
        dictationTask = Task {
            do {
                try await PermissionManager.requestMicrophoneAndSpeechAccess()
                let transcript = try await dictation.captureAndTranscribe()
                let polished = cleanupEnabled ? textPolisher.polish(transcript) : transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                await MainActor.run {
                    completeDictation(with: polished, targetApplication: targetApplication)
                }
            } catch {
                await MainActor.run {
                    failDictation(with: error)
                }
            }
        }
    }

    private func stopDictation() {
        guard isListening else {
            return
        }

        statusMessage = "Finishing dictation…"
        activeDictation?.requestStop()
    }

    private func completeDictation(with text: String, targetApplication: NSRunningApplication?) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        activeDictation = nil
        dictationTask = nil
        isListening = false
        NSSound.beep()

        guard !cleaned.isEmpty else {
            statusMessage = "No text was captured."
            return
        }

        lastText = cleaned
        defaults.set(cleaned, forKey: Defaults.lastText)
        ClipboardManager.copy(cleaned)

        if autoPasteEnabled {
            statusMessage = "Copied last result. Pasting…"

            Task {
                let pasted = await AutoPasteController.paste(
                    into: targetApplication
                )

                await MainActor.run {
                    statusMessage = pasted
                        ? "Dictation pasted."
                        : "Copied last result. Use Paste Last Result if the field missed focus."
                }
            }
        } else {
            statusMessage = "Copied last result to the clipboard."
        }
    }

    private func failDictation(with error: Error) {
        activeDictation = nil
        dictationTask = nil
        isListening = false
        NSSound.beep()
        statusMessage = error.localizedDescription
    }

    private func observeActiveApplications() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                return
            }

            Task { @MainActor in
                self.lastExternalApplication = application
            }
        }
    }

    private func currentTargetApplication() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return lastExternalApplication
        }

        if let frontmost {
            return frontmost
        }

        return lastExternalApplication
    }

    private func registerHotkey() {
        hotkeyRegistrationSucceeded = hotkeyManager.register(shortcut: hotkey)
        if !hotkeyRegistrationSucceeded {
            statusMessage = "The shortcut \(hotkey.displayString) is unavailable. Pick a different one."
        }
    }
}

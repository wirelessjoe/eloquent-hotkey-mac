@preconcurrency import AppKit
import Carbon
import Foundation
import OSLog

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var availableMicrophones: [MicrophoneOption] = []
    @Published private(set) var isListening = false
    @Published private(set) var isCleaningUp = false
    @Published private(set) var lastText: String
    @Published private(set) var statusMessage: String = "Ready"
    @Published private(set) var hotkeyRegistrationSucceeded = true
    @Published private(set) var cleanupEngineStatus = TranscriptCleaner.currentStatus()

    @Published var selectedMicrophoneID: String {
        didSet {
            defaults.set(selectedMicrophoneID, forKey: Defaults.selectedMicrophoneID)
        }
    }

    @Published var autoPasteEnabled: Bool {
        didSet {
            defaults.set(autoPasteEnabled, forKey: Defaults.autoPasteEnabled)

            if autoPasteEnabled && !ensurePostEventAccess(promptIfNeeded: true) {
                statusMessage = "Allow EloquentHotkey to control your computer to enable auto-paste."
            }
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
            defaults.set(Int(hotkey.modifiers.rawValue), forKey: Defaults.hotkeyModifiers)
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
        static let hasRequestedListenEventPrompt = "hasRequestedListenEventPrompt"
        static let hasRequestedPostEventPrompt = "hasRequestedPostEventPrompt"
    }

    private let defaults = UserDefaults.standard
    private let transcriptCleaner = TranscriptCleaner()
    private let hotkeyManager = GlobalHotkeyManager()
    private let logger = Logger(subsystem: "dev.codex.EloquentHotkey", category: "AppModel")

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
            self.hotkey = Self.loadShortcut(
                keyCode: savedKeyCode,
                modifiers: savedModifiers
            )
        } else {
            self.hotkey = .defaultValue
        }

        refreshMicrophones()
        lastExternalApplication = currentTargetApplication()

        hotkeyManager.onPress = { [weak self] in
            Task { @MainActor in
                self?.startDictation(trigger: .holdToTalk)
            }
        }

        hotkeyManager.onRelease = { [weak self] in
            Task { @MainActor in
                self?.stopDictation()
            }
        }

        observeActiveApplications()

        DispatchQueue.main.async { [weak self] in
            self?.refreshCleanupEngineStatus()
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

    func refreshCleanupEngineStatus() {
        cleanupEngineStatus = TranscriptCleaner.currentStatus()
    }

    func updateHotkey(_ newHotkey: Shortcut) {
        if !PermissionManager.hasListenEventAccess() {
            _ = ensureListenEventAccess(promptIfNeeded: true)
        }

        hotkey = newHotkey
        if hotkeyRegistrationSucceeded {
            statusMessage = "Hold \(newHotkey.displayString) to dictate."
        }
    }

    func resetHotkey() {
        if !PermissionManager.hasListenEventAccess() {
            _ = ensureListenEventAccess(promptIfNeeded: true)
        }

        hotkey = .defaultValue
        if hotkeyRegistrationSucceeded {
            statusMessage = "Hold \(hotkey.displayString) to dictate."
        }
    }

    func toggleDictation() {
        guard !isCleaningUp else {
            return
        }

        if isListening {
            stopDictation()
        } else {
            startDictation(trigger: .manual)
        }
    }

    func copyLastResult() {
        guard !lastText.isEmpty else {
            return
        }

        ClipboardManager.copy(lastText)
        statusMessage = "Last result copied to the clipboard."
    }

    func setHotkeyMonitoringEnabled(_ enabled: Bool) {
        hotkeyManager.isEnabled = enabled
    }

    func pasteLastResult() {
        guard !lastText.isEmpty else {
            return
        }

        guard ensurePostEventAccess(promptIfNeeded: true) else {
            statusMessage = "Could not paste automatically. Allow EloquentHotkey to control your computer, then try again. The last result is still saved in the app."
            return
        }

        Task {
            let pasted = await AutoPasteController.paste(
                lastText,
                into: currentTargetApplication()
            )

            await MainActor.run {
                statusMessage = pasted
                    ? "Last result pasted."
                    : "Could not paste automatically. Use Copy Last Result if you want it on your clipboard."
            }
        }
    }

    private enum DictationTrigger {
        case holdToTalk
        case manual

        var autoStopOnSilence: Bool {
            self == .manual
        }

        var logName: String {
            switch self {
            case .holdToTalk:
                "hold-to-talk"
            case .manual:
                "manual"
            }
        }
    }

    private func startDictation(trigger: DictationTrigger) {
        guard !isListening, !isCleaningUp else {
            return
        }

        statusMessage = "Listening with \(selectedMicrophoneName)…"
        isListening = true
        isCleaningUp = false
        logger.debug("Starting dictation via \(trigger.logName, privacy: .public)")
        SoundEffect.playStartRecording()

        let targetApplication = currentTargetApplication()
        let config = DictationConfiguration(
            microphoneID: selectedMicrophoneID == AudioDeviceManager.systemDefaultID ? nil : selectedMicrophoneID,
            silenceTimeout: silenceTimeout,
            maxDuration: maxDuration,
            autoStopOnSilence: trigger.autoStopOnSilence
        )
        let dictation = DictationController(configuration: config)

        activeDictation = dictation
        dictationTask?.cancel()
        dictationTask = Task {
            do {
                try await PermissionManager.requestMicrophoneAndSpeechAccess()
                let transcript = try await dictation.captureAndTranscribe()
                let polished: String

                if cleanupEnabled {
                    await MainActor.run {
                        beginCleanupPhase()
                    }
                    polished = await transcriptCleaner.clean(transcript)
                } else {
                    polished = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                }

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
        logger.debug("Stop requested from UI or key release")
        activeDictation?.requestStop()
    }

    private func beginCleanupPhase() {
        isListening = false
        isCleaningUp = true
        activeDictation = nil
        statusMessage = "Cleaning up transcript…"
    }

    private func completeDictation(with text: String, targetApplication: NSRunningApplication?) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        activeDictation = nil
        dictationTask = nil
        isListening = false
        isCleaningUp = false
        SoundEffect.playFinishRecording()

        guard !cleaned.isEmpty else {
            statusMessage = "No text was captured."
            return
        }

        lastText = cleaned
        defaults.set(cleaned, forKey: Defaults.lastText)

        if autoPasteEnabled {
            guard ensurePostEventAccess(promptIfNeeded: true) else {
                statusMessage = "Saved last result. Allow EloquentHotkey to control your computer to enable auto-paste."
                return
            }

            statusMessage = "Saved last result. Pasting…"

            Task {
                let pasted = await AutoPasteController.paste(
                    cleaned,
                    into: targetApplication
                )

                await MainActor.run {
                    statusMessage = pasted
                        ? "Dictation pasted."
                        : "Saved last result. Use Paste Last Result again or Copy Last Result if the field missed focus."
                }
            }
        } else {
            statusMessage = "Saved last result. Use Copy Last Result if you want it on your clipboard."
        }
    }

    private func failDictation(with error: Error) {
        activeDictation = nil
        dictationTask = nil
        isListening = false
        isCleaningUp = false
        SoundEffect.playFinishRecording()
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
            statusMessage = PermissionManager.hasListenEventAccess()
                ? "Could not activate \(hotkey.displayString) as the global hold-to-talk shortcut."
                : "Allow EloquentHotkey to monitor your keyboard to use the global hold-to-talk shortcut."
        }
    }

    @discardableResult
    private func ensureListenEventAccess(promptIfNeeded: Bool) -> Bool {
        if PermissionManager.hasListenEventAccess() {
            return true
        }

        guard promptIfNeeded else {
            return false
        }

        let hasRequestedPrompt = defaults.bool(forKey: Defaults.hasRequestedListenEventPrompt)
        if !hasRequestedPrompt {
            defaults.set(true, forKey: Defaults.hasRequestedListenEventPrompt)
            _ = PermissionManager.hasListenEventAccess(prompt: true)
        }

        return PermissionManager.hasListenEventAccess()
    }

    @discardableResult
    private func ensurePostEventAccess(promptIfNeeded: Bool) -> Bool {
        if PermissionManager.hasPostEventAccess() {
            return true
        }

        guard promptIfNeeded else {
            return false
        }

        let hasRequestedPrompt = defaults.bool(forKey: Defaults.hasRequestedPostEventPrompt)
        if !hasRequestedPrompt {
            defaults.set(true, forKey: Defaults.hasRequestedPostEventPrompt)
            _ = PermissionManager.hasPostEventAccess(prompt: true)
        }

        return PermissionManager.hasPostEventAccess()
    }

    private static func loadShortcut(keyCode: Int, modifiers: Int) -> Shortcut {
        let appKitThreshold = 1 << 16
        if modifiers < appKitThreshold {
            var converted: NSEvent.ModifierFlags = []
            if modifiers & Int(cmdKey) != 0 {
                converted.insert(.command)
            }
            if modifiers & Int(controlKey) != 0 {
                converted.insert(.control)
            }
            if modifiers & Int(optionKey) != 0 {
                converted.insert(.option)
            }
            if modifiers & Int(shiftKey) != 0 {
                converted.insert(.shift)
            }

            return Shortcut(
                keyCode: UInt16(keyCode),
                modifiers: converted
            )
        }

        return Shortcut(
            keyCode: UInt16(keyCode),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        )
    }
}

import AppKit
import SwiftUI

@main
struct EloquentHotkeyApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(model: model)
        } label: {
            MenuBarLabelView(
                isArming: model.isArming,
                isListening: model.isListening,
                isCleaningUp: model.isCleaningUp
            )
        }

        Window("Settings", id: AppSceneID.settings) {
            SettingsView(model: model)
                .frame(width: 520)
                .padding(20)
        }
    }
}

private enum AppSceneID {
    static let settings = "settings"
}

private enum AppArtwork {
    private static let menuBarIconSize = NSSize(width: 18, height: 18)

    private static let baseMenuBarTemplateImage: NSImage = {
        if let url = Bundle.main.url(forResource: "MenuBarPastaTemplate", withExtension: "png"),
           let image = NSImage(contentsOf: url),
           let resized = resizeTemplateImage(image, to: menuBarIconSize) {
            return resized
        }

        let fallback = NSImage(
            systemSymbolName: "waveform.circle",
            accessibilityDescription: "EloquentHotkey"
        ) ?? NSImage()
        fallback.size = menuBarIconSize
        fallback.isTemplate = true
        return fallback
    }()

    static func menuBarTemplateImage(isListening: Bool, isCleaningUp: Bool) -> NSImage {
        guard isListening || isCleaningUp else {
            return baseMenuBarTemplateImage
        }

        let image = NSImage(size: menuBarIconSize)
        image.lockFocus()
        baseMenuBarTemplateImage.draw(
            in: NSRect(origin: .zero, size: menuBarIconSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        if isListening {
            let dotRect = NSRect(x: 13, y: 13, width: 4, height: 4)
            NSColor.labelColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        } else if isCleaningUp,
                  let badge = badgeSymbolImage(name: "sparkles", pointSize: 8) {
            badge.draw(
                in: NSRect(x: 10, y: 10, width: 7, height: 7),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func resizeTemplateImage(_ image: NSImage, to size: NSSize) -> NSImage? {
        let resized = NSImage(size: size)
        resized.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        resized.unlockFocus()
        resized.isTemplate = true
        return resized
    }

    private static func badgeSymbolImage(name: String, pointSize: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .semibold
        )
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "EloquentHotkey status")
        image?.isTemplate = true
        return image?.withSymbolConfiguration(configuration)
    }
}

private struct MenuBarLabelView: View {
    let isArming: Bool
    let isListening: Bool
    let isCleaningUp: Bool

    var body: some View {
        Image(
            nsImage: AppArtwork.menuBarTemplateImage(
                isListening: isArming || isListening,
                isCleaningUp: isCleaningUp
            )
        )
            .renderingMode(.template)
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if isArming {
            return "EloquentHotkey preparing microphone"
        }

        if isListening {
            return "EloquentHotkey listening"
        }

        if isCleaningUp {
            return "EloquentHotkey cleaning transcript"
        }

        return "EloquentHotkey"
    }
}

private struct StatusMenuView: View {
    @ObservedObject var model: AppModel

    private static let transcriptPreviewWidth: CGFloat = 240
    private static let transcriptPreviewMaxLines = 5
    private static let transcriptPreviewMaxCharactersPerLine = 24

    var body: some View {
        Button(primaryActionTitle) {
            model.toggleDictation()
        }
        .disabled(model.isCleaningUp)

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
            VStack(alignment: .leading, spacing: 4) {
                Text("Last Transcript")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(wrappedTranscriptPreview)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .lineLimit(Self.transcriptPreviewMaxLines)
                    .truncationMode(.tail)
                    .frame(width: Self.transcriptPreviewWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Divider()

        if model.isCleaningUp {
            Label("Cleaning transcript…", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if model.isArming {
            Label("Preparing microphone…", systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Text(model.statusMessage)
            .font(.caption)
            .foregroundStyle(.secondary)

        Divider()

        SettingsMenuItem()

        Button("Quit") {
            NSApp.terminate(nil)
        }
    }

    private var primaryActionTitle: String {
        if model.isCleaningUp {
            return "Cleaning Transcript…"
        }

        return model.isArming || model.isListening ? "Stop Dictation" : "Start Dictation"
    }

    private var wrappedTranscriptPreview: String {
        Self.wrapPreview(
            model.lastText,
            maxCharactersPerLine: Self.transcriptPreviewMaxCharactersPerLine,
            maxLines: Self.transcriptPreviewMaxLines
        )
    }

    private static func wrapPreview(
        _ text: String,
        maxCharactersPerLine: Int,
        maxLines: Int
    ) -> String {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else {
            return text
        }

        var lines: [String] = []
        var currentLine = ""
        var wordIndex = 0

        while wordIndex < words.count {
            let word = String(words[wordIndex])
            let candidate = currentLine.isEmpty ? word : currentLine + " " + word

            if candidate.count <= maxCharactersPerLine || currentLine.isEmpty {
                currentLine = candidate
                wordIndex += 1
                continue
            }

            lines.append(currentLine)
            currentLine = ""

            if lines.count == maxLines {
                break
            }
        }

        if !currentLine.isEmpty && lines.count < maxLines {
            lines.append(currentLine)
        }

        let truncated = wordIndex < words.count
        if truncated, var lastLine = lines.popLast() {
            let trimmedLimit = max(1, maxCharactersPerLine - 1)
            if lastLine.count > trimmedLimit {
                lastLine = String(lastLine.prefix(trimmedLimit))
            }
            lines.append(lastLine.trimmingCharacters(in: .whitespacesAndNewlines) + "…")
        }

        return lines.joined(separator: "\n")
    }
}

private struct SettingsMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: AppSceneID.settings)
        }
    }
}

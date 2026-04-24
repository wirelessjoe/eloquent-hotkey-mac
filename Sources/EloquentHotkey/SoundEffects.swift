import AVFoundation
import Foundation
import OSLog

enum SoundEffect {
    private enum PlaybackStyle {
        case trimmed(maxDuration: TimeInterval, fadeOutDuration: TimeInterval)
        case full
    }

    private static let playbackFraction = 0.55
    private static let startMaxDuration: TimeInterval = 0.28
    private static let finishMaxDuration: TimeInterval = 0.42
    private static let fadeOutDuration: TimeInterval = 0.10

    private static let startSoundURL = loadSoundURL(named: "Glass")
    private static let finishSoundURL = loadSoundURL(named: "Hero")
    private static let logger = Logger(subsystem: "dev.codex.EloquentHotkey", category: "SoundEffect")

    @MainActor private static var startPlaybackToken = 0
    @MainActor private static var finishPlaybackToken = 0
    @MainActor private static var startPlayer: AVAudioPlayer?
    @MainActor private static var finishPlayer: AVAudioPlayer?

    @MainActor
    static func playStartRecording() {
        startPlaybackToken += 1
        play(
            name: "start",
            url: startSoundURL,
            playbackStyle: .trimmed(maxDuration: startMaxDuration, fadeOutDuration: fadeOutDuration),
            token: startPlaybackToken,
            setPlayer: { startPlayer = $0 },
            currentToken: { startPlaybackToken }
        )
    }

    @MainActor
    static func playFinishRecording() {
        finishPlaybackToken += 1
        play(
            name: "finish",
            url: finishSoundURL,
            playbackStyle: .trimmed(maxDuration: finishMaxDuration, fadeOutDuration: fadeOutDuration),
            token: finishPlaybackToken,
            setPlayer: { finishPlayer = $0 },
            currentToken: { finishPlaybackToken }
        )
    }

    @MainActor
    private static func play(
        name: String,
        url: URL?,
        playbackStyle: PlaybackStyle,
        token: Int,
        setPlayer: @escaping @MainActor (AVAudioPlayer?) -> Void,
        currentToken: @escaping @MainActor () -> Int
    ) {
        guard let url else {
            logger.error("Could not play \(name, privacy: .public) sound because no sound file was found")
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = name == "finish" ? 0.95 : 0.7
            player.prepareToPlay()

            setPlayer(player)
            player.play()
            logger.notice("Playing \(name, privacy: .public) sound from \(url.lastPathComponent, privacy: .public)")

            let stopDelay: TimeInterval
            let fadeOutDuration: TimeInterval
            switch playbackStyle {
            case .trimmed(let maxDuration, let duration):
                stopDelay = max(0.08, min(maxDuration, player.duration * playbackFraction))
                fadeOutDuration = min(duration, max(stopDelay / 2, 0.02))
            case .full:
                stopDelay = player.duration + 0.05
                fadeOutDuration = 0
            }

            if fadeOutDuration > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0, stopDelay - fadeOutDuration)) {
                    guard currentToken() == token else {
                        return
                    }

                    player.setVolume(0, fadeDuration: fadeOutDuration)
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + stopDelay) {
                guard currentToken() == token else {
                    return
                }

                if case .trimmed = playbackStyle {
                    player.stop()
                }
                setPlayer(nil)
            }
        } catch {
            logger.error("Could not play \(name, privacy: .public) sound: \(error.localizedDescription, privacy: .public)")
            setPlayer(nil)
        }
    }

    private static func loadSoundURL(named name: String) -> URL? {
        let bundledExtensions = ["aiff", "wav", "mp3", "m4a"]
        for fileExtension in bundledExtensions {
            if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
                return url
            }
        }

        let systemURL = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        return FileManager.default.fileExists(atPath: systemURL.path) ? systemURL : nil
    }
}

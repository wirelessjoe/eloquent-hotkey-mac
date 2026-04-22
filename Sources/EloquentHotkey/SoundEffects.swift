import AVFoundation
import Foundation

enum SoundEffect {
    private enum PlaybackStyle {
        case trimmed(maxDuration: TimeInterval)
        case full
    }

    private static let playbackFraction = 0.55
    private static let startMaxDuration: TimeInterval = 0.28

    private static let startSoundURL = loadSoundURL(named: "Glass")
    private static let finishSoundURL = loadSoundURL(named: "Tink")

    @MainActor private static var startPlaybackToken = 0
    @MainActor private static var finishPlaybackToken = 0
    @MainActor private static var startPlayer: AVAudioPlayer?
    @MainActor private static var finishPlayer: AVAudioPlayer?

    @MainActor
    static func playStartRecording() {
        startPlaybackToken += 1
        play(
            url: startSoundURL,
            playbackStyle: .trimmed(maxDuration: startMaxDuration),
            token: startPlaybackToken,
            setPlayer: { startPlayer = $0 },
            currentToken: { startPlaybackToken }
        )
    }

    @MainActor
    static func playFinishRecording() {
        finishPlaybackToken += 1
        play(
            url: finishSoundURL,
            playbackStyle: .full,
            token: finishPlaybackToken,
            setPlayer: { finishPlayer = $0 },
            currentToken: { finishPlaybackToken }
        )
    }

    @MainActor
    private static func play(
        url: URL?,
        playbackStyle: PlaybackStyle,
        token: Int,
        setPlayer: @escaping @MainActor (AVAudioPlayer?) -> Void,
        currentToken: @escaping @MainActor () -> Int
    ) {
        guard let url else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.7
            player.prepareToPlay()

            setPlayer(player)
            player.play()

            let stopDelay: TimeInterval
            switch playbackStyle {
            case .trimmed(let maxDuration):
                stopDelay = max(0.08, min(maxDuration, player.duration * playbackFraction))
            case .full:
                stopDelay = player.duration + 0.05
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

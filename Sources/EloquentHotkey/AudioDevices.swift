import AVFoundation
import Foundation

struct MicrophoneOption: Identifiable, Equatable {
    let id: String
    let name: String
}

enum AudioDeviceManager {
    static let systemDefaultID = "system-default"

    private static var discoveredAudioDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    static func availableMicrophones() -> [MicrophoneOption] {
        var options = [
            MicrophoneOption(
                id: systemDefaultID,
                name: "System Default"
            )
        ]

        let devices = discoveredAudioDevices
            .sorted { $0.localizedName.localizedCaseInsensitiveCompare($1.localizedName) == .orderedAscending }

        var seen = Set<String>()
        for device in devices where seen.insert(device.uniqueID).inserted {
            options.append(
                MicrophoneOption(
                    id: device.uniqueID,
                    name: device.localizedName
                )
            )
        }

        return options
    }

    static func device(for microphoneID: String?) -> AVCaptureDevice? {
        guard let microphoneID else {
            return AVCaptureDevice.default(for: .audio) ?? discoveredAudioDevices.first
        }

        return discoveredAudioDevices.first(where: { $0.uniqueID == microphoneID })
            ?? AVCaptureDevice.default(for: .audio)
            ?? discoveredAudioDevices.first
    }
}

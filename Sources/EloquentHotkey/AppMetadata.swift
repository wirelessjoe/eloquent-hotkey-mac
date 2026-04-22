import Foundation

enum AppMetadata {
    private static let fallbackVersion = "0.1.2"
    private static let fallbackBuild = "2"

    static let authorHandle = "@wirelessjoe"
    static let authorURL = URL(string: "https://twitter.com/wirelessjoe")!

    static var versionString: String {
        let bundle = Bundle.main
        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? fallbackVersion
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? fallbackBuild

        if buildNumber.isEmpty || buildNumber == shortVersion {
            return shortVersion
        }

        return "\(shortVersion) (\(buildNumber))"
    }
}

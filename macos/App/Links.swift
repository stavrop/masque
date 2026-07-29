import Foundation

/// External links used by the About/Welcome screen and menu.
enum Links {
    static let github = URL(string: "https://github.com/stavrop/masque")!
    static let githubStar = URL(string: "https://github.com/stavrop/masque")!
    // TODO: confirm the real Buy Me a Coffee handle.
    static let buyMeACoffee = URL(string: "https://www.buymeacoffee.com/stavrop")!
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

import Foundation

/// External links used by the About/Welcome screen and menu.
enum Links {
    static let github = URL(string: "https://github.com/stavrop/masque")!
    static let githubStar = URL(string: "https://github.com/stavrop/masque")!
    static let buyMeACoffee = URL(string: "https://www.buymeacoffee.com/stavrop")!
    static let privacy = URL(string: "https://stavrop.github.io/masque/privacy.html")!
    static let terms = URL(string: "https://stavrop.github.io/masque/terms.html")!
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

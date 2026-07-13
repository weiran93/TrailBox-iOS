import Foundation

enum AppConfiguration {
    static let privacyPolicyURL = URL(string: "https://weiran93.github.io/trailbox-privacy/privacy.html")!
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/%E5%B0%8F%E9%87%8Ebox-%E7%B2%BE%E9%80%89%E8%B6%8A%E9%87%8E%E8%B7%91%E8%B7%AF%E7%BA%BF-ai%E8%BF%90%E5%8A%A8%E5%88%86%E6%9E%90/id6783572832")!
    static let supportEmail = "zhaowr93@foxmail.com"
    /// A LAN or HTTPS API endpoint can be supplied from Xcode's launch arguments:
    /// `-trailboxAPIBaseURL http://192.168.1.10:8000`.
    static var apiBaseURL: URL {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-trailboxAPIBaseURL"), arguments.indices.contains(index + 1),
           let url = URL(string: arguments[index + 1]) {
            return url
        }
        return URL(string: "https://runfast.fun")!
    }
}

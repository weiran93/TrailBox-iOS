import Foundation

enum AppConfiguration {
    /// A LAN or HTTPS API endpoint can be supplied from Xcode's launch arguments:
    /// `-trailboxAPIBaseURL http://192.168.1.10:8000`.
    static var apiBaseURL: URL {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-trailboxAPIBaseURL"), arguments.indices.contains(index + 1),
           let url = URL(string: arguments[index + 1]) {
            return url
        }
        // Physical iPhones cannot reach a development server through 127.0.0.1:
        // that address refers to the phone itself. Use the deployed API by default;
        // Xcode launch arguments can still override this for LAN/local development.
        return URL(string: "https://runfast.fun")!
    }
}

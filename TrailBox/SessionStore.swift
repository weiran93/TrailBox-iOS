import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var token: String?
    @Published var authenticationError: String?
    @Published var shouldPresentAuthentication = false

    init() {
        token = KeychainStore.readToken()
        if let data = UserDefaults.standard.data(forKey: "trailbox.current-user"), let user = try? JSONDecoder().decode(User.self, from: data) {
            self.user = user
        }
    }

    var isAuthenticated: Bool { token != nil && user != nil }

    func login(username: String, password: String) async throws {
        struct LoginRequest: Encodable { let username: String; let password: String }
        let response: TokenResponse = try await APIClient.shared.request("/auth/login", method: "POST", body: LoginRequest(username: username, password: password))
        persist(response)
    }

    func register(username: String, password: String, nickname: String?) async throws {
        struct RegisterRequest: Encodable { let username: String; let password: String; let nickname: String? }
        let response: TokenResponse = try await APIClient.shared.request("/auth/register", method: "POST", body: RegisterRequest(username: username, password: password, nickname: nickname))
        persist(response)
    }

    func logout() {
        token = nil
        user = nil
        authenticationError = nil
        KeychainStore.deleteToken()
        UserDefaults.standard.removeObject(forKey: "trailbox.current-user")
    }

    func requireAuthentication() {
        shouldPresentAuthentication = true
    }

    func deleteAccount() async throws {
        guard let token else { return }
        try await APIClient.shared.requestVoid("/users/me", method: "DELETE", token: token)
        logout()
    }

    func handle(_ error: Error) {
        if case APIError.unauthorized = error {
            authenticationError = error.localizedDescription
            logout()
        }
    }

    func update(user: User) {
        self.user = user
        UserDefaults.standard.set(try? JSONEncoder().encode(user), forKey: "trailbox.current-user")
    }

    private func persist(_ response: TokenResponse) {
        token = response.accessToken
        user = response.user
        KeychainStore.save(token: response.accessToken)
        UserDefaults.standard.set(try? JSONEncoder().encode(response.user), forKey: "trailbox.current-user")
    }
}

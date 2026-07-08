import Foundation
import Auth0

/// Holds the bearer token used on every API request. Updated by AuthManager
/// after login/renewal; read synchronously by APIClient's tokenProvider.
final class TokenStore: @unchecked Sendable {
    static let shared = TokenStore()
    private let lock = NSLock()
    private var _bearer: String?
    var bearer: String? {
        get { lock.lock(); defer { lock.unlock() }; return _bearer }
        set { lock.lock(); _bearer = newValue; lock.unlock() }
    }
    private init() {}
}

/// Authentication via Auth0 Universal Login (Auth0.swift). The tenant is
/// configured in Auth0.plist and must match the backend's AUTH0_DOMAIN so the
/// issued id token validates. Sign in with Apple is offered as an Auth0
/// connection, satisfying both Auth0 and Apple's requirement in one flow.
@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isWorking = false
    @Published var errorMessage: String?

    private let credentialsManager = CredentialsManager(authentication: Auth0.authentication())

    init() {
        Task { await restore() }
    }

    /// True once real values (not the YOUR_… placeholders) are in Auth0.plist.
    static var isConfigured: Bool {
        guard let url = Bundle.main.url(forResource: "Auth0", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url),
              let clientId = dict["ClientId"] as? String else { return false }
        return !clientId.hasPrefix("YOUR_")
    }

    /// Restore a stored session on launch (silently renewing if needed).
    func restore() async {
        guard Self.isConfigured, credentialsManager.hasValid() || credentialsManager.canRenew() else { return }
        do {
            let creds = try await credentialsManager.credentials()
            TokenStore.shared.bearer = creds.idToken
            isAuthenticated = true
        } catch {
            // Not signed in / renewal failed — remain on the login screen.
        }
    }

    /// Launch Universal Login straight into the Apple connection.
    func loginWithApple() async { await login(connection: "apple") }

    func login(connection: String? = nil) async {
        guard Self.isConfigured else {
            errorMessage = "Sign-in isn't configured yet."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            var webAuth = Auth0.webAuth().scope("openid profile email offline_access")
            if let connection { webAuth = webAuth.connection(connection) }
            let creds = try await webAuth.start()
            _ = credentialsManager.store(credentials: creds)
            TokenStore.shared.bearer = creds.idToken
            errorMessage = nil
            isAuthenticated = true
        } catch {
            errorMessage = "Sign-in didn't complete. Please try again."
        }
    }

    func signOut() {
        Task {
            if Self.isConfigured { _ = try? await Auth0.webAuth().clearSession() }
            _ = credentialsManager.clear()
            TokenStore.shared.bearer = nil
            isAuthenticated = false
        }
    }

    #if DEBUG
    /// Local-only shortcut: enter without Auth0 (pairs with the backend's DEV_AUTH_BYPASS).
    func devEnter() { isAuthenticated = true }
    #endif
}

import Foundation
import AuthenticationServices

/// Authentication state. Production uses Sign in with Apple (App Store requires
/// it alongside any third-party login) plus the Auth0-backed API. In local dev
/// the backend runs with DEV_AUTH_BYPASS, so `devEnter()` lets us proceed
/// without a signed Apple entitlement.
@MainActor
final class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var displayName: String?

    private let userKey = "goalcraft.apple.userID"

    init() {
        // Restore a prior Apple sign-in if present.
        if UserDefaults.standard.string(forKey: userKey) != nil {
            isAuthenticated = true
        }
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            if let cred = auth.credential as? ASAuthorizationAppleIDCredential {
                UserDefaults.standard.set(cred.user, forKey: userKey)
                if let name = cred.fullName, let given = name.givenName {
                    displayName = given
                }
                // TODO: exchange cred.identityToken with the backend for an
                // Auth0 session once the Apple capability is provisioned.
            }
            isAuthenticated = true
        case .failure:
            break
        }
    }

    func devEnter() { isAuthenticated = true }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: userKey)
        isAuthenticated = false
    }
}

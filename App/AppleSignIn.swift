import AuthenticationServices
import CryptoKit
import Foundation
import Security
import FirebaseAuth
import KharchaKit

/// Sign in with Apple, structured so Firebase Auth can plug in later without
/// touching the UI. On success we persist the stable Apple user id in the
/// Keychain and keep the raw nonce that Firebase's `OAuthProvider.appleCredential`
/// requires. The Firebase calls are marked TODO — enable them once the SDK and
/// `GoogleService-Info.plist` are added.
@MainActor
final class SignInManager: ObservableObject {
    @Published private(set) var userID: String? = KeychainStore.appleUserID
    /// The Firebase Auth UID once the Apple credential has been exchanged.
    /// Observers (e.g. sync) key off changes to this.
    @Published private(set) var firebaseUID: String? = Auth.auth().currentUser?.uid
    /// True when the Apple credential succeeded but the Firebase exchange failed.
    /// Cleared on sign-out. Use to surface a "backup unavailable" warning.
    @Published private(set) var firebaseAuthFailed = false
    /// Display name / email captured at first Apple sign-in (Apple only provides
    /// them once) and persisted, falling back to the Firebase user.
    @Published private(set) var displayName: String? = SignInManager.storedName ?? Auth.auth().currentUser?.displayName
    @Published private(set) var email: String? = SignInManager.storedEmail ?? Auth.auth().currentUser?.email
    var isSignedIn: Bool { userID != nil }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: KharchaContainerFactory.appGroupID) ?? .standard
    }
    private static var storedName: String? { defaults.string(forKey: "profile.name") }
    private static var storedEmail: String? { defaults.string(forKey: "profile.email") }

    /// Raw (un-hashed) nonce for the in-flight request; Firebase needs this.
    private(set) var currentNonce: String?

    /// Configure an Apple ID request: request name/email and attach a hashed
    /// nonce. Returns nothing; call from `SignInWithAppleButton`'s onRequest.
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            KeychainStore.appleUserID = credential.user
            userID = credential.user

            // Apple provides name/email only on the first authorization — capture + persist.
            if let comps = credential.fullName {
                let name = PersonNameComponentsFormatter().string(from: comps).trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    Self.defaults.set(name, forKey: "profile.name")
                    displayName = name
                }
            }
            if let email = credential.email {
                Self.defaults.set(email, forKey: "profile.email")
                self.email = email
            }

            // Exchange the Apple identity token for a Firebase account.
            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else { return }
            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: credential.fullName
            )
            Task {
                do {
                    let result = try await Auth.auth().signIn(with: firebaseCredential)
                    self.firebaseUID = result.user.uid
                    if self.displayName == nil { self.displayName = result.user.displayName }
                    if self.email == nil { self.email = result.user.email }
                } catch {
                    // Firebase exchange failed — the local Apple sign-in still holds.
                    self.firebaseAuthFailed = true
                }
            }
        case .failure:
            break // user cancelled or errored — leave state unchanged
        }
    }

    func signOut() {
        KeychainStore.appleUserID = nil
        userID = nil
        firebaseUID = nil
        firebaseAuthFailed = false
        displayName = nil
        email = nil
        Self.defaults.removeObject(forKey: "profile.name")
        Self.defaults.removeObject(forKey: "profile.email")
        try? Auth.auth().signOut()
    }

    /// Verify the Apple credential is still valid (call on launch); signs the
    /// user out locally if Apple reports it was revoked.
    func refreshCredentialState() {
        guard let userID else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: userID) { [weak self] state, _ in
            guard state == .revoked || state == .notFound else { return }
            Task { @MainActor in self?.signOut() }
        }
    }

    // MARK: - Nonce (Apple/Firebase standard implementation)

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            guard SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms) == errSecSuccess else {
                continue
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Minimal Keychain-backed string store for the Apple user id (survives app
/// reinstalls-per-keychain and is more appropriate than UserDefaults for an
/// account identifier).
enum KeychainStore {
    private static let service = "com.manish.jebkharcha.auth"
    private static let account = "apple.user.id"

    static var appleUserID: String? {
        get { read() }
        set { newValue.map(save) ?? delete() }
    }

    private static func save(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

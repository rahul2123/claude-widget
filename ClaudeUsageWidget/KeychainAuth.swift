import Foundation
import Security

/// Read-only access to the OAuth token Claude Code stores in the macOS Keychain.
///
/// The Claude Code background daemon proactively refreshes this token (~every 8h)
/// and writes it back to the Keychain, so this widget never refreshes or writes —
/// it only reads. See the design spec for rationale.
enum KeychainAuth {

    static let service = "Claude Code-credentials"

    struct Credentials {
        let accessToken: String
        let expiresAt: Date?      // from expiresAt (epoch ms)
        let subscriptionType: String?
    }

    enum AuthError: Error, LocalizedError {
        case notFound        // no keychain item — user never logged into Claude Code
        case accessDenied    // keychain ACL denied access
        case malformed       // item present but JSON unexpected

        var errorDescription: String? {
            switch self {
            case .notFound:     return "Not logged in — run Claude Code first"
            case .accessDenied: return "Keychain access denied — click Allow"
            case .malformed:    return "Could not read Claude credentials"
            }
        }
    }

    /// Reads and decodes the current credentials. Does not mutate the Keychain.
    static func loadCredentials() -> Result<Credentials, AuthError> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return .failure(.notFound)
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecUserCanceled:
            return .failure(.accessDenied)
        default:
            return .failure(.accessDenied)
        }

        guard let data = item as? Data,
              let creds = decode(data) else {
            return .failure(.malformed)
        }
        return .success(creds)
    }

    private static func decode(_ data: Data) -> Credentials? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let accessToken = oauth["accessToken"] as? String,
            !accessToken.isEmpty
        else { return nil }

        // expiresAt is epoch milliseconds (Int or Double).
        var expiresAt: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let ms = oauth["expiresAt"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        }

        let subscription = oauth["subscriptionType"] as? String

        return Credentials(
            accessToken: accessToken,
            expiresAt: expiresAt,
            subscriptionType: subscription
        )
    }
}

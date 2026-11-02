import Foundation
import Security

/// Where the Canvas personal access token lives: the Keychain, and nowhere
/// else.
///
/// Not UserDefaults, not kalla.json, not a constant in the source. This
/// repository is public, and a Canvas token is a bearer credential for a real
/// account — anyone holding it can read and write as the owner. It is also
/// deliberately left out of the backup export for the same reason.
nonisolated enum CanvasToken {
    private static let service = "tally.canvas.token"
    private static let account = "personal-access-token"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static var isSaved: Bool { current != nil }

    static var current: String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }

        return token
    }

    /// Replaces whatever is there. Available only after the first unlock, so
    /// a background refresh can still read it, but never off the device.
    @discardableResult
    static func save(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        remove()

        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func remove() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Enough of the token to recognise which one is saved, without putting
    /// the thing itself on screen where it could be shoulder-read.
    static var fingerprint: String? {
        guard let token = current else { return nil }
        let tail = String(token.suffix(4))
        return "•••• \(tail)"
    }
}

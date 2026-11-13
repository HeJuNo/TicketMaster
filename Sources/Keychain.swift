import Foundation
import Security

/// The session cookies live in the keychain, only on this device. The password is never stored.
enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "TicketMaster.session",
         kSecAttrAccount as String: account]
    }

    static func save(_ data: Data, account: String) {
        delete(account: account)
        var item = query(account)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(account: String) -> Data? {
        var item = query(account)
        item[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

/// Keychain form of a session cookie.
struct StoredCookie: Codable, Equatable {
    var name, value, domain, path: String
    var expires: Date?
    var secure: Bool

    init(_ cookie: HTTPCookie) {
        (name, value, domain, path, expires, secure) = (cookie.name, cookie.value, cookie.domain, cookie.path, cookie.expiresDate, cookie.isSecure)
    }

    var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: path]
        if let expires { properties[.expires] = expires }
        if secure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)
    }
}

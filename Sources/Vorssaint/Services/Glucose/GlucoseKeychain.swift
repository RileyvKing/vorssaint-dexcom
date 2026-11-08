// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Security

/// The Dexcom account's secrets. They live in the login Keychain, not in
/// UserDefaults, backups or logs. The app is not sandboxed, so a generic
/// password needs no entitlement; the stable local signing identity keeps
/// macOS from asking for access again after a rebuild.
enum GlucoseKeychain {
    private static let service = "com.vorssaint.utils.glucose"

    enum Account: String {
        case username
        case password
    }

    static func string(_ account: Account) -> String? {
        guard let data = data(account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func set(_ value: String, for account: Account) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        let dataAttributes: [String: Any] = [kSecValueData as String: data]
        let updated = SecItemUpdate(query as CFDictionary, dataAttributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        var added = query
        added[kSecValueData as String] = data
        added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        added[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
        return SecItemAdd(added as CFDictionary, nil) == errSecSuccess
    }

    static func remove(_ account: Account) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func clear() {
        remove(.username)
        remove(.password)
    }

    private static func data(_ account: Account) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}

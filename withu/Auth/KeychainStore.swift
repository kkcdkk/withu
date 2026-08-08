//
//  KeychainStore.swift
//  withu (iOS)
//
//  세션 토큰 / Apple user id 를 Keychain 에 안전 보관.
//  kSecAttrAccessibleAfterFirstUnlock — 백그라운드(위젯 refresh 등)에서도 읽힘.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "com.seoyoung.withu.auth"
    private static let tokenAccount = "sessionToken"
    private static let userAccount = "appleUserId"

    // MARK: 공개 API

    static func saveSessionToken(_ token: String) { save(token, account: tokenAccount) }
    static func sessionToken() -> String? { read(account: tokenAccount) }

    static func saveAppleUserId(_ id: String) { save(id, account: userAccount) }
    static func appleUserId() -> String? { read(account: userAccount) }

    /// 로그아웃 — 토큰/식별자 모두 삭제.
    static func clear() {
        delete(account: tokenAccount)
        delete(account: userAccount)
    }

    // MARK: 내부

    private static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

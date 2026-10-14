import Foundation
import Security

/// Acceso al Llavero detrás de un protocolo para poder falsearlo en tests.
protocol KeychainStoring: AnyObject {
    func read(account: String) -> String?
    @discardableResult
    func save(_ value: String, account: String) -> Bool
    @discardableResult
    func delete(account: String) -> Bool
}

/// Contraseñas genéricas del Llavero del usuario bajo un mismo servicio.
final class KeychainStore: KeychainStoring {
    static let defaultService = "com.joandev.notchwatch"

    private let service: String

    init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        return value?.isEmpty == false ? value : nil
    }

    @discardableResult
    func save(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let base = baseQuery(account: account)
        let attributes: [String: Any] = [kSecValueData as String: data]

        var status = SecItemUpdate(base as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = base
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    @discardableResult
    func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

import Foundation
import Security

struct SecurityBrowserSafeStorage: BrowserSafeStorageSecretProviding {
    func secret(for application: BrowserImportApplication) throws -> String {
        let service: String
        switch application {
        case .arc:
            service = "Arc Safe Storage"
        case .chrome:
            service = "Chrome Safe Storage"
        case .zen, .safari, .firefox:
            throw BrowserPasswordImportError.unsupportedBrowser
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let secret = String(data: data, encoding: .utf8),
            !secret.isEmpty
        else {
            throw BrowserPasswordImportError.safeStorageUnavailable
        }
        return secret
    }
}

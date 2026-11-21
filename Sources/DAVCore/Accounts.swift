import Foundation
import Security

/// The app group shared by the app and its File Provider extension.
public enum AppGroup {
    static let defaultIdentifier = "group.io.github.crazyquark.davdrive"

    /// SideStore and AltStore rename app groups for the signing team and list
    /// the new names under ALTAppGroups in Info.plist, so prefer those.
    public static let identifier: String = {
        let listed = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] ?? []
        return listed.first { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil }
            ?? defaultIdentifier
    }()

    public static var defaults: UserDefaults { UserDefaults(suiteName: identifier) ?? .standard }
}

/// A WebDAV server the user added. The password lives in the Keychain.
public struct Account: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var urlString: String
    public var username: String
    public var allowsUntrustedCertificates: Bool

    public init(id: String = UUID().uuidString, name: String, urlString: String, username: String,
                allowsUntrustedCertificates: Bool = false) {
        self.id = id
        self.name = name
        self.urlString = urlString
        self.username = username
        self.allowsUntrustedCertificates = allowsUntrustedCertificates
    }

    public var url: URL? {
        var string = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !string.contains("://") { string = "https://" + string }
        guard let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host() != nil else { return nil }
        return url
    }
}

/// Accounts as JSON in the app group's defaults, readable by the extension.
public enum AccountStore {
    private static let key = "accounts"

    public static func load() -> [Account] {
        guard let data = AppGroup.defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Account].self, from: data)) ?? []
    }

    public static func save(_ accounts: [Account]) {
        AppGroup.defaults.set(try? JSONEncoder().encode(accounts), forKey: key)
    }

    public static func account(id: String) -> Account? { load().first { $0.id == id } }

    public static func client(forAccountID id: String) throws -> WebDAVClient {
        guard let account = account(id: id) else { throw DAVError.invalidURL }
        return try WebDAVClient(account: account, password: Keychain.password(for: id) ?? "")
    }
}

/// Passwords in a Keychain access group both targets share (the app group).
public enum Keychain {
    private static let service = "io.github.crazyquark.davdrive.account"

    private static func query(_ id: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecAttrAccessGroup as String: AppGroup.identifier,
        ]
    }

    public static func password(for id: String) -> String? {
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func setPassword(_ password: String, for id: String) -> OSStatus {
        SecItemDelete(query(id) as CFDictionary)
        var item = query(id)
        item[kSecValueData as String] = Data(password.utf8)
        // The extension may run while the device is locked (after first unlock).
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(item as CFDictionary, nil)
    }

    public static func deletePassword(for id: String) {
        SecItemDelete(query(id) as CFDictionary)
    }
}

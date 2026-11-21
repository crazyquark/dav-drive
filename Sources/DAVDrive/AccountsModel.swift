import DAVCore
import FileProvider
import SwiftUI

/// The accounts, each registered with the system as a File Provider domain
/// so it shows up under Locations in the Files app.
@MainActor @Observable
final class AccountsModel {
    private(set) var accounts: [Account] = AccountStore.load()
    var lastError: String?

    func save(_ account: Account, password: String) async {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        AccountStore.save(accounts)
        let status = Keychain.setPassword(password, for: account.id)
        if status != errSecSuccess {
            lastError = "Couldn't store the password in the Keychain (error \(status))."
        }
        await register(account)
        if let manager = NSFileProviderManager(for: domain(for: account)) {
            // Clears a "sign in" error in Files and lists everything again.
            try? await manager.signalErrorResolved(NSFileProviderError(.notAuthenticated))
            try? await manager.signalEnumerator(for: .workingSet)
            try? await manager.reimportItems(below: .rootContainer)
        }
    }

    func delete(_ account: Account) async {
        accounts.removeAll { $0.id == account.id }
        AccountStore.save(accounts)
        Keychain.deletePassword(for: account.id)
        do {
            try await NSFileProviderManager.remove(domain(for: account))
        } catch {
            lastError = "Couldn't remove \(account.name) from Files: \(error.localizedDescription)"
        }
    }

    /// Makes the registered domains match the accounts.
    func syncDomains() async {
        let registered = (try? await NSFileProviderManager.domains()) ?? []
        let ids = Set(accounts.map(\.id))
        for domain in registered where !ids.contains(domain.identifier.rawValue) {
            try? await NSFileProviderManager.remove(domain)
        }
        for account in accounts where !registered.contains(where: {
            $0.identifier.rawValue == account.id && $0.displayName == account.name
        }) {
            await register(account)
        }
    }

    /// Opens the account's folder in the Files app.
    func openInFiles(_ account: Account) async {
        do {
            guard let manager = NSFileProviderManager(for: domain(for: account)) else { return }
            let url = try await manager.getUserVisibleURL(for: .rootContainer)
            var components = URLComponents()
            components.scheme = "shareddocuments"
            components.path = url.path(percentEncoded: false)
            if let filesURL = components.url { await UIApplication.shared.open(filesURL) }
        } catch {
            lastError = "Couldn't open Files: \(error.localizedDescription)"
        }
    }

    private func register(_ account: Account) async {
        do {
            // Adding an existing identifier updates its display name.
            try await NSFileProviderManager.add(domain(for: account))
        } catch {
            lastError = "Couldn't add \(account.name) to Files: \(error.localizedDescription)"
        }
    }

    private func domain(for account: Account) -> NSFileProviderDomain {
        NSFileProviderDomain(identifier: NSFileProviderDomainIdentifier(account.id), displayName: account.name)
    }
}

import DAVCore
import SwiftUI

struct AccountEditor: View {
    let original: Account?

    @Environment(AccountsModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var urlString: String
    @State private var username: String
    @State private var password: String
    @State private var allowsUntrustedCertificates: Bool

    @State private var test: TestState = .idle
    @State private var confirmSaveAnyway = false

    enum TestState: Equatable {
        case idle, running, ok(Int), failed(String)
    }

    init(account: Account?) {
        original = account
        _name = State(initialValue: account?.name ?? "")
        _urlString = State(initialValue: account?.urlString ?? "")
        _username = State(initialValue: account?.username ?? "")
        _password = State(initialValue: account.flatMap { Keychain.password(for: $0.id) } ?? "")
        _allowsUntrustedCertificates = State(initialValue: account?.allowsUntrustedCertificates ?? false)
    }

    private var draft: Account {
        Account(
            id: original?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespaces).isEmpty ? (draftHost ?? "WebDAV") : name.trimmingCharacters(in: .whitespaces),
            urlString: urlString.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username,
            allowsUntrustedCertificates: allowsUntrustedCertificates
        )
    }

    private var draftHost: String? {
        Account(name: "", urlString: urlString, username: "").url?.host()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Address", text: $urlString, prompt: Text("https://server.example/dav/"))
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Name", text: $name, prompt: Text(draftHost ?? "Shown in Files"))
                } header: {
                    Text("Server")
                } footer: {
                    Text("The WebDAV address, including the folder to show. Without http:// or https://, https is used.")
                }

                Section("Sign In") {
                    TextField("User Name", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                Section {
                    Toggle("Allow Untrusted Certificate", isOn: $allowsUntrustedCertificates)
                } footer: {
                    Text("Only for servers you own that use a self-signed certificate. Anyone on the network could pretend to be such a server.")
                }

                Section {
                    Button {
                        Task { await runTest() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            testStatus
                        }
                    }
                    .disabled(draft.url == nil || test == .running)
                    if case .failed(let message) = test {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(original == nil ? "Add Server" : "Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await saveTapped() } }
                        .disabled(draft.url == nil || test == .running)
                }
            }
            .confirmationDialog("The connection test failed.", isPresented: $confirmSaveAnyway, titleVisibility: .visible) {
                Button("Save Anyway") { Task { await save() } }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(test == .running)
    }

    @ViewBuilder private var testStatus: some View {
        switch test {
        case .idle: EmptyView()
        case .running: ProgressView()
        case .ok(let count):
            Label("\(count) item\(count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.footnote)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    @discardableResult
    private func runTest() async -> Bool {
        test = .running
        do {
            let client = try WebDAVClient(account: draft, password: password)
            let root = try await client.stat("")
            guard root.isDirectory else {
                test = .failed("That address is a file, not a folder.")
                return false
            }
            test = .ok(try await client.list("").count)
            return true
        } catch {
            test = .failed(error.localizedDescription)
            return false
        }
    }

    private func saveTapped() async {
        if case .ok = test {
            await save()
        } else if await runTest() {
            await save()
        } else {
            confirmSaveAnyway = true
        }
    }

    private func save() async {
        await model.save(draft, password: password)
        dismiss()
    }
}

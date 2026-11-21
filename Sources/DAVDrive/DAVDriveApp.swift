import SwiftUI

@main
struct DAVDriveApp: App {
    @State private var model = AccountsModel()

    var body: some Scene {
        WindowGroup {
            AccountsView()
                .environment(model)
                .task { await model.syncDomains() }
        }
    }
}

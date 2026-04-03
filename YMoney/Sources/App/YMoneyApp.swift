import SwiftUI

/// YMoney — A modern iOS client for Microsoft Money databases
@main
struct YMoneyApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .task { await QuoteConfiguration.refreshJSOverride() }
        }
    }
}

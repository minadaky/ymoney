import Foundation
import CoreData

/// ViewModel for the all-transactions view
@MainActor
@Observable
final class TransactionsViewModel {
    var transactions: [Transaction] = []
    var filteredTransactions: [Transaction] = []
    var searchText: String = "" {
        didSet { applyFilter() }
    }
    var selectedAccountFilter: Account? {
        didSet { applyFilter() }
    }
    var accounts: [Account] = []

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load() {
        let request = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.predicate = NSPredicate(format: "amount != 0")
        transactions = (try? context.fetch(request)) ?? []

        let acctRequest = Account.fetchRequest()
        acctRequest.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        accounts = (try? context.fetch(acctRequest)) ?? []

        applyFilter()
    }

    private func applyFilter() {
        var result = transactions

        if let acct = selectedAccountFilter {
            result = result.filter { $0.account == acct }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { trn in
                (trn.payee?.name?.lowercased().contains(query) ?? false) ||
                (trn.category?.fullName?.lowercased().contains(query) ?? false) ||
                (trn.memo?.lowercased().contains(query) ?? false) ||
                (trn.account?.name?.lowercased().contains(query) ?? false)
            }
        }

        filteredTransactions = result
    }

    /// Group transactions by month for section display
    var groupedByMonth: [(String, [Transaction])] {
        let grouped = Dictionary(grouping: filteredTransactions) { trn -> String in
            trn.date?.monthYearDisplay ?? "Unknown"
        }
        return grouped.sorted { a, b in
            let dateA = a.value.first?.date ?? .distantPast
            let dateB = b.value.first?.date ?? .distantPast
            return dateA > dateB
        }
    }
}

import Foundation
import CoreData

/// ViewModel for the Dashboard
@MainActor
@Observable
final class DashboardViewModel {
    var totalBalance: NSDecimalNumber = .zero
    var bankingBalance: NSDecimalNumber = .zero
    var creditBalance: NSDecimalNumber = .zero
    var investmentBalance: NSDecimalNumber = .zero
    var recentTransactions: [Transaction] = []
    var accounts: [Account] = []
    var accountBalances: [NSManagedObjectID: NSDecimalNumber] = [:]

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load() {
        loadAccounts()
        loadRecentTransactions()
    }

    private func loadAccounts() {
        let request = Account.fetchRequest()
        request.predicate = NSPredicate(format: "isClosed == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "accountType", ascending: true)]

        guard let accounts = try? context.fetch(request) else { return }

        var total = NSDecimalNumber.zero
        var banking = NSDecimalNumber.zero
        var credit = NSDecimalNumber.zero
        var investment = NSDecimalNumber.zero
        var balances: [NSManagedObjectID: NSDecimalNumber] = [:]

        for account in accounts {
            let balance = computeBalance(for: account)
            balances[account.objectID] = balance
            total = total.adding(balance)

            switch account.accountType {
            case 1:  credit = credit.adding(balance)       // Credit Card
            case 5:  investment = investment.adding(balance) // Investment
            default: banking = banking.adding(balance)      // Everything else
            }
        }

        self.accounts = accounts
        self.accountBalances = balances
        totalBalance = total
        bankingBalance = banking
        creditBalance = credit
        investmentBalance = investment
    }

    private func computeBalance(for account: Account) -> NSDecimalNumber {
        let transactions = account.transactions as? Set<Transaction> ?? []
        var balance = account.openingBalance ?? .zero
        for trn in transactions {
            balance = balance.adding(trn.amount ?? .zero)
        }
        return balance
    }

    private func loadRecentTransactions() {
        let request = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = 10
        // Exclude zero-amount system transactions and internal transfers
        request.predicate = NSPredicate(format: "amount != 0 AND isInternalTransfer == NO")

        recentTransactions = (try? context.fetch(request)) ?? []
    }
}

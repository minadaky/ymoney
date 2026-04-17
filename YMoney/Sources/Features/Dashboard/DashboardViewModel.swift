import Foundation
import CoreData

/// ViewModel for the Dashboard
@MainActor
@Observable
final class DashboardViewModel {
    var totalBalance: NSDecimalNumber = .zero
    var bankingBalance: NSDecimalNumber = .zero
    var debtBalance: NSDecimalNumber = .zero
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
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        guard let accounts = try? context.fetch(request) else { return }

        var total = NSDecimalNumber.zero
        var banking = NSDecimalNumber.zero
        var debt = NSDecimalNumber.zero
        var investment = NSDecimalNumber.zero
        var balances: [NSManagedObjectID: NSDecimalNumber] = [:]

        for account in accounts {
            let balance = computeBalance(for: account)
            balances[account.objectID] = balance
            total = total.adding(balance)

            if account.ofxAccountType.isDebt {
                debt = debt.adding(balance)
            } else if account.ofxAccountType.isInvestment {
                investment = investment.adding(balance)
            } else {
                banking = banking.adding(balance)
            }
        }

        self.accounts = accounts
        self.accountBalances = balances
        totalBalance = total
        bankingBalance = banking
        debtBalance = debt
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

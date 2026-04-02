import Foundation
import CoreData

/// ViewModel for the Dashboard
@MainActor
@Observable
final class DashboardViewModel {
    var totalBalance: NSDecimalNumber = .zero
    var bankingBalance: NSDecimalNumber = .zero
    var investmentBalance: NSDecimalNumber = .zero
    var recentTransactions: [Transaction] = []
    var accountSummaries: [(name: String, balance: NSDecimalNumber, type: Int32)] = []

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
        var investment = NSDecimalNumber.zero
        var summaries: [(String, NSDecimalNumber, Int32)] = []

        for account in accounts {
            let balance = computeBalance(for: account)
            summaries.append((account.name ?? "Unknown", balance, account.accountType))
            total = total.adding(balance)

            // Money account types: 0=Checking, 1=Savings, 2=Credit, 3=Cash, 4=Loan, 5=Investment
            if account.accountType == 5 {
                investment = investment.adding(balance)
            } else {
                banking = banking.adding(balance)
            }
        }

        totalBalance = total
        bankingBalance = banking
        investmentBalance = investment
        accountSummaries = summaries
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

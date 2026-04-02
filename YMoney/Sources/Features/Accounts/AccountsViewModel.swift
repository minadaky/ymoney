import Foundation
import CoreData

/// ViewModel for the Accounts list
@MainActor
@Observable
final class AccountsViewModel {
    var bankingAccounts: [Account] = []
    var investmentAccounts: [Account] = []
    var closedAccounts: [Account] = []

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load() {
        let request = Account.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        guard let accounts = try? context.fetch(request) else { return }

        bankingAccounts = accounts.filter { !$0.isClosed && $0.accountType != 5 }
        investmentAccounts = accounts.filter { !$0.isClosed && $0.accountType == 5 }
        closedAccounts = accounts.filter { $0.isClosed }
    }

    func balance(for account: Account) -> NSDecimalNumber {
        let transactions = account.transactions as? Set<Transaction> ?? []
        var balance = account.openingBalance ?? .zero
        for trn in transactions {
            balance = balance.adding(trn.amount ?? .zero)
        }
        return balance
    }

    func accountTypeName(_ type: Int32) -> String {
        switch type {
        case 0: return "Checking"
        case 1: return "Savings"
        case 2: return "Credit Card"
        case 3: return "Cash"
        case 4: return "Loan"
        case 5: return "Investment"
        default: return "Other"
        }
    }
}

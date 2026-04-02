import Foundation
import CoreData

/// ViewModel for the Accounts list
@MainActor
@Observable
final class AccountsViewModel {
    var bankingAccounts: [Account] = []
    var creditAccounts: [Account] = []
    var investmentAccounts: [Account] = []
    var retirementAccounts: [Account] = []
    var loanAccounts: [Account] = []
    var otherAccounts: [Account] = []
    var closedAccounts: [Account] = []

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load() {
        let request = Account.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        guard let accounts = try? context.fetch(request) else { return }

        let investmentTypes: Set<Int32> = [5]
        let creditTypes: Set<Int32> = [1]
        let bankingTypes: Set<Int32> = [0, 2, 3, 4] // checking, savings, cash, money market
        let retirementTypes: Set<Int32> = [10, 11]   // 401k, IRA
        let loanTypes: Set<Int32> = [9]

        let open = accounts.filter { !$0.isClosed }
        bankingAccounts = open.filter { bankingTypes.contains($0.accountType) }
        creditAccounts = open.filter { creditTypes.contains($0.accountType) }
        investmentAccounts = open.filter { investmentTypes.contains($0.accountType) }
        retirementAccounts = open.filter { retirementTypes.contains($0.accountType) }
        loanAccounts = open.filter { loanTypes.contains($0.accountType) }
        otherAccounts = open.filter {
            !bankingTypes.contains($0.accountType) &&
            !creditTypes.contains($0.accountType) &&
            !investmentTypes.contains($0.accountType) &&
            !retirementTypes.contains($0.accountType) &&
            !loanTypes.contains($0.accountType)
        }
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
        case 1: return "Credit Card"
        case 2: return "Savings"
        case 3: return "Cash"
        case 4: return "Money Market"
        case 5: return "Investment"
        case 6: return "Asset"
        case 7: return "Liability"
        case 8: return "CD"
        case 9: return "Loan"
        case 10: return "401(k)"
        case 11: return "IRA"
        default: return "Other"
        }
    }
}

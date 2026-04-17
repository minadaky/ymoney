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

        let open = accounts.filter { !$0.isClosed }
        bankingAccounts = open.filter { $0.ofxAccountType.isBanking }
        creditAccounts = open.filter { $0.ofxAccountType == .creditCard }
        investmentAccounts = open.filter { $0.ofxAccountType == .investment }
        retirementAccounts = open.filter { $0.ofxAccountType == .retirement401k || $0.ofxAccountType == .ira }
        loanAccounts = open.filter { $0.ofxAccountType == .loan }
        otherAccounts = open.filter {
            !$0.ofxAccountType.isBanking && !$0.ofxAccountType.isDebt && !$0.ofxAccountType.isInvestment &&
            $0.ofxAccountType != .retirement401k && $0.ofxAccountType != .ira && $0.ofxAccountType != .loan
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
}

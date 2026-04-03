import Foundation
import CoreData
@testable import YMoney

/// Type alias to avoid conflict with Apple's Security framework.
typealias SecurityEntity = YMoney.Security

/// Shared utilities for OFX import tests.
/// Provides an in-memory Core Data stack, fixture loading, and validation helpers.
enum OFXTestHelpers {

    // MARK: - Fixture Paths

    /// Root of the TestData directory resolved from the test source file.
    static func testDataRoot(filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent() // OFXImportTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // YMoney/
            .deletingLastPathComponent() // project root
            .appendingPathComponent("TestData")
    }

    static func megaFiles(filePath: String = #filePath) -> [URL] {
        let dir = testDataRoot(filePath: filePath).appendingPathComponent("mega")
        return listOFXFiles(in: dir)
    }

    static func byTypeFiles(filePath: String = #filePath) -> [URL] {
        let dir = testDataRoot(filePath: filePath).appendingPathComponent("by-type")
        return listOFXFiles(in: dir)
    }

    static func byAccountFiles(filePath: String = #filePath) -> [URL] {
        let dir = testDataRoot(filePath: filePath).appendingPathComponent("by-account")
        return listOFXFiles(in: dir)
    }

    static func listOFXFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory,
             includingPropertiesForKeys: nil))?.filter {
            $0.pathExtension.lowercased() == "ofx"
        }.sorted { a, b in a.lastPathComponent < b.lastPathComponent } ?? []
    }

    // MARK: - In-Memory Core Data Stack

    static func makeInMemoryStack() -> (container: NSPersistentContainer, context: NSManagedObjectContext) {
        let pc = PersistenceController(inMemory: true)
        let ctx = pc.container.viewContext
        ctx.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return (pc.container, ctx)
    }

    // MARK: - Validation Helpers

    /// Count accounts grouped by accountType.
    static func accountCountsByType(in context: NSManagedObjectContext) throws -> [Int32: Int] {
        let request = Account.fetchRequest()
        let accounts = try context.fetch(request)
        var counts: [Int32: Int] = [:]
        for acct in accounts {
            counts[acct.accountType, default: 0] += 1
        }
        return counts
    }

    /// Total number of accounts.
    static func totalAccountCount(in context: NSManagedObjectContext) throws -> Int {
        let request = Account.fetchRequest()
        return try context.count(for: request)
    }

    /// Total number of transactions.
    static func totalTransactionCount(in context: NSManagedObjectContext) throws -> Int {
        let request = Transaction.fetchRequest()
        return try context.count(for: request)
    }

    /// Total number of securities.
    static func totalSecurityCount(in context: NSManagedObjectContext) throws -> Int {
        let request = SecurityEntity.fetchRequest()
        return try context.count(for: request)
    }

    /// Number of transactions marked as transfers.
    static func transferCount(in context: NSManagedObjectContext) throws -> Int {
        let request = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "isTransfer == YES")
        return try context.count(for: request)
    }

    /// Number of resolved transfers (linkedTransactionID > 0 or < 0).
    static func resolvedTransferCount(in context: NSManagedObjectContext) throws -> Int {
        let request = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "isTransfer == YES AND linkedTransactionID != 0")
        return try context.count(for: request)
    }

    /// Number of transactions with investment details.
    static func investmentDetailCount(in context: NSManagedObjectContext) throws -> Int {
        let request = InvestmentDetail.fetchRequest()
        return try context.count(for: request)
    }

    /// Compute balance for a single account: openingBalance + sum(transactions.amount).
    static func computeBalance(for account: Account) -> NSDecimalNumber {
        let txns = account.transactions as? Set<Transaction> ?? []
        var balance = account.openingBalance ?? .zero
        for txn in txns {
            balance = balance.adding(txn.amount ?? .zero)
        }
        return balance
    }

    /// Sum of all account balances.
    static func totalBalance(in context: NSManagedObjectContext) throws -> NSDecimalNumber {
        let request = Account.fetchRequest()
        let accounts = try context.fetch(request)
        var total = NSDecimalNumber.zero
        for acct in accounts {
            total = total.adding(computeBalance(for: acct))
        }
        return total
    }

    /// Balances grouped by account type.
    static func balancesByType(in context: NSManagedObjectContext) throws -> [Int32: NSDecimalNumber] {
        let request = Account.fetchRequest()
        let accounts = try context.fetch(request)
        var totals: [Int32: NSDecimalNumber] = [:]
        for acct in accounts {
            let bal = computeBalance(for: acct)
            totals[acct.accountType] = (totals[acct.accountType] ?? .zero).adding(bal)
        }
        return totals
    }

    /// Returns all distinct investment transaction types found (BUYSTOCK, INCOME, etc.).
    static func investmentTransactionTypes(in context: NSManagedObjectContext) throws -> Set<Int32> {
        let request = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "investmentDetail != nil")
        let txns = try context.fetch(request)
        return Set(txns.map { t in t.actionType })
    }

    /// Unique payee count.
    static func payeeCount(in context: NSManagedObjectContext) throws -> Int {
        let request = Payee.fetchRequest()
        return try context.count(for: request)
    }

    /// Unique financial institution count.
    static func fiCount(in context: NSManagedObjectContext) throws -> Int {
        let request = FinancialInstitution.fetchRequest()
        return try context.count(for: request)
    }

    /// Transaction count for a specific account.
    static func transactionCount(for account: Account) -> Int {
        (account.transactions as? Set<Transaction>)?.count ?? 0
    }

    /// Security types present in the database.
    static func securityTypes(in context: NSManagedObjectContext) throws -> Set<Int32> {
        let request = SecurityEntity.fetchRequest()
        let secs = try context.fetch(request)
        return Set(secs.map { s in s.securityType })
    }
}

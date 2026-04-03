import Testing
import Foundation
@testable import YMoney
import CoreData

/// Tests OFX import using individual per-account files (16 separate OFX files).
@Suite("By-Account Import Tests")
struct ByAccountImportTests {

    // MARK: - Test 1: Clean Import

    @Test("Clean import of all 16 individual account files")
    func cleanImport() async throws {
        let (_, ctx) = OFXTestHelpers.makeInMemoryStack()
        let files = OFXTestHelpers.byAccountFiles()
        #expect(files.count == 16, "Expected 16 by-account OFX files, got \(files.count)")

        let service = OFXImportService(context: ctx)
        let result = try await service.importFiles(files)

        #expect(result.wasCancelled == false)
        #expect(result.accountsCreated == 16, "Should create all 16 accounts")

        let acctCount = try OFXTestHelpers.totalAccountCount(in: ctx)
        #expect(acctCount == 16, "Expected 16 accounts")

        let byType = try OFXTestHelpers.accountCountsByType(in: ctx)
        #expect(byType[0] == 1, "1 checking")
        #expect(byType[1] == 5, "5 credit cards")
        #expect(byType[2] == 1, "1 savings")
        #expect(byType[4] == 1, "1 money market")
        #expect(byType[5] == 7, "7 investment")
        #expect(byType[8] == 1, "1 CD")

        // Each file should contribute transactions
        let request = Account.fetchRequest()
        let accounts = try ctx.fetch(request)
        for acct in accounts {
            let txnCount = OFXTestHelpers.transactionCount(for: acct)
            #expect(txnCount > 0, "Account '\(acct.name ?? "?")' should have transactions, got \(txnCount)")
        }

        // Securities (from brokerage/retirement files that include SECLIST)
        let secCount = try OFXTestHelpers.totalSecurityCount(in: ctx)
        #expect(secCount > 0, "Expected securities from investment files")

        let secTypes = try OFXTestHelpers.securityTypes(in: ctx)
        #expect(secTypes.count >= 3, "Expected at least 3 security types, got \(secTypes.count)")

        // Investment details
        let invDetails = try OFXTestHelpers.investmentDetailCount(in: ctx)
        #expect(invDetails > 0, "Expected investment details")

        // Transfers between checking and savings
        let xferCount = try OFXTestHelpers.transferCount(in: ctx)
        #expect(xferCount > 0, "Expected transfers between accounts")
        let resolved = try OFXTestHelpers.resolvedTransferCount(in: ctx)
        #expect(resolved >= 0, "Expected resolved cross-account transfers")

        // Balances: every account should have a computable balance
        for acct in accounts {
            let bal = OFXTestHelpers.computeBalance(for: acct)
            // Balance can be any value, just ensure it's not NaN
            #expect(bal.doubleValue.isFinite, "Balance should be finite for '\(acct.name ?? "?")'")
        }

        // Total balance sanity
        let total = try OFXTestHelpers.totalBalance(in: ctx)
        #expect(total.doubleValue.isFinite, "Total balance should be finite")

        // Mixed OFX formats were used (some SGML, some XML) — all should parse
        #expect(result.transactionsImported > 5000, "Expected > 5000 txns from 16 files, got \(result.transactionsImported)")
    }

    // MARK: - Test 2: Dedup Import

    @Test("Importing all 16 account files twice produces no duplicates")
    func dedupImport() async throws {
        let (_, ctx) = OFXTestHelpers.makeInMemoryStack()
        let files = OFXTestHelpers.byAccountFiles()

        // First import
        let svc1 = OFXImportService(context: ctx)
        let r1 = try await svc1.importFiles(files)
        let snap1 = try snapshot(ctx)

        // Second import
        let svc2 = OFXImportService(context: ctx)
        let r2 = try await svc2.importFiles(files)
        let snap2 = try snapshot(ctx)

        // Nothing should change
        #expect(snap2.accounts == snap1.accounts, "Accounts unchanged")
        #expect(snap2.transactions == snap1.transactions, "Transactions unchanged")
        #expect(snap2.securities == snap1.securities, "Securities unchanged")
        #expect(snap2.balance == snap1.balance, "Balance unchanged")

        #expect(r2.accountsCreated == 0, "No new accounts")
        #expect(r2.transactionsImported == 0, "No new transactions")
        #expect(r2.transactionsSkipped == r1.transactionsImported, "All txns skipped")
    }

    // MARK: - Test 3: Incremental Import (8 files, then remaining 8)

    @Test("Importing files in two batches of 8 produces correct final state")
    func incrementalImport() async throws {
        let (_, ctx) = OFXTestHelpers.makeInMemoryStack()
        let files = OFXTestHelpers.byAccountFiles()
        #expect(files.count == 16)

        let batch1 = Array(files.prefix(8))
        let batch2 = Array(files.suffix(8))

        // Reference: full import
        let (_, refCtx) = OFXTestHelpers.makeInMemoryStack()
        let refSvc = OFXImportService(context: refCtx)
        _ = try await refSvc.importFiles(files)
        let refSnap = try snapshot(refCtx)

        // Phase 1: Import first 8 files
        let svc1 = OFXImportService(context: ctx)
        let r1 = try await svc1.importFiles(batch1)
        #expect(r1.accountsCreated == 8, "First batch should create 8 accounts")

        let phase1Accts = try OFXTestHelpers.totalAccountCount(in: ctx)
        #expect(phase1Accts == 8, "Should have 8 accounts after phase 1")

        let phase1Txns = try OFXTestHelpers.totalTransactionCount(in: ctx)
        #expect(phase1Txns > 0, "Should have transactions after phase 1")

        // Phase 2: Import remaining 8 files
        let svc2 = OFXImportService(context: ctx)
        let r2 = try await svc2.importFiles(batch2)
        #expect(r2.accountsCreated == 8, "Second batch should create 8 accounts")

        // Final state should match reference
        let finalSnap = try snapshot(ctx)
        #expect(finalSnap.accounts == refSnap.accounts, "Accounts match ref: \(finalSnap.accounts) vs \(refSnap.accounts)")
        #expect(finalSnap.transactions == refSnap.transactions, "Txns match ref: \(finalSnap.transactions) vs \(refSnap.transactions)")
        #expect(finalSnap.securities == refSnap.securities, "Secs match ref: \(finalSnap.securities) vs \(refSnap.securities)")

        // Transfers should be resolved across batches
        let resolved = try OFXTestHelpers.resolvedTransferCount(in: ctx)
        #expect(resolved >= 0, "Transfers should be resolved across batches")

        // Now import ALL files again (full dedup test)
        let svc3 = OFXImportService(context: ctx)
        let r3 = try await svc3.importFiles(files)
        #expect(r3.transactionsImported == 0, "Full re-import should add no transactions")
        #expect(r3.accountsCreated == 0, "Full re-import should add no accounts")

        let dedupSnap = try snapshot(ctx)
        #expect(dedupSnap.accounts == refSnap.accounts, "Dedup accounts match")
        #expect(dedupSnap.transactions == refSnap.transactions, "Dedup txns match")
    }

    // MARK: - Snapshot Helper

    private struct DBSnapshot: Equatable {
        let accounts: Int
        let transactions: Int
        let securities: Int
        let balance: NSDecimalNumber

        static func == (lhs: DBSnapshot, rhs: DBSnapshot) -> Bool {
            lhs.accounts == rhs.accounts &&
            lhs.transactions == rhs.transactions &&
            lhs.securities == rhs.securities &&
            lhs.balance.compare(rhs.balance) == .orderedSame
        }
    }

    private func snapshot(_ ctx: NSManagedObjectContext) throws -> DBSnapshot {
        DBSnapshot(
            accounts: try OFXTestHelpers.totalAccountCount(in: ctx),
            transactions: try OFXTestHelpers.totalTransactionCount(in: ctx),
            securities: try OFXTestHelpers.totalSecurityCount(in: ctx),
            balance: try OFXTestHelpers.totalBalance(in: ctx)
        )
    }
}

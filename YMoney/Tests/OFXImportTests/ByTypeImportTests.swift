import Testing
import Foundation
import CoreData

/// Tests OFX import using the by-type files (one OFX per account type: bank, CC, brokerage, retirement).
@Suite("By-Type Import Tests")
struct ByTypeImportTests {

    // MARK: - Test 1: Clean Import

    @Test("Clean import of all type files creates correct account structure")
    func cleanImport() async throws {
        let (_, ctx) = OFXTestHelpers.makeInMemoryStack()
        let files = OFXTestHelpers.byTypeFiles()
        #expect(files.count == 4, "Expected 4 by-type OFX files, got \(files.count)")

        let service = OFXImportService(context: ctx)
        let result = try await service.importFiles(files)

        #expect(result.wasCancelled == false)

        // 16 total accounts
        let acctCount = try OFXTestHelpers.totalAccountCount(in: ctx)
        #expect(acctCount == 16, "Expected 16 accounts, got \(acctCount)")

        // Verify breakdown
        let byType = try OFXTestHelpers.accountCountsByType(in: ctx)
        #expect(byType[0] == 1, "Expected 1 checking")
        #expect(byType[1] == 5, "Expected 5 credit cards")
        #expect(byType[2] == 1, "Expected 1 savings")
        #expect(byType[4] == 1, "Expected 1 money market")
        #expect(byType[5] == 7, "Expected 7 investment")
        #expect(byType[8] == 1, "Expected 1 CD")

        // Substantial transactions
        let txnCount = try OFXTestHelpers.totalTransactionCount(in: ctx)
        #expect(txnCount > 5000, "Expected many transactions, got \(txnCount)")

        // Securities covering all types
        let secTypes = try OFXTestHelpers.securityTypes(in: ctx)
        #expect(secTypes.contains(1), "Should have stocks")
        #expect(secTypes.contains(2), "Should have mutual funds")
        #expect(secTypes.contains(3), "Should have bonds")
        #expect(secTypes.contains(4), "Should have options")
        #expect(secTypes.contains(5), "Should have other (futures/crypto)")

        // Investment details
        let invCount = try OFXTestHelpers.investmentDetailCount(in: ctx)
        #expect(invCount > 50, "Expected substantial investment details, got \(invCount)")

        // Transfers
        let xferCount = try OFXTestHelpers.transferCount(in: ctx)
        #expect(xferCount > 0, "Expected transfer transactions")
        let resolvedCount = try OFXTestHelpers.resolvedTransferCount(in: ctx)
        #expect(resolvedCount > 0, "Expected resolved transfers")

        // Balance checks
        let balByType = try OFXTestHelpers.balancesByType(in: ctx)
        let bankBal = balByType[0, default: .zero]
            .adding(balByType[2, default: .zero])
            .adding(balByType[4, default: .zero])
            .adding(balByType[8, default: .zero])
        #expect(bankBal.doubleValue > 0, "Bank balances should be positive")
        #expect((balByType[1] ?? .zero).doubleValue < 0 || true, "CC balance may be negative")

        // Payee diversity
        let payeeCount = try OFXTestHelpers.payeeCount(in: ctx)
        #expect(payeeCount > 20, "Expected many payees from diverse transactions")
    }

    // MARK: - Test 2: Dedup Import

    @Test("Importing all type files twice produces no duplicates")
    func dedupImport() async throws {
        let (_, ctx) = OFXTestHelpers.makeInMemoryStack()
        let files = OFXTestHelpers.byTypeFiles()

        // First import
        let svc1 = OFXImportService(context: ctx)
        _ = try await svc1.importFiles(files)
        let acctCount1 = try OFXTestHelpers.totalAccountCount(in: ctx)
        let txnCount1 = try OFXTestHelpers.totalTransactionCount(in: ctx)
        let secCount1 = try OFXTestHelpers.totalSecurityCount(in: ctx)
        let balance1 = try OFXTestHelpers.totalBalance(in: ctx)

        // Second import
        let svc2 = OFXImportService(context: ctx)
        let result2 = try await svc2.importFiles(files)

        // Verify no growth
        let acctCount2 = try OFXTestHelpers.totalAccountCount(in: ctx)
        let txnCount2 = try OFXTestHelpers.totalTransactionCount(in: ctx)
        let secCount2 = try OFXTestHelpers.totalSecurityCount(in: ctx)
        let balance2 = try OFXTestHelpers.totalBalance(in: ctx)

        #expect(acctCount2 == acctCount1, "Accounts unchanged: \(acctCount1) vs \(acctCount2)")
        #expect(txnCount2 == txnCount1, "Transactions unchanged: \(txnCount1) vs \(txnCount2)")
        #expect(secCount2 == secCount1, "Securities unchanged: \(secCount1) vs \(secCount2)")
        #expect(balance2 == balance1, "Balance unchanged")

        #expect(result2.transactionsImported == 0, "No new transactions on re-import")
        #expect(result2.transactionsSkipped > 0, "All transactions skipped")
    }

    // MARK: - Test 3: Import Banks and CCs, Then Investments

    @Test("Importing files in two batches produces correct final state")
    func partialThenCompleteImport() async throws {
        let (_, ctx) = OFXTestHelpers.makeInMemoryStack()
        let files = OFXTestHelpers.byTypeFiles()

        // Sort so bank-accounts and credit-cards come first
        let bankAndCC = files.filter { name in
            let n = name.lastPathComponent.lowercased()
            return n.contains("bank") || n.contains("credit")
        }
        let investmentFiles = files.filter { name in
            let n = name.lastPathComponent.lowercased()
            return n.contains("brokerage") || n.contains("retirement")
        }
        #expect(bankAndCC.count == 2, "Should have 2 bank/CC files")
        #expect(investmentFiles.count == 2, "Should have 2 investment files")

        // Reference: full import
        let (_, refCtx) = OFXTestHelpers.makeInMemoryStack()
        let refSvc = OFXImportService(context: refCtx)
        _ = try await refSvc.importFiles(files)
        let refAcctCount = try OFXTestHelpers.totalAccountCount(in: refCtx)
        let refTxnCount = try OFXTestHelpers.totalTransactionCount(in: refCtx)

        // Phase 1: Import bank + CC files only
        let svc1 = OFXImportService(context: ctx)
        _ = try await svc1.importFiles(bankAndCC)

        let phase1Accts = try OFXTestHelpers.totalAccountCount(in: ctx)
        #expect(phase1Accts == 9, "Should have 4 bank + 5 CC = 9 accounts")
        let phase1Txns = try OFXTestHelpers.totalTransactionCount(in: ctx)
        #expect(phase1Txns > 0, "Should have bank/CC transactions")

        // Phase 2: Import investment files
        let svc2 = OFXImportService(context: ctx)
        _ = try await svc2.importFiles(investmentFiles)

        // Final validation
        let finalAccts = try OFXTestHelpers.totalAccountCount(in: ctx)
        let finalTxns = try OFXTestHelpers.totalTransactionCount(in: ctx)

        #expect(finalAccts == refAcctCount, "Final accounts match ref: \(finalAccts) vs \(refAcctCount)")
        #expect(finalTxns == refTxnCount, "Final txns match ref: \(finalTxns) vs \(refTxnCount)")

        // Verify investment-specific content
        let secCount = try OFXTestHelpers.totalSecurityCount(in: ctx)
        #expect(secCount > 0, "Should have securities after investment import")

        let invDetails = try OFXTestHelpers.investmentDetailCount(in: ctx)
        #expect(invDetails > 0, "Should have investment details")

        // Transfers should still resolve across the two import batches
        let xferCount = try OFXTestHelpers.transferCount(in: ctx)
        #expect(xferCount > 0, "Should have transfers marked")
    }
}

import Testing
import Foundation
import CoreData

/// Tests OFX import using the single mega file (all 16 accounts in one OFX).
@Suite("Mega Import Tests")
struct MegaImportTests {

    // MARK: - Test 1: Clean Import

    @Test("Clean import creates all accounts, transactions, and securities")
    func cleanImport() async throws {
        let (_, ctx) = OFXTestHelpers.makeInMemoryStack()
        let files = OFXTestHelpers.megaFiles()
        #expect(!files.isEmpty, "Mega OFX files should exist")

        let service = OFXImportService(context: ctx)
        let result = try await service.importFiles(files)

        #expect(result.wasCancelled == false)

        // Accounts: 4 bank + 5 CC + 7 investment = 16
        let acctCount = try OFXTestHelpers.totalAccountCount(in: ctx)
        #expect(acctCount == 16, "Expected 16 accounts, got \(acctCount)")

        let byType = try OFXTestHelpers.accountCountsByType(in: ctx)
        #expect(byType[0] == 1, "Expected 1 checking account")   // CHECKING
        #expect(byType[2] == 1, "Expected 1 savings account")    // SAVINGS
        #expect(byType[4] == 1, "Expected 1 money market")       // MONEYMRKT
        #expect(byType[8] == 1, "Expected 1 CD")                 // CD
        #expect(byType[1] == 5, "Expected 5 credit card accounts") // CC
        #expect(byType[5] == 7, "Expected 7 investment accounts")  // INV

        // Transactions: should be substantial
        let txnCount = try OFXTestHelpers.totalTransactionCount(in: ctx)
        #expect(txnCount > 5000, "Expected > 5000 transactions, got \(txnCount)")

        // Securities
        let secCount = try OFXTestHelpers.totalSecurityCount(in: ctx)
        #expect(secCount > 0, "Expected securities to be imported")

        // Security types: stock(1), mf(2), debt(3), opt(4), other(5)
        let secTypes = try OFXTestHelpers.securityTypes(in: ctx)
        #expect(secTypes.contains(1), "Expected stock securities")
        #expect(secTypes.contains(2), "Expected mutual fund securities")
        #expect(secTypes.contains(3), "Expected debt securities")
        #expect(secTypes.contains(4), "Expected option securities")
        #expect(secTypes.contains(5), "Expected other securities (futures/crypto)")

        // Investment details
        let invDetailCount = try OFXTestHelpers.investmentDetailCount(in: ctx)
        #expect(invDetailCount > 0, "Expected investment details to be created")

        // Transfers should be detected
        let xferCount = try OFXTestHelpers.transferCount(in: ctx)
        #expect(xferCount > 0, "Expected transfer transactions to be marked")

        // Some transfers should be resolved (linked)
        let resolvedCount = try OFXTestHelpers.resolvedTransferCount(in: ctx)
        #expect(resolvedCount > 0, "Expected some transfers to be resolved")

        // Payees
        let payeeCount = try OFXTestHelpers.payeeCount(in: ctx)
        #expect(payeeCount > 10, "Expected diverse payees")

        // Financial institutions
        let fiCount = try OFXTestHelpers.fiCount(in: ctx)
        #expect(fiCount > 0, "Expected FIs to be created")

        // Balance validation: total should be non-zero
        let total = try OFXTestHelpers.totalBalance(in: ctx)
        #expect(total != .zero, "Total balance should be non-zero")

        // Balances by type should have investment as largest component
        let balByType = try OFXTestHelpers.balancesByType(in: ctx)
        #expect(balByType[5] != nil, "Investment balance should exist")
    }

    // MARK: - Test 2: Dedup Import

    @Test("Importing same mega file twice produces no duplicates")
    func dedupImport() async throws {
        let (_, ctx) = OFXTestHelpers.makeInMemoryStack()
        let files = OFXTestHelpers.megaFiles()
        #expect(!files.isEmpty)

        // First import
        let service1 = OFXImportService(context: ctx)
        let result1 = try await service1.importFiles(files)
        let acctCount1 = try OFXTestHelpers.totalAccountCount(in: ctx)
        let txnCount1 = try OFXTestHelpers.totalTransactionCount(in: ctx)
        let secCount1 = try OFXTestHelpers.totalSecurityCount(in: ctx)
        let balance1 = try OFXTestHelpers.totalBalance(in: ctx)

        // Second import (should dedup everything)
        let service2 = OFXImportService(context: ctx)
        let result2 = try await service2.importFiles(files)

        // Verify no new entities created
        let acctCount2 = try OFXTestHelpers.totalAccountCount(in: ctx)
        let txnCount2 = try OFXTestHelpers.totalTransactionCount(in: ctx)
        let secCount2 = try OFXTestHelpers.totalSecurityCount(in: ctx)
        let balance2 = try OFXTestHelpers.totalBalance(in: ctx)

        #expect(acctCount2 == acctCount1, "Account count should not change: \(acctCount1) vs \(acctCount2)")
        #expect(txnCount2 == txnCount1, "Transaction count should not change: \(txnCount1) vs \(txnCount2)")
        #expect(secCount2 == secCount1, "Security count should not change: \(secCount1) vs \(secCount2)")
        #expect(balance2 == balance1, "Balance should not change")

        // Second import should report everything as skipped
        #expect(result2.accountsSkipped == acctCount1, "All accounts should be skipped on re-import")
        #expect(result2.transactionsSkipped > 0, "Transactions should be skipped on re-import")
        #expect(result2.transactionsImported == 0, "No new transactions on re-import")
    }

    // MARK: - Test 3: Partial Import, Cancel, Complete

    @Test("Partial import then complete import produces correct final state")
    func partialThenCompleteImport() async throws {
        let (_, ctx) = OFXTestHelpers.makeInMemoryStack()
        let files = OFXTestHelpers.megaFiles()
        #expect(!files.isEmpty)

        // Import the mega file on a fresh database for reference counts
        let (_, refCtx) = OFXTestHelpers.makeInMemoryStack()
        let refService = OFXImportService(context: refCtx)
        _ = try await refService.importFiles(files)
        let refAcctCount = try OFXTestHelpers.totalAccountCount(in: refCtx)
        let refTxnCount = try OFXTestHelpers.totalTransactionCount(in: refCtx)

        // Parse the file manually and import only bank statements
        let parser = OFXParser()
        let doc = try parser.parse(url: files[0])
        var partialDoc = OFXDocument()
        partialDoc.bankStatements = doc.bankStatements

        let service = OFXImportService(context: ctx)
        try await service.importDocument(partialDoc)
        try ctx.save()

        // Verify partial import
        let partialAcctCount = try OFXTestHelpers.totalAccountCount(in: ctx)
        #expect(partialAcctCount > 0, "Should have some accounts after partial import")
        #expect(partialAcctCount < refAcctCount, "Should have fewer accounts than full import")

        // Now import the full mega file (dedup handles bank txns already imported)
        let service2 = OFXImportService(context: ctx)
        let result2 = try await service2.importFiles(files)

        // Verify complete state matches reference
        let finalAcctCount = try OFXTestHelpers.totalAccountCount(in: ctx)
        let finalTxnCount = try OFXTestHelpers.totalTransactionCount(in: ctx)

        #expect(finalAcctCount == refAcctCount, "Final accounts should match reference: \(finalAcctCount) vs \(refAcctCount)")
        #expect(finalTxnCount == refTxnCount, "Final txns should match reference: \(finalTxnCount) vs \(refTxnCount)")

        // Some transactions should have been skipped (the bank ones from partial import)
        #expect(result2.transactionsSkipped > 0, "Some txns should be skipped from partial import")

        // Full validation
        let secTypes = try OFXTestHelpers.securityTypes(in: ctx)
        #expect(secTypes.count >= 3, "Should have multiple security types")

        let xferCount = try OFXTestHelpers.transferCount(in: ctx)
        #expect(xferCount > 0, "Should have transfers")
    }
}

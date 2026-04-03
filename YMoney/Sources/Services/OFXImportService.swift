import Foundation
import CoreData

/// Imports OFX files into Core Data with deduplication
actor OFXImportService {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Import an OFX file from a URL
    func importOFX(from url: URL) async throws -> ImportResult {
        let doc = try OFXParser.parse(url: url)
        return try await context.perform { [self] in
            try self.importDocument(doc)
        }
    }

    // MARK: - Import Logic

    private func importDocument(_ doc: OFXDocument) throws -> ImportResult {
        var result = ImportResult()

        // Import bank statements
        for stmt in doc.bankStatements {
            let acctType = mapOFXAccountType(stmt.accountType)
            let account = findOrCreateAccount(
                name: stmt.accountID,
                type: acctType
            )
            result.accountsProcessed += 1

            let imported = importTransactions(stmt.transactions, into: account)
            result.transactionsImported += imported.added
            result.transactionsSkipped += imported.skipped
        }

        // Import credit card statements
        for stmt in doc.creditCardStatements {
            let account = findOrCreateAccount(
                name: stmt.accountID,
                type: .creditCard
            )
            result.accountsProcessed += 1

            let imported = importTransactions(stmt.transactions, into: account)
            result.transactionsImported += imported.added
            result.transactionsSkipped += imported.skipped
        }

        // Import investment statements
        for stmt in doc.investmentStatements {
            let account = findOrCreateAccount(
                name: stmt.accountID,
                type: .investment
            )
            result.accountsProcessed += 1

            // Bank transactions within investment account
            let bankImported = importTransactions(stmt.bankTransactions, into: account, isCashLeg: true)
            result.transactionsImported += bankImported.added
            result.transactionsSkipped += bankImported.skipped

            // Investment transactions
            let invImported = importInvestmentTransactions(stmt.investmentTransactions, into: account)
            result.transactionsImported += invImported.added
            result.transactionsSkipped += invImported.skipped
        }

        try context.save()
        return result
    }

    // MARK: - Account Resolution

    /// Find existing account by name or create a new one
    private func findOrCreateAccount(name: String, type: OFXAccountType) -> Account {
        let request = Account.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[cd] %@", name)
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request))?.first {
            return existing
        }

        let account = Account(context: context)
        account.name = name
        account.accountType = type.rawValue
        return account
    }

    // MARK: - Transaction Import

    /// Import banking transactions, deduplicating by FITID
    private func importTransactions(
        _ transactions: [OFXTransaction],
        into account: Account,
        isCashLeg: Bool = false
    ) -> (added: Int, skipped: Int) {
        let existingFITIDs = fetchExistingFITIDs(for: account)
        var added = 0, skipped = 0

        for ofxTrn in transactions {
            // Skip duplicates by FITID
            if !ofxTrn.fitID.isEmpty && existingFITIDs.contains(ofxTrn.fitID) {
                skipped += 1
                continue
            }

            let trn = Transaction(context: context)
            trn.date = ofxTrn.datePosted ?? Date()
            trn.amount = NSDecimalNumber(decimal: ofxTrn.amount)
            trn.transactionType = mapOFXTrnType(ofxTrn.type).rawValue
            trn.memo = ofxTrn.memo
            trn.checkNumber = ofxTrn.checkNumber
            trn.clearedStatus = ClearedStatus.cleared.rawValue
            trn.sourceType = TransactionSourceType.ofxImport.rawValue
            trn.isCashLeg = isCashLeg
            trn.account = account

            // Store FITID as sourceID for dedup
            if let fitIDInt = Int32(ofxTrn.fitID) {
                trn.sourceID = fitIDInt
            }

            // Handle transfer detection
            if ofxTrn.type == "XFER" {
                trn.isTransfer = true
                trn.transactionType = OFXTransactionType.xfer.rawValue
            }

            // Resolve or create payee from name
            if let name = ofxTrn.name, !name.isEmpty {
                trn.payee = findOrCreatePayee(name: name)
            }

            added += 1
        }

        return (added, skipped)
    }

    /// Import investment transactions
    private func importInvestmentTransactions(
        _ transactions: [OFXInvestmentTransaction],
        into account: Account
    ) -> (added: Int, skipped: Int) {
        let existingFITIDs = fetchExistingFITIDs(for: account)
        var added = 0, skipped = 0

        for ofxInv in transactions {
            if !ofxInv.fitID.isEmpty && existingFITIDs.contains(ofxInv.fitID) {
                skipped += 1
                continue
            }

            let trn = Transaction(context: context)
            trn.date = ofxInv.tradeDate ?? Date()
            trn.amount = NSDecimalNumber(decimal: ofxInv.total)
            trn.clearedStatus = ClearedStatus.cleared.rawValue
            trn.sourceType = TransactionSourceType.ofxImport.rawValue
            trn.account = account

            if let fitIDInt = Int32(ofxInv.fitID) {
                trn.sourceID = fitIDInt
            }

            // Map investment type
            let mapped = mapInvestmentType(ofxInv.type)
            trn.transactionType = mapped.rawValue

            // Map income type
            if let incType = ofxInv.incomeType {
                trn.incomeType = incType.lowercased()
            }

            // Resolve security
            if !ofxInv.securityID.isEmpty {
                trn.security = findOrCreateSecurity(
                    identifier: ofxInv.securityID,
                    idType: ofxInv.securityIDType
                )
            }

            // Create investment detail
            if ofxInv.units != 0 || ofxInv.unitPrice != 0 {
                let detail = InvestmentDetail(context: context)
                detail.quantity = ofxInv.units
                detail.price = ofxInv.unitPrice
                detail.commission = NSDecimalNumber(decimal: ofxInv.commission)
                detail.transaction = trn
            }

            added += 1
        }

        return (added, skipped)
    }

    // MARK: - Deduplication

    /// Fetch all FITIDs already in the account (from sourceID and transferGroupID)
    private func fetchExistingFITIDs(for account: Account) -> Set<String> {
        let transactions = (account.transactions as? Set<Transaction>) ?? []
        var fitIDs = Set<String>()
        for trn in transactions {
            if trn.sourceID != 0 {
                fitIDs.insert(String(trn.sourceID))
            }
        }
        return fitIDs
    }

    // MARK: - Entity Resolution

    private func findOrCreatePayee(name: String) -> Payee {
        let request = Payee.fetchRequest()
        request.predicate = NSPredicate(format: "name ==[cd] %@", name)
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request))?.first {
            return existing
        }

        let payee = Payee(context: context)
        payee.name = name
        return payee
    }

    private func findOrCreateSecurity(identifier: String, idType: String) -> Security {
        // Try matching by symbol first
        let request = Security.fetchRequest()
        request.predicate = NSPredicate(format: "symbol ==[cd] %@", identifier)
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request))?.first {
            return existing
        }

        let security = Security(context: context)
        security.symbol = identifier
        security.name = identifier
        security.securityType = OFXSecurityType.other.rawValue
        return security
    }

    // MARK: - Type Mapping

    private func mapOFXAccountType(_ ofxType: String) -> OFXAccountType {
        switch ofxType.uppercased() {
        case "CHECKING":   return .checking
        case "SAVINGS":    return .savings
        case "MONEYMRKT":  return .moneyMarket
        case "CREDITLINE": return .creditCard
        case "CD":         return .cd
        default:           return .checking
        }
    }

    private func mapOFXTrnType(_ type: String) -> OFXTransactionType {
        switch type.uppercased() {
        case "DEBIT", "CHECK", "PAYMENT", "FEE", "SRVCHG", "ATM", "POS", "REPEATPMT":
            return .debit
        case "CREDIT", "DEP", "DIRECTDEP", "INT", "DIV":
            return .credit
        case "XFER":
            return .xfer
        default:
            return .debit
        }
    }

    private func mapInvestmentType(_ type: String) -> OFXTransactionType {
        switch type.uppercased() {
        case "BUYSTOCK", "BUYDEBT", "BUYMF", "BUYOPT", "BUYOTHER":
            return .buy
        case "SELLSTOCK", "SELLDEBT", "SELLMF", "SELLOPT", "SELLOTHER":
            return .sell
        case "INCOME":
            return .income
        case "REINVEST":
            return .reinvest
        default:
            return .buy
        }
    }
}

// MARK: - Import Result

struct ImportResult {
    var accountsProcessed = 0
    var transactionsImported = 0
    var transactionsSkipped = 0

    var summary: String {
        var parts: [String] = []
        parts.append("\(accountsProcessed) account\(accountsProcessed == 1 ? "" : "s")")
        parts.append("\(transactionsImported) imported")
        if transactionsSkipped > 0 {
            parts.append("\(transactionsSkipped) duplicates skipped")
        }
        return parts.joined(separator: ", ")
    }
}

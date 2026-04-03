import Foundation
import CoreData

/// Result summary from an OFX import operation.
struct OFXImportResult: Sendable {
    let accountsCreated: Int
    let accountsSkipped: Int
    let transactionsImported: Int
    let transactionsSkipped: Int
    let securitiesCreated: Int
    let transfersResolved: Int
    let wasCancelled: Bool
}

/// Imports OFX files into Core Data. Supports deduplication and cancellation.
actor OFXImportService {
    private let context: NSManagedObjectContext

    // Lookup tables built during import
    private var accountsByKey: [String: Account] = [:]
    private var securitiesByUniqueId: [String: Security] = [:]
    private var existingFitIds: Set<String> = []

    // Counters for result
    private var acctCreated = 0
    private var acctSkipped = 0
    private var txnImported = 0
    private var txnSkipped = 0
    private var secCreated = 0
    private var transfersResolved = 0

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // MARK: - Public API

    /// Import one or more OFX files. Returns import summary.
    func importFiles(_ urls: [URL]) async throws -> OFXImportResult {
        resetCounters()
        try await loadExistingData()

        for url in urls {
            try Task.checkCancellation()
            let parser = OFXParser()
            let doc = try parser.parse(url: url)
            try await importDocument(doc)
        }

        try await resolveTransfers()
        try await context.perform { try self.context.save() }

        return OFXImportResult(
            accountsCreated: acctCreated,
            accountsSkipped: acctSkipped,
            transactionsImported: txnImported,
            transactionsSkipped: txnSkipped,
            securitiesCreated: secCreated,
            transfersResolved: transfersResolved,
            wasCancelled: false
        )
    }

    /// Import a single pre-parsed OFX document. Saves after completion.
    func importDocument(_ doc: OFXDocument) async throws {
        try await context.perform { [self] in
            try self.importDocumentSync(doc)
        }
    }

    // MARK: - Internal

    private func resetCounters() {
        acctCreated = 0; acctSkipped = 0; txnImported = 0
        txnSkipped = 0; secCreated = 0; transfersResolved = 0
        accountsByKey = [:]; securitiesByUniqueId = [:]; existingFitIds = []
    }

    private func loadExistingData() async throws {
        try await context.perform { [self] in
            // Load existing accounts
            let acctReq = Account.fetchRequest()
            let accounts = try self.context.fetch(acctReq)
            for acct in accounts {
                let key = acct.name ?? "unknown-\(acct.moneyID)"
                self.accountsByKey[key] = acct
            }

            // Load existing securities
            let secReq = Security.fetchRequest()
            let secs = try self.context.fetch(secReq)
            for sec in secs {
                if let symbol = sec.symbol, !symbol.isEmpty {
                    self.securitiesByUniqueId[symbol] = sec
                }
            }

            // Load existing FITIDs for dedup
            let trnReq = Transaction.fetchRequest()
            trnReq.propertiesToFetch = ["checkNumber", "moneyID"]
            let txns = try self.context.fetch(trnReq)
            for txn in txns {
                if let fitId = txn.checkNumber, !fitId.isEmpty {
                    self.existingFitIds.insert(fitId)
                }
            }
        }
    }

    private func importDocumentSync(_ doc: OFXDocument) throws {
        // Import securities first (referenced by investment transactions)
        for secInfo in doc.securities {
            importSecurity(secInfo)
        }

        // Bank statements
        for stmt in doc.bankStatements {
            try Task.checkCancellation()
            let acct = findOrCreateBankAccount(stmt)
            for txn in stmt.transactions {
                importBankTransaction(txn, into: acct)
            }
        }

        // Credit card statements
        for stmt in doc.creditCardStatements {
            try Task.checkCancellation()
            let acct = findOrCreateCCAccount(stmt)
            for txn in stmt.transactions {
                importBankTransaction(txn, into: acct)
            }
        }

        // Investment statements
        for stmt in doc.investmentStatements {
            try Task.checkCancellation()
            let acct = findOrCreateInvAccount(stmt)
            for txn in stmt.transactions {
                importInvestmentTransaction(txn, into: acct)
            }
            for pos in stmt.positions {
                updatePosition(pos)
            }
        }
    }

    // MARK: - Account Creation

    /// Map OFX account type string to Core Data accountType Int32.
    static func coreDataAccountType(ofxType: String) -> Int32 {
        switch ofxType.uppercased() {
        case "CHECKING":  return 0
        case "CREDITLINE", "CREDITCARD": return 1
        case "SAVINGS":   return 2
        case "MONEYMRKT": return 4
        case "CD":        return 8
        default:          return 0
        }
    }

    /// Generate a stable negative moneyID from a string key.
    static func stableMoneyID(_ key: String) -> Int32 {
        var hash: UInt32 = 5381
        for byte in key.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt32(byte)
        }
        return -Int32(hash & 0x7FFFFFFF) - 1
    }

    private func findOrCreateBankAccount(_ stmt: OFXBankStatement) -> Account {
        let key = "BANK:\(stmt.bankId):\(stmt.acctId)"
        if let existing = accountsByKey[key] {
            acctSkipped += 1
            return existing
        }
        let acct = Account(context: context)
        acct.moneyID = Self.stableMoneyID(key)
        acct.name = stmt.acctId
        acct.accountType = Self.coreDataAccountType(ofxType: stmt.acctType)
        acct.openingBalance = NSDecimalNumber.zero
        acct.isClosed = false
        acct.isFavorite = false
        acct.currencyID = 1 // USD

        let fi = findOrCreateFI(name: "Bank \(stmt.bankId)")
        acct.financialInstitution = fi

        accountsByKey[key] = acct
        acctCreated += 1
        return acct
    }

    private func findOrCreateCCAccount(_ stmt: OFXCreditCardStatement) -> Account {
        let key = "CC:\(stmt.acctId)"
        if let existing = accountsByKey[key] {
            acctSkipped += 1
            return existing
        }
        let acct = Account(context: context)
        acct.moneyID = Self.stableMoneyID(key)
        acct.name = stmt.acctId
        acct.accountType = 1
        acct.openingBalance = NSDecimalNumber.zero
        acct.isClosed = false
        acct.isFavorite = false
        acct.currencyID = 1
        accountsByKey[key] = acct
        acctCreated += 1
        return acct
    }

    private func findOrCreateInvAccount(_ stmt: OFXInvestmentStatement) -> Account {
        let key = "INV:\(stmt.brokerId):\(stmt.acctId)"
        if let existing = accountsByKey[key] {
            acctSkipped += 1
            return existing
        }
        let acct = Account(context: context)
        acct.moneyID = Self.stableMoneyID(key)
        acct.name = stmt.acctId
        acct.accountType = 5
        acct.openingBalance = NSDecimalNumber.zero
        acct.isClosed = false
        acct.isFavorite = false
        acct.currencyID = 1

        let fi = findOrCreateFI(name: stmt.brokerId)
        acct.financialInstitution = fi

        accountsByKey[key] = acct
        acctCreated += 1
        return acct
    }

    private var fiCache: [String: FinancialInstitution] = [:]

    private func findOrCreateFI(name: String) -> FinancialInstitution {
        if let existing = fiCache[name] { return existing }
        let fi = FinancialInstitution(context: context)
        fi.moneyID = Self.stableMoneyID("FI:\(name)")
        fi.name = name
        fiCache[name] = fi
        return fi
    }

    // MARK: - Security Import

    private func importSecurity(_ info: OFXSecurityInfo) {
        let key = info.ticker ?? info.uniqueId
        guard securitiesByUniqueId[key] == nil else { return }

        let sec = Security(context: context)
        sec.moneyID = Self.stableMoneyID("SEC:\(info.uniqueId)")
        sec.name = info.secName
        sec.symbol = info.ticker ?? info.uniqueId
        sec.isHidden = false

        switch info.securityType {
        case "STOCKINFO": sec.securityType = 1
        case "MFINFO":    sec.securityType = 2
        case "DEBTINFO":  sec.securityType = 3
        case "OPTINFO":   sec.securityType = 4
        case "OTHERINFO": sec.securityType = 5
        default:          sec.securityType = 0
        }

        securitiesByUniqueId[key] = sec
        secCreated += 1
    }

    // MARK: - Transaction Import

    /// Dedup key: account moneyID + fitId
    private func dedupKey(acctMoneyID: Int32, fitId: String) -> String {
        "\(acctMoneyID):\(fitId)"
    }

    private func importBankTransaction(_ txn: OFXBankTransaction, into acct: Account) {
        let dk = dedupKey(acctMoneyID: acct.moneyID, fitId: txn.fitId)
        guard !existingFitIds.contains(dk) else {
            txnSkipped += 1
            return
        }

        let t = Transaction(context: context)
        t.moneyID = Self.stableMoneyID(dk)
        t.date = parseOFXDate(txn.dtPosted)
        t.amount = NSDecimalNumber(decimal: txn.amount)
        t.checkNumber = txn.fitId
        t.memo = txn.memo ?? txn.name
        t.account = acct
        t.clearedStatus = 1
        t.actionType = 0

        if txn.trnType == "XFER" {
            t.isTransfer = true
        }

        let payee = findOrCreatePayee(name: txn.name)
        t.payee = payee

        existingFitIds.insert(dk)
        txnImported += 1
    }

    private func importInvestmentTransaction(_ txn: OFXInvestmentTransaction, into acct: Account) {
        let dk = dedupKey(acctMoneyID: acct.moneyID, fitId: txn.fitId)
        guard !existingFitIds.contains(dk) else {
            txnSkipped += 1
            return
        }

        let t = Transaction(context: context)
        t.moneyID = Self.stableMoneyID(dk)
        t.date = parseOFXDate(txn.dtTrade)
        t.account = acct
        t.checkNumber = txn.fitId
        t.clearedStatus = 1

        // Map transaction type to actionType
        switch txn.transactionType {
        case "BUYSTOCK", "BUYMF", "BUYDEBT", "BUYOPT", "BUYOTHER":
            t.actionType = 1
            t.amount = NSDecimalNumber(decimal: txn.total ?? 0)
        case "SELLSTOCK", "SELLMF", "SELLDEBT", "SELLOPT", "SELLOTHER":
            t.actionType = 2
            t.amount = NSDecimalNumber(decimal: txn.total ?? 0)
        case "INCOME", "REINVEST":
            t.actionType = 3
            t.amount = NSDecimalNumber(decimal: txn.total ?? 0)
        case "INVBANKTRAN":
            t.actionType = 0
            t.amount = NSDecimalNumber(decimal: txn.bankTranAmount ?? 0)
            t.memo = txn.bankTranName
            if txn.bankTranType == "XFER" { t.isTransfer = true }
        case "MARGININTEREST":
            t.actionType = 0
            t.amount = NSDecimalNumber(decimal: txn.total ?? 0)
            t.memo = "Margin Interest"
        case "RETOFCAP":
            t.actionType = 3
            t.amount = NSDecimalNumber(decimal: txn.total ?? 0)
            t.memo = "Return of Capital"
        case "SPLIT":
            t.actionType = 0
            t.amount = NSDecimalNumber.zero
            t.memo = "Stock Split \(txn.numerator ?? 1):\(txn.denominator ?? 1)"
        case "TRANSFER":
            t.actionType = 0
            t.amount = NSDecimalNumber.zero
            t.isTransfer = true
            t.memo = "Share Transfer \(txn.transferAction ?? "")"
        case "JRNLSEC":
            t.actionType = 0
            t.amount = NSDecimalNumber.zero
            t.memo = "Journal Securities"
        case "JRNLFUND":
            t.actionType = 0
            t.amount = NSDecimalNumber(decimal: txn.total ?? 0)
            t.memo = "Journal Funds"
        default:
            t.actionType = 0
            t.amount = NSDecimalNumber(decimal: txn.total ?? 0)
        }

        // Link security
        if let secId = txn.securityId {
            t.security = findSecurity(byUniqueId: secId)
        }

        // Create investment detail for buy/sell transactions
        if let units = txn.units, let price = txn.unitPrice,
           ["BUYSTOCK","SELLSTOCK","BUYMF","SELLMF","BUYDEBT","SELLDEBT",
            "BUYOPT","SELLOPT","BUYOTHER","SELLOTHER","REINVEST"].contains(txn.transactionType) {
            let detail = InvestmentDetail(context: context)
            detail.quantity = NSDecimalNumber(decimal: units).doubleValue
            detail.price = NSDecimalNumber(decimal: price).doubleValue
            detail.commission = NSDecimalNumber(decimal: txn.commission ?? 0)
            detail.transaction = t
        }

        existingFitIds.insert(dk)
        txnImported += 1
    }

    // MARK: - Position Updates

    private func updatePosition(_ pos: OFXPosition) {
        guard let sec = findSecurity(byUniqueId: pos.securityId) else { return }
        sec.lastPrice = NSDecimalNumber(decimal: pos.unitPrice).doubleValue
        let date = parseOFXDate(pos.dtPriceAsOf)
        sec.lastPriceDate = date
    }

    // MARK: - Transfer Resolution

    private func resolveTransfers() async throws {
        try await context.perform { [self] in
            let request = Transaction.fetchRequest()
            request.predicate = NSPredicate(format: "isTransfer == YES AND linkedTransactionID == 0")
            let transfers = try self.context.fetch(request)

            var unmatched = transfers
            var matched = Set<NSManagedObjectID>()

            for i in 0..<unmatched.count {
                let t1 = unmatched[i]
                guard !matched.contains(t1.objectID) else { continue }

                for j in (i+1)..<unmatched.count {
                    let t2 = unmatched[j]
                    guard !matched.contains(t2.objectID) else { continue }
                    guard t1.account != t2.account else { continue }

                    let amt1 = (t1.amount ?? .zero).decimalValue
                    let amt2 = (t2.amount ?? .zero).decimalValue
                    guard amt1 + amt2 == 0 || abs(NSDecimalNumber(decimal: amt1 + amt2).doubleValue) < 0.01 else { continue }

                    guard let d1 = t1.date, let d2 = t2.date else { continue }
                    let daysDiff = abs(Calendar.current.dateComponents([.day], from: d1, to: d2).day ?? 999)
                    guard daysDiff <= 3 else { continue }

                    t1.linkedTransactionID = t2.moneyID
                    t2.linkedTransactionID = t1.moneyID
                    t1.linkedAccount = t2.account
                    t2.linkedAccount = t1.account
                    matched.insert(t1.objectID)
                    matched.insert(t2.objectID)
                    self.transfersResolved += 1
                    break
                }
            }
        }
    }

    // MARK: - Helpers

    private var payeeCache: [String: Payee] = [:]

    private func findOrCreatePayee(name: String) -> Payee {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = payeeCache[normalized] { return existing }
        let payee = Payee(context: context)
        payee.moneyID = Self.stableMoneyID("PAY:\(normalized)")
        payee.name = normalized
        payee.isHidden = false
        payeeCache[normalized] = payee
        return payee
    }

    private func findSecurity(byUniqueId uid: String) -> Security? {
        // Try direct lookup first, then scan all entries
        if let sec = securitiesByUniqueId[uid] { return sec }
        for (_, sec) in securitiesByUniqueId {
            if sec.symbol == uid { return sec }
        }
        return nil
    }

    private func parseOFXDate(_ dateStr: String) -> Date {
        let clean = dateStr.components(separatedBy: "[").first ?? dateStr
        let formats = ["yyyyMMddHHmmss", "yyyyMMddHHmmss.SSS", "yyyyMMdd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for fmt in formats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: clean) { return date }
        }
        return Date()
    }
}

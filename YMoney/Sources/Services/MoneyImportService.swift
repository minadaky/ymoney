import Foundation
import CoreData

/// Imports Microsoft Money JSON export data into Core Data
actor MoneyImportService {
    private let context: NSManagedObjectContext

    // Lookup tables built during import
    private var accountsByMoneyID: [Int32: Account] = [:]
    private var categoriesByMoneyID: [Int32: Category] = [:]
    private var payeesByMoneyID: [Int32: Payee] = [:]
    private var securitiesByMoneyID: [Int32: Security] = [:]
    private var transactionsByMoneyID: [Int32: Transaction] = [:]
    private var lotsByMoneyID: [Int32: Lot] = [:]
    // Tracks which Money account IDs are cash companions absorbed into investment accounts
    private var cashCompanionIDs: Set<Int32> = []
    // Maps cash companion Money ID -> parent investment account
    private var cashToInvestmentMap: [Int32: Int32] = [:]
    // Maps Money account ID -> original account ID for reparented transactions
    private var originalAccountIDs: [Int32: Int32] = [:]
    private var fiByMoneyID: [Int32: FinancialInstitution] = [:]

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Import the bundled codekind_export.json file
    func importBundledData() async throws {
        guard let url = Bundle.main.url(forResource: "codekind_export", withExtension: "json") else {
            throw ImportError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ImportError.invalidFormat
        }

        try await context.perform { [self] in
            try self.importAllSync(json: json)
        }
    }

    private func importAllSync(json: [String: Any]) throws {
        // Order matters: import reference data first, then transactional data
        importCurrencies(json["CRNC"] as? [[String: Any]] ?? [])
        importFinancialInstitutions(json["FI"] as? [[String: Any]] ?? [])
        importCategories(json["CAT"] as? [[String: Any]] ?? [])
        importPayees(json["PAY"] as? [[String: Any]] ?? [])
        importSecurities(json["SEC"] as? [[String: Any]] ?? [])
        importAccounts(json["ACCT"] as? [[String: Any]] ?? [])
        importTransactions(json["TRN"] as? [[String: Any]] ?? [])
        importInvestmentDetails(json["TRN_INV"] as? [[String: Any]] ?? [])
        importTransfers(json["TRN_XFER"] as? [[String: Any]] ?? [])
        resolveTransferLinks()
        importLots(json["LOT"] as? [[String: Any]] ?? [])
        importBudgets(json: json)

        try context.save()
    }

    // MARK: - Currencies

    private func importCurrencies(_ rows: [[String: Any]]) {
        for row in rows {
            let currency = Currency(context: context)
            currency.moneyID = intVal(row["hcrnc"])
            currency.name = row["szFull"] as? String
            currency.symbol = row["szSymbol"] as? String
            currency.isoCode = row["szISOCode"] as? String
        }
    }

    // MARK: - Financial Institutions

    private func importFinancialInstitutions(_ rows: [[String: Any]]) {
        for row in rows {
            let fi = FinancialInstitution(context: context)
            fi.moneyID = intVal(row["hfi"])
            fi.name = (row["szFull"] as? String) ?? "Unknown"
            fi.notes = row["mComment"] as? String
            fiByMoneyID[fi.moneyID] = fi
        }
    }

    // MARK: - Categories

    private func importCategories(_ rows: [[String: Any]]) {
        // First pass: create all categories
        for row in rows {
            let cat = Category(context: context)
            cat.moneyID = intVal(row["hcat"])
            cat.fullName = (row["szFull"] as? String) ?? "Unknown"
            cat.level = intVal(row["nLevel"])
            cat.isTaxRelated = boolVal(row["fTax"])
            cat.isBusiness = boolVal(row["fBusiness"])
            cat.isHidden = boolVal(row["fHidden"])
            categoriesByMoneyID[cat.moneyID] = cat
        }

        // Second pass: set parent relationships
        for row in rows {
            let moneyID = intVal(row["hcat"])
            if let parentID = row["hcatParent"] as? Int, parentID > 0 {
                let cat = categoriesByMoneyID[Int32(moneyID)]
                cat?.parent = categoriesByMoneyID[Int32(parentID)]
            }
        }
    }

    // MARK: - Payees

    private func importPayees(_ rows: [[String: Any]]) {
        for row in rows {
            let payee = Payee(context: context)
            payee.moneyID = intVal(row["hpay"])
            payee.name = (row["szFull"] as? String) ?? "Unknown"
            payee.isHidden = boolVal(row["fHidden"])
            payeesByMoneyID[payee.moneyID] = payee
        }
    }

    // MARK: - Securities

    private func importSecurities(_ rows: [[String: Any]]) {
        for row in rows {
            let sec = Security(context: context)
            sec.moneyID = intVal(row["hsec"])
            sec.name = (row["szFull"] as? String) ?? "Unknown"
            sec.symbol = row["szSymbol"] as? String
            sec.exchange = row["szExchg"] as? String
            sec.securityType = intVal(row["sct"])
            sec.isHidden = boolVal(row["fHidden"])
            securitiesByMoneyID[sec.moneyID] = sec
        }
    }

    // MARK: - Accounts

    private func importAccounts(_ rows: [[String: Any]]) {
        // First pass: identify cash companion accounts (hacctRel links them)
        for row in rows {
            let moneyID = intVal(row["hacct"])
            let relatedID = intVal(row["hacctRel"])
            let accountType = intVal(row["at"])

            // If this is a non-investment account that is related to another account,
            // check if the related account is an investment account
            if accountType != 5 && relatedID > 0 {
                // Find the related account in the raw data
                let relatedRow = rows.first { intVal($0["hacct"]) == relatedID }
                let relatedType = intVal(relatedRow?["at"])
                if relatedType == 5 {
                    // This is a cash companion to an investment account
                    cashCompanionIDs.insert(moneyID)
                    cashToInvestmentMap[moneyID] = relatedID
                }
            }
        }

        // Second pass: create accounts, skip cash companions
        for row in rows {
            let moneyID = intVal(row["hacct"])

            // Skip cash companion accounts — their transactions will be merged
            if cashCompanionIDs.contains(moneyID) {
                continue
            }

            let acct = Account(context: context)
            acct.moneyID = moneyID
            acct.name = (row["szFull"] as? String) ?? "Unknown"
            acct.accountType = intVal(row["at"])
            acct.isClosed = boolVal(row["fClosed"])
            acct.isFavorite = boolVal(row["fFavorite"])
            acct.notes = row["mComment"] as? String
            acct.openDate = Date.fromMoneyString(row["dtOpen"] as? String)
            acct.openingBalance = decimalVal(row["amtOpen"])
            acct.currencyID = intVal(row["hcrnc"])
            acct.groupType = intVal(row["grp"])

            // Record if this investment account has a cash companion
            let relatedID = intVal(row["hacctRel"])
            if acct.accountType == 5 && relatedID > 0 && cashCompanionIDs.contains(relatedID) {
                acct.cashCompanionMoneyID = relatedID
            }

            // Link financial institution
            let fiID = intVal(row["hfi"])
            if fiID > 0 {
                acct.financialInstitution = fiByMoneyID[fiID]
            }

            accountsByMoneyID[acct.moneyID] = acct
        }

        // Also map cash companion IDs to the investment account object
        for (cashID, investID) in cashToInvestmentMap {
            if let investAcct = accountsByMoneyID[investID] {
                accountsByMoneyID[cashID] = investAcct
            }
        }
    }

    // MARK: - Transactions

    private func importTransactions(_ rows: [[String: Any]]) {
        for row in rows {
            let trn = Transaction(context: context)
            trn.moneyID = intVal(row["htrn"])
            trn.date = Date.fromMoneyString(row["dt"] as? String) ?? Date()
            trn.amount = decimalVal(row["amt"])
            trn.memo = row["mMemo"] as? String
            trn.checkNumber = row["szId"] as? String
            trn.clearedStatus = intVal(row["cs"])
            trn.actionType = intVal(row["act"])
            trn.transactionFlags = intVal(row["grftt"])

            // Determine the original Money account ID for this transaction
            let rawAcctID = intVal(row["hacct"])

            // If this transaction belongs to a cash companion, mark it
            if cashCompanionIDs.contains(rawAcctID) {
                trn.isCashLeg = true
            }

            // The accountsByMoneyID map already redirects cash companion IDs
            // to the parent investment account
            trn.account = accountsByMoneyID[rawAcctID]

            // Track original account ID for transfer resolution later
            originalAccountIDs[trn.moneyID] = rawAcctID

            // Link category
            let catID = intVal(row["hcat"])
            if catID > 0 {
                trn.category = categoriesByMoneyID[catID]
            }

            // Link payee
            let payID = intVal(row["lHpay"])
            if payID > 0 {
                trn.payee = payeesByMoneyID[payID]
            }

            // Link security (for investment transactions)
            let secID = intVal(row["hsec"])
            if secID > 0 {
                trn.security = securitiesByMoneyID[secID]
            }

            transactionsByMoneyID[trn.moneyID] = trn
        }
    }

    // MARK: - Investment Details

    private func importInvestmentDetails(_ rows: [[String: Any]]) {
        for row in rows {
            let trnID = intVal(row["htrn"])
            guard let trn = transactionsByMoneyID[trnID] else { continue }

            let detail = InvestmentDetail(context: context)
            detail.price = doubleVal(row["dPrice"])
            detail.quantity = doubleVal(row["qty"])
            detail.commission = decimalVal(row["amtCmn"])
            detail.transaction = trn
        }
    }

    // MARK: - Transfers

    private func importTransfers(_ rows: [[String: Any]]) {
        for row in rows {
            let fromID = intVal(row["htrnFrom"])
            let linkID = intVal(row["htrnLink"])

            guard let fromTrn = transactionsByMoneyID[fromID],
                  let linkTrn = transactionsByMoneyID[linkID] else { continue }

            let fromOrigAcct = originalAccountIDs[fromID] ?? 0
            let linkOrigAcct = originalAccountIDs[linkID] ?? 0

            // Determine if this is an internal transfer (between an investment
            // account and its cash companion — same merged account)
            let fromIsCash = cashCompanionIDs.contains(fromOrigAcct)
            let linkIsCash = cashCompanionIDs.contains(linkOrigAcct)
            let fromParent = cashToInvestmentMap[fromOrigAcct] ?? fromOrigAcct
            let linkParent = cashToInvestmentMap[linkOrigAcct] ?? linkOrigAcct

            let isInternal = fromParent == linkParent

            fromTrn.isTransfer = true
            fromTrn.linkedTransactionID = linkID
            linkTrn.isTransfer = true
            linkTrn.linkedTransactionID = fromID

            if isInternal {
                // Both sides are within the same merged account
                fromTrn.isInternalTransfer = true
                linkTrn.isInternalTransfer = true
            }
        }
    }

    /// After transfers are imported, resolve linkedAccount references
    /// so the UI can deep-link to the other account in a transfer.
    private func resolveTransferLinks() {
        for (_, trn) in transactionsByMoneyID {
            guard trn.isTransfer, trn.linkedTransactionID > 0 else { continue }
            if let linkedTrn = transactionsByMoneyID[trn.linkedTransactionID] {
                // The linked account is the account of the OTHER transaction
                // But since cash companions are merged, use the merged account
                if linkedTrn.account != trn.account {
                    trn.linkedAccount = linkedTrn.account
                }
            }
        }
    }

    // MARK: - Lots

    private func importLots(_ rows: [[String: Any]]) {
        for row in rows {
            let lot = Lot(context: context)
            lot.moneyID = intVal(row["hlot"])
            lot.quantity = doubleVal(row["qty"])
            lot.buyDate = Date.fromMoneyString(row["dtBuy"] as? String)
            lot.sellDate = Date.fromMoneyString(row["dtSell"] as? String)

            let acctID = intVal(row["hacct"])
            lot.account = accountsByMoneyID[acctID]

            let secID = intVal(row["hsec"])
            lot.security = securitiesByMoneyID[secID]

            lotsByMoneyID[lot.moneyID] = lot
        }
    }

    // MARK: - Budgets

    private func importBudgets(json: [String: Any]) {
        let bgtItems = json["BGT_ITM"] as? [[String: Any]] ?? []
        let bgtBuckets = json["BGT_BKT"] as? [[String: Any]] ?? []

        // Build bucket name lookup
        var bucketNames: [Int32: String] = [:]
        for bucket in bgtBuckets {
            let id = intVal(bucket["hbgtbkt"])
            bucketNames[id] = bucket["szFull"] as? String
        }

        for item in bgtItems {
            let bi = BudgetCategory(context: context)
            bi.moneyID = intVal(item["hbgtitm"])
            bi.moneyBgtID = intVal(item["hbgt"])
            bi.name = item["szFull"] as? String
            bi.amountPerPeriod = decimalVal(item["amtPerFrq"])

            // Monthly amounts
            bi.amount1 = decimalVal(item["amt1"])
            bi.amount2 = decimalVal(item["amt2"])
            bi.amount3 = decimalVal(item["amt3"])
            bi.amount4 = decimalVal(item["amt4"])
            bi.amount5 = decimalVal(item["amt5"])
            bi.amount6 = decimalVal(item["amt6"])
            bi.amount7 = decimalVal(item["amt7"])
            bi.amount8 = decimalVal(item["amt8"])
            bi.amount9 = decimalVal(item["amt9"])
            bi.amount10 = decimalVal(item["amt10"])
            bi.amount11 = decimalVal(item["amt11"])
            bi.amount12 = decimalVal(item["amt12"])

            // Link category
            let catID = intVal(item["hcat"])
            if catID > 0 {
                bi.category = categoriesByMoneyID[catID]
            }

            // Bucket name
            let bucketID = intVal(item["hbgtbkt"])
            bi.bucketName = bucketNames[bucketID]
        }
    }

    // MARK: - Helpers

    private func intVal(_ val: Any?) -> Int32 {
        if let i = val as? Int { return Int32(i) }
        if let d = val as? Double { return Int32(d) }
        return 0
    }

    private func doubleVal(_ val: Any?) -> Double {
        if let d = val as? Double { return d }
        if let i = val as? Int { return Double(i) }
        return 0.0
    }

    private func boolVal(_ val: Any?) -> Bool {
        if let b = val as? Bool { return b }
        if let i = val as? Int { return i != 0 }
        return false
    }

    private func decimalVal(_ val: Any?) -> NSDecimalNumber {
        if let d = val as? Double { return NSDecimalNumber(value: d) }
        if let i = val as? Int { return NSDecimalNumber(value: i) }
        return NSDecimalNumber.zero
    }
}

enum ImportError: LocalizedError {
    case fileNotFound
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .fileNotFound: return "Could not find bundled Money data file"
        case .invalidFormat: return "Invalid Money data format"
        }
    }
}

import Foundation
import CoreData

/// Imports Microsoft Money JSON export data into Core Data
actor MoneyImportService {
    private let context: NSManagedObjectContext

    // Lookup tables built during import
    private var accountsBySourceID: [Int32: Account] = [:]
    private var categoriesBySourceID: [Int32: Category] = [:]
    private var payeesBySourceID: [Int32: Payee] = [:]
    private var securitiesBySourceID: [Int32: Security] = [:]
    private var transactionsBySourceID: [Int32: Transaction] = [:]
    private var lotsBySourceID: [Int32: Lot] = [:]
    // Tracks which Money account IDs are cash companions absorbed into investment accounts
    private var cashCompanionIDs: Set<Int32> = []
    // Maps cash companion Money ID -> parent investment account
    private var cashToInvestmentMap: [Int32: Int32] = [:]
    // Maps Money account ID -> original account ID for reparented transactions
    private var originalAccountIDs: [Int32: Int32] = [:]
    private var fiBySourceID: [Int32: FinancialInstitution] = [:]

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Import the bundled codekind_export.json file
    func importBundledData() async throws {
        guard let url = Bundle.main.url(forResource: "codekind_export", withExtension: "json") else {
            throw ImportError.fileNotFound
        }
        try await importJSON(from: url)
    }

    /// Import a Money JSON export from any file URL
    func importJSON(from url: URL) async throws {
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
            currency.sourceID = intVal(row["hcrnc"])
            currency.name = row["szFull"] as? String
            currency.symbol = row["szSymbol"] as? String
            currency.isoCode = row["szISOCode"] as? String
        }
    }

    // MARK: - Financial Institutions

    private func importFinancialInstitutions(_ rows: [[String: Any]]) {
        for row in rows {
            let fi = FinancialInstitution(context: context)
            fi.sourceID = intVal(row["hfi"])
            fi.name = (row["szFull"] as? String) ?? "Unknown"
            fi.notes = row["mComment"] as? String
            fiBySourceID[fi.sourceID] = fi
        }
    }

    // MARK: - Categories

    private func importCategories(_ rows: [[String: Any]]) {
        // First pass: create all categories
        for row in rows {
            let cat = Category(context: context)
            cat.sourceID = intVal(row["hcat"])
            cat.fullName = (row["szFull"] as? String) ?? "Unknown"
            cat.level = intVal(row["nLevel"])
            cat.isTaxRelated = boolVal(row["fTax"])
            cat.isBusiness = boolVal(row["fBusiness"])
            cat.isHidden = boolVal(row["fHidden"])
            categoriesBySourceID[cat.sourceID] = cat
        }

        // Second pass: set parent relationships
        for row in rows {
            let sourceID = intVal(row["hcat"])
            if let parentID = row["hcatParent"] as? Int, parentID > 0 {
                let cat = categoriesBySourceID[Int32(sourceID)]
                cat?.parent = categoriesBySourceID[Int32(parentID)]
            }
        }
    }

    // MARK: - Payees

    private func importPayees(_ rows: [[String: Any]]) {
        for row in rows {
            let payee = Payee(context: context)
            payee.sourceID = intVal(row["hpay"])
            payee.name = (row["szFull"] as? String) ?? "Unknown"
            payee.isHidden = boolVal(row["fHidden"])
            payeesBySourceID[payee.sourceID] = payee
        }
    }

    // MARK: - Securities

    private func importSecurities(_ rows: [[String: Any]]) {
        for row in rows {
            let sec = Security(context: context)
            sec.sourceID = intVal(row["hsec"])
            sec.name = (row["szFull"] as? String) ?? "Unknown"
            sec.symbol = row["szSymbol"] as? String
            sec.exchange = row["szExchg"] as? String
            sec.securityType = OFXSecurityType.fromMoneyType(intVal(row["sct"])).rawValue
            sec.isHidden = boolVal(row["fHidden"])
            securitiesBySourceID[sec.sourceID] = sec
        }
    }

    // MARK: - Accounts

    private func importAccounts(_ rows: [[String: Any]]) {
        // First pass: identify cash companion accounts (hacctRel links them)
        for row in rows {
            let sourceID = intVal(row["hacct"])
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
                    cashCompanionIDs.insert(sourceID)
                    cashToInvestmentMap[sourceID] = relatedID
                }
            }
        }

        // Second pass: create accounts, skip cash companions
        for row in rows {
            let sourceID = intVal(row["hacct"])

            // Skip cash companion accounts — their transactions will be merged
            if cashCompanionIDs.contains(sourceID) {
                continue
            }

            let acct = Account(context: context)
            acct.sourceID = sourceID
            acct.name = (row["szFull"] as? String) ?? "Unknown"
            acct.accountType = OFXAccountType.fromMoneyType(intVal(row["at"])).rawValue
            acct.isClosed = boolVal(row["fClosed"])
            acct.isFavorite = boolVal(row["fFavorite"])
            acct.notes = row["mComment"] as? String
            acct.openDate = Date.fromMoneyString(row["dtOpen"] as? String)
            acct.openingBalance = decimalVal(row["amtOpen"])
            acct.currencyID = intVal(row["hcrnc"])

            // Record if this investment account has a cash companion
            let relatedID = intVal(row["hacctRel"])
            if acct.ofxAccountType == .investment && relatedID > 0 && cashCompanionIDs.contains(relatedID) {
                acct.hasCashCompanion = true
            }

            // Link financial institution
            let fiID = intVal(row["hfi"])
            if fiID > 0 {
                acct.financialInstitution = fiBySourceID[fiID]
            }

            accountsBySourceID[acct.sourceID] = acct
        }

        // Also map cash companion IDs to the investment account object
        for (cashID, investID) in cashToInvestmentMap {
            if let investAcct = accountsBySourceID[investID] {
                accountsBySourceID[cashID] = investAcct
            }
        }
    }

    // MARK: - Transactions

    /// Top-level Money category IDs that are generic buckets (INCOME=130, EXPENSE=131)
    private static let genericCategoryIDs: Set<Int32> = [130, 131]

    /// Maps Money category IDs to OFX income types
    private static let categoryToIncomeType: [Int32: String] = [
        133: "div",      // Dividends
        134: "int",      // Interest
        135: "cglong",   // Capital Gains (default to long-term)
    ]

    private func importTransactions(_ rows: [[String: Any]]) {
        for row in rows {
            let trn = Transaction(context: context)
            trn.sourceID = intVal(row["htrn"])
            trn.date = Date.fromMoneyString(row["dt"] as? String) ?? Date()
            trn.amount = decimalVal(row["amt"])
            trn.memo = row["mMemo"] as? String
            trn.checkNumber = row["szId"] as? String
            trn.clearedStatus = ClearedStatus.fromMoneyStatus(intVal(row["cs"])).rawValue

            // Map Money action type → OFX transaction type
            let moneyAct = intVal(row["act"])
            let catID = intVal(row["hcat"])
            let hasSecID = intVal(row["hsec"]) > 0
            let mapped = Self.mapTransactionType(moneyAct: moneyAct, catID: catID, hasSecurity: hasSecID, amount: trn.amount)
            trn.transactionType = mapped.type
            trn.incomeType = mapped.incomeType

            // Determine the original Money account ID for this transaction
            let rawAcctID = intVal(row["hacct"])

            // If this transaction belongs to a cash companion, mark it
            if cashCompanionIDs.contains(rawAcctID) {
                trn.isCashLeg = true
            }

            // The accountsBySourceID map already redirects cash companion IDs
            // to the parent investment account
            trn.account = accountsBySourceID[rawAcctID]

            // Track original account ID for transfer resolution later
            originalAccountIDs[trn.sourceID] = rawAcctID

            // Link category — skip generic INCOME/EXPENSE buckets for investment transactions
            if catID > 0 && !Self.genericCategoryIDs.contains(catID) {
                trn.category = categoriesBySourceID[catID]
            } else if catID > 0 && !hasSecID {
                // Non-investment transactions keep their category even if generic
                trn.category = categoriesBySourceID[catID]
            }

            // Link payee
            let payID = intVal(row["lHpay"])
            if payID > 0 {
                trn.payee = payeesBySourceID[payID]
            }

            // Link security (for investment transactions)
            let secID = intVal(row["hsec"])
            if secID > 0 {
                trn.security = securitiesBySourceID[secID]
            }

            transactionsBySourceID[trn.sourceID] = trn
        }
    }

    /// Maps a Money `act` value to our OFX-aligned transaction type and optional income type
    private static func mapTransactionType(
        moneyAct: Int32,
        catID: Int32,
        hasSecurity: Bool,
        amount: NSDecimalNumber?
    ) -> (type: String, incomeType: String?) {
        switch moneyAct {
        case 1:  // Buy
            return ("buy", nil)
        case 2:  // Sell
            return ("sell", nil)
        case 3:  // Dividend
            let income = categoryToIncomeType[catID] ?? "div"
            return ("income", income)
        case 4:  // Interest
            return ("income", "int")
        case 12: // Reinvest
            let income = categoryToIncomeType[catID] ?? "div"
            return ("reinvest", income)
        case 5:  // Transfer
            return ("xfer", nil)
        default:
            // For unknown types, infer from amount sign
            if hasSecurity {
                // Investment account transaction without clear type
                let amt = amount?.doubleValue ?? 0
                return (amt >= 0 ? "credit" : "debit", nil)
            }
            let amt = amount?.doubleValue ?? 0
            return (amt >= 0 ? "credit" : "debit", nil)
        }
    }

    // MARK: - Investment Details

    private func importInvestmentDetails(_ rows: [[String: Any]]) {
        for row in rows {
            let trnID = intVal(row["htrn"])
            guard let trn = transactionsBySourceID[trnID] else { continue }

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

            guard let fromTrn = transactionsBySourceID[fromID],
                  let linkTrn = transactionsBySourceID[linkID] else { continue }

            let fromOrigAcct = originalAccountIDs[fromID] ?? 0
            let linkOrigAcct = originalAccountIDs[linkID] ?? 0

            let fromParent = cashToInvestmentMap[fromOrigAcct] ?? fromOrigAcct
            let linkParent = cashToInvestmentMap[linkOrigAcct] ?? linkOrigAcct

            let isInternal = fromParent == linkParent

            // Both sides share a transferGroupID
            let groupID = UUID().uuidString

            fromTrn.isTransfer = true
            fromTrn.transferGroupID = groupID
            linkTrn.isTransfer = true
            linkTrn.transferGroupID = groupID

            if isInternal {
                fromTrn.isInternalTransfer = true
                linkTrn.isInternalTransfer = true
            }
        }
    }

    /// After transfers are imported, resolve linkedAccount references
    /// so the UI can deep-link to the other account in a transfer.
    private func resolveTransferLinks() {
        // Group transfer transactions by transferGroupID
        var groups: [String: [Transaction]] = [:]
        for (_, trn) in transactionsBySourceID {
            guard trn.isTransfer, let gid = trn.transferGroupID else { continue }
            groups[gid, default: []].append(trn)
        }

        for (_, pair) in groups {
            guard pair.count == 2 else { continue }
            let a = pair[0], b = pair[1]
            if a.account != b.account {
                a.linkedAccount = b.account
                b.linkedAccount = a.account
            }
        }
    }

    // MARK: - Lots

    private func importLots(_ rows: [[String: Any]]) {
        for row in rows {
            let lot = Lot(context: context)
            lot.sourceID = intVal(row["hlot"])
            lot.quantity = doubleVal(row["qty"])
            lot.buyDate = Date.fromMoneyString(row["dtBuy"] as? String)
            lot.sellDate = Date.fromMoneyString(row["dtSell"] as? String)

            let acctID = intVal(row["hacct"])
            lot.account = accountsBySourceID[acctID]

            let secID = intVal(row["hsec"])
            lot.security = securitiesBySourceID[secID]

            lotsBySourceID[lot.sourceID] = lot
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
            bi.sourceID = intVal(item["hbgtitm"])
            bi.sourceBudgetID = intVal(item["hbgt"])
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
                bi.category = categoriesBySourceID[catID]
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

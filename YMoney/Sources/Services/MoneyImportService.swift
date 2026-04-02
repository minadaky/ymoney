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
        for row in rows {
            let acct = Account(context: context)
            acct.moneyID = intVal(row["hacct"])
            acct.name = (row["szFull"] as? String) ?? "Unknown"
            acct.accountType = intVal(row["at"])
            acct.isClosed = boolVal(row["fClosed"])
            acct.isFavorite = boolVal(row["fFavorite"])
            acct.notes = row["mComment"] as? String
            acct.openDate = Date.fromMoneyString(row["dtOpen"] as? String)
            acct.openingBalance = decimalVal(row["amtOpen"])
            acct.currencyID = intVal(row["hcrnc"])
            acct.groupType = intVal(row["grp"])

            // Link financial institution
            let fiID = intVal(row["hfi"])
            if fiID > 0 {
                acct.financialInstitution = fiByMoneyID[fiID]
            }

            accountsByMoneyID[acct.moneyID] = acct
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

            // Link account
            let acctID = intVal(row["hacct"])
            trn.account = accountsByMoneyID[acctID]

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

            if let fromTrn = transactionsByMoneyID[fromID] {
                fromTrn.isTransfer = true
                fromTrn.linkedTransactionID = linkID
            }
            if let linkTrn = transactionsByMoneyID[linkID] {
                linkTrn.isTransfer = true
                linkTrn.linkedTransactionID = fromID
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

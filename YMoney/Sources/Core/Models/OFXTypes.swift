import Foundation

// MARK: - OFX Account Types

/// OFX-standard account types
enum OFXAccountType: String, CaseIterable, Identifiable {
    case checking    = "CHECKING"
    case savings     = "SAVINGS"
    case creditCard  = "CREDITCARD"
    case cash        = "CASH"
    case moneyMarket = "MONEYMRKT"
    case investment  = "INVESTMENT"
    case asset       = "ASSET"
    case liability   = "LIABILITY"
    case cd          = "CD"
    case loan        = "LOAN"
    case retirement401k = "401K"
    case ira         = "IRA"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .checking:    return "Checking"
        case .savings:     return "Savings"
        case .creditCard:  return "Credit Card"
        case .cash:        return "Cash"
        case .moneyMarket: return "Money Market"
        case .investment:  return "Investment"
        case .asset:       return "Asset"
        case .liability:   return "Liability"
        case .cd:          return "CD"
        case .loan:        return "Loan"
        case .retirement401k: return "401(k)"
        case .ira:         return "IRA"
        }
    }

    var icon: String {
        switch self {
        case .checking:    return "building.columns.fill"
        case .savings:     return "banknote.fill"
        case .creditCard:  return "creditcard.fill"
        case .cash:        return "dollarsign.circle.fill"
        case .moneyMarket: return "building.fill"
        case .investment:  return "chart.line.uptrend.xyaxis"
        case .asset:       return "house.fill"
        case .liability:   return "minus.circle.fill"
        case .cd:          return "lock.fill"
        case .loan:        return "percent"
        case .retirement401k: return "briefcase.fill"
        case .ira:         return "heart.fill"
        }
    }

    var color: String {
        switch self {
        case .checking:    return "blue"
        case .savings:     return "teal"
        case .creditCard:  return "orange"
        case .cash:        return "green"
        case .moneyMarket: return "cyan"
        case .investment:  return "purple"
        case .asset:       return "brown"
        case .liability:   return "pink"
        case .cd:          return "indigo"
        case .loan:        return "red"
        case .retirement401k: return "mint"
        case .ira:         return "mint"
        }
    }

    /// OFX ACCTTYPE value for bank statement export
    var ofxBankType: String {
        switch self {
        case .checking, .cash:  return "CHECKING"
        case .savings:          return "SAVINGS"
        case .creditCard:       return "CREDITLINE"
        case .moneyMarket:      return "MONEYMRKT"
        case .cd:               return "CD"
        case .loan, .liability: return "CREDITLINE"
        default:                return "CHECKING"
        }
    }

    var isInvestment: Bool {
        self == .investment || self == .retirement401k || self == .ira
    }

    var isDebt: Bool {
        self == .creditCard || self == .liability || self == .loan
    }

    var isBanking: Bool {
        !isInvestment && !isDebt
    }

    /// Map Microsoft Money `at` field to OFX account type
    static func fromMoneyType(_ moneyAT: Int32) -> OFXAccountType {
        switch moneyAT {
        case 0:  return .checking
        case 1:  return .creditCard
        case 2:  return .savings
        case 3:  return .cash
        case 4:  return .moneyMarket
        case 5:  return .investment
        case 6:  return .asset
        case 7:  return .liability
        case 8:  return .cd
        case 9:  return .loan
        case 10: return .retirement401k
        case 11: return .ira
        default: return .checking
        }
    }
}

// MARK: - OFX Transaction Types

/// OFX-standard transaction types
enum OFXTransactionType: String, CaseIterable, Identifiable {
    case debit    = "debit"
    case credit   = "credit"
    case xfer     = "xfer"
    case buy      = "buy"
    case sell     = "sell"
    case income   = "income"
    case reinvest = "reinvest"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .debit:    return "Withdrawal"
        case .credit:   return "Deposit"
        case .xfer:     return "Transfer"
        case .buy:      return "Buy"
        case .sell:     return "Sell"
        case .income:   return "Investment Income"
        case .reinvest: return "Reinvest"
        }
    }

    func displayName(incomeType: OFXIncomeType?) -> String {
        switch self {
        case .income:
            switch incomeType {
            case .div:     return "Dividend"
            case .int:     return "Interest"
            case .cgshort: return "Short-term Capital Gain"
            case .cglong:  return "Long-term Capital Gain"
            case .misc:    return "Miscellaneous Income"
            case nil:      return "Investment Income"
            }
        case .reinvest:
            switch incomeType {
            case .div:     return "Reinvest Dividend"
            case .int:     return "Reinvest Interest"
            default:       return "Reinvest"
            }
        default:
            return displayName
        }
    }

    var isInvestmentType: Bool {
        self == .buy || self == .sell || self == .income || self == .reinvest
    }
}

// MARK: - OFX Income Types

/// OFX INCOMETYPE values
enum OFXIncomeType: String, CaseIterable, Identifiable {
    case div     = "div"
    case int     = "int"
    case cgshort = "cgshort"
    case cglong  = "cglong"
    case misc    = "misc"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .div:     return "Dividend"
        case .int:     return "Interest"
        case .cgshort: return "Short-term Capital Gain"
        case .cglong:  return "Long-term Capital Gain"
        case .misc:    return "Miscellaneous"
        }
    }
}

// MARK: - OFX Security Types

/// OFX security classification
enum OFXSecurityType: String, CaseIterable, Identifiable {
    case stock      = "STOCK"
    case mutualFund = "MF"
    case bond       = "BOND"
    case option     = "OPTION"
    case other      = "OTHER"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stock:      return "Stock"
        case .mutualFund: return "Mutual Fund"
        case .bond:       return "Bond"
        case .option:     return "Option"
        case .other:      return "Other"
        }
    }

    /// Map Microsoft Money `sct` field to OFX security type
    static func fromMoneyType(_ moneySCT: Int32) -> OFXSecurityType {
        switch moneySCT {
        case 1:  return .stock
        case 2:  return .mutualFund
        case 3:  return .bond
        case 4:  return .option
        default: return .other
        }
    }
}

// MARK: - Cleared Status

/// Transaction cleared/reconciliation status (universal, not Money-specific)
enum ClearedStatus: String, CaseIterable {
    case uncleared   = "uncleared"
    case cleared     = "cleared"
    case reconciled  = "reconciled"

    var displayName: String {
        switch self {
        case .uncleared:  return "Uncleared"
        case .cleared:    return "Cleared"
        case .reconciled: return "Reconciled"
        }
    }

    /// Map Microsoft Money `cs` field to cleared status
    static func fromMoneyStatus(_ cs: Int32) -> ClearedStatus {
        switch cs {
        case 1: return .cleared
        case 2: return .reconciled
        default: return .uncleared
        }
    }
}

// MARK: - Source Type

/// Where a transaction originated
enum TransactionSourceType: Int16 {
    case mnyImport  = 0
    case manual     = 1
    case ofxImport  = 2
}

// MARK: - Core Data Convenience Extensions

extension Account {
    var ofxAccountType: OFXAccountType {
        get { OFXAccountType(rawValue: accountType ?? "CHECKING") ?? .checking }
        set { accountType = newValue.rawValue }
    }
}

extension Transaction {
    var ofxType: OFXTransactionType {
        get { OFXTransactionType(rawValue: transactionType ?? "debit") ?? .debit }
        set { transactionType = newValue.rawValue }
    }

    var ofxIncomeType: OFXIncomeType? {
        get { OFXIncomeType(rawValue: incomeType ?? "") }
        set { incomeType = newValue?.rawValue }
    }

    var ofxClearedStatus: ClearedStatus {
        get { ClearedStatus(rawValue: clearedStatus ?? "uncleared") ?? .uncleared }
        set { clearedStatus = newValue.rawValue }
    }
}

extension Security {
    var ofxSecurityType: OFXSecurityType {
        get { OFXSecurityType(rawValue: securityType ?? "OTHER") ?? .other }
        set { securityType = newValue.rawValue }
    }
}

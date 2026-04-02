import Foundation
import CoreData

/// Exports transactions in OFX 2.0 format compatible with Microsoft Money import
final class OFXExportService {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Export all transactions for a specific account to OFX format
    func exportAccount(_ account: Account) throws -> String {
        let transactions = (account.transactions as? Set<Transaction>)?.sorted {
            ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
        } ?? []

        var ofx = ofxHeader()
        ofx += "<OFX>\n"
        ofx += signOnResponse()

        if account.accountType == 5 {
            ofx += investmentStatementResponse(account: account, transactions: transactions)
        } else {
            ofx += bankStatementResponse(account: account, transactions: transactions)
        }

        ofx += "</OFX>\n"
        return ofx
    }

    /// Export all accounts to a single OFX file
    func exportAll() throws -> String {
        let request = Account.fetchRequest()
        request.predicate = NSPredicate(format: "isClosed == NO")
        let accounts = try context.fetch(request)

        var ofx = ofxHeader()
        ofx += "<OFX>\n"
        ofx += signOnResponse()

        for account in accounts {
            let transactions = (account.transactions as? Set<Transaction>)?.sorted {
                ($0.date ?? .distantPast) < ($1.date ?? .distantPast)
            } ?? []

            // Skip investment accounts (use INVSTMTTRNRS for those)
            if account.accountType == 5 {
                ofx += investmentStatementResponse(account: account, transactions: transactions)
            } else {
                ofx += bankStatementResponse(account: account, transactions: transactions)
            }
        }

        ofx += "</OFX>\n"
        return ofx
    }

    // MARK: - OFX Building

    private func ofxHeader() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <?OFX OFXHEADER="200" VERSION="220" SECURITY="NONE" OLDFILEUID="NONE" NEWFILEUID="NONE"?>

        """
    }

    private func signOnResponse() -> String {
        let now = ofxDate(Date())
        return """
        <SIGNONMSGSRSV1>
        <SONRS>
        <STATUS><CODE>0</CODE><SEVERITY>INFO</SEVERITY></STATUS>
        <DTSERVER>\(now)</DTSERVER>
        <LANGUAGE>ENG</LANGUAGE>
        </SONRS>
        </SIGNONMSGSRSV1>

        """
    }

    private func bankStatementResponse(account: Account, transactions: [Transaction]) -> String {
        let acctType = ofxAccountType(account.accountType)
        let acctID = account.name ?? "UNKNOWN"

        var xml = """
        <BANKMSGSRSV1>
        <STMTTRNRS>
        <TRNUID>0</TRNUID>
        <STATUS><CODE>0</CODE><SEVERITY>INFO</SEVERITY></STATUS>
        <STMTRS>
        <CURDEF>USD</CURDEF>
        <BANKACCTFROM>
        <BANKID>YMoney</BANKID>
        <ACCTID>\(escapeXML(acctID))</ACCTID>
        <ACCTTYPE>\(acctType)</ACCTTYPE>
        </BANKACCTFROM>
        <BANKTRANLIST>

        """

        if let first = transactions.first?.date {
            xml += "<DTSTART>\(ofxDate(first))</DTSTART>\n"
        }
        if let last = transactions.last?.date {
            xml += "<DTEND>\(ofxDate(last))</DTEND>\n"
        }

        for trn in transactions {
            guard let amount = trn.amount, amount != NSDecimalNumber.zero else { continue }
            xml += transactionElement(trn)
        }

        // Calculate balance
        var balance = account.openingBalance ?? .zero
        for trn in transactions {
            balance = balance.adding(trn.amount ?? .zero)
        }

        xml += """
        </BANKTRANLIST>
        <LEDGERBAL>
        <BALAMT>\(balance.stringValue)</BALAMT>
        <DTASOF>\(ofxDate(Date()))</DTASOF>
        </LEDGERBAL>
        </STMTRS>
        </STMTTRNRS>
        </BANKMSGSRSV1>

        """

        return xml
    }

    private func investmentStatementResponse(account: Account, transactions: [Transaction]) -> String {
        let acctID = account.name ?? "UNKNOWN"

        var xml = """
        <INVSTMTMSGSRSV1>
        <INVSTMTTRNRS>
        <TRNUID>0</TRNUID>
        <STATUS><CODE>0</CODE><SEVERITY>INFO</SEVERITY></STATUS>
        <INVSTMTRS>
        <DTASOF>\(ofxDate(Date()))</DTASOF>
        <CURDEF>USD</CURDEF>
        <INVACCTFROM>
        <BROKERID>YMoney</BROKERID>
        <ACCTID>\(escapeXML(acctID))</ACCTID>
        </INVACCTFROM>
        <INVTRANLIST>

        """

        for trn in transactions {
            guard let detail = trn.investmentDetail else {
                // Non-investment transaction in an investment account
                if let amount = trn.amount, amount != NSDecimalNumber.zero {
                    xml += transactionElement(trn)
                }
                continue
            }

            let symbol = trn.security?.symbol ?? "UNKNOWN"
            let date = ofxDate(trn.date ?? Date())

            switch trn.actionType {
            case 1: // Buy
                xml += """
                <BUYSTOCK>
                <INVBUY>
                <INVTRAN><FITID>\(trn.moneyID)</FITID><DTTRADE>\(date)</DTTRADE></INVTRAN>
                <SECID><UNIQUEID>\(escapeXML(symbol))</UNIQUEID><UNIQUEIDTYPE>TICKER</UNIQUEIDTYPE></SECID>
                <UNITS>\(detail.quantity)</UNITS>
                <UNITPRICE>\(detail.price)</UNITPRICE>
                <TOTAL>\(trn.amount?.stringValue ?? "0")</TOTAL>
                <SUBACCTSEC>OTHER</SUBACCTSEC>
                <SUBACCTFUND>OTHER</SUBACCTFUND>
                </INVBUY>
                <BUYTYPE>BUY</BUYTYPE>
                </BUYSTOCK>

                """

            case 2: // Sell
                xml += """
                <SELLSTOCK>
                <INVSELL>
                <INVTRAN><FITID>\(trn.moneyID)</FITID><DTTRADE>\(date)</DTTRADE></INVTRAN>
                <SECID><UNIQUEID>\(escapeXML(symbol))</UNIQUEID><UNIQUEIDTYPE>TICKER</UNIQUEIDTYPE></SECID>
                <UNITS>\(detail.quantity)</UNITS>
                <UNITPRICE>\(detail.price)</UNITPRICE>
                <TOTAL>\(trn.amount?.stringValue ?? "0")</TOTAL>
                <SUBACCTSEC>OTHER</SUBACCTSEC>
                <SUBACCTFUND>OTHER</SUBACCTFUND>
                </INVSELL>
                <SELLTYPE>SELL</SELLTYPE>
                </SELLSTOCK>

                """

            case 3: // Dividend
                xml += """
                <INCOME>
                <INVTRAN><FITID>\(trn.moneyID)</FITID><DTTRADE>\(date)</DTTRADE></INVTRAN>
                <SECID><UNIQUEID>\(escapeXML(symbol))</UNIQUEID><UNIQUEIDTYPE>TICKER</UNIQUEIDTYPE></SECID>
                <INCOMETYPE>DIV</INCOMETYPE>
                <TOTAL>\(trn.amount?.stringValue ?? "0")</TOTAL>
                <SUBACCTSEC>OTHER</SUBACCTSEC>
                <SUBACCTFUND>OTHER</SUBACCTFUND>
                </INCOME>

                """

            default:
                break
            }
        }

        xml += """
        </INVTRANLIST>
        </INVSTMTRS>
        </INVSTMTTRNRS>
        </INVSTMTMSGSRSV1>

        """

        return xml
    }

    private func transactionElement(_ trn: Transaction) -> String {
        let amount = trn.amount ?? .zero
        let trnType = amount.doubleValue >= 0 ? "CREDIT" : "DEBIT"
        let date = ofxDate(trn.date ?? Date())
        let name = trn.payee?.name ?? trn.category?.fullName ?? "Transaction"

        return """
        <STMTTRN>
        <TRNTYPE>\(trnType)</TRNTYPE>
        <DTPOSTED>\(date)</DTPOSTED>
        <TRNAMT>\(amount.stringValue)</TRNAMT>
        <FITID>\(trn.moneyID)</FITID>
        <NAME>\(escapeXML(name))</NAME>
        \(trn.memo != nil ? "<MEMO>\(escapeXML(trn.memo!))</MEMO>" : "")
        \(trn.checkNumber != nil ? "<CHECKNUM>\(escapeXML(trn.checkNumber!))</CHECKNUM>" : "")
        </STMTTRN>

        """
    }

    // MARK: - Helpers

    private func ofxDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private func ofxAccountType(_ type: Int32) -> String {
        switch type {
        case 0: return "CHECKING"
        case 1: return "SAVINGS"
        case 2: return "CREDITLINE"
        case 3: return "CHECKING"
        default: return "CHECKING"
        }
    }

    private func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

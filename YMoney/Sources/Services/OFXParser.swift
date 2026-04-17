import Foundation

// MARK: - Parsed OFX Model

/// Top-level result of parsing an OFX file
struct OFXDocument {
    var bankStatements: [OFXBankStatement] = []
    var creditCardStatements: [OFXCreditCardStatement] = []
    var investmentStatements: [OFXInvestmentStatement] = []
}

struct OFXBankStatement {
    var bankID: String = ""
    var accountID: String = ""
    var accountType: String = "CHECKING"
    var currency: String = "USD"
    var transactions: [OFXTransaction] = []
    var ledgerBalance: Decimal?
    var balanceDate: Date?
}

struct OFXCreditCardStatement {
    var accountID: String = ""
    var currency: String = "USD"
    var transactions: [OFXTransaction] = []
    var ledgerBalance: Decimal?
    var balanceDate: Date?
}

struct OFXInvestmentStatement {
    var brokerID: String = ""
    var accountID: String = ""
    var currency: String = "USD"
    var bankTransactions: [OFXTransaction] = []
    var investmentTransactions: [OFXInvestmentTransaction] = []
}

struct OFXTransaction {
    var type: String = "DEBIT"    // DEBIT, CREDIT, XFER, CHECK, etc.
    var datePosted: Date?
    var amount: Decimal = 0
    var fitID: String = ""
    var name: String?
    var memo: String?
    var checkNumber: String?
}

struct OFXInvestmentTransaction {
    var type: String               // BUYSTOCK, SELLSTOCK, INCOME, REINVEST, BUYDEBT, BUYMF, etc.
    var fitID: String = ""
    var tradeDate: Date?
    var securityID: String = ""
    var securityIDType: String = "TICKER"
    var units: Double = 0
    var unitPrice: Double = 0
    var total: Decimal = 0
    var commission: Decimal = 0
    var incomeType: String?        // DIV, INT, CGSHORT, CGLONG, MISC
    var buyType: String?           // BUY, BUYTOCOVER
    var sellType: String?          // SELL, SELLSHORT
}

// MARK: - OFX Parser

/// Parses OFX files in both SGML (1.x) and XML (2.x) formats
final class OFXParser {

    /// Parse an OFX file from a URL
    static func parse(url: URL) throws -> OFXDocument {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .ascii) else {
            throw OFXParseError.encodingError
        }
        return try parse(text: text)
    }

    /// Parse an OFX string
    static func parse(text: String) throws -> OFXDocument {
        // Strip OFX headers (everything before <OFX>)
        guard let ofxStart = text.range(of: "<OFX>", options: .caseInsensitive) else {
            throw OFXParseError.noOFXElement
        }

        let body = String(text[ofxStart.lowerBound...])

        // Normalize SGML to XML: add closing tags to leaf elements
        let normalized = normalizeSGML(body)

        // Parse as XML
        let root = try parseXML(normalized)

        return buildDocument(from: root)
    }

    // MARK: - SGML Normalization

    /// Convert OFX SGML (unclosed leaf tags) to valid XML
    private static func normalizeSGML(_ input: String) -> String {
        var result = ""
        var i = input.startIndex

        while i < input.endIndex {
            if input[i] == "<" {
                // Find end of tag
                guard let closeAngle = input[input.index(after: i)...].firstIndex(of: ">") else {
                    result.append(input[i])
                    i = input.index(after: i)
                    continue
                }

                let tagContent = String(input[input.index(after: i)..<closeAngle])
                let fullTag = String(input[i...closeAngle])

                if tagContent.hasPrefix("/") {
                    // Closing tag — pass through
                    result += fullTag
                } else {
                    // Opening tag
                    let tagName = tagContent.split(separator: " ").first.map(String.init) ?? tagContent
                    result += fullTag

                    // Look ahead: if next non-whitespace is NOT "<", this is a leaf element
                    let afterTag = input.index(after: closeAngle)
                    if afterTag < input.endIndex {
                        let rest = input[afterTag...]
                        let trimmed = rest.drop(while: { $0 == "\r" || $0 == "\n" })
                        if !trimmed.isEmpty && trimmed.first != "<" {
                            // Leaf element — find value (up to next newline or <)
                            if let valueEnd = trimmed.firstIndex(where: { $0 == "<" || $0 == "\r" || $0 == "\n" }) {
                                let value = String(trimmed[trimmed.startIndex..<valueEnd]).trimmingCharacters(in: .whitespaces)
                                result += value
                                result += "</\(tagName)>"
                                i = valueEnd
                                continue
                            } else {
                                // Value extends to end of input
                                let value = String(trimmed).trimmingCharacters(in: .whitespaces)
                                result += value
                                result += "</\(tagName)>"
                                i = input.endIndex
                                continue
                            }
                        }
                    }
                }

                i = input.index(after: closeAngle)
            } else {
                result.append(input[i])
                i = input.index(after: i)
            }
        }

        return result
    }

    // MARK: - XML Parsing

    private static func parseXML(_ xml: String) throws -> XMLNode {
        guard let data = xml.data(using: .utf8) else {
            throw OFXParseError.encodingError
        }

        let delegate = OFXXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        guard let root = delegate.root else {
            throw OFXParseError.parseError(delegate.parseError?.localizedDescription ?? "Unknown parse error")
        }
        return root
    }

    // MARK: - Document Building

    private static func buildDocument(from root: XMLNode) -> OFXDocument {
        var doc = OFXDocument()

        // Bank statements
        if let bankMsgs = root.child("BANKMSGSRSV1") {
            for stmtTrnRs in bankMsgs.children(named: "STMTTRNRS") {
                if let stmtRs = stmtTrnRs.child("STMTRS") {
                    doc.bankStatements.append(parseBankStatement(stmtRs))
                }
            }
        }

        // Credit card statements
        if let ccMsgs = root.child("CREDITCARDMSGSRSV1") {
            for stmtTrnRs in ccMsgs.children(named: "CCSTMTTRNRS") {
                if let stmtRs = stmtTrnRs.child("CCSTMTRS") {
                    doc.creditCardStatements.append(parseCCStatement(stmtRs))
                }
            }
        }

        // Investment statements
        if let invMsgs = root.child("INVSTMTMSGSRSV1") {
            for stmtTrnRs in invMsgs.children(named: "INVSTMTTRNRS") {
                if let stmtRs = stmtTrnRs.child("INVSTMTRS") {
                    doc.investmentStatements.append(parseInvestmentStatement(stmtRs))
                }
            }
        }

        return doc
    }

    private static func parseBankStatement(_ node: XMLNode) -> OFXBankStatement {
        var stmt = OFXBankStatement()
        stmt.currency = node.childValue("CURDEF") ?? "USD"

        if let acctFrom = node.child("BANKACCTFROM") {
            stmt.bankID = acctFrom.childValue("BANKID") ?? ""
            stmt.accountID = acctFrom.childValue("ACCTID") ?? ""
            stmt.accountType = acctFrom.childValue("ACCTTYPE") ?? "CHECKING"
        }

        if let tranList = node.child("BANKTRANLIST") {
            stmt.transactions = parseTransactions(tranList)
        }

        if let ledger = node.child("LEDGERBAL") {
            stmt.ledgerBalance = Decimal(string: ledger.childValue("BALAMT") ?? "")
            stmt.balanceDate = parseOFXDate(ledger.childValue("DTASOF"))
        }

        return stmt
    }

    private static func parseCCStatement(_ node: XMLNode) -> OFXCreditCardStatement {
        var stmt = OFXCreditCardStatement()
        stmt.currency = node.childValue("CURDEF") ?? "USD"

        if let acctFrom = node.child("CCACCTFROM") {
            stmt.accountID = acctFrom.childValue("ACCTID") ?? ""
        }

        if let tranList = node.child("BANKTRANLIST") {
            stmt.transactions = parseTransactions(tranList)
        }

        if let ledger = node.child("LEDGERBAL") {
            stmt.ledgerBalance = Decimal(string: ledger.childValue("BALAMT") ?? "")
            stmt.balanceDate = parseOFXDate(ledger.childValue("DTASOF"))
        }

        return stmt
    }

    private static func parseInvestmentStatement(_ node: XMLNode) -> OFXInvestmentStatement {
        var stmt = OFXInvestmentStatement()
        stmt.currency = node.childValue("CURDEF") ?? "USD"

        if let acctFrom = node.child("INVACCTFROM") {
            stmt.brokerID = acctFrom.childValue("BROKERID") ?? ""
            stmt.accountID = acctFrom.childValue("ACCTID") ?? ""
        }

        if let tranList = node.child("INVTRANLIST") {
            // Bank transactions within investment account
            for stmtTrn in tranList.children(named: "INVBANKTRAN") {
                if let bankTrn = stmtTrn.child("STMTTRN") {
                    stmt.bankTransactions.append(parseSingleTransaction(bankTrn))
                }
            }

            // Investment transactions
            let invTypes = ["BUYSTOCK", "SELLSTOCK", "BUYDEBT", "BUYMF", "BUYOPT", "BUYOTHER",
                            "SELLDEBT", "SELLMF", "SELLOPT", "SELLOTHER",
                            "INCOME", "REINVEST", "TRANSFER"]
            for typeName in invTypes {
                for invNode in tranList.children(named: typeName) {
                    stmt.investmentTransactions.append(parseInvestmentTransaction(invNode, type: typeName))
                }
            }
        }

        return stmt
    }

    private static func parseTransactions(_ tranList: XMLNode) -> [OFXTransaction] {
        tranList.children(named: "STMTTRN").map { parseSingleTransaction($0) }
    }

    private static func parseSingleTransaction(_ node: XMLNode) -> OFXTransaction {
        OFXTransaction(
            type: node.childValue("TRNTYPE") ?? "DEBIT",
            datePosted: parseOFXDate(node.childValue("DTPOSTED")),
            amount: Decimal(string: node.childValue("TRNAMT") ?? "0") ?? 0,
            fitID: node.childValue("FITID") ?? UUID().uuidString,
            name: node.childValue("NAME"),
            memo: node.childValue("MEMO"),
            checkNumber: node.childValue("CHECKNUM")
        )
    }

    private static func parseInvestmentTransaction(_ node: XMLNode, type: String) -> OFXInvestmentTransaction {
        // Buy types nest inside INVBUY, sell types inside INVSELL
        let invBuy = node.child("INVBUY")
        let invSell = node.child("INVSELL")
        let inner = invBuy ?? invSell ?? node

        let invTran = inner.child("INVTRAN") ?? node.child("INVTRAN")
        let secID = inner.child("SECID") ?? node.child("SECID")

        return OFXInvestmentTransaction(
            type: type,
            fitID: invTran?.childValue("FITID") ?? UUID().uuidString,
            tradeDate: parseOFXDate(invTran?.childValue("DTTRADE")),
            securityID: secID?.childValue("UNIQUEID") ?? "",
            securityIDType: secID?.childValue("UNIQUEIDTYPE") ?? "TICKER",
            units: Double(inner.childValue("UNITS") ?? node.childValue("UNITS") ?? "0") ?? 0,
            unitPrice: Double(inner.childValue("UNITPRICE") ?? node.childValue("UNITPRICE") ?? "0") ?? 0,
            total: Decimal(string: inner.childValue("TOTAL") ?? node.childValue("TOTAL") ?? "0") ?? 0,
            commission: Decimal(string: inner.childValue("COMMISSION") ?? "0") ?? 0,
            incomeType: node.childValue("INCOMETYPE"),
            buyType: node.childValue("BUYTYPE"),
            sellType: node.childValue("SELLTYPE")
        )
    }

    // MARK: - Date Parsing

    /// Parse OFX date format: YYYYMMDDHHMMSS[.XXX[:tz]]
    static func parseOFXDate(_ string: String?) -> Date? {
        guard let s = string, !s.isEmpty else { return nil }
        // Take first 8-14 chars (ignore timezone bracket)
        let clean = s.prefix(while: { $0 != "[" && $0 != "." }).prefix(14)
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")

        if clean.count >= 14 {
            fmt.dateFormat = "yyyyMMddHHmmss"
        } else if clean.count >= 8 {
            fmt.dateFormat = "yyyyMMdd"
        } else {
            return nil
        }
        return fmt.date(from: String(clean))
    }
}

// MARK: - XML Node Model

/// Simple tree node for parsed XML
final class XMLNode {
    let name: String
    var value: String = ""
    var children: [XMLNode] = []

    init(name: String) {
        self.name = name
    }

    func child(_ name: String) -> XMLNode? {
        children.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func children(named name: String) -> [XMLNode] {
        children.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    func childValue(_ name: String) -> String? {
        let val = child(name)?.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return val?.isEmpty == true ? nil : val
    }
}

// MARK: - XML Delegate

private final class OFXXMLDelegate: NSObject, XMLParserDelegate {
    var root: XMLNode?
    var parseError: Error?
    private var stack: [XMLNode] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let node = XMLNode(name: elementName)
        if stack.isEmpty {
            root = node
        } else {
            stack.last?.children.append(node)
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.value += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if !stack.isEmpty { stack.removeLast() }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
    }
}

// MARK: - Errors

enum OFXParseError: LocalizedError {
    case encodingError
    case noOFXElement
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .encodingError: return "Could not read file encoding"
        case .noOFXElement: return "No <OFX> element found in file"
        case .parseError(let msg): return "OFX parse error: \(msg)"
        }
    }
}

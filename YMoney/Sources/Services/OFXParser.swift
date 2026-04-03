import Foundation

// MARK: - OFX Document Model

/// Represents a fully parsed OFX document containing all statement types.
struct OFXDocument: Sendable {
    var bankStatements: [OFXBankStatement] = []
    var creditCardStatements: [OFXCreditCardStatement] = []
    var investmentStatements: [OFXInvestmentStatement] = []
    var securities: [OFXSecurityInfo] = []
}

/// A bank account statement (BANKMSGSRSV1 / STMTRS).
struct OFXBankStatement: Sendable {
    let bankId: String
    let acctId: String
    let acctType: String
    let curDef: String
    let transactions: [OFXBankTransaction]
    let ledgerBalance: Decimal
    let availBalance: Decimal?
}

/// A credit card statement (CREDITCARDMSGSRSV1 / CCSTMTRS).
struct OFXCreditCardStatement: Sendable {
    let acctId: String
    let curDef: String
    let transactions: [OFXBankTransaction]
    let ledgerBalance: Decimal
    let availBalance: Decimal?
}

/// A bank or credit card transaction (STMTTRN).
struct OFXBankTransaction: Sendable {
    let trnType: String
    let dtPosted: String
    let amount: Decimal
    let fitId: String
    let name: String
    let memo: String?
    let checkNum: String?
    let refNum: String?
    let sic: String?
}

/// An investment account statement (INVSTMTMSGSRSV1 / INVSTMTRS).
struct OFXInvestmentStatement: Sendable {
    let brokerId: String
    let acctId: String
    let curDef: String
    let dtAsOf: String
    let transactions: [OFXInvestmentTransaction]
    let positions: [OFXPosition]
    let availCash: Decimal
    let marginValue: Decimal
    let shortValue: Decimal
}

/// An investment transaction from INVTRANLIST.
struct OFXInvestmentTransaction: Sendable {
    let transactionType: String
    let fitId: String
    let dtTrade: String
    let dtSettle: String?
    let securityId: String?
    let units: Decimal?
    let unitPrice: Decimal?
    let total: Decimal?
    let commission: Decimal?
    let subAcctSec: String?
    let subAcctFund: String?
    let buyType: String?
    let sellType: String?
    let optBuyType: String?
    let optSellType: String?
    let incomeType: String?
    let transferAction: String?
    let bankTranType: String?
    let bankTranAmount: Decimal?
    let bankTranName: String?
    let oldUnits: Decimal?
    let newUnits: Decimal?
    let numerator: Int?
    let denominator: Int?
    let subAcctFrom: String?
    let subAcctTo: String?
}

/// A position from INVPOSLIST.
struct OFXPosition: Sendable {
    let positionType: String
    let securityId: String
    let units: Decimal
    let unitPrice: Decimal
    let marketValue: Decimal
    let dtPriceAsOf: String
    let memo: String?
}

/// Security information from SECLISTMSGSRSV1.
struct OFXSecurityInfo: Sendable {
    let securityType: String
    let uniqueId: String
    let uniqueIdType: String
    let secName: String
    let ticker: String?
    let stockType: String?
    let mfType: String?
    let parValue: Decimal?
    let debtType: String?
    let dtMaturity: String?
    let couponRate: Decimal?
    let couponFreq: String?
    let optionType: String?
    let strikePrice: Decimal?
    let dtExpire: String?
    let sharesPerContract: Int?
    let underlyingId: String?
    let typeDescription: String?
}

// MARK: - OFX Parse Error

enum OFXParseError: LocalizedError {
    case fileNotFound(URL)
    case emptyFile
    case noOFXContent
    case xmlParseFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url): return "OFX file not found: \(url.lastPathComponent)"
        case .emptyFile: return "OFX file is empty"
        case .noOFXContent: return "No <OFX> tag found in file"
        case .xmlParseFailed(let err): return "XML parse failed: \(err?.localizedDescription ?? "unknown")"
        }
    }
}

// MARK: - OFX Node Tree

/// Intermediate tree node used during XML parsing. Converted to typed models afterwards.
final class OFXNode {
    let name: String
    var text: String = ""
    var children: [OFXNode] = []
    weak var parent: OFXNode?

    init(name: String, parent: OFXNode? = nil) {
        self.name = name
        self.parent = parent
    }

    func child(_ name: String) -> OFXNode? {
        children.first { node in node.name == name }
    }

    func allChildren(_ name: String) -> [OFXNode] {
        children.filter { node in node.name == name }
    }

    var value: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    subscript(_ childName: String) -> String? {
        let v = child(childName)?.value
        return (v?.isEmpty == true) ? nil : v
    }

    func decimal(_ childName: String) -> Decimal? {
        guard let v = self[childName] else { return nil }
        return Decimal(string: v)
    }

    func int(_ childName: String) -> Int? {
        guard let v = self[childName] else { return nil }
        return Int(v)
    }
}

// MARK: - OFX Parser

/// Parses OFX files (both SGML v1.x and XML v2.x) into an ``OFXDocument``.
final class OFXParser: NSObject, XMLParserDelegate {

    private var root = OFXNode(name: "ROOT")
    private var current: OFXNode!
    private var parseError: Error?

    // MARK: Public API

    /// Parse OFX data from a file URL.
    func parse(url: URL) throws -> OFXDocument {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw OFXParseError.fileNotFound(url)
        }
        let data = try Data(contentsOf: url)
        return try parse(data: data)
    }

    /// Parse OFX data from raw bytes.
    func parse(data: Data) throws -> OFXDocument {
        guard !data.isEmpty else { throw OFXParseError.emptyFile }
        let xmlData = preprocessToXML(data)
        root = OFXNode(name: "ROOT")
        current = root
        parseError = nil
        let parser = XMLParser(data: xmlData)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        guard parser.parse() else {
            throw OFXParseError.xmlParseFailed(parser.parserError ?? parseError)
        }
        return buildDocument(from: root)
    }

    // MARK: SGML Preprocessing

    /// Escape `&` that are not part of an XML entity reference.
    private static func escapeUnescapedAmpersands(_ text: String) -> String {
        // Match & not followed by amp; lt; gt; quot; apos; or #
        var result = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "&" {
                let rest = text[i...]
                let alreadyEscaped = rest.hasPrefix("&amp;") || rest.hasPrefix("&lt;")
                    || rest.hasPrefix("&gt;") || rest.hasPrefix("&quot;")
                    || rest.hasPrefix("&apos;") || rest.hasPrefix("&#")
                if alreadyEscaped {
                    result.append("&")
                } else {
                    result.append(contentsOf: "&amp;")
                }
            } else {
                result.append(text[i])
            }
            i = text.index(after: i)
        }
        return result
    }

    private func preprocessToXML(_ rawData: Data) -> Data {
        guard let rawText = String(data: rawData, encoding: .utf8)
                ?? String(data: rawData, encoding: .ascii) else {
            return rawData
        }
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        // OFX XML v2: starts with <?xml — still needs & escaping and <?OFX?> removal
        if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<?XML") {
            var cleaned = rawText
            // Remove <?OFX ...?> processing instruction (NSXMLParser doesn't handle it)
            if let piRange = cleaned.range(of: #"<\?OFX[^?]*\?>"#, options: .regularExpression) {
                cleaned.removeSubrange(piRange)
            }
            // Escape unescaped ampersands in element values
            cleaned = Self.escapeUnescapedAmpersands(cleaned)
            return cleaned.data(using: .utf8) ?? rawData
        }

        // SGML format
        guard rawText.range(of: "<OFX>", options: .caseInsensitive) != nil else {
            return rawData
        }
        var result = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        let lines = rawText.components(separatedBy: .newlines)
        var inOFX = false
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            if t.uppercased().hasPrefix("<OFX") { inOFX = true }
            guard inOFX else { continue }
            if t.hasPrefix("</") || t.hasPrefix("<?") {
                result += t + "\n"
                continue
            }
            if t.hasPrefix("<"), let gtIdx = t.firstIndex(of: ">") {
                let tagName = String(t[t.index(after: t.startIndex)..<gtIdx])
                let afterGt = String(t[t.index(after: gtIdx)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if afterGt.isEmpty || afterGt.hasPrefix("<") {
                    result += t + "\n"
                } else if afterGt.contains("</\(tagName)>") {
                    result += t + "\n"
                } else {
                    let escaped = afterGt
                        .replacingOccurrences(of: "&", with: "&amp;")
                        .replacingOccurrences(of: "&amp;amp;", with: "&amp;")
                    result += "<\(tagName)>\(escaped)</\(tagName)>\n"
                }
            } else {
                result += t + "\n"
            }
        }
        return result.data(using: .utf8) ?? rawData
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let node = OFXNode(name: elementName, parent: current)
        current.children.append(node)
        current = node
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        current.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        current = current.parent ?? root
    }

    func parser(_ parser: XMLParser, parseErrorOccurred error: Error) {
        parseError = error
    }

    // MARK: Tree to Document Conversion

    private func buildDocument(from root: OFXNode) -> OFXDocument {
        var doc = OFXDocument()
        guard let ofx = root.child("OFX") else { return doc }

        // Handle multiple message blocks (mega files have one per account)
        for bankMsgs in ofx.allChildren("BANKMSGSRSV1") {
            for trnRs in bankMsgs.allChildren("STMTTRNRS") {
                if let stmtRs = trnRs.child("STMTRS") {
                    doc.bankStatements.append(parseBankStatement(stmtRs))
                }
            }
        }
        for ccMsgs in ofx.allChildren("CREDITCARDMSGSRSV1") {
            for trnRs in ccMsgs.allChildren("CCSTMTTRNRS") {
                if let stmtRs = trnRs.child("CCSTMTRS") {
                    doc.creditCardStatements.append(parseCCStatement(stmtRs))
                }
            }
        }
        for invMsgs in ofx.allChildren("INVSTMTMSGSRSV1") {
            for trnRs in invMsgs.allChildren("INVSTMTTRNRS") {
                if let stmtRs = trnRs.child("INVSTMTRS") {
                    doc.investmentStatements.append(parseInvStatement(stmtRs))
                }
            }
        }
        // Merge all security lists found
        for secMsgs in ofx.allChildren("SECLISTMSGSRSV1") {
            if let secList = secMsgs.child("SECLIST") {
                doc.securities.append(contentsOf: parseSecurityList(secList))
            }
        }
        return doc
    }

    // MARK: Statement Parsers

    private func parseBankStatement(_ node: OFXNode) -> OFXBankStatement {
        let acctFrom = node.child("BANKACCTFROM")
        let tranList = node.child("BANKTRANLIST")
        let ledger = node.child("LEDGERBAL")
        let avail = node.child("AVAILBAL")
        let txns = tranList?.allChildren("STMTTRN").map { parseBankTxn(node: $0) } ?? []
        return OFXBankStatement(
            bankId: acctFrom?["BANKID"] ?? "",
            acctId: acctFrom?["ACCTID"] ?? "",
            acctType: acctFrom?["ACCTTYPE"] ?? "CHECKING",
            curDef: node["CURDEF"] ?? "USD",
            transactions: txns,
            ledgerBalance: ledger?.decimal("BALAMT") ?? 0,
            availBalance: avail?.decimal("BALAMT")
        )
    }

    private func parseCCStatement(_ node: OFXNode) -> OFXCreditCardStatement {
        let acctFrom = node.child("CCACCTFROM")
        let tranList = node.child("BANKTRANLIST")
        let ledger = node.child("LEDGERBAL")
        let avail = node.child("AVAILBAL")
        let txns = tranList?.allChildren("STMTTRN").map { parseBankTxn(node: $0) } ?? []
        return OFXCreditCardStatement(
            acctId: acctFrom?["ACCTID"] ?? "",
            curDef: node["CURDEF"] ?? "USD",
            transactions: txns,
            ledgerBalance: ledger?.decimal("BALAMT") ?? 0,
            availBalance: avail?.decimal("BALAMT")
        )
    }

    private func parseBankTxn(node: OFXNode) -> OFXBankTransaction {
        OFXBankTransaction(
            trnType: node["TRNTYPE"] ?? "OTHER",
            dtPosted: node["DTPOSTED"] ?? "",
            amount: node.decimal("TRNAMT") ?? 0,
            fitId: node["FITID"] ?? "",
            name: node["NAME"] ?? "",
            memo: node["MEMO"],
            checkNum: node["CHECKNUM"],
            refNum: node["REFNUM"],
            sic: node["SIC"]
        )
    }

    private func parseInvStatement(_ node: OFXNode) -> OFXInvestmentStatement {
        let acctFrom = node.child("INVACCTFROM")
        let tranList = node.child("INVTRANLIST")
        let posList = node.child("INVPOSLIST")
        let invBal = node.child("INVBAL")
        var txns: [OFXInvestmentTransaction] = []
        if let tl = tranList { txns = parseInvestmentTransactions(tl) }
        var positions: [OFXPosition] = []
        if let pl = posList { positions = parsePositions(pl) }
        return OFXInvestmentStatement(
            brokerId: acctFrom?["BROKERID"] ?? "",
            acctId: acctFrom?["ACCTID"] ?? "",
            curDef: node["CURDEF"] ?? "USD",
            dtAsOf: node["DTASOF"] ?? "",
            transactions: txns,
            positions: positions,
            availCash: invBal?.decimal("AVAILCASH") ?? 0,
            marginValue: invBal?.decimal("MARGVAL") ?? 0,
            shortValue: invBal?.decimal("SHORTVAL") ?? 0
        )
    }

    // MARK: Investment Transaction Parsers

    private let invTxnTypes = Set([
        "BUYSTOCK","SELLSTOCK","BUYMF","SELLMF","BUYDEBT","SELLDEBT",
        "BUYOPT","SELLOPT","BUYOTHER","SELLOTHER","INCOME","REINVEST",
        "TRANSFER","INVBANKTRAN","MARGININTEREST","RETOFCAP","SPLIT",
        "JRNLSEC","JRNLFUND"
    ])

    private func parseInvestmentTransactions(_ tranList: OFXNode) -> [OFXInvestmentTransaction] {
        var result: [OFXInvestmentTransaction] = []
        for child in tranList.children where invTxnTypes.contains(child.name) {
            result.append(parseInvTxn(child))
        }
        return result
    }

    private func parseInvTxn(_ node: OFXNode) -> OFXInvestmentTransaction {
        let invBuy = node.child("INVBUY")
        let invSell = node.child("INVSELL")
        let inner = invBuy ?? invSell
        let invTran = inner?.child("INVTRAN") ?? node.child("INVTRAN")
        let secIdNode = inner?.child("SECID") ?? node.child("SECID")
        let stmtTrn = node.child("STMTTRN")
        return OFXInvestmentTransaction(
            transactionType: node.name,
            fitId: invTran?["FITID"] ?? stmtTrn?["FITID"] ?? "",
            dtTrade: invTran?["DTTRADE"] ?? stmtTrn?["DTPOSTED"] ?? "",
            dtSettle: invTran?["DTSETTLE"],
            securityId: secIdNode?["UNIQUEID"],
            units: inner?.decimal("UNITS") ?? node.decimal("UNITS"),
            unitPrice: inner?.decimal("UNITPRICE") ?? node.decimal("UNITPRICE"),
            total: inner?.decimal("TOTAL") ?? node.decimal("TOTAL"),
            commission: inner?.decimal("COMMISSION") ?? node.decimal("COMMISSION"),
            subAcctSec: inner?["SUBACCTSEC"] ?? node["SUBACCTSEC"],
            subAcctFund: inner?["SUBACCTFUND"] ?? node["SUBACCTFUND"],
            buyType: node["BUYTYPE"],
            sellType: node["SELLTYPE"],
            optBuyType: node["OPTBUYTYPE"],
            optSellType: node["OPTSELLTYPE"],
            incomeType: node["INCOMETYPE"],
            transferAction: node["TFERACTION"],
            bankTranType: stmtTrn?["TRNTYPE"],
            bankTranAmount: stmtTrn?.decimal("TRNAMT"),
            bankTranName: stmtTrn?["NAME"],
            oldUnits: node.decimal("OLDUNITS"),
            newUnits: node.decimal("NEWUNITS"),
            numerator: node.int("NUMERATOR"),
            denominator: node.int("DENOMINATOR"),
            subAcctFrom: node["SUBACCTFROM"],
            subAcctTo: node["SUBACCTTO"]
        )
    }

    // MARK: Position Parsers

    private let posTypes = Set(["POSSTOCK","POSMF","POSDEBT","POSOPT","POSOTHER"])

    private func parsePositions(_ posList: OFXNode) -> [OFXPosition] {
        var result: [OFXPosition] = []
        for child in posList.children where posTypes.contains(child.name) {
            let invPos = child.child("INVPOS")
            let secId = invPos?.child("SECID")
            result.append(OFXPosition(
                positionType: child.name,
                securityId: secId?["UNIQUEID"] ?? "",
                units: invPos?.decimal("UNITS") ?? 0,
                unitPrice: invPos?.decimal("UNITPRICE") ?? 0,
                marketValue: invPos?.decimal("MKTVAL") ?? 0,
                dtPriceAsOf: invPos?["DTPRICEASOF"] ?? "",
                memo: invPos?["MEMO"]
            ))
        }
        return result
    }

    // MARK: Security List Parser

    private func parseSecurityList(_ secList: OFXNode) -> [OFXSecurityInfo] {
        var result: [OFXSecurityInfo] = []
        for child in secList.children {
            let secInfo = child.child("SECINFO")
            let secId = secInfo?.child("SECID")
            guard let uid = secId?["UNIQUEID"] else { continue }
            var underlyingId: String?
            if child.name == "OPTINFO" {
                for optChild in child.children where optChild.name == "SECID" {
                    let innerUid = optChild["UNIQUEID"]
                    if innerUid != uid { underlyingId = innerUid; break }
                }
            }
            result.append(OFXSecurityInfo(
                securityType: child.name,
                uniqueId: uid,
                uniqueIdType: secId?["UNIQUEIDTYPE"] ?? "CUSIP",
                secName: secInfo?["SECNAME"] ?? "",
                ticker: secInfo?["TICKER"],
                stockType: child["STOCKTYPE"],
                mfType: child["MFTYPE"],
                parValue: child.decimal("PARVALUE"),
                debtType: child["DEBTTYPE"],
                dtMaturity: child["DTMAT"],
                couponRate: child.decimal("COUPONRT"),
                couponFreq: child["COUPONFREQ"],
                optionType: child["OPTTYPE"],
                strikePrice: child.decimal("STRIKEPRICE"),
                dtExpire: child["DTEXPIRE"],
                sharesPerContract: child.int("SHPERCTRCT"),
                underlyingId: underlyingId,
                typeDescription: child["TYPEDESC"]
            ))
        }
        return result
    }
}

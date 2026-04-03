# YMoney File Import — Implementation Plan

## Overview

Add the ability to import bank-exported CSV, OFX, and QFX files into YMoney.
Real-world bank exports are notoriously non-compliant, so the architecture uses
a **deterministic parser** for the happy path (~90% of data) with **Apple
Intelligence** (`FoundationModels` framework, iOS 26+) as a progressive
enhancement for ambiguous cases. Devices without Apple Intelligence fall back to
a manual column-mapping UI.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                      FileImportCoordinator                   │
│                                                              │
│  1. File picker (UTType: .ofx, .qfx, .commaSeparatedText)   │
│  2. Format detection (extension + magic bytes)               │
│  3. Dispatch to parser                                       │
│                                                              │
│  ┌───────────┐  ┌──────────┐  ┌────────────────────────────┐│
│  │ OFXParser │  │CSVParser │  │ (future: QIF, MT940, etc.) ││
│  │ (SGML+XML)│  │(RFC 4180)│  │                            ││
│  └─────┬─────┘  └────┬─────┘  └────────────────────────────┘│
│        └──────┬───────┘                                      │
│          ┌────▼──────────┐                                   │
│          │ImportedLedger │  (intermediate representation)     │
│          └────┬──────────┘                                   │
│          ┌────▼──────────┐                                   │
│          │ Normalizer    │  dates, amounts, payee cleanup    │
│          └────┬──────────┘                                   │
│     ┌─────────▼─────────────┐                                │
│     │  AI Assist (optional) │  payee normalization,          │
│     │  iOS 26+ only         │  category suggestion,          │
│     │  @Generable structs   │  CSV column auto-detection     │
│     └─────────┬─────────────┘                                │
│          ┌────▼──────────┐                                   │
│          │ Preview UI    │  user reviews before commit       │
│          └────┬──────────┘                                   │
│          ┌────▼──────────┐                                   │
│          │ImportService  │  maps to Core Data, deduplicates  │
│          └───────────────┘                                   │
└──────────────────────────────────────────────────────────────┘
```

---

## Intermediate Representation

All parsers produce the same types. These are plain Swift structs — not Core
Data managed objects — so parsing is fully testable without a persistent store.

```swift
struct ImportedLedger {
    var account: ImportedAccount
    var transactions: [ImportedTransaction]
    var source: ImportSource  // .ofx, .qfx, .csv
}

struct ImportedAccount {
    var bankID: String?           // OFX <BANKID> or <BROKERID>
    var accountID: String?        // OFX <ACCTID>
    var accountType: String?      // OFX <ACCTTYPE> e.g. "CHECKING"
    var name: String?             // derived or user-supplied
    var currencyCode: String?     // OFX <CURDEF>
}

struct ImportedTransaction {
    var fitID: String?            // OFX <FITID> — used for dedup
    var date: Date
    var amount: Decimal
    var payeeName: String?
    var memo: String?
    var checkNumber: String?
    var transactionType: String?  // OFX <TRNTYPE>: DEBIT, CREDIT, etc.
    var confidence: FieldConfidence
}

struct FieldConfidence {
    var date: Float       // 0.0–1.0
    var amount: Float
    var payee: Float
}

enum ImportSource {
    case ofx, qfx, csv
}
```

---

## 1. OFX / QFX Parser

### Why not XMLParser?

OFX 1.x (which most banks still export, and which QFX is based on) uses a
**loose SGML** format:

```
OFXHEADER:100
DATA:OFXSGML
VERSION:102
...
<OFX>
<SIGNONMSGSRSV1>
<SONRS>
<STATUS>
<CODE>0
<SEVERITY>INFO
</STATUS>
```

Tags like `<CODE>0` have **no closing tag**. This is valid SGML but invalid XML.
Apple's `XMLParser` will reject it immediately.

### Parser Design

**`OFXParser`** — a two-phase parser:

1. **Header parser**: reads the plain-text preamble line by line. Extracts:
   - `OFXHEADER` (100 = SGML, 200 = XML)
   - `VERSION` (102/103 = OFX 1.x, 200+ = OFX 2.x)
   - `CHARSET`, `ENCODING`

2. **Body parser**: depends on detected version:
   - **OFX 1.x (SGML)**: custom `SGMLTokenizer` that handles:
     - `<TAG>value` (no closing tag — the value is everything until the next `<`)
     - `<TAG>value</TAG>` (optional closing tag)
     - `<AGGREGATE>` ... `</AGGREGATE>` (nested structure)
     - Whitespace tolerance, mixed line endings
   - **OFX 2.x (XML)**: delegate to Foundation `XMLParser`

**`SGMLTokenizer`** produces a tree of `OFXElement` nodes:

```swift
indirect enum OFXElement {
    case value(tag: String, content: String)
    case aggregate(tag: String, children: [OFXElement])
}
```

**`OFXMapper`** walks the tree and extracts:
- `<BANKMSGSRSV1>` → bank statement with `<STMTTRNRS>` transactions
- `<CREDITCARDMSGSRSV1>` → credit card statement
- `<INVSTMTMSGSRSV1>` → investment statement (future phase)

Each `<STMTTRN>` maps to an `ImportedTransaction`:
- `<FITID>` → `fitID`
- `<DTPOSTED>` → `date` (OFX format: `YYYYMMDD[HHmmss[.XXX]]`)
- `<TRNAMT>` → `amount`
- `<NAME>` → `payeeName`
- `<MEMO>` → `memo`
- `<CHECKNUM>` → `checkNumber`
- `<TRNTYPE>` → `transactionType`

QFX handling: QFX is OFX + Intuit extensions. The parser ignores unknown tags
gracefully (including `<INTU.BID>`, `<INTU.USERID>`, etc.) rather than failing.

### Confidence Scoring

OFX transactions get high confidence (0.95+) since the format is self-describing.
The parser lowers confidence when:
- Date format is ambiguous or missing time component → 0.9
- Payee `<NAME>` looks like a raw bank descriptor → 0.7
- Amount is zero or suspiciously large → 0.8

---

## 2. CSV Parser

### Challenge

CSV has no standard schema for financial data. Every bank uses different:
- Column names (or no header row at all)
- Date formats (`MM/DD/YYYY`, `DD/MM/YYYY`, `YYYY-MM-DD`, etc.)
- Amount conventions (single column with sign, separate debit/credit columns)
- Payee placement (column called "Description", "Payee", "Merchant", etc.)

### Parser Design

**`CSVTokenizer`** — RFC 4180 compliant with tolerance:
- Handles quoted fields with embedded commas/newlines
- Tolerates unquoted fields, mixed line endings (CRLF, LF, CR)
- Detects delimiter (comma, semicolon, tab) by frequency analysis of first 5 rows

**`CSVColumnDetector`** — heuristic column mapping:

```swift
struct CSVColumnMapping {
    var dateColumn: Int
    var amountColumn: Int           // single amount column
    var debitColumn: Int?           // separate debit column (alternative)
    var creditColumn: Int?          // separate credit column (alternative)
    var payeeColumn: Int?
    var memoColumn: Int?
    var checkNumberColumn: Int?
    var categoryColumn: Int?
    var balanceColumn: Int?         // detected but ignored during import
    var confidence: Float
}
```

Detection heuristics (applied to header names + first 10 data rows):
1. **Date column**: header contains "date" (case-insensitive), OR column values
   match a date regex (`\d{1,4}[/\-\.]\d{1,2}[/\-\.]\d{1,4}`)
2. **Amount column**: header contains "amount"/"sum"/"total", OR all values are
   numeric with optional sign/currency symbol. If two numeric columns exist,
   check for "debit"/"credit" headers.
3. **Payee column**: header contains "description"/"payee"/"merchant"/"name",
   OR the longest text column that isn't a date or number.
4. **Memo column**: header contains "memo"/"note"/"reference", OR a second text
   column after payee.
5. **Check number**: header contains "check"/"cheque"/"number".

**Date format detection**: test candidate date strings against common formats:
```
MM/dd/yyyy, dd/MM/yyyy, yyyy-MM-dd, M/d/yyyy, d/M/yyyy,
MM-dd-yyyy, dd-MM-yyyy, yyyy/MM/dd, MMM dd yyyy, dd MMM yyyy
```
Pick the format that parses the most rows successfully. If `MM/dd` and `dd/MM`
are both valid for all rows (ambiguous), set `confidence.date = 0.5`.

### Confidence Scoring

CSV confidence is generally lower than OFX:
- Header row detected + all heuristics match → 0.85
- No header row → 0.6
- Ambiguous date format → 0.5 on date field
- Separate debit/credit detected → 0.9 (less ambiguous than signed amounts)

---

## 3. Import Normalizer

Runs on every `ImportedLedger` regardless of source format.

### Date Normalization
- Strips time components (transactions are date-level granularity in YMoney)
- Validates date is within reasonable range (1970–2100)
- Flags far-future/sentinel dates (like `+10000-02-28` from MS Money)

### Amount Normalization
- Removes currency symbols (`$`, `€`, `£`, etc.)
- Normalizes thousands separators (`,` vs `.` by locale)
- Ensures sign convention: negative = outflow, positive = inflow
- For separate debit/credit columns: debit becomes negative, credit positive

### Payee Normalization (deterministic)
- Strips common bank prefixes: `CHECKCARD`, `POS`, `ACH`, `DEBIT`, `PURCHASE`
- Strips trailing transaction IDs / reference numbers
- Strips city/state suffixes (regex: `\s+[A-Z]{2}\s*\d{5}(-\d{4})?$`)
- Title-cases the result
- Example: `"CHECKCARD 0423 WHOLEFDS MKT #10847 AUSTIN TX"` → `"Wholefds Mkt"`

---

## 4. Apple Intelligence Assist (iOS 26+)

Activated only when `FieldConfidence` is below threshold (0.8) on any field, or
when the user explicitly requests AI help.

### Availability Check

```swift
import FoundationModels

var aiAvailable: Bool {
    if #available(iOS 26, macOS 26, *) {
        return SystemLanguageModel.default.availability == .available
    }
    return false
}
```

### Use Case A: CSV Column Auto-Detection

When heuristic detection has low confidence, ask the model:

```swift
@Generable
struct CSVMapping: Codable {
    @Guide(description: "Zero-based index of the date column")
    var dateColumn: Int
    @Guide(description: "Zero-based index of the amount column, or -1 if split into debit/credit")
    var amountColumn: Int
    @Guide(description: "Zero-based index of the payee/description column")
    var payeeColumn: Int
    @Guide(description: "Zero-based index of the memo column, or -1 if none")
    var memoColumn: Int
}
```

Prompt: system instruction + first 5 rows of the CSV as context.

### Use Case B: Payee Normalization

After deterministic cleanup still leaves a messy payee name:

```swift
@Generable
struct NormalizedPayee: Codable {
    @Guide(description: "Clean, human-readable merchant or payee name")
    var name: String
    @Guide(description: "Suggested spending category")
    var suggestedCategory: String?
}
```

### Use Case C: Date Disambiguation

When the CSV date column is ambiguous (e.g., all values could be MM/DD or DD/MM):

```swift
@Generable
struct DateFormatGuess: Codable {
    @Guide(description: "The date format string, e.g. MM/dd/yyyy or dd/MM/yyyy")
    var format: String
    @Guide(description: "Confidence from 0.0 to 1.0")
    var confidence: Double
}
```

### Fallback

When Apple Intelligence is unavailable, the app shows:
- **CSV**: manual column mapping UI (dropdowns for each column)
- **OFX/QFX**: parsing errors displayed inline with option to skip bad records
- **Payee**: raw payee name used as-is (user can edit after import)

---

## 5. Import Preview & Commit

### Preview UI (`ImportPreviewView`)

Before writing to Core Data, the user sees:
- **Account selection**: match to existing account or create new
- **Transaction list**: scrollable preview with date, payee, amount
- **Flagged items**: rows with low confidence highlighted in yellow
- **Duplicate detection**: transactions matching existing `fitID` or
  (date + amount + payee) shown as "already imported" in gray
- **Stats bar**: "47 new, 3 duplicates, 2 flagged"

### Account Matching

For OFX/QFX: match on `<ACCTID>` against existing `Account.name` or let user
pick from a list.

For CSV: no account metadata exists — user must select or create an account.

### Core Data Mapping (`FileImportService`)

```
ImportedTransaction → Transaction (Core Data)
─────────────────────────────────────────────
fitID              → stored in memo prefix "[FITID:xxx] " for dedup
date               → date
amount             → amount (as NSDecimalNumber)
payeeName          → Payee lookup/create → payee relationship
memo               → memo
checkNumber        → checkNumber
transactionType    → clearedStatus (DEBIT/CREDIT → 0 uncleared)
(n/a)              → moneyID: auto-increment from max existing + 1
(n/a)              → isTransfer: false
(n/a)              → isCashLeg: false
(n/a)              → actionType: nil (not investment)
```

### Payee Resolution

1. Exact match on `Payee.name` → use existing
2. Case-insensitive match → use existing
3. No match → create new `Payee` with auto-assigned `moneyID`

### Duplicate Detection

A transaction is considered duplicate if ANY of:
- Same `fitID` exists in the target account (OFX/QFX only)
- Same (date, amount, payeeName) exists in the target account

Duplicates are shown in preview but excluded from import by default (user can
override).

---

## 6. File Organization

```
YMoney/Sources/
├── Features/
│   └── Import/
│       ├── ImportCoordinatorView.swift    // file picker + format routing
│       ├── ImportPreviewView.swift        // transaction review before commit
│       ├── CSVColumnMappingView.swift     // manual column mapping fallback
│       └── ImportViewModel.swift          // orchestrates parse → preview → commit
│
├── Services/
│   └── Import/
│       ├── Parsing/
│       │   ├── OFXParser.swift            // SGML/XML OFX parser
│       │   ├── SGMLTokenizer.swift        // OFX 1.x SGML tokenizer
│       │   ├── OFXMapper.swift            // OFXElement tree → ImportedLedger
│       │   ├── CSVParser.swift            // RFC 4180 tokenizer
│       │   └── CSVColumnDetector.swift    // heuristic column detection
│       │
│       ├── ImportedLedger.swift           // intermediate representation types
│       ├── ImportNormalizer.swift          // date/amount/payee normalization
│       ├── ImportConfidenceScorer.swift    // per-field confidence scoring
│       ├── FileImportService.swift        // Core Data mapping + dedup
│       └── AIImportAssistant.swift        // Apple Intelligence integration
│
└── Core/
    └── Extensions/
        └── UTType+Finance.swift           // .ofx, .qfx UTType declarations
```

---

## 7. Implementation Order

| # | Task | Depends On |
|---|------|------------|
| 1 | `ImportedLedger.swift` — intermediate types | — |
| 2 | `SGMLTokenizer.swift` — OFX 1.x SGML tokenizer | — |
| 3 | `OFXParser.swift` + `OFXMapper.swift` — full OFX/QFX parsing | 1, 2 |
| 4 | `CSVParser.swift` + `CSVColumnDetector.swift` — CSV parsing | 1 |
| 5 | `ImportNormalizer.swift` — date/amount/payee cleanup | 1 |
| 6 | `UTType+Finance.swift` — file type declarations | — |
| 7 | `FileImportService.swift` — Core Data mapping + dedup | 1, 5 |
| 8 | `ImportPreviewView.swift` + `ImportViewModel.swift` — review UI | 3, 4, 7 |
| 9 | `ImportCoordinatorView.swift` — file picker + routing | 6, 8 |
| 10 | `CSVColumnMappingView.swift` — manual mapping fallback | 4, 8 |
| 11 | `AIImportAssistant.swift` — Apple Intelligence integration | 5, 8 |
| 12 | Tests — sample OFX/QFX/CSV fixtures from real banks | 3, 4 |
| 13 | Navigation integration — add Import to app tab/menu | 9 |

---

## 8. Deployment Target Strategy

| Feature | Minimum OS |
|---------|------------|
| Deterministic parsers, preview UI, manual mapping | iOS 17.0 (current target) |
| Apple Intelligence assist | iOS 26.0 (runtime check) |

```swift
if #available(iOS 26, macOS 26, *) {
    // Show "Auto-detect columns" button, "Clean up payees" option
} else {
    // Show manual column mapping UI only
}
```

No deployment target bump required. AI features are purely additive.

---

## 9. Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| OFX SGML edge cases from specific banks | Ship with a test corpus; add user "report bad file" flow |
| CSV column detection gets it wrong | Always show preview; manual mapping as override |
| Apple Intelligence gives bad payee names | User can edit in preview; AI suggestions are never auto-committed |
| Duplicate detection too aggressive | Show dupes in preview with override toggle |
| `moneyID` collisions with existing MS Money import | Start auto-increment from `max(moneyID) + 10000` |
| Large files (10k+ transactions) | Stream parsing; paginated preview; background Core Data save |

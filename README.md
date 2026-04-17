# YMoney

A modern iOS client for Microsoft Money databases. Read your `.mny` files on iPhone and iPad, browse all your financial data, and export to OFX for Money Sunset Edition compatibility.

## Architecture

- **SwiftUI** + **Core Data** — iOS 17+ / macOS Catalyst
- **Clean Architecture**: Views → ViewModels → Services
- `@Observable` ViewModels, Swift structured concurrency
- `.mny` import via Java Jackcess bridge → JSON → Core Data

## Data Pipeline

The `.mny` format is a proprietary Jet 4.0 database with MSISAM obfuscation — not SQLite. A Java tool (Jackcess + jackcess-encrypt) extracts all 83 tables to JSON, which is bundled in the app and imported into Core Data on first launch.

**Compatibility:**
- **Read:** `.mny` files (Microsoft Money 2000–Sunset Edition)
- **Export:** OFX 2.0 (compatible with Money Sunset Edition import)

## Feature Matrix

Comprehensive comparison against Microsoft Money Plus Sunset Deluxe and Intuit Quicken Classic.

### Accounts & Navigation

| Feature | Money | Quicken | YMoney | Notes |
|---------|:-----:|:-------:|:------:|-------|
| Multiple account types | ✅ | ✅ | ✅ | Checking, Credit Card, Savings, Cash, Money Market, Investment, Asset, Liability, CD, Loan, 401(k), IRA |
| Account grouping by type | ✅ | ✅ | ✅ | Banking, Credit Cards, Investments, Retirement, Loans, Other, Closed |
| Account detail / register | ✅ | ✅ | ✅ | Balance header, searchable transaction list |
| Add / edit / delete accounts | ✅ | ✅ | ❌ | |
| Investment + cash companion merge | ✅ | — | ✅ | Cash accounts absorbed into parent via `hacctRel` |
| Financial institution linking | ✅ | ✅ | ✅ | Imported from .mny |

### Transactions

| Feature | Money | Quicken | YMoney | Notes |
|---------|:-----:|:-------:|:------:|-------|
| Transaction register | ✅ | ✅ | ✅ | Grouped by month, filterable by account |
| Transaction search | ✅ | ✅ | ✅ | Payee, category, memo, account |
| Transaction detail view | ✅ | ✅ | ✅ | Amount, date, payee, category, account, memo, check #, investment detail |
| Add / edit / delete transactions | ✅ | ✅ | ❌ | |
| Split transactions | ✅ | ✅ | ❌ | One payment → multiple categories |
| Scheduled / recurring transactions | ✅ | ✅ | ❌ | Bills, paychecks, auto-payments |
| Transfer tracking | ✅ | ✅ | ✅ | Direction labels, linked account shown inline |
| Transfer deep links | — | — | ✅ | Tap through to source/target account |
| Internal transfer filtering | — | — | ✅ | Investment ↔ cash leg transfers hidden as noise |
| Deposit / withdrawal icons | — | — | ✅ | Green ↓ deposit, red ↑ withdrawal, blue ⇄ transfer |
| Check number tracking | ✅ | ✅ | ✅ | Displayed in detail view |

### Categories & Payees

| Feature | Money | Quicken | YMoney | Notes |
|---------|:-----:|:-------:|:------:|-------|
| Hierarchical category browser | ✅ | ✅ | ✅ | Parent → child → grandchild |
| Tax-related category flags | ✅ | ✅ | ✅ | Shown in category browser |
| Add / edit / delete categories | ✅ | ✅ | ❌ | |
| Payee list with totals | ✅ | ✅ | ✅ | Transaction count + total per payee |
| Payee search | ✅ | ✅ | ✅ | |
| Add / edit / merge / delete payees | ✅ | ✅ | ❌ | |

### Investments

| Feature | Money | Quicken | YMoney | Notes |
|---------|:-----:|:-------:|:------:|-------|
| Portfolio holdings view | ✅ | ✅ | ✅ | Shares per security per account |
| Securities list | ✅ | ✅ | ✅ | Name, symbol, exchange |
| Lot tracking (open / closed) | ✅ | ✅ | ✅ | Buy/sell dates, quantities |
| Investment transactions (buy/sell/dividend) | ✅ | ✅ | ✅ | Action badges, price × quantity |
| All / Investment / Cash filter | — | — | ✅ | Segmented control on investment accounts |
| Investment performance (IRR, ROI) | ✅ | ✅ | ❌ | |
| Cost basis tracking | ✅ | ✅ | ❌ | |
| Asset allocation chart | ✅ | ✅ | ❌ | |
| Manual price updates | ✅ | — | ❌ | |
| Tax lot harvesting report | — | ✅ | ❌ | Quicken Premier+ |

### Budgets

| Feature | Money | Quicken | YMoney | Notes |
|---------|:-----:|:-------:|:------:|-------|
| Budget overview | ✅ | ✅ | ✅ | Budgeted vs spent totals |
| Category budget items with progress bars | ✅ | ✅ | ✅ | Color-coded: green → orange → red |
| Budget grouping by bucket | ✅ | ✅ | ✅ | Debt, transfers, savings, etc. |
| Add / edit budget amounts | ✅ | ✅ | ❌ | |
| Multi-period budgets | ✅ | ✅ | ❌ | Currently only shows current month actuals |

### Reports & Charts

| Feature | Money | Quicken | YMoney | Notes |
|---------|:-----:|:-------:|:------:|-------|
| Income vs expense summary | ✅ | ✅ | ✅ | Total income, expenses, net |
| Spending by category (pie chart) | ✅ | ✅ | ✅ | Swift Charts donut on iOS 17+ |
| Monthly cash flow bars | ✅ | ✅ | ✅ | Income and expense per month |
| Net worth over time | ✅ | ✅ | ❌ | Only current snapshot |
| Date range filtering on reports | ✅ | ✅ | ❌ | |
| Customizable reports | ✅ | ✅ | ❌ | |
| Tax schedule reports | ✅ | ✅ | ❌ | |
| Print / PDF export | ✅ | ✅ | ❌ | |

### Reconciliation & Planning

| Feature | Money | Quicken | YMoney | Notes |
|---------|:-----:|:-------:|:------:|-------|
| Account reconciliation | ✅ | ✅ | ❌ | Match cleared transactions to statement |
| Cash flow forecast | ✅ | ✅ | ❌ | Project future balance from scheduled txns |
| Savings goals | ✅ | ✅ | ❌ | Data imported but no UI |
| Debt reduction planner | ✅ | ✅ | ❌ | Payoff scenarios, interest comparison |
| Retirement / lifetime planner | ❌ | ✅ | ❌ | Quicken exclusive |

### Import & Export

| Feature | Money | Quicken | YMoney | Notes |
|---------|:-----:|:-------:|:------:|-------|
| .mny file import | ✅ | ❌ | ✅ | Read-only via Jackcess bridge |
| QIF import | ✅ | ✅ | ❌ | |
| OFX import | ✅ | ✅ | ❌ | |
| OFX 2.0 export | ✅ | ✅ | ✅ | Per-account or bulk, Money-compatible |
| CSV export | ✅ | ✅ | ❌ | |
| QXF export | — | ✅ | ❌ | |

### Multi-Currency

| Feature | Money | Quicken | YMoney | Notes |
|---------|:-----:|:-------:|:------:|-------|
| Currency definitions | ✅ | ✅ | ✅ | 154 currencies imported |
| Multi-currency transactions | ✅ | ✅ | ❌ | Data imported but not used in UI |
| Exchange rate tracking | ✅ | ✅ | ❌ | |

### Settings & Data

| Feature | Money | Quicken | YMoney | Notes |
|---------|:-----:|:-------:|:------:|-------|
| Data status display | — | — | ✅ | |
| Format support info | — | — | ✅ | |
| Data reset | — | — | ⚠️ | Resets flag but doesn't clear Core Data |

---

**Legend:** ✅ Implemented | ❌ Not yet | ⚠️ Partial / buggy | — Not applicable

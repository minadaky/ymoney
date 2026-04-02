import SwiftUI
import CoreData

/// Filter mode for investment account transactions
enum TransactionFilter: String, CaseIterable {
    case all = "All"
    case investment = "Investment"
    case cash = "Cash"
}

/// Account detail view showing transaction register
struct AccountDetailView: View {
    let account: Account
    @Environment(\.managedObjectContext) private var viewContext

    @State private var transactions: [Transaction] = []
    @State private var balance: NSDecimalNumber = .zero
    @State private var searchText = ""
    @State private var filter: TransactionFilter = .all

    /// Whether this is an investment account with a merged cash companion
    private var isInvestmentAccount: Bool {
        account.accountType == 5 && account.cashCompanionMoneyID > 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Balance header
            VStack(spacing: 4) {
                Text("Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(CurrencyFormatter.format(balance))
                    .font(.title.bold().monospacedDigit())
                    .foregroundColor(CurrencyFormatter.isPositive(balance) ? Color.primary : Color.red)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.ultraThinMaterial)

            // Filter picker for investment accounts
            if isInvestmentAccount {
                Picker("Filter", selection: $filter) {
                    ForEach(TransactionFilter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Transaction register
            List {
                ForEach(filteredTransactions, id: \.objectID) { trn in
                    NavigationLink {
                        TransactionDetailView(transaction: trn)
                    } label: {
                        transactionRow(trn)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search transactions")
        }
        .navigationTitle(account.name ?? "Account")
        .onAppear { loadTransactions() }
    }

    private var filteredTransactions: [Transaction] {
        var result = transactions

        // Apply investment/cash filter
        switch filter {
        case .all:
            // Hide internal transfers (investment ↔ its own cash) — they are noise
            result = result.filter { !$0.isInternalTransfer }
        case .investment:
            result = result.filter { !$0.isCashLeg && !$0.isInternalTransfer }
        case .cash:
            result = result.filter { $0.isCashLeg && !$0.isInternalTransfer }
        }

        // Apply search
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { trn in
                (trn.payee?.name?.lowercased().contains(query) ?? false) ||
                (trn.category?.fullName?.lowercased().contains(query) ?? false) ||
                (trn.memo?.lowercased().contains(query) ?? false) ||
                (trn.linkedAccount?.name?.lowercased().contains(query) ?? false)
            }
        }

        return result
    }

    private func loadTransactions() {
        let txns = (account.transactions as? Set<Transaction>) ?? []
        transactions = txns.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        var bal = account.openingBalance ?? .zero
        for trn in txns {
            bal = bal.adding(trn.amount ?? .zero)
        }
        balance = bal
    }

    private func transactionRow(_ trn: Transaction) -> some View {
        HStack {
            // Leading icon
            transactionIcon(trn)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                // Title
                Text(transactionTitle(trn))
                    .font(.subheadline)
                    .lineLimit(1)

                // Subtitle
                HStack(spacing: 4) {
                    Text(trn.date?.shortDisplay ?? "")
                    if let cat = trn.category?.fullName {
                        Text("·")
                        Text(cat)
                            .lineLimit(1)
                    }
                    if trn.isCashLeg {
                        Text("·")
                        Text("Cash")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Deep link to linked account for transfers
                if trn.isTransfer, let linkedAcct = trn.linkedAccount {
                    NavigationLink {
                        AccountDetailView(account: linkedAcct)
                    } label: {
                        Label(linkedAcct.name ?? "Account", systemImage: "arrow.right.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Text(CurrencyFormatter.format(trn.amount))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(CurrencyFormatter.isPositive(trn.amount) ? .green : .red)
        }
        .padding(.vertical, 2)
    }

    private func transactionIcon(_ trn: Transaction) -> some View {
        Group {
            if trn.investmentDetail != nil {
                Image(systemName: investmentIcon(trn.actionType))
                    .foregroundStyle(.purple)
            } else if trn.isTransfer {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.blue)
            } else if trn.isCashLeg {
                Image(systemName: "dollarsign.circle")
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.gray.opacity(0.3))
            }
        }
    }

    private func transactionTitle(_ trn: Transaction) -> String {
        if let detail = trn.investmentDetail, detail.quantity != 0 {
            let action = investmentActionName(trn.actionType)
            let secName = trn.security?.symbol ?? trn.security?.name ?? ""
            return "\(action) \(secName)"
        }
        if trn.isTransfer, let linked = trn.linkedAccount {
            let direction = (trn.amount?.doubleValue ?? 0) >= 0 ? "from" : "to"
            return "Transfer \(direction) \(linked.name ?? "Account")"
        }
        return trn.payee?.name ?? trn.category?.fullName ?? "Transaction"
    }

    private func investmentIcon(_ actionType: Int32) -> String {
        switch actionType {
        case 1: return "arrow.down.circle.fill"
        case 2: return "arrow.up.circle.fill"
        case 3: return "banknote.fill"
        case 4: return "percent"
        default: return "chart.line.uptrend.xyaxis"
        }
    }

    private func investmentActionName(_ type: Int32) -> String {
        switch type {
        case 1: return "Buy"
        case 2: return "Sell"
        case 3: return "Dividend"
        case 4: return "Interest"
        case 12: return "Reinvest"
        default: return "Trade"
        }
    }
}

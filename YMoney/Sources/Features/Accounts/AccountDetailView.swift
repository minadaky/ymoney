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
    var scrollToTransferGroupID: String? = nil
    @Environment(\.managedObjectContext) private var viewContext

    @State private var transactions: [Transaction] = []
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var filter: TransactionFilter = .all
    @State private var scrollTarget: NSManagedObjectID?

    @State private var showAddTransaction = false

    /// Whether this is an investment account with a merged cash companion
    private var isInvestmentAccount: Bool {
        account.ofxAccountType == .investment && account.hasCashCompanion
    }

    /// Balance computed from the current filter
    private var balance: NSDecimalNumber {
        let opening: NSDecimalNumber
        switch filter {
        case .all, .cash:
            opening = account.openingBalance ?? .zero
        case .investment:
            opening = .zero
        }
        // Sum amounts from the filter-matching transactions (ignoring search text)
        let filtered: [Transaction]
        switch filter {
        case .all:
            filtered = transactions.filter { !$0.isInternalTransfer }
        case .investment:
            filtered = transactions.filter { !$0.isCashLeg && !$0.isInternalTransfer }
        case .cash:
            filtered = transactions.filter { $0.isCashLeg && !$0.isInternalTransfer }
        }
        return filtered.reduce(opening) { $0.adding($1.amount ?? .zero) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // Balance header as list section
                Section {
                    VStack(spacing: 4) {
                        Text("Balance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(CurrencyFormatter.format(balance))
                            .font(.title.bold().monospacedDigit())
                            .foregroundColor(CurrencyFormatter.isPositive(balance) ? Color.primary : Color.red)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)

                    // Filter picker for investment accounts
                    if isInvestmentAccount {
                        Picker("Filter", selection: $filter) {
                            ForEach(TransactionFilter.allCases, id: \.self) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                }

                // Transaction register
                Section {
                    ForEach(filteredTransactions, id: \.objectID) { trn in
                        NavigationLink {
                            TransactionDetailView(transaction: trn)
                        } label: {
                            transactionRow(trn)
                        }
                        .id(trn.objectID)
                        .listRowBackground(
                            trn.objectID == scrollTarget
                                ? Color.blue.opacity(0.15)
                                : nil
                        )
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search transactions")
            .onChange(of: scrollTarget) { _, target in
                if let target {
                    withAnimation {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
        .navigationTitle(account.name ?? "Account")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddTransaction = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddTransaction) {
            TransactionEditorView(transaction: nil, preselectedAccount: account)
        }
        .onAppear { loadTransactions() }
        .onChange(of: showAddTransaction) { _, isPresented in
            if !isPresented { loadTransactions() }
        }
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

        // Resolve scroll target from transferGroupID
        if let gid = scrollToTransferGroupID {
            let match = transactions.first { $0.transferGroupID == gid }
            scrollTarget = match?.objectID
        }
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
                    if trn.isTransfer, let linkedAcct = trn.linkedAccount {
                        Text("·")
                        Text(linkedAcct.name ?? "Account")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Image(systemName: investmentIcon(trn.transactionType))
                    .foregroundStyle(.purple)
            } else if trn.isTransfer {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.blue)
            } else if trn.isCashLeg {
                Image(systemName: "dollarsign.circle")
                    .foregroundStyle(.orange)
            } else if (trn.amount?.doubleValue ?? 0) >= 0 {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func transactionTitle(_ trn: Transaction) -> String {
        if let detail = trn.investmentDetail, detail.quantity != 0 {
            let action = investmentActionName(trn.transactionType)
            let secName = trn.security?.symbol ?? trn.security?.name ?? ""
            return "\(action) \(secName)"
        }
        if trn.isTransfer, let linked = trn.linkedAccount {
            let direction = (trn.amount?.doubleValue ?? 0) >= 0 ? "from" : "to"
            return "Transfer \(direction) \(linked.name ?? "Account")"
        }
        return trn.payee?.name ?? trn.category?.fullName ?? "Transaction"
    }

    private func investmentIcon(_ type: String?) -> String {
        switch type {
        case "buy": return "arrow.down.circle.fill"
        case "sell": return "arrow.up.circle.fill"
        case "income": return "banknote.fill"
        case "reinvest": return "arrow.triangle.2.circlepath"
        default: return "chart.line.uptrend.xyaxis"
        }
    }

    private func investmentActionName(_ type: String?) -> String {
        switch type {
        case "buy": return "Buy"
        case "sell": return "Sell"
        case "income": return "Dividend"
        case "reinvest": return "Reinvest"
        default: return "Trade"
        }
    }
}

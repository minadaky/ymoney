import SwiftUI
import CoreData

/// Account detail view showing transaction register
struct AccountDetailView: View {
    let account: Account
    @Environment(\.managedObjectContext) private var viewContext

    @State private var transactions: [Transaction] = []
    @State private var balance: NSDecimalNumber = .zero
    @State private var searchText = ""

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
        if searchText.isEmpty { return transactions }
        let query = searchText.lowercased()
        return transactions.filter { trn in
            (trn.payee?.name?.lowercased().contains(query) ?? false) ||
            (trn.category?.fullName?.lowercased().contains(query) ?? false) ||
            (trn.memo?.lowercased().contains(query) ?? false)
        }
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
            if trn.isTransfer {
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(.blue)
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(trn.payee?.name ?? trn.category?.fullName ?? "Transaction")
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(trn.date?.shortDisplay ?? "")
                    if let cat = trn.category?.fullName {
                        Text("·")
                        Text(cat)
                            .lineLimit(1)
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
}

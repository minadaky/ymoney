import SwiftUI
import CoreData

/// All-transactions view with search, filter, and grouping
struct TransactionsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel: TransactionsViewModel?
    @State private var searchText = ""

    var body: some View {
        Group {
            if let vm = viewModel {
                transactionsList(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Transactions")
        .onAppear {
            let vm = TransactionsViewModel(context: viewContext)
            vm.load()
            viewModel = vm
        }
    }

    private func transactionsList(_ vm: TransactionsViewModel) -> some View {
        List {
            // Account filter
            Section {
                Picker("Account", selection: Binding(
                    get: { vm.selectedAccountFilter },
                    set: { vm.selectedAccountFilter = $0 }
                )) {
                    Text("All Accounts").tag(nil as Account?)
                    ForEach(vm.accounts, id: \.objectID) { acct in
                        Text(acct.name ?? "Unknown").tag(acct as Account?)
                    }
                }
            }

            // Grouped transactions
            ForEach(vm.groupedByMonth, id: \.0) { monthName, transactions in
                Section {
                    ForEach(transactions, id: \.objectID) { trn in
                        NavigationLink {
                            TransactionDetailView(transaction: trn)
                        } label: {
                            transactionRow(trn)
                        }
                    }
                } header: {
                    HStack {
                        Text(monthName)
                        Spacer()
                        let total = transactions.reduce(NSDecimalNumber.zero) { $0.adding($1.amount ?? .zero) }
                        Text(CurrencyFormatter.format(total))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        }
        .searchable(text: Binding(
            get: { vm.searchText },
            set: { vm.searchText = $0 }
        ), prompt: "Search payee, category, memo")
    }

    private func transactionRow(_ trn: Transaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if trn.isTransfer {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    Text(transactionTitle(trn))
                        .font(.subheadline)
                        .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Text(trn.date?.shortDisplay ?? "")
                    if let acctName = trn.account?.name {
                        Text("·")
                        Text(acctName)
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

    private func transactionTitle(_ trn: Transaction) -> String {
        if trn.isTransfer, let linked = trn.linkedAccount {
            let direction = (trn.amount?.doubleValue ?? 0) >= 0 ? "from" : "to"
            return "Transfer \(direction) \(linked.name ?? "Account")"
        }
        return trn.payee?.name ?? trn.category?.fullName ?? "Transaction"
    }
}

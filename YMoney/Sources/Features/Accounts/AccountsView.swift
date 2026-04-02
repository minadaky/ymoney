import SwiftUI
import CoreData

/// List of all accounts grouped by type
struct AccountsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel: AccountsViewModel?

    var body: some View {
        List {
            if let vm = viewModel {
                if !vm.bankingAccounts.isEmpty {
                    Section("Banking") {
                        ForEach(vm.bankingAccounts, id: \.objectID) { account in
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                accountRow(account, vm: vm)
                            }
                        }
                    }
                }

                if !vm.investmentAccounts.isEmpty {
                    Section("Investments") {
                        ForEach(vm.investmentAccounts, id: \.objectID) { account in
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                accountRow(account, vm: vm)
                            }
                        }
                    }
                }

                if !vm.closedAccounts.isEmpty {
                    Section("Closed") {
                        ForEach(vm.closedAccounts, id: \.objectID) { account in
                            NavigationLink {
                                AccountDetailView(account: account)
                            } label: {
                                accountRow(account, vm: vm)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Accounts")
        .onAppear {
            let vm = AccountsViewModel(context: viewContext)
            vm.load()
            viewModel = vm
        }
    }

    private func accountRow(_ account: Account, vm: AccountsViewModel) -> some View {
        HStack {
            Image(systemName: iconForType(account.accountType))
                .foregroundStyle(colorForType(account.accountType))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name ?? "Unknown")
                    .font(.body)
                Text(vm.accountTypeName(account.accountType))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            let balance = vm.balance(for: account)
            Text(CurrencyFormatter.format(balance))
                .font(.body.monospacedDigit())
                .foregroundColor(CurrencyFormatter.isPositive(balance) ? Color.primary : Color.red)
        }
        .padding(.vertical, 4)
    }

    private func iconForType(_ type: Int32) -> String {
        switch type {
        case 0: return "building.columns.fill"
        case 1: return "banknote.fill"
        case 2: return "creditcard.fill"
        case 3: return "dollarsign.circle.fill"
        case 4: return "percent"
        case 5: return "chart.line.uptrend.xyaxis"
        default: return "questionmark.circle"
        }
    }

    private func colorForType(_ type: Int32) -> Color {
        switch type {
        case 0: return .blue
        case 1: return .teal
        case 2: return .orange
        case 3: return .green
        case 4: return .red
        case 5: return .purple
        default: return .gray
        }
    }
}

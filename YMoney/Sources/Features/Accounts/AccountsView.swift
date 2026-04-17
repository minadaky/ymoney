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
                    accountSection("Banking", accounts: vm.bankingAccounts, vm: vm)
                }
                if !vm.creditAccounts.isEmpty {
                    accountSection("Credit Cards", accounts: vm.creditAccounts, vm: vm)
                }
                if !vm.investmentAccounts.isEmpty {
                    accountSection("Investments", accounts: vm.investmentAccounts, vm: vm)
                }
                if !vm.retirementAccounts.isEmpty {
                    accountSection("Retirement", accounts: vm.retirementAccounts, vm: vm)
                }
                if !vm.loanAccounts.isEmpty {
                    accountSection("Loans", accounts: vm.loanAccounts, vm: vm)
                }
                if !vm.otherAccounts.isEmpty {
                    accountSection("Other", accounts: vm.otherAccounts, vm: vm)
                }
                if !vm.closedAccounts.isEmpty {
                    accountSection("Closed", accounts: vm.closedAccounts, vm: vm)
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

    private func accountSection(_ title: String, accounts: [Account], vm: AccountsViewModel) -> some View {
        Section(title) {
            ForEach(accounts, id: \.objectID) { account in
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    accountRow(account, vm: vm)
                }
            }
        }
    }

    private func accountRow(_ account: Account, vm: AccountsViewModel) -> some View {
        HStack {
            Image(systemName: account.ofxAccountType.icon)
                .foregroundStyle(accountColor(for: account))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name ?? "Unknown")
                    .font(.body)
                Text(account.ofxAccountType.displayName)
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

    private func accountColor(for account: Account) -> Color {
        switch account.ofxAccountType {
        case .checking:       return .blue
        case .savings:        return .teal
        case .creditCard:     return .orange
        case .cash:           return .green
        case .moneyMarket:    return .cyan
        case .investment:     return .purple
        case .asset:          return .brown
        case .liability:      return .pink
        case .cd:             return .indigo
        case .loan:           return .red
        case .retirement401k, .ira: return .mint
        }
    }
}

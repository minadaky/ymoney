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
        case 0: return "building.columns.fill"    // Checking
        case 1: return "creditcard.fill"           // Credit Card
        case 2: return "banknote.fill"             // Savings
        case 3: return "dollarsign.circle.fill"    // Cash
        case 4: return "building.fill"             // Money Market
        case 5: return "chart.line.uptrend.xyaxis" // Investment
        case 6: return "house.fill"                // Asset
        case 7: return "minus.circle.fill"         // Liability
        case 8: return "lock.fill"                 // CD
        case 9: return "percent"                   // Loan
        case 10: return "briefcase.fill"           // 401(k)
        case 11: return "heart.fill"               // IRA
        default: return "questionmark.circle"
        }
    }

    private func colorForType(_ type: Int32) -> Color {
        switch type {
        case 0: return .blue       // Checking
        case 1: return .orange     // Credit Card
        case 2: return .teal       // Savings
        case 3: return .green      // Cash
        case 4: return .cyan       // Money Market
        case 5: return .purple     // Investment
        case 6: return .brown      // Asset
        case 7: return .pink       // Liability
        case 8: return .indigo     // CD
        case 9: return .red        // Loan
        case 10: return .mint      // 401(k)
        case 11: return .mint      // IRA
        default: return .gray
        }
    }
}

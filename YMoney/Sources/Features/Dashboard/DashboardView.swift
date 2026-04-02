import SwiftUI
import CoreData

/// Main dashboard showing financial overview
struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel: DashboardViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let vm = viewModel {
                    netWorthCard(vm)
                    balanceSummary(vm)
                    accountsList(vm)
                    recentTransactionsCard(vm)
                } else {
                    ProgressView()
                }
            }
            .padding()
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            let vm = DashboardViewModel(context: viewContext)
            vm.load()
            viewModel = vm
        }
    }

    private func netWorthCard(_ vm: DashboardViewModel) -> some View {
        VStack(spacing: 4) {
            Text("Net Worth")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.format(vm.totalBalance))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(CurrencyFormatter.isPositive(vm.totalBalance) ? Color.primary : Color.red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func balanceSummary(_ vm: DashboardViewModel) -> some View {
        HStack(spacing: 12) {
            summaryTile(title: "Banking", amount: vm.bankingBalance, icon: "building.columns.fill", color: .blue)
            summaryTile(title: "Investments", amount: vm.investmentBalance, icon: "chart.line.uptrend.xyaxis", color: .green)
        }
    }

    private func summaryTile(title: String, amount: NSDecimalNumber, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(CurrencyFormatter.format(amount))
                .font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func accountsList(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Accounts")
                .font(.headline)
                .padding(.bottom, 2)

            ForEach(vm.accounts, id: \.objectID) { account in
                let balance = vm.accountBalances[account.objectID] ?? .zero
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    HStack {
                        Image(systemName: accountIcon(for: account.accountType))
                            .foregroundStyle(accountColor(for: account.accountType))
                            .frame(width: 24)
                        Text(account.name ?? "Unknown")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(CurrencyFormatter.format(balance))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(CurrencyFormatter.isPositive(balance) ? Color.primary : Color.red)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func recentTransactionsCard(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Transactions")
                .font(.headline)
                .padding(.bottom, 2)

            ForEach(vm.recentTransactions, id: \.objectID) { trn in
                NavigationLink {
                    TransactionDetailView(transaction: trn)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(trn.payee?.name ?? trn.category?.fullName ?? "Transaction")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                Text(trn.date?.shortDisplay ?? "")
                                if let acctName = trn.account?.name {
                                    Text("·")
                                    Text(acctName)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CurrencyFormatter.format(trn.amount))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(CurrencyFormatter.isPositive(trn.amount) ? .green : .red)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }

                if trn != vm.recentTransactions.last {
                    Divider()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func accountIcon(for type: Int32) -> String {
        switch type {
        case 0: return "building.columns"
        case 1: return "banknote"
        case 2: return "creditcard"
        case 3: return "dollarsign.circle"
        case 4: return "percent"
        case 5: return "chart.line.uptrend.xyaxis"
        default: return "questionmark.circle"
        }
    }

    private func accountColor(for type: Int32) -> Color {
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

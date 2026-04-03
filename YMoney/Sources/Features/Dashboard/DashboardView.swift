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
            summaryTile(title: "Debt", amount: vm.debtBalance, icon: "creditcard.fill", color: .red)
        }
    }

    private func summaryTile(title: String, amount: NSDecimalNumber, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(CurrencyFormatter.formatCompact(amount))
                .font(.subheadline.bold().monospacedDigit())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
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
                        Image(systemName: accountIcon(for: account))
                            .foregroundStyle(accountColor(for: account))
                            .frame(width: 24)
                        Text(account.name ?? "Unknown")
                            .font(.subheadline)
                        Spacer()
                        Text(CurrencyFormatter.format(balance))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(CurrencyFormatter.isPositive(balance) ? Color.primary : Color.red)
                    }
                    .padding(.vertical, 4)
                }
                .foregroundStyle(.primary)
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
                            .foregroundColor(CurrencyFormatter.isPositive(trn.amount) ? Color.primary : Color.red)
                    }
                    .padding(.vertical, 2)
                }
                .foregroundStyle(.primary)

                if trn != vm.recentTransactions.last {
                    Divider()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func accountIcon(for account: Account) -> String {
        account.ofxAccountType.icon
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

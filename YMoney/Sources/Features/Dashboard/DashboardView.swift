import SwiftUI
import CoreData

/// Main dashboard showing financial overview
struct DashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel: DashboardViewModel?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
        .navigationTitle("Dashboard")
        .onAppear {
            let vm = DashboardViewModel(context: viewContext)
            vm.load()
            viewModel = vm
        }
    }

    private func netWorthCard(_ vm: DashboardViewModel) -> some View {
        VStack(spacing: 8) {
            Text("Net Worth")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(CurrencyFormatter.format(vm.totalBalance))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(CurrencyFormatter.isPositive(vm.totalBalance) ? Color.primary : Color.red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func balanceSummary(_ vm: DashboardViewModel) -> some View {
        HStack(spacing: 16) {
            summaryTile(title: "Banking", amount: vm.bankingBalance, icon: "building.columns.fill", color: .blue)
            summaryTile(title: "Investments", amount: vm.investmentBalance, icon: "chart.line.uptrend.xyaxis", color: .green)
        }
    }

    private func summaryTile(title: String, amount: NSDecimalNumber, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Accounts")
                .font(.headline)

            ForEach(Array(vm.accountSummaries.enumerated()), id: \.offset) { _, summary in
                HStack {
                    Image(systemName: accountIcon(for: summary.type))
                        .foregroundStyle(accountColor(for: summary.type))
                        .frame(width: 24)
                    Text(summary.name)
                        .font(.subheadline)
                    Spacer()
                    Text(CurrencyFormatter.format(summary.balance))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(CurrencyFormatter.isPositive(summary.balance) ? Color.primary : Color.red)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func recentTransactionsCard(_ vm: DashboardViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Transactions")
                .font(.headline)

            ForEach(vm.recentTransactions, id: \.objectID) { trn in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trn.payee?.name ?? trn.category?.fullName ?? "Transaction")
                            .font(.subheadline)
                        Text(trn.date?.shortDisplay ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(CurrencyFormatter.format(trn.amount))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(CurrencyFormatter.isPositive(trn.amount) ? .green : .red)
                }
                .padding(.vertical, 2)

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
        case 0: return "building.columns"       // Checking
        case 1: return "banknote"               // Savings
        case 2: return "creditcard"             // Credit
        case 3: return "dollarsign.circle"      // Cash
        case 4: return "percent"                // Loan
        case 5: return "chart.line.uptrend.xyaxis" // Investment
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

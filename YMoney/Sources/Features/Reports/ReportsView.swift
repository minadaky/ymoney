import SwiftUI
import CoreData

/// Financial reports view
struct ReportsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel: ReportsViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                reportsContent(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Reports")
        .onAppear {
            let vm = ReportsViewModel(context: viewContext)
            vm.load()
            viewModel = vm
        }
    }

    private func reportsContent(_ vm: ReportsViewModel) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Income vs Expense Summary
                incomeExpenseCard(vm)

                // Spending by Category
                spendingByCategoryCard(vm)

                // Monthly Cash Flow
                monthlyCashFlowCard(vm)
            }
            .padding()
        }
    }

    private func incomeExpenseCard(_ vm: ReportsViewModel) -> some View {
        VStack(spacing: 16) {
            Text("Income vs Expenses")
                .font(.headline)

            HStack(spacing: 24) {
                VStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("Income")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.format(vm.totalIncome))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.green)
                }

                VStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                    Text("Expenses")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.format(vm.totalExpenses))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.red)
                }

                VStack {
                    Image(systemName: "equal.circle.fill")
                        .font(.title2)
                        .foregroundStyle(vm.netIncome >= 0 ? .green : .red)
                    Text("Net")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(CurrencyFormatter.format(vm.netIncome))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(vm.netIncome >= 0 ? .green : .red)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func spendingByCategoryCard(_ vm: ReportsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spending by Category")
                .font(.headline)

            SpendingChartView(data: vm.spendingByCategory)

            ForEach(vm.spendingByCategory) { item in
                HStack {
                    Circle()
                        .fill(chartColor(item.color))
                        .frame(width: 10, height: 10)
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(CurrencyFormatter.format(item.amount))
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func monthlyCashFlowCard(_ vm: ReportsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monthly Cash Flow")
                .font(.headline)

            ForEach(vm.monthlyFlows) { flow in
                VStack(alignment: .leading, spacing: 4) {
                    Text(flow.month)
                        .font(.caption.bold())

                    HStack(spacing: 8) {
                        // Income bar
                        let maxVal = max(vm.monthlyFlows.map { max($0.income, $0.expense) }.max() ?? 1, 1)

                        VStack(alignment: .leading) {
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.green)
                                    .frame(width: max(0, geo.size.width * (flow.income / maxVal)))
                            }
                            .frame(height: 12)

                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(.red)
                                    .frame(width: max(0, geo.size.width * (flow.expense / maxVal)))
                            }
                            .frame(height: 12)
                        }

                        VStack(alignment: .trailing) {
                            Text(CurrencyFormatter.format(flow.income))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.green)
                            Text(CurrencyFormatter.format(flow.expense))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.red)
                        }
                        .frame(width: 80)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chartColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .red, .purple, .teal, .pink, .yellow, .indigo, .brown, .mint, .cyan, .gray, .black, .white]
        return colors[index % colors.count]
    }
}

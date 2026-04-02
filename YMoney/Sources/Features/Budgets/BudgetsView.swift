import SwiftUI
import CoreData

/// Budget tracking view with progress bars
struct BudgetsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel: BudgetsViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                budgetContent(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Budgets")
        .onAppear {
            let vm = BudgetsViewModel(context: viewContext)
            vm.load()
            viewModel = vm
        }
    }

    private func budgetContent(_ vm: BudgetsViewModel) -> some View {
        List {
            // Summary header
            Section {
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Budgeted")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.format(vm.totalBudgeted))
                                .font(.title3.bold().monospacedDigit())
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Spent")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(CurrencyFormatter.format(vm.totalSpent))
                                .font(.title3.bold().monospacedDigit())
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            // Budget categories grouped by bucket
            let grouped = Dictionary(grouping: vm.budgetRows) { $0.bucketName }
            let sortedGroups = grouped.sorted { $0.key < $1.key }

            ForEach(sortedGroups, id: \.key) { bucketName, rows in
                Section(bucketName) {
                    ForEach(rows) { row in
                        budgetRow(row)
                    }
                }
            }
        }
    }

    private func budgetRow(_ row: BudgetsViewModel.BudgetRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.categoryName)
                    .font(.subheadline)
                Spacer()
                Text("\(CurrencyFormatter.format(row.actual)) / \(CurrencyFormatter.format(row.budgeted))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor(row.percentUsed))
                        .frame(width: max(0, geo.size.width * min(row.percentUsed, 1.0)), height: 8)
                }
            }
            .frame(height: 8)

            if row.percentUsed > 1.0 {
                Text("Over budget by \(CurrencyFormatter.format(row.remaining.multiplying(by: NSDecimalNumber(value: -1))))")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func progressColor(_ percent: Double) -> Color {
        if percent > 1.0 { return .red }
        if percent > 0.8 { return .orange }
        return .green
    }
}

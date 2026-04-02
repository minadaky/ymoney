import Foundation
import CoreData

/// ViewModel for reports
@MainActor
@Observable
final class ReportsViewModel {
    struct CategorySpending: Identifiable {
        let id: NSManagedObjectID
        let name: String
        let amount: Double
        let color: Int
    }

    struct MonthlyFlow: Identifiable {
        let id = UUID()
        let month: String
        let income: Double
        let expense: Double
    }

    var spendingByCategory: [CategorySpending] = []
    var monthlyFlows: [MonthlyFlow] = []
    var totalIncome: Double = 0
    var totalExpenses: Double = 0
    var netIncome: Double = 0

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load() {
        loadSpendingByCategory()
        loadMonthlyFlows()
    }

    private func loadSpendingByCategory() {
        let request = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "amount < 0 AND category != nil AND category.level > 0")

        guard let transactions = try? context.fetch(request) else { return }

        // Group by category
        let grouped = Dictionary(grouping: transactions) { $0.category?.fullName ?? "Unknown" }
        var results: [CategorySpending] = []

        var colorIndex = 0
        for (name, txns) in grouped.sorted(by: { a, b in
            let totalA = a.value.reduce(0.0) { $0 + ($1.amount?.doubleValue ?? 0) }
            let totalB = b.value.reduce(0.0) { $0 + ($1.amount?.doubleValue ?? 0) }
            return totalA < totalB
        }) {
            let total = txns.reduce(0.0) { $0 + ($1.amount?.doubleValue ?? 0) }
            if let cat = txns.first?.category {
                results.append(CategorySpending(
                    id: cat.objectID,
                    name: name,
                    amount: abs(total),
                    color: colorIndex
                ))
            }
            colorIndex += 1
        }

        spendingByCategory = Array(results.prefix(15))
    }

    private func loadMonthlyFlows() {
        let request = Transaction.fetchRequest()
        request.predicate = NSPredicate(format: "amount != 0")
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

        guard let transactions = try? context.fetch(request) else { return }

        let calendar = Calendar.current
        let grouped = Dictionary(grouping: transactions) { trn -> String in
            guard let date = trn.date else { return "Unknown" }
            let comps = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
        }

        var flows: [MonthlyFlow] = []
        var totIncome = 0.0
        var totExpenses = 0.0

        for (month, txns) in grouped.sorted(by: { $0.key < $1.key }) {
            let income = txns.filter { ($0.amount?.doubleValue ?? 0) > 0 }
                .reduce(0.0) { $0 + ($1.amount?.doubleValue ?? 0) }
            let expense = txns.filter { ($0.amount?.doubleValue ?? 0) < 0 }
                .reduce(0.0) { $0 + ($1.amount?.doubleValue ?? 0) }

            flows.append(MonthlyFlow(month: month, income: income, expense: abs(expense)))
            totIncome += income
            totExpenses += abs(expense)
        }

        monthlyFlows = flows
        totalIncome = totIncome
        totalExpenses = totExpenses
        netIncome = totIncome - totExpenses
    }
}

import Foundation
import CoreData

/// ViewModel for Budget tracking
@MainActor
@Observable
final class BudgetsViewModel {
    struct BudgetRow: Identifiable {
        let id: NSManagedObjectID
        let categoryName: String
        let bucketName: String
        let budgeted: NSDecimalNumber
        let actual: NSDecimalNumber
        var remaining: NSDecimalNumber { budgeted.subtracting(actual.multiplying(by: NSDecimalNumber(value: -1))) }
        var percentUsed: Double {
            guard budgeted.doubleValue > 0 else { return 0 }
            return min(abs(actual.doubleValue) / budgeted.doubleValue, 2.0)
        }
    }

    var budgetRows: [BudgetRow] = []
    var totalBudgeted: NSDecimalNumber = .zero
    var totalSpent: NSDecimalNumber = .zero

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load() {
        let request = BudgetCategory.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "bucketName", ascending: true)]
        request.predicate = NSPredicate(format: "amountPerPeriod != nil AND amountPerPeriod != 0")

        guard let items = try? context.fetch(request) else { return }

        var rows: [BudgetRow] = []
        var totalBgt: NSDecimalNumber = .zero
        var totalAct: NSDecimalNumber = .zero

        for item in items {
            let catName = item.category?.fullName ?? item.name ?? "Unknown"
            let budgeted = item.amountPerPeriod ?? .zero

            // Calculate actual spending in this category
            let actual = computeActualSpending(for: item.category)

            rows.append(BudgetRow(
                id: item.objectID,
                categoryName: catName,
                bucketName: item.bucketName ?? "Other",
                budgeted: budgeted,
                actual: actual
            ))

            totalBgt = totalBgt.adding(budgeted)
            totalAct = totalAct.adding(actual)
        }

        budgetRows = rows
        totalBudgeted = totalBgt
        totalSpent = totalAct
    }

    private func computeActualSpending(for category: Category?) -> NSDecimalNumber {
        guard let category = category else { return .zero }
        let transactions = category.transactions as? Set<Transaction> ?? []

        // Filter to current month
        let now = Date()
        let startOfMonth = now.startOfMonth

        let monthlyTxns = transactions.filter { trn in
            guard let date = trn.date else { return false }
            return date >= startOfMonth && date <= now
        }

        return monthlyTxns.reduce(NSDecimalNumber.zero) { $0.adding($1.amount ?? .zero) }
    }
}

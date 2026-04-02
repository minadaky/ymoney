import Foundation
import CoreData

/// ViewModel for the Investment portfolio view
@MainActor
@Observable
final class InvestmentsViewModel {
    struct Holding: Identifiable {
        let id: NSManagedObjectID
        let securityName: String
        let symbol: String
        let accountName: String
        let totalShares: Double
        let openLots: [Lot]
        let closedLots: [Lot]
    }

    struct PortfolioSummary {
        var totalValue: NSDecimalNumber = .zero
        var totalCostBasis: NSDecimalNumber = .zero
        var holdings: [Holding] = []
    }

    var portfolio = PortfolioSummary()
    var investmentTransactions: [Transaction] = []
    var securities: [Security] = []

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load() {
        loadSecurities()
        loadHoldings()
        loadInvestmentTransactions()
    }

    private func loadSecurities() {
        let request = Security.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        securities = (try? context.fetch(request)) ?? []
    }

    private func loadHoldings() {
        let request = Lot.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "buyDate", ascending: false)]

        guard let lots = try? context.fetch(request) else { return }

        // Group lots by security + account
        let grouped = Dictionary(grouping: lots) { lot -> String in
            "\(lot.security?.moneyID ?? 0)-\(lot.account?.moneyID ?? 0)"
        }

        var holdings: [Holding] = []
        for (_, groupLots) in grouped {
            guard let first = groupLots.first,
                  let sec = first.security,
                  sec.symbol != "None" else { continue } // Skip cash placeholder

            let openLots = groupLots.filter { $0.sellDate == nil }
            let closedLots = groupLots.filter { $0.sellDate != nil }
            let totalShares = openLots.reduce(0.0) { $0 + $1.quantity }

            holdings.append(Holding(
                id: first.objectID,
                securityName: sec.name ?? "Unknown",
                symbol: sec.symbol ?? "",
                accountName: first.account?.name ?? "Unknown",
                totalShares: totalShares,
                openLots: openLots,
                closedLots: closedLots
            ))
        }

        portfolio.holdings = holdings.sorted { $0.totalShares > $1.totalShares }
    }

    private func loadInvestmentTransactions() {
        let request = Transaction.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.predicate = NSPredicate(format: "investmentDetail != nil")
        investmentTransactions = (try? context.fetch(request)) ?? []
    }
}

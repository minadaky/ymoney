import Foundation
import CoreData

/// ViewModel for the Investment portfolio view
@MainActor
@Observable
final class InvestmentsViewModel {
    struct Holding: Identifiable {
        let id: NSManagedObjectID
        let securityObjectID: NSManagedObjectID
        let securityName: String
        let symbol: String
        let accountName: String
        let totalShares: Double
        let openLots: [Lot]
        let closedLots: [Lot]
        let lastPrice: Double
        let previousClose: Double
        let lastPriceDate: Date?
    }

    struct PortfolioSummary {
        var totalValue: NSDecimalNumber = .zero
        var totalCostBasis: NSDecimalNumber = .zero
        var holdings: [Holding] = []
    }

    var portfolio = PortfolioSummary()
    var investmentTransactions: [Transaction] = []
    var securities: [Security] = []

    /// Per-symbol fetch state for swipe-to-quote.
    var fetchingSymbols: Set<String> = []
    var fetchError: String?
    /// Full diagnostic info (includes raw API response) for clipboard copy.
    var fetchErrorDiagnostic: String?

    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func load() {
        loadSecurities()
        loadHoldings()
        loadInvestmentTransactions()
    }

    // MARK: - Quote Fetching (swipe action)

    /// Fetch a live quote for a single holding, persist to Core Data, and reload.
    func fetchQuote(for holding: Holding) async {
        let symbol = holding.symbol
        guard !symbol.isEmpty else { return }

        fetchingSymbols.insert(symbol)
        fetchError = nil
        fetchErrorDiagnostic = nil
        defer { fetchingSymbols.remove(symbol) }

        do {
            let provider = QuoteConfiguration.makeProvider()
            let quote = try await provider.quote(for: symbol)

            // Persist on the Security entity (denormalized for fast display)
            guard let security = context.object(with: holding.securityObjectID) as? Security else { return }
            security.lastPrice = quote.currentPrice
            security.previousClose = quote.previousClose
            security.lastPriceDate = quote.timestamp

            // Append to quote history (one record per fetch, deduped by calendar day)
            let calendar = Calendar.current
            let quoteDay = calendar.startOfDay(for: quote.timestamp)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: quoteDay) else { return }
            let request = SecurityQuote.fetchRequest()
            request.predicate = NSPredicate(
                format: "security == %@ AND date >= %@ AND date < %@",
                security,
                quoteDay as NSDate,
                nextDay as NSDate
            )
            request.fetchLimit = 1

            let existing = (try? context.fetch(request))?.first

            let record = existing ?? SecurityQuote(context: context)
            record.security = security
            record.date = quote.timestamp
            record.price = quote.currentPrice
            record.previousClose = quote.previousClose
            record.dayHigh = quote.dayHigh
            record.dayLow = quote.dayLow
            record.openPrice = quote.openPrice

            try context.save()

            // Reload holdings to pick up new prices
            loadHoldings()
        } catch let e as QuoteProviderError {
            fetchError = e.localizedDescription
            fetchErrorDiagnostic = e.diagnosticDescription
        } catch {
            fetchError = error.localizedDescription
            fetchErrorDiagnostic = error.localizedDescription
        }
    }

    // MARK: - Data Loading

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
                  sec.symbol != "None" else { continue }

            let openLots = groupLots.filter { $0.sellDate == nil }
            let closedLots = groupLots.filter { $0.sellDate != nil }
            let totalShares = openLots.reduce(0.0) { $0 + $1.quantity }

            holdings.append(Holding(
                id: first.objectID,
                securityObjectID: sec.objectID,
                securityName: sec.name ?? "Unknown",
                symbol: sec.symbol ?? "",
                accountName: first.account?.name ?? "Unknown",
                totalShares: totalShares,
                openLots: openLots,
                closedLots: closedLots,
                lastPrice: sec.lastPrice,
                previousClose: sec.previousClose,
                lastPriceDate: sec.lastPriceDate
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

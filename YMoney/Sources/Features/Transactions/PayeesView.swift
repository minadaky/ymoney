import SwiftUI
import CoreData

/// Payees list and management view
struct PayeesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var payees: [Payee] = []
    @State private var searchText = ""

    var body: some View {
        List {
            ForEach(filteredPayees, id: \.objectID) { payee in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(payee.name ?? "Unknown")
                            .font(.body)
                        let count = (payee.transactions as? Set<Transaction>)?.count ?? 0
                        Text("\(count) transaction\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    let total = (payee.transactions as? Set<Transaction>)?.reduce(NSDecimalNumber.zero) {
                        $0.adding($1.amount ?? .zero)
                    } ?? .zero
                    Text(CurrencyFormatter.format(total))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(CurrencyFormatter.isPositive(total) ? .green : .red)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search payees")
        .navigationTitle("Payees")
        .onAppear { loadPayees() }
    }

    private var filteredPayees: [Payee] {
        if searchText.isEmpty { return payees }
        return payees.filter { $0.name?.lowercased().contains(searchText.lowercased()) ?? false }
    }

    private func loadPayees() {
        let request = Payee.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.predicate = NSPredicate(format: "isHidden == NO")
        payees = (try? viewContext.fetch(request)) ?? []
    }
}

import SwiftUI

/// Detail view for a specific investment holding (lots)
struct InvestmentDetailView: View {
    let holding: InvestmentsViewModel.Holding

    var body: some View {
        List {
            // Summary
            Section {
                VStack(spacing: 8) {
                    Text(holding.securityName)
                        .font(.title2.bold())
                    Text(holding.symbol)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.4f total shares", holding.totalShares))
                        .font(.headline.monospacedDigit())
                    Text("in \(holding.accountName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Open Lots
            if !holding.openLots.isEmpty {
                Section("Open Lots (\(holding.openLots.count))") {
                    ForEach(holding.openLots, id: \.objectID) { lot in
                        lotRow(lot, isOpen: true)
                    }
                }
            }

            // Closed Lots
            if !holding.closedLots.isEmpty {
                Section("Closed Lots (\(holding.closedLots.count))") {
                    ForEach(holding.closedLots, id: \.objectID) { lot in
                        lotRow(lot, isOpen: false)
                    }
                }
            }
        }
        .navigationTitle(holding.symbol)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func lotRow(_ lot: Lot, isOpen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(String(format: "%.4f shares", lot.quantity))
                    .font(.subheadline.monospacedDigit())
                Spacer()
                if isOpen {
                    Text("Open")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.green.opacity(0.15))
                        .foregroundStyle(.green)
                        .clipShape(Capsule())
                } else {
                    Text("Closed")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.15))
                        .foregroundStyle(.gray)
                        .clipShape(Capsule())
                }
            }

            HStack {
                if let buyDate = lot.buyDate {
                    Label("Bought \(buyDate.shortDisplay)", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let sellDate = lot.sellDate {
                    Label("Sold \(sellDate.shortDisplay)", systemImage: "arrow.up.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

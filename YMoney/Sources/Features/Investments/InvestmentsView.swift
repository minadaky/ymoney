import SwiftUI
import CoreData

/// Investment portfolio overview
struct InvestmentsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewModel: InvestmentsViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                investmentContent(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Investments")
        .onAppear {
            let vm = InvestmentsViewModel(context: viewContext)
            vm.load()
            viewModel = vm
        }
    }

    private func investmentContent(_ vm: InvestmentsViewModel) -> some View {
        List {
            // Holdings section
            if !vm.portfolio.holdings.isEmpty {
                Section("Holdings") {
                    ForEach(vm.portfolio.holdings) { holding in
                        NavigationLink {
                            InvestmentDetailView(holding: holding)
                        } label: {
                            holdingRow(holding)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await vm.fetchQuote(for: holding) }
                            } label: {
                                if vm.fetchingSymbols.contains(holding.symbol) {
                                    Label("Fetching…", systemImage: "arrow.trianglehead.2.clockwise")
                                } else {
                                    Label("Quote", systemImage: "chart.line.uptrend.xyaxis")
                                }
                            }
                            .tint(.blue)
                            .disabled(vm.fetchingSymbols.contains(holding.symbol))
                        }
                    }
                }
            }

            if let error = vm.fetchError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .onTapGesture {
                            UIPasteboard.general.string = vm.fetchErrorDiagnostic ?? error
                            let saved = vm.fetchErrorDiagnostic
                            vm.fetchError = "Copied to clipboard ✓"
                            vm.fetchErrorDiagnostic = saved
                            Task {
                                try? await Task.sleep(for: .seconds(2))
                                await MainActor.run { vm.fetchError = nil }
                            }
                        }
                }
            }

            // Securities section
            Section("Securities") {
                ForEach(vm.securities, id: \.objectID) { sec in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sec.name ?? "Unknown")
                                .font(.subheadline)
                            if let symbol = sec.symbol {
                                Text(symbol)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let exchange = sec.exchange, !exchange.isEmpty {
                            Text(exchange)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Investment Transactions
            if !vm.investmentTransactions.isEmpty {
                Section("Recent Activity") {
                    ForEach(vm.investmentTransactions.prefix(20), id: \.objectID) { trn in
                        NavigationLink {
                            TransactionDetailView(transaction: trn)
                        } label: {
                            investmentTransactionRow(trn)
                        }
                    }
                }
            }
        }
    }

    private func holdingRow(_ holding: InvestmentsViewModel.Holding) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(holding.securityName)
                    .font(.subheadline)
                HStack(spacing: 4) {
                    Text(holding.symbol)
                        .font(.caption.bold())
                    Text("·")
                    Text(holding.accountName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if holding.lastPrice > 0 {
                    Text(CurrencyFormatter.format(NSDecimalNumber(value: holding.lastPrice)))
                        .font(.subheadline.monospacedDigit().bold())
                    if holding.previousClose > 0 {
                        let change = holding.lastPrice - holding.previousClose
                        let pct = (change / holding.previousClose) * 100
                        HStack(spacing: 2) {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .imageScale(.small)
                            Text(String(format: "%+.2f (%.1f%%)", change, pct))
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(change >= 0 ? .green : .red)
                    }
                } else {
                    Text(String(format: "%.2f shares", holding.totalShares))
                        .font(.subheadline.monospacedDigit())
                    Text("\(holding.openLots.count) open lot\(holding.openLots.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func investmentTransactionRow(_ trn: Transaction) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    actionBadge(trn.actionType)
                    Text(trn.security?.name ?? "Unknown")
                        .font(.subheadline)
                        .lineLimit(1)
                }
                Text(trn.date?.shortDisplay ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let detail = trn.investmentDetail {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(CurrencyFormatter.format(trn.amount))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(CurrencyFormatter.isPositive(trn.amount) ? .green : .red)
                    if detail.quantity != 0 {
                        Text(String(format: "%.2f @ $%.4f", detail.quantity, detail.price))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func actionBadge(_ type: Int32) -> some View {
        let (text, color): (String, Color) = {
            switch type {
            case 1: return ("BUY", .green)
            case 2: return ("SELL", .red)
            case 3: return ("DIV", .blue)
            case 4: return ("INT", .orange)
            default: return ("TXN", .gray)
            }
        }()

        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

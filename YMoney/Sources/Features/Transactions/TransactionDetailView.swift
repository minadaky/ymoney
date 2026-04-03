import SwiftUI
import CoreData

/// Detail view for a single transaction
struct TransactionDetailView: View {
    let transaction: Transaction
    @State private var showEditor = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Amount") {
                HStack {
                    Text(CurrencyFormatter.format(transaction.amount))
                        .font(.title.bold().monospacedDigit())
                        .foregroundStyle(CurrencyFormatter.isPositive(transaction.amount) ? .green : .red)
                    Spacer()
                    statusBadge
                }
            }

            Section("Details") {
                if let date = transaction.date {
                    detailRow("Date", value: date.shortDisplay, icon: "calendar")
                }
                if let payee = transaction.payee?.name {
                    detailRow("Payee", value: payee, icon: "person.fill")
                }
                if let category = transaction.category?.fullName {
                    detailRow("Category", value: category, icon: "tag.fill")
                }
                if let account = transaction.account?.name {
                    detailRow("Account", value: account, icon: "building.columns.fill")
                }
                if let check = transaction.checkNumber, !check.isEmpty {
                    detailRow("Check #", value: check, icon: "number")
                }
            }

            if transaction.isTransfer {
                Section("Transfer") {
                    if transaction.isInternalTransfer {
                        Label("Internal transfer (investment ↔ cash)", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.secondary)
                    } else if let linkedAcct = transaction.linkedAccount {
                        NavigationLink {
                            AccountDetailView(
                                account: linkedAcct,
                                scrollToTransferGroupID: transaction.transferGroupID
                            )
                        } label: {
                            HStack {
                                Image(systemName: "arrow.left.arrow.right")
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    let direction = (transaction.amount?.doubleValue ?? 0) >= 0 ? "From" : "To"
                                    Text("\(direction) \(linkedAcct.name ?? "Account")")
                                        .font(.subheadline)
                                    Text("Tap to view account")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Label("Transfer between accounts", systemImage: "arrow.left.arrow.right")
                            .foregroundStyle(.blue)
                    }
                }
            }

            if transaction.isCashLeg {
                Section {
                    Label("Cash leg of investment transaction", systemImage: "dollarsign.circle")
                        .foregroundStyle(.orange)
                }
            }

            if let investmentDetail = transaction.investmentDetail {
                Section("Investment") {
                    if let sec = transaction.security {
                        detailRow("Security", value: sec.name ?? "Unknown", icon: "chart.line.uptrend.xyaxis")
                        if let symbol = sec.symbol {
                            detailRow("Symbol", value: symbol, icon: "textformat")
                        }
                    }
                    detailRow("Price", value: String(format: "$%.4f", investmentDetail.price), icon: "dollarsign.circle")
                    detailRow("Quantity", value: String(format: "%.4f", investmentDetail.quantity), icon: "number.circle")
                    if let commission = investmentDetail.commission, commission != NSDecimalNumber.zero {
                        detailRow("Commission", value: CurrencyFormatter.format(commission), icon: "percent")
                    }
                }
            }

            if let memo = transaction.memo, !memo.isEmpty {
                Section("Memo") {
                    Text(memo)
                        .font(.body)
                }
            }

            Section("System") {
                detailRow("Money ID", value: "\(transaction.moneyID)", icon: "number")
                detailRow("Action Type", value: actionTypeName(transaction.actionType), icon: "gearshape")
                detailRow("Cleared", value: clearedStatusName(transaction.clearedStatus), icon: "checkmark.circle")
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditor = true
                } label: {
                    Text("Edit")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            TransactionEditorView(transaction: transaction, preselectedAccount: nil)
        }
    }

    private var statusBadge: some View {
        Group {
            if transaction.isTransfer {
                Label("Transfer", systemImage: "arrow.left.arrow.right")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.blue.opacity(0.15))
                    .clipShape(Capsule())
            } else if transaction.investmentDetail != nil {
                Label("Investment", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.purple.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    private func detailRow(_ label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }

    private func actionTypeName(_ type: Int32) -> String {
        switch type {
        case 0: return "Withdrawal"
        case 1: return "Buy"
        case 2: return "Sell"
        case 3: return "Dividend"
        case 4: return "Interest"
        case 5: return "Transfer"
        default: return "Type \(type)"
        }
    }

    private func clearedStatusName(_ status: Int32) -> String {
        switch status {
        case 0: return "Uncleared"
        case 1: return "Cleared"
        case 2: return "Reconciled"
        default: return "Unknown"
        }
    }
}

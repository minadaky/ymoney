import SwiftUI
import CoreData

/// The kind of transaction the user is entering
enum TransactionKind: String, CaseIterable {
    case expense = "Expense"
    case income = "Income"
    case transfer = "Transfer"
}

/// Full-screen form for creating or editing a transaction
struct TransactionEditorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let transaction: Transaction?
    let preselectedAccount: Account?

    @State private var date = Date()
    @State private var amountText = ""
    @State private var kind: TransactionKind = .expense
    @State private var selectedAccount: Account?
    @State private var transferToAccount: Account?
    @State private var selectedCategory: Category?
    @State private var payeeName = ""
    @State private var memo = ""
    @State private var checkNumber = ""
    @State private var clearedStatus: String = ClearedStatus.uncleared.rawValue

    @State private var accounts: [Account] = []
    @State private var payees: [Payee] = []
    @State private var showCategoryPicker = false
    @State private var errorMessage: String?

    private var isEditing: Bool { transaction != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(TransactionKind.allCases, id: \.self) { k in
                            Text(k.rawValue).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text(amountPrefix)
                            .font(.title2.bold())
                            .foregroundStyle(amountColor)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold().monospacedDigit())
                    }
                }

                Section(kind == .transfer ? "Accounts" : "Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    Picker(kind == .transfer ? "From" : "Account", selection: $selectedAccount) {
                        Text("Select Account").tag(nil as Account?)
                        ForEach(accounts, id: \.objectID) { acct in
                            Text(acct.name ?? "Unknown").tag(acct as Account?)
                        }
                    }

                    if kind == .transfer {
                        Picker("To", selection: $transferToAccount) {
                            Text("Select Account").tag(nil as Account?)
                            ForEach(accounts.filter { $0 != selectedAccount }, id: \.objectID) { acct in
                                Text(acct.name ?? "Unknown").tag(acct as Account?)
                            }
                        }
                    }

                    if kind != .transfer {
                        HStack {
                            Label("Payee", systemImage: "person.fill")
                            Spacer()
                            TextField("Payee name", text: $payeeName)
                                .multilineTextAlignment(.trailing)
                        }

                        Button {
                            showCategoryPicker = true
                        } label: {
                            HStack {
                                Label("Category", systemImage: "tag.fill")
                                Spacer()
                                Text(selectedCategory?.fullName ?? "None")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Optional") {
                    HStack {
                        Label("Check #", systemImage: "number")
                        Spacer()
                        TextField("Check number", text: $checkNumber)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    HStack {
                        Label("Memo", systemImage: "note.text")
                        Spacer()
                        TextField("Notes", text: $memo)
                            .multilineTextAlignment(.trailing)
                    }

                    Picker("Status", selection: $clearedStatus) {
                        Text("Uncleared").tag(ClearedStatus.uncleared.rawValue)
                        Text("Cleared").tag(ClearedStatus.cleared.rawValue)
                        Text("Reconciled").tag(ClearedStatus.reconciled.rawValue)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                    }
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            deleteTransaction()
                        } label: {
                            Label("Delete Transaction", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Transaction" : "New Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .bold()
                }
            }
            .sheet(isPresented: $showCategoryPicker) {
                NavigationStack {
                    CategoryPickerView(
                        selectedCategory: $selectedCategory,
                        isPresented: $showCategoryPicker
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showCategoryPicker = false }
                        }
                    }
                }
            }
            .onAppear { loadData() }
        }
    }

    private var amountPrefix: String {
        switch kind {
        case .expense: return "-$"
        case .income: return "+$"
        case .transfer: return "$"
        }
    }

    private var amountColor: Color {
        switch kind {
        case .expense: return .red
        case .income: return .green
        case .transfer: return .blue
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        let acctReq = Account.fetchRequest()
        acctReq.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        acctReq.predicate = NSPredicate(format: "isClosed == NO")
        accounts = (try? viewContext.fetch(acctReq)) ?? []

        let payReq = Payee.fetchRequest()
        payReq.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        payees = (try? viewContext.fetch(payReq)) ?? []

        if let acct = preselectedAccount {
            selectedAccount = acct
        }

        if let trn = transaction {
            date = trn.date ?? Date()
            let amt = trn.amount?.doubleValue ?? 0
            if trn.isTransfer {
                kind = .transfer
                amountText = String(format: "%.2f", abs(amt))
                if amt < 0 {
                    selectedAccount = trn.account
                    transferToAccount = trn.linkedAccount
                } else {
                    transferToAccount = trn.account
                    selectedAccount = trn.linkedAccount
                }
            } else {
                kind = amt < 0 ? .expense : .income
                amountText = String(format: "%.2f", abs(amt))
                selectedAccount = trn.account
            }
            selectedCategory = trn.category
            payeeName = trn.payee?.name ?? ""
            memo = trn.memo ?? ""
            checkNumber = trn.checkNumber ?? ""
            clearedStatus = trn.clearedStatus ?? ClearedStatus.uncleared.rawValue
        }
    }

    // MARK: - Save

    private func save() {
        guard let amountDouble = Double(amountText), amountDouble > 0 else {
            errorMessage = "Enter a valid amount"
            return
        }
        guard selectedAccount != nil else {
            errorMessage = "Select an account"
            return
        }

        if kind == .transfer {
            guard let toAcct = transferToAccount else {
                errorMessage = "Select a destination account"
                return
            }
            guard toAcct != selectedAccount else {
                errorMessage = "Source and destination must differ"
                return
            }
            saveTransfer(amount: amountDouble, from: selectedAccount!, to: toAcct)
        } else {
            saveRegular(amount: amountDouble)
        }
    }

    private func saveRegular(amount: Double) {
        let signedAmount = kind == .expense ? -amount : amount
        let trn = transaction ?? Transaction(context: viewContext)

        trn.date = date
        trn.amount = NSDecimalNumber(value: signedAmount)
        trn.account = selectedAccount
        trn.category = selectedCategory
        trn.memo = memo.isEmpty ? nil : memo
        trn.checkNumber = checkNumber.isEmpty ? nil : checkNumber
        trn.clearedStatus = clearedStatus
        trn.isTransfer = false
        trn.transferGroupID = nil
        trn.linkedAccount = nil

        resolvePayee(for: trn)

        if transaction == nil {
            trn.sourceType = TransactionSourceType.manual.rawValue
            trn.sourceID = 0
        }

        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveTransfer(amount: Double, from: Account, to: Account) {
        if let existing = transaction {
            deleteTransferPair(existing)
        }

        let groupID = UUID().uuidString

        let outflow = Transaction(context: viewContext)
        outflow.date = date
        outflow.amount = NSDecimalNumber(value: -amount)
        outflow.account = from
        outflow.linkedAccount = to
        outflow.isTransfer = true
        outflow.transferGroupID = groupID
        outflow.memo = memo.isEmpty ? nil : memo
        outflow.clearedStatus = clearedStatus
        outflow.sourceType = TransactionSourceType.manual.rawValue
        outflow.sourceID = 0

        let inflow = Transaction(context: viewContext)
        inflow.date = date
        inflow.amount = NSDecimalNumber(value: amount)
        inflow.account = to
        inflow.linkedAccount = from
        inflow.isTransfer = true
        inflow.transferGroupID = groupID
        inflow.memo = memo.isEmpty ? nil : memo
        inflow.clearedStatus = clearedStatus
        inflow.sourceType = TransactionSourceType.manual.rawValue
        inflow.sourceID = 0

        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    private func deleteTransferPair(_ trn: Transaction) {
        if let gid = trn.transferGroupID, !gid.isEmpty {
            let request = Transaction.fetchRequest()
            request.predicate = NSPredicate(format: "transferGroupID == %@", gid)
            if let pair = try? viewContext.fetch(request) {
                for t in pair { viewContext.delete(t) }
            }
        } else {
            viewContext.delete(trn)
        }
    }

    private func resolvePayee(for trn: Transaction) {
        if !payeeName.isEmpty {
            if let existing = payees.first(where: {
                $0.name?.lowercased() == payeeName.lowercased()
            }) {
                trn.payee = existing
            } else {
                let newPayee = Payee(context: viewContext)
                newPayee.name = payeeName
                newPayee.sourceID = 0
                newPayee.isHidden = false
                trn.payee = newPayee
            }
        } else {
            trn.payee = nil
        }
    }

    // MARK: - Delete

    private func deleteTransaction() {
        guard let trn = transaction else { return }
        deleteTransferPair(trn)
        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}

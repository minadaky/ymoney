import SwiftUI
import CoreData

/// Source type for transaction provenance tracking
enum TransactionSourceType: Int16 {
    case mnyImport = 0
    case manual = 1
    case ofxImport = 2
}

/// Full-screen form for creating or editing a transaction
struct TransactionEditorView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    /// nil = creating new, non-nil = editing existing
    let transaction: Transaction?
    /// Pre-selected account (from account detail "+" button)
    let preselectedAccount: Account?

    @State private var date = Date()
    @State private var amountText = ""
    @State private var isExpense = true
    @State private var selectedAccount: Account?
    @State private var selectedCategory: Category?
    @State private var selectedPayee: Payee?
    @State private var payeeName = ""
    @State private var memo = ""
    @State private var checkNumber = ""
    @State private var clearedStatus: Int32 = 0

    @State private var accounts: [Account] = []
    @State private var categories: [Category] = []
    @State private var payees: [Payee] = []
    @State private var showCategoryPicker = false
    @State private var showPayeePicker = false
    @State private var errorMessage: String?

    private var isEditing: Bool { transaction != nil }

    var body: some View {
        NavigationStack {
            Form {
                // Amount section
                Section {
                    HStack {
                        Picker("Type", selection: $isExpense) {
                            Text("Expense").tag(true)
                            Text("Income").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack {
                        Text(isExpense ? "-$" : "+$")
                            .font(.title2.bold())
                            .foregroundStyle(isExpense ? .red : .green)
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.title2.bold().monospacedDigit())
                    }
                }

                // Details section
                Section("Details") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    Picker("Account", selection: $selectedAccount) {
                        Text("Select Account").tag(nil as Account?)
                        ForEach(accounts, id: \.objectID) { acct in
                            Text(acct.name ?? "Unknown").tag(acct as Account?)
                        }
                    }

                    // Payee — type-ahead with existing payees
                    HStack {
                        Label("Payee", systemImage: "person.fill")
                        Spacer()
                        TextField("Payee name", text: $payeeName)
                            .multilineTextAlignment(.trailing)
                    }

                    // Category picker
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

                // Optional section
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
                        Text("Uncleared").tag(Int32(0))
                        Text("Cleared").tag(Int32(1))
                        Text("Reconciled").tag(Int32(2))
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                // Delete button for editing
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

    // MARK: - Data Loading

    private func loadData() {
        let acctReq = Account.fetchRequest()
        acctReq.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        acctReq.predicate = NSPredicate(format: "isClosed == NO")
        accounts = (try? viewContext.fetch(acctReq)) ?? []

        let catReq = Category.fetchRequest()
        catReq.sortDescriptors = [NSSortDescriptor(key: "fullName", ascending: true)]
        categories = (try? viewContext.fetch(catReq)) ?? []

        let payReq = Payee.fetchRequest()
        payReq.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        payees = (try? viewContext.fetch(payReq)) ?? []

        // Pre-fill from preselected account
        if let acct = preselectedAccount {
            selectedAccount = acct
        }

        // Pre-fill from existing transaction when editing
        if let trn = transaction {
            date = trn.date ?? Date()
            let amt = trn.amount?.doubleValue ?? 0
            isExpense = amt < 0
            amountText = String(format: "%.2f", abs(amt))
            selectedAccount = trn.account
            selectedCategory = trn.category
            selectedPayee = trn.payee
            payeeName = trn.payee?.name ?? ""
            memo = trn.memo ?? ""
            checkNumber = trn.checkNumber ?? ""
            clearedStatus = trn.clearedStatus
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

        let signedAmount = isExpense ? -amountDouble : amountDouble
        let trn = transaction ?? Transaction(context: viewContext)

        trn.date = date
        trn.amount = NSDecimalNumber(value: signedAmount)
        trn.account = selectedAccount
        trn.category = selectedCategory
        trn.memo = memo.isEmpty ? nil : memo
        trn.checkNumber = checkNumber.isEmpty ? nil : checkNumber
        trn.clearedStatus = clearedStatus

        // Resolve payee — find existing or create new
        if !payeeName.isEmpty {
            if let existing = payees.first(where: {
                $0.name?.lowercased() == payeeName.lowercased()
            }) {
                trn.payee = existing
            } else {
                let newPayee = Payee(context: viewContext)
                newPayee.name = payeeName
                newPayee.moneyID = 0
                newPayee.isHidden = false
                trn.payee = newPayee
            }
        } else {
            trn.payee = nil
        }

        // Mark as manual if new
        if transaction == nil {
            trn.isManual = true
            trn.sourceType = TransactionSourceType.manual.rawValue
            trn.moneyID = 0
        }

        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Delete

    private func deleteTransaction() {
        guard let trn = transaction else { return }
        viewContext.delete(trn)
        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}

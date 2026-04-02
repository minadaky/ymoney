import SwiftUI
import CoreData

/// OFX Export view
struct ExportView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var accounts: [Account] = []
    @State private var selectedAccount: Account?
    @State private var exportAll = true
    @State private var isExporting = false
    @State private var exportResult: String?
    @State private var showShareSheet = false
    @State private var exportURL: URL?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("OFX Export", systemImage: "square.and.arrow.up.fill")
                        .font(.headline)
                    Text("Export your transactions in OFX 2.0 format, compatible with Microsoft Money Sunset Edition import.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Options") {
                Toggle("Export All Accounts", isOn: $exportAll)

                if !exportAll {
                    Picker("Account", selection: $selectedAccount) {
                        Text("Select Account").tag(nil as Account?)
                        ForEach(accounts, id: \.objectID) { acct in
                            Text(acct.name ?? "Unknown").tag(acct as Account?)
                        }
                    }
                }
            }

            Section {
                Button {
                    performExport()
                } label: {
                    if isExporting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Export OFX File", systemImage: "arrow.down.doc.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isExporting || (!exportAll && selectedAccount == nil))
            }

            if let result = exportResult {
                Section("Result") {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.green)

                    if let url = exportURL {
                        ShareLink(item: url) {
                            Label("Share OFX File", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("Export")
        .onAppear { loadAccounts() }
    }

    private func loadAccounts() {
        let request = Account.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        request.predicate = NSPredicate(format: "isClosed == NO")
        accounts = (try? viewContext.fetch(request)) ?? []
    }

    private func performExport() {
        isExporting = true
        let service = OFXExportService(context: viewContext)

        do {
            let ofxContent: String
            if exportAll {
                ofxContent = try service.exportAll()
            } else if let account = selectedAccount {
                ofxContent = try service.exportAccount(account)
            } else {
                return
            }

            // Write to temp file
            let fileName = exportAll ? "YMoney_Export.ofx" : "\(selectedAccount?.name ?? "Account")_Export.ofx"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try ofxContent.write(to: tempURL, atomically: true, encoding: .utf8)

            exportURL = tempURL
            exportResult = "Exported successfully! \(ofxContent.count) bytes"
        } catch {
            exportResult = "Export failed: \(error.localizedDescription)"
        }

        isExporting = false
    }
}

import SwiftUI
import UniformTypeIdentifiers

/// App settings — data management, import, and about
struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var hasImported = UserDefaults.standard.bool(forKey: "hasImportedData")
    @State private var quotesEnabled = QuoteConfiguration.quotesEnabled
    @State private var quoteTestStatus: QuoteTest = .idle
    @State private var overrideURL = QuoteConfiguration.jsOverrideURL ?? ""
    @State private var overrideStatus: OverrideStatus = .idle
    @State private var showDeleteConfirmation = false
    @State private var showMoneyFilePicker = false
    @State private var showOFXFilePicker = false
    @State private var isImporting = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private enum QuoteTest: Equatable {
        case idle, checking, valid(String), invalid(String)
    }

    private enum OverrideStatus: Equatable {
        case idle, fetching, success, failed(String)
    }

    var body: some View {
        List {
            Section("Quotes") {
                Toggle(isOn: $quotesEnabled) {
                    Label("Enable Quotes", systemImage: "chart.line.uptrend.xyaxis")
                }
                .onChange(of: quotesEnabled) {
                    QuoteConfiguration.quotesEnabled = quotesEnabled
                }

                if quotesEnabled {
                    HStack {
                        Label("Data Source", systemImage: "globe")
                        Spacer()
                        Text("Yahoo Finance")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await testQuote() }
                    } label: {
                        HStack {
                            Label("Test Connection", systemImage: "antenna.radiowaves.left.and.right")
                            Spacer()
                            switch quoteTestStatus {
                            case .idle:
                                EmptyView()
                            case .checking:
                                ProgressView()
                                    .controlSize(.small)
                            case .valid(let price):
                                Text("AAPL \(price)")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            case .invalid(let msg):
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .disabled(quoteTestStatus == .checking)

                    Text("No API key required. Swipe right on a holding to fetch its price.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if quotesEnabled {
                Section("JS Transform Override") {
                HStack {
                    Label("URL", systemImage: "link")
                    Spacer()
                    TextField("https://example.com/transform.js", text: $overrideURL)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: overrideURL) {
                            QuoteConfiguration.jsOverrideURL = overrideURL.isEmpty ? nil : overrideURL
                            overrideStatus = .idle
                        }
                }

                HStack {
                    Button {
                        Task { await fetchOverride() }
                    } label: {
                        Label("Fetch Now", systemImage: "arrow.down.circle")
                    }
                    .disabled(overrideURL.isEmpty || overrideStatus == .fetching)

                    Spacer()

                    switch overrideStatus {
                    case .idle:
                        if QuoteConfiguration.jsOverride != nil {
                            Text("Cached ✓")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    case .fetching:
                        ProgressView()
                            .controlSize(.small)
                    case .success:
                        Text("Updated ✓")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .failed(let msg):
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    }
                }

                if QuoteConfiguration.jsOverride != nil {
                    Button(role: .destructive) {
                        QuoteConfiguration.clearOverride()
                        overrideStatus = .idle
                    } label: {
                        Label("Clear Override (use bundled)", systemImage: "trash")
                    }
                }

                Text("Optional. Point to a hosted JS file to hot-fix the Yahoo parser without an app update. Checked on each launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            }

            Section("Data") {
                HStack {
                    Label("Data Status", systemImage: "cylinder.fill")
                    Spacer()
                    Text(hasImported ? "Imported" : "Not Imported")
                        .foregroundStyle(.secondary)
                }

                Button {
                    showOFXFilePicker = true
                } label: {
                    Label("Import OFX File", systemImage: "arrow.down.doc.fill")
                }
                .disabled(isImporting)

                Button {
                    showMoneyFilePicker = true
                } label: {
                    Label("Import Money File (.json)", systemImage: "square.and.arrow.down")
                }
                .disabled(isImporting)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                }
                .disabled(isImporting)
            }

            if isImporting {
                Section {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Importing…")
                    }
                }
            }

            if let message = statusMessage {
                Section {
                    Label(message, systemImage: statusIsError ? "xmark.circle" : "checkmark.circle")
                        .foregroundStyle(statusIsError ? .red : .green)
                }
            }

            Section("About") {
                infoRow("Version", value: "1.0", icon: "info.circle")
                infoRow("Database Format", value: "MS Money (.mny)", icon: "doc.fill")
                infoRow("Compatibility", value: "Money Sunset Edition", icon: "checkmark.shield")
            }

            Section("Format Support") {
                Label("Import: OFX 1.x (SGML) & 2.x (XML)", systemImage: "arrow.down.doc")
                Label("Import: .mny → JSON export", systemImage: "arrow.down.doc")
                Label("Export: OFX 2.0", systemImage: "arrow.up.doc")
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete all financial data?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) {
                deleteAllData()
            }
        } message: {
            Text("This will permanently remove all accounts, transactions, categories, payees, investments, and budgets. You'll need to re-import a Money file to use the app.")
        }
        .fileImporter(
            isPresented: $showMoneyFilePicker,
            allowedContentTypes: [UTType.json],
            allowsMultipleSelection: false
        ) { result in
            handleMoneyFileImport(result)
        }
        .fileImporter(
            isPresented: $showOFXFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "ofx") ?? .plainText,
                                  UTType(filenameExtension: "qfx") ?? .plainText,
                                  .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleOFXFileImport(result)
        }
    }

    private func infoRow(_ label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func deleteAllData() {
        statusMessage = nil
        do {
            try PersistenceController.shared.deleteAllData()
            hasImported = false
            statusMessage = "All data deleted"
            statusIsError = false
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
            statusIsError = true
        }
    }

    private func handleMoneyFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Must access security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                statusMessage = "Cannot access file"
                statusIsError = true
                return
            }

            isImporting = true
            statusMessage = nil

            Task {
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    // Delete existing data first
                    try PersistenceController.shared.deleteAllData()

                    let service = MoneyImportService(context: viewContext)
                    try await service.importJSON(from: url)
                    UserDefaults.standard.set(true, forKey: "hasImportedData")

                    await MainActor.run {
                        hasImported = true
                        isImporting = false
                        statusMessage = "Import complete"
                        statusIsError = false
                    }
                } catch {
                    await MainActor.run {
                        isImporting = false
                        statusMessage = "Import failed: \(error.localizedDescription)"
                        statusIsError = true
                    }
                }
            }

        case .failure(let error):
            statusMessage = "File picker error: \(error.localizedDescription)"
            statusIsError = true
        }
    }

    private func handleOFXFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            guard url.startAccessingSecurityScopedResource() else {
                statusMessage = "Cannot access file"
                statusIsError = true
                return
            }

            isImporting = true
            statusMessage = nil

            Task {
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let service = OFXImportService(context: viewContext)
                    let importResult = try await service.importOFX(from: url)
                    UserDefaults.standard.set(true, forKey: "hasImportedData")

                    await MainActor.run {
                        hasImported = true
                        isImporting = false
                        statusMessage = importResult.summary
                        statusIsError = false
                    }
                } catch {
                    await MainActor.run {
                        isImporting = false
                        statusMessage = "OFX import failed: \(error.localizedDescription)"
                        statusIsError = true
                    }
                }
            }

        case .failure(let error):
            statusMessage = "File picker error: \(error.localizedDescription)"
            statusIsError = true
        }
    }

    private func testQuote() async {
        quoteTestStatus = .checking
        do {
            let provider = QuoteConfiguration.makeProvider()
            let q = try await provider.quote(for: "AAPL")
            quoteTestStatus = .valid(String(format: "$%.2f", q.currentPrice))
        } catch {
            quoteTestStatus = .invalid(error.localizedDescription)
        }
    }

    private func fetchOverride() async {
        overrideStatus = .fetching
        await QuoteConfiguration.refreshJSOverride()
        if QuoteConfiguration.jsOverride != nil {
            overrideStatus = .success
        } else {
            overrideStatus = .failed("Failed or invalid JS")
        }
    }
}

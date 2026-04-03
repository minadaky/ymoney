import SwiftUI

/// App settings
struct SettingsView: View {
    @State private var hasImported = UserDefaults.standard.bool(forKey: "hasImportedData")
    @State private var quoteTestStatus: QuoteTest = .idle
    @State private var overrideURL = QuoteConfiguration.jsOverrideURL ?? ""
    @State private var overrideStatus: OverrideStatus = .idle

    private enum QuoteTest: Equatable {
        case idle, checking, valid(String), invalid(String)
    }

    private enum OverrideStatus: Equatable {
        case idle, fetching, success, failed(String)
    }

    var body: some View {
        List {
            Section("Quotes") {
                HStack {
                    Label("Data Source", systemImage: "chart.line.uptrend.xyaxis")
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

            Section("Data") {
                HStack {
                    Label("Data Status", systemImage: "cylinder.fill")
                    Spacer()
                    Text(hasImported ? "Imported" : "Not Imported")
                        .foregroundStyle(.secondary)
                }

                Button(role: .destructive) {
                    UserDefaults.standard.set(false, forKey: "hasImportedData")
                    hasImported = false
                } label: {
                    Label("Reset Data", systemImage: "trash")
                }
            }

            Section("About") {
                HStack {
                    Label("Version", systemImage: "info.circle")
                    Spacer()
                    Text("1.0")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Database Format", systemImage: "doc.fill")
                    Spacer()
                    Text("MS Money (.mny)")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Compatibility", systemImage: "checkmark.shield")
                    Spacer()
                    Text("Money Sunset Edition")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Format Support") {
                Label("Read: .mny (Jet 4.0 / MSISAM)", systemImage: "arrow.down.doc")
                Label("Export: OFX 2.0", systemImage: "arrow.up.doc")
            }
        }
        .navigationTitle("Settings")
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

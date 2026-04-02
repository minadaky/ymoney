import SwiftUI

/// App settings
struct SettingsView: View {
    @State private var hasImported = UserDefaults.standard.bool(forKey: "hasImportedData")

    var body: some View {
        List {
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
}

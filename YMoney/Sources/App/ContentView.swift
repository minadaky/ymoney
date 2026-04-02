import SwiftUI
import CoreData

/// Root navigation view with tab bar
struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var hasImported = UserDefaults.standard.bool(forKey: "hasImportedData")
    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        Group {
            if hasImported {
                MainTabView()
            } else {
                importView
            }
        }
        .onAppear {
            if !hasImported && !isImporting {
                performImport()
            }
        }
    }

    private var importView: some View {
        VStack(spacing: 24) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("YMoney")
                .font(.largeTitle.bold())

            Text("Microsoft Money for iOS")
                .font(.title3)
                .foregroundStyle(.secondary)

            if isImporting {
                ProgressView("Importing Money database...")
                    .padding()
            } else {
                Button {
                    performImport()
                } label: {
                    Label("Import Money Data", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 40)
            }

            if let error = importError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding()
            }
        }
        .padding()
    }

    private func performImport() {
        isImporting = true
        importError = nil

        Task {
            do {
                let service = MoneyImportService(context: viewContext)
                try await service.importBundledData()
                UserDefaults.standard.set(true, forKey: "hasImportedData")
                await MainActor.run {
                    hasImported = true
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    isImporting = false
                }
            }
        }
    }
}

/// Main tab-based navigation
struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "chart.pie.fill")
            }

            NavigationStack {
                AccountsView()
            }
            .tabItem {
                Label("Accounts", systemImage: "building.columns.fill")
            }

            NavigationStack {
                TransactionsView()
            }
            .tabItem {
                Label("Transactions", systemImage: "list.bullet.rectangle.fill")
            }

            NavigationStack {
                InvestmentsView()
            }
            .tabItem {
                Label("Investments", systemImage: "chart.line.uptrend.xyaxis")
            }

            NavigationStack {
                MoreView()
            }
            .tabItem {
                Label("More", systemImage: "ellipsis.circle.fill")
            }
        }
    }
}

/// "More" tab with additional features
struct MoreView: View {
    var body: some View {
        List {
            NavigationLink {
                BudgetsView()
            } label: {
                Label("Budgets", systemImage: "chart.bar.fill")
            }

            NavigationLink {
                ReportsView()
            } label: {
                Label("Reports", systemImage: "chart.xyaxis.line")
            }

            NavigationLink {
                PayeesView()
            } label: {
                Label("Payees", systemImage: "person.2.fill")
            }

            NavigationLink {
                CategoryPickerView(selectedCategory: .constant(nil), isPresented: .constant(true))
            } label: {
                Label("Categories", systemImage: "tag.fill")
            }

            NavigationLink {
                ExportView()
            } label: {
                Label("Export (OFX)", systemImage: "square.and.arrow.up.fill")
            }

            NavigationLink {
                SettingsView()
            } label: {
                Label("Settings", systemImage: "gearshape.fill")
            }
        }
        .navigationTitle("More")
    }
}

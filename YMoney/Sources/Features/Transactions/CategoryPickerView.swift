import SwiftUI
import CoreData

/// Hierarchical category browser
struct CategoryPickerView: View {
    @Binding var selectedCategory: Category?
    @Binding var isPresented: Bool
    @Environment(\.managedObjectContext) private var viewContext

    @State private var categories: [Category] = []

    var body: some View {
        List {
            ForEach(topLevelCategories, id: \.objectID) { parent in
                Section(parent.fullName ?? "Unknown") {
                    ForEach(childCategories(of: parent), id: \.objectID) { child in
                        Button {
                            selectedCategory = child
                            isPresented = false
                        } label: {
                            HStack {
                                Text(child.fullName ?? "Unknown")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if child == selectedCategory {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                                if child.isTaxRelated {
                                    Image(systemName: "doc.text.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }

                        // Sub-sub categories
                        ForEach(childCategories(of: child), id: \.objectID) { grandchild in
                            Button {
                                selectedCategory = grandchild
                                isPresented = false
                            } label: {
                                HStack {
                                    Text("  " + (grandchild.fullName ?? "Unknown"))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if grandchild == selectedCategory {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .onAppear { loadCategories() }
    }

    private var topLevelCategories: [Category] {
        categories.filter { $0.level == 0 }
    }

    private func childCategories(of parent: Category) -> [Category] {
        let children = parent.children as? Set<Category> ?? []
        return children.sorted { ($0.fullName ?? "") < ($1.fullName ?? "") }
    }

    private func loadCategories() {
        let request = Category.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "fullName", ascending: true)]
        categories = (try? viewContext.fetch(request)) ?? []
    }
}

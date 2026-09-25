import SwiftUI

struct MoveListView: View {
    let items: [ScanItem]

    private var grouped: [(FileCategory, [ScanItem])] {
        let dict = Dictionary(grouping: items) { item -> FileCategory in
            if case .move(let category) = item.action { return category }
            return .other
        }
        return dict.map { ($0.key, $0.value) }.sorted { $0.0.displayName < $1.0.displayName }
    }

    var body: some View {
        if items.isEmpty {
            EmptyStateView(title: "Rien à ranger ici, ce dossier est déjà propre.", systemImage: "checkmark.circle")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Button("Tout cocher") { items.forEach { $0.isSelected = true } }
                    Button("Tout décocher") { items.forEach { $0.isSelected = false } }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)

                List {
                    ForEach(grouped, id: \.0.id) { category, categoryItems in
                        Section("\(category.displayName) → \(category.folderName)/") {
                            ForEach(categoryItems) { item in
                                ScanItemRow(item: item, subtitle: nil)
                            }
                        }
                    }
                }
            }
        }
    }
}

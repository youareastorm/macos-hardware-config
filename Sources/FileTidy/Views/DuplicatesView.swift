import SwiftUI

struct DuplicatesView: View {
    let groups: [DuplicateGroup]

    var body: some View {
        if groups.isEmpty {
            EmptyStateView(title: "Aucun doublon détecté.", systemImage: "doc.on.doc")
        } else {
            List {
                ForEach(groups) { group in
                    Section("Groupe de \(group.items.count) fichiers identiques") {
                        ForEach(group.items) { duplicate in
                            DuplicateItemRow(item: duplicate)
                        }
                    }
                }
            }
        }
    }
}

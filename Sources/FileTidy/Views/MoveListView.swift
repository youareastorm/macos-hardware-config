import SwiftUI

struct MoveListView: View {
    let items: [ScanItem]

    private struct DisplayGroup: Identifiable {
        let id: String
        let destination: MoveDestination
        let items: [ScanItem]
    }

    private var grouped: [DisplayGroup] {
        var map: [String: (MoveDestination, [ScanItem])] = [:]
        for item in items {
            guard case .move(let destination) = item.action else { continue }
            map[destination.relativePath, default: (destination, [])].1.append(item)
        }
        return map
            .map { DisplayGroup(id: $0.key, destination: $0.value.0, items: $0.value.1) }
            .sorted { $0.destination.relativePath < $1.destination.relativePath }
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
                    ForEach(grouped) { group in
                        Section {
                            ForEach(group.items) { item in
                                ScanItemRow(item: item, subtitle: nil)
                            }
                        } header: {
                            header(for: group.destination)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func header(for destination: MoveDestination) -> some View {
        switch destination.kind {
        case .newFolder:
            HStack(spacing: 6) {
                Image(systemName: "folder.badge.plus")
                Text("Nouveau dossier proposé : \(destination.relativePath)/")
            }
        case .existingFolder:
            HStack(spacing: 6) {
                Text("\(destination.category.displayName) → \(destination.relativePath)/")
                Text("dossier existant")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }
        case .defaultCategory:
            Text("\(destination.category.displayName) → \(destination.relativePath)/")
        }
    }
}

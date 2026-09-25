import SwiftUI

struct CleanupListView: View {
    let items: [ScanItem]

    var body: some View {
        if items.isEmpty {
            EmptyStateView(title: "Aucun fichier indésirable détecté.", systemImage: "trash")
        } else {
            VStack(spacing: 0) {
                HStack {
                    Button("Tout cocher") { items.forEach { $0.isSelected = true } }
                    Button("Tout décocher") { items.forEach { $0.isSelected = false } }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 4)

                List(items) { item in
                    ScanItemRow(item: item, subtitle: reason(for: item))
                }
            }
        }
    }

    private func reason(for item: ScanItem) -> String {
        switch item.action {
        case .deleteTorrent: return "Fichier .torrent (métadonnées de téléchargement, plus utile une fois le téléchargement terminé)"
        case .deleteExtractedArchive: return "Archive .zip déjà décompressée à côté"
        case .move: return ""
        }
    }
}

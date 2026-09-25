import SwiftUI

struct ScanItemRow: View {
    @ObservedObject var item: ScanItem
    let subtitle: String?

    var body: some View {
        Toggle(isOn: $item.isSelected) {
            HStack {
                Image(systemName: iconName)
                    .foregroundStyle(isDelete ? .red : .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(ByteFormatter.string(for: item.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }

    private var isDelete: Bool {
        switch item.action {
        case .deleteTorrent, .deleteExtractedArchive: return true
        case .move: return false
        }
    }

    private var iconName: String {
        switch item.action {
        case .move: return "arrow.turn.down.right"
        case .deleteTorrent, .deleteExtractedArchive: return "trash"
        }
    }
}

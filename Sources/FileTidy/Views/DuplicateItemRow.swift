import SwiftUI

struct DuplicateItemRow: View {
    @ObservedObject var item: DuplicateFileItem

    var body: some View {
        Toggle(isOn: $item.isSelectedForDeletion) {
            HStack {
                Image(systemName: item.isSelectedForDeletion ? "trash" : "checkmark.circle")
                    .foregroundStyle(item.isSelectedForDeletion ? .red : .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.fileName)
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(ByteFormatter.string(for: item.size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
    }
}

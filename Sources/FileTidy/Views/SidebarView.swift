import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @ObservedObject var viewModel: OrganizerViewModel
    @State private var showingImporter = false

    var body: some View {
        List(selection: $viewModel.selectedFolderID) {
            Section("Dossiers surveillés") {
                ForEach(viewModel.watchedFolders) { folder in
                    Label(folder.displayName, systemImage: icon(for: folder.kind))
                        .tag(folder.id)
                        .contextMenu {
                            if folder.kind == .custom {
                                Button("Retirer de la liste", role: .destructive) {
                                    viewModel.removeCustomFolder(folder)
                                }
                            }
                        }
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    showingImporter = true
                } label: {
                    Label("Ajouter un dossier", systemImage: "plus")
                }
                .help("Ajouter un autre dossier à surveiller")
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                viewModel.addCustomFolder(url: url)
            }
        }
        .navigationTitle("FileTidy")
    }

    private func icon(for kind: WatchedFolder.Kind) -> String {
        switch kind {
        case .desktop: return "menubar.dock.rectangle"
        case .downloads: return "arrow.down.circle"
        case .custom: return "folder"
        }
    }
}

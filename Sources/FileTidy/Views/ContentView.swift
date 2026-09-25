import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: OrganizerViewModel

    enum Tab: String, CaseIterable, Identifiable {
        case move = "À ranger"
        case cleanup = "À supprimer"
        case duplicates = "Doublons"
        var id: String { rawValue }
    }

    @State private var selectedTab: Tab = .move

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: viewModel)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()

                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(label(for: tab)).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding()

                Group {
                    switch selectedTab {
                    case .move:
                        MoveListView(items: viewModel.moveItems)
                    case .cleanup:
                        CleanupListView(items: viewModel.cleanupItems)
                    case .duplicates:
                        DuplicatesView(groups: viewModel.duplicateGroups)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()
                footer
            }
        }
        .onChange(of: viewModel.selectedFolderID) { _ in
            viewModel.scanSelectedFolder()
        }
        .onAppear {
            viewModel.scanSelectedFolder()
        }
        .alert("Erreur", isPresented: Binding(
            get: { viewModel.lastError != nil },
            set: { if !$0 { viewModel.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }

    private func label(for tab: Tab) -> String {
        switch tab {
        case .move: return "\(tab.rawValue) (\(viewModel.moveItems.count))"
        case .cleanup: return "\(tab.rawValue) (\(viewModel.cleanupItems.count))"
        case .duplicates:
            let count = viewModel.duplicateGroups.reduce(0) { $0 + $1.items.count }
            return "\(tab.rawValue) (\(count))"
        }
    }

    private var header: some View {
        HStack {
            Text(viewModel.selectedFolder?.displayName ?? "Aucun dossier")
                .font(.title2.bold())
            Spacer()
            if viewModel.isScanning {
                ProgressView().controlSize(.small)
            }
            Button {
                viewModel.scanSelectedFolder()
            } label: {
                Label("Analyser", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isScanning || viewModel.selectedFolder == nil)
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            if let summary = viewModel.lastSummary {
                Text(summary).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.applySelected()
            } label: {
                Label("Appliquer les actions sélectionnées", systemImage: "checkmark.circle.fill")
            }
            .keyboardShortcut(.defaultAction)
            .disabled(viewModel.selectedFolder == nil || viewModel.isScanning)
        }
        .padding()
    }
}

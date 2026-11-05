import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.openWindow) private var openWindow

    /// `List` needs an optional binding; the store always has a filter selected,
    /// so clearing the selection is ignored.
    private var selection: Binding<SidebarSelection?> {
        Binding(
            get: { store.sidebarSelection },
            set: { if let value = $0 { store.selectSidebar(value) } }
        )
    }

    var body: some View {
        List(selection: selection) {
            Section("Library") {
                ForEach(SidebarFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.symbol)
                        .badge(count(for: filter))
                        .tag(SidebarSelection.smart(filter))
                }
            }

            Section("Folders") {
                ForEach(store.sidebarFolders, id: \.node.id) { entry in
                    FolderListRow(node: entry.node, depth: entry.depth)
                        .tag(SidebarSelection.folder(entry.node.id))
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search notes")
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .contextMenu {
            Button("New Note") { store.createNote() }
            Button("New Folder") { store.createFolder() }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { store.expandAllFolders() } label: {
                Image(systemName: "chevron.down")
            }
            .help("Expand all folders")

            Button { store.collapseAllFolders() } label: {
                Image(systemName: "chevron.up")
            }
            .help("Collapse all folders")

            Button { store.createFolder() } label: {
                Image(systemName: "folder.badge.plus")
            }
            .help("New folder")

            Spacer(minLength: 0)

            Menu {
                Button("New Note") { store.createNote() }
                Button("New Folder") { store.createFolder() }
                Divider()
                Button("Open Vault in This Window…") { VaultPicker.choose { store.openVault($0) } }
                Button("Open Vault in New Window…") {
                    VaultPicker.choose { url in
                        VaultCoordinator.openInNewWindow(url, openWindow: openWindow)
                    }
                }
                Button("Rescan") { store.rescanPreservingEditor() }
                if let url = store.vaultURL {
                    Button("Reveal Vault in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Divider()
                Button("Close Vault") { store.closeVault() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .help("Vault actions")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func count(for filter: SidebarFilter) -> Int {
        switch filter {
        case .all: return store.allNotesCount
        case .starred: return store.starredCount
        case .recent:
            return store.notes.filter { $0.modified > Date().addingTimeInterval(-60 * 60 * 24 * 14) }.count
        }
    }
}

/// One folder row in the source list. The chevron only appears for folders with
/// children; expansion stays in the store so Expand All / Collapse All work.
struct FolderListRow: View {
    let node: FolderNode
    let depth: Int
    @EnvironmentObject private var store: VaultStore

    private var isExpanded: Bool { store.expandedFolders.contains(node.id) }

    var body: some View {
        HStack(spacing: 5) {
            Button {
                toggleExpanded()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .opacity(node.children.isEmpty ? 0 : 1)
            }
            .buttonStyle(.borderless)
            .disabled(node.children.isEmpty)
            .frame(width: 12)

            Label(node.name, systemImage: node.id.isEmpty ? "house" : "folder")
                .lineLimit(1)
                .badge(node.totalCount)
        }
        .padding(.leading, CGFloat(depth) * 12)
        .contextMenu {
            Button("New Note Here") { store.createNote(in: node.id) }
            Button("New Folder Here") { store.createFolder(in: node.id) }
            Divider()
            Button("Reveal in Finder") {
                if let root = store.vaultURL {
                    NSWorkspace.shared.activateFileViewerSelecting([root.appendingPathComponent(node.id)])
                }
            }
        }
    }

    private func toggleExpanded() {
        if isExpanded {
            store.expandedFolders.remove(node.id)
        } else {
            store.expandedFolders.insert(node.id)
        }
    }
}

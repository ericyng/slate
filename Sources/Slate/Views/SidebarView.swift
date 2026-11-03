import SwiftUI
import AppKit

struct SidebarView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(SidebarFilter.allCases) { filter in
                        SidebarRow(
                            icon: filter.symbol,
                            title: filter.title,
                            count: count(for: filter),
                            isSelected: store.sidebarSelection == .smart(filter)
                        ) {
                            store.selectSidebar(.smart(filter))
                        }
                    }

                    Divider()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)

                    HStack(spacing: 4) {
                        Text("FOLDERS")
                            .font(.system(size: 10.5, weight: .semibold))
                            .kerning(0.6)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            store.expandAllFolders()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Expand all folders")

                        Button {
                            store.collapseAllFolders()
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Collapse all folders")

                        Button {
                            store.createFolder()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("New folder")
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)

                    if store.vaultURL != nil {
                        FolderRow(node: store.rootNode, depth: 0, icon: "house")
                    }

                    if store.tree.isEmpty {
                        Text("No folders yet")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 2)
                    }

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 8)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(store.vaultName)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .kerning(0.5)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
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
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 20)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private func count(for filter: SidebarFilter) -> Int {
        switch filter {
        case .all: return store.allNotesCount
        case .starred: return store.starredCount
        case .recent: return store.notes.filter { $0.modified > Date().addingTimeInterval(-60 * 60 * 24 * 14) }.count
        }
    }
}

struct SidebarRow: View {
    let icon: String
    let title: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11.5))
                .frame(width: 16)
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary.opacity(0.8))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 25)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovered = $0 }
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor)
        } else if hovered {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
    }
}

struct FolderRow: View {
    let node: FolderNode
    let depth: Int
    var icon: String = "folder"
    @EnvironmentObject private var store: VaultStore
    @State private var hovered = false

    private var isSelected: Bool { store.sidebarSelection == .folder(node.id) }
    private var isExpanded: Bool { store.expandedFolders.contains(node.id) }

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 5) {
                Group {
                    if node.children.isEmpty {
                        Color.clear.frame(width: 12)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
                            .frame(width: 12)
                            .contentShape(Rectangle())
                            .onTapGesture { toggleExpanded() }
                    }
                }
                .frame(width: 12)

                Image(systemName: node.id.isEmpty ? "house" : (isExpanded && !node.children.isEmpty ? "folder.fill" : "folder"))
                    .font(.system(size: 11.5))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor.opacity(0.9))

                Text(node.name)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if node.totalCount > 0 {
                    Text("\(node.totalCount)")
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary.opacity(0.8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.leading, CGFloat(depth) * 12)
            .frame(height: 25)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .contentShape(Rectangle())
            .onTapGesture {
                store.selectSidebar(.folder(node.id))
                if !node.children.isEmpty { store.expandedFolders.insert(node.id) }
            }
            .onHover { hovered = $0 }
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

            if isExpanded {
                ForEach(node.children) { child in
                    FolderRow(node: child, depth: depth + 1)
                }
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor)
        } else if hovered {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.06))
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

import SwiftUI
import AppKit

struct NoteListView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.renameRequest) private var rename
    @State private var hoveredID: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            Divider()

            if store.visibleNotes.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(store.visibleNotes) { note in
                            NoteRow(
                                note: note,
                                isSelected: note.id == store.selectedNoteID,
                                isStarred: store.starred.contains(note.id),
                                isHovered: hoveredID == note.id
                            )
                            .onTapGesture { store.select(noteID: note.id) }
                            .onHover { hoveredID = $0 ? note.id : (hoveredID == note.id ? nil : hoveredID) }
                            .contextMenu {
                                Button(store.starred.contains(note.id) ? "Unstar" : "Star") {
                                    store.toggleStar(note.id)
                                }
                                Button("Rename…") {
                                    rename.begin(note.id, note.url.deletingPathExtension().lastPathComponent)
                                }
                                Divider()
                                Button("Open in Default App") { store.openInEditor(note.id) }
                                Button("Reveal in Finder") { store.revealInFinder(note.id) }
                                Divider()
                                Button("Move to Trash") { store.deleteNote(id: note.id) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(store.selectionTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text("\(store.visibleNotes.count)")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)

            Menu {
                Picker("Sort By", selection: $store.sort) {
                    ForEach(NoteSort.allCases) { sort in
                        Text(sort.title).tag(sort)
                    }
                }
                Divider()
                Button("New Note") { store.createNote() }
                Button("New Folder") { store.createFolder() }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Search", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: store.searchText.isEmpty ? "note.text" : "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(store.searchText.isEmpty ? "No notes here" : "No matches")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if store.searchText.isEmpty {
                Button("New Note") { store.createNote() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    let isStarred: Bool
    let isHovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(note.title)
                    .font(.system(size: 12.8, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                if isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.orange)
                }
                Spacer(minLength: 4)
                Text(DateText.listStamp(note.modified))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
            }
            HStack(spacing: 4) {
                Text(note.snippet)
                    .font(.system(size: 11.5))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isSelected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor)
                        .padding(.horizontal, 6)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                        .padding(.horizontal, 6)
                }
            }
        )
        .contentShape(Rectangle())
    }
}

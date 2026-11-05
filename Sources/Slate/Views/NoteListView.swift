import SwiftUI
import AppKit

struct NoteListView: View {
    @EnvironmentObject private var store: VaultStore
    @Environment(\.renameRequest) private var rename

    /// `List` drives selection, arrow keys and keyboard focus. Clearing the
    /// selection is ignored so the detail pane always has a note.
    private var selection: Binding<String?> {
        Binding(
            get: { store.selectedNoteID },
            set: { if let id = $0 { store.select(noteID: id) } }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)

            if store.visibleNotes.isEmpty {
                emptyState
            } else {
                List(selection: selection) {
                    ForEach(store.visibleNotes) { note in
                        NoteRow(
                            note: note,
                            isStarred: store.starred.contains(note.id)
                        )
                        .tag(note.id)
                        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            note.id == store.selectedNoteID
                                ? Color.accentColor.opacity(0.16)
                                : Color.clear
                        )
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
                .listStyle(.inset)
                .environment(\.defaultMinListRowHeight, 44)
                .scrollContentBackground(.hidden)
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

            Button {
                store.createNote()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.borderless)
            .help("New note (⌘N)")

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
            .help("Sort and create")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
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
            } else {
                Button("Clear Search") { store.searchText = "" }
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
    let isStarred: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(note.title)
                    .font(.system(size: 12.8, weight: .semibold))
                    .lineLimit(1)
                if isStarred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 4)
                Text(DateText.listStamp(note.modified))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(note.snippet)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

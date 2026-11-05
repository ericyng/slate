import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var prefs: Preferences
    @State private var renameTarget: String?
    @State private var renameText = ""
    @State private var observesTermination = false
    /// Per-window column state; the system remembers the sidebar width.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if store.vaultURL == nil {
                WelcomeView()
            } else {
                mainLayout
            }
        }
        .frame(minWidth: 920, minHeight: 600)
        .toolbar { toolbarContent }
        .alert("Rename Note", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let id = renameTarget { store.renameNote(id: id, to: renameText) }
                renameTarget = nil
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onAppear {
            guard !observesTermination else { return }
            observesTermination = true
            NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { store.flushSave() }
            }
        }
        .environment(\.renameRequest, RenameRequest { id, name in
            renameTarget = id
            renameText = name
        })
    }

    private var mainLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 236, max: 340)
        } content: {
            NoteListView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 306, max: 460)
        } detail: {
            DetailView()
        }
        .navigationSplitViewStyle(.balanced)
        // Content fades under the toolbar instead of a hard line appearing.
        .modifier(ScrollEdgeFade())
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                store.createNote()
                EditorCommandCenter.shared.focus()
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            .slateProminentButton()
            .help("New note (⌘N)")
            .disabled(store.vaultURL == nil)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if store.selectedNote != nil, store.layout.showsEditor {
                Button { EditorCommandCenter.shared.wrap("**") } label: {
                    Image(systemName: "bold")
                }
                .help("Bold (⌘B)")

                Button { EditorCommandCenter.shared.wrap("*") } label: {
                    Image(systemName: "italic")
                }
                .help("Italic (⌘I)")

                Button { EditorCommandCenter.shared.wrap("`") } label: {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                }
                .help("Inline code (⌘E)")

                Menu {
                    Button("Heading 1") { EditorCommandCenter.shared.setHeading(1) }
                    Button("Heading 2") { EditorCommandCenter.shared.setHeading(2) }
                    Button("Heading 3") { EditorCommandCenter.shared.setHeading(3) }
                    Button("Body Text") { EditorCommandCenter.shared.setHeading(0) }
                    Divider()
                    Button("Bulleted List") { EditorCommandCenter.shared.toggleLinePrefix("- ") }
                    Button("Numbered List") { EditorCommandCenter.shared.applyNumberedList() }
                    Button("Quote") { EditorCommandCenter.shared.toggleLinePrefix("> ") }
                    Button("Task") { EditorCommandCenter.shared.toggleLinePrefix("- [ ] ") }
                    Button("Code Block") { EditorCommandCenter.shared.insertCodeBlock() }
                } label: {
                    Image(systemName: "textformat")
                }
                .menuIndicator(.hidden)
                .help("Paragraph styles")
            }

            if let note = store.selectedNote {
                Button {
                    store.toggleStar(note.id)
                } label: {
                    Image(systemName: store.starred.contains(note.id) ? "star.fill" : "star")
                }
                .help(store.starred.contains(note.id) ? "Unstar" : "Star")
            }

            Picker("Layout", selection: Binding(
                get: { store.layout },
                set: { value in
                    store.flushSave()
                    store.setLayout(value)
                }
            )) {
                ForEach(EditorLayout.allCases) { layout in
                    Label(layout.shortTitle, systemImage: layout.symbol)
                        .labelStyle(.iconOnly)
                        .tag(layout)
                }
            }
            .pickerStyle(.segmented)
            .help("Write, split, or read — ⌘1 / ⌘2 / ⌘3 (⌘R toggles read)")
            .disabled(store.selectedNote == nil)
        }
    }
}

/// Lets deep views (note rows) ask the window for a rename sheet.
struct RenameRequest {
    var begin: (String, String) -> Void
}

private struct RenameRequestKey: EnvironmentKey {
    static let defaultValue = RenameRequest { _, _ in }
}

extension EnvironmentValues {
    var renameRequest: RenameRequest {
        get { self[RenameRequestKey.self] }
        set { self[RenameRequestKey.self] = newValue }
    }
}

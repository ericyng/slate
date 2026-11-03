import SwiftUI
import AppKit

struct WelcomeView: View {
    @EnvironmentObject private var store: VaultStore

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 14) {
                AppGlyph(size: 76)

                VStack(spacing: 4) {
                    Text("Slate")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text("Markdown notes, in plain folders.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    feature("folder", "Point it at any folder", "Every .md file is a note, every folder is a notebook. No database, no lock-in.")
                    feature("textformat", "Live markdown", "Text is styled as you type, and the rendered page updates beside the source. ⌘R gives you the full page.")
                    feature("magnifyingglass", "Instant search", "Search titles and full text across the whole vault.")
                }
                .padding(.top, 6)

                HStack(spacing: 10) {
                    Button("Choose Vault…") {
                        VaultPicker.choose { store.openVault($0) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)

                    Button("Create Sample Vault") {
                        if let url = SampleVault.create() {
                            store.openVault(url)
                        }
                    }
                    .controlSize(.large)
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: 430)

            Spacer()

            Text("Notes are saved as UTF-8 markdown, so they open in any editor.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The icon drawn in-app, and reused by the icon generator.
struct AppGlyph: View {
    var size: CGFloat = 64

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.98, green: 0.78, blue: 0.36),
                                 Color(red: 0.94, green: 0.55, blue: 0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)

            VStack(spacing: size * 0.06) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(Color.white.opacity(index == 0 ? 0.95 : 0.72))
                        .frame(width: size * (index == 0 ? 0.46 : 0.52), height: size * 0.07)
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.15), radius: size * 0.06, y: size * 0.02)
    }
}

enum SampleVault {
    @MainActor
    static func create() -> URL? {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let root = documents.appendingPathComponent("Slate Vault")

        let files: [(String, String)] = [
            ("Welcome.md", welcomeNote),
            ("Getting Started/Syntax Cheat Sheet.md", syntaxNote),
            ("Getting Started/Keyboard Shortcuts.md", shortcutsNote),
            ("Projects/Roadmap.md", roadmapNote),
            ("Projects/Design Notes.md", designNote),
            ("Journal/2026-11-01.md", journalNote),
            ("Reading List.md", readingNote)
        ]

        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for (path, contents) in files {
                let url = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try contents.write(to: url, atomically: true, encoding: .utf8)
                }
            }
            return root
        } catch {
            return nil
        }
    }

    static let welcomeNote = """
    # Welcome to Slate

    This is a markdown vault. Every note here is a real `.md` file inside the folder
    **Slate Vault**, so you can open it in any editor, sync it with iCloud or git, and
    never worry about a proprietary database.

    ## Three things to try

    - Press **⌘N** to start a note. The first heading becomes its title.
    - Press **⌘R** to switch between *write* and *read* mode.
    - Type `**bold**`, `*italic*`, `` `code` ``, or `- [ ] a task` and watch it style itself.

    > The syntax stays visible while you write. Nothing is hidden from you, and nothing
    > is lost when you open the file somewhere else.

    ## What lives in a vault

    1. Folders become notebooks in the sidebar.
    2. Notes are listed newest first, with starred notes pinned to the top.
    3. A small `.slate` folder remembers stars and the last note you had open.

    ---

    Start by deleting these samples, or keep them around as a reference.
    """

    static let syntaxNote = """
    # Syntax Cheat Sheet

    ## Text

    **Bold**, *italic*, ***both***, ~~strikethrough~~, and `inline code`.

    A [link](https://example.com) keeps its target hidden in read mode.

    ## Structure

    # Heading 1
    ## Heading 2
    ### Heading 3

    ---

    ## Lists

    - A bullet
      - A nested bullet
    - Another bullet

    1. First
    2. Second
    3. Third

    - [x] A finished task
    - [ ] An open task

    ## Quotes

    > A quote is indented and quiet.
    > It can span several lines.

    ## Code

    ```swift
    struct Note {
        let title: String
        let body: String
    }
    ```
    """

    static let shortcutsNote = """
    # Keyboard Shortcuts

    - **⌘N** — new note
    - **⇧⌘N** — new folder
    - **⌘O** — open a different vault
    - **⌘S** — save now (notes save themselves anyway)
    - **⌘R** — toggle read mode
    - **⌘B** / **⌘I** — bold / italic
    - **⌘E** — inline code
    - **⌥⌘1…3** — heading levels
    - **⌘[** / **⌘]** — previous / next note
    - **⌘F** — find inside the current note
    """

    static let roadmapNote = """
    # Roadmap

    ## Now

    - [x] Vault folders and plain markdown files
    - [x] Live styling in the editor
    - [ ] Wikilinks between notes
    - [ ] Backlinks panel

    ## Next

    1. Export to PDF
    2. Tag browser
    3. Optional encrypted notes

    ## Later

    - iOS companion
    - Quick capture from the menu bar

    > Keep this list honest: if it has not moved in three weeks, delete it.
    """

    static let designNote = """
    # Design Notes

    The goal is *Apple Notes calm* with *Obsidian honesty*.

    ## Principles

    - **One window, three columns.** Folders, notes, text. No tabs to manage.
    - **Plain text wins.** If Slate disappeared tomorrow, the vault still reads fine.
    - **Styling, not hiding.** Markdown symbols stay visible in write mode; read mode is for reading.

    ## Open questions

    - How loud should a starred note be?
    - Should the editor follow the cursor into read mode?
    - Do we need per-folder sort settings?
    """

    static let journalNote = """
    # 1 November 2026

    Started building Slate today: a markdown notes app that feels like Apple Notes and
    stores everything in a normal folder.

    ## Log

    - 09:20 — Stubbed the vault scanner and sidebar tree
    - 11:05 — Live markdown styling in `NSTextView`
    - 14:40 — Read mode renderer, search, stars
    - 16:15 — Sample vault so the app has something to show

    ## Tomorrow

    - Wikilinks and backlinks
    - Better empty states
    """

    static let readingNote = """
    # Reading List

    - [x] *The Design of Everyday Things* — Don Norman
    - [ ] *Thinking in Systems* — Donella Meadows
    - [ ] *Shape Up* — Ryan Singer
    - [ ] [The Grug Brained Developer](https://grugbrain.dev)

    ## Notes

    Keep one sentence per book about *why* it is on the list.
    """
}

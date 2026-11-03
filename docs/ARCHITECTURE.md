# Architecture

A multi-window SwiftUI app with one AppKit island: the `NSTextView` that does the actual editing. About 4,300 lines of Swift, no third-party dependencies.

Each window owns one vault, so several vaults can be open side by side.

## Module map

```
SlateApp.swift          App/Scene, menu commands, vault picker, AppDelegate (flush on quit)
Model/
  Note.swift            Note, FolderNode, sidebar filters, sort orders
  VaultStore.swift      the only stateful object: scanning, CRUD, search, autosave, metadata
  Preferences.swift     persisted settings (theme, layout, font, autosave, …)
Markdown/
  MarkdownParser.swift  NSString → [MarkdownBlock] with source ranges + inline spans
  MarkdownRenderer.swift theme + two outputs (editor attribute runs, read-mode string)
Views/
  ContentView.swift     three-pane shell, toolbar, layout picker, rename alert, error alert
  SidebarView.swift     smart lists, folder tree with Vault Root + expand/collapse all, vault menu
  NoteListView.swift    search field, sort menu, rows, context menus
  DetailView.swift      filename header, word count, layout host (source / live / split / reading)
  EditorView.swift      MarkdownEditor (editable NSTextView) + MarkdownPreview (read-only)
  SettingsView.swift    General / Appearance / Advanced preference tabs
  VaultWindowView.swift one window = one VaultStore, launch bootstrap, focused-value wiring
  WelcomeView.swift     first-run screen, app glyph, embedded sample vault
Services/
  FSEventsWatcher.swift recursive vault change notifications
Support/
  EditorCommandCenter.swift  formatting + find commands against the focused window's editor
  VaultCoordinator.swift     registry of open vault windows, routing "open vault" to the right one
  Formatting.swift           date formatting
```

`VaultStore` is a `@MainActor ObservableObject` injected with `.environmentObject`. Everything that mutates the vault goes through it, so the file system and the UI cannot disagree.

## Data model

```swift
struct Note {
    let id: String        // path relative to the vault root, e.g. "Projects/Roadmap.md"
    let url: URL
    let folder: String    // "" for the vault root
    var title: String     // first heading → first line → filename
    var snippet: String   // first body line, markdown stripped
    var modified, created: Date
    var body: String      // full text, kept in memory
}
```

`id` is the path, not a UUID — that keeps selection, stars and the metadata file meaningful across launches and portable across machines.

`FolderNode` is a value-type tree built from the set of directories that contain notes, with a recursive `totalCount`.

## Vault scanning

`VaultStore.scan()` walks the root with `FileManager.enumerator`, skipping hidden files, package descendants, and editor bundles (`*.xcodeproj`, `*.code`, `*.sublime-project`). For each markdown-ish file under 2 MB it reads the text (`UTF-8`, falling back to ISO Latin-1) and derives title/snippet **once**, at scan time, so list rendering never touches disk.

Notes are kept in one flat `[Note]` array; the sidebar tree and every list are derived from it. That keeps "one source of truth" simple at the cost of a full re-derive on change — fine for thousands of notes, which is the target size.

`visibleNotes` applies, in order: sidebar scope (smart list, or folder + descendants by prefix), search (case-insensitive substring over title, filename and body), sort (edited/created/title), then starred-first.

## Markdown pipeline

The core idea: **parse once into ranges, render twice.**

```swift
struct MarkdownBlock {
    var kind: BlockKind            // heading(level), paragraph, bullet, numbered,
                                   // task(done), quote, code(lang), rule, blank
    var range: NSRange             // whole block including newline
    var contentRange: NSRange      // text without the block marker
    var markerRange: NSRange?      // "# ", "- ", "> ", the fence line, …
    var indent: Int
    var inlines: [InlineSpan]      // bold/italic/code/strike/link, plus `syntax` spans
}
```

All offsets are **UTF-16 `NSRange`** over an `NSString`, which is what AppKit wants, so no index conversion happens after parsing.

The parser walks lines, handles fenced blocks first (so their contents are never inline-parsed), then classifies each line in order: rule → heading → task → bullet → numbered → quote → paragraph. Inline scanning is a small left-to-right delimiter scanner (not regex soup) supporting `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``, `[text](url)`, with recursion into bold/italic interiors and a pass that marks every delimiter as `syntax`.

Two consumers:

- **`editorRuns(for:)`** returns `[(NSRange, attributes)]`: a base body style for the whole document, a per-block style (heading size, code background, quote colour, list indents), then inline runs, with `syntax` spans dimmed to tertiary colour. Applied to the real text storage, so the file on disk is untouched.
- **`rendered(_:)`** rebuilds an `NSAttributedString`: it walks the block list, emits the marker (•, 1., ☑/☐) where useful, and copies only the non-syntax segments of each block, layering bold/italic/code/link attributes. Links get `.link` URLs so they are clickable.

Because both read the same ranges, there is no second markdown implementation to drift.

## The editor island

`MarkdownEditor` is an `NSViewRepresentable` around `NSTextView.scrollableTextView()`:

- `isRichText = false`, so the string is always plain markdown and paste is plain.
- Automatic quote/dash/text replacement and link detection are off — they would silently rewrite syntax.
- `textDidChange` re-parses the document, then re-applies attributes **only to the edited block** (the blank-line-delimited block plus one neighbour on each side). A full repaint happens on note switch, font-size change, or when the number of ``` fence lines changes — a fence flips how everything below it parses. Attribute edits are wrapped in `undoManager.disableUndoRegistration()`, so `⌘Z` restores *text*, not styling. Restyling is skipped while an IME composition is in flight (`hasMarkedText()`).
- After styling, `typingAttributes` is reset to body style, so the next keystroke does not inherit a heading font.
- `updateNSView` only replaces the string when it actually differs from the binding, which avoids clobbering the caret while typing; on a real change (note switch) it resets the selection and scroll to the top.

`MarkdownPreview` is the same wrapper with `isEditable = false` and a rendered attributed string. In split view it re-renders on every keystroke but keeps the reader's place as a *fraction* of the scrollable height, so the view does not drift as text above the viewport grows.

Known trade-off: the document is still parsed in full on every keystroke (linear, cheap), while attribute application is now block-scoped so AppKit only re-lays-out the visible edit.

## Autosave and rename flow

```
keystroke → textDidChange → binding → store.updateEditorText
          → 400 ms debounce task → write(id:text)
          → note.title/snippet/modified updated
          → maybeAutoRename (only while the file is still "Untitled…")
```

Flushes (`flushSave`) run on note switch, mode switch, `⌘S`, vault close, and app termination. Writes are `String.write(to:atomically:true)`.

Auto-rename is deliberately narrow: filename must still start with `Untitled` and have extension `.md`, and the body must start with a `# ` heading after blank lines. It updates the note id, star bookkeeping and selection in place; the editor text is not reloaded, so the caret stays put.

## External changes

`FSEventsWatcher` wraps an `FSEventStream` (file-level events, 0.4 s latency) on the vault root and calls back on the main queue. `VaultStore` debounces 700 ms, then rescans.

Two guards keep it from fighting the user:

- **Self-write suppression** — rescans within 1.2 s of Slate's own write are ignored, except when a save is pending.
- **Editor preservation** — the selected note keeps its in-memory body, title and snippet (i.e. your unsaved typing) even if the disk version looks different; only files that vanished are dropped from the selection.

## UI structure

`ContentView` composes `SidebarView | NoteListView | DetailView` in an `HStack` with fixed 236/306 pt side columns rather than `NavigationSplitView`, because the three panes are always visible and the widths are stable. Selection is one enum:

```swift
enum SidebarSelection { case smart(SidebarFilter), folder(String) }
```

Rows are custom views (hover state, accent fill, counts) instead of `List`, which keeps the Apple Notes look and avoids `List`'s selection quirks with mixed smart/folder rows.

Menu bar commands are declared in `SlateApp` and act on the focused window through `.focusedSceneValue(\.vaultStore, store)`, so `⌘N`, `⌘S`, layout switches and note navigation apply to the window in front.

Editing commands do not touch the store: they go through `EditorCommandCenter.shared`, which implements marker toggling, heading levels, list prefixes and fenced blocks as text insertions. Its target is resolved from `NSApp.keyWindow`'s responder chain (falling back to an editable `NSTextView` found in that window's view tree), never from a single stored reference — otherwise a command issued right after switching windows would edit the background window. The same object owns **Find**: it forwards `⌘F` / `⌘G` to `NSTextView.performTextFinderAction(_:)`, which is what actually shows AppKit's find bar over the editor (`usesFindBar = true`).

## Windows and layouts

`WindowGroup(id: "vault")` hosts `VaultWindowView`, which creates one `VaultStore` per window. `VaultRegistry` is a weak table of live stores keyed by vault path, so opening a vault that is already open raises its window instead of duplicating it, and `VaultCoordinator` routes `⌘O` / `⇧⌘O` to the current window or a new one. `LaunchState` makes only the first window of a launch restore the last vault; extra windows start at the welcome screen.

The right pane has four layouts, held per window in `VaultStore.layout` and initialised from `Preferences.defaultLayout`:

- **Source** (`⌘1`) — `NSTextView` with every marker visible but dimmed.
- **Live preview** (`⌘2`, default) — the same `NSTextView`, but `MarkdownEditor(concealSyntax: true)` paints markers and inline delimiters in a 0.1 pt clear font on every block except the one holding the caret. Concealed characters stay in the string, so the file on disk is untouched and the caret's model of the text is unchanged. List and task markers are only dimmed, never hidden, since the dash and checkbox carry the list semantics.
- **Side by side** (`⌘3`) — `HSplitView` of editor and preview.
- **Reading** (`⌘4`) — preview only.

`⌘R` toggles reading against the last writing layout. Revealing/concealing is driven by `textViewDidChangeSelection`: it compares the caret's blank-line-delimited block (`Coordinator.blockSpan`, exact, no neighbour widening) with the last painted one and restyles only the union of the two. Edits use the wider `blockRange` scope so a merge with a neighbour repaints too.

The sidebar tree is rooted at a synthetic `Vault Root` row (`VaultStore.rootNode`, id `""`): selecting it shows only notes whose `folder` is empty, which is how root-level files such as `Note.md` become reachable. `expandAllFolders()` / `collapseAllFolders()` drive `expandedFolders` from `allFolderIDs` (the root id included).

Preferences are a single `@MainActor ObservableObject` shared by every window and persisted in `UserDefaults`; views observe it, and `VaultStore` reads the values it needs at decision time (autosave delay, auto-rename, external watching).

## Extension points

**Add a block type** (say, tables):
1. Extend `BlockKind` and classify the line in `MarkdownParser.parse`.
2. Return the right `paragraphStyle` from `MarkdownRenderer.paragraphStyle(for:indent:)`.
3. Add attributes in `editorRuns` and an emit branch in `rendered`.
4. Add a case to the exhaustive switches — the compiler lists them for you.

**Add a formatting command:** add a method to `EditorCommandCenter`, expose it in `SlateApp`'s Format menu and optionally in `ContentView.toolbar`.

**Add a sidebar mode:** add a case to `SidebarFilter` (title + SF Symbol), then handle it in `VaultStore.visibleNotes`.

## Testing

`swift test` runs the parser/renderer/metadata suite plus `ScopedRestyleTests` (block-range maths for partial restyling and live-preview block spans) and `LivePreviewTests` (marker concealment and reveal). The pieces worth testing are pure functions over strings, which is why parsing and rendering were kept out of the views. GUI flows were verified by driving the built app through the accessibility tree: create → type → autosave → auto-rename → layouts → search → star → trash, plus folder creation and two vault windows.

## Deliberate limits

- One vault per window, and no tabs: open a second window for a second vault. Each window's vault is remembered only for the session, so the next launch reopens one window rather than a pile of them.
- No sandbox, no security-scoped bookmarks: the app is built for local use and reads the folder path directly.
- No file coordination (`NSFileCoordinator`) with iCloud; a sync client mid-write could momentarily produce a stale read.
- UTF-16 offsets mean a surrogate pair is never split, but combining characters are walked naively — harmless for styling.

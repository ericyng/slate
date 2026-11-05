import Foundation
import AppKit

enum SidebarSelection: Hashable {
    case smart(SidebarFilter)
    case folder(String)
    case tag(String)
}

/// A folder prepared for the source list: the node plus how deep to indent it.
struct SidebarFolderEntry: Hashable {
    let node: FolderNode
    let depth: Int
}

@MainActor
final class VaultStore: ObservableObject {

    init() {
        layout = Preferences.shared.defaultLayout
        previousLayout = Preferences.shared.defaultLayout == .preview ? .editor : Preferences.shared.defaultLayout
    }

    // MARK: Vault state

    @Published private(set) var vaultURL: URL?
    @Published private(set) var notes: [Note] = [] {
        didSet { rebuildSearchIndex(); invalidateDerived() }
    }
    @Published private(set) var tree: [FolderNode] = []
    @Published private(set) var isLoaded = false
    /// Live word count for the meta bar, refreshed on a short debounce rather
    /// than recomputed from the whole document on every keystroke.
    @Published private(set) var wordCount: Int = 0

    // MARK: UI state

    @Published var sidebarSelection: SidebarSelection = .smart(.all) {
        didSet { invalidateDerived() }
    }
    @Published var selectedNoteID: String?
    @Published var searchText: String = "" {
        didSet { invalidateDerived() }
    }
    @Published var sort: NoteSort = .modified {
        didSet { invalidateDerived() }
    }
    @Published var layout: EditorLayout
    @Published var expandedFolders: Set<String> = []
    @Published var editorText: String = ""
    @Published var errorMessage: String?

    /// The NSWindow hosting this store. Set by `WindowAccessor`.
    weak var window: NSWindow?
    /// Guards the one-time launch bootstrap in `VaultWindowView`.
    var didBootstrap = false

    // MARK: Private

    private var previousLayout: EditorLayout
    private var watcher: FSEventsWatcher?
    private var rescanTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var wordCountTask: Task<Void, Never>?
    private var pendingSaveID: String?
    private var lastSelfWrite = Date.distantPast

    /// Derived lists are expensive (filter, case-folded search, sort) and the
    /// views ask for them several times per render, so they are computed once
    /// and invalidated when their inputs change.
    private var cachedVisibleNotes: [Note]?
    private var cachedTags: [String]?
    /// Lowercased title + filename + body per note id, so a search does not
    /// allocate a new lowercased copy of every note body on each keystroke.
    private var searchIndex: [String: String] = [:]

    private static let metadataDir = ".slate"
    private static let lastVaultKey = "lastVaultPath"

    var vaultName: String {
        vaultURL?.lastPathComponent ?? "Vault"
    }

    var selectedNote: Note? {
        guard let id = selectedNoteID else { return nil }
        return notes.first { $0.id == id }
    }

    // MARK: - Opening

    func openVault(_ url: URL) {
        let target = url.standardizedFileURL
        // One vault, one window: if it is already open elsewhere, raise that window.
        if let existing = VaultRegistry.shared.store(for: target), existing !== self {
            existing.focusWindow()
            return
        }
        closeVault()
        vaultURL = target
        UserDefaults.standard.set(target.path, forKey: Self.lastVaultKey)
        VaultRegistry.shared.register(self)
        window?.representedURL = target
        loadMetadata()
        isLoaded = true
        startWatchingIfNeeded()
        scan { [weak self] in
            guard let self else { return }
            if self.selectedNoteID == nil || self.note(self.selectedNoteID!) == nil {
                self.selectedNoteID = self.visibleNotes.first?.id
            }
            self.loadEditorForSelection()
        }
    }

    func closeVault() {
        flushSave()
        watcher?.stop()
        watcher = nil
        rescanTask?.cancel()
        scanTask?.cancel()
        saveTask?.cancel()
        wordCountTask?.cancel()
        MarkdownParseCache.shared.clear()
        vaultURL = nil
        notes = []
        tree = []
        expandedFolders = []
        selectedNoteID = nil
        editorText = ""
        isLoaded = false
        starred = []
        window?.representedURL = nil
    }

    /// Called by the window once SwiftUI has produced the hosting NSWindow.
    func attach(window: NSWindow?) {
        self.window = window
        // Extra vault windows are a per-session thing: on the next launch Slate
        // reopens one window with the last vault rather than a pile of empties.
        window?.isRestorable = false
        VaultRegistry.shared.register(self)
        if let vaultURL {
            window?.representedURL = vaultURL
        }
    }

    /// Brings this vault's window to the front, e.g. when it is picked again.
    func focusWindow() {
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func restoreLastVault() {
        guard let path = UserDefaults.standard.string(forKey: Self.lastVaultKey) else { return }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            openVault(URL(fileURLWithPath: path))
        }
    }

    // MARK: - Layout

    func setLayout(_ newLayout: EditorLayout) {
        guard newLayout != layout else { return }
        if layout != .preview { previousLayout = layout }
        layout = newLayout
        if newLayout != .preview {
            DispatchQueue.main.async { EditorCommandCenter.shared.focus() }
        }
    }

    /// ⌘R: jump to preview-only, then back to the previous layout.
    func togglePreview() {
        if layout == .preview {
            setLayout(previousLayout == .preview ? .live : previousLayout)
        } else {
            previousLayout = layout
            layout = .preview
        }
    }

    // MARK: - External change watching

    private func startWatchingIfNeeded() {
        guard Preferences.shared.watchForExternalChanges, let url = vaultURL else { return }
        watcher = FSEventsWatcher(url: url) { [weak self] paths in
            guard let self else { return }
            guard Self.affectsContent(paths) else { return }
            self.scheduleRescan()
        }
    }

    /// Everything lives inside the vault, including `.slate/metadata.json`, so
    /// starring a note or moving the selection would otherwise look like an
    /// external edit and trigger a full rescan.
    nonisolated private static func affectsContent(_ paths: [String]) -> Bool {
        if paths.isEmpty { return true }
        return paths.contains { path in
            let name = (path as NSString).lastPathComponent
            if name == ".DS_Store" { return false }
            if path.contains("/.slate/") { return false }
            return true
        }
    }

    /// Applies the "Watch for external changes" setting immediately.
    func refreshWatcher() {
        if Preferences.shared.watchForExternalChanges {
            guard watcher == nil else { return }
            startWatchingIfNeeded()
        } else {
            watcher?.stop()
            watcher = nil
        }
    }

    // MARK: - Scanning

    /// Reads the vault off the main thread: a large tree means thousands of
    /// file reads and title/snippet derivations, which used to freeze the UI on
    /// open and on every external-change rescan.
    private func scan(completion: (() -> Void)? = nil) {
        guard let root = vaultURL else { return }
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                Self.loadSnapshot(root: root)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.notes = snapshot.notes
            self.buildTree(folderPaths: snapshot.folders)
            completion?()
        }
    }

    nonisolated private static func loadSnapshot(root: URL) -> (notes: [Note], folders: Set<String>) {
        let fm = FileManager.default
        var found: [Note] = []
        var folderPaths: Set<String> = [""]

        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]
        guard let enumerator = fm.enumerator(at: root,
                                             includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return ([], folderPaths)
        }

        let editors = ["code", "sublime-project", "xcodeproj"]
        let rootPath = root.standardizedFileURL.path
        while let url = enumerator.nextObject() as? URL {
            if editors.contains(url.pathExtension) {
                enumerator.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                let rel = relativePath(url, rootPath: rootPath)
                if !rel.isEmpty { folderPaths.insert(rel) }
                continue
            }
            guard isMarkdown(url) else { continue }
            guard (values?.fileSize ?? 0) < 2_000_000 else { continue }
            guard let body = readText(url) else { continue }
            let rel = relativePath(url, rootPath: rootPath)
            let folder = (rel as NSString).deletingLastPathComponent
            found.append(Note(
                id: rel,
                url: url,
                folder: folder,
                title: deriveTitle(body, url: url),
                snippet: deriveSnippet(body),
                modified: values?.contentModificationDate ?? Date.distantPast,
                created: values?.creationDate ?? values?.contentModificationDate ?? Date.distantPast,
                body: body
            ))
        }

        return (found, folderPaths)
    }

    /// Rescan after an external change, keeping the note being edited intact.
    func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self?.rescanPreservingEditor()
        }
    }

    func rescanPreservingEditor() {
        guard vaultURL != nil else { return }
        // Our own write just landed; ignore the echo.
        if Date().timeIntervalSince(lastSelfWrite) < 1.2, pendingSaveID == nil { return }

        let previous = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        scan { [weak self] in
            guard let self else { return }
            guard let id = self.selectedNoteID else { return }
            if let index = self.notes.firstIndex(where: { $0.id == id }) {
                self.notes[index].body = self.editorText
                self.notes[index].title = Self.deriveTitle(self.editorText, url: self.notes[index].url)
                self.notes[index].snippet = Self.deriveSnippet(self.editorText)
                if let old = previous[id], old.modified > self.notes[index].modified {
                    self.notes[index].modified = old.modified
                }
            } else {
                self.selectedNoteID = nil
                self.editorText = ""
            }
        }
    }

    nonisolated private static func isMarkdown(_ url: URL) -> Bool {
        ["md", "markdown", "mdown", "txt"].contains(url.pathExtension.lowercased())
    }

    nonisolated private static func relativePath(_ url: URL, rootPath: String) -> String {
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        var rel = String(path.dropFirst(rootPath.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        return rel
    }

    private func relativePath(of url: URL, in root: URL) -> String {
        Self.relativePath(url, rootPath: root.standardizedFileURL.path)
    }

    private func isMarkdown(_ url: URL) -> Bool {
        Self.isMarkdown(url)
    }

    private func buildTree(folderPaths: Set<String>) {
        var counts: [String: Int] = [:]
        for note in notes { counts[note.folder, default: 0] += 1 }

        func children(of parent: String) -> [FolderNode] {
            let prefixes = folderPaths.filter { path in
                guard path != parent else { return false }
                let dir = (path as NSString).deletingLastPathComponent
                return dir == parent
            }
            return prefixes.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { path in
                FolderNode(id: path,
                           name: (path as NSString).lastPathComponent,
                           children: children(of: path),
                           noteCount: counts[path] ?? 0)
            }
        }

        tree = children(of: "")
        if expandedFolders.isEmpty {
            expandedFolders = Set(folderPaths.filter { !$0.isEmpty && $0.split(separator: "/").count <= 2 })
        }
        // The root row is the way into the top-level notebooks, so it starts open.
        expandedFolders.insert("")
    }

    // MARK: - Derived lists

    /// The vault root as a folder row: its own notes plus the top-level notebooks.
    var rootNode: FolderNode {
        FolderNode(id: "",
                   name: "Vault Root",
                   children: tree,
                   noteCount: notes.reduce(0) { $0 + ($1.folder.isEmpty ? 1 : 0) })
    }

    /// Folders flattened in display order, honouring the store's expansion
    /// state. A `List` needs a flat sequence; rebuilding it is cheap because the
    /// sidebar only holds notebook paths, not notes.
    var sidebarFolders: [SidebarFolderEntry] {
        var entries: [SidebarFolderEntry] = []
        func walk(_ node: FolderNode, depth: Int) {
            entries.append(SidebarFolderEntry(node: node, depth: depth))
            guard expandedFolders.contains(node.id) else { return }
            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }
        walk(rootNode, depth: 0)
        return entries
    }

    /// Every folder id in the tree, for Expand All.
    var allFolderIDs: Set<String> {
        var ids: Set<String> = []
        func walk(_ nodes: [FolderNode]) {
            for node in nodes {
                ids.insert(node.id)
                walk(node.children)
            }
        }
        walk(tree)
        return ids
    }

    func expandAllFolders() {
        // The root row owns the top-level notebooks, so it has to open too.
        expandedFolders = allFolderIDs.union([""])
    }

    func collapseAllFolders() {
        expandedFolders.removeAll()
    }

    var visibleNotes: [Note] {
        if let cachedVisibleNotes { return cachedVisibleNotes }
        let result = computeVisibleNotes()
        cachedVisibleNotes = result
        return result
    }

    private func computeVisibleNotes() -> [Note] {
        var result: [Note]

        switch sidebarSelection {
        case .smart(.all):
            result = notes
        case .smart(.starred):
            result = notes.filter { starred.contains($0.id) }
        case .smart(.recent):
            result = notes
                .filter { $0.modified > Date().addingTimeInterval(-60 * 60 * 24 * 14) }
            if result.isEmpty { result = notes }
        case .folder(let path):
            result = notes.filter { note in
                if path.isEmpty { return note.folder.isEmpty }
                return note.folder == path || note.folder.hasPrefix(path + "/")
            }
        case .tag(let name):
            result = notes.filter { $0.body.lowercased().contains("#" + name.lowercased()) }
        }

        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter { note in
                searchIndex[note.id]?.contains(query) ?? false
            }
        }

        switch sort {
        case .modified:
            result.sort { $0.modified > $1.modified }
        case .created:
            result.sort { $0.created > $1.created }
        case .title:
            result.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }

        // Starred notes float to the top of any list.
        let starredNotes = result.filter { starred.contains($0.id) }
        let others = result.filter { !starred.contains($0.id) }
        return starredNotes + others
    }

    private func invalidateDerived() {
        cachedVisibleNotes = nil
        cachedTags = nil
    }

    private func rebuildSearchIndex() {
        searchIndex = Dictionary(uniqueKeysWithValues: notes.map { note in
            (note.id, Self.searchableText(title: note.title, filename: note.filename, body: note.body))
        })
    }

    nonisolated private static func searchableText(title: String, filename: String, body: String) -> String {
        title.lowercased() + "\n" + filename.lowercased() + "\n" + body.lowercased()
    }

    var allNotesCount: Int { notes.count }
    var starredCount: Int { notes.reduce(0) { $0 + (starred.contains($1.id) ? 1 : 0) } }

    var allTags: [String] {
        if let cachedTags { return cachedTags }
        var set = Set<String>()
        for note in notes {
            var i = note.body.startIndex
            while let r = note.body[i...].range(of: "#") {
                let after = r.upperBound
                var j = after
                while j < note.body.endIndex {
                    let c = note.body[j]
                    if c.isLetter || c.isNumber || c == "_" || c == "-" { j = note.body.index(after: j) } else { break }
                }
                if j > after { set.insert(String(note.body[after..<j])) }
                i = j
            }
        }
        let sorted = set.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        cachedTags = sorted
        return sorted
    }

    var selectionTitle: String {
        switch sidebarSelection {
        case .smart(let filter): return filter.title
        case .folder(let path):
            return path.isEmpty ? "Vault Root" : (path as NSString).lastPathComponent
        case .tag(let name): return "#" + name
        }
    }

    func note(_ id: String) -> Note? { notes.first { $0.id == id } }

    // MARK: - Export

    func exportHTML() -> URL? {
        guard let note = selectedNote else { return nil }
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let url = desktop.appendingPathComponent(note.url.deletingPathExtension().lastPathComponent + ".html")
        let escaped = note.body
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\(note.title)</title></head><body><pre>\(escaped)</pre></body></html>"
        try? html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Wikilinks

    /// Notes that link to the given note via [[...]] referencing its title or filename.
    func backlinks(to note: Note) -> [Note] {
        let targets = Set([note.title.lowercased(), (note.url.deletingPathExtension().lastPathComponent).lowercased()])
        return notes.filter { other in
            guard other.id != note.id else { return false }
            let body = other.body.lowercased()
            var i = body.startIndex
            while let r = body[i...].range(of: "[[") {
                let after = r.upperBound
                if let close = body[after...].range(of: "]]") {
                    let name = String(body[after..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if targets.contains(name) { return true }
                    i = close.upperBound
                } else { break }
            }
            return false
        }
    }

    /// Resolve a wikilink target string to a note (title or filename, case-insensitive).
    func resolveWikilink(_ target: String) -> Note? {
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return notes.first { $0.title.lowercased() == t }
            ?? notes.first { $0.url.deletingPathExtension().lastPathComponent.lowercased() == t }
    }

    // MARK: - Selection & editing

    func select(noteID: String) {
        guard noteID != selectedNoteID else { return }
        flushSave()
        selectedNoteID = noteID
        loadEditorForSelection()
    }

    func selectSidebar(_ selection: SidebarSelection) {
        flushSave()
        sidebarSelection = selection
        if let id = selectedNoteID, !visibleNotes.contains(where: { $0.id == id }) {
            selectedNoteID = visibleNotes.first?.id
            loadEditorForSelection()
        }
    }

    func selectAdjacent(offset: Int) {
        let list = visibleNotes
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedNoteID } ?? 0
        let next = min(max(current + offset, 0), list.count - 1)
        select(noteID: list[next].id)
    }

    private func loadEditorForSelection() {
        if let note = selectedNote {
            editorText = note.body
            refreshWordCount(note.body)
        } else {
            editorText = ""
            refreshWordCount("")
        }
    }

    func updateEditorText(_ text: String) {
        guard let id = selectedNoteID else { return }
        guard text != editorText else { return }
        editorText = text
        refreshWordCount(text)
        scheduleSave(id: id, text: text)
    }

    /// Word counts are for the meta bar, not for saving: a short debounce keeps
    /// the whole-document split off the typing path.
    private func refreshWordCount(_ text: String) {
        wordCountTask?.cancel()
        wordCountTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let count = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            guard let self, self.wordCount != count else { return }
            self.wordCount = count
        }
    }

    private func scheduleSave(id: String, text: String) {
        saveTask?.cancel()
        pendingSaveID = id
        let delay = max(0.05, Preferences.shared.autosaveDelay)
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.write(id: id, text: text)
        }
    }

    func flushSave() {
        guard let id = pendingSaveID else { return }
        saveTask?.cancel()
        saveTask = nil
        write(id: id, text: editorText)
    }

    private func write(id: String, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let url = notes[index].url
        lastSelfWrite = Date()
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Could not save \(url.lastPathComponent): \(error.localizedDescription)"
            return
        }
        notes[index].body = text
        notes[index].title = Self.deriveTitle(text, url: url)
        notes[index].snippet = Self.deriveSnippet(text)
        notes[index].modified = Date()
        searchIndex[id] = Self.searchableText(title: notes[index].title,
                                              filename: url.lastPathComponent,
                                              body: text)
        if pendingSaveID == id { pendingSaveID = nil }
        maybeAutoRename(index: index)
    }

    /// A brand-new note picks up the name of its first heading, like Apple Notes.
    private func maybeAutoRename(index: Int) {
        guard Preferences.shared.autoRenameNewNotes else { return }
        var note = notes[index]
        guard note.url.deletingPathExtension().lastPathComponent.hasPrefix("Untitled"),
              note.url.pathExtension.lowercased() == "md" else { return }
        guard let heading = firstHeading(in: note.body) else { return }
        let cleaned = Self.sanitizeFilename(heading)
        guard cleaned.count > 0, cleaned.count < 60 else { return }
        guard cleaned != note.url.deletingPathExtension().lastPathComponent else { return }

        let dir = note.url.deletingLastPathComponent()
        var target = dir.appendingPathComponent(cleaned).appendingPathExtension("md")
        var suffix = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = dir.appendingPathComponent("\(cleaned) \(suffix)").appendingPathExtension("md")
            suffix += 1
        }
        do {
            try FileManager.default.moveItem(at: note.url, to: target)
        } catch {
            return
        }
        let oldID = note.id
        let root = vaultURL ?? dir
        note = Note(id: relativePath(of: target, in: root),
                    url: target,
                    folder: note.folder,
                    title: note.title,
                    snippet: note.snippet,
                    modified: note.modified,
                    created: note.created,
                    body: note.body)
        notes[index] = note
        if starred.remove(oldID) != nil { starred.insert(note.id) }
        if selectedNoteID == oldID { selectedNoteID = note.id }
        saveMetadata()
    }

    private func firstHeading(in text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let title = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                return title.isEmpty ? nil : title
            }
            if !trimmed.isEmpty { return nil }
        }
        return nil
    }

    // MARK: - Note operations

    @discardableResult
    func createNote(in folder: String? = nil) -> String? {
        guard let root = vaultURL else { return nil }
        flushSave()

        var targetFolder = ""
        switch sidebarSelection {
        case .folder(let path): targetFolder = path
        case .tag: targetFolder = folder ?? selectedNote?.folder ?? ""
        case .smart: targetFolder = folder ?? selectedNote?.folder ?? ""
        }

        let dir = targetFolder.isEmpty ? root : root.appendingPathComponent(targetFolder)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var url = dir.appendingPathComponent("Untitled.md")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("Untitled \(n).md")
            n += 1
        }
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
        } catch {
            errorMessage = "Could not create note: \(error.localizedDescription)"
            return nil
        }

        let rel = relativePath(of: url, in: root)
        let created = Date()
        notes.append(Note(id: rel, url: url, folder: targetFolder,
                          title: "New Note", snippet: "No additional text",
                          modified: created, created: created, body: ""))
        selectedNoteID = rel
        editorText = ""
        sidebarSelection = .folder(targetFolder)
        return rel
    }

    @discardableResult
    func createFolder(named name: String = "New Folder", in parent: String? = nil) -> String? {
        guard let root = vaultURL else { return nil }
        var parentPath = parent ?? ""
        if parent == nil, case .folder(let path) = sidebarSelection { parentPath = path }

        let dir = parentPath.isEmpty ? root : root.appendingPathComponent(parentPath)
        var url = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(name) \(n)")
            n += 1
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            errorMessage = "Could not create folder: \(error.localizedDescription)"
            return nil
        }
        let rel = relativePath(of: url, in: root)
        buildTree(folderPaths: collectFolders())
        expandedFolders.insert(rel)
        sidebarSelection = .folder(rel)
        return rel
    }

    private func collectFolders() -> Set<String> {
        guard let root = vaultURL else { return [""] }
        var paths: Set<String> = [""]
        if let en = FileManager.default.enumerator(at: root,
                                                  includingPropertiesForKeys: [.isDirectoryKey],
                                                  options: [.skipsHiddenFiles]) {
            while let url = en.nextObject() as? URL {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    let rel = relativePath(of: url, in: root)
                    if !rel.isEmpty { paths.insert(rel) }
                }
            }
        }
        return paths
    }

    func renameNote(id: String, to newName: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var note = notes[index]
        let cleaned = Self.sanitizeFilename(newName)
        guard !cleaned.isEmpty else { return }

        let ext = note.url.pathExtension.isEmpty ? "md" : note.url.pathExtension
        let target = note.url.deletingLastPathComponent()
            .appendingPathComponent(cleaned)
            .appendingPathExtension(ext)
        guard target != note.url else { return }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            errorMessage = "A note called “\(cleaned)” already exists here."
            return
        }
        do {
            try FileManager.default.moveItem(at: note.url, to: target)
        } catch {
            errorMessage = "Could not rename: \(error.localizedDescription)"
            return
        }
        let root = vaultURL ?? note.url.deletingLastPathComponent()
        note = Note(id: relativePath(of: target, in: root), url: target, folder: note.folder,
                    title: note.title, snippet: note.snippet, modified: note.modified,
                    created: note.created, body: note.body)
        notes[index] = note
        if starred.remove(id) != nil { starred.insert(note.id) }
        if selectedNoteID == id { selectedNoteID = note.id }
        saveMetadata()
        rescanPreservingEditor()
    }

    func deleteNote(id: String) {
        guard let note = note(id) else { return }
        if pendingSaveID == id {
            saveTask?.cancel()
            saveTask = nil
            pendingSaveID = nil
        }
        do {
            try FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
        } catch {
            errorMessage = "Could not move to Trash: \(error.localizedDescription)"
            return
        }
        notes.removeAll { $0.id == id }
        starred.remove(id)
        if selectedNoteID == id {
            selectedNoteID = visibleNotes.first?.id
            loadEditorForSelection()
        }
        saveMetadata()
    }

    func toggleStar(_ id: String? = nil) {
        let target = id ?? selectedNoteID
        guard let target else { return }
        if starred.contains(target) { starred.remove(target) } else { starred.insert(target) }
        saveMetadata()
    }

    func revealInFinder(_ id: String) {
        guard let note = note(id) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([note.url])
    }

    func openInEditor(_ id: String) {
        guard let note = note(id) else { return }
        NSWorkspace.shared.open(note.url)
    }

    // MARK: - Metadata

    @Published var starred: Set<String> = []

    private var metadataURL: URL? {
        vaultURL?.appendingPathComponent(Self.metadataDir).appendingPathComponent("metadata.json")
    }

    private struct Metadata: Codable {
        var starred: [String]
        var lastNote: String?
    }

    private func loadMetadata() {
        guard let url = metadataURL,
              let data = try? Data(contentsOf: url),
              let meta = try? JSONDecoder().decode(Metadata.self, from: data) else {
            starred = []
            return
        }
        starred = Set(meta.starred)
        if let last = meta.lastNote {
            selectedNoteID = last
        }
    }

    private func saveMetadata() {
        guard let url = metadataURL else { return }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let meta = Metadata(starred: Array(starred).sorted(), lastNote: selectedNoteID)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Text helpers

    nonisolated static func deriveTitle(_ body: String, url: URL) -> String {
        for line in body.split(separator: "\n", omittingEmptySubsequences: false).prefix(60) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }.count
                let text = trimmed.dropFirst(hashes).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty { return String(text.prefix(120)) }
            }
        }
        for line in body.split(separator: "\n", omittingEmptySubsequences: false).prefix(60) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let plain = MarkdownDocument.plainText(trimmed)
                if !plain.isEmpty { return String(plain.prefix(120)) }
            }
        }
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? "New Note" : name
    }

    nonisolated static func deriveSnippet(_ body: String) -> String {
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        var sawHeading = false
        var skippedPlainTitle = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                sawHeading = true
                continue
            }
            if !sawHeading && !skippedPlainTitle {
                skippedPlainTitle = true
                continue
            }
            let plain = MarkdownDocument.plainText(trimmed)
            if !plain.isEmpty {
                return String(plain.prefix(140))
            }
        }
        return "No additional text"
    }

    nonisolated static func sanitizeFilename(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = name.components(separatedBy: illegal).joined(separator: " ")
        return cleaned.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "  ", with: " ")
    }

    nonisolated static func readText(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1)
    }
}

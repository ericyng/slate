import Foundation

/// A single markdown file inside the vault.
struct Note: Identifiable, Hashable {
    /// Path relative to the vault root, e.g. "Projects/Roadmap.md".
    let id: String
    let url: URL
    /// Directory relative to the vault root ("" for the root).
    let folder: String
    /// Display title, derived from the first heading or first non-empty line.
    var title: String
    /// One-line preview of the body.
    var snippet: String
    var modified: Date
    var created: Date
    /// Full body text, kept in memory so search and previews are instant.
    var body: String

    var filename: String { url.lastPathComponent }
    var wordCount: Int {
        body.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// A directory in the vault.
struct FolderNode: Identifiable, Hashable {
    /// Relative path ("" for the vault root).
    let id: String
    var name: String
    var children: [FolderNode]
    var noteCount: Int

    /// Notes in this folder and every folder below it.
    var totalCount: Int {
        noteCount + children.reduce(0) { $0 + $1.totalCount }
    }
}

enum SidebarFilter: String, CaseIterable, Identifiable {
    case all, starred, recent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "All Notes"
        case .starred: return "Starred"
        case .recent: return "Recently Edited"
        }
    }
    var symbol: String {
        switch self {
        case .all: return "tray.full"
        case .starred: return "star"
        case .recent: return "clock"
        }
    }
}

enum NoteSort: String, CaseIterable, Identifiable {
    case modified, created, title
    var id: String { rawValue }
    var title: String {
        switch self {
        case .modified: return "Date Edited"
        case .created: return "Date Created"
        case .title: return "Title"
        }
    }
}

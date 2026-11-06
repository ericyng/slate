import SwiftUI
import AppKit

// MARK: - Layout

/// How the right-hand pane is split between source and rendered output.
enum EditorLayout: String, CaseIterable, Identifiable {
    case editor
    case live
    case split
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editor: return "Source"
        case .live: return "Live Preview"
        case .split: return "Side by Side"
        case .preview: return "Reading"
        }
    }

    var shortTitle: String {
        switch self {
        case .editor: return "Source"
        case .live: return "Live"
        case .split: return "Split"
        case .preview: return "Read"
        }
    }

    var symbol: String {
        switch self {
        case .editor: return "square.and.pencil"
        case .live: return "text.bubble"
        case .split: return "rectangle.split.2x1"
        case .preview: return "doc.richtext"
        }
    }

    var showsEditor: Bool { self != .preview }
    var showsPreview: Bool { self == .split || self == .preview }

    /// Live preview styles the source inline and hides markers on the line the
    /// caret is not in.
    var concealsSyntax: Bool { self == .live }
}

// MARK: - Theme

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Preferences

/// User settings, persisted in `UserDefaults` and shared by every window.
///
/// Views observe the shared instance; `VaultStore` reads it directly at the
/// moment a decision is made (autosave delay, auto-rename, watching).
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    @Published var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    /// Editor and preview font size in points.
    @Published var bodyFontSize: Double {
        didSet { defaults.set(bodyFontSize, forKey: Key.bodyFontSize) }
    }

    /// Layout a freshly opened window starts in.
    @Published var defaultLayout: EditorLayout {
        didSet { defaults.set(defaultLayout.rawValue, forKey: Key.defaultLayout) }
    }

    /// Width of the text column in points (per pane in live preview).
    @Published var contentWidth: Double {
        didSet { defaults.set(contentWidth, forKey: Key.contentWidth) }
    }

    /// Seconds after the last keystroke before a note is written to disk.
    @Published var autosaveDelay: Double {
        didSet { defaults.set(autosaveDelay, forKey: Key.autosaveDelay) }
    }

    /// Rename brand-new `Untitled…` notes from their first heading.
    @Published var autoRenameNewNotes: Bool {
        didSet { defaults.set(autoRenameNewNotes, forKey: Key.autoRename) }
    }

    /// Watch the vault with FSEvents so external edits show up live.
    @Published var watchForExternalChanges: Bool {
        didSet { defaults.set(watchForExternalChanges, forKey: Key.watch) }
    }

    @Published var spellCheck: Bool {
        didSet { defaults.set(spellCheck, forKey: Key.spellCheck) }
    }

    @Published var showWordCount: Bool {
        didSet { defaults.set(showWordCount, forKey: Key.wordCount) }
    }

    /// Reopen the last vault when Slate launches or a new window opens.
    @Published var restoreLastVault: Bool {
        didSet { defaults.set(restoreLastVault, forKey: Key.restoreLastVault) }
    }

    private let defaults: UserDefaults

    private enum Key {
        static let theme = "theme"
        static let bodyFontSize = "bodyFontSize"
        static let defaultLayout = "defaultLayout"
        static let contentWidth = "contentWidth"
        static let autosaveDelay = "autosaveDelay"
        static let autoRename = "autoRenameNewNotes"
        static let watch = "watchForExternalChanges"
        static let spellCheck = "spellCheck"
        static let wordCount = "showWordCount"
        static let restoreLastVault = "restoreLastVault"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.theme: AppTheme.system.rawValue,
            Key.bodyFontSize: Double(MarkdownTheme.preferredBodySize),
            Key.defaultLayout: EditorLayout.live.rawValue,
            Key.contentWidth: 760.0,
            Key.autosaveDelay: 0.4,
            Key.autoRename: true,
            Key.watch: true,
            Key.spellCheck: true,
            Key.wordCount: true,
            Key.restoreLastVault: true
        ])

        theme = AppTheme(rawValue: defaults.string(forKey: Key.theme) ?? "") ?? .system
        bodyFontSize = defaults.double(forKey: Key.bodyFontSize)
        defaultLayout = EditorLayout(rawValue: defaults.string(forKey: Key.defaultLayout) ?? "") ?? .live
        contentWidth = defaults.double(forKey: Key.contentWidth)
        autosaveDelay = defaults.double(forKey: Key.autosaveDelay)
        autoRenameNewNotes = defaults.bool(forKey: Key.autoRename)
        watchForExternalChanges = defaults.bool(forKey: Key.watch)
        spellCheck = defaults.bool(forKey: Key.spellCheck)
        showWordCount = defaults.bool(forKey: Key.wordCount)
        restoreLastVault = defaults.bool(forKey: Key.restoreLastVault)
    }

    /// Puts every setting back to its factory value.
    func resetToDefaults() {
        theme = .system
        bodyFontSize = 15
        defaultLayout = .live
        contentWidth = 760
        autosaveDelay = 0.4
        autoRenameNewNotes = true
        watchForExternalChanges = true
        spellCheck = true
        showWordCount = true
        restoreLastVault = true
    }
}

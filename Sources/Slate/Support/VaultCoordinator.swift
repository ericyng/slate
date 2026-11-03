import SwiftUI
import AppKit

enum WindowID {
    static let vault = "vault"
}

/// One-shot launch bookkeeping so only the first window of a launch restores a vault.
@MainActor
enum LaunchState {
    private static var claimedFirstWindow = false

    static func claimFirstWindow() -> Bool {
        defer { claimedFirstWindow = true }
        return !claimedFirstWindow
    }

    /// `--vault PATH` when the app was launched from the command line.
    static func vaultArgument() -> URL? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--vault"), index + 1 < args.count else { return nil }
        let url = URL(fileURLWithPath: args[index + 1]).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return url
    }
}

/// Weak index of the open windows' stores, so a vault is only ever open in one window.
@MainActor
final class VaultRegistry {
    static let shared = VaultRegistry()

    private let table = NSHashTable<VaultStore>.weakObjects()

    func register(_ store: VaultStore) {
        table.add(store)
    }

    func store(for url: URL) -> VaultStore? {
        let path = url.standardizedFileURL.path
        for store in table.allObjects {
            if store.vaultURL?.standardizedFileURL.path == path { return store }
        }
        return nil
    }

    var allStores: [VaultStore] { table.allObjects }
}

/// Routes "open this vault" requests to the right window.
@MainActor
enum VaultCoordinator {
    /// Set when a brand-new window should adopt a vault as soon as it appears.
    private static var pendingURL: URL?

    /// Opens `url` in `store` when that window is empty, otherwise in its own
    /// window — or brings the existing window for that vault to the front.
    static func open(_ url: URL, from store: VaultStore?, openWindow: OpenWindowAction) {
        let target = url.standardizedFileURL

        if let existing = VaultRegistry.shared.store(for: target) {
            existing.focusWindow()
            return
        }

        if let store, store.vaultURL == nil {
            store.openVault(target)
            return
        }

        if let store, store.vaultURL?.standardizedFileURL == target {
            store.focusWindow()
            return
        }

        pendingURL = target
        openWindow(id: WindowID.vault)
    }

    static func openInNewWindow(_ url: URL, openWindow: OpenWindowAction) {
        let target = url.standardizedFileURL
        if let existing = VaultRegistry.shared.store(for: target) {
            existing.focusWindow()
            return
        }
        pendingURL = target
        openWindow(id: WindowID.vault)
    }

    static func takePending() -> URL? {
        defer { pendingURL = nil }
        return pendingURL
    }
}

/// Captures the `NSWindow` hosting a SwiftUI view, so the store can raise it.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { onWindow(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onWindow(nsView.window) }
    }
}

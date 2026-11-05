import SwiftUI
import AppKit

/// Root of one window. Every window owns a `VaultStore`, so each window shows
/// exactly one vault and windows are fully independent.
struct VaultWindowView: View {
    @StateObject private var store = VaultStore()
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        ContentView()
            .environmentObject(store)
            .environmentObject(prefs)
            .focusedSceneValue(\.vaultStore, store)
            .preferredColorScheme(prefs.theme.colorScheme)
            .navigationTitle(store.vaultURL == nil ? "Slate" : store.vaultName)
            .background(WindowAccessor { window in
                store.attach(window: window)
                if let window { WindowChrome.apply(to: window) }
            })
            .modifier(WindowMaterial())
            .onAppear(perform: bootstrap)
            .onChange(of: prefs.watchForExternalChanges) { _, _ in
                store.refreshWatcher()
            }
    }

    private func bootstrap() {
        guard !store.didBootstrap else { return }
        store.didBootstrap = true

        if let pending = VaultCoordinator.takePending() {
            store.openVault(pending)
            return
        }

        // Only the first window of a launch reopens a vault; extra windows
        // start at the welcome screen so they can be pointed elsewhere.
        guard LaunchState.claimFirstWindow() else { return }
        if let argument = LaunchState.vaultArgument() {
            store.openVault(argument)
        } else if prefs.restoreLastVault {
            store.restoreLastVault()
        }
    }
}

// MARK: - Focused store

private struct VaultStoreFocusedKey: FocusedValueKey {
    typealias Value = VaultStore
}

extension FocusedValues {
    /// The store of the window that currently has focus, for menu commands.
    var vaultStore: VaultStore? {
        get { self[VaultStoreFocusedKey.self] }
        set { self[VaultStoreFocusedKey.self] = newValue }
    }
}

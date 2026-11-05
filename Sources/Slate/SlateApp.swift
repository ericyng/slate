import SwiftUI
import AppKit

@main
struct SlateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: WindowID.vault) {
            VaultWindowView()
        }
        .defaultSize(width: 1440, height: 880)
        .windowToolbarStyle(.unifiedCompact)
        .commands { SlateCommands() }

        Settings {
            SettingsView()
        }
    }
}

/// Menu bar commands. They act on the focused window's store, so with several
/// vault windows open each command applies to the one in front.
struct SlateCommands: Commands {
    @FocusedValue(\.vaultStore) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Note") {
                store?.createNote()
                EditorCommandCenter.shared.focus()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(store == nil)

            Button("New Folder") {
                store?.createFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(store == nil)

            Divider()

            Button("New Window") {
                openWindow(id: WindowID.vault)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("Open Vault…") {
                VaultPicker.choose { url in
                    VaultCoordinator.open(url, from: store, openWindow: openWindow)
                }
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open Vault in New Window…") {
                VaultPicker.choose { url in
                    VaultCoordinator.openInNewWindow(url, openWindow: openWindow)
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Now") { store?.flushSave() }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()

            Button("Find…") { EditorCommandCenter.shared.showFind() }
                .keyboardShortcut("f", modifiers: .command)

            Button("Find Next") { EditorCommandCenter.shared.findAgain(forward: true) }
                .keyboardShortcut("g", modifiers: .command)

            Button("Find Previous") { EditorCommandCenter.shared.findAgain(forward: false) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
        }

        CommandMenu("Format") {
            Button("Bold") { EditorCommandCenter.shared.wrap("**") }
                .keyboardShortcut("b", modifiers: .command)
            Button("Italic") { EditorCommandCenter.shared.wrap("*") }
                .keyboardShortcut("i", modifiers: .command)
            Button("Inline Code") { EditorCommandCenter.shared.wrap("`") }
                .keyboardShortcut("e", modifiers: .command)
            Button("Strikethrough") { EditorCommandCenter.shared.wrap("~~") }
                .keyboardShortcut("x", modifiers: [.command, .shift])

            Divider()

            Button("Heading 1") { EditorCommandCenter.shared.setHeading(1) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Heading 2") { EditorCommandCenter.shared.setHeading(2) }
                .keyboardShortcut("2", modifiers: [.command, .option])
            Button("Heading 3") { EditorCommandCenter.shared.setHeading(3) }
                .keyboardShortcut("3", modifiers: [.command, .option])
            Button("Body Text") { EditorCommandCenter.shared.setHeading(0) }
                .keyboardShortcut("0", modifiers: [.command, .option])

            Divider()

            Button("Bulleted List") { EditorCommandCenter.shared.toggleLinePrefix("- ") }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Numbered List") { EditorCommandCenter.shared.applyNumberedList() }
            Button("Quote") { EditorCommandCenter.shared.toggleLinePrefix("> ") }
            Button("Task") { EditorCommandCenter.shared.toggleLinePrefix("- [ ] ") }
            Button("Code Block") { EditorCommandCenter.shared.insertCodeBlock() }
        }

        CommandMenu("View") {
            Button("Source") { store?.setLayout(.editor) }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(store == nil)

            Button("Live Preview") { store?.setLayout(.live) }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(store == nil)

            Button("Side by Side") { store?.setLayout(.split) }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(store == nil)

            Button("Reading") { store?.setLayout(.preview) }
                .keyboardShortcut("4", modifiers: .command)
                .disabled(store == nil)

            Button("Toggle Preview") { store?.togglePreview() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(store == nil)

            Divider()

            Button("Next Note") { store?.selectAdjacent(offset: 1) }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(store == nil)

            Button("Previous Note") { store?.selectAdjacent(offset: -1) }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(store == nil)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            for store in VaultRegistry.shared.allStores {
                store.flushSave()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

enum VaultPicker {
    /// Asks for a vault folder as a sheet on the window that asked, so every
    /// other vault window stays usable while the panel is up.
    @MainActor
    static func choose(completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose a Vault"
        panel.message = "Pick a folder to use as your markdown vault."
        panel.prompt = "Open Vault"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

        let deliver: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }

        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: deliver)
        } else {
            panel.begin(completionHandler: deliver)
        }
    }
}

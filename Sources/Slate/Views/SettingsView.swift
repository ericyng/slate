import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject private var prefs = Preferences.shared

    var body: some View {
        TabView {
            GeneralSettingsView(prefs: prefs)
                .tabItem { Label("General", systemImage: "gearshape") }

            AppearanceSettingsView(prefs: prefs)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            AdvancedSettingsView(prefs: prefs)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 580, height: 520)
        .preferredColorScheme(prefs.theme.colorScheme)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @ObservedObject var prefs: Preferences

    private var lastVaultPath: String? {
        UserDefaults.standard.string(forKey: "lastVaultPath")
    }

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Reopen the last vault at launch", isOn: $prefs.restoreLastVault)
                LabeledContent("Last vault") {
                    Text(lastVaultPath.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "None yet")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Section("Saving") {
                LabeledContent("Autosave delay") {
                    HStack(spacing: 10) {
                        Slider(value: $prefs.autosaveDelay, in: 0.1...2.0, step: 0.1)
                            .frame(width: 180)
                        Text(String(format: "%.1f s", prefs.autosaveDelay))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                }
                Toggle("Rename new notes from their first heading", isOn: $prefs.autoRenameNewNotes)
                Text("A note still called “Untitled” takes its filename from the first `# heading` you type. Notes you rename yourself are never touched.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Windows") {
                Text("Each window holds one vault, so you can keep several vaults open side by side. Use File ▸ New Window (⌥⌘N) and open a different folder in it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Appearance

private struct AppearanceSettingsView: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Theme") {
                Picker("Appearance", selection: $prefs.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Text") {
                LabeledContent("Font size") {
                    HStack(spacing: 10) {
                        Slider(value: $prefs.bodyFontSize, in: 11...22, step: 0.5)
                            .frame(width: 180)
                        Text(String(format: "%.0f pt", prefs.bodyFontSize))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                }

                LabeledContent("Text column") {
                    HStack(spacing: 10) {
                        Slider(value: $prefs.contentWidth, in: 520...1100, step: 20)
                            .frame(width: 180)
                        Text("\(Int(prefs.contentWidth)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing)
                    }
                }

                Toggle("Check spelling while typing", isOn: $prefs.spellCheck)
                Toggle("Show word count", isOn: $prefs.showWordCount)

                Text("Heading")
                    .font(.system(size: prefs.bodyFontSize * 1.66, weight: .bold))
                Text("Body text at \(String(format: "%.0f", prefs.bodyFontSize)) pt, with headings, lists and code scaled to match.")
                    .font(.system(size: prefs.bodyFontSize))
                    .foregroundStyle(.secondary)
            }

            Section("Layout") {
                Picker("New windows open in", selection: $prefs.defaultLayout) {
                    ForEach(EditorLayout.allCases) { layout in
                        Text(layout.title).tag(layout)
                    }
                }
                .pickerStyle(.segmented)

                Text("Live Preview shows the rendered note beside the source and updates as you type. You can switch per window with ⌘1, ⌘2 and ⌘3.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

private struct AdvancedSettingsView: View {
    @ObservedObject var prefs: Preferences
    @State private var showResetConfirmation = false

    var body: some View {
        Form {
            Section("Vault") {
                Toggle("Watch for external changes", isOn: $prefs.watchForExternalChanges)
                Text("Uses FSEvents so edits made in another editor appear without a manual rescan. Your own unsaved typing is never overwritten.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Storage") {
                LabeledContent("Metadata") {
                    Text(".slate/metadata.json")
                        .foregroundStyle(.secondary)
                        .monospaced()
                }
                Text("Stars and the last open note live in this file inside each vault. Delete it and only those are lost — every note stays a plain markdown file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reveal Last Vault in Finder") {
                    guard let path = UserDefaults.standard.string(forKey: "lastVaultPath") else { return }
                    let url = URL(fileURLWithPath: path)
                    guard FileManager.default.fileExists(atPath: url.path) else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }

            Section {
                Button("Reset All Settings…", role: .destructive) {
                    showResetConfirmation = true
                }
                .confirmationDialog(
                    "Reset every setting to its default?",
                    isPresented: $showResetConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Reset Settings", role: .destructive) { prefs.resetToDefaults() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Notes and vaults are not affected.")
                }

                LabeledContent("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

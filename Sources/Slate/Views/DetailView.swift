import SwiftUI
import AppKit

struct DetailView: View {
    @EnvironmentObject private var store: VaultStore
    @EnvironmentObject private var prefs: Preferences
    @Environment(\.renameRequest) private var rename

    private var editorBinding: Binding<String> {
        Binding(
            get: { store.editorText },
            set: { store.updateEditorText($0) }
        )
    }

    var body: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)

            if let note = store.selectedNote {
                VStack(spacing: 0) {
                    metaBar(note)
                    Divider().opacity(0.5)
                    content
                }
            } else {
                emptyState
            }
        }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var content: some View {
        switch store.layout {
        case .editor:
            pane {
                MarkdownEditor(
                    text: editorBinding,
                    bodySize: prefs.bodyFontSize,
                    spellCheck: prefs.spellCheck
                )
            }

        case .live:
            pane {
                MarkdownEditor(
                    text: editorBinding,
                    bodySize: prefs.bodyFontSize,
                    spellCheck: prefs.spellCheck,
                    concealSyntax: true
                )
            }

        case .preview:
            pane {
                MarkdownPreview(text: store.editorText, bodySize: prefs.bodyFontSize)
            }

        case .split:
            HSplitView {
                MarkdownEditor(
                    text: editorBinding,
                    bodySize: prefs.bodyFontSize,
                    spellCheck: prefs.spellCheck
                )
                .frame(minWidth: 260, idealWidth: 420)

                MarkdownPreview(text: store.editorText, bodySize: prefs.bodyFontSize)
                    .frame(minWidth: 260, idealWidth: 420)
            }
        }
    }

    /// Single-pane layouts keep the text column centred and readable.
    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content()
                .frame(maxWidth: prefs.contentWidth)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Header

    private func metaBar(_ note: Note) -> some View {
        HStack(spacing: 8) {
            Button {
                rename.begin(note.id, note.url.deletingPathExtension().lastPathComponent)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 9.5))
                    Text(note.filename)
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Rename note")

            if store.starred.contains(note.id) {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            if prefs.showWordCount {
                Text("\(store.wordCount) words")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)

                Text("·")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }

            Text(DateText.detailStamp(note.modified))
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20)
        .frame(height: 30)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(.quaternary)
            Text("No note selected")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Choose a note, or start a new one with ⌘N.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Button("New Note") { store.createNote() }
                .controlSize(.small)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

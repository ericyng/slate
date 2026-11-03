# Plan

Goal: a native macOS markdown notes app — Apple Notes calm, Obsidian-style vault.

## Approach

1. **Stack** — Swift 6 + SwiftUI for structure, AppKit `NSTextView` for the editor (SwiftUI's `TextEditor` cannot style per-character or expose a find bar). Built as a SwiftPM executable, packaged into `Slate.app` by `build.sh`.
2. **Storage** — no database. Vault folder → subfolders are notebooks, `.md` files are notes. One hidden `.slate/metadata.json` for stars and the last-open note.
3. **Rendering** — one markdown parser that records *source ranges*, used twice:
   - editor: attribute runs over the raw text (syntax dimmed, not hidden)
   - read mode: rebuilt attributed string with syntax stripped
4. **Correctness** — unit tests for the parser, renderer and derived metadata; GUI smoke test for create → type → autosave → rename → read mode → search → star → trash.

## Steps

- [x] Package skeleton, app entry, Info.plist, icon generator, build script
- [x] Vault scanning, folder tree, notes index, metadata
- [x] Markdown parser (headings, lists, tasks, quotes, fences, rules, inline)
- [x] Editor styling pass + read-mode renderer
- [x] Three-pane UI: sidebar, note list, detail, toolbar, welcome screen
- [x] Autosave, auto-rename from first heading, external-change watching
- [x] Search, stars, sort, context menus, rename, reveal, trash
- [x] Keyboard shortcuts and Format menu
- [x] Settings window (General / Appearance / Advanced) backed by `UserDefaults`
- [x] One vault per window, with a registry that prevents duplicate windows
- [x] Split live-preview layout alongside write and read modes
- [x] Inline (Obsidian-style) live preview: markers concealed off the caret's block
- [x] Vault Root row for loose root-level notes, plus expand/collapse all folders
- [x] Block-scoped restyling so long notes stay responsive while typing
- [x] Tests + smoke test on a real vault
- [ ] Wikilinks / backlinks (next)
- [ ] Tags browser, images/attachments, export

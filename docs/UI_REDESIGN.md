# Making Slate feel native: performance and Liquid Glass plan

Status: phases 1–3 shipped, phases 4–8 still a proposal. Baseline for the numbers below is
`e5cd0a6` (perf overhaul), macOS 26.6, Swift 6.4, deployment target macOS 14.

The goal is not "Slate with a blur behind it". It is Slate that looks and behaves like an
Apple app on this OS: system chrome, system list and search behaviour, one accent, one type
ramp, and glass used only where the system uses it — on controls that float above content,
never behind text.

## What is already done

The performance pass landed and is verified:

| Path | Before (`HEAD~1`) | After |
| --- | --- | --- |
| Parse a 2,000-line note | 48.2 ms | 5.9 ms |
| Restyle whole document | 7.1 ms | 2.5 ms |
| Restyle the edited block | 55.0 ms (full restyle) | 6.8 ms keystroke total |
| Font/paragraph allocation | per block per keystroke | cached, shared |

Changes: single-pass line scanner with UTF-16 indices instead of regex-per-line, one-entry
parse cache shared by split view, scoped restyle of the dirty block, cached fonts and
paragraph styles, debounced word count, and an FSEvents callback that filters Slate's own
metadata writes instead of rescanning the vault. Scans now run off the main thread.

Also fixed: a segfault in the FSEvents callback introduced during that work (a C string
array was being read as a `CFArray`; the stream now uses `kFSEventStreamCreateFlagUseCFTypes`).
Typing into a live vault was re-tested in the real app afterwards: no crash, save lands.

Two small material experiments (`.ultraThinMaterial` sidebar, `.thinMaterial` note list,
0.6-opacity editor background) are stashed as `WIP glass experiment`. They are deliberately
not shipped: the editor background must stay opaque, and materials applied ad hoc are the
opposite of the system look. Phase 3 replaces them with one availability-gated glass layer.

## Progress

| Phase | State |
| --- | --- |
| 1 — Split view and window chrome | shipped, merged to `main` |
| 2 — Native sidebar and note list | shipped, merged to `main` |
| 3 — One Liquid Glass layer | shipped, merged to `main` |
| 4 — Editor chrome and typography | next |
| 5–8 | not started |

Deviations from the phase text below, recorded so later phases do not re-plan around them:

- The sidebar is a flat, expansion-ordered `List` rather than nested `DisclosureGroup`s. The
  store still owns `expandedFolders`, so Expand All / Collapse All and the per-row chevrons
  keep working; `DisclosureGroup` would have moved that state into the view.
- Search is one `.searchable` field (sidebar placement) matching titles and bodies. The
  All / Title / Body `.searchScopes` are not implemented.
- The window background material is `.thinMaterial`; a custom `.ultraThinMaterial` note-list
  background was tried and reverted because it fought the split view's own vibrancy.

Phase 3 shipped as `Support/GlassSupport.swift`: `slateGlass(cornerRadius:tint:interactive:)`,
`slateProminentButton()`, `GlassGroup` (a `GlassEffectContainer` with a pre-26 passthrough)
and `GlassSupport.surface`. Glass sits on exactly three surfaces — the toolbar's New Note
button, the sidebar footer capsule and the welcome card — and nowhere else. The fallback
chain is native glass on 26 → `.ultraThinMaterial` before 26 → an opaque
`windowBackgroundColor` surface with a hairline border under Reduce Transparency or Increase
Contrast; `SLATE_OPAQUE_CHROME=1` forces the opaque branch for testing. Not built yet:
`glassEffectID` merging between footer controls, and `.glassEffectTransition(.materialize)`
on vault open.

## Design principles

1. **Glass is chrome, not canvas.** Toolbars, floating controls and the sidebar get glass.
   The editor and reading panes keep `textBackgroundColor`. Translucent text is unreadable
   in dark mode and in Reduce Transparency.
2. **System components before custom.** `NavigationSplitView`, `List`, `.searchable`,
   `.toolbar` and `Form` already give selection, keyboard navigation, vibrancy, drag and
   drop, accessibility and the correct macOS 26 glass for free.
3. **One compatibility point.** Every `macOS 26` API goes through `Support/GlassSupport.swift`
   with a `#available` fallback to materials, so the `macOS 14` deployment target still builds
   and looks intentional rather than broken.
4. **Short motion.** 150–250 ms, ease-out, and disabled under Reduce Motion.
5. **The text is the product.** No chrome change may reduce contrast, shrink the reading
   measure, or add per-keystroke work.

## Phase 1 — Split view and window chrome (≈0.5–1 day)

Replace the hand-built `HStack` + `Divider()` layout in `ContentView` with a real
three-column `NavigationSplitView`. This is the single biggest "feels Mac" change and it is
small.

```swift
NavigationSplitView(columnVisibility: $columns) {
    SidebarView()
        .navigationSplitViewColumnWidth(min: 200, ideal: 236, max: 320)
} content: {
    NoteListView()
        .navigationSplitViewColumnWidth(min: 240, ideal: 306, max: 420)
} detail: {
    DetailView()
}
.navigationSplitViewStyle(.balanced)
```

Window (`VaultWindowView` + `WindowAccessor`):

- `window.titlebarAppearsTransparent = true`, `styleMask.insert(.fullSizeContentView)`
- `window.toolbarStyle = .unifiedCompact`, keep the title, drop the separate title row
- `.containerBackground(.thinMaterial, for: .window)` (macOS 15+) so the desktop shows
  through the window edge the way Mail and Notes do
- `.scrollEdgeEffectStyle(.soft, for: .top)` (macOS 26) so content fades under the toolbar
  instead of a hard divider appearing when you scroll
- keep column visibility in per-window state, not a global pref

Delete the manual dividers and the fixed `.frame(width:)` calls; the split view owns those.

Acceptance: separators drag, sidebar collapses with ⌃⌘S and restores, no divider
double-drawing, window still restores its size.

## Phase 2 — Native sidebar and note list (≈1–2 days)

Both lists are custom `ScrollView` + `VStack` + `onTapGesture` today. That costs keyboard
navigation, selection rings, type-select, drag and drop, context-menu correctness, and
accessibility. Replace them with `List(selection:)` and keep the row views.

- Sidebar: `List(selection:)` + `.listStyle(.sidebar)`; `Section("Library")` for the smart
  filters and `Section("Folders")` for the tree; folder rows via `DisclosureGroup`, count via
  `.badge(count)`. Source-list vibrancy and the correct glass sidebar come automatically.
- Note list: `List(selection:)` + `.listStyle(.inset)`, `.listRowSeparator(.hidden)` for the
  plain look, `.listRowInsets` to keep the current spacing. Selection and arrow keys then
  work without custom hover state.
- Search moves to `.searchable(text: $store.searchText, placement: .sidebar,
  prompt: "Search notes")` with `.searchScopes` for All / Title / Body.
- `.contextMenu` on both lists (star, rename, reveal, trash, move to folder) replaces the
  bespoke buttons where the system menu fits better.
- Keep the expand/collapse-all buttons, but move them into the sidebar footer.

Acceptance: ↑/↓ move the note selection, Return opens, type-select jumps to a title, right
click matches Finder conventions, VoiceOver reads rows and counts.

## Phase 3 — One Liquid Glass layer (≈2–3 days)

New `Sources/Slate/Support/GlassSupport.swift`:

```swift
enum GlassSupport {
    @ViewBuilder
    static func surface(cornerRadius: CGFloat = 12,
                        tint: Color? = nil,
                        interactive: Bool = false) -> some View { … }
}

extension View {
    @ViewBuilder
    func slateGlass(cornerRadius: CGFloat = 12,
                    tint: Color? = nil,
                    interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                .regular.tint(tint).interactive(interactive),
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            self.background(.ultraThinMaterial,
                            in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}
```

Where it goes, and where it does not:

| Surface | Treatment |
| --- | --- |
| Toolbar buttons, New Note | system toolbar; `.buttonStyle(.glassProminent)` for the primary action |
| Layout picker, star, format menu | native toolbar items, grouped with `GlassEffectContainer` when they sit together |
| Search field | `.searchable` gives the system glass field — do not hand-build one |
| Sidebar footer / vault switcher | one glass capsule, `glassEffectID` inside a container |
| Meta bar (words, date) | plain secondary text first; only add a glass pill if it floats over content |
| Editor, reading pane, code blocks | **no glass** — opaque `textBackgroundColor` |
| Welcome screen | one glass card over a soft gradient, `.glassEffectTransition(.materialize)` on vault open |

Use `GlassEffectContainer(spacing:)` + `.glassEffectID(_:in:)` with a `@Namespace` when two
glass shapes are within ~20 pt, so they merge and animate as one body instead of two blobs
fighting for pixels. Bridge to `NSGlassEffectView` only if a control must live in AppKit
(the editor's floating toolbar, if one is added); SwiftUI covers the rest.

Accessibility is not optional here: under Reduce Transparency and Increase Contrast the
`#available` fallback must resolve to an opaque surface. Test with
`NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`.

## Phase 4 — Editor chrome and typography (≈1–2 days)

The editor is already the strongest part; this is polish with real payoff.

- **Reading measure.** Cap the text container at ~720 pt and centre it inside the pane, like
  Notes and Obsidian's readable line length. Wide windows currently stretch prose to 1,400 pt.
- **Type ramp.** Derive sizes from `NSFont.preferredFont(forTextStyle: .body)` so the app
  follows the system text size, and keep `MarkdownTheme.bodySize` as the user override.
- **Text blocks.** Render code fences and quotes as `NSTextBlock` with a rounded background,
  padding and a 3 pt accent bar for quotes, instead of a run background that only covers the
  glyphs. Same for tables via `NSTextTable` — this alone makes reading mode look designed.
- **Caret and selection.** `insertionPointColor = .controlAccentColor`, accent-tinted
  selection, and a 2 pt focus ring around the pane that matches the system one.
- **Task checkboxes.** Clickable `NSTextAttachment` checkboxes in reading mode that write
  `- [ ]`/`- [x]` back to the file.
- **Optional focus dimming.** Dim non-caret paragraphs to 60% when live preview is on; do it
  as a paragraph-level foreground alpha, not a restyle of the whole document.

## Phase 5 — Motion and micro-detail (≈0.5–1 day)

- `.animation(.smooth(duration: 0.2), value: store.layout)` on pane changes;
  `.contentTransition(.numericText())` on the word count.
- `.symbolEffect(.bounce, value: isStarred)` for the star, `.symbolEffect(.replace)` for
  layout icons.
- Glass transitions: `.glassEffectTransition(.materialize)` for the welcome card and the
  floating meta bar.
- Respect `accessibilityReduceMotion`; no animation longer than 250 ms.

## Phase 6 — Native behaviours worth adding (≈1–2 days)

- **One window per vault.** `WindowGroup(id: "vault", for: URL.self)` +
  `openWindow(value: url)`, deduped by path, so opening the same vault twice raises the
  existing window. This also gives native window restoration.
- **Drag and drop.** `.dropDestination(for: URL.self)` on the window: `.md` files import into
  the vault, folders open as a vault.
- **Quick Look and Print.** `QLPreviewPanel` for the selected note, `⌘P` via
  `NSTextView.printView(_:)`.
- **Open Recent.** `NSDocumentController.shared.noteNewRecentDocumentURL(_:)` on vault open;
  a "Recent Vaults" submenu in the File menu.
- **Share.** `.ShareLink` for the current note in the toolbar overflow.
- **Services.** "New Note from Selection" via `NSPerformService`.
- **Window tabbing.** `window.tabbingMode = .preferred` so Window ▸ Merge All Windows works.

## Phase 7 — Settings (≈0.5 day)

`SettingsView` becomes a native preferences window: `TabView` with `.tabViewStyle(.automatic)`,
`Form` with `.formStyle(.grouped)`, `LabeledContent` rows, system `Picker`/`Toggle`/`Slider`,
and `.windowResizability(.contentSize)`. Add the new toggles from phases 3–5 (focus dimming,
glass fallback, reading measure).

## Phase 8 — Verification

Every phase ends with the same gate:

1. `swift build` warning-free and `swift test` 25/25 (plus new tests for layout constants and
   the glass fallback decision).
2. `./build.sh`, then drive the installed app: open a vault, type in a 2,000-line note, switch
   all four layouts, collapse/expand the sidebar, open Settings, open a second vault window.
3. Visual matrix: light/dark, Reduce Transparency on/off, Increase Contrast on/off, Reduce
   Motion on/off, full screen, Stage Manager, 1280-wide window.
4. Performance gate: keystroke work stays under 16 ms on the 2,000-line note
   (`swift test -c release --filter PerformanceTests` prints the numbers), scrolling stays at
   60 fps, memory under ~300 MB with 1,000 notes.
5. Regenerate `docs/images/slate-window.png` and `slate-read-mode.png` after the chrome
   changes, in both appearances.

## Order, effort and risk

| Phase | Change | Effort | Risk | Payoff |
| --- | --- | --- | --- | --- |
| 1 | `NavigationSplitView`, transparent titlebar, scroll edge | 0.5–1 d | Low | High |
| 2 | Native `List` sidebar and note list, `.searchable` | 1–2 d | Medium (row styling) | High |
| 3 | Glass compatibility layer and placement | 2–3 d | Medium (legibility) | High |
| 4 | Editor measure, type ramp, `NSTextBlock` code/quotes | 1–2 d | Medium (TextKit) | High |
| 5 | Motion and micro-detail | 0.5–1 d | Low | Medium |
| 6 | Window-per-vault, drop, Quick Look, recents | 1–2 d | Medium | Medium |
| 7 | Native settings window | 0.5 d | Low | Medium |
| 8 | Verification and screenshots | ongoing | — | — |

**Suggested first pull request:** phases 1 + 2, plus the glass layer from phase 3 applied only
to the toolbar and sidebar footer. That is ~2 days, low risk, and is the point where the app
stops looking like a SwiftUI demo and starts looking like a Mac app. Phase 4 lands second
because it changes how the product reads, not just how it looks.

## Deliberately not doing

- Rewriting the editor in SwiftUI `TextEditor` (loses the live-preview styling engine).
- Adopting `NSDocument` (the vault is the document; per-window stores already work).
- Glass behind body text, custom window drawing, or a custom titlebar.
- iCloud sync, plugin API, themes beyond light/dark/system in this pass.

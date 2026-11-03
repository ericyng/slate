# User guide

## 1. What a vault is

A vault is just a folder on disk.

- Every `.md`, `.markdown`, `.mdown` or `.txt` file inside it is a note.
- Every subfolder is a notebook in the sidebar.
- Slate keeps one hidden folder, `.slate/`, holding stars and the note you had open. Delete it and you lose only those two things.

Nothing is imported or converted. If you already have an Obsidian, Bear-export or iCloud folder, point Slate at it.

> Files larger than 2 MB are ignored so a stray log file cannot stall startup, and hidden files (`.git`, `.obsidian`, `.DS_Store`) are skipped.

## 2. Opening a vault

**First run.** The welcome screen offers:

- **Choose Vault…** — pick any folder (you can create one in the panel). `⌘O` does the same later.
- **Create Sample Vault** — writes a seven-note demo vault to `~/Documents/Slate Vault` and opens it. Safe to delete afterwards.

After that, Slate reopens the last vault automatically. From the terminal you can force one:

```bash
open Slate.app --args --vault ~/Documents/Notes
```

**Switching or closing.** The `⋯` menu at the top of the sidebar has *Open Vault…*, *Rescan*, *Reveal Vault in Finder* and *Close Vault*.

**Several vaults at once.** Each window holds exactly one vault, so open a second window for a second folder:

- **File ▸ New Window** (`⌥⌘N`) opens an empty window at the welcome screen; pick a vault there.
- **File ▸ Open Vault in New Window…** (`⇧⌘O`) picks a folder and opens it in a fresh window.
- `⌘O` opens the folder in the current window if that window has no vault yet, otherwise in a new window.
- Opening a vault that is already open in another window just brings that window to the front — a vault is never open twice.
- Windows are independent: separate vault, separate selection, separate layout. Settings apply to all of them.

Window positions are not restored on the next launch; Slate reopens a single window with the last vault you used.

## 3. The window

```
┌──────────────┬───────────────┬──────────────────────────────┐
│ SIDEBAR      │ NOTE LIST     │ EDITOR                       │
│ All Notes 7  │ Search        │  # Welcome to Slate          │
│ Starred      │ ───────────── │                              │
│ Recent       │ Welcome…  14:3│  This is a markdown vault…   │
│ FOLDERS      │ Roadmap   14:2│                              │
│ ▸ Projects   │ Reading…  13:0│                              │
└──────────────┴───────────────┴──────────────────────────────┘
```

The sidebar and note list are fixed-width; the editor takes the rest and keeps a readable ~800 pt column, centred, however wide the window is.

## 4. Sidebar

| Row | Shows |
| --- | --- |
| **All Notes** | every note in the vault |
| **Starred** | only starred notes |
| **Recently Edited** | notes edited in the last 14 days (falls back to all notes when empty) |
| **Vault Root** (house) | only the notes saved directly in the vault root — the loose `Note.md` files |
| Folder | that folder *and everything under it* |

- Counts on the right are note totals; a folder's count includes its descendants.
- Click the disclosure triangle to collapse or expand a folder; clicking a folder name also expands it.
- **Vault Root** sits above the top-level folders and starts open, so folders at the root of the vault are always one row away.
- `⌄` / `⌃` next to **FOLDERS** expand or collapse every folder at once — handy in a big vault.
- `+` next to **FOLDERS** creates a folder inside the currently selected folder.
- Right-click a folder for **New Note Here**, **New Folder Here**, **Reveal in Finder**.

## 5. Note list

Rows show title, a one-line snippet and the edited date. **Starred notes float to the top** of whichever list you are in.

- **Search** filters titles, filenames and full note text, within the current sidebar selection. `✕` clears it.
- **Sort** (the slider icon, top right) offers Date Edited, Date Created and Title. Starred notes still come first.
- **Right-click a note** for Star/Unstar, Rename…, Open in Default App, Reveal in Finder, Move to Trash.
- Title is derived automatically: the first heading, else the first non-empty line, else the filename.

## 6. Writing

The editor is plain text with markdown styled live. Markers such as `##` or `**` stay visible but dimmed, so what you see is exactly what is saved.

### Supported syntax

| Markdown | Renders as |
| --- | --- |
| `# H1` … `###### H6` | sized headings |
| `**bold**`, `__bold__` | bold |
| `*italic*`, `_italic_` | italic |
| `~~struck~~` | strikethrough |
| `` `code` `` | inline code |
| `[text](https://url)` | link (clickable in read mode) |
| `- item` / `* item` / `+ item` | bullets, with nesting |
| `1. item` | numbered list |
| `- [ ]` / `- [x]` | ☐ / ☑ task |
| `> quote` | indented quote |
| ```` ```lang ```` | fenced code block |
| `---`, `***`, `___` | horizontal rule |
| `\*` | escaped character |

Inline markdown is parsed inside headings, list items and quotes. Markdown inside fenced code blocks is left alone.

Not handled yet: tables, images, footnotes, raw HTML and YAML front matter (they are kept as text, never mangled).

### Titles and filenames

New notes are created as `Untitled.md`, `Untitled 2.md`, … As soon as the note's first heading exists and the file is still called `Untitled…`, Slate renames the file to that heading (cleaned of `/ \ : * ? " < > |`). Nothing else ever renames itself; use **Rename…** to change a filename deliberately.

### Saving

There is no Save button to forget. Typing schedules a write 400 ms later; switching notes, switching mode, quitting and `⌘S` all flush immediately. Writes are atomic, so a crash cannot leave a half-written note.

Conflicts: if something outside Slate edits a note, the vault is rescanned and the list updates. The note you are currently typing in keeps your text; Slate will not overwrite your in-progress edit from underneath you.

### Layouts and read mode

The toolbar's segmented control picks how the right pane is split:

- **Live** (`⌘2`, the default) — one pane that *is* the editor, Obsidian-style: headings, bold, italics, links and inline code are drawn as formatted text, and the markdown markers are hidden. Put the caret in a paragraph and that paragraph shows its raw source again so you can edit it; move away and it renders. Your file on disk is always the plain source you typed.
- **Source** (`⌘1`) — styled source only: markers visible (dimmed), nothing concealed.
- **Side by Side** (`⌘3`) — source on the left, rendered preview on the right, the preview following along as you type. Drag the divider to change the balance.
- **Reading** (`⌘4`) — rendered output: markers removed, headings at real sizes, links clickable, tasks as ☑/☐.

In Live preview, list dashes and task checkboxes stay visible even when the surrounding markers are hidden, because they carry the list structure.

`⌘R` jumps to Reading and back to whichever layout you came from. Reading mode is a view, not a conversion: your source is untouched.

The layout belongs to the window, so two vault windows can sit in different layouts. The layout a *new* window starts in is set in **Settings ▸ Appearance**.

### Formatting

The Format menu and the toolbar do the marker typing for you:

- `⌘B` bold, `⌘I` italic, `⌘E` inline code, `⇧⌘X` strikethrough — each toggles off again if the selection is already wrapped.
- `⌥⌘1`/`⌥⌘2`/`⌥⌘3` set heading level, `⌥⌘0` returns to body text.
- `⇧⌘L` bulleted list, and Numbered List / Quote / Task / Code Block in the Format menu.
- List commands apply to every line in the selection.

## 7. Settings

**Slate ▸ Settings…** (`⌘,`) opens one settings window for the whole app. Changes apply immediately to every open vault window — there is no OK button.

| Tab | Setting | Effect |
| --- | --- | --- |
| **General** | Reopen the last vault at launch | Start where you left off instead of the welcome screen. |
| | Autosave delay | How long after the last keystroke a note is written (0.1–2 s). Switching notes, `⌘S` and quitting still save at once. |
| | Rename new notes from their first heading | The Apple Notes behaviour; only files still called `Untitled…` are touched. |
| **Appearance** | Appearance | System, Light or Dark, applied to windows and the settings window itself. |
| | Font size | Body text size; headings, code and indents scale with it. |
| | Text column | Width of the centred column in Live, Source and Reading layouts (Side by Side uses the whole pane). |
| | Check spelling while typing / Show word count | Spell-check the source; show the word count in the editor header. |
| | New windows open in | The layout a freshly opened window starts in. |
| **Advanced** | Watch for external changes | FSEvents watching, so edits from another editor appear within a second. |
| | Metadata location | Where stars and the last note live (`<vault>/.slate/metadata.json`), plus **Reveal Last Vault in Finder**. |
| | Reset All Settings… | Back to factory defaults. Notes and vaults are never affected. |

## 8. Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘N` | new note |
| `⇧⌘N` | new folder |
| `⌥⌘N` | new window (empty, for another vault) |
| `⌘O` / `⇧⌘O` | open vault in this window / in a new window |
| `⌘,` | settings |
| `⌘S` | save now |
| `⌘1` / `⌘2` / `⌘3` / `⌘4` | source / live preview / side by side / reading layout |
| `⌘R` | live ⇄ reading mode |
| `⌘B` / `⌘I` / `⌘E` / `⇧⌘X` | bold / italic / inline code / strikethrough |
| `⌥⌘1` … `⌥⌘3`, `⌥⌘0` | heading 1–3, body text |
| `⇧⌘L` | bulleted list |
| `⌘]` / `⌘[` | next / previous note |
| `⌘F` | find bar over the current note (wrap is on; type to search as you go) |
| `⌘G` / `⇧⌘G` | next / previous find match |
| `⌘Z` / `⇧⌘Z` | undo / redo |

The find bar also appears from **Edit ▸ Find…**, and `Esc` closes it. It searches the open note only — to search the whole vault, use the *Search* field above the note list.

## 9. Organizing

- **New note** (`⌘N`) lands in the folder you have selected, or the folder of the current note when a smart list is selected.
- **New folder** (`⇧⌘N`) lands inside the current folder.
- **Rename** — right-click the row, or click the filename in the editor header. Spaces and unicode are fine; `/` becomes a space.
- **Move to Trash** — the row's context menu. The file goes to the macOS Trash, so `⌘Z` in Finder or “Put Back” recovers it.
- **Moving notes between folders** — do it in Finder (or your file manager). Slate picks the change up within a second.
- **Stars** — toolbar star or the row's context menu. Stored in `<vault>/.slate/metadata.json`.

## 10. Vault on disk

```
My Vault/
├── Welcome.md
├── Projects/
│   ├── Roadmap.md
│   └── Design Notes.md
├── Journal/
│   └── 2026-11-01.md
└── .slate/
    └── metadata.json        {"lastNote":"Welcome.md","starred":["Projects/Roadmap.md"]}
```

Paths in `metadata.json` are relative to the vault root, so moving or renaming the vault folder keeps your stars.

## 11. Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| A note I edited in another app still shows old text | Slate reloads within ~1 s. If the note is open and being edited, your text wins — switch away and back. |
| A new file does not appear | Only `.md`, `.markdown`, `.mdown` and `.txt` are scanned, files ≥ 2 MB are skipped, and dot-folders are ignored. Use *Rescan* in the vault menu. |
| Search finds nothing | Search is scoped to the current sidebar selection; click **All Notes** first. |
| Stars disappeared | `.slate` was deleted or the vault was replaced. Stars do not live in the note files. |
| "Slate.app is damaged" / won't open | The build is ad-hoc signed. Rebuild with `./build.sh`, or `xattr -dr com.apple.quarantine Slate.app` if it was downloaded. |
| Typing feels slow on a huge vault | Every note body is held in memory for search. Vaults up to a few thousand notes are fine. |
| The window will not go narrower than ~900 pt | Intentional minimum so three panes stay usable. |

## 12. FAQ

**Does it work with my Obsidian vault?** Yes — it reads the same folders and files and ignores `.obsidian`. Slate does not write front matter, wikilinks or tags, so it will not damage Obsidian features; it simply shows them as text.

**Can I keep the vault in iCloud Drive or Dropbox?** Yes. Point Slate at the local folder; the sync client does the rest. Avoid two copies of Slate editing the same note at once.

**Is my text ever locked in?** No. Closing Slate leaves plain UTF-8 markdown files. The only non-note file is `.slate/metadata.json`.

**Can I edit the same vault from iOS?** Not with Slate — there is no iOS app yet. Any other markdown editor works on the same folder.

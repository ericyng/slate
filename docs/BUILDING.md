# Building and running

## Requirements

| Need | Version |
| --- | --- |
| macOS | 14.0 or newer (built and tested on macOS 26) |
| Swift toolchain | Swift 6.x (Xcode 27 command line tools used here) |
| Xcode | optional — the package builds with `swift build` alone; Xcode is needed only if you want the debugger or previews |

Check what you have:

```bash
swift --version
xcode-select -p        # should print /Applications/Xcode.app/Contents/Developer
```

If `xcode-select` points at a bare CommandLineTools install, `swift build` still works. If it points nowhere, run `xcode-select --install`.

## Build

```bash
cd Slate
./build.sh
```

That is the whole build. It runs `swift build -c release`, then assembles `Slate.app`:

```
Slate.app/Contents/
├── Info.plist            from Resources/Info.plist
├── MacOS/Slate           the compiled binary
└── Resources/AppIcon.icns
```

and ad-hoc signs the bundle (`codesign --force --deep --sign -`), then refreshes Launch Services so the icon and name show up immediately.

Options:

```bash
CONFIG=debug ./build.sh      # debug build (faster to compile, slower to run)
./build.sh --run             # build, then launch
./build.sh --run --vault ~/Notes   # launch straight into a vault
```

Or use the `Makefile` shortcuts:

```bash
make build      # same as ./build.sh
make run        # build and launch
make debug      # debug build
make test       # swift test
make clean      # remove .build and Slate.app
make icon       # regenerate Resources/AppIcon.icns
```

## Run

```bash
open Slate.app                                 # last vault
open Slate.app --args --vault ~/Notes          # a specific vault
open -n Slate.app --args --vault ~/Notes       # a second instance
```

`--vault` takes any folder; a non-existent path is ignored and the welcome screen appears. Without `--vault`, Slate reopens the last vault from `UserDefaults` (key `lastVaultPath`).

You *can* run the raw binary — `.build/release/Slate` — but it has no bundle, so the app menu, icon, and `UserDefaults` domain are wrong. Use the bundle.

## Test

```bash
swift test                                   # all tests
swift test --filter MarkdownTests/testInlineSpans   # one test
```

The suite covers the markdown parser (headings, fences, lists, tasks, quotes, inline spans, unmatched markers), the renderer (syntax stripping, editor attribute runs staying inside the text) and the derived metadata (titles, snippets, filename cleaning). It does not drive the UI; GUI behaviour is described in the smoke-test list in [PLAN.md](../PLAN.md).

## Install

```bash
cp -R Slate.app /Applications/
```

Or drag it there from Finder. Because it is ad-hoc signed, macOS treats it as a local build: fine on the machine that built it, but another Mac may complain. See *Signing* below.

## The icon

`Resources/AppIcon.icns` is generated once and then reused. To change the artwork, edit `Tools/make-icon.swift` (it draws the same rounded amber tile with three text lines that the welcome screen shows) and regenerate:

```bash
rm -f Resources/AppIcon.icns
./build.sh
```

`build.sh` renders a 1024 px PNG with the script, runs it through `sips` into every iconset size, and calls `iconutil`. You can also do it by hand:

```bash
swift Tools/make-icon.swift /tmp/icon.png
# then build an .iconset from it and: iconutil -c icns /tmp/AppIcon.iconset -o Resources/AppIcon.icns
```

## Working in Xcode

```bash
open Package.swift
```

Xcode opens the package as a project. Choose the **Slate** scheme and Run. Two caveats:

- Xcode runs the executable rather than the `.app` bundle, so the toolbar and window work but the bundle identity differs from the shipped app. Use `./build.sh` for anything you want to keep.
- Previews work for the SwiftUI views; the `NSTextView` wrappers preview as blank because they need a live window.

To add a source file, drop it under `Sources/Slate/…` — SwiftPM picks it up automatically; there is no project file to maintain. Same for tests under `Tests/SlateTests/`.

## Signing and distribution

The build is ad-hoc signed (`-`), which is enough for local use. To hand the app to someone else you need a Developer ID:

```bash
codesign --force --deep --options runtime \
         --sign "Developer ID Application: Name (TEAMID)" Slate.app
xcrun notarytool submit Slate.zip --keychain-profile <profile> --wait
xcrun stapler staple Slate.app
```

None of that is automated here. If a copied build is quarantined, `xattr -dr com.apple.quarantine Slate.app` clears it.

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `error: unable to find utility "swift"` | `xcode-select --install`, or point `xcode-select` at Xcode. |
| Build succeeds but `Slate.app` does not launch | Run it from the terminal to see the crash: `./Slate.app/Contents/MacOS/Slate`. |
| Changes do not appear after rebuilding while the app is open | Quit Slate first; macOS keeps the old process running. `pkill -f Slate.app/Contents/MacOS/Slate` if needed. |
| Icon is still the generic one | Launch Services cache: the build script re-registers it; otherwise `killall Finder` or log out. |
| `swift test` fails to find the module | Run from the package root (the folder with `Package.swift`). |
| Build is slow after switching branches | `rm -rf .build` and rebuild. |

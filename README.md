# QuickFind

QuickFind is a fast, keyboard-first macOS launcher designed with a Raycast-inspired interface. It features split-pane file/app previews, clipboard history, inline calculations and conversions, customizable global shortcuts, and an interactive `⌘K` action panel.

Built as a **Universal 2 macOS application** natively supporting both Apple Silicon (M1/M2/M3/M4) and Intel Macs on macOS 14+.

---

## 🚀 Installation on Any Mac

### Option 1: Download Prebuilt Release (DMG)
1. Download `QuickFind.dmg` from the [Latest Release](../../releases/latest).
2. Open the disk image and drag **QuickFind.app** into your **Applications** folder.
3. Open `QuickFind` from your Applications folder.

> [!NOTE]
> **First-Launch on macOS (Gatekeeper)**:
> Since QuickFind is ad-hoc signed, macOS may prompt: *"QuickFind cannot be opened because Apple cannot check it for malicious software"* or *"is damaged"*.
> - **Easy fix**: Right-click (or Control-click) **QuickFind.app** in `Applications` and select **Open**, then click **Open**.
> - **Or via Terminal**: Run `xattr -cr /Applications/QuickFind.app` to remove the quarantine flag.

---

## ⌨️ Features & Shortcuts

- **Toggle Launcher**: Default is `Option + Space` (customizable in Settings `⌘,`).
- **Split Preview Pane**: View application info, file paths, dimensions/sizes, calculation details, and full clipboard previews with live word/character stats.
- **Raycast-Style Actions**: Press `⌘K` to trigger the contextual Actions panel (Open, Reveal in Finder, Copy Path, Copy Name, Toggle Pin, Quit).
- **Numbered App Launching**: Press `⌘1`–`⌘9` to immediately launch top app matches.
- **Inline Calculator & Conversions**:
  - Math: `12 * 45`, `(100 - 30) / 7`, `2^8`
  - Units: `10 km to mi`, `100 f to c`, `60 sec to min`
  - Currency: `50 USD to EUR`, `100 EUR to JPY` (with local offline caching)
- **Clipboard History**: Search `clipboard` or `clip:query` to search copied history. Pin items with `⌘P` to preserve them permanently.
- **Finder Navigation**: Select any file and press `⌘ Return` to show in Finder, or `⌘ Shift C` to copy the path.

---

## 🛠️ Building From Source

### Local Development Build
```sh
sh scripts/build-app.sh
open "$HOME/Applications/QuickFind.app"
```

### Packaging Universal Release (DMG & ZIP)
```sh
sh scripts/package-release.sh
```
This produces `dist/QuickFind.dmg` and `dist/QuickFind.zip` containing a Universal 2 binary with full AppIcon assets and codesigning.

---

## 🔒 Privacy & Permissions

- All indexing, ranking, and clipboard history are stored strictly locally on your Mac.
- Clipboard capture can be paused at any time from the Settings menu.
- QuickFind uses macOS Spotlight metadata and standard AppKit APIs.

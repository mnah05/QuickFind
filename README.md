# QuickFind

QuickFind is a fast, keyboard-first macOS launcher designed with a Raycast-inspired interface. It features split-pane file/app previews, clipboard history, inline calculations and conversions, customizable global shortcuts, and an interactive `⌘K` action panel.

Built as a **Universal 2 macOS application** natively supporting both Apple Silicon (M1/M2/M3/M4) and Intel Macs on macOS 14+.

---

## 📚 Documentation

- 📥 [**Installation & Gatekeeper Guide**](docs/INSTALLATION.md) — Step-by-step setup for any Mac, DMG/ZIP instructions, and security approvals.
- ✨ [**Features & User Guide**](docs/FEATURES.md) — Comprehensive guide to Raycast UI, shortcuts, fuzzy search, clipboard, and calculator.
- 🚀 [**Release & CI/CD Workflow**](docs/RELEASES.md) — How the GitHub Actions automated release pipeline builds and deploys Universal 2 releases.

---

## 🚀 Quick Install on Any Mac

### Prebuilt Release (DMG)
1. Download `QuickFind.dmg` from the [Latest Release](https://github.com/mnah05/QuickFind/releases/latest).
2. Open the disk image and drag **QuickFind.app** into your **Applications** folder.
3. Launch `QuickFind` from Applications.

> [!NOTE]
> **First-Launch on macOS (Gatekeeper)**:
> Since QuickFind is open-source and ad-hoc signed:
> - **Easy fix**: Right-click (or Control-click) `QuickFind.app` in `Applications`, select **Open**, and confirm.
> - **Or via Terminal**: Run `xattr -cr /Applications/QuickFind.app`.
> - See the full [Installation Guide](docs/INSTALLATION.md) for details.

---

## ⌨️ Features & Shortcuts

- **Toggle Launcher**: Default is `Option + Space` (customizable in Settings `⌘,`).
- **Split Preview Pane**: View application info, file paths, dimensions/sizes, calculation details, and full clipboard previews with live word/character stats.
- **Raycast Actions Panel (`⌘K`)**: Instant contextual actions including Open, Reveal in Finder (`⌘↵`), Copy Path (`⌘⇧C`), Copy Name, Toggle Pin (`⌘P`), Settings, and Quit.
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

### Packaging Universal Release Locally (DMG & ZIP)
```sh
sh scripts/package-release.sh
```
This produces `dist/QuickFind.dmg` and `dist/QuickFind.zip` containing a Universal 2 binary with full AppIcon assets and codesigning.

### Automated Releases (GitHub Actions)
The repository includes a GitHub Action workflow ([`.github/workflows/release.yml`](.github/workflows/release.yml)) that automatically builds the universal binary, packages the DMG & ZIP, and publishes the release on GitHub.

To publish a new release:
```sh
git tag v1.0.1
git push origin v1.0.1
```
You can also trigger it manually from the **Actions** tab on GitHub via `workflow_dispatch`. See [Release Workflow](docs/RELEASES.md) for full instructions.

---

## 🔒 Privacy & Permissions

- All indexing, ranking, and clipboard history are stored strictly locally on your Mac.
- Sensitive pasteboards (such as 1Password passwords or transient types) are automatically ignored.
- Clipboard capture can be paused at any time from the Settings menu.
- QuickFind uses macOS Spotlight metadata and standard AppKit APIs.

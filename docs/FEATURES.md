# Features & User Guide

QuickFind is modeled after Raycast to deliver a lightning-fast, keyboard-driven launcher for macOS.

---

## 🎨 Raycast Interface

- **Split View Layout**: Left-side 395px filtered search results list with a dynamic right-side preview pane.
- **Preview Pane**:
  - **Applications**: High-res app icon, bundle identifier, version number, app location, and quick actions hint.
  - **Files**: Large document icon, file size, last modified timestamp, containing directory path.
  - **Clipboard Entries**: Live character and word counters, full scrollable multiline code/text preview.
  - **Calculations**: Large computed answer cards with formula breakdown and copy shortcuts.
- **Search Header & Breadcrumbs**: Search loupe indicator, breadcrumb filter badge (e.g. `[📋 Clipboard ×]`), query input, clear query button, and settings toggle.
- **Bottom Status & Action Bar**:
  - Left: Context-sensitive primary action hint (e.g., `↵ Open Application`, `↵ Copy to Clipboard`).
  - Right: `Actions ⌘K` command panel trigger.

---

## ⌨️ Complete Keyboard Shortcuts Reference

| Shortcut | Context | Action |
| :--- | :--- | :--- |
| `⌥ Space` | Anywhere | Toggle QuickFind window |
| `↑` / `↓` | List | Navigate through search results |
| `Return` (`↵`) | Selected Item | Execute primary action (Open app/file, copy result) |
| `⌘1` – `⌘9` | App Results | Instantly open application by rank number |
| `⌘ Return` | File Result | Reveal item in Finder |
| `⌘ Shift C` | Any Result | Copy path / content to clipboard |
| `⌘K` | Anywhere | Open or close the Raycast Actions panel |
| `⌘,` | Anywhere | Open QuickFind Settings |
| `⌘P` | Clipboard Item | Toggle Pin status (protects from auto-expiry) |
| `Esc` | Window | Dismiss Action Panel, clear query, or hide launcher |

---

## 🔎 Search Capabilities

### Fuzzy Search
QuickFind uses intelligent fuzzy string matching:
- Exact prefix and title matches rank highest.
- Usage tracking prioritizes frequently and recently opened apps.
- Matched substring characters are highlighted in the UI.

### File Search
Searches local files via macOS Spotlight metadata:
- Fast asynchronous debounced queries.
- Excludes `.Trash` and non-document packages.
- Displays directory paths and file size metadata.

### Clipboard History
- Search `clipboard` or `clip:<term>` to browse past clippings.
- Filter out sensitive clipboard entries automatically (passwords copied from 1Password and concealed pasteboards are ignored).
- Configurable auto-expiry (defaults to 30 days; pinned entries never expire).

### Calculations & Conversions
Enter expressions directly into the search bar:
- **Math**: `25 * 4`, `(100 - 25) / 5`, `2^16`, `10 % 3`
- **Unit Conversions**: `10 km to mi`, `60 sec to min`, `100 f to c`, `1 kg to lb`
- **Currency Conversions**: `100 USD to EUR`, `50 GBP to JPY` (uses a previously cached local rate for up to seven days; no network lookup is performed. Without a cached rate, conversion is unavailable.)

### Updates
- Update checks are opt-in in Settings. When enabled, QuickFind checks GitHub once at launch; “Check now” is always available.
- If a newer release exists, QuickFind offers to download and open its DMG. You choose when to download and replace the installed app.
- Update checks contact GitHub only for release information. No search queries, clipboard contents, or usage history are sent.

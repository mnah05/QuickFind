# Installation & Distribution Guide

QuickFind is packaged as a **Universal 2 macOS application**, meaning it runs natively at full speed on both Apple Silicon (M1, M2, M3, M4) and Intel Macs running macOS 14 (Sonoma) or newer.

---

## 📥 Installing on Another Mac

### Method A: DMG Installer (Recommended)

1. Download `QuickFind.dmg` from the [Latest Release](https://github.com/mnah05/QuickFind/releases/latest).
2. Double-click `QuickFind.dmg` to mount the disk image.
3. Drag the **QuickFind** app icon onto the **Applications** shortcut.
4. Eject the disk image.
5. Launch **QuickFind** from your Applications folder or Spotlight.

---

### Method B: ZIP Archive

1. Download `QuickFind.zip` from the [Latest Release](https://github.com/mnah05/QuickFind/releases/latest).
2. Double-click `QuickFind.zip` to extract `QuickFind.app`.
3. Move `QuickFind.app` to your `/Applications` folder:
   ```bash
   mv ~/Downloads/QuickFind.app /Applications/
   ```
4. Launch `QuickFind` from `/Applications`.

---

## 🛡️ Resolving macOS Gatekeeper Warnings

Since QuickFind is distributed outside the Mac App Store with ad-hoc signing, macOS Gatekeeper may display a security alert when opened for the first time on a new Mac:

> *"QuickFind cannot be opened because Apple cannot check it for malicious software"*  
> or  
> *"QuickFind is damaged and cannot be opened"*

This is standard macOS protection for non-notarized open-source binaries. You can resolve it in two ways:

### Solution 1: Control-Click (UI)
1. Open the `/Applications` folder in Finder.
2. **Right-click** (or hold **Control** and click) on `QuickFind.app`.
3. Choose **Open** from the context menu.
4. Click **Open** in the dialog box that appears.
*(macOS will remember this approval and you can open the app normally in the future).*

### Solution 2: Terminal Command
Run this command once in Terminal to clear the download quarantine flag:
```bash
xattr -cr /Applications/QuickFind.app
```

---

## ⚙️ Initial Setup & Permissions

- **Global Shortcut**: Press `⌥ Space` (Option + Space) to toggle the launcher. You can change this anytime from the Settings menu (`⌘,`).
- **Open at Login**: Click the Settings gear or press `⌘,` and check **Open at login** to start QuickFind automatically.
- **Spotlight Indexing**: QuickFind relies on macOS Spotlight for file searches. Ensure the folders you want to search are indexed by Spotlight (**System Settings → Siri & Spotlight → Spotlight Privacy**).

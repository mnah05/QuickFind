# Release & CI/CD Workflow Documentation

QuickFind features an automated release workflow powered by GitHub Actions ([`.github/workflows/release.yml`](../.github/workflows/release.yml)). It compiles native Universal 2 binaries, creates production disk images (`.dmg`) and zip archives (`.zip`), and publishes GitHub releases automatically.

---

## 🚀 How to Trigger a Release

### Method 1: Git Version Tagging (Recommended)

1. Make sure your local `main` branch is up to date and clean:
   ```bash
   git checkout main
   git pull origin main
   ```

2. Create a new semantic version tag (must start with `v`, e.g., `v1.0.4`, `v1.1.0`):
   ```bash
   git tag v1.0.4
   ```

3. Push the tag to GitHub:
   ```bash
   git push origin v1.0.4
   ```

4. The GitHub Action will automatically:
   - Check out the repository on an Apple Silicon (`macos-15`) runner.
   - Run `scripts/package-release.sh`.
   - Compile both Apple Silicon (`arm64`) and Intel (`x86_64`) binaries.
   - Merge them with `lipo` into a single Universal 2 binary.
   - Package `QuickFind.dmg` (with drag-to-Applications symlink) and `QuickFind.zip`.
   - Publish a new GitHub Release with automatically generated release notes and attach both assets.

---

### Method 2: Manual Trigger via GitHub UI (`workflow_dispatch`)

1. Go to the [Actions tab](https://github.com/mnah05/QuickFind/actions) on GitHub.
2. In the left sidebar, click **Release**.
3. Click the **Run workflow** dropdown on the right.
4. Enter the desired tag name (e.g. `v1.0.4`).
5. Click **Run workflow**.

---

## 🛠️ Local Release Packaging

You can test or create release artifacts locally without pushing a tag:

```bash
sh scripts/package-release.sh
```

### Generated Artifacts
All release artifacts are generated into the `dist/` directory:
- `dist/QuickFind.app`: Self-contained, signed Universal 2 app bundle.
- `dist/QuickFind.dmg`: Compressed UDZO disk image ready for user distribution.
- `dist/QuickFind.zip`: Compressed zip archive preserving macOS extended attributes and codesign metadata.

---

## 🔍 Verifying the Universal Binary

To confirm that the output binary supports both architectures:

```bash
file dist/QuickFind.app/Contents/MacOS/QuickFind
```

Expected output:
```
dist/QuickFind.app/Contents/MacOS/QuickFind: Mach-O universal binary with 2 architectures: [x86_64:Mach-O 64-bit executable x86_64] [arm64]
```

---

## 🔐 Permissions & GitHub Token

The workflow uses GitHub's built-in `GITHUB_TOKEN` with write permissions:
```yaml
permissions:
  contents: write
```
No additional personal access tokens (PAT) or external secrets are required.

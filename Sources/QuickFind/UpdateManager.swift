import AppKit
import Combine
import Foundation

@MainActor
final class UpdateManager: ObservableObject {
    static let shared = UpdateManager()

    @Published var automaticChecksEnabled: Bool {
        didSet {
            UserDefaults.standard.set(automaticChecksEnabled, forKey: "automaticUpdateChecks.v1")
            if automaticChecksEnabled { checkNow() }
        }
    }
    @Published private(set) var statusMessage = "Updates are checked only when you ask or enable automatic checks."
    @Published private(set) var isChecking = false

    private let releaseEndpoint = URL(string: "https://api.github.com/repos/mnah05/QuickFind/releases/latest")!
    private var promptIsVisible = false
    private let dismissedVersionKey = "dismissedUpdateVersion.v1"

    private init() {
        automaticChecksEnabled = UserDefaults.standard.bool(forKey: "automaticUpdateChecks.v1")
    }

    func checkAutomaticallyIfEnabled() {
        guard automaticChecksEnabled else { return }
        checkNow()
    }

    func checkNow() {
        guard !isChecking else { return }
        isChecking = true
        statusMessage = "Checking GitHub for a newer release…"
        Task { await fetchLatestRelease() }
    }

    private func fetchLatestRelease() async {
        defer { isChecking = false }
        do {
            var request = URLRequest(url: releaseEndpoint)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("QuickFind/\(installedVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode),
                  data.count < 1_000_000 else {
                throw UpdateError.invalidResponse
            }
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard release.htmlURL.scheme == "https",
                  release.htmlURL.host == "github.com" else {
                throw UpdateError.invalidResponse
            }

            let latestVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            guard Self.isVersion(latestVersion, newerThan: installedVersion) else {
                statusMessage = "You’re up to date (v\(installedVersion))."
                return
            }

            statusMessage = "QuickFind v\(latestVersion) is available."
            guard UserDefaults.standard.string(forKey: dismissedVersionKey) != release.tagName else { return }
            presentUpdatePrompt(release, version: latestVersion)
        } catch is CancellationError {
            statusMessage = "Update check cancelled."
        } catch {
            statusMessage = "Couldn’t check for updates. Try again when you’re online."
        }
    }

    private var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private func presentUpdatePrompt(_ release: GitHubRelease, version: String) {
        guard !promptIsVisible else { return }
        promptIsVisible = true
        defer { promptIsVisible = false }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "QuickFind v\(version) is available"
        alert.informativeText = "You have v\(installedVersion). Download and open the DMG to replace your current copy. This update check only contacts GitHub."
        alert.addButton(withTitle: "Download Update")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(release.tagName, forKey: dismissedVersionKey)
            return
        }

        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".dmg") }) else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }
        downloadAndOpen(asset, version: version)
    }

    private func downloadAndOpen(_ asset: GitHubRelease.Asset, version: String) {
        guard asset.downloadURL.scheme == "https",
              let host = asset.downloadURL.host,
              ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"].contains(host) else {
            statusMessage = "GitHub returned an unexpected download address. Open the release page to download it."
            return
        }

        statusMessage = "Downloading QuickFind v\(version)…"
        Task {
            do {
                var request = URLRequest(url: asset.downloadURL)
                request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
                request.setValue("QuickFind/\(installedVersion)", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 120
                let (temporaryURL, response) = try await URLSession.shared.download(for: request)
                guard let response = response as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else {
                    throw UpdateError.invalidResponse
                }

                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let destination = downloads.appendingPathComponent("QuickFind-v\(version)-\(UUID().uuidString.prefix(8)).dmg")
                try FileManager.default.moveItem(at: temporaryURL, to: destination)
                NSWorkspace.shared.open(destination)
                statusMessage = "Opened the downloaded DMG. Replace your current QuickFind app to finish updating."
            } catch {
                statusMessage = "Download failed. Try again or open the GitHub release page."
            }
        }
    }

    private static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        func components(_ version: String) -> [Int]? {
            let pieces = version.split(separator: ".", omittingEmptySubsequences: false)
            guard !pieces.isEmpty else { return nil }
            let values = pieces.compactMap { Int($0) }
            return values.count == pieces.count ? values : nil
        }
        guard let candidateParts = components(candidate), let currentParts = components(current) else { return false }
        for index in 0..<max(candidateParts.count, currentParts.count) {
            let candidateValue = index < candidateParts.count ? candidateParts[index] : 0
            let currentValue = index < currentParts.count ? currentParts[index] : 0
            if candidateValue != currentValue { return candidateValue > currentValue }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    struct Asset: Decodable {
        let name: String
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
        }
    }
}

private enum UpdateError: Error {
    case invalidResponse
}

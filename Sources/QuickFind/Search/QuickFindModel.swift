import AppKit
import Combine

private struct CachedAppCatalogue: Codable { let paths: [String] }

private struct AppSearchEntry {
    let result: SearchResult
    let normalizedName: String
    init(url: URL) {
        result = SearchResult.app(url: url)
        normalizedName = FuzzyMatcher.normalize(result.title)
    }
}

@MainActor
final class QuickFindModel: NSObject, ObservableObject {
    @Published var query = "" { didSet { search() } }
    @Published var results: [SearchResult] = []
    @Published var calculation: CalculationDisplay?
    @Published var searchingFiles = false
    @Published private(set) var appsReady = false
    @Published private(set) var parsed: ParsedQuery = .empty

    private var appEntries: [AppSearchEntry] = []
    private let appCatalogueKey = "appCatalogue.v1"
    private var metadataQuery: NSMetadataQuery?
    private var fileSearchWorkItem: DispatchWorkItem?
    private var fileSearchTimeout: DispatchWorkItem?
    private var currencyRates: [String: CachedCurrencyRate] = {
        guard let data = UserDefaults.standard.data(forKey: "currencyRates.v1"),
              let rates = try? JSONDecoder().decode([String: CachedCurrencyRate].self, from: data) else { return [:] }
        return rates
    }()

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: appCatalogueKey),
           let cached = try? JSONDecoder().decode(CachedAppCatalogue.self, from: data) {
            appEntries = cached.paths.map { AppSearchEntry(url: URL(fileURLWithPath: $0)) }
            appsReady = !appEntries.isEmpty
        }
        Task { [weak self] in
            let urls = await Task.detached(priority: .utility) {
                Self.discoverApps()
            }.value
            guard let self else { return }
            self.appEntries = urls.map { AppSearchEntry(url: $0) }
            self.appsReady = true
            if let data = try? JSONEncoder().encode(CachedAppCatalogue(paths: urls.map(\.path))) {
                UserDefaults.standard.set(data, forKey: self.appCatalogueKey)
            }
            self.search()
        }
    }

    func search() {
        fileSearchWorkItem?.cancel()
        fileSearchTimeout?.cancel()
        calculation = nil
        searchingFiles = false
        stopFileSearch()
        parsed = ParsedQuery.parse(query)

        switch parsed {
        case .empty:
            results = defaultSuggestions()
        case .clipboard(let filter):
            results = ClipboardHistory.shared.entries
                .filter { filter.isEmpty || $0.text.localizedCaseInsensitiveContains(filter) }
                .map(SearchResult.clipboard)
        case .currency(let request):
            results = []
            if request.base == request.quote {
                calculation = CalculatorEngine.currencyDisplay(for: request, input: query, rate: 1, date: "same currency")
            } else {
                let key = "\(request.base)-\(request.quote)"
                let inverseKey = "\(request.quote)-\(request.base)"
                if let cached = currencyRates[key], Date().timeIntervalSince(cached.fetchedAt) < 7 * 24 * 60 * 60 {
                    calculation = CalculatorEngine.currencyDisplay(for: request, input: query, rate: cached.rate, date: cached.date, detailPrefix: "Local cached reference rate")
                } else if let inverse = currencyRates[inverseKey], Date().timeIntervalSince(inverse.fetchedAt) < 7 * 24 * 60 * 60 {
                    calculation = CalculatorEngine.currencyDisplay(for: request, input: query, rate: 1 / inverse.rate, date: inverse.date, detailPrefix: "Local cached inverse rate")
                } else {
                    calculation = CalculatorEngine.error(query, "Currency conversion needs a locally cached rate. No rate is available offline.")
                }
            }
        case .calculation(let display):
            calculation = display
            results = []
        case .search(let text):
            results = rankedApps(matching: text)
            searchingFiles = true
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard ParsedQuery.parse(self.query) == .search(text) else {
                    self.searchingFiles = false
                    return
                }
                self.startFileSearch(for: text)
            }
            fileSearchWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }

    func activate(_ result: SearchResult) {
        if result.id == "cmd:clipboard" {
            self.query = "clip"
            return
        }
        if let url = result.url {
            UsageTracker.shared.recordUse(of: url)
            if result.kind == .app {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    guard error != nil else { return }
                    DispatchQueue.main.async { NSWorkspace.shared.open(url) }
                }
            } else {
                NSWorkspace.shared.open(url)
            }
        } else if let text = result.text {
            ClipboardHistory.shared.copy(text)
        }
    }

    private func defaultSuggestions() -> [SearchResult] {
        guard appsReady else { return [] }
        let ranked = appEntries.compactMap { entry -> (Int, Date, SearchResult)? in
            guard let url = entry.result.url else { return nil }
            let usage = UsageTracker.shared.usageRank(for: url)
            return (usage.count, usage.lastUsed ?? Date.distantPast, entry.result)
        }
        .sorted {
            if $0.0 != $1.0 { return $0.0 > $1.0 }
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.2.title.localizedStandardCompare($1.2.title) == .orderedAscending
        }
        .prefix(15)
        .map(\.2)

        var items = Array(ranked)
        items.append(SearchResult(
            id: "cmd:clipboard",
            title: "Clipboard History",
            detail: "QuickFind Command",
            kind: .clipboard,
            url: nil,
            text: nil
        ))
        return items
    }

    private func rankedApps(matching text: String) -> [SearchResult] {
        let normalizedQuery = FuzzyMatcher.normalize(text)
        return appEntries.compactMap { entry -> (Double, SearchResult)? in
            guard let url = entry.result.url,
                  let rank = UsageTracker.shared.score(normalizedName: entry.normalizedName, query: normalizedQuery, url: url) else { return nil }
            return (rank, entry.result)
        }
        .sorted {
            if $0.0 == $1.0 { return $0.1.title.localizedStandardCompare($1.1.title) == .orderedAscending }
            return $0.0 < $1.0
        }
        .map(\.1)
    }

    private func startFileSearch(for text: String) {
        stopFileSearch()
        guard !text.isEmpty else {
            searchingFiles = false
            return
        }
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.predicate = NSPredicate(
            format: "%K CONTAINS[cd] %@ AND %K != %@",
            NSMetadataItemFSNameKey, text, NSMetadataItemContentTypeKey, "com.apple.application-bundle"
        )
        query.valueListAttributes = [NSMetadataItemPathKey, NSMetadataItemURLKey, NSMetadataItemFSNameKey, NSMetadataItemContentTypeKey]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSNameKey, ascending: true)]
        metadataQuery = query
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidFinish(_:)), name: .NSMetadataQueryDidFinishGathering, object: query)
        query.start()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.metadataQuery === query else { return }
            self.finishFileSearch(query)
        }
        fileSearchTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    }

    @objc private func metadataQueryDidFinish(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery, metadataQuery === query else { return }
        finishFileSearch(query)
    }

    private func finishFileSearch(_ query: NSMetadataQuery) {
        fileSearchTimeout?.cancel()
        fileSearchTimeout = nil
        query.disableUpdates()
        let trimmed: String
        if case .search(let text) = ParsedQuery.parse(self.query) {
            trimmed = text
        } else {
            searchingFiles = false
            stopFileSearch()
            return
        }
        // Rank a larger Spotlight sample so alphabetical ordering is less likely to hide strong matches.
        let count = min(query.resultCount, 250)
        let items = (0..<count).compactMap { query.result(at: $0) as? NSMetadataItem }
        let files = items.compactMap { item -> (Double, SearchResult)? in
            let path = (item.value(forAttribute: NSMetadataItemPathKey) as? String)
                ?? (item.value(forAttribute: NSMetadataItemURLKey) as? String)
            guard let path, !path.isEmpty else { return nil }
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension != "app",
                  !path.contains("/.Trash/") && !path.hasSuffix("/.Trash") else { return nil }
            let result = SearchResult.file(url: url)
            guard let rank = UsageTracker.shared.score(name: result.title, query: trimmed, url: url) else { return nil }
            return (rank, result)
        }
        .sorted {
            if $0.0 == $1.0 { return $0.1.title.localizedStandardCompare($1.1.title) == .orderedAscending }
            return $0.0 < $1.0
        }
        .prefix(35)
        .map(\.1)

        let appResults = results.filter { $0.kind == .app }
        results = (appResults + files).uniqued(by: \.id)
        searchingFiles = false
        stopFileSearch()
    }

    private func stopFileSearch() {
        fileSearchTimeout?.cancel()
        fileSearchTimeout = nil
        if let metadataQuery {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: metadataQuery)
            metadataQuery.stop()
        }
        metadataQuery = nil
        searchingFiles = false
    }

    nonisolated private static func discoverApps() -> [URL] {
        let appRoots = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")
        ]
        let discoveredApps = appRoots.flatMap { root -> [URL] in
            guard FileManager.default.fileExists(atPath: root.path) else { return [] }
            var apps: [URL] = []
            if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                while let url = enumerator.nextObject() as? URL {
                    guard url.pathExtension == "app" else { continue }
                    apps.append(url)
                    enumerator.skipDescendants()
                }
            }
            return apps
        }
        var seenApps = Set<String>()
        return discoveredApps.filter {
            let key = Bundle(url: $0)?.bundleIdentifier ?? $0.resolvingSymlinksInPath().standardizedFileURL.path
            return seenApps.insert(key).inserted
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

import AppKit
import Combine
import CoreServices

private struct CachedAppCatalogue: Codable, Sendable {
    var paths: [String]
    var eventID: UInt64?
    var osVersion: String?
}

struct AppSearchEntry: Sendable {
    let url: URL
    let names: [String]

    init(url: URL) {
        self.init(url: url, names: Self.names(for: url))
    }

    init(url: URL, names: [String]) {
        self.url = url
        self.names = names.isEmpty ? [url.deletingPathExtension().lastPathComponent] : names
    }

    private static func names(for url: URL) -> [String] {
        var names: [String] = []
        func add(_ value: String?) {
            guard var trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return }
            if trimmed.lowercased().hasSuffix(".app") {
                trimmed = String(trimmed.dropLast(4))
            }
            guard !trimmed.isEmpty, !names.contains(trimmed) else { return }
            names.append(trimmed)
        }

        add(url.deletingPathExtension().lastPathComponent)
        add(FileManager.default.displayName(atPath: url.path))
        guard let bundle = Bundle(url: url) else { return names }
        add(bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String)
        add(bundle.infoDictionary?["CFBundleDisplayName"] as? String)
        add(bundle.localizedInfoDictionary?["CFBundleName"] as? String)
        add(bundle.infoDictionary?["CFBundleName"] as? String)
        if let identifier = bundle.bundleIdentifier {
            add(identifier.split(separator: ".").last.map(String.init))
        }
        return names
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
    private let catalogueMonitor = AppCatalogueMonitor()
    private var catalogueToken = 0
    private var catalogueRefresh: DispatchWorkItem?
    private var activeFileQueries: [NSMetadataQuery] = []
    private var fileQueryLimits: [ObjectIdentifier: Int] = [:]
    private var gatheredFileURLs: [URL] = []
    private var fileSearchPublished = false
    private var fileSearchWorkItem: DispatchWorkItem?
    private var fileSearchTimeout: DispatchWorkItem?
    private var currencyRates: [String: CachedCurrencyRate] = {
        guard let data = UserDefaults.standard.data(forKey: "currencyRates.v1"),
              let rates = try? JSONDecoder().decode([String: CachedCurrencyRate].self, from: data) else { return [:] }
        return rates
    }()

    override init() {
        super.init()
        let cached = loadCatalogue()
        if let cached {
            appEntries = cached.paths.map { path in
                let url = URL(fileURLWithPath: path)
                return AppSearchEntry(url: url, names: [url.deletingPathExtension().lastPathComponent])
            }
            appsReady = !appEntries.isEmpty
            enrichCachedNames()
        }
        let osChanged = cached?.osVersion != Self.osVersion
        catalogueMonitor.start(paths: Self.appRoots.map(\.path), since: cached?.eventID) { [weak self] historyChanged in
            Task { @MainActor in
                guard let self else { return }
                if cached == nil || cached?.eventID == nil || historyChanged || osChanged {
                    self.refreshCatalogue()
                } else {
                    self.noteCatalogueFresh()
                }
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.scheduleCatalogueRefresh()
            }
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
        let ranked = appEntries.map { entry -> (Int, Date, URL) in
            let usage = UsageTracker.shared.usageRank(for: entry.url)
            return (usage.count, usage.lastUsed ?? Date.distantPast, entry.url)
        }
        .sorted {
            if $0.0 != $1.0 { return $0.0 > $1.0 }
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            let leftName = $0.2.deletingPathExtension().lastPathComponent
            let rightName = $1.2.deletingPathExtension().lastPathComponent
            return leftName.localizedStandardCompare(rightName) == .orderedAscending
        }
        .prefix(15)
        .map { SearchResult.app(url: $0.2) }

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
        return appEntries.compactMap { entry -> (Double, URL)? in
            guard let rank = UsageTracker.shared.bestScore(names: entry.names, query: text, url: entry.url) else { return nil }
            return (rank, entry.url)
        }
        .sorted {
            if $0.0 == $1.0 {
                let leftName = $0.1.deletingPathExtension().lastPathComponent
                let rightName = $1.1.deletingPathExtension().lastPathComponent
                return leftName.localizedStandardCompare(rightName) == .orderedAscending
            }
            return $0.0 < $1.0
        }
        .map { SearchResult.app(url: $0.1) }
    }

    private func startFileSearch(for text: String) {
        cancelFileQueries()
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else {
            searchingFiles = false
            return
        }
        fileSearchPublished = false
        gatheredFileURLs = []
        let notApp = NSPredicate(format: "%K != %@", NSMetadataItemContentTypeKey, "com.apple.application-bundle")
        let containsTokens = tokens.map {
            NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, $0)
        }
        beginFileQuery(
            NSCompoundPredicate(andPredicateWithSubpredicates: containsTokens + [notApp]),
            limit: 400
        )
        var strongMatches: [NSPredicate] = tokens.filter { $0.count >= 2 }.map {
            NSPredicate(format: "%K BEGINSWITH[cd] %@", NSMetadataItemFSNameKey, $0)
        }
        for token in tokens where token.count >= 2 {
            for separator in [" ", "_", "-", "."] {
                strongMatches.append(NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, separator + token))
            }
        }
        if !strongMatches.isEmpty {
            beginFileQuery(
                NSCompoundPredicate(andPredicateWithSubpredicates: [
                    NSCompoundPredicate(orPredicateWithSubpredicates: strongMatches),
                    notApp
                ]),
                limit: 200
            )
        }
        guard !activeFileQueries.isEmpty else {
            searchingFiles = false
            return
        }
        let timeout = DispatchWorkItem { [weak self] in
            self?.publishFileResults()
        }
        fileSearchTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    }

    private func beginFileQuery(_ predicate: NSPredicate, limit: Int) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        query.predicate = predicate
        query.valueListAttributes = [NSMetadataItemPathKey, NSMetadataItemURLKey, NSMetadataItemFSNameKey, NSMetadataItemContentTypeKey, NSMetadataItemFSContentChangeDateKey]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        fileQueryLimits[ObjectIdentifier(query)] = limit
        activeFileQueries.append(query)
        NotificationCenter.default.addObserver(self, selector: #selector(metadataQueryDidFinish(_:)), name: .NSMetadataQueryDidFinishGathering, object: query)
        query.start()
    }

    @objc private func metadataQueryDidFinish(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery,
              let index = activeFileQueries.firstIndex(where: { $0 === query }) else { return }
        absorb(query)
        activeFileQueries.remove(at: index)
        NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
        query.stop()
        if activeFileQueries.isEmpty {
            publishFileResults()
        }
    }

    private func absorb(_ query: NSMetadataQuery) {
        query.disableUpdates()
        let limit = fileQueryLimits[ObjectIdentifier(query)] ?? 400
        let count = min(query.resultCount, limit)
        for index in 0..<count {
            guard let item = query.result(at: index) as? NSMetadataItem else { continue }
            let path = (item.value(forAttribute: NSMetadataItemPathKey) as? String)
                ?? (item.value(forAttribute: NSMetadataItemURLKey) as? String)
            guard let path, !path.isEmpty else { continue }
            let url = URL(fileURLWithPath: path)
            guard url.pathExtension != "app",
                  !path.contains("/.Trash/") && !path.hasSuffix("/.Trash") else { continue }
            gatheredFileURLs.append(url)
        }
    }

    private func publishFileResults() {
        guard !fileSearchPublished else { return }
        fileSearchPublished = true
        fileSearchTimeout?.cancel()
        fileSearchTimeout = nil
        for query in activeFileQueries {
            absorb(query)
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
            query.stop()
        }
        activeFileQueries = []
        fileQueryLimits = [:]

        guard case .search(let text) = ParsedQuery.parse(self.query) else {
            searchingFiles = false
            gatheredFileURLs = []
            return
        }

        var seen = Set<String>()
        let files = gatheredFileURLs.filter { seen.insert($0.standardizedFileURL.path).inserted }
            .compactMap { url -> (Double, SearchResult)? in
                let result = SearchResult.file(url: url)
                guard let rank = UsageTracker.shared.score(name: result.title, query: text, url: url) else { return nil }
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
        gatheredFileURLs = []
        searchingFiles = false
    }

    private func stopFileSearch() {
        cancelFileQueries()
        searchingFiles = false
    }

    private func cancelFileQueries() {
        fileSearchTimeout?.cancel()
        fileSearchTimeout = nil
        fileSearchPublished = true
        for query in activeFileQueries {
            NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
            query.stop()
        }
        activeFileQueries = []
        fileQueryLimits = [:]
        gatheredFileURLs = []
    }

    private func loadCatalogue() -> CachedAppCatalogue? {
        guard let data = UserDefaults.standard.data(forKey: appCatalogueKey),
              let cached = try? JSONDecoder().decode(CachedAppCatalogue.self, from: data) else { return nil }
        return cached
    }

    private func enrichCachedNames() {
        let token = catalogueToken
        let urls = appEntries.map(\.url)
        Task { [weak self] in
            let entries = await Task.detached(priority: .utility) {
                urls.map { AppSearchEntry(url: $0) }
            }.value
            guard let self, token == self.catalogueToken else { return }
            self.appEntries = entries
            self.search()
        }
    }

    private func scheduleCatalogueRefresh() {
        catalogueRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refreshCatalogue() }
        catalogueRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func refreshCatalogue() {
        catalogueRefresh?.cancel()
        catalogueToken += 1
        let token = catalogueToken
        let eventID = FSEventsGetCurrentEventId()
        Task { [weak self] in
            let entries = await Task.detached(priority: .utility) {
                Self.discoverApps().map { AppSearchEntry(url: $0) }
            }.value
            guard let self, token == self.catalogueToken else { return }
            self.appEntries = entries
            self.appsReady = true
            self.saveCatalogue(paths: entries.map(\.url.path), eventID: eventID)
            self.search()
        }
    }

    private func noteCatalogueFresh() {
        saveCatalogue(paths: appEntries.map(\.url.path), eventID: FSEventsGetCurrentEventId())
    }

    private func saveCatalogue(paths: [String], eventID: FSEventStreamEventId) {
        let cached = CachedAppCatalogue(paths: paths, eventID: UInt64(eventID), osVersion: Self.osVersion)
        if let data = try? JSONEncoder().encode(cached) {
            UserDefaults.standard.set(data, forKey: appCatalogueKey)
        }
    }

    nonisolated private static var osVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    nonisolated private static var appRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            URL(fileURLWithPath: "/System/Volumes/Preboot/Cryptexes/App/System/Applications"),
            URL(fileURLWithPath: "/System/Library/CoreServices/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")
        ]
    }

    nonisolated private static func discoverApps() -> [URL] {
        let appRoots = Self.appRoots
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

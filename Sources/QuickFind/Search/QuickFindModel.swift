import AppKit
import Combine

@MainActor
final class QuickFindModel: NSObject, ObservableObject {
    @Published var query = "" { didSet { search() } }
    @Published var results: [SearchResult] = []
    @Published var calculation: CalculationDisplay?
    @Published var searchingFiles = false
    @Published private(set) var appsReady = false
    @Published private(set) var parsed: ParsedQuery = .empty

    private var appURLs: [URL] = []
    private var metadataQuery: NSMetadataQuery?
    private var fileSearchWorkItem: DispatchWorkItem?
    private var fileSearchTimeout: DispatchWorkItem?
    private var currencyTask: Task<Void, Never>?
    private var currencyRates: [String: CachedCurrencyRate] = {
        guard let data = UserDefaults.standard.data(forKey: "currencyRates.v1"),
              let rates = try? JSONDecoder().decode([String: CachedCurrencyRate].self, from: data) else { return [:] }
        return rates
    }()

    override init() {
        super.init()
        Task.detached(priority: .userInitiated) { [weak self] in
            let urls = Self.discoverApps()
            await MainActor.run {
                guard let self else { return }
                self.appURLs = urls
                self.appsReady = true
                self.search()
            }
        }
    }

    func search() {
        fileSearchWorkItem?.cancel()
        fileSearchTimeout?.cancel()
        currencyTask?.cancel()
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
                if let cached = currencyRates[key], Date().timeIntervalSince(cached.fetchedAt) < 24 * 60 * 60 {
                    calculation = CalculatorEngine.currencyDisplay(for: request, input: query, rate: cached.rate, date: cached.date)
                } else if let inverse = currencyRates[inverseKey], Date().timeIntervalSince(inverse.fetchedAt) < 24 * 60 * 60 {
                    calculation = CalculatorEngine.currencyDisplay(for: request, input: query, rate: 1 / inverse.rate, date: inverse.date)
                } else {
                    calculation = CalculatorEngine.loadingCurrency(query, request: request)
                }
                loadCurrencyRate(request, input: query)
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
        let ranked = appURLs.map { url -> (Int, Date, SearchResult) in
            let result = SearchResult.app(url: url)
            let usage = UsageTracker.shared.usageRank(for: url)
            return (usage.count, usage.lastUsed ?? Date.distantPast, result)
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
        appURLs.compactMap { url -> (Double, SearchResult)? in
            let result = SearchResult.app(url: url)
            guard let rank = UsageTracker.shared.score(name: result.title, query: text, url: url) else { return nil }
            return (rank, result)
        }
        .sorted {
            if $0.0 == $1.0 { return $0.1.title.localizedStandardCompare($1.1.title) == .orderedAscending }
            return $0.0 < $1.0
        }
        .map(\.1)
    }

    private func loadCurrencyRate(_ request: CurrencyRequest, input: String) {
        currencyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled, self.query == input else { return }
            let key = "\(request.base)-\(request.quote)"
            let inverseKey = "\(request.quote)-\(request.base)"
            do {
                if let cached = currencyRates[key], Date().timeIntervalSince(cached.fetchedAt) < 24 * 60 * 60 {
                    calculation = CalculatorEngine.currencyDisplay(for: request, input: input, rate: cached.rate, date: cached.date)
                    return
                }
                if let inverse = currencyRates[inverseKey], Date().timeIntervalSince(inverse.fetchedAt) < 24 * 60 * 60 {
                    calculation = CalculatorEngine.currencyDisplay(for: request, input: input, rate: 1 / inverse.rate, date: inverse.date)
                    return
                }
                let response = try await CurrencyRateService.latestRate(base: request.base, quote: request.quote)
                guard !Task.isCancelled, query == input else { return }
                let cached = CachedCurrencyRate(rate: response.rate, date: response.date, fetchedAt: Date())
                currencyRates[key] = cached
                if let data = try? JSONEncoder().encode(currencyRates) { UserDefaults.standard.set(data, forKey: "currencyRates.v1") }
                calculation = CalculatorEngine.currencyDisplay(for: request, input: input, rate: response.rate, date: response.date)
            } catch {
                guard !Task.isCancelled, query == input else { return }
                if let cached = currencyRates[key], Date().timeIntervalSince(cached.fetchedAt) < 7 * 24 * 60 * 60 {
                    calculation = CalculatorEngine.currencyDisplay(for: request, input: input, rate: cached.rate, date: cached.date, detailPrefix: "Offline cached rate")
                } else if let inverse = currencyRates[inverseKey], Date().timeIntervalSince(inverse.fetchedAt) < 7 * 24 * 60 * 60 {
                    calculation = CalculatorEngine.currencyDisplay(for: request, input: input, rate: 1 / inverse.rate, date: inverse.date, detailPrefix: "Offline cached inverse rate")
                } else {
                    calculation = CalculatorEngine.error(input, "Currency rate unavailable. Check the currency codes or connection.")
                }
            }
        }
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
        let count = min(query.resultCount, 80)
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

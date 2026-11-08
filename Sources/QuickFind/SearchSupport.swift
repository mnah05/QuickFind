import Foundation
import Combine

private struct UsageRecord: Codable {
    var count: Int
    var lastUsed: Date
}

@MainActor
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()
    private let storageKey = "usageRecords.v1"
    private var records: [String: UsageRecord]

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([String: UsageRecord].self, from: data) {
            records = stored
        } else {
            records = [:]
        }
    }

    func usageRank(for url: URL) -> (count: Int, lastUsed: Date?) {
        let record = records[url.standardizedFileURL.path]
        return (record?.count ?? 0, record?.lastUsed)
    }

    func score(name: String, query: String, url: URL) -> Double? {
        guard let matchScore = FuzzyMatcher.score(name: name, query: query) else { return nil }
        let record = records[url.standardizedFileURL.path]
        let usageBoost = min(log1p(Double(record?.count ?? 0)) * 3.5, 14)
        let ageHours = record.map { max(Date().timeIntervalSince($0.lastUsed) / 3600, 0) } ?? 10_000
        let recentBoost = max(0, 8 - log1p(ageHours) * 1.7)
        return matchScore - usageBoost - recentBoost
    }

    func recordUse(of url: URL) {
        let key = url.standardizedFileURL.path
        let previousCount = records[key]?.count ?? 0
        records[key] = UsageRecord(count: min(previousCount + 1, 100_000), lastUsed: Date())
        if records.count > 2_000 {
            records = records.sorted { $0.value.lastUsed > $1.value.lastUsed }
                .prefix(1_500)
                .reduce(into: [:]) { $0[$1.key] = $1.value }
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

enum FuzzyMatcher {
    static func score(name: String, query: String) -> Double? {
        let needle = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return nil }
        let candidate = normalize(name)
        if candidate == needle { return 0 }
        if candidate.hasPrefix(needle) { return 25 + Double(candidate.count - needle.count) * 0.03 }

        let words = candidate.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(needle) }) { return 45 + Double(candidate.count - needle.count) * 0.05 }
        if let range = candidate.range(of: needle) { return 65 + Double(candidate.distance(from: candidate.startIndex, to: range.lowerBound)) * 0.12 }

        let candidateChars = Array(candidate)
        let queryChars = Array(needle)
        var queryIndex = 0
        var lastMatchIndex: Int?
        var firstMatchIndex = 0
        var gaps = 0
        for (index, character) in candidateChars.enumerated() where queryIndex < queryChars.count {
            guard character == queryChars[queryIndex] else { continue }
            if queryIndex == 0 { firstMatchIndex = index }
            if let lastMatchIndex, index > lastMatchIndex + 1 { gaps += index - lastMatchIndex - 1 }
            lastMatchIndex = index
            queryIndex += 1
        }
        guard queryIndex == queryChars.count else { return nil }
        return 95 + Double(gaps) * 2.2 + Double(firstMatchIndex) * 0.6 + Double(candidateChars.count - queryChars.count) * 0.04
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }
}

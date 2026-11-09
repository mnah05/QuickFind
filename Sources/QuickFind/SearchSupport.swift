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
        guard let matchScore = FuzzyMatcher.match(candidate: name, query: query)?.score else { return nil }
        return adjusted(matchScore, url: url)
    }

    /// Lowest score wins. Each name is an alias (filename, display name, bundle-id suffix).
    func bestScore(names: [String], query: String, url: URL) -> Double? {
        names.compactMap { score(name: $0, query: query, url: url) }.min()
    }

    private func adjusted(_ matchScore: Double, url: URL) -> Double {
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

struct FuzzyHit: Equatable {
    var score: Double
    var ranges: [Range<String.Index>]
}

enum FuzzyMatcher {
    /// Lower scores rank first.
    /// Exact 0, prefix ~25, word prefix ~45, acronym ~50, substring ~65, scattered subsequence ~70+.
    /// Multi-word queries require every token to match; the score is the average of the token scores.
    static func match(candidate: String, query: String) -> FuzzyHit? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let units = Unit.make(from: candidate)
        guard !units.isEmpty else { return nil }

        let foldedQuery = fold(trimmed)
        if units.map(\.folded) == foldedQuery {
            return FuzzyHit(score: 0, ranges: [candidate.startIndex..<candidate.endIndex])
        }

        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return nil }
        if tokens.count == 1 {
            return matchToken(units, in: candidate, token: tokens[0])
        }

        var total = 0.0
        var ranges: [Range<String.Index>] = []
        for token in tokens {
            guard let hit = matchToken(units, in: candidate, token: token) else { return nil }
            total += hit.score
            ranges.append(contentsOf: hit.ranges)
        }
        var score = total / Double(tokens.count)
        if let contiguous = contiguousMatch(units, in: candidate, needle: foldedQuery), contiguous.score < score {
            score = contiguous.score
        }
        return FuzzyHit(score: score, ranges: merge(ranges))
    }

    static func score(name: String, query: String) -> Double? {
        match(candidate: name, query: query)?.score
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
    }

    private static func matchToken(_ units: [Unit], in candidate: String, token: String) -> FuzzyHit? {
        let needle = fold(token)
        guard !needle.isEmpty, needle.count <= units.count else { return nil }
        if units.map(\.folded) == needle {
            return FuzzyHit(score: 0, ranges: [candidate.startIndex..<candidate.endIndex])
        }
        if let prefix = prefixMatch(units, in: candidate, needle: needle) { return prefix }
        if let wordPrefix = wordPrefixMatch(units, in: candidate, needle: needle) { return wordPrefix }
        return [substringMatch(units, in: candidate, needle: needle),
                acronymMatch(units, in: candidate, needle: needle),
                subsequenceMatch(units, in: candidate, needle: needle)]
            .compactMap { $0 }
            .min { $0.score < $1.score }
    }

    private static func contiguousMatch(_ units: [Unit], in candidate: String, needle: [Character]) -> FuzzyHit? {
        if let prefix = prefixMatch(units, in: candidate, needle: needle) { return prefix }
        return substringMatch(units, in: candidate, needle: needle)
    }

    private static func prefixMatch(_ units: [Unit], in candidate: String, needle: [Character]) -> FuzzyHit? {
        guard units.count >= needle.count else { return nil }
        guard Array(units.prefix(needle.count).map(\.folded)) == needle else { return nil }
        let extra = units.count - needle.count
        let sources = units.prefix(needle.count).map(\.source)
        return FuzzyHit(score: 25 + Double(extra) * 0.03, ranges: ranges(for: sources, in: candidate))
    }

    private static func wordPrefixMatch(_ units: [Unit], in candidate: String, needle: [Character]) -> FuzzyHit? {
        let extra = units.count - needle.count
        for index in units.indices where units[index].isBoundary {
            guard index + needle.count <= units.count else { continue }
            let slice = units[index..<(index + needle.count)]
            guard slice.map(\.folded) == needle else { continue }
            return FuzzyHit(score: 45 + Double(extra) * 0.05, ranges: ranges(for: slice.map(\.source), in: candidate))
        }
        return nil
    }

    private static func substringMatch(_ units: [Unit], in candidate: String, needle: [Character]) -> FuzzyHit? {
        guard units.count >= needle.count else { return nil }
        for start in 0...(units.count - needle.count) {
            let slice = units[start..<(start + needle.count)]
            guard slice.map(\.folded) == needle else { continue }
            return FuzzyHit(score: 65 + Double(start) * 0.12, ranges: ranges(for: slice.map(\.source), in: candidate))
        }
        return nil
    }

    /// Query characters that each land on a word start or camelCase boundary, in order.
    private static func acronymMatch(_ units: [Unit], in candidate: String, needle: [Character]) -> FuzzyHit? {
        var queryIndex = 0
        var skippedBoundaries = 0
        var matched: [String.Index] = []
        var first = 0
        for (index, unit) in units.enumerated() where unit.isBoundary {
            guard queryIndex < needle.count else { break }
            if unit.folded == needle[queryIndex] {
                if queryIndex == 0 { first = index }
                matched.append(unit.source)
                queryIndex += 1
            } else {
                skippedBoundaries += 1
            }
        }
        guard queryIndex == needle.count else { return nil }
        let extra = units.count - needle.count
        let score = 50 + Double(skippedBoundaries) * 1.4 + Double(first) * 0.15 + Double(extra) * 0.04
        guard score < 65 else { return nil }
        return FuzzyHit(score: score, ranges: ranges(for: matched, in: candidate))
    }

    private static func subsequenceMatch(_ units: [Unit], in candidate: String, needle: [Character]) -> FuzzyHit? {
        var queryIndex = 0
        var lastMatch: Int?
        var first = 0
        var gaps = 0
        var boundaryHits = 0
        var matched: [String.Index] = []
        for (index, unit) in units.enumerated() where queryIndex < needle.count {
            guard unit.folded == needle[queryIndex] else { continue }
            if queryIndex == 0 { first = index }
            if let lastMatch, index > lastMatch + 1 { gaps += index - lastMatch - 1 }
            if unit.isBoundary { boundaryHits += 1 }
            lastMatch = index
            matched.append(unit.source)
            queryIndex += 1
        }
        guard queryIndex == needle.count else { return nil }
        let extra = units.count - needle.count
        let raw = 95 + Double(gaps) * 2.2 + Double(first) * 0.6 + Double(extra) * 0.04
        let discount = min(Double(boundaryHits) * 6, 25)
        return FuzzyHit(score: max(70, raw - discount), ranges: ranges(for: matched, in: candidate))
    }

    private static func fold(_ value: String) -> [Character] {
        var output: [Character] = []
        output.reserveCapacity(value.count)
        for character in value {
            let folded = String(character).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
            output.append(contentsOf: folded)
        }
        return output
    }

    private static func ranges(for sources: [String.Index], in candidate: String) -> [Range<String.Index>] {
        guard !sources.isEmpty else { return [] }
        let ordered = sources.sorted()
        var result: [Range<String.Index>] = []
        var start = ordered[0]
        var end = candidate.index(after: ordered[0])
        for index in ordered.dropFirst() {
            if index < end { continue }
            if index == end {
                end = candidate.index(after: index)
            } else {
                result.append(start..<end)
                start = index
                end = candidate.index(after: index)
            }
        }
        result.append(start..<end)
        return result
    }

    private static func merge(_ ranges: [Range<String.Index>]) -> [Range<String.Index>] {
        let ordered = ranges.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [Range<String.Index>] = []
        for range in ordered {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                let upper = max(last.upperBound, range.upperBound)
                merged[merged.count - 1] = last.lowerBound..<upper
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private struct Unit {
        var folded: Character
        var source: String.Index
        var isBoundary: Bool

        static func make(from candidate: String) -> [Unit] {
            var units: [Unit] = []
            var previousAlphanumeric = false
            var index = candidate.startIndex
            for character in candidate {
                let folded = String(character).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
                let boundary = units.isEmpty || !previousAlphanumeric || character.isUppercase
                for (offset, item) in folded.enumerated() {
                    units.append(Unit(folded: item, source: index, isBoundary: offset == 0 && boundary))
                }
                previousAlphanumeric = character.isLetter || character.isNumber
                index = candidate.index(after: index)
            }
            return units
        }
    }
}

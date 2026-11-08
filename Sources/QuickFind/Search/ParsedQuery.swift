import Foundation

enum ParsedQuery: Equatable {
    case empty
    case clipboard(filter: String)
    case currency(CurrencyRequest)
    case calculation(CalculationDisplay)
    case search(String)

    static func parse(_ query: String) -> ParsedQuery {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .empty }

        let lowered = raw.localizedLowercase
        if lowered == "clip" || lowered == "clipboard"
            || lowered.hasPrefix("clip:") || lowered.hasPrefix("clip ")
            || lowered.hasPrefix("clipboard:") || lowered.hasPrefix("clipboard ") {
            let prefixLength = lowered.hasPrefix("clipboard") ? "clipboard".count : "clip".count
            let filter = String(raw.dropFirst(prefixLength))
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
            return .clipboard(filter: filter)
        }

        if let local = CalculatorEngine.localCalculation(from: raw) {
            return .calculation(local)
        }

        if let request = CalculatorEngine.currencyRequest(from: raw) {
            return .currency(request)
        }

        return .search(raw)
    }
}

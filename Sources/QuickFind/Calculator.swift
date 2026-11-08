import Foundation

struct CalculationDisplay: Identifiable, Equatable {
    enum State: Equatable { case value, loading, error }
    let id = "calculator"
    let expression: String
    let output: String
    let detail: String
    let copyText: String
    let state: State
}
struct CurrencyRequest: Equatable {
    let amount: Double
    let base: String
    let quote: String
}

struct CachedCurrencyRate: Codable {
    let rate: Double
    let date: String
    let fetchedAt: Date
}

enum CalculatorEngine {
    static func currencyRequest(from input: String) -> CurrencyRequest? {
        guard let groups = captures(
            pattern: #"^\s*((?:[0-9]{1,3}(?:,[0-9]{3})+|(?:[0-9]{1,2},)?[0-9]{2}(?:,[0-9]{2})*,[0-9]{3}|[0-9]+)(?:\.[0-9]+)?|\.[0-9]+)\s+([A-Za-z]{3})\s+(?:to|in)\s+([A-Za-z]{3})\s*$"#,
            input: input
        ), groups.count >= 4, let amount = Double(groups[1].replacingOccurrences(of: ",", with: "")), amount.isFinite, amount >= 0 else { return nil }
        return CurrencyRequest(amount: amount, base: groups[2].uppercased(), quote: groups[3].uppercased())
    }

    static func localCalculation(from input: String) -> CalculationDisplay? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let groups = captures(
            pattern: #"^\s*(-?(?:(?:[0-9]{1,3}(?:,[0-9]{3})+|(?:[0-9]{1,2},)?[0-9]{2}(?:,[0-9]{2})*,[0-9]{3}|[0-9]+)(?:\.[0-9]*)?|\.[0-9]+))\s*([A-Za-z°]+)\s+(?:to|in)\s+([A-Za-z°]+)\s*$"#,
            input: trimmed
        ), groups.count >= 4, let amount = Double(groups[1].replacingOccurrences(of: ",", with: "")), amount.isFinite {
            let source = groups[2].lowercased()
            let target = groups[3].lowercased()
            let from = units[source]
            let to = units[target]
            guard from != nil || to != nil else { return nil }
            guard let from, let to else {
                return error(trimmed, "Unknown unit. Try km, mi, kg, lb, L, gal, °C, °F, or hours.")
            }
            guard from.dimension == to.dimension else {
                return error(trimmed, "Those units measure different things.")
            }
            if from.dimension == "temperature" {
                let celsius: Double
                switch source {
                case "f", "°f", "fahrenheit": celsius = (amount - 32) * 5 / 9
                case "k", "°k", "kelvin": celsius = amount - 273.15
                default: celsius = amount
                }
                guard celsius >= -273.15 else { return error(trimmed, "Temperature can’t be below absolute zero.") }
            }
            let converted = convert(amount, from: source, to: target, fromUnit: from, toUnit: to)
            guard converted.isFinite else { return error(trimmed, "That conversion is outside the supported range.") }
            let output = "\(format(amount)) \(groups[2]) = \(format(converted)) \(groups[3])"
            return CalculationDisplay(expression: trimmed, output: output, detail: "Unit conversion", copyText: "\(format(converted)) \(groups[3])", state: .value)
        }

        let arithmeticInput = normalizeGroupingSeparators(in: trimmed)
        let allowed = CharacterSet(charactersIn: "0123456789.+-*/%^() ×÷−\n\t")
        guard arithmeticInput.unicodeScalars.allSatisfy(allowed.contains), arithmeticInput.contains(where: \.isNumber) else { return nil }
        let operatorOrParenChars = CharacterSet(charactersIn: "+-*/%^×÷−()")
        guard arithmeticInput.unicodeScalars.contains(where: operatorOrParenChars.contains) else { return nil }
        do {
            var parser = try ArithmeticParser(arithmeticInput)
            let value = try parser.evaluate()
            guard value.isFinite else { return error(trimmed, "The result is outside the supported range.") }
            let output = format(value)
            return CalculationDisplay(expression: trimmed, output: output, detail: "Calculator · Return to copy", copyText: output, state: .value)
        } catch ArithmeticError.divisionByZero {
            return error(trimmed, "Cannot divide by zero.")
        } catch ArithmeticError.incomplete {
            return nil
        } catch {
            return nil
        }
    }

    static func currencyDisplay(for request: CurrencyRequest, input: String, rate: Double, date: String, detailPrefix: String = "Reference rate") -> CalculationDisplay {
        let converted = request.amount * rate
        guard converted.isFinite else { return error(input, "That amount is outside the supported range.") }
        let amountText = format(request.amount)
        let output = "\(amountText) \(request.base) = \(format(converted)) \(request.quote)"
        return CalculationDisplay(
            expression: input,
            output: output,
            detail: "\(detailPrefix) · \(request.base)/\(request.quote) · \(date)",
            copyText: "\(format(converted)) \(request.quote)",
            state: .value
        )
    }

    static func loadingCurrency(_ input: String, request: CurrencyRequest) -> CalculationDisplay {
        CalculationDisplay(expression: input, output: "Getting rate…", detail: "\(request.base) to \(request.quote)", copyText: "", state: .loading)
    }

    static func error(_ input: String, _ message: String) -> CalculationDisplay {
        CalculationDisplay(expression: input, output: message, detail: "Calculator", copyText: "", state: .error)
    }

    private struct Unit {
        let dimension: String
        let scale: Double
    }

    private static let units: [String: Unit] = {
        var result: [String: Unit] = [:]
        func add(_ names: [String], _ dimension: String, _ scale: Double) {
            for name in names { result[name] = Unit(dimension: dimension, scale: scale) }
        }
        add(["m", "meter", "meters", "metre", "metres"], "length", 1)
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], "length", 1_000)
        add(["cm", "centimeter", "centimeters", "centimetre", "centimetres"], "length", 0.01)
        add(["mm", "millimeter", "millimeters", "millimetre", "millimetres"], "length", 0.001)
        add(["mi", "mile", "miles"], "length", 1_609.344)
        add(["ft", "foot", "feet"], "length", 0.3048)
        add(["in", "inch", "inches"], "length", 0.0254)
        add(["yd", "yard", "yards"], "length", 0.9144)
        add(["kg", "kilogram", "kilograms"], "mass", 1)
        add(["g", "gram", "grams"], "mass", 0.001)
        add(["mg", "milligram", "milligrams"], "mass", 0.000001)
        add(["lb", "lbs", "pound", "pounds"], "mass", 0.45359237)
        add(["oz", "ounce", "ounces"], "mass", 0.028349523125)
        add(["st", "stone", "stones"], "mass", 6.35029318)
        add(["l", "liter", "liters", "litre", "litres"], "volume", 1)
        add(["ml", "milliliter", "milliliters", "millilitre", "millilitres"], "volume", 0.001)
        add(["gal", "gallon", "gallons"], "volume", 3.785411784)
        add(["cup", "cups"], "volume", 0.2365882365)
        add(["tbsp", "tablespoon", "tablespoons"], "volume", 0.0147867648)
        add(["tsp", "teaspoon", "teaspoons"], "volume", 0.00492892159)
        add(["s", "sec", "second", "seconds"], "time", 1)
        add(["ms", "millisecond", "milliseconds"], "time", 0.001)
        add(["min", "minute", "minutes"], "time", 60)
        add(["h", "hr", "hour", "hours"], "time", 3_600)
        add(["d", "day", "days"], "time", 86_400)
        add(["wk", "week", "weeks"], "time", 604_800)
        add(["c", "°c", "celsius"], "temperature", 1)
        add(["f", "°f", "fahrenheit"], "temperature", 1)
        add(["k", "°k", "kelvin"], "temperature", 1)
        return result
    }()

    private static func convert(_ amount: Double, from source: String, to target: String, fromUnit: Unit, toUnit: Unit) -> Double {
        if fromUnit.dimension == "temperature" {
            let celsius: Double
            switch source {
            case "f", "°f", "fahrenheit": celsius = (amount - 32) * 5 / 9
            case "k", "°k", "kelvin": celsius = amount - 273.15
            default: celsius = amount
            }
            switch target {
            case "f", "°f", "fahrenheit": return celsius * 9 / 5 + 32
            case "k", "°k", "kelvin": return celsius + 273.15
            default: return celsius
            }
        }
        return amount * fromUnit.scale / toUnit.scale
    }

    private static func format(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 8
        formatter.minimumFractionDigits = 0
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func captures(pattern: String, input: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: input) else { return "" }
            return String(input[range])
        }
    }

    private static func normalizeGroupingSeparators(in input: String) -> String {
        let pattern = #"(?<![0-9,])((?:[0-9]{1,3}(?:,[0-9]{3})+|(?:[0-9]{1,2},)?[0-9]{2}(?:,[0-9]{2})*,[0-9]{3})(?:\.[0-9]+)?)(?![0-9,])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input)).reversed()
        var normalized = input
        for match in matches {
            guard let range = Range(match.range(at: 1), in: normalized) else { continue }
            normalized.replaceSubrange(range, with: normalized[range].replacingOccurrences(of: ",", with: ""))
        }
        return normalized
    }
}

private enum ArithmeticError: Error { case incomplete, invalid, divisionByZero }

private struct ArithmeticParser {
    private enum Token { case number(Double), plus, minus, multiply, divide, remainder, power, leftParen, rightParen }
    private var tokens: [Token] = []
    private var index = 0

    init(_ input: String) throws {
        let chars = Array(input.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "\n", with: " "))
        var cursor = 0
        while cursor < chars.count {
            let char = chars[cursor]
            if char.isWhitespace { cursor += 1; continue }
            if char.isNumber || char == "." {
                let start = cursor
                var periods = 0
                var digits = 0
                while cursor < chars.count && (chars[cursor].isNumber || chars[cursor] == ".") {
                    if chars[cursor] == "." { periods += 1 } else { digits += 1 }
                    cursor += 1
                }
                guard periods <= 1, digits > 0, let value = Double(String(chars[start..<cursor])) else { throw ArithmeticError.invalid }
                tokens.append(.number(value))
            } else {
                switch char {
                case "+": tokens.append(.plus)
                case "-": tokens.append(.minus)
                case "*": tokens.append(.multiply)
                case "/": tokens.append(.divide)
                case "%": tokens.append(.remainder)
                case "^": tokens.append(.power)
                case "(": tokens.append(.leftParen)
                case ")": tokens.append(.rightParen)
                default: throw ArithmeticError.invalid
                }
                cursor += 1
            }
            guard tokens.count <= 128 else { throw ArithmeticError.invalid }
        }
    }

    mutating func evaluate() throws -> Double {
        guard !tokens.isEmpty else { throw ArithmeticError.incomplete }
        let value = try parseExpression()
        guard index == tokens.count else { throw ArithmeticError.invalid }
        return value
    }

    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()
        while index < tokens.count {
            if consume(.plus) { value += try parseTerm() }
            else if consume(.minus) { value -= try parseTerm() }
            else { break }
        }
        return value
    }

    private mutating func parseTerm() throws -> Double {
        var value = try parseUnary()
        while index < tokens.count {
            if consume(.multiply) { value *= try parseUnary() }
            else if consume(.divide) {
                let divisor = try parseUnary()
                guard divisor != 0 else { throw ArithmeticError.divisionByZero }
                value /= divisor
            } else if consume(.remainder) {
                let divisor = try parseUnary()
                guard divisor != 0 else { throw ArithmeticError.divisionByZero }
                value = value.truncatingRemainder(dividingBy: divisor)
            } else { break }
        }
        return value
    }

    private mutating func parseUnary() throws -> Double {
        if consume(.plus) { return try parseUnary() }
        if consume(.minus) { return -(try parseUnary()) }
        var value = try parsePrimary()
        if consume(.power) { value = pow(value, try parseUnary()) }
        return value
    }

    private mutating func parsePrimary() throws -> Double {
        guard index < tokens.count else { throw ArithmeticError.incomplete }
        let token = tokens[index]
        index += 1
        switch token {
        case .number(let value): return value
        case .leftParen:
            let value = try parseExpression()
            guard consume(.rightParen) else { throw ArithmeticError.incomplete }
            return value
        default:
            index -= 1
            throw ArithmeticError.invalid
        }
    }

    private mutating func consume(_ expected: Token) -> Bool {
        guard index < tokens.count else { return false }
        let current = tokens[index]
        let matches: Bool
        switch (current, expected) {
        case (.plus, .plus), (.minus, .minus), (.multiply, .multiply), (.divide, .divide),
             (.remainder, .remainder), (.power, .power), (.leftParen, .leftParen), (.rightParen, .rightParen): matches = true
        default: matches = false
        }
        if matches { index += 1 }
        return matches
    }
}

import Foundation

enum FormulaDialect: Equatable {
  case english
  case french

  var decimalSeparator: Character {
    self == .french ? "," : "."
  }

  var argumentSeparator: Character {
    self == .french ? ";" : ","
  }
}

private enum FormulaToken: Equatable {
  case number(Double)
  case identifier(String)
  case string(String)
  case plus
  case minus
  case multiply
  case divide
  case power
  case percent
  case leftParenthesis
  case rightParenthesis
  case separator
  case colon
  case end
}

private indirect enum FormulaExpression {
  case number(Double)
  case text(String)
  case reference(CellAddress)
  case range(CellRange)
  case constant(String)
  case unaryMinus(FormulaExpression)
  case percent(FormulaExpression)
  case binary(Character, FormulaExpression, FormulaExpression)
  case function(String, [FormulaExpression])
}

private struct ParsedFormula {
  var expression: FormulaExpression
  var references: [CellRange]
}

private struct FormulaLexer {
  private let characters: [Character]
  private let dialect: FormulaDialect
  private var index = 0

  init(_ source: String, dialect: FormulaDialect) {
    characters = Array(source)
    self.dialect = dialect
  }

  mutating func tokenize() throws -> [FormulaToken] {
    var tokens: [FormulaToken] = []
    while index < characters.count {
      let character = characters[index]
      if character.isWhitespace {
        index += 1
        continue
      }

      if character.isNumber
        || (character == dialect.decimalSeparator && peekCharacter()?.isNumber == true)
      {
        tokens.append(try readNumber())
        continue
      }

      if character.isLetter || character == "_" || character == "$" {
        tokens.append(.identifier(readIdentifier()))
        continue
      }

      if character == "\"" {
        tokens.append(.string(try readString()))
        continue
      }

      switch character {
      case "+": tokens.append(.plus)
      case "-": tokens.append(.minus)
      case "*": tokens.append(.multiply)
      case "/": tokens.append(.divide)
      case "^": tokens.append(.power)
      case "%": tokens.append(.percent)
      case "(": tokens.append(.leftParenthesis)
      case ")": tokens.append(.rightParenthesis)
      case ":": tokens.append(.colon)
      default:
        if character == dialect.argumentSeparator {
          tokens.append(.separator)
        } else {
          throw SpreadsheetFormulaError.parse
        }
      }
      index += 1
    }
    tokens.append(.end)
    return tokens
  }

  private mutating func readNumber() throws -> FormulaToken {
    var value = ""
    var hasDecimalSeparator = false
    var hasExponent = false

    while index < characters.count {
      let character = characters[index]
      if character.isNumber {
        value.append(character)
        index += 1
        continue
      }
      if character == dialect.decimalSeparator && !hasDecimalSeparator && !hasExponent {
        hasDecimalSeparator = true
        value.append(".")
        index += 1
        continue
      }
      if (character == "e" || character == "E") && !hasExponent && !value.isEmpty {
        hasExponent = true
        value.append(character)
        index += 1
        if index < characters.count,
          (characters[index] == "+" || characters[index] == "-")
        {
          value.append(characters[index])
          index += 1
        }
        continue
      }
      break
    }

    guard let number = Double(value) else {
      throw SpreadsheetFormulaError.parse
    }
    return .number(number)
  }

  private mutating func readIdentifier() -> String {
    var value = ""
    while index < characters.count {
      let character = characters[index]
      if character.isLetter || character.isNumber || character == "_"
        || character == "$" || character == "."
      {
        value.append(character)
        index += 1
      } else {
        break
      }
    }
    return value
  }

  private mutating func readString() throws -> String {
    index += 1
    var value = ""
    while index < characters.count {
      let character = characters[index]
      if character == "\"" {
        if index + 1 < characters.count, characters[index + 1] == "\"" {
          value.append("\"")
          index += 2
          continue
        }
        index += 1
        return value
      }
      value.append(character)
      index += 1
    }
    throw SpreadsheetFormulaError.parse
  }

  private func peekCharacter() -> Character? {
    let next = index + 1
    return next < characters.count ? characters[next] : nil
  }
}

private struct FormulaParser {
  private let tokens: [FormulaToken]
  private var index = 0

  init(tokens: [FormulaToken]) {
    self.tokens = tokens
  }

  mutating func parse() throws -> FormulaExpression {
    let expression = try parseAddition()
    guard current == .end else { throw SpreadsheetFormulaError.parse }
    return expression
  }

  private mutating func parseAddition() throws -> FormulaExpression {
    var expression = try parseMultiplication()
    while current == .plus || current == .minus {
      let operation: Character = current == .plus ? "+" : "-"
      advance()
      expression = .binary(operation, expression, try parseMultiplication())
    }
    return expression
  }

  private mutating func parseMultiplication() throws -> FormulaExpression {
    var expression = try parsePower()
    while current == .multiply || current == .divide {
      let operation: Character = current == .multiply ? "*" : "/"
      advance()
      expression = .binary(operation, expression, try parsePower())
    }
    return expression
  }

  private mutating func parsePower() throws -> FormulaExpression {
    var expression = try parseUnary()
    if current == .power {
      advance()
      expression = .binary("^", expression, try parsePower())
    }
    return expression
  }

  private mutating func parseUnary() throws -> FormulaExpression {
    if current == .plus {
      advance()
      return try parseUnary()
    }
    if current == .minus {
      advance()
      return .unaryMinus(try parseUnary())
    }
    return try parsePostfix()
  }

  private mutating func parsePostfix() throws -> FormulaExpression {
    var expression = try parsePrimary()
    while current == .percent {
      advance()
      expression = .percent(expression)
    }
    return expression
  }

  private mutating func parsePrimary() throws -> FormulaExpression {
    switch current {
    case .number(let value):
      advance()
      return .number(value)
    case .string(let value):
      advance()
      return .text(value)
    case .identifier(let identifier):
      advance()
      if current == .leftParenthesis {
        return try parseFunction(named: identifier)
      }
      if let address = CellAddress(identifier) {
        if current == .colon {
          advance()
          guard case .identifier(let endIdentifier) = current,
            let endAddress = CellAddress(endIdentifier)
          else {
            throw SpreadsheetFormulaError.invalidReference
          }
          advance()
          return .range(CellRange(start: address, end: endAddress))
        }
        return .reference(address)
      }
      return .constant(identifier.uppercased())
    case .leftParenthesis:
      advance()
      let expression = try parseAddition()
      guard current == .rightParenthesis else {
        throw SpreadsheetFormulaError.parse
      }
      advance()
      return expression
    default:
      throw SpreadsheetFormulaError.parse
    }
  }

  private mutating func parseFunction(named name: String) throws -> FormulaExpression {
    advance()
    var arguments: [FormulaExpression] = []
    if current != .rightParenthesis {
      while true {
        arguments.append(try parseAddition())
        if current == .separator {
          advance()
          continue
        }
        break
      }
    }
    guard current == .rightParenthesis else {
      throw SpreadsheetFormulaError.parse
    }
    advance()
    return .function(name.uppercased(), arguments)
  }

  private var current: FormulaToken {
    index < tokens.count ? tokens[index] : .end
  }

  private mutating func advance() {
    index += 1
  }
}

struct FlexibleNumberParser {
  static func parse(_ input: String, locale: Locale = .current) -> Double? {
    var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    value = value
      .replacingOccurrences(of: "\u{00A0}", with: "")
      .replacingOccurrences(of: "\u{202F}", with: "")
      .replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "'", with: "")

    let commas = value.indices.filter { value[$0] == "," }
    let dots = value.indices.filter { value[$0] == "." }
    if let lastComma = commas.last, let lastDot = dots.last {
      let commaIsDecimal = lastComma > lastDot
      let grouping = commaIsDecimal ? "." : ","
      let decimal = commaIsDecimal ? "," : "."
      return Double(
        value
          .replacingOccurrences(of: grouping, with: "")
          .replacingOccurrences(of: decimal, with: ".")
      )
    }

    if !commas.isEmpty {
      return parseSingleSeparator(
        value,
        separator: ",",
        occurrences: commas.count,
        locale: locale
      )
    }
    if !dots.isEmpty {
      return parseSingleSeparator(
        value,
        separator: ".",
        occurrences: dots.count,
        locale: locale
      )
    }
    return Double(value)
  }

  private static func parseSingleSeparator(
    _ value: String,
    separator: Character,
    occurrences: Int,
    locale: Locale
  ) -> Double? {
    let parts = value.split(separator: separator, omittingEmptySubsequences: false)
    guard parts.count == occurrences + 1 else { return nil }

    if occurrences > 1 {
      let looksGrouped = parts.dropFirst().allSatisfy { part in
        part.count == 3 && part.allSatisfy(\.isNumber)
      }
      if looksGrouped {
        return Double(value.replacingOccurrences(of: String(separator), with: ""))
      }
      guard occurrences == 1 else { return nil }
    }

    guard let fractional = parts.last else { return nil }
    let localeDecimal = locale.decimalSeparator?.first
    let isAmbiguousThousandsGroup = fractional.count == 3
      && fractional.allSatisfy(\.isNumber)
      && localeDecimal != separator
    if isAmbiguousThousandsGroup {
      return Double(value.replacingOccurrences(of: String(separator), with: ""))
    }
    return Double(value.replacingOccurrences(of: String(separator), with: "."))
  }
}

final class SpreadsheetFormulaEngine {
  private var parsedCache: [String: Result<ParsedFormula, SpreadsheetFormulaError>] = [:]
  private var valueCache: [CellAddress: SpreadsheetValue] = [:]

  func invalidate() {
    valueCache.removeAll(keepingCapacity: true)
  }

  func value(
    at address: CellAddress,
    cells: [CellAddress: CellRecord]
  ) -> SpreadsheetValue {
    var visiting = Set<CellAddress>()
    return evaluateCell(address, cells: cells, visiting: &visiting)
  }

  func referenceRanges(in rawInput: String) -> [CellRange] {
    guard rawInput.trimmingCharacters(in: .whitespaces).hasPrefix("=") else {
      return []
    }
    switch parsedFormula(rawInput) {
    case .success(let formula): return formula.references
    case .failure: return []
    }
  }

  func literalValue(for record: CellRecord) -> SpreadsheetValue {
    let trimmed = record.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .blank }

    if trimmed.hasSuffix("%"),
      let number = FlexibleNumberParser.parse(String(trimmed.dropLast()))
    {
      return .number(number / 100)
    }
    if let time = SpreadsheetTime.parse(trimmed) {
      return .time(time)
    }
    if let number = FlexibleNumberParser.parse(trimmed) {
      return .number(number)
    }
    if let date = Self.parseDate(trimmed) {
      return .date(date)
    }
    switch trimmed.uppercased() {
    case "TRUE": return .boolean(true)
    case "FALSE": return .boolean(false)
    default: return .text(record.rawInput)
    }
  }

  private func evaluateCell(
    _ address: CellAddress,
    cells: [CellAddress: CellRecord],
    visiting: inout Set<CellAddress>
  ) -> SpreadsheetValue {
    if let cached = valueCache[address] { return cached }
    guard let record = cells[address] else { return .blank }
    let trimmed = record.rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("=") else {
      let value = literalValue(for: record)
      valueCache[address] = value
      return value
    }
    guard !visiting.contains(address) else { return .error(.cycle) }

    visiting.insert(address)
    let value: SpreadsheetValue
    switch parsedFormula(record.rawInput) {
    case .success(let parsed):
      value = evaluate(parsed.expression, cells: cells, visiting: &visiting)
    case .failure(let error):
      value = .error(error)
    }
    visiting.remove(address)
    valueCache[address] = value
    return value
  }

  private func evaluate(
    _ expression: FormulaExpression,
    cells: [CellAddress: CellRecord],
    visiting: inout Set<CellAddress>
  ) -> SpreadsheetValue {
    switch expression {
    case .number(let value):
      return .number(value)
    case .text(let value):
      return .text(value)
    case .reference(let address):
      return evaluateCell(address, cells: cells, visiting: &visiting)
    case .range:
      return .error(.invalidValue)
    case .constant(let name):
      switch name {
      case "PI": return .number(Double.pi)
      case "E": return .number(exp(1))
      default: return .error(.unknownName)
      }
    case .unaryMinus(let child):
      return numericResult(
        evaluate(child, cells: cells, visiting: &visiting)
      ) { -$0 }
    case .percent(let child):
      return numericResult(
        evaluate(child, cells: cells, visiting: &visiting)
      ) { $0 / 100 }
    case .binary(let operation, let left, let right):
      let leftValue = evaluate(left, cells: cells, visiting: &visiting)
      let rightValue = evaluate(right, cells: cells, visiting: &visiting)
      if case .error(let error) = leftValue { return .error(error) }
      if case .error(let error) = rightValue { return .error(error) }
      guard let lhs = coerceNumber(leftValue), let rhs = coerceNumber(rightValue) else {
        return .error(.invalidValue)
      }
      switch operation {
      case "+": return .number(lhs + rhs)
      case "-": return .number(lhs - rhs)
      case "*": return .number(lhs * rhs)
      case "/": return rhs == 0 ? .error(.divisionByZero) : .number(lhs / rhs)
      case "^": return .number(pow(lhs, rhs))
      default: return .error(.parse)
      }
    case .function(let name, let arguments):
      return evaluateFunction(name, arguments: arguments, cells: cells, visiting: &visiting)
    }
  }

  private func evaluateFunction(
    _ name: String,
    arguments: [FormulaExpression],
    cells: [CellAddress: CellRecord],
    visiting: inout Set<CellAddress>
  ) -> SpreadsheetValue {
    var values: [SpreadsheetValue] = []
    for argument in arguments {
      if case .range(let range) = argument {
        let addresses = range.addresses()
        guard !addresses.isEmpty else { return .error(.invalidValue) }
        values.append(contentsOf: addresses.map {
          evaluateCell($0, cells: cells, visiting: &visiting)
        })
      } else {
        values.append(evaluate(argument, cells: cells, visiting: &visiting))
      }
    }
    if let error = values.compactMap({ value -> SpreadsheetFormulaError? in
      if case .error(let error) = value { return error }
      return nil
    }).first {
      return .error(error)
    }

    let numbers = values.compactMap(\.numericValue)
    switch name {
    case "SUM":
      return .number(numbers.reduce(0, +))
    case "AVG", "AVERAGE":
      guard !numbers.isEmpty else { return .error(.divisionByZero) }
      return .number(numbers.reduce(0, +) / Double(numbers.count))
    case "MIN":
      return .number(numbers.min() ?? 0)
    case "MAX":
      return .number(numbers.max() ?? 0)
    case "COUNT":
      return .number(Double(numbers.count))
    case "COUNTA":
      return .number(Double(values.filter { !$0.isBlank }.count))
    case "ABS":
      guard numbers.count == 1 else { return .error(.invalidValue) }
      return .number(abs(numbers[0]))
    case "ROUND":
      guard numbers.count == 1 || numbers.count == 2 else {
        return .error(.invalidValue)
      }
      let digits = numbers.count == 2 ? Int(numbers[1]) : 0
      let factor = pow(10, Double(digits))
      return .number((numbers[0] * factor).rounded() / factor)
    default:
      return .error(.unknownName)
    }
  }

  private func parsedFormula(
    _ rawInput: String
  ) -> Result<ParsedFormula, SpreadsheetFormulaError> {
    if let cached = parsedCache[rawInput] { return cached }
    let source = String(
      rawInput.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst()
    )
    let result: Result<ParsedFormula, SpreadsheetFormulaError>
    if Self.containsUnquotedSemicolon(source) {
      result = parse(source, dialect: .french)
    } else {
      let english = parse(source, dialect: .english)
      if case .failure = english, source.contains(",") {
        result = parse(source, dialect: .french)
      } else {
        result = english
      }
    }
    parsedCache[rawInput] = result
    return result
  }

  private func parse(
    _ source: String,
    dialect: FormulaDialect
  ) -> Result<ParsedFormula, SpreadsheetFormulaError> {
    do {
      var lexer = FormulaLexer(source, dialect: dialect)
      var parser = FormulaParser(tokens: try lexer.tokenize())
      let expression = try parser.parse()
      var references: [CellRange] = []
      collectReferences(expression, into: &references)
      return .success(ParsedFormula(expression: expression, references: references))
    } catch let error as SpreadsheetFormulaError {
      return .failure(error)
    } catch {
      return .failure(.parse)
    }
  }

  private func collectReferences(
    _ expression: FormulaExpression,
    into references: inout [CellRange]
  ) {
    switch expression {
    case .reference(let address):
      references.append(CellRange(address))
    case .range(let range):
      references.append(range)
    case .unaryMinus(let child), .percent(let child):
      collectReferences(child, into: &references)
    case .binary(_, let left, let right):
      collectReferences(left, into: &references)
      collectReferences(right, into: &references)
    case .function(_, let arguments):
      for argument in arguments {
        collectReferences(argument, into: &references)
      }
    default:
      break
    }
  }

  private func numericResult(
    _ value: SpreadsheetValue,
    transform: (Double) -> Double
  ) -> SpreadsheetValue {
    if case .error(let error) = value { return .error(error) }
    guard let number = coerceNumber(value) else { return .error(.invalidValue) }
    return .number(transform(number))
  }

  private func coerceNumber(_ value: SpreadsheetValue) -> Double? {
    switch value {
    case .blank: return 0
    case .number(let number): return number
    case .time(let fractionOfDay): return fractionOfDay
    case .boolean(let boolean): return boolean ? 1 : 0
    case .text(let text): return FlexibleNumberParser.parse(text)
    default: return nil
    }
  }

  private static func containsUnquotedSemicolon(_ value: String) -> Bool {
    let characters = Array(value)
    var inQuotes = false
    var index = 0
    while index < characters.count {
      let character = characters[index]
      if character == "\"" {
        if inQuotes, index + 1 < characters.count, characters[index + 1] == "\"" {
          index += 2
          continue
        }
        inQuotes.toggle()
      } else if character == ";" && !inQuotes {
        return true
      }
      index += 1
    }
    return false
  }

  private static func parseDate(_ value: String) -> Date? {
    let isoFormatter = ISO8601DateFormatter()
    if let date = isoFormatter.date(from: value) { return date }

    let formats = ["yyyy-MM-dd", "dd/MM/yyyy", "MM/dd/yyyy", "dd-MM-yyyy"]
    for format in formats {
      let formatter = DateFormatter()
      formatter.locale = .current
      formatter.calendar = .current
      formatter.timeZone = .current
      formatter.dateFormat = format
      formatter.isLenient = false
      if let date = formatter.date(from: value) { return date }
    }
    return nil
  }
}

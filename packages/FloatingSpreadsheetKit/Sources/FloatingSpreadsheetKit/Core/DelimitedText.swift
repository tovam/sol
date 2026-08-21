import Foundation

enum DelimitedTextSeparator: String, Codable, CaseIterable {
  case tab = "\t"
  case comma = ","
  case semicolon = ";"

  var character: Character { Character(rawValue) }

  var displayName: String {
    switch self {
    case .tab: return "Tab"
    case .comma: return "Comma"
    case .semicolon: return "Semicolon"
    }
  }
}

enum DelimitedTextEncoding: String, Codable, CaseIterable {
  case utf8
  case utf16
  case windows1252
  case isoLatin1

  var displayName: String {
    switch self {
    case .utf8: return "UTF-8"
    case .utf16: return "UTF-16"
    case .windows1252: return "Windows-1252"
    case .isoLatin1: return "ISO-8859-1"
    }
  }

  var foundationEncoding: String.Encoding {
    switch self {
    case .utf8: return .utf8
    case .utf16: return .utf16
    case .windows1252: return .windowsCP1252
    case .isoLatin1: return .isoLatin1
    }
  }
}

enum DelimitedTextEscapeMode: String, Codable, CaseIterable {
  case doubledQuote
  case backslash
}

struct DelimitedTextOptions: Codable, Equatable {
  var separator: DelimitedTextSeparator
  var firstRowIsHeader: Bool
  var encoding: DelimitedTextEncoding
  var quote: Character
  var escapeMode: DelimitedTextEscapeMode

  init(
    separator: DelimitedTextSeparator,
    firstRowIsHeader: Bool = false,
    encoding: DelimitedTextEncoding = .utf8,
    quote: Character = "\"",
    escapeMode: DelimitedTextEscapeMode = .doubledQuote
  ) {
    self.separator = separator
    self.firstRowIsHeader = firstRowIsHeader
    self.encoding = encoding
    self.quote = quote
    self.escapeMode = escapeMode
  }

  private enum CodingKeys: String, CodingKey {
    case separator
    case firstRowIsHeader
    case encoding
    case quote
    case escapeMode
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    separator = try values.decode(DelimitedTextSeparator.self, forKey: .separator)
    firstRowIsHeader = try values.decode(Bool.self, forKey: .firstRowIsHeader)
    encoding = try values.decode(DelimitedTextEncoding.self, forKey: .encoding)
    let quoteString = try values.decode(String.self, forKey: .quote)
    quote = quoteString.first ?? "\""
    escapeMode = try values.decode(DelimitedTextEscapeMode.self, forKey: .escapeMode)
  }

  func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(separator, forKey: .separator)
    try values.encode(firstRowIsHeader, forKey: .firstRowIsHeader)
    try values.encode(encoding, forKey: .encoding)
    try values.encode(String(quote), forKey: .quote)
    try values.encode(escapeMode, forKey: .escapeMode)
  }
}

struct DelimitedTextCandidate: Equatable {
  var options: DelimitedTextOptions
  var rows: [[String]]
  var score: Int
}

enum DelimitedTextDetection {
  case direct(DelimitedTextCandidate)
  case ambiguous([DelimitedTextCandidate])
}

enum DelimitedTextError: LocalizedError {
  case invalidEncoding
  case unterminatedQuote

  var errorDescription: String? {
    switch self {
    case .invalidEncoding:
      return "The selected text encoding could not decode this file."
    case .unterminatedQuote:
      return "A quoted field is not terminated."
    }
  }
}

struct DelimitedTextParser {
  func detect(_ text: String) throws -> DelimitedTextDetection {
    if text.contains("\t") {
      let options = DelimitedTextOptions(
        separator: .tab,
        firstRowIsHeader: inferHeader(in: try parse(text, options: .init(separator: .tab)))
      )
      return .direct(
        DelimitedTextCandidate(
          options: options,
          rows: try parse(text, options: options),
          score: Int.max
        )
      )
    }

    var candidates: [DelimitedTextCandidate] = []
    for separator in [DelimitedTextSeparator.comma, .semicolon] {
      let baseOptions = DelimitedTextOptions(separator: separator)
      guard let rows = try? parse(text, options: baseOptions) else { continue }
      let widths = rows.filter { row in
        !row.allSatisfy { $0.isEmpty }
      }.map { $0.count }
      guard let widest = widths.max(), widest > 1 else { continue }
      let mostCommonWidth = Dictionary(grouping: widths, by: { $0 })
        .max { $0.value.count < $1.value.count }?.key ?? widest
      let consistentRows = widths.filter { $0 == mostCommonWidth }.count
      let score = consistentRows * 100 + mostCommonWidth * 10 - (widths.count - consistentRows) * 25
      var options = baseOptions
      options.firstRowIsHeader = inferHeader(in: rows)
      candidates.append(
        DelimitedTextCandidate(options: options, rows: rows, score: score)
      )
    }

    candidates.sort { $0.score > $1.score }

    // A single French-formatted number is valid spreadsheet content, not an
    // obvious one-row CSV document. Keep both interpretations available so
    // the import UI can ask instead of silently splitting `1,2` in half.
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.contains("\n"), !trimmed.contains("\r"), !trimmed.contains("\t"),
      FlexibleNumberParser.parse(trimmed) != nil,
      candidates.contains(where: { $0.options.separator == .comma })
    {
      let singleCellOptions = DelimitedTextOptions(separator: .tab)
      candidates.append(
        DelimitedTextCandidate(
          options: singleCellOptions,
          rows: [[text]],
          score: candidates.first?.score ?? 0
        )
      )
      return .ambiguous(candidates)
    }

    if candidates.isEmpty {
      let separator: DelimitedTextSeparator = text.contains(";") ? .semicolon : .comma
      let options = DelimitedTextOptions(separator: separator)
      return .direct(
        DelimitedTextCandidate(
          options: options,
          rows: try parse(text, options: options),
          score: 0
        )
      )
    }
    if candidates.count == 1 || candidates[0].score >= candidates[1].score + 100 {
      return .direct(candidates[0])
    }
    return .ambiguous(candidates)
  }

  func decode(
    _ data: Data,
    encoding: DelimitedTextEncoding? = nil
  ) throws -> (text: String, encoding: DelimitedTextEncoding) {
    if let encoding {
      guard let text = String(data: data, encoding: encoding.foundationEncoding) else {
        throw DelimitedTextError.invalidEncoding
      }
      return (text, encoding)
    }

    let hasUTF16ByteOrderMark = data.starts(with: [0xFF, 0xFE])
      || data.starts(with: [0xFE, 0xFF])
    let candidates: [DelimitedTextEncoding] = hasUTF16ByteOrderMark
      ? [.utf16, .utf8, .windows1252, .isoLatin1]
      : [.utf8, .windows1252, .isoLatin1]
    for candidate in candidates {
      if let text = String(data: data, encoding: candidate.foundationEncoding) {
        return (text, candidate)
      }
    }
    throw DelimitedTextError.invalidEncoding
  }

  func parse(
    _ text: String,
    options: DelimitedTextOptions
  ) throws -> [[String]] {
    let characters = Array(text)
    var rows: [[String]] = []
    var row: [String] = []
    var field = ""
    var inQuotes = false
    var index = 0

    func finishField() {
      row.append(field)
      field = ""
    }

    func finishRow() {
      finishField()
      rows.append(row)
      row = []
    }

    while index < characters.count {
      let character = characters[index]
      if inQuotes {
        if options.escapeMode == .backslash,
          character == "\\",
          index + 1 < characters.count,
          characters[index + 1] == options.quote
        {
          field.append(options.quote)
          index += 2
          continue
        }
        if character == options.quote {
          if options.escapeMode == .doubledQuote,
            index + 1 < characters.count,
            characters[index + 1] == options.quote
          {
            field.append(options.quote)
            index += 2
            continue
          }
          inQuotes = false
          index += 1
          continue
        }
        field.append(character)
        index += 1
        continue
      }

      if character == options.quote && field.isEmpty {
        inQuotes = true
        index += 1
      } else if character == options.separator.character {
        finishField()
        index += 1
      } else if character == "\n" || character == "\r" {
        finishRow()
        if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
          index += 2
        } else {
          index += 1
        }
      } else {
        field.append(character)
        index += 1
      }
    }

    guard !inQuotes else { throw DelimitedTextError.unterminatedQuote }
    if !field.isEmpty || !row.isEmpty || rows.isEmpty {
      finishRow()
    }
    return rows
  }

  private func inferHeader(in rows: [[String]]) -> Bool {
    guard rows.count >= 2, !rows[0].isEmpty else { return false }
    let first = rows[0]
    let sample = rows.dropFirst().prefix(8)
    let firstIsMostlyText = first.filter {
      FlexibleNumberParser.parse($0) == nil && !$0.trimmingCharacters(in: .whitespaces).isEmpty
    }.count * 2 >= first.count
    let numericColumnsBelow = first.indices.filter { column in
      sample.contains { row in
        column < row.count && FlexibleNumberParser.parse(row[column]) != nil
      }
    }.count
    return firstIsMostlyText && numericColumnsBelow > 0
  }
}

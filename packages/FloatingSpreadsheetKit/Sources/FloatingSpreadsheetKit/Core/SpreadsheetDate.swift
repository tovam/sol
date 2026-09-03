import Foundation

struct SpreadsheetDateComponents: Equatable {
  var year: Int?
  var month: Int
  var day: Int
  var hour: Int
  var minute: Int
  var second: Int
  var includesTime: Bool
}

enum SpreadsheetDate {
  private static let isoDate = try! NSRegularExpression(
    pattern: #"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](.+))?$"#,
    options: [.caseInsensitive]
  )
  private static let slashDate = try! NSRegularExpression(
    pattern: #"^(\d{1,2})/(\d{1,2})(?:/(\d{4}))?(?:\s+(.+))?$"#,
    options: [.caseInsensitive]
  )
  private static let englishDashDate = try! NSRegularExpression(
    pattern: #"^(\d{1,2})-(\d{1,2})(?:-(\d{4}))?(?:\s+(.+))?$"#,
    options: [.caseInsensitive]
  )
  private static let colonTime = try! NSRegularExpression(
    pattern: #"^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?$"#,
    options: [.caseInsensitive]
  )
  private static let hourMarkerTime = try! NSRegularExpression(
    pattern: #"^(\d{1,2})h(?:(\d{2}))?(?::(\d{2}))?$"#,
    options: [.caseInsensitive]
  )
  private static let meridiemTime = try! NSRegularExpression(
    pattern: #"^(\d{1,2})\s*(am|pm)$"#,
    options: [.caseInsensitive]
  )

  static func components(
    _ input: String,
    displayLocale: SpreadsheetDisplayLocale = .french
  ) -> SpreadsheetDateComponents? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }

    if let captures = captures(isoDate, in: value),
      let year = integer(captures, 1),
      let month = integer(captures, 2),
      let day = integer(captures, 3),
      let time = parsedTime(captures[safe: 4] ?? nil)
    {
      return SpreadsheetDateComponents(
        year: year,
        month: month,
        day: day,
        hour: time.hour,
        minute: time.minute,
        second: time.second,
        includesTime: time.wasProvided
      )
    }

    if let captures = captures(slashDate, in: value),
      let first = integer(captures, 1),
      let second = integer(captures, 2),
      let time = parsedTime(captures[safe: 4] ?? nil)
    {
      let day = displayLocale == .french ? first : second
      let month = displayLocale == .french ? second : first
      return SpreadsheetDateComponents(
        year: integer(captures, 3),
        month: month,
        day: day,
        hour: time.hour,
        minute: time.minute,
        second: time.second,
        includesTime: time.wasProvided
      )
    }

    // A date beginning with a year is ISO. Without a year, a dash is an
    // English month-day separator regardless of the sheet display locale.
    if let captures = captures(englishDashDate, in: value),
      let month = integer(captures, 1),
      let day = integer(captures, 2),
      let time = parsedTime(captures[safe: 4] ?? nil)
    {
      return SpreadsheetDateComponents(
        year: integer(captures, 3),
        month: month,
        day: day,
        hour: time.hour,
        minute: time.minute,
        second: time.second,
        includesTime: time.wasProvided
      )
    }

    return nil
  }

  static func parse(
    _ input: String,
    displayLocale: SpreadsheetDisplayLocale = .french,
    defaultYear: Int? = nil,
    timeZone: TimeZone = .current
  ) -> Date? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.contains("T"), let internetDate = parseInternetDate(value) {
      return internetDate
    }
    guard let parsed = components(value, displayLocale: displayLocale) else {
      return nil
    }
    let year = parsed.year
      ?? defaultYear
      ?? Calendar(identifier: .gregorian).dateComponents(
        in: timeZone,
        from: Date()
      ).year
    guard let year else { return nil }
    return date(from: parsed, year: year, timeZone: timeZone)
  }

  static func date(
    from parsed: SpreadsheetDateComponents,
    year: Int,
    timeZone: TimeZone
  ) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = timeZone
    components.year = year
    components.month = parsed.month
    components.day = parsed.day
    components.hour = parsed.hour
    components.minute = parsed.minute
    components.second = parsed.second
    guard let result = calendar.date(from: components) else { return nil }
    let verified = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: result
    )
    guard verified.year == year,
      verified.month == parsed.month,
      verified.day == parsed.day,
      verified.hour == parsed.hour,
      verified.minute == parsed.minute,
      verified.second == parsed.second
    else {
      return nil
    }
    return result
  }

  static func format(
    _ date: Date,
    locale: Locale = .current,
    timeZone: TimeZone = .current,
    includesTime: Bool? = nil
  ) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateStyle = .short
    let calendarComponents = formatter.calendar.dateComponents(
      in: timeZone,
      from: date
    )
    let hasClockValue = calendarComponents.hour != 0
      || calendarComponents.minute != 0
      || calendarComponents.second != 0
    formatter.timeStyle = (includesTime ?? hasClockValue) ? .medium : .none
    return formatter.string(from: date)
  }

  static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = timeZone
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
  }

  static func isTimestamp(_ input: String) -> Bool {
    input.range(
      of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#,
      options: .regularExpression
    ) != nil
  }

  private static func parsedTime(
    _ rawValue: String?
  ) -> (hour: Int, minute: Int, second: Int, wasProvided: Bool)? {
    guard let rawValue else { return (0, 0, 0, false) }
    let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return (0, 0, 0, false) }

    if let captures = captures(colonTime, in: value),
      let rawHour = integer(captures, 1),
      let minute = integer(captures, 2)
    {
      return validatedTime(
        hour: rawHour,
        minute: minute,
        second: integer(captures, 3) ?? 0,
        meridiem: captures[safe: 4] ?? nil
      )
    }
    if let captures = captures(hourMarkerTime, in: value),
      let hour = integer(captures, 1)
    {
      return validatedTime(
        hour: hour,
        minute: integer(captures, 2) ?? 0,
        second: integer(captures, 3) ?? 0,
        meridiem: nil
      )
    }
    if let captures = captures(meridiemTime, in: value),
      let hour = integer(captures, 1)
    {
      return validatedTime(
        hour: hour,
        minute: 0,
        second: 0,
        meridiem: captures[safe: 2] ?? nil
      )
    }
    return nil
  }

  private static func validatedTime(
    hour rawHour: Int,
    minute: Int,
    second: Int,
    meridiem: String?
  ) -> (hour: Int, minute: Int, second: Int, wasProvided: Bool)? {
    guard (0...59).contains(minute), (0...59).contains(second) else {
      return nil
    }
    if let meridiem = meridiem?.lowercased() {
      guard (1...12).contains(rawHour) else { return nil }
      let hour = meridiem == "am"
        ? rawHour % 12
        : (rawHour % 12) + 12
      return (hour, minute, second, true)
    }
    guard (0...23).contains(rawHour) else { return nil }
    return (rawHour, minute, second, true)
  }

  private static func parseInternetDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
  }

  private static func captures(
    _ expression: NSRegularExpression,
    in value: String
  ) -> [String?]? {
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    guard let match = expression.firstMatch(in: value, range: range),
      match.range == range
    else {
      return nil
    }
    return (0..<match.numberOfRanges).map { index in
      let matchRange = match.range(at: index)
      guard matchRange.location != NSNotFound,
        let range = Range(matchRange, in: value)
      else {
        return nil
      }
      return String(value[range])
    }
  }

  private static func integer(_ captures: [String?], _ index: Int) -> Int? {
    guard let value = captures[safe: index] ?? nil else { return nil }
    return Int(value)
  }
}

private extension Collection {
  subscript(safe index: Index) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

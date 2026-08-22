import Foundation

struct SpreadsheetHistogramSample: Equatable {
  var value: Double
  var isDuration: Bool
}

enum SpreadsheetHistogramMethod: String, Equatable {
  case freedmanDiaconis = "Freedman–Diaconis"
  case scott = "Scott"
  case sturges = "Sturges"
  case singleValue = "Single value"
}

struct SpreadsheetHistogramBin: Equatable, Identifiable {
  var index: Int
  var lowerBound: Double
  var upperBound: Double
  var count: Int
  var percentage: Double
  var cumulativePercentage: Double
  var minimum: Double?
  var maximum: Double?
  var mean: Double?
  var median: Double?
  var standardDeviation: Double?
  var includesUpperBound: Bool

  var id: Int { index }
  var midpoint: Double { lowerBound + (upperBound - lowerBound) / 2 }
}

struct SpreadsheetHistogramResult: Equatable {
  var bins: [SpreadsheetHistogramBin]
  var sampleCount: Int
  var binWidth: Double
  var method: SpreadsheetHistogramMethod
  var isDuration: Bool
  var minimum: Double
  var maximum: Double
  var mean: Double
  var median: Double
  var standardDeviation: Double
}

enum SpreadsheetHistogramCalculator {
  private static let maximumBinCount = 80

  static func calculate(
    samples rawSamples: [SpreadsheetHistogramSample]
  ) -> SpreadsheetHistogramResult? {
    let samples = rawSamples.filter { $0.value.isFinite }.sorted { $0.value < $1.value }
    guard !samples.isEmpty else { return nil }

    let values = samples.map(\.value)
    let isDuration = samples.allSatisfy(\.isDuration)
    let minimum = values[0]
    let maximum = values[values.count - 1]
    let mean = arithmeticMean(values)
    let median = quantile(values, probability: 0.5)
    let standardDeviation = populationStandardDeviation(values, mean: mean)

    let layout = binLayout(
      values: values,
      minimum: minimum,
      maximum: maximum,
      standardDeviation: standardDeviation,
      isDuration: isDuration
    )
    let buckets = bucket(
      values,
      lowerBound: layout.lowerBound,
      width: layout.width,
      count: layout.count
    )
    var cumulativeCount = 0
    let bins = buckets.enumerated().map { index, valuesInBin in
      cumulativeCount += valuesInBin.count
      let binMean = valuesInBin.isEmpty ? nil : arithmeticMean(valuesInBin)
      return SpreadsheetHistogramBin(
        index: index,
        lowerBound: layout.lowerBound + Double(index) * layout.width,
        upperBound: layout.lowerBound + Double(index + 1) * layout.width,
        count: valuesInBin.count,
        percentage: Double(valuesInBin.count) / Double(values.count),
        cumulativePercentage: Double(cumulativeCount) / Double(values.count),
        minimum: valuesInBin.first,
        maximum: valuesInBin.last,
        mean: binMean,
        median: valuesInBin.isEmpty ? nil : quantile(valuesInBin, probability: 0.5),
        standardDeviation: binMean.map {
          populationStandardDeviation(valuesInBin, mean: $0)
        },
        includesUpperBound: index == buckets.count - 1
      )
    }

    return SpreadsheetHistogramResult(
      bins: bins,
      sampleCount: values.count,
      binWidth: layout.width,
      method: layout.method,
      isDuration: isDuration,
      minimum: minimum,
      maximum: maximum,
      mean: mean,
      median: median,
      standardDeviation: standardDeviation
    )
  }

  private static func binLayout(
    values: [Double],
    minimum: Double,
    maximum: Double,
    standardDeviation: Double,
    isDuration: Bool
  ) -> (lowerBound: Double, width: Double, count: Int, method: SpreadsheetHistogramMethod) {
    let range = maximum - minimum
    guard values.count > 1, range > 0 else {
      let fallback = isDuration ? 60.0 / 86_400.0 : max(abs(minimum) * 0.1, 1)
      let width = niceWidth(fallback, isDuration: isDuration)
      return (minimum - width / 2, width, 1, .singleValue)
    }

    let cubeRootCount = pow(Double(values.count), 1.0 / 3.0)
    let interquartileRange = quantile(values, probability: 0.75)
      - quantile(values, probability: 0.25)
    let fdWidth = 2 * interquartileRange / cubeRootCount

    let rawWidth: Double
    let method: SpreadsheetHistogramMethod
    if fdWidth.isFinite, fdWidth > 0 {
      rawWidth = fdWidth
      method = .freedmanDiaconis
    } else {
      let scottWidth = 3.5 * standardDeviation / cubeRootCount
      if scottWidth.isFinite, scottWidth > 0 {
        rawWidth = scottWidth
        method = .scott
      } else {
        let sturgesCount = max(1, Int(ceil(log2(Double(values.count)) + 1)))
        rawWidth = range / Double(sturgesCount)
        method = .sturges
      }
    }

    var width = niceWidth(rawWidth, isDuration: isDuration)
    var lowerBound = floor(minimum / width) * width
    var count = max(1, Int(ceil((maximum - lowerBound) / width)))
    if count > maximumBinCount {
      width = niceWidth(range / Double(maximumBinCount), isDuration: isDuration)
      lowerBound = floor(minimum / width) * width
      count = max(1, Int(ceil((maximum - lowerBound) / width)))
    }
    if count > maximumBinCount {
      count = maximumBinCount
      width = (maximum - lowerBound) / Double(count)
    }
    return (lowerBound, width, count, method)
  }

  private static func bucket(
    _ values: [Double],
    lowerBound: Double,
    width: Double,
    count: Int
  ) -> [[Double]] {
    var buckets = Array(repeating: [Double](), count: count)
    for value in values {
      let rawIndex = Int(floor((value - lowerBound) / width))
      let index = min(count - 1, max(0, rawIndex))
      buckets[index].append(value)
    }
    return buckets
  }

  private static func niceWidth(_ rawWidth: Double, isDuration: Bool) -> Double {
    guard rawWidth.isFinite, rawWidth > 0 else { return 1 }
    if isDuration {
      let seconds = rawWidth * 86_400
      let candidates: [Double] = [
        1, 2, 5, 10, 15, 30,
        60, 2 * 60, 5 * 60, 10 * 60, 15 * 60, 30 * 60,
        60 * 60, 2 * 60 * 60, 3 * 60 * 60, 4 * 60 * 60,
        6 * 60 * 60, 12 * 60 * 60, 24 * 60 * 60,
      ]
      if let candidate = candidates.first(where: { $0 >= seconds }) {
        return candidate / 86_400
      }
      return niceNumericWidth(seconds / 86_400) // Whole days.
    }
    return niceNumericWidth(rawWidth)
  }

  private static func niceNumericWidth(_ rawWidth: Double) -> Double {
    let exponent = floor(log10(rawWidth))
    let magnitude = pow(10, exponent)
    let normalized = rawWidth / magnitude
    let niceNormalized: Double
    switch normalized {
    case ...1: niceNormalized = 1
    case ...2: niceNormalized = 2
    case ...2.5: niceNormalized = 2.5
    case ...5: niceNormalized = 5
    default: niceNormalized = 10
    }
    return niceNormalized * magnitude
  }

  private static func arithmeticMean(_ values: [Double]) -> Double {
    values.reduce(0, +) / Double(values.count)
  }

  private static func populationStandardDeviation(
    _ values: [Double],
    mean: Double
  ) -> Double {
    guard values.count > 1 else { return 0 }
    let variance = values.reduce(0) { partial, value in
      let delta = value - mean
      return partial + delta * delta
    } / Double(values.count)
    return sqrt(variance)
  }

  private static func quantile(_ sortedValues: [Double], probability: Double) -> Double {
    guard sortedValues.count > 1 else { return sortedValues[0] }
    let position = min(1, max(0, probability)) * Double(sortedValues.count - 1)
    let lowerIndex = Int(floor(position))
    let upperIndex = Int(ceil(position))
    guard lowerIndex != upperIndex else { return sortedValues[lowerIndex] }
    let weight = position - Double(lowerIndex)
    return sortedValues[lowerIndex] * (1 - weight) + sortedValues[upperIndex] * weight
  }
}

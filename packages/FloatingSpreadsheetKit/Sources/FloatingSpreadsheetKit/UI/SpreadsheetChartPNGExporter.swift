import AppKit

enum SpreadsheetChartPNGExporter {
  static func pngData(for view: NSView) -> Data? {
    view.layoutSubtreeIfNeeded()
    let bounds = view.bounds.integral
    guard bounds.width > 0, bounds.height > 0,
      let bitmap = view.bitmapImageRepForCachingDisplay(in: bounds)
    else {
      return nil
    }

    view.cacheDisplay(in: bounds, to: bitmap)
    bitmap.size = bounds.size
    return bitmap.representation(using: .png, properties: [:])
  }
}

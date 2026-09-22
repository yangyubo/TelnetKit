import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// The monospaced cell the terminal area uses, so a window size in points becomes a NAWS
/// column and row count.
///
/// The cell is measured once from the platform's monospaced system font at the size the
/// terminal view draws, which keeps the reported columns and rows close to what the view
/// shows instead of assuming a fixed cell.
enum DemoWindowMetrics {
    /// The point size the terminal view draws with; this is the size the cell is measured at.
    static let terminalFontSize: CGFloat = 12

    /// The size of one character cell.
    static let cell: CGSize = measureCell()

    static func columns(forWidth width: CGFloat) -> Int {
        max(1, Int(width / cell.width))
    }

    static func rows(forHeight height: CGFloat) -> Int {
        max(1, Int(height / cell.height))
    }

    private static func measureCell() -> CGSize {
        #if canImport(AppKit)
        let font = NSFont.monospacedSystemFont(ofSize: terminalFontSize, weight: .regular)
        #elseif canImport(UIKit)
        let font = UIFont.monospacedSystemFont(ofSize: terminalFontSize, weight: .regular)
        #endif
        let size = ("0" as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width), height: ceil(size.height))
    }
}

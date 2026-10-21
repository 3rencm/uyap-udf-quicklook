import CoreGraphics
import Foundation

// Ekran üzerindeki pencereleri listeler.
// Çıktı: id<TAB>owner<TAB>layer<TAB>genislik<TAB>yukseklik<TAB>ad
//
// Kullanım:
//   swift Tools/listwindows.swift            -> tum pencereler
//   swift Tools/listwindows.swift UDFTest    -> yalnizca adi "UDFTest" icerenler

let filters = CommandLine.arguments.dropFirst().map { $0.lowercased() }

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

for window in list {
    let owner = window[kCGWindowOwnerName as String] as? String ?? "?"
    let number = window[kCGWindowNumber as String] as? Int ?? 0
    let name = window[kCGWindowName as String] as? String ?? ""
    let layer = window[kCGWindowLayer as String] as? Int ?? -1
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = bounds["Width"] as? Int ?? 0
    let height = bounds["Height"] as? Int ?? 0

    if !filters.isEmpty {
        let haystack = "\(owner) \(name)".lowercased()
        guard filters.contains(where: { haystack.contains($0) }) else { continue }
    }

    print("\(number)\t\(owner)\t\(layer)\t\(width)\t\(height)\t\(name)")
}

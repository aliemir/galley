// Prints every on-screen window an app owns as "id layer x,y,w,h", for
// `screencapture -l <id>` or `-R x,y,w,h` (popovers are their own windows).
// Usage: swift tools/window-bounds.swift Galley
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.dropFirst().first ?? "Galley"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for info in windows where (info[kCGWindowOwnerName as String] as? String) == owner {
    guard let id = info[kCGWindowNumber as String] as? Int,
          let b = info[kCGWindowBounds as String] as? [String: Double] else { continue }
    let layer = info[kCGWindowLayer as String] as? Int ?? 0
    let name = info[kCGWindowName as String] as? String ?? ""
    print(id, layer, "\(Int(b["X"]!)),\(Int(b["Y"]!)),\(Int(b["Width"]!)),\(Int(b["Height"]!))", name)
}

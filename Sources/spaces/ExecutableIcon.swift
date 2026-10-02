import AppKit

enum ExecutableIcon {
  private static let canvas: CGFloat = 1024

  static func install() -> Bool {
    guard let path = Bundle.main.executableURL?.resolvingSymlinksInPath().path,
      let permissions = try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
    else { return false }
    try? FileManager.default.setAttributes([.posixPermissions: permissions | 0o200], ofItemAtPath: path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path) }
    return NSWorkspace.shared.setIcon(image(), forFile: path)
  }

  private static func image() -> NSImage {
    NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { bounds in
      NSColor.black.setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 100, dy: 100), xRadius: 185, yRadius: 185).fill()

      let tile = CGSize(width: 150, height: 340)
      let gap: CGFloat = 50
      let originX = (canvas - (3 * tile.width + 2 * gap)) / 2
      NSColor.white.set()
      for column in 0..<3 {
        let frame = CGRect(
          origin: CGPoint(x: originX + CGFloat(column) * (tile.width + gap), y: (canvas - tile.height) / 2),
          size: tile)
        guard column != 1 else {
          NSBezierPath(roundedRect: frame, xRadius: 36, yRadius: 36).fill()
          continue
        }
        let outline = NSBezierPath(roundedRect: frame.insetBy(dx: 14, dy: 14), xRadius: 26, yRadius: 26)
        outline.lineWidth = 28
        outline.stroke()
      }
      return true
    }
  }
}

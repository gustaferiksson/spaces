import AppKit

public enum ScreenCorner: String, CaseIterable, Codable, Sendable {
  case topLeft = "top-left"
  case topRight = "top-right"
  case bottomLeft = "bottom-left"
  case bottomRight = "bottom-right"

  static let size: CGFloat = 4

  func contains(_ point: CGPoint, in screen: CGRect) -> Bool {
    let nearLeft = point.x - screen.minX <= Self.size
    let nearRight = screen.maxX - point.x <= Self.size
    let nearTop = screen.maxY - point.y <= Self.size
    let nearBottom = point.y - screen.minY <= Self.size
    if self == .topLeft { return nearTop && nearLeft }
    if self == .topRight { return nearTop && nearRight }
    if self == .bottomLeft { return nearBottom && nearLeft }
    return nearBottom && nearRight
  }
}

@MainActor
public final class HotCorner {
  private let corner: ScreenCorner
  private let onFire: () -> Void
  private var wasInCorner = false
  private var monitors: [Any] = []

  public init(_ corner: ScreenCorner, onFire: @escaping () -> Void) {
    self.corner = corner
    self.onFire = onFire
    let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    monitors = [
      NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
        MainActor.assumeIsolated { self?.evaluate() }
      },
      NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
        self?.evaluate()
        return event
      },
    ].compactMap { $0 }
  }

  isolated deinit {
    monitors.forEach(NSEvent.removeMonitor)
  }

  private func evaluate() {
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(mouse) }
    let inCorner = screen.map { corner.contains(mouse, in: $0.frame) } ?? false
    let fires = inCorner && !wasInCorner && NSEvent.pressedMouseButtons == 0
    wasInCorner = inCorner
    if fires { onFire() }
  }
}

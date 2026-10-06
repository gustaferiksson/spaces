import AppKit

@MainActor
public final class WindowMover {
  private static let systemWide = AXUIElementCreateSystemWide()

  private var restoreFrames: [AXUIElement: CGRect] = [:]
  private var placements:
    [AXUIElement: (action: WindowAction, fraction: CGFloat, frame: CGRect, original: CGRect)] = [:]
  let gap: @MainActor () -> CGFloat

  public init(gap: @escaping @MainActor () -> CGFloat) {
    self.gap = gap
    AXUIElementSetMessagingTimeout(Self.systemWide, 1)
  }

  public func perform(_ action: WindowAction) {
    guard let window = Self.focusedWindow(), let frame = Self.frame(of: window) else { return }
    let overlap = { (screen: NSScreen) in
      let shared = screen.frame.intersection(frame)
      return shared.width * shared.height
    }
    guard let screen = NSScreen.screens.max(by: { overlap($0) < overlap($1) }) else { return }
    let visible = screen.visibleFrame
    let gap = gap()
    let last = placements[window].flatMap { last in
      last.action == action && last.frame.isClose(to: frame) ? last : nil
    }

    if action == .maximize {
      let maximized = WindowLayout.frame(.maximize, in: visible, gap: gap)
      if last == nil && !maximized.isClose(to: frame) {
        restoreFrames[window] = frame
        place(window, at: maximized, action: action, fraction: 1, from: frame)
      } else if let original = restoreFrames.removeValue(forKey: window) {
        Self.setFrame(of: window, to: original)
        placements[window] = nil
      }
      return
    }

    let cycles = action == .leftHalf || action == .rightHalf
    let fraction =
      cycles ? WindowLayout.nextFraction(action, window: frame, in: visible, gap: gap, last: last?.fraction) : 1 / 2
    place(
      window, at: WindowLayout.frame(action, in: visible, fraction: fraction, gap: gap), action: action,
      fraction: fraction, from: frame)
  }

  public func snap(_ window: AXUIElement, to action: WindowAction, on screen: NSScreen, from original: CGRect) {
    if action == .maximize { restoreFrames[window] = original }
    place(
      window, at: WindowLayout.frame(action, in: screen.visibleFrame, gap: gap()), action: action, fraction: 1 / 2,
      from: original)
  }

  func unsnap(_ window: AXUIElement, placedAt placed: CGRect, grabbedAt cursor: CGPoint) -> CGRect? {
    guard let placement = placements[window], placement.frame.isClose(to: placed),
      let current = Self.frame(of: window)
    else { return nil }
    placements[window] = nil
    let size = placement.original.size
    let restored = CGRect(
      x: cursor.x - (cursor.x - current.minX) / current.width * size.width,
      y: current.maxY - size.height, width: size.width, height: size.height)
    Self.setFrame(of: window, to: restored)
    return Self.frame(of: window) ?? restored
  }

  private func place(
    _ window: AXUIElement, at target: CGRect, action: WindowAction, fraction: CGFloat, from current: CGRect
  ) {
    let original = placements[window].flatMap { $0.frame.isClose(to: current) ? $0.original : nil } ?? current
    Self.setFrame(of: window, to: target)
    placements[window] = (action, fraction, Self.frame(of: window) ?? target, original)
  }

  static func window(at point: CGPoint) -> (window: AXUIElement, frame: CGRect)? {
    var element: AXUIElement?
    let flipped = flip(CGRect(origin: point, size: .zero)).origin
    guard AXUIElementCopyElementAtPosition(systemWide, Float(flipped.x), Float(flipped.y), &element) == .success,
      let element
    else { return nil }
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    let window = role as? String == kAXWindowRole ? element : attribute(kAXWindowAttribute, of: element)
    guard let window, let frame = frame(of: window) else { return nil }
    return (window, frame)
  }

  static func frame(of window: AXUIElement) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
      AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
      let positionValue, let sizeValue,
      CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
    else { return nil }
    var position = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    return flip(CGRect(origin: position, size: size))
  }

  private static func setFrame(of window: AXUIElement, to frame: CGRect) {
    var pid: pid_t = 0
    AXUIElementGetPid(window, &pid)
    let app = AXUIElementCreateApplication(pid)
    var enhanced: CFTypeRef?
    AXUIElementCopyAttributeValue(app, "AXEnhancedUserInterface" as CFString, &enhanced)
    let wasEnhanced = enhanced as? Bool == true
    // Apps with VoiceOver-style enhanced UI on animate resizes and land on stale frames.
    if wasEnhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
    defer {
      if wasEnhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    let flipped = flip(frame)
    var position = flipped.origin
    var size = flipped.size
    guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size)
    else { return }
    // Size before and after the move, so a window crossing displays isn't clamped by the old screen.
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
  }

  private static func focusedWindow() -> AXUIElement? {
    guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
    return attribute(kAXFocusedWindowAttribute, of: AXUIElementCreateApplication(pid))
  }

  private static func attribute(_ name: String, of element: AXUIElement) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
      CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return (value as! AXUIElement)
  }

  // Accessibility frames have a top-left origin on the primary display; AppKit's are bottom-left.
  private static func flip(_ rect: CGRect) -> CGRect {
    let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
    return CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
  }
}

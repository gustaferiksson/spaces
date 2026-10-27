import AppKit
import Synchronization

public struct SwitcherWindow: Identifiable, Equatable, @unchecked Sendable {
  public let id: CGWindowID
  public let title: String
  public let isUntitled: Bool
  let element: AXUIElement?
}

public struct SwitcherApp: Identifiable, Equatable, Sendable {
  public let id: pid_t
  public let name: String
  public let icon: NSImage
  public let windows: [SwitcherWindow]
  public let recentWindowID: CGWindowID

  private static let titleSeparators = [" — ", " – ", " - ", " | ", " · ", ": "]

  public init(
    id: pid_t, name: String, icon: NSImage, windows: [(id: CGWindowID, title: String?, element: AXUIElement?)],
    frontToBack: [CGWindowID]
  ) {
    self.id = id
    self.name = name
    self.icon = icon
    let ordered = windows.sorted { $0.id < $1.id }
    let titles = ordered.map { Self.cleanTitle($0.title, appName: name) }
    self.windows = ordered.indices.map { index in
      let window = ordered[index]
      guard let title = titles[index] else {
        let number = titles[..<index].filter { $0 == nil }.count + 1
        let title = number > 1 ? "Untitled Window \(number)" : "Untitled Window"
        return SwitcherWindow(id: window.id, title: title, isUntitled: true, element: window.element)
      }
      return SwitcherWindow(id: window.id, title: title, isUntitled: false, element: window.element)
    }
    let ids = Set(ordered.map(\.id))
    recentWindowID = frontToBack.first(where: ids.contains) ?? ordered.first?.id ?? 0
  }

  public static func sorted(_ apps: [SwitcherApp]) -> [SwitcherApp] {
    apps.sorted { lhs, rhs in
      let order = lhs.name.localizedStandardCompare(rhs.name)
      return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }
  }

  static func cleanTitle(_ raw: String?, appName: String) -> String? {
    let title = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored, .backwards]
    let stripped = titleSeparators.lazy.compactMap { separator in
      title.range(of: separator + appName, options: options).map { String(title[..<$0.lowerBound]) }
    }.first ?? title
    let cleaned = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty || cleaned.compare(appName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
      ? nil : cleaned
  }
}

extension SwitcherApp {
  private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

  private static let getWindow: GetWindow? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
    .map { unsafeBitCast($0, to: GetWindow.self) }
  private static let accessibilityTimeout: Float = 0.1
  private static let minimumUnmatchedSize: CGFloat = 100

  // AXUIElement is an immutable CF reference that the Accessibility API accepts from any thread.
  private struct AccessibilityWindow: @unchecked Sendable {
    let id: CGWindowID
    let title: String?
    let element: AXUIElement
    let isWindow: Bool
  }

  static func onCurrentSpace(displays: [CGRect]) -> [SwitcherApp] {
    let ownPID = ProcessInfo.processInfo.processIdentifier
    let info =
      CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
      ?? []
    let onScreen = info.compactMap { entry -> (pid: pid_t, id: CGWindowID, isSubstantial: Bool)? in
      guard entry[kCGWindowLayer as String] as? Int == 0, let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
        let id = entry[kCGWindowNumber as String] as? CGWindowID, pid != ownPID,
        let boundsInfo = entry[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsInfo), displays.contains(where: bounds.intersects)
      else { return nil }
      let isVisible = entry[kCGWindowAlpha as String] as? Double ?? 1 > 0
      return (pid, id, isVisible && min(bounds.width, bounds.height) >= minimumUnmatchedSize)
    }
    let pids = Array(Set(onScreen.map(\.pid)))
    let accessibility = Mutex<[pid_t: [AccessibilityWindow]]>([:])
    DispatchQueue.concurrentPerform(iterations: pids.count) { index in
      guard let windows = accessibilityWindows(of: pids[index]) else { return }
      accessibility.withLock { $0[pids[index]] = windows }
    }
    let apps = pids.compactMap { pid -> SwitcherApp? in
      let axWindows = accessibility.withLock { $0[pid] }
      guard let app = NSRunningApplication(processIdentifier: pid), !app.isHidden else { return nil }
      let cgWindows = onScreen.filter { $0.pid == pid }
      let cgIDs = Set(cgWindows.map(\.id))
      let matchedIDs = Set((axWindows ?? []).map(\.id))
      let listed = (axWindows ?? []).filter { $0.isWindow && cgIDs.contains($0.id) }
        .map { (id: $0.id, title: $0.title, element: Optional($0.element)) }
      let unmatched = cgWindows.filter { $0.isSubstantial && !matchedIDs.contains($0.id) }
        .map { (id: $0.id, title: String?.none, element: AXUIElement?.none) }
      guard !listed.isEmpty || !unmatched.isEmpty else { return nil }
      return SwitcherApp(
        id: pid, name: app.localizedName ?? app.bundleIdentifier ?? "", icon: app.icon ?? NSImage(),
        windows: listed + unmatched, frontToBack: onScreen.map(\.id))
    }
    return sorted(apps)
  }

  private static func accessibilityWindows(of pid: pid_t) -> [AccessibilityWindow]? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, accessibilityTimeout)
    var value: CFTypeRef?
    guard let getWindow, AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
      let windows = value as? [AXUIElement]
    else { return nil }
    return windows.compactMap { window in
      var id: CGWindowID = 0
      var subrole: CFTypeRef?
      var title: CFTypeRef?
      guard getWindow(window, &id) == .success else { return nil }
      AXUIElementSetMessagingTimeout(window, accessibilityTimeout)
      AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
      AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
      let isWindow = subrole as? String == kAXStandardWindowSubrole || subrole as? String == kAXDialogSubrole
      return AccessibilityWindow(id: id, title: title as? String, element: window, isWindow: isWindow)
    }
  }
}


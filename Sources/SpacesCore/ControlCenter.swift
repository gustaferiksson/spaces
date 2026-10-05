import AppKit

public func toggleControlCenter() {
  guard
    let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first?
      .processIdentifier
  else { return }
  var extrasMenuBar: CFTypeRef?
  AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), "AXExtrasMenuBar" as CFString, &extrasMenuBar)
  guard let extrasMenuBar, CFGetTypeID(extrasMenuBar) == AXUIElementGetTypeID() else { return }
  var groups: CFTypeRef?
  AXUIElementCopyAttributeValue(extrasMenuBar as! AXUIElement, kAXChildrenAttribute as CFString, &groups)
  let items = (groups as? [AXUIElement] ?? []).flatMap { group in
    var items: CFTypeRef?
    AXUIElementCopyAttributeValue(group, kAXChildrenAttribute as CFString, &items)
    return items as? [AXUIElement] ?? []
  }
  let controlCenter = items.first { item in
    var identifier: CFTypeRef?
    AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifier)
    return identifier as? String == "com.apple.menuextra.controlcenter"
  }
  guard let controlCenter else { return }
  AXUIElementPerformAction(controlCenter, kAXPressAction as CFString)
}

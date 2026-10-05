import AppKit

public func toggleControlCenter() {
  guard
    let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.MenuBarAgent").first?
      .processIdentifier
  else { return }
  var extrasMenuBar: CFTypeRef?
  AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), "AXExtrasMenuBar" as CFString, &extrasMenuBar)
  guard let extrasMenuBar, CFGetTypeID(extrasMenuBar) == AXUIElementGetTypeID() else { return }
  let item = children(of: extrasMenuBar as! AXUIElement).flatMap(children).first { item in
    var identifier: CFTypeRef?
    AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifier)
    return identifier as? String == "com.apple.menuextra.controlcenter"
  }
  guard let item else { return }
  AXUIElementPerformAction(item, kAXPressAction as CFString)
}

private func children(of element: AXUIElement) -> [AXUIElement] {
  var children: CFTypeRef?
  AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
  return children as? [AXUIElement] ?? []
}

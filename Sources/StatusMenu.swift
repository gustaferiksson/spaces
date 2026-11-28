import AppKit
import SwiftUI

@MainActor @Observable
final class MenuHighlight {
  var item: NSUserInterfaceItemIdentifier?
}

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
  static let width: CGFloat = 300
  static let badgeSize: CGFloat = 26
  static let spaceSwitchingItem = NSUserInterfaceItemIdentifier("spaceSwitching")
  static let windowSnappingItem = NSUserInterfaceItemIdentifier("windowSnapping")

  let menu = NSMenu()
  let highlight = MenuHighlight()
  private let engine: Engine
  private let settings: AppSettings
  private let updater: AppUpdater
  private var statusItem: NSStatusItem?

  init(engine: Engine, settings: AppSettings, updater: AppUpdater) {
    self.engine = engine
    self.settings = settings
    self.updater = updater
    super.init()
    menu.delegate = self
    menu.autoenablesItems = false
    menu.minimumWidth = Self.width
  }

  func install() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.menu = menu
    statusItem = item
    Task { [engine, settings] in
      for await (desktop, showsDesktop) in Observations({ (engine.desktopNumber, settings.showDesktopInMenuBar) }) {
        item.button?.image = menuBarImage(desktop: showsDesktop ? desktop : nil)
      }
    }
    Task { [settings] in
      for await isVisible in Observations({ settings.showMenuBarIcon }) {
        item.isVisible = isVisible
      }
    }
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    var items = [
      rowItem(Self.spaceSwitchingItem, "Instant Space Switching", #selector(toggleSpaceSwitching), SpaceSwitchingRow(engine: engine, highlight: highlight)),
      rowItem(Self.windowSnappingItem, "Window Snapping", #selector(toggleWindowSnapping), WindowSnappingRow(engine: engine, settings: settings, highlight: highlight)),
    ]
    if !engine.isTrusted {
      let view = NSHostingView(rootView: NoticeRow())
      view.setFrameSize(view.fittingSize)
      let notice = NSMenuItem()
      notice.view = view
      notice.isEnabled = false
      items += [notice, actionItem("Allow Accessibility Access…", #selector(openAccessibilitySettings))]
    }
    items.append(.separator())
    if NSEvent.modifierFlags.contains(.option) {
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
      let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
      let info = NSMenuItem(title: "Spaces \(version) (\(build))", action: nil, keyEquivalent: "")
      info.isEnabled = false
      items += [info, .separator()]
    }
    if let staged = updater.staged {
      items.append(actionItem("Install Spaces \(staged.version) and Relaunch", #selector(installUpdate)))
    }
    items += [
      actionItem("Spaces Settings…", #selector(openSettings), key: ","),
      actionItem("Quit Spaces", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp),
    ]
    menu.items = items
  }

  func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
    highlight.item = item?.identifier
  }

  func menuDidClose(_ menu: NSMenu) {
    highlight.item = nil
  }

  private func menuBarImage(desktop: Int?) -> NSImage? {
    guard let desktop else {
      let symbol = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "Spaces")
      symbol?.isTemplate = true
      return symbol
    }
    let title = NSAttributedString(
      string: "Desktop \(desktop)",
      attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)]
    )
    let size = title.size()
    let image = NSImage(size: NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up)), flipped: false) { rect in
      title.draw(in: rect)
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = title.string
    return image
  }

  private func rowItem<Content: View>(_ id: NSUserInterfaceItemIdentifier, _ title: String, _ action: Selector, _ row: Content) -> NSMenuItem {
    let view = MenuRowHostingView(rootView: row)
    view.setFrameSize(view.fittingSize)
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.view = view
    item.identifier = id
    item.target = self
    return item
  }

  private func actionItem(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = target ?? self
    // macOS assigns symbols to items like Settings… and Quit, and 27 shows only some of them; Wi-Fi's menu shows none.
    if #available(macOS 27, *) { item.preferredImageVisibility = .hidden }
    return item
  }

  @objc private func toggleSpaceSwitching() {
    engine.spaceSwitchingEnabled.toggle()
  }

  @objc private func toggleWindowSnapping() {
    engine.windowSnappingEnabled.toggle()
  }

  @objc private func openAccessibilitySettings() {
    NSWorkspace.shared.open(accessibilitySettingsURL)
  }

  @objc private func installUpdate() {
    updater.installAndRelaunch()
  }

  @objc private func openSettings() {
    showSettingsWindow()
  }
}

// Custom menu item views get mouse events but no action; sending it here matches a standard item's click.
private final class MenuRowHostingView<Content: View>: NSHostingView<Content> {
  override func hitTest(_ point: NSPoint) -> NSView? {
    frame.contains(point) ? self : nil
  }

  override func mouseUp(with event: NSEvent) {
    guard let item = enclosingMenuItem, item.isEnabled, let action = item.action else { return }
    NSApp.sendAction(action, to: item.target, from: item)
  }
}

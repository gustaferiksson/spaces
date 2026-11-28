import AppKit
import SpacesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let engine = Engine(settings: .shared)
  let updater = AppUpdater()
  private lazy var statusMenu = StatusMenu(engine: engine, settings: .shared, updater: updater)
  private let screenCorners = ScreenCornersController(settings: .shared)

  func applicationDidFinishLaunching(_ notification: Notification) {
    #if DEBUG
      if let output = SettingsSnapshot.output {
        Task { await SettingsSnapshot.capture(to: output) { _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false) } }
        return
      }
    #endif
    statusMenu.install()
    screenCorners.start()
    engine.start()
    updater.start()
  }

  func applicationWillTerminate(_ notification: Notification) {
    updater.installOnQuit()
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for action in urls.compactMap({ $0.host().flatMap { HotKeyAction(rawValue: $0) } }) {
      engine.perform(action)
    }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    showSettingsWindow()
    return true
  }
}

// SwiftUI rejects showSettingsWindow: sent from code ("use SettingsLink") but honours its own app-menu item.
@MainActor
func showSettingsWindow() {
  guard let menu = NSApp.mainMenu?.items.first?.submenu,
    let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," })
  else { return }
  NSApp.activate()
  menu.performActionForItem(at: index)
}

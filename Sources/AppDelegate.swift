import AppKit
import SpacesCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let engine = Engine(settings: .shared)
  let updater = AppUpdater()

  func applicationDidFinishLaunching(_ notification: Notification) {
    #if DEBUG
      if let output = SettingsSnapshot.output {
        Task { await SettingsSnapshot.capture(to: output) { _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false) } }
        return
      }
    #endif
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
    // SwiftUI rejects showSettingsWindow: sent from code ("use SettingsLink") but honours its own app-menu item.
    guard let menu = NSApp.mainMenu?.items.first?.submenu,
      let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," })
    else { return true }
    NSApp.activate()
    menu.performActionForItem(at: index)
    return true
  }
}

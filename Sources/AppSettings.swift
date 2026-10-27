import Foundation
import Observation
import SpacesCore

let defaultSnapActions: [SnapZone: WindowAction] = [
  .left: .leftHalf,
  .right: .rightHalf,
  .top: .maximize,
  .topLeft: .topLeft,
  .topRight: .topRight,
  .bottomLeft: .bottomLeft,
  .bottomRight: .bottomRight,
]

private let dockCornerKeys: [ScreenCorner: String] = [
  .topLeft: "tl", .topRight: "tr", .bottomLeft: "bl", .bottomRight: "br",
]

// Dock's hot corner action codes: 1 is none, 2 is Mission Control.
func macOSHotCornerAction(_ corner: ScreenCorner) -> Int? {
  guard let key = dockCornerKeys[corner], let dock = UserDefaults(suiteName: "com.apple.dock"),
    dock.integer(forKey: "wvous-\(key)-modifier") == 0
  else { return nil }
  let action = dock.integer(forKey: "wvous-\(key)-corner")
  return action > 1 ? action : nil
}

@MainActor @Observable
final class AppSettings {
  static let shared: AppSettings = {
    #if DEBUG
      if SettingsSnapshot.output != nil {
        let suite = "dev.gustaf.Spaces.snapshot"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        return AppSettings(store: UserDefaults(suiteName: suite) ?? .standard)
      }
    #endif
    return AppSettings(store: .standard)
  }()

  @ObservationIgnored private let store: UserDefaults

  var showMenuBarIcon: Bool { didSet { store.set(showMenuBarIcon, forKey: "showMenuBarIcon") } }
  var showDesktopInMenuBar: Bool { didSet { store.set(showDesktopInMenuBar, forKey: "showDesktopInMenuBar") } }
  var spaceSwitchingEnabled: Bool { didSet { store.set(spaceSwitchingEnabled, forKey: "spaceSwitchingEnabled") } }
  var windowSnappingEnabled: Bool { didSet { store.set(windowSnappingEnabled, forKey: "windowSnappingEnabled") } }
  var windowGap: Double { didSet { store.set(windowGap, forKey: "windowGap") } }
  var windowSwitcherEnabled: Bool { didSet { store.set(windowSwitcherEnabled, forKey: "windowSwitcherEnabled") } }
  var switcherAnimates: Bool { didSet { store.set(switcherAnimates, forKey: "switcherAnimates") } }
  var switcherCorner: ScreenCorner? { didSet { store.set(switcherCorner?.rawValue, forKey: "switcherCorner") } }
  var snapActions: [SnapZone: WindowAction] {
    didSet {
      let stored = Dictionary(uniqueKeysWithValues: snapActions.map { ($0.key.rawValue, $0.value.rawValue) })
      store.set(stored, forKey: "snapActions")
    }
  }
  var shortcuts: [HotKeyAction: Shortcut] {
    didSet { store.set(try? JSONEncoder().encode(shortcuts), forKey: "shortcuts") }
  }

  init(store: UserDefaults) {
    store.register(defaults: [
      "showMenuBarIcon": true, "spaceSwitchingEnabled": true, "windowSnappingEnabled": true, "switcherAnimates": true,
    ])
    self.store = store
    showMenuBarIcon = store.bool(forKey: "showMenuBarIcon")
    showDesktopInMenuBar = store.bool(forKey: "showDesktopInMenuBar")
    spaceSwitchingEnabled = store.bool(forKey: "spaceSwitchingEnabled")
    windowSnappingEnabled = store.bool(forKey: "windowSnappingEnabled")
    windowGap = store.double(forKey: "windowGap")
    windowSwitcherEnabled = store.bool(forKey: "windowSwitcherEnabled")
    switcherAnimates = store.bool(forKey: "switcherAnimates")
    switcherCorner = store.string(forKey: "switcherCorner").flatMap(ScreenCorner.init)
    let storedSnapActions = (store.dictionary(forKey: "snapActions") as? [String: String]).map { stored in
      Dictionary(
        uniqueKeysWithValues: stored.compactMap { zone, action in
          SnapZone(rawValue: zone).flatMap { zone in WindowAction(rawValue: action).map { (zone, $0) } }
        })
    }
    snapActions = storedSnapActions ?? defaultSnapActions
    shortcuts =
      store.data(forKey: "shortcuts").flatMap { try? JSONDecoder().decode([HotKeyAction: Shortcut].self, from: $0) }
      ?? Shortcut.defaults
  }

  func isEnabled(_ action: HotKeyAction) -> Bool {
    if action == .previousSpace || action == .nextSpace { return spaceSwitchingEnabled }
    if action == .windowSwitcher { return windowSwitcherEnabled }
    if WindowAction(rawValue: action.rawValue) != nil { return windowSnappingEnabled }
    return true
  }
}

import AppKit
import Observation
import SpacesCore

@MainActor @Observable
final class Engine {
  let settings: AppSettings
  private(set) var isTrusted = AXIsProcessTrusted()
  private(set) var takenShortcuts: Set<HotKeyAction> = []
  private(set) var desktopNumber = SpaceLayout.current()?.desktopNumber

  var spaceSwitchingEnabled: Bool {
    get { settings.spaceSwitchingEnabled }
    set {
      settings.spaceSwitchingEnabled = newValue
      registerShortcuts()
    }
  }

  var windowSnappingEnabled: Bool {
    get { settings.windowSnappingEnabled }
    set {
      settings.windowSnappingEnabled = newValue
      registerShortcuts()
    }
  }

  @ObservationIgnored private let switcher = SpaceSwitcher()
  @ObservationIgnored private let mover: WindowMover
  @ObservationIgnored private var indicator: SpaceIndicator?
  @ObservationIgnored private var hotKeys: HotKeyListener?
  @ObservationIgnored private var snap: SnapController?
  @ObservationIgnored private var spaceObserver: (any NSObjectProtocol)?

  init(settings: AppSettings) {
    self.settings = settings
    mover = WindowMover { CGFloat(settings.windowGap) }
  }

  func start() {
    spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.desktopNumber = SpaceLayout.current()?.desktopNumber }
    }
    Task {
      await waitForAccessibility()
      begin()
    }
  }

  private func begin() {
    indicator = SpaceIndicator()
    hotKeys = try? HotKeyListener { [weak self] action in self?.perform(action) }
    registerShortcuts()
    snap = SnapController(mover: mover, isEnabled: { [settings] in settings.windowSnappingEnabled }) {
      [settings] zone in settings.snapActions[zone]
    }
  }

  func perform(_ action: HotKeyAction) {
    guard isTrusted, settings.isEnabled(action) else { return }
    if let windowAction = WindowAction(rawValue: action.rawValue) {
      mover.perform(windowAction)
    } else if action == .controlCenter {
      toggleControlCenter()
    } else if let destination = switcher.switchSpace(action == .previousSpace ? .left : .right) {
      indicator?.show(destination)
    }
  }

  func setShortcut(_ shortcut: Shortcut?, for action: HotKeyAction) {
    let duplicates = settings.shortcuts.filter { $0.key != action && $0.value == shortcut }.keys
    duplicates.forEach { settings.shortcuts[$0] = nil }
    settings.shortcuts[action] = shortcut
    registerShortcuts()
  }

  func pauseShortcuts() {
    hotKeys?.unregisterAll()
  }

  func registerShortcuts() {
    takenShortcuts = hotKeys?.register(settings.shortcuts.filter { settings.isEnabled($0.key) }) ?? []
  }

  private func waitForAccessibility() async {
    guard !isTrusted else { return }
    AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    while !AXIsProcessTrusted() { try? await Task.sleep(for: .seconds(1)) }
    isTrusted = true
  }
}

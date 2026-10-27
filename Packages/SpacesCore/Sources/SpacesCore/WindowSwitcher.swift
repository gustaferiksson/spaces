import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI

public enum SwitcherTrigger: Sendable {
  case hotCorner, shortcut
}

@MainActor @Observable
public final class WindowSwitcher {
  static let tileSize: CGFloat = 112
  static let tileSpacing: CGFloat = 4
  static let maxColumns = 8
  static let thumbnailWidth: CGFloat = 240
  private static let expandDelay: Duration = .milliseconds(200)

  private(set) var apps: [SwitcherApp] = []
  private(set) var columns = 1
  private(set) var thumbnails: [CGWindowID: CGImage] = [:]
  public var selectedApp: pid_t?
  public var expandedApp: pid_t?
  public var selectedWindow: CGWindowID?

  @ObservationIgnored private let panel = SwitcherPanel()
  @ObservationIgnored private var clickMonitor: Any?
  @ObservationIgnored private var expandTask: Task<Void, Never>?
  @ObservationIgnored private var shareableContent: SCShareableContent?

  public init() {
    panel.contentView = NSHostingView(rootView: SwitcherView(switcher: self))
    let closeOn: [(NotificationCenter, Notification.Name, AnyObject?)] = [
      (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification, nil),
      (.default, NSApplication.didChangeScreenParametersNotification, nil),
      (.default, NSWindow.didResignKeyNotification, panel),
    ]
    for (center, name, object) in closeOn {
      center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.close() }
      }
    }
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.panel.isKeyWindow, !event.modifierFlags.contains(.command) else { return event }
      self.handleKey(Int(event.keyCode))
      return nil
    }
  }

  public func toggle(from trigger: SwitcherTrigger) {
    guard !panel.isVisible else {
      close()
      return
    }
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(mouse) } ?? NSScreen.main
    guard let screen else { return }
    load(SwitcherApp.onCurrentSpace(), width: screen.visibleFrame.width)
    if trigger == .shortcut { selectedApp = apps.first?.id }
    panel.setFrame(screen.visibleFrame, display: false)
    panel.alphaValue = 0
    panel.makeKeyAndOrderFront(nil)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      panel.animator().alphaValue = 1
    }
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
    guard CGPreflightScreenCaptureAccess() else { return }
    Task {
      let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
      guard panel.isVisible else { return }
      shareableContent = content
      if let selectedWindow { loadThumbnail(selectedWindow) }
    }
  }

  public func load(_ apps: [SwitcherApp], width: CGFloat) {
    self.apps = apps
    let fitting = Int((width * 0.8 + Self.tileSpacing) / (Self.tileSize + Self.tileSpacing))
    columns = max(1, min(apps.count, Self.maxColumns, fitting))
    selectedApp = nil
    expandedApp = nil
    selectedWindow = nil
    thumbnails = [:]
  }

  public func close() {
    clickMonitor.map(NSEvent.removeMonitor)
    clickMonitor = nil
    expandTask?.cancel()
    shareableContent = nil
    thumbnails = [:]
    panel.orderOut(nil)
  }

  func focus(_ app: SwitcherApp, window id: CGWindowID) {
    let appElement = AXUIElementCreateApplication(app.id)
    AXUIElementSetMessagingTimeout(appElement, 0.25)
    let element = app.windows.first { $0.id == id }?.element
    var role: CFTypeRef?
    let exists =
      element.map { AXUIElementCopyAttributeValue($0, kAXRoleAttribute as CFString, &role) == .success }
      ?? (NSRunningApplication(processIdentifier: app.id)?.isTerminated == false)
    guard exists else {
      load(SwitcherApp.onCurrentSpace(), width: panel.frame.width)
      return
    }
    AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    if let element {
      AXUIElementPerformAction(element, kAXRaiseAction as CFString)
      AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
    }
    close()
  }

  func hover(_ app: SwitcherApp?) {
    expandTask?.cancel()
    guard let app, expandedApp == nil || expandedApp == app.id else { return }
    selectedApp = app.id
    guard app.windows.count > 1, expandedApp != app.id else { return }
    expandTask = Task { [weak self] in
      try? await Task.sleep(for: Self.expandDelay)
      guard !Task.isCancelled, let self else { return }
      self.expandedApp = app.id
      self.selectedWindow = nil
    }
  }

  func collapse() {
    expandedApp = nil
    selectedWindow = nil
  }

  func selectWindow(_ id: CGWindowID) {
    selectedWindow = id
    loadThumbnail(id)
  }

  static func step(from index: Int?, dx: Int, dy: Int, count: Int, columns: Int) -> Int? {
    guard count > 0 else { return nil }
    guard let index else { return 0 }
    let next = index + dx + dy * columns
    if dx != 0 { return next >= 0 && next < count && next / columns == index / columns ? next : index }
    if next >= count { return index / columns < (count - 1) / columns ? count - 1 : index }
    return next >= 0 ? next : index
  }

  private func handleKey(_ keyCode: Int) {
    let selected = apps.first { $0.id == selectedApp }
    let expanded = apps.first { $0.id == expandedApp }
    if keyCode == kVK_Escape {
      if expanded == nil { close() } else { collapse() }
    } else if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
      if let expanded, let selectedWindow {
        focus(expanded, window: selectedWindow)
      } else if let selected {
        focus(selected, window: selected.recentWindowID)
      }
    } else if keyCode == kVK_Space {
      if expanded != nil {
        collapse()
      } else if let selected, selected.windows.count > 1 {
        expandedApp = selected.id
        selectWindow(selected.windows[0].id)
      }
    } else if let expanded {
      moveInStack(expanded, keyCode: keyCode)
    } else {
      moveInGrid(keyCode: keyCode)
    }
  }

  private func moveInStack(_ app: SwitcherApp, keyCode: Int) {
    if keyCode == kVK_LeftArrow {
      collapse()
      return
    }
    let delta = keyCode == kVK_UpArrow ? -1 : keyCode == kVK_DownArrow ? 1 : 0
    guard delta != 0 else { return }
    let index = app.windows.firstIndex { $0.id == selectedWindow }.map { $0 + delta } ?? 0
    selectWindow(app.windows[min(max(index, 0), app.windows.count - 1)].id)
  }

  private func moveInGrid(keyCode: Int) {
    let moves = [kVK_LeftArrow: (-1, 0), kVK_RightArrow: (1, 0), kVK_UpArrow: (0, -1), kVK_DownArrow: (0, 1)]
    guard let (dx, dy) = moves[keyCode] else { return }
    let index = apps.firstIndex { $0.id == selectedApp }
    let next = Self.step(from: index, dx: dx, dy: dy, count: apps.count, columns: columns)
    selectedApp = next.map { apps[$0].id }
  }

  private func loadThumbnail(_ id: CGWindowID) {
    guard thumbnails[id] == nil, let window = shareableContent?.windows.first(where: { $0.windowID == id }) else { return }
    let configuration = SCStreamConfiguration()
    let scale = panel.backingScaleFactor * Self.thumbnailWidth / max(window.frame.width, 1)
    configuration.width = Int(window.frame.width * scale)
    configuration.height = Int(window.frame.height * scale)
    configuration.showsCursor = false
    let filter = SCContentFilter(desktopIndependentWindow: window)
    Task {
      guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
        panel.isVisible
      else { return }
      thumbnails[id] = image
    }
  }
}

final class SwitcherPanel: NSPanel {
  init() {
    super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    hidesOnDeactivate = false
    level = .statusBar
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
  }

  override var canBecomeKey: Bool { true }
}

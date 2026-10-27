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
  static let maxPreviewWidth: CGFloat = 320
  static let previewAspect: CGFloat = 0.625
  static let previewInset: CGFloat = 8
  static let previewTitleHeight: CGFloat = 24
  private static let expandDelay: Duration = .milliseconds(200)

  private(set) var apps: [SwitcherApp] = []
  private(set) var columns = 1
  private(set) var size = CGSize.zero
  public var thumbnails: [CGWindowID: CGImage] = [:]
  public var selectedApp: pid_t?
  public var expandedApp: pid_t?
  public var selectedWindow: CGWindowID?

  @ObservationIgnored private let panel = SwitcherPanel()
  @ObservationIgnored private var clickMonitor: Any?
  @ObservationIgnored private var expandTask: Task<Void, Never>?
  @ObservationIgnored private var refreshTask: Task<Void, Never>?

  public init() {
    let hostingView = NSHostingView(rootView: SwitcherView(switcher: self))
    hostingView.sizingOptions = []
    panel.contentView = hostingView
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
    collapse()
    selectedApp = trigger == .shortcut ? apps.first?.id : nil
    load(apps, in: screen.visibleFrame.size)
    panel.setFrame(screen.visibleFrame, display: false)
    panel.makeKeyAndOrderFront(nil)
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
    refresh()
  }

  public func refresh() {
    let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
    let displays = NSScreen.screens.map {
      CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
    }
    refreshTask?.cancel()
    refreshTask = Task {
      let fresh = await Task.detached(priority: .userInitiated) { SwitcherApp.onCurrentSpace(displays: displays) }.value
      guard !Task.isCancelled else { return }
      load(fresh, in: size)
      guard panel.isVisible else { return }
      await captureThumbnails()
    }
  }

  public func load(_ apps: [SwitcherApp], in size: CGSize) {
    self.apps = apps
    self.size = size
    let fitting = Int((size.width * 0.8 + Self.tileSpacing) / (Self.tileSize + Self.tileSpacing))
    columns = max(1, min(apps.count, Self.maxColumns, fitting))
    let windowIDs = Set(apps.flatMap { $0.windows.map(\.id) })
    thumbnails = thumbnails.filter { windowIDs.contains($0.key) }
    if let selectedApp, !apps.contains(where: { $0.id == selectedApp }) { self.selectedApp = nil }
    if let expandedApp, !apps.contains(where: { $0.id == expandedApp }) { collapse() }
    if let selectedWindow, !windowIDs.contains(selectedWindow) { self.selectedWindow = nil }
  }

  var gridSize: CGSize {
    let rows = CGFloat((apps.count + columns - 1) / columns)
    let width = CGFloat(columns) * (Self.tileSize + Self.tileSpacing) - Self.tileSpacing
    return CGSize(width: width, height: max(0, rows * (Self.tileSize + Self.tileSpacing) - Self.tileSpacing))
  }

  var gridTop: CGFloat {
    max(16, ((size.height - gridSize.height - 32) / 3 / 4).rounded(.down) * 4)
  }

  var previewLayout: (columns: Int, size: CGSize) {
    let count = apps.first { $0.id == expandedApp }?.windows.count ?? 0
    let available = CGSize(width: size.width - 96, height: size.height - gridTop - gridSize.height - 80)
    return Self.previewLayout(count: count, in: available)
  }

  static func previewLayout(count: Int, in available: CGSize) -> (columns: Int, size: CGSize) {
    guard count > 0 else { return (1, .zero) }
    let options = (1...count).map { rowCount in
      let columns = (count + rowCount - 1) / rowCount
      let rows = CGFloat(rowCount)
      let byWidth = available.width / CGFloat(columns) - 2 * previewInset
      let byHeight = (available.height / rows - 2 * previewInset - previewTitleHeight) / previewAspect
      let width = max(96, (min(maxPreviewWidth, byWidth, byHeight) / 4).rounded(.down) * 4)
      return (columns: columns, size: CGSize(width: width, height: (width * previewAspect / 4).rounded(.down) * 4))
    }
    return options.max { ($0.size.width, $0.columns) < ($1.size.width, $1.columns) }!
  }

  public func close() {
    clickMonitor.map(NSEvent.removeMonitor)
    clickMonitor = nil
    expandTask?.cancel()
    refreshTask?.cancel()
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
      selectedApp = nil
      collapse()
      refresh()
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
    guard let app else { return }
    selectedApp = app.id
    guard expandedApp != app.id else { return }
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
    selectedApp = expandedApp
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
    expandTask?.cancel()
    let selected = apps.first { $0.id == selectedApp }
    let expanded = apps.first { $0.id == expandedApp }
    if keyCode == kVK_Escape {
      if expanded == nil { close() } else { collapse() }
    } else if keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter {
      if let expanded {
        focus(expanded, window: selectedWindow ?? expanded.recentWindowID)
      } else if let selected {
        focus(selected, window: selected.recentWindowID)
      }
    } else if keyCode == kVK_Space {
      if expanded != nil {
        collapse()
      } else if let selected {
        expandedApp = selected.id
        selectWindow(selected.windows[0].id)
      }
    } else {
      move(in: expanded, keyCode: keyCode)
    }
  }

  private func move(in expanded: SwitcherApp?, keyCode: Int) {
    let moves = [kVK_LeftArrow: (-1, 0), kVK_RightArrow: (1, 0), kVK_UpArrow: (0, -1), kVK_DownArrow: (0, 1)]
    guard let (dx, dy) = moves[keyCode] else { return }
    guard let expanded else {
      let index = apps.firstIndex { $0.id == selectedApp }
      selectedApp = Self.step(from: index, dx: dx, dy: dy, count: apps.count, columns: columns).map { apps[$0].id }
      return
    }
    let index = expanded.windows.firstIndex { $0.id == selectedWindow }
    let previewColumns = previewLayout.columns
    guard index.map({ dx >= 0 || $0 % previewColumns != 0 }) ?? true else {
      collapse()
      return
    }
    let next = Self.step(from: index, dx: dx, dy: dy, count: expanded.windows.count, columns: previewColumns)
    next.map { selectWindow(expanded.windows[$0].id) }
  }

  private func captureThumbnails() async {
    guard CGPreflightScreenCaptureAccess(),
      let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    else { return }
    let scale = panel.backingScaleFactor
    let windows = apps.flatMap(\.windows).compactMap { window in content.windows.first { $0.windowID == window.id } }
    for window in windows {
      Task {
        let configuration = SCStreamConfiguration()
        let maxHeight = Self.maxPreviewWidth * Self.previewAspect
        let fit = scale * min(1, Self.maxPreviewWidth / max(window.frame.width, 1), maxHeight / max(window.frame.height, 1))
        configuration.width = Int(window.frame.width * fit)
        configuration.height = Int(window.frame.height * fit)
        configuration.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        else { return }
        thumbnails[window.windowID] = image
      }
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

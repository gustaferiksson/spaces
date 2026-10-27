import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit
import SwiftUI

public enum SwitcherTrigger: Sendable {
  case hotCorner, shortcut
}

@MainActor @Observable
public final class WindowSwitcher {
  static let maxStackWidth: CGFloat = 480
  static let maxPreviewWidth: CGFloat = 640
  static let previewAspect: CGFloat = 0.625
  static let previewInset: CGFloat = 8
  static let stackLabelHeight: CGFloat = 40
  static let previewLabelHeight: CGFloat = 24
  private static let expandDelay: Duration = .milliseconds(200)

  private(set) var apps: [SwitcherApp] = []
  private(set) var size = CGSize.zero
  private(set) var contentRect = CGRect.zero
  private(set) var screenOrigin = CGPoint.zero
  private(set) var pickedWindow: CGWindowID?
  private(set) var wallpapers: [URL: CGImage] = [:]
  public var isPresented = false
  public var thumbnails: [CGWindowID: CGImage] = [:]
  public var selectedApp: pid_t?
  public var expandedApp: pid_t?
  public var selectedWindow: CGWindowID?
  public var backdropURL: URL?
  public var backdropOptions: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
  public var animation = Animation.smooth(duration: 0.24)

  @ObservationIgnored private let animates: () -> Bool
  @ObservationIgnored private let panel = SwitcherPanel()
  @ObservationIgnored private var clickMonitor: Any?
  @ObservationIgnored private var expandTask: Task<Void, Never>?
  @ObservationIgnored private var refreshTask: Task<Void, Never>?
  @ObservationIgnored private var collapsePoint: CGPoint?

  public init(animates: @escaping () -> Bool = { true }) {
    self.animates = animates
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
      if self.isPresented { self.handleKey(Int(event.keyCode)) }
      return nil
    }
  }

  var motion: Animation? { animates() ? animation : nil }

  var wallpaper: CGImage? { backdropURL.flatMap { wallpapers[$0] } }

  public func toggle(from trigger: SwitcherTrigger) {
    guard !panel.isVisible else {
      dismiss()
      return
    }
    let mouse = NSEvent.mouseLocation
    let screen = NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(mouse) } ?? NSScreen.main
    guard let screen else { return }
    var reset = Transaction()
    reset.disablesAnimations = true
    withTransaction(reset) {
      place(frame: screen.frame, visibleFrame: screen.visibleFrame, primaryHeight: NSScreen.screens[0].frame.maxY)
      backdropURL = NSWorkspace.shared.desktopImageURL(for: screen)
      backdropOptions = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
      expandedApp = nil
      selectedWindow = nil
      collapsePoint = mouse
      selectedApp = trigger == .shortcut ? apps.first?.id : nil
      pickedWindow = nil
      isPresented = motion == nil
    }
    panel.setFrame(screen.frame, display: false)
    panel.makeKeyAndOrderFront(nil)
    if let motion {
      panel.display()
      CATransaction.flush()
      DispatchQueue.main.async { withAnimation(motion) { self.isPresented = true } }
    }
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.close() }
    }
    refresh()
  }

  public func place(frame: CGRect, visibleFrame: CGRect, primaryHeight: CGFloat) {
    size = frame.size
    screenOrigin = CGPoint(x: frame.minX, y: primaryHeight - frame.maxY)
    let visible = CGRect(
      x: visibleFrame.minX - frame.minX, y: frame.maxY - visibleFrame.maxY, width: visibleFrame.width,
      height: visibleFrame.height)
    contentRect = visible.insetBy(
      dx: (visible.width * 0.05 / 4).rounded(.up) * 4, dy: (visible.height * 0.05 / 4).rounded(.up) * 4)
  }

  public func refresh() {
    let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
    let displays = NSScreen.screens.map {
      CGRect(x: $0.frame.minX, y: primaryHeight - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height)
    }
    loadWallpapers()
    refreshTask?.cancel()
    refreshTask = Task {
      let fresh = await Task.detached(priority: .userInitiated) { SwitcherApp.onCurrentSpace(displays: displays) }.value
      guard !Task.isCancelled else { return }
      load(fresh)
      guard panel.isVisible else { return }
      await captureThumbnails()
    }
  }

  public func load(_ apps: [SwitcherApp]) {
    self.apps = apps
    let windowIDs = Set(apps.flatMap { $0.windows.map(\.id) })
    thumbnails = thumbnails.filter { windowIDs.contains($0.key) }
    if let selectedApp, !apps.contains(where: { $0.id == selectedApp }) { self.selectedApp = nil }
    if let expandedApp, !apps.contains(where: { $0.id == expandedApp }) { collapse() }
    if let selectedWindow, !windowIDs.contains(selectedWindow) { self.selectedWindow = nil }
  }

  public func setWallpaper(_ image: CGImage, for url: URL) {
    wallpapers[url] = image
  }

  private func loadWallpapers() {
    let urls = Set(NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0) })
    let maxPixels = NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }.max() ?? 0
    wallpapers = wallpapers.filter { urls.contains($0.key) }
    for url in urls where wallpapers[url] == nil {
      Task {
        let image = await Task.detached(priority: .utility) {
          let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
          ] as CFDictionary
          return CGImageSourceCreateWithURL(url as CFURL, nil).flatMap {
            CGImageSourceCreateThumbnailAtIndex($0, 0, options)
          }
        }.value
        image.map { wallpapers[url] = $0 }
      }
    }
  }

  var stackLayout: (columns: Int, size: CGSize) {
    Self.layout(
      count: apps.count, in: contentRect.size, maxWidth: Self.maxStackWidth, labelHeight: Self.stackLabelHeight)
  }

  var previewLayout: (columns: Int, size: CGSize) {
    let count = apps.first { $0.id == expandedApp }?.windows.count ?? 0
    return Self.layout(
      count: count, in: contentRect.size, maxWidth: Self.maxPreviewWidth, labelHeight: Self.previewLabelHeight)
  }

  static func layout(count: Int, in available: CGSize, maxWidth: CGFloat, labelHeight: CGFloat) -> (
    columns: Int, size: CGSize
  ) {
    guard count > 0 else { return (1, .zero) }
    let options = (1...count).map { rowCount in
      let columns = (count + rowCount - 1) / rowCount
      let rows = CGFloat(rowCount)
      let byWidth = available.width / CGFloat(columns) - 2 * previewInset
      let byHeight = (available.height / rows - 2 * previewInset - labelHeight) / previewAspect
      let width = max(96, (min(maxWidth, byWidth, byHeight) / 4).rounded(.down) * 4)
      return (columns: columns, size: CGSize(width: width, height: (width * previewAspect / 4).rounded(.down) * 4))
    }
    return options.max { ($0.size.width, $0.columns) < ($1.size.width, $1.columns) }!
  }

  static func cells(count: Int, columns: Int, slot: CGSize, labelHeight: CGFloat, in rect: CGRect) -> [CGRect] {
    let cell = CGSize(width: slot.width + 2 * previewInset, height: slot.height + labelHeight + 2 * previewInset)
    let rows = (count + columns - 1) / columns
    let top = rect.minY + ((rect.height - CGFloat(rows) * cell.height) / 8).rounded(.down) * 4
    return (0..<count).map { index in
      let row = index / columns
      let inRow = min(columns, count - row * columns)
      let left = rect.minX + ((rect.width - CGFloat(inRow) * cell.width) / 8).rounded(.down) * 4
      return CGRect(
        origin: CGPoint(x: left + CGFloat(index % columns) * cell.width, y: top + CGFloat(row) * cell.height),
        size: cell)
    }
  }

  static func fit(_ size: CGSize, in slot: CGRect) -> CGRect {
    let scale = min(slot.width / max(size.width, 1), slot.height / max(size.height, 1))
    let fitted = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    return CGRect(
      x: slot.midX - fitted.width / 2, y: slot.maxY - fitted.height, width: fitted.width, height: fitted.height)
  }

  public func close() {
    clickMonitor.map(NSEvent.removeMonitor)
    clickMonitor = nil
    expandTask?.cancel()
    refreshTask?.cancel()
    panel.orderOut(nil)
  }

  func dismiss(then finish: @escaping () -> Void = {}) {
    guard isPresented else { return }
    expandTask?.cancel()
    guard let motion else {
      close()
      finish()
      return
    }
    withAnimation(motion) {
      isPresented = false
    } completion: { [weak self] in
      self?.close()
      finish()
    }
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
    pickedWindow = id
    dismiss {
      AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
      if let element {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
      }
    }
  }

  func hover(_ app: SwitcherApp?) {
    expandTask?.cancel()
    guard let app else { return }
    selectedApp = app.id
    guard app.windows.count > 1, NSEvent.mouseLocation != collapsePoint else { return }
    expandTask = Task { [weak self] in
      try? await Task.sleep(for: Self.expandDelay)
      guard !Task.isCancelled else { return }
      self?.expand(app)
    }
  }

  func expand(_ app: SwitcherApp) {
    expandTask?.cancel()
    withAnimation(motion) {
      expandedApp = app.id
      selectedWindow = nil
    }
  }

  func collapse() {
    withAnimation(motion) {
      expandedApp = nil
      selectedWindow = nil
    }
    collapsePoint = NSEvent.mouseLocation
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
      if expanded == nil { dismiss() } else { collapse() }
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
        expand(selected)
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
      let columns = stackLayout.columns
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
    let mainIDs = Set(apps.map(\.recentWindowID))
    let windows = apps.flatMap(\.windows).compactMap { window in content.windows.first { $0.windowID == window.id } }
    for pass in [windows.filter { mainIDs.contains($0.windowID) }, windows.filter { !mainIDs.contains($0.windowID) }] {
      let captures = pass.map { window in
        Task {
          let configuration = SCStreamConfiguration()
          let maxHeight = Self.maxPreviewWidth * Self.previewAspect
          let fit =
            scale * min(1, Self.maxPreviewWidth / max(window.frame.width, 1), maxHeight / max(window.frame.height, 1))
          configuration.width = Int(window.frame.width * fit)
          configuration.height = Int(window.frame.height * fit)
          configuration.showsCursor = false
          let filter = SCContentFilter(desktopIndependentWindow: window)
          let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
          image.map { thumbnails[window.windowID] = $0 }
        }
      }
      for capture in captures { await capture.value }
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

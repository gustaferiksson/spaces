import AppKit
import ColorSync
import Observation
import SpacesCore
import SwiftUI

extension NSScreen {
  var cornerDisplayIdentifier: String? {
    guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
      let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
  }
}

@MainActor
final class ScreenCornersController {
  private let settings: AppSettings
  private var panels: [NSPanel] = []
  private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

  init(settings: AppSettings) { self.settings = settings }

  func start() {
    observeSettings()
    for (center, name) in [
      (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
      (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
      (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
    ] {
      let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.refresh() }
      }
      observers.append((center, observer))
    }
  }

  isolated deinit {
    for (center, observer) in observers { center.removeObserver(observer) }
    panels.forEach { $0.close() }
  }

  private func observeSettings() {
    withObservationTracking {
      refresh()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeSettings() }
    }
  }

  private func refresh() {
    panels.forEach { $0.close() }
    panels.removeAll()
    guard settings.screenCornersEnabled else { return }
    for screen in NSScreen.screens {
      guard let id = screen.cornerDisplayIdentifier else { continue }
      let style = settings.screenCornerStyles[id] ?? ScreenCornerStyle()
      let fullScreen = SpaceLayout.current(displayIdentifier: id).map { $0.desktopNumber == nil } ?? false
      let radius = style.radius(fullScreen: fullScreen, width: screen.frame.width, height: screen.frame.height)
      guard radius > 0 else { continue }
      let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.isReleasedWhenClosed = false
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.ignoresMouseEvents = true
      panel.hidesOnDeactivate = false
      panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
      panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
      panel.contentView = NSHostingView(rootView: ScreenCornerMask(style: style, radius: radius))
      panel.setFrame(screen.frame, display: true)
      panel.orderFrontRegardless()
      panels.append(panel)
    }
  }
}

struct ScreenCornerMask: View {
  let style: ScreenCornerStyle
  let radius: CGFloat

  var body: some View {
    GeometryReader { geometry in
      let rounded = UnevenRoundedRectangle(
        topLeadingRadius: style.topLeft ? radius : 0,
        bottomLeadingRadius: style.bottomLeft ? radius : 0,
        bottomTrailingRadius: style.bottomRight ? radius : 0,
        topTrailingRadius: style.topRight ? radius : 0,
        style: style.continuous ? .continuous : .circular)
      Path { path in
        let bounds = CGRect(origin: .zero, size: geometry.size)
        path.addRect(bounds)
        path.addPath(rounded.path(in: bounds))
      }
      .fill(.black, style: FillStyle(eoFill: true))
    }
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityHidden(true)
  }
}

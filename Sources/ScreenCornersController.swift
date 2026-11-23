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
  private var overlays: [String: (panel: NSPanel, content: NSHostingView<ScreenCornerMask>)] = [:]
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
    overlays.values.forEach { $0.panel.close() }
  }

  private func observeSettings() {
    withObservationTracking {
      refresh()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in self?.observeSettings() }
    }
  }

  private func refresh() {
    var visibleDisplays: Set<String> = []
    let screens = settings.screenCornersEnabled ? NSScreen.screens : []
    for screen in screens {
      guard let id = screen.cornerDisplayIdentifier else { continue }
      let style = settings.screenCornerStyles[id] ?? ScreenCornerStyle()
      let radius = style.radius(for: screen.frame.size)
      guard radius > 0, style.topLeft || style.topRight || style.bottomLeft || style.bottomRight else { continue }
      visibleDisplays.insert(id)
      let mask = ScreenCornerMask(style: style, radius: radius)
      if let (panel, content) = overlays[id] {
        if content.rootView != mask { content.rootView = mask }
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
      } else {
        let content = NSHostingView(rootView: mask)
        overlays[id] = (makePanel(frame: screen.frame, content: content), content)
      }
    }
    for id in Set(overlays.keys).subtracting(visibleDisplays) {
      overlays.removeValue(forKey: id)?.panel.close()
    }
  }

  private func makePanel(frame: CGRect, content: NSHostingView<ScreenCornerMask>) -> NSPanel {
    let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    panel.contentView = content
    panel.setFrame(frame, display: true)
    panel.orderFrontRegardless()
    return panel
  }
}

struct ScreenCornerMask: View, Equatable {
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

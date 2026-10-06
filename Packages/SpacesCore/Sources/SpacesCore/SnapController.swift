import AppKit
import SwiftUI

@MainActor
public final class SnapController {
  private let mover: WindowMover
  private let isEnabled: () -> Bool
  private let actionForZone: (SnapZone) -> WindowAction?
  private let overlay = SnapOverlay()
  private var monitor: Any?
  private var drag: (window: AXUIElement, original: CGRect, isMoving: Bool)?
  private var target: (action: WindowAction, screen: NSScreen)?

  public init(
    mover: WindowMover, isEnabled: @escaping () -> Bool, actionForZone: @escaping (SnapZone) -> WindowAction?
  ) {
    self.mover = mover
    self.isEnabled = isEnabled
    self.actionForZone = actionForZone
    monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) {
      [weak self] event in
      let type = event.type
      MainActor.assumeIsolated { self?.handle(type) }
    }
  }

  isolated deinit {
    monitor.map(NSEvent.removeMonitor)
  }

  private func handle(_ type: NSEvent.EventType) {
    if type == .leftMouseDown {
      drag = isEnabled() ? WindowMover.window(at: NSEvent.mouseLocation).map { ($0.window, $0.frame, false) } : nil
    } else if type == .leftMouseDragged {
      dragged()
    } else if type == .leftMouseUp {
      dropped()
    }
  }

  private func dragged() {
    guard let drag else { return }
    if !drag.isMoving {
      guard let frame = WindowMover.frame(of: drag.window), frame.origin != drag.original.origin,
        abs(frame.width - drag.original.width) < 1, abs(frame.height - drag.original.height) < 1
      else { return }
      self.drag?.isMoving = true
      if let restored = mover.unsnap(drag.window, placedAt: drag.original, grabbedAt: NSEvent.mouseLocation) {
        self.drag?.original = restored
      }
    }
    let mouse = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.insetBy(dx: -1, dy: -1).contains(mouse) }),
      let zone = SnapZone(point: mouse, in: screen.frame), let action = actionForZone(zone)
    else {
      target = nil
      overlay.hide()
      return
    }
    target = (action, screen)
    overlay.show(WindowLayout.frame(action, in: screen.visibleFrame, gap: mover.gap()), on: screen)
  }

  private func dropped() {
    defer {
      drag = nil
      target = nil
      overlay.hide()
    }
    guard let drag, drag.isMoving, let target else { return }
    mover.snap(drag.window, to: target.action, on: target.screen, from: drag.original)
  }
}

@MainActor
final class SnapOverlay {
  private let model = SnapOverlayModel()
  private let panel: NSPanel

  init() {
    panel = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
    panel.contentView = NSHostingView(rootView: SnapOverlayView(model: model))
  }

  func show(_ frame: CGRect, on screen: NSScreen) {
    if panel.frame != screen.frame { panel.setFrame(screen.frame, display: false) }
    let local = CGRect(
      x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    guard !model.isVisible || model.frame != local else { return }
    if !model.isVisible { model.frame = local }
    panel.orderFrontRegardless()
    withAnimation(.spring(duration: 0.25, bounce: 0.15)) {
      model.frame = local
      model.isVisible = true
    }
  }

  func hide() {
    guard model.isVisible else { return }
    withAnimation(.easeOut(duration: 0.15)) { model.isVisible = false }
  }
}

@MainActor
@Observable
final class SnapOverlayModel {
  var frame = CGRect.zero
  var isVisible = false
}

struct SnapOverlayView: View {
  let model: SnapOverlayModel

  var body: some View {
    Color.clear
      .glassEffect(.clear, in: .rect(cornerRadius: 24))
      .frame(width: model.frame.width, height: model.frame.height)
      .scaleEffect(model.isVisible ? 1 : 0.96)
      .opacity(model.isVisible ? 1 : 0)
      .position(x: model.frame.midX, y: model.frame.midY)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

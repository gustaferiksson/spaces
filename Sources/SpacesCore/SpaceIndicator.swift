import AppKit
import SwiftUI

@MainActor
public final class SpaceIndicator {
  private static let panelSize = CGSize(width: 320, height: 80)
  private static let menuBarGap: CGFloat = 8
  static let slideDistance: CGFloat = 12
  private static let holdDuration: Duration = .milliseconds(1200)

  private let model = IndicatorModel()
  private let panel: NSPanel
  private var hideTask: Task<Void, Never>?
  private var observer: (any NSObjectProtocol)?

  public init() {
    panel = NSPanel(
      contentRect: CGRect(origin: .zero, size: Self.panelSize), styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    panel.contentView = NSHostingView(rootView: IndicatorView(model: model))
    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, let layout = SpaceLayout.current() else { return }
        self.show(layout)
      }
    }
  }

  isolated deinit {
    observer.map { NSWorkspace.shared.notificationCenter.removeObserver($0) }
  }

  public func show(_ layout: SpaceLayout) {
    let title = layout.desktopNumber.map { "Desktop \($0)" } ?? NSWorkspace.shared.frontmostApplication?.localizedName
    guard let title else { return }

    let mouse = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    panel.setFrameOrigin(
      CGPoint(
        x: visible.midX - Self.panelSize.width / 2,
        y: visible.maxY - Self.menuBarGap - Self.panelSize.height + Self.slideDistance))
    panel.orderFrontRegardless()
    model.title = title
    withAnimation(.spring(duration: 0.2, bounce: 0.2)) { model.isVisible = true }

    hideTask?.cancel()
    hideTask = Task { [weak self] in
      try? await Task.sleep(for: Self.holdDuration)
      guard !Task.isCancelled, let self else { return }
      withAnimation(.easeOut(duration: 0.25)) { self.model.isVisible = false }
    }
  }
}

@MainActor
@Observable
final class IndicatorModel {
  var title = ""
  var isVisible = false
}

struct IndicatorView: View {
  let model: IndicatorModel

  var body: some View {
    Text(model.title)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(.primary)
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .glassEffect(.regular, in: .capsule)
      .scaleEffect(model.isVisible ? 1 : 0.85, anchor: .top)
      .offset(y: model.isVisible ? 0 : -SpaceIndicator.slideDistance)
      .opacity(model.isVisible ? 1 : 0)
      .padding(.top, SpaceIndicator.slideDistance)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}


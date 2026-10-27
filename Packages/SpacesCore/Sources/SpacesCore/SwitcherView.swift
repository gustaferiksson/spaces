import SwiftUI

public struct SwitcherView: View {
  let switcher: WindowSwitcher
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(switcher: WindowSwitcher) {
    self.switcher = switcher
  }

  public var body: some View {
    let presented = switcher.isPresented
    let expanded = switcher.apps.first { $0.id == switcher.expandedApp }
    let stackLayout = switcher.stackLayout
    let stackCells = WindowSwitcher.cells(
      count: switcher.apps.count, columns: stackLayout.columns, slot: stackLayout.size,
      labelHeight: WindowSwitcher.stackLabelHeight, in: switcher.contentRect)
    let previewLayout = switcher.previewLayout
    let previewCells = WindowSwitcher.cells(
      count: expanded?.windows.count ?? 0, columns: previewLayout.columns, slot: previewLayout.size,
      labelHeight: WindowSwitcher.previewLabelHeight, in: switcher.contentRect)
    let inset = WindowSwitcher.previewInset
    ZStack(alignment: .topLeading) {
      SwitcherBackdrop(switcher: switcher, dims: presented)
        .contentShape(.rect)
        .onTapGesture { expanded == nil ? switcher.dismiss() : switcher.collapse() }
      if switcher.apps.isEmpty {
        ContentUnavailableView(
          "No Windows on This Space", systemImage: "macwindow",
          description: Text("Open windows on this Space appear here, grouped by app.")
        )
        .frame(width: 360)
        .padding(16)
        .foregroundStyle(.white)
        .glassEffect(.regular.tint(.black.opacity(0.32)), in: .rect(cornerRadius: 24))
        .position(x: switcher.size.width / 2, y: switcher.size.height / 2)
        .opacity(presented ? 1 : 0)
      }
      ForEach(Array(switcher.apps.enumerated()), id: \.element.id) { index, app in
        let main = app.windows.first { $0.id == app.recentWindowID } ?? app.windows[0]
        let slot = CGRect(origin: stackCells[index].origin, size: stackLayout.size).offsetBy(dx: inset, dy: inset)
        SwitcherCell(
          frame: stackCells[index], face: WindowSwitcher.fit(main.frame.size, in: slot), depth: min(app.windows.count - 1, 2),
          title: main.title, isUntitled: main.isUntitled, subtitle: app.name, isSelected: switcher.selectedApp == app.id,
          accessibilityLabel: "\(app.name), \(app.windows.count == 1 ? "1 window" : "\(app.windows.count) windows")"
        ) {
          if app.windows.count == 1 { switcher.focus(app, window: main.id) } else { switcher.expand(app) }
        } hover: {
          switcher.hover($0 ? app : nil)
        }
        .accessibilityAction(named: "Show Windows") { switcher.expand(app) }
        .opacity(presented && expanded == nil ? 1 : 0)
        .allowsHitTesting(expanded == nil)
      }
      if let expanded {
        ForEach(Array(expanded.windows.enumerated()), id: \.element.id) { index, window in
          let slot = CGRect(origin: previewCells[index].origin, size: previewLayout.size).offsetBy(dx: inset, dy: inset)
          SwitcherCell(
            frame: previewCells[index], face: WindowSwitcher.fit(window.frame.size, in: slot), depth: 0,
            title: window.title, isUntitled: window.isUntitled, subtitle: nil,
            isSelected: switcher.selectedWindow == window.id, accessibilityLabel: window.title
          ) {
            switcher.focus(expanded, window: window.id)
          } hover: {
            if $0 { switcher.selectWindow(window.id) }
          }
          .opacity(presented ? 1 : 0)
        }
      }
      ZStack(alignment: .topLeading) {
        ForEach(Array(switcher.apps.enumerated()), id: \.element.id) { appIndex, app in
          ForEach(Array(app.windows.enumerated()), id: \.element.id) { index, window in
            let isExpanded = expanded?.id == app.id
            let cell = isExpanded ? previewCells[index] : stackCells[appIndex]
            let slot = CGRect(origin: cell.origin, size: isExpanded ? previewLayout.size : stackLayout.size)
              .offsetBy(dx: inset, dy: inset)
            let isShown = isExpanded || (expanded == nil && window.id == app.recentWindowID)
            let image = switcher.thumbnails[window.id]
            let isAtRest = presented || reduceMotion || image == nil
            let frame =
              isAtRest
              ? WindowSwitcher.fit(window.frame.size, in: slot)
              : window.frame.offsetBy(dx: -switcher.screenOrigin.x, dy: -switcher.screenOrigin.y)
            WindowFace(
              app: app, image: image, count: isExpanded ? 1 : app.windows.count, showsBadges: presented
            )
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .opacity(presented ? (isShown ? 1 : 0) : (isAtRest ? 0 : 1))
            .zIndex(window.id == switcher.pickedWindow ? 1 : -Double(window.depth) / 10_000)
          }
        }
      }
      .id(reduceMotion ? switcher.expandedApp : nil)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
    .frame(width: switcher.size.width, height: switcher.size.height, alignment: .topLeading)
    .opacity(reduceMotion && !presented ? 0 : 1)
    .allowsHitTesting(presented)
    .environment(\.colorScheme, .dark)
  }
}

private struct SwitcherBackdrop: View {
  let switcher: WindowSwitcher
  let dims: Bool

  var body: some View {
    let options = switcher.backdropOptions
    let scaling = (options[.imageScaling] as? NSNumber).flatMap { NSImageScaling(rawValue: $0.uintValue) }
    let stretches = scaling == .scaleAxesIndependently
    let fills = stretches || (scaling != .scaleNone && options[.allowClipping] as? Bool ?? true)
    ZStack {
      if let image = switcher.backdropURL.flatMap({ switcher.wallpapers[$0] }) {
        Color(nsColor: options[.fillColor] as? NSColor ?? .black)
        Image(decorative: image, scale: 1)
          .resizable()
          .aspectRatio(stretches ? switcher.size.width / switcher.size.height : nil, contentMode: fills ? .fill : .fit)
      } else {
        Rectangle().fill(.regularMaterial)
      }
      Color.black.opacity(dims ? 0.32 : 0)
    }
    .frame(width: switcher.size.width, height: switcher.size.height)
    .clipped()
  }
}

private struct SwitcherCell: View {
  let frame: CGRect
  let face: CGRect
  let depth: Int
  let title: String
  let isUntitled: Bool
  let subtitle: String?
  let isSelected: Bool
  let accessibilityLabel: String
  let action: () -> Void
  let hover: (Bool) -> Void

  var body: some View {
    let inset = WindowSwitcher.previewInset
    Button(action: action) {
      ZStack(alignment: .topLeading) {
        ForEach([2, 1].filter { depth >= $0 }, id: \.self) { level in
          RoundedRectangle(cornerRadius: 8)
            .fill(.white.opacity(level == 1 ? 0.32 : 0.16))
            .frame(width: face.width - 16 * CGFloat(level), height: face.height)
            .offset(x: face.minX - frame.minX + 8 * CGFloat(level), y: face.minY - frame.minY - 4 * CGFloat(level))
        }
        VStack(spacing: 0) {
          Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isUntitled ? .secondary : .primary)
          if let subtitle {
            Text(subtitle)
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .shadow(color: .black.opacity(0.5), radius: 4)
        .frame(width: frame.width - 2 * inset)
        .offset(x: inset, y: face.maxY - frame.minY + 8)
      }
      .frame(width: frame.width, height: frame.height, alignment: .topLeading)
      .background(isSelected ? Color.white.opacity(0.16) : .clear, in: .rect(cornerRadius: 16))
      .contentShape(.rect(cornerRadius: 16))
    }
    .buttonStyle(.plain)
    .focusEffectDisabled()
    .accessibilityLabel(accessibilityLabel)
    .onHover(perform: hover)
    .position(x: frame.midX, y: frame.midY)
  }
}

private struct WindowFace: View {
  let app: SwitcherApp
  let image: CGImage?
  let count: Int
  let showsBadges: Bool

  var body: some View {
    Group {
      if let image {
        Color.clear
          .overlay { Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill) }
          .overlay(alignment: .bottomLeading) {
            Image(nsImage: app.icon)
              .resizable()
              .frame(width: 32, height: 32)
              .shadow(color: .black.opacity(0.32), radius: 4)
              .padding(8)
              .opacity(showsBadges ? 1 : 0)
          }
      } else {
        Rectangle()
          .fill(Color(white: 0.2))
          .overlay {
            Image(nsImage: app.icon)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .frame(maxWidth: 96, maxHeight: 96)
              .padding(16)
          }
      }
    }
    .clipShape(.rect(cornerRadius: 8))
    .shadow(color: .black.opacity(0.32), radius: 8, y: 4)
    .overlay(alignment: .topTrailing) {
      if count > 1 {
        Text("\(count)")
          .font(.system(size: 11, weight: .semibold))
          .monospacedDigit()
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .background(.regularMaterial, in: .capsule)
          .offset(x: 8, y: -8)
          .opacity(showsBadges ? 1 : 0)
      }
    }
  }
}

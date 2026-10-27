import SwiftUI

struct SwitcherView: View {
  let switcher: WindowSwitcher

  var body: some View {
    let rows = stride(from: 0, to: switcher.apps.count, by: switcher.columns).map {
      Array(switcher.apps[$0..<min($0 + switcher.columns, switcher.apps.count)])
    }
    ZStack {
      Color.clear
        .contentShape(.rect)
        .onTapGesture { switcher.close() }
      GlassEffectContainer {
        if rows.isEmpty {
          ContentUnavailableView(
            "No Windows on This Space", systemImage: "macwindow",
            description: Text("Open windows on this Space appear here, grouped by app.")
          )
          .frame(width: 360)
          .padding(16)
          .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
          VStack(alignment: .leading, spacing: WindowSwitcher.tileSpacing) {
            ForEach(rows.indices, id: \.self) { row in
              HStack(spacing: WindowSwitcher.tileSpacing) {
                ForEach(rows[row].indices, id: \.self) { column in
                  let horizontal: HorizontalAlignment = column * 2 >= switcher.columns ? .trailing : .leading
                  let vertical: VerticalAlignment = rows.count > 1 && row * 2 >= rows.count ? .bottom : .top
                  SwitcherTile(
                    app: rows[row][column], switcher: switcher, anchor: Alignment(horizontal: horizontal, vertical: vertical))
                }
              }
              .zIndex(rows[row].contains { $0.id == switcher.expandedApp } ? 1 : 0)
            }
          }
          .padding(16)
          .glassEffect(.regular, in: .rect(cornerRadius: 24))
        }
      }
    }
  }
}

private struct SwitcherTile: View {
  let app: SwitcherApp
  let switcher: WindowSwitcher
  let anchor: Alignment

  var body: some View {
    let count = app.windows.count
    let isExpanded = switcher.expandedApp == app.id
    Button {
      switcher.focus(app, window: app.recentWindowID)
    } label: {
      VStack(spacing: 8) {
        ZStack(alignment: .bottom) {
          ForEach(Array([2, 1].filter { count > $0 }), id: \.self) { depth in
            RoundedRectangle(cornerRadius: 16)
              .fill(.primary.opacity(depth == 1 ? 0.24 : 0.12))
              .frame(width: 80 - 8 * CGFloat(depth), height: 80)
              .offset(y: -4 * CGFloat(depth))
          }
          Image(nsImage: app.icon)
            .resizable()
            .frame(width: 64, height: 64)
            .frame(width: 80, height: 80)
            .background(.thinMaterial, in: .rect(cornerRadius: 16))
            .overlay(alignment: .topTrailing) {
              if count > 1 {
                Text("\(count)")
                  .font(.system(size: 11, weight: .semibold))
                  .monospacedDigit()
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(.regularMaterial, in: .capsule)
                  .offset(x: 8, y: -8)
              }
            }
        }
        .frame(height: 88, alignment: .bottom)
        Text(app.name)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
          .truncationMode(.tail)
          .padding(.horizontal, 4)
      }
      .frame(width: WindowSwitcher.tileSize, height: WindowSwitcher.tileSize)
      .background(
        switcher.selectedApp == app.id ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 16))
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .onHover { if $0 { switcher.hoverBegan(app) } else { switcher.hoverEnded() } }
    .overlay(alignment: anchor) {
      if isExpanded {
        ExpandedStack(app: app, switcher: switcher, thumbnailFirst: anchor.horizontal == .trailing)
          .fixedSize()
      }
    }
    .zIndex(isExpanded ? 1 : 0)
    .accessibilityLabel("\(app.name), \(count == 1 ? "1 window" : "\(count) windows")")
    .accessibilityAction(named: "Show Windows") {
      guard count > 1 else { return }
      switcher.expandedApp = app.id
    }
  }
}

private struct ExpandedStack: View {
  private static let visibleRows = 12
  private static let rowHeight: CGFloat = 28

  let app: SwitcherApp
  let switcher: WindowSwitcher
  let thumbnailFirst: Bool

  var body: some View {
    let thumbnail = switcher.selectedWindow.flatMap { switcher.thumbnails[$0] }.map { image in
      Image(decorative: image, scale: 1)
        .resizable()
        .aspectRatio(contentMode: .fit)
        .frame(width: WindowSwitcher.thumbnailWidth)
        .clipShape(.rect(cornerRadius: 8))
        .padding(8)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
    HStack(alignment: .top, spacing: 8) {
      if thumbnailFirst { thumbnail }
      card
      if !thumbnailFirst { thumbnail }
    }
    .onHover { if !$0 { switcher.collapse() } }
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        switcher.focus(app, window: app.recentWindowID)
      } label: {
        HStack(spacing: 8) {
          Image(nsImage: app.icon)
            .resizable()
            .frame(width: 32, height: 32)
          Text(app.name)
            .font(.headline)
            .lineLimit(1)
          Spacer(minLength: 0)
        }
        .padding(8)
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      Divider()
        .padding(.horizontal, 8)
      ScrollView {
        VStack(spacing: 0) {
          ForEach(app.windows) { window in
            Button {
              switcher.focus(app, window: window.id)
            } label: {
              Text(window.title)
                .font(.system(size: 13))
                .foregroundStyle(window.isUntitled ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .frame(height: Self.rowHeight)
                .background(
                  switcher.selectedWindow == window.id ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { if $0 { switcher.selectWindow(window.id) } }
          }
        }
      }
      .scrollBounceBehavior(.basedOnSize)
      .frame(height: Self.rowHeight * CGFloat(min(app.windows.count, Self.visibleRows)))
    }
    .padding(8)
    .frame(width: 288)
    .background(.regularMaterial, in: .rect(cornerRadius: 20))
    .glassEffect(.regular, in: .rect(cornerRadius: 20))
  }
}

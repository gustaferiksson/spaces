import SwiftUI

public struct SwitcherView: View {
  let switcher: WindowSwitcher

  public init(switcher: WindowSwitcher) {
    self.switcher = switcher
  }

  public var body: some View {
    let rows = stride(from: 0, to: switcher.apps.count, by: switcher.columns).map {
      Array(switcher.apps[$0..<min($0 + switcher.columns, switcher.apps.count)])
    }
    ZStack(alignment: rows.isEmpty ? .center : .top) {
      Color.clear
        .contentShape(.rect)
        .onTapGesture { switcher.close() }
      Group {
        if rows.isEmpty {
          ContentUnavailableView(
            "No Windows on This Space", systemImage: "macwindow",
            description: Text("Open windows on this Space appear here, grouped by app.")
          )
          .frame(width: 360)
        } else {
          VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: WindowSwitcher.tileSpacing) {
              ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: WindowSwitcher.tileSpacing) {
                  ForEach(rows[row]) { SwitcherTile(app: $0, switcher: switcher) }
                }
              }
            }
            if let app = switcher.apps.first(where: { $0.id == switcher.expandedApp }) {
              WindowPreviews(app: app, switcher: switcher)
            }
          }
        }
      }
      .padding(16)
      .background(Color(nsColor: .windowBackgroundColor).opacity(0.9), in: .rect(cornerRadius: 24))
      .glassEffect(.regular, in: .rect(cornerRadius: 24))
      .contentShape(.rect(cornerRadius: 24))
      .onTapGesture {}
      .padding(.top, rows.isEmpty ? 0 : switcher.gridTop)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: rows.isEmpty ? .center : .top)
    }
  }
}

private struct SwitcherTile: View {
  let app: SwitcherApp
  let switcher: WindowSwitcher

  var body: some View {
    let count = app.windows.count
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
    .focusEffectDisabled()
    .accessibilityLabel("\(app.name), \(count == 1 ? "1 window" : "\(count) windows")")
    .accessibilityAction(named: "Show Windows") { switcher.expandedApp = app.id }
    .onHover { switcher.hover($0 ? app : nil) }
  }
}

private struct WindowPreviews: View {
  let app: SwitcherApp
  let switcher: WindowSwitcher

  var body: some View {
    let layout = switcher.previewLayout
    let cellWidth = layout.size.width + 2 * WindowSwitcher.previewInset
    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 0), count: layout.columns), spacing: 0) {
      ForEach(app.windows) { window in
        Button {
          switcher.focus(app, window: window.id)
        } label: {
          VStack(spacing: 8) {
            Group {
              if let image = switcher.thumbnails[window.id] {
                Image(decorative: image, scale: 1)
                  .resizable()
                  .aspectRatio(contentMode: .fit)
                  .clipShape(.rect(cornerRadius: 8))
              } else {
                RoundedRectangle(cornerRadius: 8)
                  .fill(.primary.opacity(0.08))
                  .overlay {
                    Image(nsImage: app.icon)
                      .resizable()
                      .aspectRatio(contentMode: .fit)
                      .frame(maxWidth: 64, maxHeight: 64)
                  }
              }
            }
            .frame(width: layout.size.width, height: layout.size.height)
            Text(window.title)
              .font(.system(size: 13))
              .foregroundStyle(window.isUntitled ? .secondary : .primary)
              .lineLimit(1)
              .truncationMode(.middle)
              .frame(width: layout.size.width, height: WindowSwitcher.previewTitleHeight - 8)
          }
          .padding(WindowSwitcher.previewInset)
          .background(
            switcher.selectedWindow == window.id ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 16))
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { if $0 { switcher.selectWindow(window.id) } }
      }
    }
    .fixedSize()
  }
}

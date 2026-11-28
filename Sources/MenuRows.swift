import SwiftUI

struct SpaceSwitchingRow: View {
  let engine: Engine
  let highlight: MenuHighlight

  var body: some View {
    MenuRow(isHighlighted: highlight.item == StatusMenu.spaceSwitchingItem) {
      BadgeRow(
        symbol: "rectangle.split.3x1.fill",
        title: "Instant Space Switching",
        subtitle: engine.spaceSwitchingEnabled ? "On" + (engine.desktopNumber.map { " · Desktop \($0)" } ?? "") : "Off",
        isOn: engine.spaceSwitchingEnabled
      )
    }
  }
}

struct WindowSnappingRow: View {
  let engine: Engine
  let settings: AppSettings
  let highlight: MenuHighlight

  var body: some View {
    MenuRow(isHighlighted: highlight.item == StatusMenu.windowSnappingItem) {
      BadgeRow(
        symbol: "rectangle.lefthalf.inset.filled",
        title: "Window Snapping",
        subtitle: engine.windowSnappingEnabled ? "On" + (settings.windowGap > 0 ? " · \(Int(settings.windowGap)) pt gap" : "") : "Off",
        isOn: engine.windowSnappingEnabled
      )
    }
  }
}

struct NoticeRow: View {
  var body: some View {
    MenuRow(isHighlighted: false) {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Image(systemName: "exclamationmark.triangle")
          .frame(width: StatusMenu.badgeSize)
          .accessibilityHidden(true)
        Text("Spaces needs Accessibility access to switch Spaces and move windows.")
          .fixedSize(horizontal: false, vertical: true)
      }
      .foregroundStyle(.secondary)
    }
  }
}

private struct BadgeRow: View {
  let symbol: String
  let title: String
  let subtitle: String
  let isOn: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: symbol)
        .resizable()
        .scaledToFit()
        .fontWeight(.semibold)
        .frame(width: 14, height: 14)
        .foregroundStyle(isOn ? Color.white : .primary)
        .frame(width: StatusMenu.badgeSize, height: StatusMenu.badgeSize)
        .background(isOn ? Color.accentColor : .primary.opacity(0.1), in: .circle)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        Text(title)
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct MenuRow<Content: View>: View {
  let isHighlighted: Bool
  @ViewBuilder let content: Content

  var body: some View {
    content
      .foregroundStyle(isHighlighted ? Color(nsColor: .selectedMenuItemTextColor) : .primary)
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(isHighlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear, in: .rect(cornerRadius: 8))
      .padding(.horizontal, 5)
      .frame(width: StatusMenu.width)
  }
}

import SpacesCore
import SwiftUI

struct ScreenCornersSettings: View {
  @Bindable var settings: AppSettings
  @State private var screens = NSScreen.screens

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $settings.screenCornersEnabled) {
          Text("Round screen corners")
          Text("Cover the screen corners with black curves. Changes apply immediately.")
        }
      }
      ForEach(screens, id: \.cornerDisplayIdentifier) { screen in
        if let id = screen.cornerDisplayIdentifier {
          displaySection(screen, id: id)
        }
      }
    }
    .formStyle(.grouped)
    .frame(height: 680)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
      screens = NSScreen.screens
    }
  }

  private func displaySection(_ screen: NSScreen, id: String) -> some View {
    let style = Binding(
      get: { settings.screenCornerStyles[id] ?? ScreenCornerStyle() },
      set: { settings.screenCornerStyles[id] = $0 })
    return Section {
      ScreenCornersPreview(style: style)
        .disabled(!style.wrappedValue.enabled)
      Toggle("Enable on this display", isOn: style.enabled)
      Group {
        radiusSlider("Desktop radius", value: style.desktopRadius)
        radiusSlider("Fullscreen radius", value: style.fullScreenRadius)
        Picker("Shape", selection: style.continuous) {
          Text("Continuous").tag(true)
          Text("Circular").tag(false)
        }
        HStack {
          Toggle("Top left", isOn: style.topLeft)
          Toggle("Top right", isOn: style.topRight)
        }
        HStack {
          Toggle("Bottom left", isOn: style.bottomLeft)
          Toggle("Bottom right", isOn: style.bottomRight)
        }
      }
      .disabled(!style.wrappedValue.enabled)
    } header: {
      Text(screen.localizedName)
    } footer: {
      Text("Set a radius to 0 to keep that context square. Settings are saved for this display, including when it is disconnected.")
    }
    .disabled(!settings.screenCornersEnabled)
  }

  private func radiusSlider(_ title: String, value: Binding<Double>) -> some View {
    LabeledContent(title) {
      Slider(value: value, in: 0...100, step: 1)
        .accessibilityLabel(title)
      Text("\(Int(value.wrappedValue)) pt")
        .monospacedDigit()
        .frame(width: 48, alignment: .trailing)
    }
  }
}

private struct ScreenCornersPreview: View {
  @Binding var style: ScreenCornerStyle
  @State private var fullScreen = false

  var body: some View {
    VStack(spacing: 14) {
      Picker("Preview", selection: $fullScreen) {
        Text("Desktop").tag(false)
        Text("Fullscreen").tag(true)
      }
      .pickerStyle(.segmented)
      .frame(width: 240)

      ZStack {
        LinearGradient(
          colors: [Color(red: 0.12, green: 0.23, blue: 0.52), Color(red: 0.43, green: 0.36, blue: 0.72),
                   Color(red: 0.89, green: 0.58, blue: 0.61)],
          startPoint: .topLeading, endPoint: .bottomTrailing)
        Circle()
          .fill(.white.opacity(0.12))
          .frame(width: 180, height: 180)
          .offset(x: 120, y: 85)
          .blur(radius: 12)
        if fullScreen {
          Image(systemName: "play.rectangle.fill")
            .font(.system(size: 48, weight: .ultraLight))
            .foregroundStyle(.white.opacity(0.8))
        } else {
          VStack(spacing: 0) {
            HStack(spacing: 5) {
              ForEach([Color.red, .yellow, .green], id: \.self) { color in
                Circle().fill(color.opacity(0.9)).frame(width: 6, height: 6)
              }
              Spacer()
              Text("Spaces").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
              Spacer()
            }
            .padding(9)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
              RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.12)).frame(width: 72, height: 7)
              RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.06)).frame(height: 5)
              RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.06)).frame(width: 100, height: 5)
            }
            .padding(14)
            Spacer(minLength: 0)
          }
          .frame(width: 170, height: 110)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
          .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.4)))
          .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
          VStack {
            Rectangle().fill(.white.opacity(0.15)).frame(height: 12)
            Spacer()
            RoundedRectangle(cornerRadius: 9).fill(.ultraThinMaterial).frame(width: 130, height: 22)
              .padding(.bottom, 7)
          }
        }
        ScreenCornerMask(
          style: style,
          radius: style.radius(fullScreen: fullScreen, width: 1440, height: 900) * 0.4)
        VStack {
          HStack {
            cornerButton("Top left", value: $style.topLeft)
            Spacer()
            cornerButton("Top right", value: $style.topRight)
          }
          Spacer()
          HStack {
            cornerButton("Bottom left", value: $style.bottomLeft)
            Spacer()
            cornerButton("Bottom right", value: $style.bottomRight)
          }
        }
        .padding(14)
        .environment(\.layoutDirection, .leftToRight)
      }
      .frame(width: 360, height: 210)
      .clipped()
      .overlay(Rectangle().strokeBorder(.white.opacity(0.15)))
      .background(.black)
      .shadow(color: .black.opacity(0.16), radius: 10, y: 4)

      Text("Click a corner to turn its curve on or off.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
  }

  private func cornerButton(_ title: String, value: Binding<Bool>) -> some View {
    Button { value.wrappedValue.toggle() } label: {
      Image(systemName: value.wrappedValue ? "checkmark.square.fill" : "square")
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(value.wrappedValue ? Color.accentColor : .white.opacity(0.8))
        .background(.white.opacity(value.wrappedValue ? 0.9 : 0.15), in: RoundedRectangle(cornerRadius: 4))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(title)
    .accessibilityValue(value.wrappedValue ? "Rounded" : "Square")
  }
}

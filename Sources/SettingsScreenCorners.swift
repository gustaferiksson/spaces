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
      Toggle("Enable on this display", isOn: style.enabled)
      ScreenCornersPreview(style: style, displaySize: screen.frame.size)
        .disabled(!style.wrappedValue.enabled)
      Group {
        radiusSlider("Desktop radius", value: style.desktopRadius)
        radiusSlider("Fullscreen radius", value: style.fullScreenRadius)
        Picker("Shape", selection: style.continuous) {
          Text("Continuous").tag(true)
          Text("Circular").tag(false)
        }
      }
      .disabled(!style.wrappedValue.enabled)
    } header: {
      Text(screen.localizedName)
    } footer: {
      Text("Set either radius to 0 to leave all corners square in that mode.")
    }
    .disabled(!settings.screenCornersEnabled)
  }

  private func radiusSlider(_ title: String, value: Binding<Double>) -> some View {
    LabeledContent(title) {
      Slider(value: value, in: 0...100)
        .accessibilityLabel(title)
      Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(0)))) pt")
        .monospacedDigit()
        .frame(width: 48, alignment: .trailing)
    }
  }
}

private struct ScreenCornersPreview: View {
  @Binding var style: ScreenCornerStyle
  let displaySize: CGSize
  @State private var fullScreen = false

  var body: some View {
    VStack(spacing: 10) {
      Picker("Preview", selection: $fullScreen) {
        Text("Desktop").tag(false)
        Text("Fullscreen").tag(true)
      }
      .labelsHidden()
      .pickerStyle(.segmented)
      .frame(maxWidth: 220)

      Color.clear
        .aspectRatio(displaySize.width / displaySize.height, contentMode: .fit)
        .overlay {
          GeometryReader { geometry in
            let size = geometry.size
            let scale = size.width / displaySize.width
            let radius = style.radius(fullScreen: fullScreen, width: displaySize.width, height: displaySize.height)
            ZStack {
              wallpaper
              if fullScreen {
                Image(systemName: "play.rectangle")
                  .font(.system(size: min(size.width, size.height) * 0.25, weight: .light))
                  .foregroundStyle(.white.opacity(0.8))
                  .accessibilityHidden(true)
              } else {
                desktopDetails(size: size)
                  .accessibilityHidden(true)
              }
              ScreenCornerMask(style: style, radius: radius * scale)
                .allowsHitTesting(false)
            }
            .clipped()
            .overlay { Rectangle().strokeBorder(.white.opacity(0.2)).allowsHitTesting(false) }
            .overlay(alignment: .topLeading) { cornerButton("Top left", value: $style.topLeft) }
            .overlay(alignment: .topTrailing) { cornerButton("Top right", value: $style.topRight) }
            .overlay(alignment: .bottomLeading) { cornerButton("Bottom left", value: $style.bottomLeft) }
            .overlay(alignment: .bottomTrailing) { cornerButton("Bottom right", value: $style.bottomRight) }
            .environment(\.layoutDirection, .leftToRight)
          }
        }
        .frame(maxWidth: 400, maxHeight: 180)
        .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
  }

  private var wallpaper: some View {
    LinearGradient(
      colors: [
        Color(red: 0.12, green: 0.23, blue: 0.52),
        Color(red: 0.43, green: 0.36, blue: 0.72),
        Color(red: 0.89, green: 0.58, blue: 0.61),
      ],
      startPoint: .topLeading,
      endPoint: .bottomTrailing)
  }

  private func desktopDetails(size: CGSize) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 8)
        .fill(.regularMaterial)
        .overlay(alignment: .topLeading) {
          HStack(spacing: 4) {
            ForEach([Color.red, .yellow, .green], id: \.self) { color in
              Circle().fill(color).frame(width: 4, height: 4)
            }
          }
          .padding(6)
        }
        .frame(width: size.width * 0.42, height: size.height * 0.48)
        .shadow(color: .black.opacity(0.2), radius: 5, y: 3)

      VStack {
        Rectangle().fill(.white.opacity(0.15)).frame(height: size.height * 0.06)
        Spacer()
        Capsule().fill(.ultraThinMaterial)
          .frame(width: size.width * 0.3, height: size.height * 0.09)
          .padding(.bottom, 5)
      }
    }
  }

  private func cornerButton(_ title: String, value: Binding<Bool>) -> some View {
    Button {
      value.wrappedValue.toggle()
    } label: {
      RoundedRectangle(cornerRadius: 5)
        .fill(value.wrappedValue ? Color.accentColor : Color.black.opacity(0.38))
        .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.7)) }
        .overlay {
          Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .opacity(value.wrappedValue ? 1 : 0)
        }
        .frame(width: 18, height: 18)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(4)
    .accessibilityLabel(title)
    .accessibilityValue(value.wrappedValue ? "Rounded" : "Square")
    .help(title)
  }
}

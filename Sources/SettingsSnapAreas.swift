import SpacesCore
import SwiftUI

private let zoneTitles: [(zone: SnapZone, title: String)] = [
  (.left, "Left edge"),
  (.right, "Right edge"),
  (.top, "Top edge"),
  (.bottom, "Bottom edge"),
  (.topLeft, "Top-left corner"),
  (.topRight, "Top-right corner"),
  (.bottomLeft, "Bottom-left corner"),
  (.bottomRight, "Bottom-right corner"),
]

private let actionTitles: [(action: WindowAction, title: String)] = [
  (.leftHalf, "Left Half"),
  (.rightHalf, "Right Half"),
  (.topHalf, "Top Half"),
  (.bottomHalf, "Bottom Half"),
  (.topLeft, "Top-Left Quarter"),
  (.topRight, "Top-Right Quarter"),
  (.bottomLeft, "Bottom-Left Quarter"),
  (.bottomRight, "Bottom-Right Quarter"),
  (.maximize, "Maximize"),
  (.firstThird, "First Third"),
  (.centerThird, "Center Third"),
  (.lastThird, "Last Third"),
  (.firstTwoThirds, "First Two Thirds"),
  (.lastTwoThirds, "Last Two Thirds"),
]

struct SnapAreasSettings: View {
  @Bindable var settings: AppSettings
  @Environment(Engine.self) private var engine
  @State private var macOSTiles = UserDefaults(suiteName: "com.apple.WindowManager")?
    .object(forKey: "EnableTilingByEdgeDrag") as? Bool ?? true

  var body: some View {
    @Bindable var engine = engine
    Form {
      Section {
        Toggle(isOn: $engine.windowSnappingEnabled) {
          Text("Window snapping")
          Text("Move windows with shortcuts and by dragging them to a screen edge, where a preview shows where they'll go.")
        }
      }

      Section {
        LabeledContent {
          HStack(spacing: 4) {
            TextField(
              "Window gap",
              value: Binding(get: { settings.windowGap }, set: { settings.windowGap = min(max($0.rounded(), 0), 32) }),
              format: .number
            )
            .labelsHidden()
            .multilineTextAlignment(.trailing)
            .frame(width: 48)
            Text("pt")
              .foregroundStyle(.secondary)
            Stepper("Window gap", value: $settings.windowGap, in: 0...32, step: 1)
              .labelsHidden()
          }
        } label: {
          Text("Window gap")
          Text("Space around snapped windows and between neighbouring ones.")
        }
      }
      .disabled(!settings.windowSnappingEnabled)

      Section {
        ForEach(zoneTitles, id: \.zone) { zone, title in
          Picker(title, selection: $settings.snapActions[zone]) {
            Text("Off").tag(WindowAction?.none)
            Divider()
            ForEach(actionTitles, id: \.action) { action, title in
              Text(title).tag(WindowAction?.some(action))
            }
          }
        }
      } header: {
        Text("Snap Areas")
      }
      .disabled(!settings.windowSnappingEnabled)

      if macOSTiles {
        Section {
          LabeledContent {
            Button("Open Desktop & Dock…") {
              NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
            }
          } label: {
            Text("macOS also tiles dragged windows")
            Text("Turn off Drag windows to screen edges to tile under Windows, or both will act on the same drag.")
          }
        }
      }

      Section {
        HStack {
          Spacer()
          Button("Restore Defaults") { settings.snapActions = defaultSnapActions }
            .disabled(settings.snapActions == defaultSnapActions)
        }
      }
    }
    .formStyle(.grouped)
    .frame(height: macOSTiles ? 644 : 548)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      macOSTiles =
        UserDefaults(suiteName: "com.apple.WindowManager")?.object(forKey: "EnableTilingByEdgeDrag") as? Bool ?? true
    }
  }
}

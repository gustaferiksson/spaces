import SpacesCore
import SwiftUI

private let cornerTitles: [(corner: ScreenCorner, title: String)] = [
  (.topLeft, "Top-Left"),
  (.topRight, "Top-Right"),
  (.bottomLeft, "Bottom-Left"),
  (.bottomRight, "Bottom-Right"),
]

struct SwitcherSettings: View {
  @Bindable var settings: AppSettings
  @Environment(Engine.self) private var engine
  @AppStorage("requestedScreenRecording") private var requestedScreenRecording = false
  @State private var canRecordScreen = CGPreflightScreenCaptureAccess()
  @State private var macOSCorners = Set(ScreenCorner.allCases.filter { macOSHotCornerAction($0) != nil })
  @State private var contentHeight: CGFloat = 0

  var body: some View {
    @Bindable var engine = engine
    let cornerConflicts = settings.windowSwitcherEnabled && settings.switcherCorner.map(macOSCorners.contains) ?? false
    Form {
      Section {
        Toggle(isOn: $engine.windowSwitcherEnabled) {
          Text("Window switcher")
          Text("Show the apps with windows on this Space and previews of their windows, from a hot corner or a shortcut.")
        }
      }

      Section {
        Picker("Hot corner", selection: $engine.switcherCorner) {
          Text("Off").tag(ScreenCorner?.none)
          Divider()
          ForEach(cornerTitles, id: \.corner) { corner, title in
            Text(title).tag(ScreenCorner?.some(corner))
          }
        }
        ShortcutRow(title: "Shortcut", action: .windowSwitcher)
      } footer: {
        if settings.switcherCorner == nil && settings.shortcuts[.windowSwitcher] == nil {
          Text("Choose a hot corner or shortcut to open it.")
        }
      }
      .disabled(!settings.windowSwitcherEnabled)

      if cornerConflicts {
        Section {
          LabeledContent {
            Button("Open Desktop & Dock…") {
              NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
            }
          } label: {
            Text("macOS also uses this corner")
            Text("Set it to - under Hot Corners, or both will open.")
          }
        }
      }

      Section {
        LabeledContent {
          if canRecordScreen {
            Label("Allowed", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.secondary)
          } else {
            Button("Allow…", action: requestScreenRecording)
          }
        } label: {
          Text("Window previews")
          Text(
            canRecordScreen
              ? "Shows a live preview of each window."
              : "Strongly recommended. Without Screen Recording access, windows show as title cards. After allowing it, quit and reopen Spaces.")
        }
      }
    }
    .formStyle(.grouped)
    .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height.rounded(.up) } action: { contentHeight = $1 }
    .frame(minHeight: contentHeight)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      canRecordScreen = CGPreflightScreenCaptureAccess()
      macOSCorners = Set(ScreenCorner.allCases.filter { macOSHotCornerAction($0) != nil })
    }
  }

  private func requestScreenRecording() {
    guard requestedScreenRecording else {
      requestedScreenRecording = true
      canRecordScreen = CGRequestScreenCaptureAccess()
      return
    }
    NSWorkspace.shared.open(
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
  }
}

import SwiftUI

@main
struct SpacesApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Bindable private var settings = AppSettings.shared

  var body: some Scene {
    MenuBarExtra(isInserted: $settings.showMenuBarIcon) {
      Toggle("Instant Space Switching", isOn: Bindable(appDelegate.engine).spaceSwitchingEnabled)
      Toggle("Window Snapping", isOn: Bindable(appDelegate.engine).windowSnappingEnabled)
      Divider()
      if !appDelegate.engine.isTrusted {
        Button("Allow Accessibility Access…") { NSWorkspace.shared.open(accessibilitySettingsURL) }
        Divider()
      }
      UpdateMenuItems(updater: appDelegate.updater)
      SettingsLink { Text("Settings…") }
        .keyboardShortcut(",")
      Button("Quit Spaces") { NSApp.terminate(nil) }
        .keyboardShortcut("q")
    } label: {
      if settings.showDesktopInMenuBar, let desktop = appDelegate.engine.desktopNumber {
        Image(nsImage: desktopLabelImage(desktop))
      } else {
        Image(systemName: "rectangle.split.3x1")
      }
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SettingsView(settings: settings)
        .environment(appDelegate.engine)
        .environment(appDelegate.updater)
    }
  }
}

// MenuBarExtra flattens its label to plain title text, dropping .font and .monospacedDigit.
private func desktopLabelImage(_ desktop: Int) -> NSImage {
  let title = NSAttributedString(
    string: "Desktop \(desktop)",
    attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)]
  )
  let size = title.size()
  let image = NSImage(size: NSSize(width: size.width.rounded(.up), height: size.height.rounded(.up)), flipped: false) { rect in
    title.draw(in: rect)
    return true
  }
  image.isTemplate = true
  image.accessibilityDescription = title.string
  return image
}

let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

private struct UpdateMenuItems: View {
  let updater: AppUpdater

  var body: some View {
    if let staged = updater.staged {
      Button("Install Spaces \(staged.version) and Relaunch", action: updater.installAndRelaunch)
    } else {
      Button(checkTitle) { updater.check(.manual) }
        .disabled(updater.isBusy)
    }
    if let note {
      Text(note)
    }
  }

  private var checkTitle: String {
    if updater.status == .checking { return "Checking for Updates…" }
    if updater.status == .downloading { return "Downloading Update…" }
    return "Check for Updates…"
  }

  private var note: String? {
    if case .upToDate(let version) = updater.status { return "Spaces \(version) is the latest version." }
    if case .blocked(let message) = updater.status { return message }
    if case .failed(let message) = updater.status { return message }
    return nil
  }
}

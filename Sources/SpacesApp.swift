import SwiftUI

@main
struct SpacesApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @Bindable private var settings = AppSettings.shared

  var body: some Scene {
    Settings {
      SettingsView(settings: settings)
        .environment(appDelegate.engine)
        .environment(appDelegate.updater)
    }
  }
}

let accessibilitySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

import SwiftUI

enum SettingsTab: String {
  case general, shortcuts, snapAreas, switcher, about
}

struct SettingsView: View {
  @Bindable var settings: AppSettings
  @AppStorage("settingsTab") private var tab = SettingsTab.general

  var body: some View {
    TabView(selection: $tab) {
      Tab("General", systemImage: "gearshape", value: .general) {
        GeneralSettings(settings: settings)
      }
      Tab("Shortcuts", systemImage: "keyboard", value: .shortcuts) {
        ShortcutsSettings(settings: settings)
      }
      Tab("Snap Areas", systemImage: "rectangle.split.2x1", value: .snapAreas) {
        SnapAreasSettings(settings: settings)
      }
      Tab("Window Switcher", systemImage: "square.grid.2x2", value: .switcher) {
        SwitcherSettings(settings: settings)
      }
      Tab("About", systemImage: "info.circle", value: .about) {
        AboutSettings()
      }
    }
    .frame(minWidth: 560)
    .windowResizeBehavior(.enabled)
    .onAppear {
      // Without a Dock icon, macOS leaves the menu bar blank after a Space switch while Settings is key.
      NSApp.setActivationPolicy(.regular)
      NSApp.activate()
    }
    .onDisappear { NSApp.setActivationPolicy(.accessory) }
  }
}

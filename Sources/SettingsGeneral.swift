import ServiceManagement
import SwiftUI

struct GeneralSettings: View {
  @Bindable var settings: AppSettings
  @Environment(Engine.self) private var engine
  @Environment(AppUpdater.self) private var updater
  @State private var loginStatus = SMAppService.mainApp.status
  @State private var loginError: String?

  var body: some View {
    @Bindable var engine = engine
    Form {
      Section {
        Toggle(isOn: $engine.spaceSwitchingEnabled) {
          Text("Instant Space switching")
          Text("Switch to the previous or next Space with a shortcut, without the slide animation.")
        }
        Toggle(isOn: $engine.windowSnappingEnabled) {
          Text("Window snapping")
          Text("Move windows with shortcuts and by dragging them to a screen edge.")
        }
      }

      Section {
        LabeledContent {
          if engine.isTrusted {
            Label("Allowed", systemImage: "checkmark.circle.fill")
              .foregroundStyle(.secondary)
          } else {
            Button("Open Accessibility Settings…") { NSWorkspace.shared.open(accessibilitySettingsURL) }
          }
        } label: {
          Text("Accessibility access")
          Text("Spaces needs it to switch Spaces and move windows. It starts working as soon as you allow it.")
        }
      }

      Section {
        Toggle("Launch at login", isOn: Binding(
          get: { loginStatus == .enabled || loginStatus == .requiresApproval },
          set: setLaunchAtLogin
        ))
        if loginStatus == .requiresApproval {
          LabeledContent {
            Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
          } label: {
            Text("Approval needed")
            Text("Allow Spaces in System Settings to finish turning this on.")
          }
        }
        if let loginError {
          Text(loginError)
            .font(.callout)
            .foregroundStyle(.red)
        }
      }

      Section {
        Toggle("Show menu bar icon", isOn: $settings.showMenuBarIcon)
        Toggle("Show the current Desktop instead of the icon", isOn: $settings.showDesktopInMenuBar)
          .disabled(!settings.showMenuBarIcon)
      } header: {
        Text("Menu Bar")
      } footer: {
        Text("When hidden, open Spaces again to show Settings.")
      }

      Section {
        LabeledContent {
          Button("Open Keyboard Shortcuts…") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!)
          }
        } label: {
          Text("Turn off the built-in Space shortcuts")
          Text("Untick Move left a space and Move right a space under Mission Control, so macOS doesn't take ⌃← and ⌃→ first.")
        }
      } header: {
        Text("Switching Spaces")
      }

      Section("Updates") {
        LabeledContent("Version", value: AppUpdater.currentVersion)
        HStack(spacing: 8) {
          updateStatus
          Spacer()
          if updater.isBusy {
            ProgressView()
              .controlSize(.small)
              .accessibilityLabel(updater.status == .checking ? "Checking" : "Downloading")
          }
          if let staged = updater.staged {
            Button("Install Spaces \(staged.version) and Relaunch", action: updater.installAndRelaunch)
          } else {
            Button("Check for Updates") { updater.check(.manual) }
              .disabled(updater.isBusy)
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(height: 680)
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      loginStatus = SMAppService.mainApp.status
    }
  }

  @ViewBuilder private var updateStatus: some View {
    if updater.status == .checking {
      Text("Checking for updates…").font(.callout).foregroundStyle(.secondary)
    } else if updater.status == .downloading {
      Text("Downloading the update…").font(.callout).foregroundStyle(.secondary)
    } else if case .upToDate(let version) = updater.status {
      Text("Spaces \(version) is the latest version.").font(.callout).foregroundStyle(.secondary)
    } else if case .ready(let version) = updater.status {
      Text("Spaces \(version) is ready to install.").font(.callout)
    } else if case .blocked(let message) = updater.status {
      Text(message).font(.callout).foregroundStyle(.orange)
    } else if case .failed(let message) = updater.status {
      Text(message).font(.callout).foregroundStyle(.red)
    }
  }

  private func setLaunchAtLogin(_ isOn: Bool) {
    do {
      if isOn { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
      loginError = nil
    } catch {
      loginError = "Couldn't change Launch at login: \(error.localizedDescription)"
    }
    loginStatus = SMAppService.mainApp.status
  }
}

import Carbon.HIToolbox
import SpacesCore
import SwiftUI

struct ShortcutsSettings: View {
  @Bindable var settings: AppSettings
  @Environment(Engine.self) private var engine

  var body: some View {
    Form {
      Section("Spaces") {
        ShortcutRow(title: "Previous Space", action: .previousSpace)
        ShortcutRow(title: "Next Space", action: .nextSpace)
        ShortcutRow(title: "Toggle Control Center", action: .controlCenter)
      }

      Section {
        ShortcutRow(title: "Left Half", action: .leftHalf)
        ShortcutRow(title: "Right Half", action: .rightHalf)
        ShortcutRow(title: "Maximize", action: .maximize)
        ShortcutRow(title: "First Third", action: .firstThird)
        ShortcutRow(title: "Center Third", action: .centerThird)
        ShortcutRow(title: "Last Third", action: .lastThird)
        ShortcutRow(title: "First Two Thirds", action: .firstTwoThirds)
        ShortcutRow(title: "Last Two Thirds", action: .lastTwoThirds)
      } header: {
        Text("Windows")
      } footer: {
        Text("Pressing a half again cycles it through ½, ⅔ and ⅓ of the screen. Pressing Maximize on a maximized window restores its previous size.")
      }

      Section {
        HStack {
          Spacer()
          Button("Restore Defaults") {
            settings.shortcuts = Shortcut.defaults
            engine.registerShortcuts()
          }
          .disabled(settings.shortcuts == Shortcut.defaults)
        }
      }
    }
    .formStyle(.grouped)
    .frame(height: 640)
  }
}

private struct ShortcutRow: View {
  let title: String
  let action: HotKeyAction
  @Environment(Engine.self) private var engine
  @State private var monitor: Any?

  var body: some View {
    LabeledContent {
      HStack(spacing: 4) {
        Button(action: toggleRecording) {
          if monitor != nil {
            Text("Type Shortcut…").foregroundStyle(.secondary)
          } else if let shortcut = engine.settings.shortcuts[action] {
            ShortcutKeys(shortcut: shortcut)
          } else {
            Text("Record Shortcut").foregroundStyle(.secondary)
          }
        }
        .frame(minWidth: 120)
        if engine.settings.shortcuts[action] != nil && monitor == nil {
          Button("Clear", systemImage: "xmark.circle.fill") { engine.setShortcut(nil, for: action) }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
      }
    } label: {
      Text(title)
      if engine.takenShortcuts.contains(action) {
        Text("In use by another app. Quit it or pick another shortcut.")
          .foregroundStyle(.orange)
      }
    }
    .disabled(!engine.settings.isEnabled(action))
    .onDisappear(perform: stopRecording)
  }

  private func toggleRecording() {
    guard monitor == nil else {
      stopRecording()
      return
    }
    engine.pauseShortcuts()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      record(event)
      return nil
    }
  }

  private func record(_ event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard !(event.keyCode == kVK_Escape && flags.isEmpty) else {
      stopRecording()
      return
    }
    guard !flags.intersection([.control, .option, .command]).isEmpty else {
      NSSound.beep()
      return
    }
    let modifiers =
      (flags.contains(.control) ? controlKey : 0) | (flags.contains(.option) ? optionKey : 0)
      | (flags.contains(.shift) ? shiftKey : 0) | (flags.contains(.command) ? cmdKey : 0)
    let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
    engine.setShortcut(Shortcut(keyCode: Int(event.keyCode), modifiers: modifiers, key: key), for: action)
    stopRecording()
  }

  private func stopRecording() {
    guard let monitor else { return }
    NSEvent.removeMonitor(monitor)
    self.monitor = nil
    engine.registerShortcuts()
  }
}

private let keySymbols: [UInt32: String] = [
  UInt32(kVK_LeftArrow): "arrow.left",
  UInt32(kVK_RightArrow): "arrow.right",
  UInt32(kVK_UpArrow): "arrow.up",
  UInt32(kVK_DownArrow): "arrow.down",
  UInt32(kVK_Return): "return",
  UInt32(kVK_Delete): "delete.left",
  UInt32(kVK_ForwardDelete): "delete.right",
  UInt32(kVK_Tab): "arrow.right.to.line",
  UInt32(kVK_Space): "space",
  UInt32(kVK_Escape): "escape",
]

private struct ShortcutKeys: View {
  let shortcut: Shortcut

  var body: some View {
    let modifierSymbols = [
      (controlKey, "control"), (optionKey, "option"), (shiftKey, "shift"), (cmdKey, "command"),
    ].filter { shortcut.modifiers & UInt32($0.0) != 0 }.map(\.1)
    HStack(spacing: 4) {
      ForEach(modifierSymbols, id: \.self) { Image(systemName: $0) }
      if let symbol = keySymbols[shortcut.keyCode] {
        Image(systemName: symbol)
      } else {
        Text(shortcut.key)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      modifierSymbols.map(\.localizedCapitalized).joined(separator: " ") + " " + shortcut.key)
  }
}

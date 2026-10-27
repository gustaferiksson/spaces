#if DEBUG
import AppKit
import SwiftUI
import SpacesCore

@MainActor
enum SettingsSnapshot {
  nonisolated static let output = UserDefaults.standard.string(forKey: "settingsSnapshot").map { URL(filePath: $0) }
  nonisolated static let switcherOutput = UserDefaults.standard.string(forKey: "switcherSnapshot").map {
    URL(filePath: $0)
  }

  static func capture(to output: URL, openSettings: () -> Void) async {
    if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
    openSettings()
    let window = await settingsWindow()
    window.setFrameOrigin(NSPoint(x: -4000, y: 0))
    try? await Task.sleep(for: .seconds(1.5))
    guard let image = image(of: window) else { exit(1) }
    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: output)
    exit(0)
  }

  static func captureSwitcher(to output: URL) async {
    if UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
    let state = UserDefaults.standard.string(forKey: "switcherState") ?? "grid"
    let apps = state == "empty" ? [] : fixtureApps()
    let size = CGSize(width: 1200, height: 720)
    let switcher = WindowSwitcher()
    switcher.load(apps, width: size.width)
    let expanded = apps.first { $0.name == (state == "expanded-end" ? "Safari" : "Mail") }
    switcher.selectedApp = expanded?.id
    if state.hasPrefix("expanded"), let expanded {
      switcher.expandedApp = expanded.id
      switcher.selectedWindow = expanded.windows[1].id
    }
    let window = NSWindow(
      contentRect: CGRect(origin: CGPoint(x: -4000, y: 0), size: size), styleMask: .borderless, backing: .buffered,
      defer: false)
    window.backgroundColor = NSColor(patternImage: NSImage(size: size, flipped: false) { rect in
      NSGradient(colors: [.systemIndigo, .systemTeal, .systemOrange])?.draw(in: rect, angle: -30)
      return true
    })
    window.contentView = NSHostingView(rootView: switcher.content)
    window.orderFrontRegardless()
    try? await Task.sleep(for: .seconds(1.5))
    guard let image = image(of: window) else { exit(1) }
    try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: output)
    exit(0)
  }

  private static func fixtureApps() -> [SwitcherApp] {
    let fixtures: [(path: String, titles: [String?])] = [
      ("/System/Applications/Calendar.app", ["Week of 26 October"]),
      ("/System/Library/CoreServices/Finder.app", ["Downloads", "Documents", "spaces"]),
      ("/System/Applications/Mail.app", ["Inbox — Mail", "Re: Window switcher spec", nil, "Drafts — Mail"]),
      ("/System/Applications/Messages.app", ["Messages"]),
      ("/System/Applications/Music.app", ["Music"]),
      ("/System/Applications/Notes.app", ["Groceries", "Window switcher ideas"]),
      ("/System/Applications/Preview.app", [nil]),
      ("/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app", [
        "Apple Developer Documentation: ScreenCaptureKit, capturing a single window without the desktop",
        "GitHub - gustaferiksson/spaces", "Hacker News", "Liquid Glass | Apple Developer", "YouTube",
      ]),
      ("/System/Applications/System Settings.app", ["Desktop & Dock"]),
      ("/Applications/Xcode.app", ["Spaces — WindowSwitcher.swift", "SpacesCore — SwitcherApp.swift"]),
    ]
    let apps = fixtures.enumerated().map { index, fixture in
      let name = FileManager.default.displayName(atPath: fixture.path).replacingOccurrences(of: ".app", with: "")
      let windows = fixture.titles.enumerated().map { offset, title in
        (id: CGWindowID(index * 10 + offset + 1), title: title, element: AXUIElement?.none)
      }
      return SwitcherApp(
        id: pid_t(index + 1), name: name, icon: NSWorkspace.shared.icon(forFile: fixture.path), windows: windows,
        frontToBack: windows.reversed().map(\.id))
    }
    return SwitcherApp.sorted(apps)
  }

  // cacheDisplay skips Liquid Glass; CGWindowListCreateImage is SDK-obsoleted but still exported and captures own windows without Screen Recording.
  private static func image(of window: NSWindow) -> CGImage? {
    typealias CreateImage = @convention(c) (CGRect, CGWindowListOption, CGWindowID, CGWindowImageOption) -> Unmanaged<CGImage>?
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
    let create = unsafeBitCast(symbol, to: CreateImage.self)
    return create(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution])?.takeRetainedValue()
  }

  private static func settingsWindow() async -> NSWindow {
    while true {
      if let window = NSApp.windows.first(where: { $0.isVisible && $0.identifier?.rawValue.contains("Settings") == true }) { return window }
      try? await Task.sleep(for: .milliseconds(20))
    }
  }
}
#endif

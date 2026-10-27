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
    let count = UserDefaults.standard.integer(forKey: "switcherCount")
    let apps = state == "empty" ? [] : Array(fixtureApps().prefix(count > 0 ? count : .max))
    let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let switcher = WindowSwitcher()
    switcher.place(frame: frame, visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944), primaryHeight: frame.height)
    switcher.load(apps)
    let wallpaperURL = URL(filePath: "/fixture-wallpaper")
    switcher.wallpapers[wallpaperURL] = fixtureWallpaper(size: frame.size)
    switcher.backdropURL = wallpaperURL
    let expanded = apps.max { $0.windows.count < $1.windows.count }
    switcher.selectedApp = apps.first { $0.name == "Mail" }?.id ?? apps.first?.id
    if state == "expanded", let expanded {
      switcher.selectedApp = expanded.id
      switcher.expandedApp = expanded.id
      switcher.selectedWindow = expanded.windows.dropFirst().first?.id
    }
    if state != "titlecards" {
      for app in apps {
        for window in app.windows {
          switcher.thumbnails[window.id] = fixtureThumbnail(window.title, size: window.frame.size, isDark: app.name == "Terminal")
        }
      }
    }
    switcher.isPresented = state != "start" && state != "mid"
    let window = NSWindow(contentRect: frame.offsetBy(dx: -4000, dy: 0), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = NSHostingView(rootView: SwitcherView(switcher: switcher))
    window.orderFrontRegardless()
    try? await Task.sleep(for: .seconds(1))
    if state == "mid" {
      withAnimation(.linear(duration: 4)) { switcher.isPresented = true }
      try? await Task.sleep(for: .seconds(2))
    }
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
      ("/System/Applications/Utilities/Terminal.app", ["tine", "roost", "tidy", "crew", "spaces", "anc"]),
      ("/Applications/Xcode.app", ["Spaces — WindowSwitcher.swift", "SpacesCore — SwitcherApp.swift"]),
    ]
    let sizes = [
      CGSize(width: 1100, height: 700), CGSize(width: 720, height: 540), CGSize(width: 440, height: 700),
      CGSize(width: 1300, height: 420), CGSize(width: 800, height: 800),
    ]
    let apps = fixtures.enumerated().map { index, fixture in
      let name = FileManager.default.displayName(atPath: fixture.path).replacingOccurrences(of: ".app", with: "")
      let windows = fixture.titles.enumerated().map { offset, title in
        let number = index * 10 + offset
        let size = sizes[(index + offset) % sizes.count]
        let origin = CGPoint(x: CGFloat(number * 97 % 400), y: 40 + CGFloat(number * 53 % 240))
        return (id: CGWindowID(number + 1), title: title, element: AXUIElement?.none, frame: CGRect(origin: origin, size: size))
      }
      return SwitcherApp(
        id: pid_t(index + 1), name: name, icon: NSWorkspace.shared.icon(forFile: fixture.path), windows: windows,
        frontToBack: windows.reversed().map(\.id))
    }
    return SwitcherApp.sorted(apps)
  }

  private static func fixtureWallpaper(size: CGSize) -> CGImage? {
    let image = NSImage(size: size, flipped: false) { rect in
      NSGradient(colors: [.systemIndigo, .systemTeal, .systemOrange])?.draw(in: rect, angle: -30)
      NSColor.white.withAlphaComponent(0.12).setFill()
      for index in 0..<6 {
        NSBezierPath(ovalIn: CGRect(x: CGFloat(index) * 280 - 100, y: CGFloat(index % 3) * 260 - 80, width: 420, height: 420)).fill()
      }
      return true
    }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
  }

  private static func fixtureThumbnail(_ title: String, size: CGSize, isDark: Bool) -> CGImage? {
    let image = NSImage(size: size, flipped: true) { rect in
      (isDark ? NSColor(white: 0.12, alpha: 1) : .white).setFill()
      rect.fill()
      NSColor(white: isDark ? 0.2 : 0.92, alpha: 1).setFill()
      CGRect(x: 0, y: 0, width: rect.width, height: 52).fill()
      for (offset, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        color.setFill()
        NSBezierPath(ovalIn: CGRect(x: 20 + CGFloat(offset) * 32, y: 16, width: 20, height: 20)).fill()
      }
      let text = NSColor(white: isDark ? 0.85 : 0.2, alpha: 1)
      (title as NSString).draw(
        at: CGPoint(x: 140, y: 12),
        withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: text])
      for line in 0..<Int((rect.height - 100) / 44) {
        (isDark ? NSColor.systemGreen : .systemGray).withAlphaComponent(0.6).setFill()
        let width = (rect.width - 80) * CGFloat((line * 37 + title.count * 13) % 60 + 30) / 100
        CGRect(x: 40, y: 88 + CGFloat(line) * 44, width: width, height: 18).fill()
      }
      return true
    }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
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

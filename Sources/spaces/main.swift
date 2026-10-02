import AppKit
import SpacesCore

func fail(_ message: String, code: Int32) -> Never {
  FileHandle.standardError.write(Data("spaces: \(message)\n".utf8))
  exit(code)
}

let command = CommandLine.arguments.dropFirst().first ?? ""

if command == "install-icon" {
  exit(ExecutableIcon.install() ? 0 : 1)
}

guard ["left", "right", "daemon"].contains(command) else {
  FileHandle.standardError.write(Data("usage: spaces [left|right|daemon]\n".utf8))
  exit(2)
}

let hasAccess = CGPreflightPostEventAccess() || CGRequestPostEventAccess()
let switcher = SpaceSwitcher()

if let direction = Direction(rawValue: command) {
  guard hasAccess else { fail("grant Accessibility access, then run again", code: 1) }
  switcher.switchSpace(direction)
  RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
  exit(0)
}

if !hasAccess {
  FileHandle.standardError.write(Data("spaces: waiting for Accessibility access\n".utf8))
  while !CGPreflightPostEventAccess() { Thread.sleep(forTimeInterval: 2) }
}

do {
  let indicator = SpaceIndicator()
  let listener = try HotKeyListener { direction in
    if let destination = switcher.switchSpace(direction) { indicator.show(destination) }
  }
  NSApplication.shared.setActivationPolicy(.accessory)
  withExtendedLifetime((listener, indicator)) { NSApplication.shared.run() }
} catch {
  fail("\(error)", code: 1)
}

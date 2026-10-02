import CoreGraphics
import Foundation

@MainActor
public final class SpaceSwitcher {
  private static let phaseInterval: TimeInterval = 0.01

  private let naturalScrolling: Bool

  public init() {
    naturalScrolling =
      CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication)
      as? Bool ?? true
  }

  public func switchSpace(_ direction: Direction) {
    guard SpaceLayout.current()?.canMove(direction) ?? true else { return }
    let events = DockSwipe.gesture(direction, naturalScrolling: naturalScrolling).compactMap { $0.event() }
    guard events.count == SwipePhase.allCases.count else { return }
    for event in events {
      event.post(tap: .cgSessionEventTap)
      DockSwipe.companionEvent()?.post(tap: .cgSessionEventTap)
      Thread.sleep(forTimeInterval: Self.phaseInterval)
    }
  }
}

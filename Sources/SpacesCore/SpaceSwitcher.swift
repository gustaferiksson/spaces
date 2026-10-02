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

  @discardableResult
  public func switchSpace(_ direction: Direction) -> SpaceLayout? {
    let layout = SpaceLayout.current()
    let destination = layout?.moved(direction)
    guard layout == nil || destination != nil else { return nil }
    let events = DockSwipe.gesture(direction, naturalScrolling: naturalScrolling).compactMap { $0.event() }
    guard events.count == SwipePhase.allCases.count else { return nil }
    for event in events {
      event.post(tap: .cgSessionEventTap)
      DockSwipe.companionEvent()?.post(tap: .cgSessionEventTap)
      Thread.sleep(forTimeInterval: Self.phaseInterval)
    }
    return destination
  }
}

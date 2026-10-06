import CoreGraphics
import Foundation

@MainActor
public final class SpaceSwitcher {
  private static let phaseInterval: TimeInterval = 0.01
  private static let releasePollInterval: Duration = .milliseconds(50)
  // Mission Control's "Move left/right a space"; only these carry a dragged window along.
  private static let moveSpaceHotKeys: (left: Int32, right: Int32) = (79, 81)

  private typealias GetSymbolicHotKeyValue = @convention(c) (
    Int32, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt16>, UnsafeMutablePointer<UInt32>
  ) -> Int32
  private typealias IsSymbolicHotKeyEnabled = @convention(c) (Int32) -> Bool
  private typealias SetSymbolicHotKeyEnabled = @convention(c) (Int32, Bool) -> Int32

  private static let skyLight:
    (value: GetSymbolicHotKeyValue, isEnabled: IsSymbolicHotKeyEnabled, setEnabled: SetSymbolicHotKeyEnabled)? = {
      let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
      guard let value = dlsym(handle, "SLSGetSymbolicHotKeyValue"),
        let isEnabled = dlsym(handle, "SLSIsSymbolicHotKeyEnabled"),
        let setEnabled = dlsym(handle, "SLSSetSymbolicHotKeyEnabled")
      else { return nil }
      return (
        unsafeBitCast(value, to: GetSymbolicHotKeyValue.self),
        unsafeBitCast(isEnabled, to: IsSymbolicHotKeyEnabled.self),
        unsafeBitCast(setEnabled, to: SetSymbolicHotKeyEnabled.self)
      )
    }()

  private let naturalScrolling: Bool
  private var nativeHotKeysRestore: Task<Void, Never>?

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
    if CGEventSource.buttonState(.combinedSessionState, button: .left) {
      carryDraggedWindow(direction)
      return nil
    }
    let events = DockSwipe.gesture(direction, naturalScrolling: naturalScrolling).compactMap { $0.event() }
    guard events.count == SwipePhase.allCases.count else { return nil }
    for event in events {
      event.post(tap: .cgSessionEventTap)
      DockSwipe.companionEvent()?.post(tap: .cgSessionEventTap)
      Thread.sleep(forTimeInterval: Self.phaseInterval)
    }
    return destination
  }

  private func carryDraggedWindow(_ direction: Direction) {
    guard nativeHotKeysRestore == nil, let skyLight = Self.skyLight else { return }
    let hotKey = direction == .left ? Self.moveSpaceHotKeys.left : Self.moveSpaceHotKeys.right
    var keyEquivalent: UInt16 = 0
    var keyCode: UInt16 = 0
    var modifiers: UInt32 = 0
    guard skyLight.value(hotKey, &keyEquivalent, &keyCode, &modifiers) == CGError.success.rawValue else { return }
    let source = CGEventSource(stateID: .hidSystemState)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    else { return }

    let hotKeys = [Self.moveSpaceHotKeys.left, Self.moveSpaceHotKeys.right]
    let wasEnabled = hotKeys.map(skyLight.isEnabled)
    hotKeys.forEach { _ = skyLight.setEnabled($0, true) }
    keyDown.flags = CGEventFlags(rawValue: UInt64(modifiers))
    keyUp.flags = keyDown.flags
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)

    nativeHotKeysRestore = Task { [weak self] in
      repeat {
        try? await Task.sleep(for: Self.releasePollInterval)
      } while CGEventSource.buttonState(.combinedSessionState, button: .left)
      zip(hotKeys, wasEnabled).forEach { _ = skyLight.setEnabled($0, $1) }
      self?.nativeHotKeysRestore = nil
    }
  }
}

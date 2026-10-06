import Carbon.HIToolbox

public enum HotKeyAction: String, CaseIterable, Codable, Sendable {
  case previousSpace = "previous-space"
  case nextSpace = "next-space"
  case controlCenter = "control-center"
  case leftHalf = "left-half"
  case rightHalf = "right-half"
  case maximize
  case firstThird = "first-third"
  case centerThird = "center-third"
  case lastThird = "last-third"
  case firstTwoThirds = "first-two-thirds"
  case lastTwoThirds = "last-two-thirds"
}

public struct Shortcut: Codable, Equatable, Sendable {
  public let keyCode: UInt32
  public let modifiers: UInt32
  public let key: String

  public init(keyCode: Int, modifiers: Int, key: String) {
    self.keyCode = UInt32(keyCode)
    self.modifiers = UInt32(modifiers)
    self.key = key
  }

  public static let defaults: [HotKeyAction: Shortcut] = [
    .previousSpace: Shortcut(keyCode: kVK_LeftArrow, modifiers: controlKey, key: "←"),
    .nextSpace: Shortcut(keyCode: kVK_RightArrow, modifiers: controlKey, key: "→"),
    .controlCenter: Shortcut(keyCode: kVK_ANSI_C, modifiers: controlKey | optionKey | cmdKey, key: "C"),
    .leftHalf: Shortcut(keyCode: kVK_LeftArrow, modifiers: controlKey | optionKey, key: "←"),
    .rightHalf: Shortcut(keyCode: kVK_RightArrow, modifiers: controlKey | optionKey, key: "→"),
    .maximize: Shortcut(keyCode: kVK_Return, modifiers: controlKey | optionKey, key: "↩"),
  ]
}

public struct HotKeyError: Error, CustomStringConvertible {
  public let operation: String
  public let status: OSStatus

  public var description: String { "\(operation) failed (\(status))" }
}

@MainActor
public final class HotKeyListener {
  private static let signature: OSType = 0x7370_6373

  private let onPress: (HotKeyAction) -> Void
  private var hotKeys: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?

  public init(onPress: @escaping (HotKeyAction) -> Void) throws(HotKeyError) {
    self.onPress = onPress
    try installHandler()
  }

  isolated deinit {
    unregisterAll()
    if let handler { RemoveEventHandler(handler) }
  }

  public func register(_ bindings: [HotKeyAction: Shortcut]) -> Set<HotKeyAction> {
    unregisterAll()
    var taken = Set<HotKeyAction>()
    for (index, action) in HotKeyAction.allCases.enumerated() {
      guard let shortcut = bindings[action] else { continue }
      var hotKey: EventHotKeyRef?
      let status = RegisterEventHotKey(
        shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: UInt32(index)),
        GetApplicationEventTarget(), 0, &hotKey)
      guard status == noErr, let hotKey else {
        taken.insert(action)
        continue
      }
      hotKeys.append(hotKey)
    }
    return taken
  }

  public func unregisterAll() {
    hotKeys.forEach { UnregisterEventHotKey($0) }
    hotKeys = []
  }

  private func installHandler() throws(HotKeyError) {
    var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKey = EventHotKeyID()
        GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
          MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
        let listener = Unmanaged<HotKeyListener>.fromOpaque(userData).takeUnretainedValue()
        let id = hotKey.id
        MainActor.assumeIsolated { listener.handle(id) }
        return noErr
      }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
    guard status == noErr else { throw HotKeyError(operation: "InstallEventHandler", status: status) }
  }

  private func handle(_ id: UInt32) {
    guard HotKeyAction.allCases.indices.contains(Int(id)) else { return }
    onPress(HotKeyAction.allCases[Int(id)])
  }
}

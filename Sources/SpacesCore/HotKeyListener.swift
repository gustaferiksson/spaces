import Carbon.HIToolbox

public struct HotKeyError: Error, CustomStringConvertible {
  public let operation: String
  public let status: OSStatus

  public var description: String { "\(operation) failed (\(status))" }
}

@MainActor
public final class HotKeyListener {
  private static let signature: OSType = 0x7370_6373
  private static let bindings: [(id: UInt32, keyCode: Int, direction: Direction)] = [
    (1, kVK_LeftArrow, .left),
    (2, kVK_RightArrow, .right),
  ]

  private let onPress: (Direction) -> Void
  private var hotKeys: [EventHotKeyRef] = []
  private var handler: EventHandlerRef?

  public init(onPress: @escaping (Direction) -> Void) throws(HotKeyError) {
    self.onPress = onPress
    try installHandler()
    try registerControlArrows()
  }

  isolated deinit {
    hotKeys.forEach { UnregisterEventHotKey($0) }
    if let handler { RemoveEventHandler(handler) }
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

  private func registerControlArrows() throws(HotKeyError) {
    for binding in Self.bindings {
      var hotKey: EventHotKeyRef?
      let status = RegisterEventHotKey(
        UInt32(binding.keyCode), UInt32(controlKey), EventHotKeyID(signature: Self.signature, id: binding.id),
        GetApplicationEventTarget(), 0, &hotKey)
      guard status == noErr, let hotKey else { throw HotKeyError(operation: "RegisterEventHotKey", status: status) }
      hotKeys.append(hotKey)
    }
  }

  private func handle(_ id: UInt32) {
    guard let binding = Self.bindings.first(where: { $0.id == id }) else { return }
    onPress(binding.direction)
  }
}

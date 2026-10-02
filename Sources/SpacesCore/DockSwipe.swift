import CoreGraphics
import Foundation

public enum Direction: String, Sendable {
  case left, right
}

enum SwipePhase: UInt32, CaseIterable, Sendable {
  case began = 1
  case changed = 2
  case ended = 4
}

struct DockSwipe {
  private enum Field {
    static let cgsEventType = CGEventField(rawValue: 55)!
    static let hidEventType = CGEventField(rawValue: 110)!
    static let swipeMotion = CGEventField(rawValue: 123)!
    static let swipeProgress = CGEventField(rawValue: 124)!
    static let swipePositionX = CGEventField(rawValue: 125)!
    static let swipeVelocityX = CGEventField(rawValue: 129)!
    static let gesturePhase = CGEventField(rawValue: 132)!
  }

  private enum EventType {
    static let cgsGesture: Int64 = 29
    static let cgsDockControl: Int64 = 30
    static let hidDockSwipe: UInt32 = 23
    static let hidVelocity: UInt32 = 9
  }

  private static let horizontalMotion: UInt16 = 1
  private static let dockGestureFlavor: UInt16 = 3
  private static let rawHIDPayloadTag: UInt16 = 4205
  private static let serializedEventVersion: [UInt8] = [0, 0, 0, 2]
  private static let positionX = 0.1
  private static let minimalProgress = 1e-4
  private static let flingVelocity = 9999.0

  let phase: SwipePhase
  let progress: Double
  let velocity: Double
  let timestamp: UInt64

  init(phase: SwipePhase, direction: Direction, naturalScrolling: Bool, timestamp: UInt64) {
    let sign: Double = (direction == .right ? -1 : 1) * (naturalScrolling ? 1 : -1)
    self.phase = phase
    self.progress = Self.minimalProgress * sign
    self.velocity = phase == .ended ? Self.flingVelocity * sign : 0
    self.timestamp = timestamp
  }

  static func gesture(_ direction: Direction, naturalScrolling: Bool) -> [DockSwipe] {
    SwipePhase.allCases.map {
      DockSwipe(phase: $0, direction: direction, naturalScrolling: naturalScrolling, timestamp: mach_absolute_time())
    }
  }

  static func companionEvent() -> CGEvent? {
    let event = CGEvent(source: nil)
    event?.setIntegerValueField(Field.cgsEventType, value: EventType.cgsGesture)
    return event
  }

  func event() -> CGEvent? {
    guard let event = CGEvent(source: nil) else { return nil }
    event.setIntegerValueField(Field.cgsEventType, value: EventType.cgsDockControl)
    event.setIntegerValueField(Field.hidEventType, value: Int64(EventType.hidDockSwipe))
    event.setIntegerValueField(Field.gesturePhase, value: Int64(phase.rawValue))
    event.setIntegerValueField(Field.swipeMotion, value: Int64(Self.horizontalMotion))
    event.setDoubleValueField(Field.swipeProgress, value: progress)
    event.setDoubleValueField(Field.swipePositionX, value: Self.positionX)
    event.setDoubleValueField(Field.swipeVelocityX, value: velocity)
    guard let serialized = event.data as Data?, serialized.starts(with: Self.serializedEventVersion) else {
      return nil
    }
    let payload = hidPayload()
    var record = ByteWriter()
    record.appendBigEndian(UInt16(payload.count))
    record.appendBigEndian(Self.rawHIDPayloadTag)
    return CGEvent(withDataAllocator: nil, data: (serialized + record.bytes + payload) as CFData)
  }

  func hidPayload() -> [UInt8] {
    let hasVelocity = phase == .ended
    var writer = ByteWriter()

    writer.append(timestamp)
    writer.append(UInt64(0))
    writer.append(UInt32(0))
    writer.append(UInt32(0))
    writer.append(UInt32(hasVelocity ? 2 : 1))

    writer.append(UInt32(40))
    writer.append(EventType.hidDockSwipe)
    writer.append(phase.rawValue << 24)
    writer.append(UInt32(0))
    writer.appendFixedPoint(Self.positionX)
    writer.appendFixedPoint(0)
    writer.appendFixedPoint(0)
    writer.append(UInt32(0))
    writer.append(Self.horizontalMotion)
    writer.append(Self.dockGestureFlavor)
    writer.appendFixedPoint(progress)

    guard hasVelocity else { return writer.bytes }
    writer.append(UInt32(28))
    writer.append(EventType.hidVelocity)
    writer.append(UInt32(0))
    writer.append(UInt32(1))
    writer.appendFixedPoint(velocity)
    writer.appendFixedPoint(0)
    writer.appendFixedPoint(0)
    return writer.bytes
  }
}

struct ByteWriter {
  private(set) var bytes: [UInt8] = []

  mutating func append(_ value: some FixedWidthInteger) {
    withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
  }

  mutating func appendBigEndian(_ value: some FixedWidthInteger) {
    withUnsafeBytes(of: value.bigEndian) { bytes.append(contentsOf: $0) }
  }

  mutating func appendFixedPoint(_ value: Double) {
    append(Int32(clamping: Int64(value * 65536)))
  }
}

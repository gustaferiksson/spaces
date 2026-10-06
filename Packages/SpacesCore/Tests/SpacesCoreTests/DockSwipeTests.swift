import Foundation
import Testing

@testable import SpacesCore

struct DockSwipeTests {
  private let timestamp: UInt64 = 0x0102_0304_0506_0708

  private func hex(_ phase: SwipePhase, _ direction: Direction, naturalScrolling: Bool = true) -> String {
    DockSwipe(phase: phase, direction: direction, naturalScrolling: naturalScrolling, timestamp: timestamp)
      .hidPayload().map { String(format: "%02x", $0) }.joined()
  }

  @Test func beganRightMatchesWireFormat() {
    #expect(
      hex(.began, .right)
        == "08070605040302010000000000000000000000000000000001000000280000001700000000000001000000009919000000000000000000000000000001000300faffffff"
    )
  }

  @Test func changedRightMatchesWireFormat() {
    #expect(
      hex(.changed, .right)
        == "08070605040302010000000000000000000000000000000001000000280000001700000000000002000000009919000000000000000000000000000001000300faffffff"
    )
  }

  @Test func endedRightCarriesVelocityRecord() {
    #expect(
      hex(.ended, .right)
        == "08070605040302010000000000000000000000000000000002000000280000001700000000000004000000009919000000000000000000000000000001000300faffffff1c0000000900000000000000010000000000f1d80000000000000000"
    )
  }

  @Test func endedLeftCarriesVelocityRecord() {
    #expect(
      hex(.ended, .left)
        == "08070605040302010000000000000000000000000000000002000000280000001700000000000004000000009919000000000000000000000000000001000300060000001c00000009000000000000000100000000000f270000000000000000"
    )
  }

  @Test func reversedScrollingFlipsDirection() {
    #expect(hex(.ended, .right, naturalScrolling: false) == hex(.ended, .left))
  }

  @Test func eventCarriesPayloadRecord() throws {
    let swipe = DockSwipe(phase: .ended, direction: .right, naturalScrolling: true, timestamp: timestamp)
    let data = try #require(swipe.event()?.data as Data?)
    let payload = swipe.hidPayload()
    let record: [UInt8] = [0x00, UInt8(payload.count), 0x10, 0x6d] + payload
    #expect(data.firstRange(of: record) != nil)
  }
}

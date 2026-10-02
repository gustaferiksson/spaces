import ColorSync
import CoreGraphics
import Foundation

struct SpaceLayout: Equatable {
  let index: Int
  let count: Int

  init?(displays: [[String: Any]], cursorDisplay: String?) {
    let display =
      displays.count == 1 ? displays.first : displays.first { $0["Display Identifier"] as? String == cursorDisplay }
    guard let spaces = display?["Spaces"] as? [[String: Any]],
      let currentID = (display?["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int,
      let index = spaces.firstIndex(where: { $0["ManagedSpaceID"] as? Int == currentID })
    else { return nil }
    self.index = index
    self.count = spaces.count
  }

  func canMove(_ direction: Direction) -> Bool {
    direction == .left ? index > 0 : index < count - 1
  }
}

extension SpaceLayout {
  private typealias MainConnectionID = @convention(c) () -> Int32
  private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

  private static let skyLight: (mainConnectionID: MainConnectionID, copyManagedDisplaySpaces: CopyManagedDisplaySpaces)? = {
    let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
    guard let mainConnectionID = dlsym(handle, "SLSMainConnectionID"),
      let copyManagedDisplaySpaces = dlsym(handle, "SLSCopyManagedDisplaySpaces")
    else { return nil }
    return (
      unsafeBitCast(mainConnectionID, to: MainConnectionID.self),
      unsafeBitCast(copyManagedDisplaySpaces, to: CopyManagedDisplaySpaces.self)
    )
  }()

  static func current() -> SpaceLayout? {
    guard let skyLight,
      let displays = skyLight.copyManagedDisplaySpaces(skyLight.mainConnectionID())?.takeRetainedValue()
        as? [[String: Any]]
    else { return nil }
    return SpaceLayout(displays: displays, cursorDisplay: cursorDisplayIdentifier())
  }

  private static func cursorDisplayIdentifier() -> String? {
    let cursor = CGEvent(source: nil)?.location ?? .zero
    var displayID: CGDirectDisplayID = 0
    var count: UInt32 = 0
    guard CGGetDisplaysWithPoint(cursor, 1, &displayID, &count) == .success, count == 1,
      let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
  }
}

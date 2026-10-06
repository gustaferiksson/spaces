import ColorSync
import CoreGraphics
import Foundation

public struct SpaceLayout: Equatable, Sendable {
  private static let desktopType = 0

  let index: Int
  let desktopNumbers: [Int?]

  public var desktopNumber: Int? { desktopNumbers[index] }

  init?(displays: [[String: Any]], cursorDisplay: String?) {
    let display =
      displays.count == 1 ? displays.first : displays.first { $0["Display Identifier"] as? String == cursorDisplay }
    guard let spaces = display?["Spaces"] as? [[String: Any]],
      let currentID = (display?["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int,
      let index = spaces.firstIndex(where: { $0["ManagedSpaceID"] as? Int == currentID })
    else { return nil }
    self.index = index
    self.desktopNumbers = spaces.reduce(into: []) { numbers, space in
      numbers.append(space["type"] as? Int == Self.desktopType ? numbers.compactMap { $0 }.count + 1 : nil)
    }
  }

  private init(index: Int, desktopNumbers: [Int?]) {
    self.index = index
    self.desktopNumbers = desktopNumbers
  }

  func moved(_ direction: Direction) -> SpaceLayout? {
    let destination = index + (direction == .left ? -1 : 1)
    guard desktopNumbers.indices.contains(destination) else { return nil }
    return SpaceLayout(index: destination, desktopNumbers: desktopNumbers)
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

  public static func current() -> SpaceLayout? {
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

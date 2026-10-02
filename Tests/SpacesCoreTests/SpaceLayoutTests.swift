import Testing

@testable import SpacesCore

struct SpaceLayoutTests {
  private func display(_ identifier: String, current: Int, spaces: [Int]) -> [String: Any] {
    [
      "Display Identifier": identifier,
      "Current Space": ["ManagedSpaceID": current],
      "Spaces": spaces.map { ["ManagedSpaceID": $0] },
    ]
  }

  @Test func firstSpaceOnlyMovesRight() throws {
    let layout = try #require(SpaceLayout(displays: [display("Main", current: 3, spaces: [3, 4, 5])], cursorDisplay: nil))
    #expect(!layout.canMove(.left))
    #expect(layout.canMove(.right))
  }

  @Test func lastSpaceOnlyMovesLeft() throws {
    let layout = try #require(SpaceLayout(displays: [display("Main", current: 5, spaces: [3, 4, 5])], cursorDisplay: nil))
    #expect(layout.canMove(.left))
    #expect(!layout.canMove(.right))
  }

  @Test func usesDisplayUnderCursor() throws {
    let displays = [display("A", current: 1, spaces: [1, 2]), display("B", current: 4, spaces: [3, 4])]
    let layout = try #require(SpaceLayout(displays: displays, cursorDisplay: "B"))
    #expect(layout == SpaceLayout(displays: [display("B", current: 4, spaces: [3, 4])], cursorDisplay: nil))
  }

  @Test func unknownCursorDisplayYieldsNoLayout() {
    let displays = [display("A", current: 1, spaces: [1, 2]), display("B", current: 4, spaces: [3, 4])]
    #expect(SpaceLayout(displays: displays, cursorDisplay: "C") == nil)
  }
}

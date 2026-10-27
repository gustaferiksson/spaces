import AppKit
import Testing

@testable import SpacesCore

struct SwitcherAppTests {
  private let element = AXUIElementCreateApplication(1)

  private func app(_ pid: pid_t, _ name: String) -> SwitcherApp {
    SwitcherApp(id: pid, name: name, icon: NSImage(), windows: [(1, "Window", element)], frontToBack: [])
  }

  @Test func appsSortByNameLikeFinder() {
    let apps = [app(1, "safari"), app(2, "Ärende"), app(3, "App 10"), app(4, "App 9"), app(5, "Mail")]
    #expect(SwitcherApp.sorted(apps).map(\.name) == ["App 9", "App 10", "Ärende", "Mail", "safari"])
  }

  @Test func sameNameAppsKeepPidOrder() {
    #expect(SwitcherApp.sorted([app(9, "Code"), app(3, "Code")]).map(\.id) == [3, 9])
  }

  @Test func titleLosesTrailingAppName() {
    #expect(SwitcherApp.cleanTitle("Inbox — Mail", appName: "Mail") == "Inbox")
    #expect(SwitcherApp.cleanTitle("README.md - visual studio code", appName: "Visual Studio Code") == "README.md")
    #expect(SwitcherApp.cleanTitle("  Notes | Obsidian ", appName: "Obsidian") == "Notes")
  }

  @Test func titleKeepsAppNameElsewhere() {
    #expect(SwitcherApp.cleanTitle("Mail — Inbox", appName: "Mail") == "Mail — Inbox")
    #expect(SwitcherApp.cleanTitle("Gmail", appName: "Mail") == "Gmail")
  }

  @Test func emptyOrAppNameOnlyTitleIsUntitled() {
    #expect(SwitcherApp.cleanTitle(nil, appName: "Mail") == nil)
    #expect(SwitcherApp.cleanTitle("   ", appName: "Mail") == nil)
    #expect(SwitcherApp.cleanTitle("mail", appName: "Mail") == nil)
  }

  @Test func windowsKeepCreationOrderAndNumberUntitledOnes() {
    let app = SwitcherApp(
      id: 1, name: "Mail", icon: NSImage(),
      windows: [(30, nil, element), (10, "Inbox — Mail", element), (20, "", element)], frontToBack: [99, 30, 10])
    #expect(app.windows.map(\.id) == [10, 20, 30])
    #expect(app.windows.map(\.title) == ["Inbox", "Untitled Window", "Untitled Window 2"])
    #expect(app.windows.map(\.isUntitled) == [false, true, true])
    #expect(app.recentWindowID == 30)
  }
}

struct CornerDwellTests {
  private func fired(_ steps: [(inCorner: Bool, buttonDown: Bool, ms: Int)]) -> [Bool] {
    let start = ContinuousClock.now
    var dwell = CornerDwell()
    return steps.map { dwell.update(inCorner: $0.inCorner, buttonDown: $0.buttonDown, now: start + .milliseconds($0.ms)) }
  }

  @Test func firesOnceAfterTheDelay() {
    #expect(fired([(true, false, 0), (true, false, 100), (true, false, 150), (true, false, 5000)]) == [false, false, true, false])
  }

  @Test func leavingRearms() {
    let steps = [(true, false, 0), (true, false, 200), (false, false, 300), (true, false, 400), (true, false, 550)]
    #expect(fired(steps) == [false, true, false, false, true])
  }

  @Test func leavingEarlyRestartsTheDelay() {
    #expect(fired([(true, false, 0), (false, false, 100), (true, false, 200), (true, false, 300)]) == [false, false, false, false])
  }

  @Test func heldButtonSpendsTheCornerUntilLeft() {
    let steps = [(true, true, 0), (true, false, 10), (true, false, 1000), (false, false, 2000), (true, false, 3000), (true, false, 4000)]
    #expect(fired(steps) == [false, false, false, false, false, true])
  }

  @Test func pressingWhileDwellingCancels() {
    #expect(fired([(true, false, 0), (true, true, 100), (true, false, 300)]) == [false, false, false])
  }
}

struct ScreenCornerTests {
  private let screen = CGRect(x: 100, y: 0, width: 1000, height: 800)

  @Test func cornersUseAppKitCoordinates() {
    #expect(ScreenCorner.topLeft.contains(CGPoint(x: 100, y: 799), in: screen))
    #expect(ScreenCorner.bottomRight.contains(CGPoint(x: 1099, y: 0), in: screen))
    #expect(!ScreenCorner.topLeft.contains(CGPoint(x: 100, y: 0), in: screen))
    #expect(!ScreenCorner.topRight.contains(CGPoint(x: 1090, y: 799), in: screen))
  }
}

@MainActor
struct SwitcherGridTests {
  private func step(_ index: Int?, dx: Int = 0, dy: Int = 0, count: Int = 10) -> Int? {
    WindowSwitcher.step(from: index, dx: dx, dy: dy, count: count, columns: 4)
  }

  @Test func firstMoveSelectsTheFirstTile() {
    #expect(step(nil, dx: 1) == 0)
    #expect(step(nil, dy: 1, count: 0) == nil)
  }

  @Test func horizontalMovesStayInTheRow() {
    #expect(step(1, dx: 1) == 2)
    #expect(step(3, dx: 1) == 3)
    #expect(step(4, dx: -1) == 4)
    #expect(step(0, dx: -1) == 0)
    #expect(step(9, dx: 1) == 9)
  }

  @Test func verticalMovesStopAtTheEdges() {
    #expect(step(1, dy: 1) == 5)
    #expect(step(5, dy: -1) == 1)
    #expect(step(1, dy: -1) == 1)
    #expect(step(9, dy: 1) == 9)
  }

  @Test func downIntoAShortLastRowLandsOnTheLastTile() {
    #expect(step(7, dy: 1) == 9)
    #expect(step(4, dy: 1) == 8)
  }
}

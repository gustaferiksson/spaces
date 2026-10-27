import AppKit
import Testing

@testable import SpacesCore

struct SwitcherAppTests {
  private let element = AXUIElementCreateApplication(1)

  private func app(_ pid: pid_t, _ name: String) -> SwitcherApp {
    SwitcherApp(id: pid, name: name, icon: NSImage(), windows: [(1, "Window", element, .zero)], frontToBack: [])
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
      windows: [(30, nil, element, .zero), (10, "Inbox — Mail", element, .zero), (20, "", element, .zero)], frontToBack: [99, 30, 10])
    #expect(app.windows.map(\.id) == [10, 20, 30])
    #expect(app.windows.map(\.title) == ["Inbox", "Untitled Window", "Untitled Window 2"])
    #expect(app.windows.map(\.isUntitled) == [false, true, true])
    #expect(app.recentWindowID == 30)
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

@MainActor
struct SwitcherLayoutTests {
  private let screenContent = CGSize(width: 1360, height: 848)

  private func previews(_ count: Int, _ width: CGFloat, _ height: CGFloat) -> (columns: Int, size: CGSize) {
    WindowSwitcher.layout(count: count, in: CGSize(width: width, height: height), maxWidth: 320, labelHeight: 24)
  }

  private func stacks(_ count: Int) -> (columns: Int, size: CGSize) {
    WindowSwitcher.layout(count: count, in: screenContent, maxWidth: 480, labelHeight: 40)
  }

  @Test func wideAreaFitsOneRowAtTheMaximumWidth() {
    let layout = previews(3, 1200, 400)
    #expect(layout.columns == 3)
    #expect(layout.size == CGSize(width: 320, height: 200))
  }

  @Test func shortAreaWrapsIntoBalancedRows() {
    let layout = previews(6, 1416, 408)
    #expect(layout.columns == 3)
    #expect(layout.size == CGSize(width: 260, height: 160))
  }

  @Test func sizesStayOnTheFourPointGrid() {
    let layout = previews(5, 1001, 333)
    #expect(layout.size.width.truncatingRemainder(dividingBy: 4) == 0)
    #expect(layout.size.height.truncatingRemainder(dividingBy: 4) == 0)
  }

  @Test func tinyAreaKeepsAMinimumWidth() {
    #expect(previews(4, 200, 40).size.width == 96)
  }

  @Test func fewStacksGrowToTheMaximumSize() {
    #expect(stacks(4).columns == 2)
    #expect(stacks(4).size == CGSize(width: 480, height: 300))
  }

  @Test func equalSizesPreferFewerRows() {
    #expect(stacks(2).columns == 2)
  }

  @Test func manyStacksShrinkIntoBalancedRows() {
    #expect(stacks(10).columns == 4)
    #expect(stacks(10).size == CGSize(width: 324, height: 200))
  }

  @Test func cellsAreUniformAndCentredWithTheLastRowCentred() {
    let rect = CGRect(origin: CGPoint(x: 76, y: 86), size: screenContent)
    let cells = WindowSwitcher.cells(
      count: 10, columns: 4, slot: CGSize(width: 324, height: 200), labelHeight: 40, in: rect)
    #expect(cells[0] == CGRect(x: 76, y: 126, width: 340, height: 256))
    #expect(cells[5].minX - cells[4].minX == 340)
    #expect(cells[8].minX == 416)
    #expect(cells[9] == CGRect(x: 756, y: 638, width: 340, height: 256))
    #expect(Set(cells.map(\.size)).count == 1)
  }

  @Test func faceFitsTheSlotBottomAligned() {
    let slot = CGRect(x: 0, y: 0, width: 320, height: 200)
    #expect(WindowSwitcher.fit(CGSize(width: 800, height: 1000), in: slot) == CGRect(x: 80, y: 0, width: 160, height: 200))
    #expect(WindowSwitcher.fit(CGSize(width: 1600, height: 400), in: slot) == CGRect(x: 0, y: 120, width: 320, height: 80))
  }
}

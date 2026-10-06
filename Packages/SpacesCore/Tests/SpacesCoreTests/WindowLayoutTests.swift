import CoreGraphics
import Testing

@testable import SpacesCore

struct WindowLayoutTests {
  private let screen = CGRect(x: 0, y: 80, width: 1500, height: 900)

  @Test func halvesFillTheirSide() {
    #expect(WindowLayout.frame(.leftHalf, in: screen) == CGRect(x: 0, y: 80, width: 750, height: 900))
    #expect(WindowLayout.frame(.rightHalf, in: screen) == CGRect(x: 750, y: 80, width: 750, height: 900))
  }

  @Test func topIsTheHigherYInAppKitCoordinates() {
    #expect(WindowLayout.frame(.topHalf, in: screen) == CGRect(x: 0, y: 530, width: 1500, height: 450))
    #expect(WindowLayout.frame(.bottomRight, in: screen) == CGRect(x: 750, y: 80, width: 750, height: 450))
  }

  @Test func rightTwoThirdsHugsTheRightEdge() {
    #expect(WindowLayout.frame(.rightHalf, in: screen, fraction: 2.0 / 3) == CGRect(x: 500, y: 80, width: 1000, height: 900))
  }

  @Test func repeatingAHalfCyclesHalfTwoThirdsThird() {
    let half = WindowLayout.frame(.leftHalf, in: screen)
    let twoThirds = WindowLayout.frame(.leftHalf, in: screen, fraction: 2.0 / 3)
    let third = WindowLayout.frame(.leftHalf, in: screen, fraction: 1.0 / 3)
    #expect(WindowLayout.nextFraction(.leftHalf, window: half, in: screen, last: nil) == 2.0 / 3)
    #expect(WindowLayout.nextFraction(.leftHalf, window: twoThirds, in: screen, last: nil) == 1.0 / 3)
    #expect(WindowLayout.nextFraction(.leftHalf, window: third, in: screen, last: nil) == 1.0 / 2)
  }

  @Test func aWindowElsewhereStartsAtHalf() {
    let floating = CGRect(x: 200, y: 300, width: 640, height: 480)
    #expect(WindowLayout.nextFraction(.leftHalf, window: floating, in: screen, last: nil) == 1.0 / 2)
  }

  @Test func theOtherSideStartsAtHalf() {
    let leftHalf = WindowLayout.frame(.leftHalf, in: screen)
    #expect(WindowLayout.nextFraction(.rightHalf, window: leftHalf, in: screen, last: nil) == 1.0 / 2)
  }

  @Test func gapsSurroundTilesWithOneGapBetweenNeighbours() {
    let left = WindowLayout.frame(.leftHalf, in: screen, gap: 8)
    let right = WindowLayout.frame(.rightHalf, in: screen, gap: 8)
    #expect(left == CGRect(x: 8, y: 88, width: 738, height: 884))
    #expect(right == CGRect(x: 754, y: 88, width: 738, height: 884))
    #expect(right.minX - left.maxX == 8)
  }

  @Test func gappedQuartersAndMaximize() {
    #expect(WindowLayout.frame(.topRight, in: screen, gap: 8) == CGRect(x: 754, y: 534, width: 738, height: 438))
    #expect(WindowLayout.frame(.bottomLeft, in: screen, gap: 8) == CGRect(x: 8, y: 88, width: 738, height: 438))
    #expect(WindowLayout.frame(.maximize, in: screen, gap: 8) == CGRect(x: 8, y: 88, width: 1484, height: 884))
  }

  @Test func gappedCycleMatchesGappedFrames() {
    let half = WindowLayout.frame(.leftHalf, in: screen, gap: 12)
    let twoThirds = WindowLayout.frame(.leftHalf, in: screen, fraction: 2.0 / 3, gap: 12)
    #expect(WindowLayout.nextFraction(.leftHalf, window: half, in: screen, gap: 12, last: nil) == 2.0 / 3)
    #expect(WindowLayout.nextFraction(.leftHalf, window: twoThirds, in: screen, gap: 12, last: nil) == 1.0 / 3)
  }

  @Test func thirdsSplitTheWidth() {
    #expect(WindowLayout.frame(.firstThird, in: screen) == CGRect(x: 0, y: 80, width: 500, height: 900))
    #expect(WindowLayout.frame(.centerThird, in: screen) == CGRect(x: 500, y: 80, width: 500, height: 900))
    #expect(WindowLayout.frame(.lastThird, in: screen) == CGRect(x: 1000, y: 80, width: 500, height: 900))
    #expect(WindowLayout.frame(.firstTwoThirds, in: screen) == CGRect(x: 0, y: 80, width: 1000, height: 900))
    #expect(WindowLayout.frame(.lastTwoThirds, in: screen) == CGRect(x: 500, y: 80, width: 1000, height: 900))
  }

  @Test func gappedThirdsShareOneGapBetweenNeighbours() {
    let first = WindowLayout.frame(.firstThird, in: screen, gap: 6)
    let center = WindowLayout.frame(.centerThird, in: screen, gap: 6)
    let last = WindowLayout.frame(.lastThird, in: screen, gap: 6)
    #expect(first == CGRect(x: 6, y: 86, width: 492, height: 888))
    #expect(center == CGRect(x: 504, y: 86, width: 492, height: 888))
    #expect(last == CGRect(x: 1002, y: 86, width: 492, height: 888))
    #expect(WindowLayout.frame(.firstTwoThirds, in: screen, gap: 6) == CGRect(x: 6, y: 86, width: 990, height: 888))
    #expect(WindowLayout.frame(.lastTwoThirds, in: screen, gap: 6) == CGRect(x: 504, y: 86, width: 990, height: 888))
  }

  @Test func cycledThirdsMatchTheThirdActions() {
    let cycledThird = WindowLayout.frame(.leftHalf, in: screen, fraction: 1.0 / 3, gap: 6)
    let cycledTwoThirds = WindowLayout.frame(.rightHalf, in: screen, fraction: 2.0 / 3, gap: 6)
    #expect(cycledThird == WindowLayout.frame(.firstThird, in: screen, gap: 6))
    #expect(cycledTwoThirds == WindowLayout.frame(.lastTwoThirds, in: screen, gap: 6))
  }

  @Test func lastFractionWinsWhenTheWindowCouldNotFitExactly() {
    let clamped = CGRect(x: 0, y: 80, width: 640, height: 900)
    #expect(WindowLayout.nextFraction(.leftHalf, window: clamped, in: screen, last: 1.0 / 3) == 1.0 / 2)
  }
}

struct SnapZoneTests {
  private let screen = CGRect(x: 0, y: 0, width: 1500, height: 1000)

  @Test func edges() {
    #expect(SnapZone(point: CGPoint(x: 0, y: 500), in: screen) == .left)
    #expect(SnapZone(point: CGPoint(x: 1499, y: 500), in: screen) == .right)
    #expect(SnapZone(point: CGPoint(x: 700, y: 999), in: screen) == .top)
    #expect(SnapZone(point: CGPoint(x: 700, y: 1), in: screen) == .bottom)
  }

  @Test func cornersReachAlongEitherEdge() {
    #expect(SnapZone(point: CGPoint(x: 18, y: 1000), in: screen) == .topLeft)
    #expect(SnapZone(point: CGPoint(x: 1500, y: 12), in: screen) == .bottomRight)
  }

  @Test func awayFromEdgesIsNoZone() {
    #expect(SnapZone(point: CGPoint(x: 10, y: 500), in: screen) == nil)
  }

  @Test func zonesFollowAScreenOffsetFromTheOrigin() {
    let secondary = CGRect(x: 1500, y: -200, width: 1000, height: 800)
    #expect(SnapZone(point: CGPoint(x: 1500, y: 100), in: secondary) == .left)
  }
}

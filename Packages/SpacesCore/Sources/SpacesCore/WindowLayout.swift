import CoreGraphics

public enum WindowAction: String, CaseIterable, Codable, Sendable {
  case leftHalf = "left-half"
  case rightHalf = "right-half"
  case topHalf = "top-half"
  case bottomHalf = "bottom-half"
  case topLeft = "top-left"
  case topRight = "top-right"
  case bottomLeft = "bottom-left"
  case bottomRight = "bottom-right"
  case maximize
  case firstThird = "first-third"
  case centerThird = "center-third"
  case lastThird = "last-third"
  case firstTwoThirds = "first-two-thirds"
  case lastTwoThirds = "last-two-thirds"
}

public enum SnapZone: String, CaseIterable, Codable, Sendable {
  case left, right, top, bottom
  case topLeft = "top-left"
  case topRight = "top-right"
  case bottomLeft = "bottom-left"
  case bottomRight = "bottom-right"

  static let edgeDistance: CGFloat = 4
  static let cornerLength: CGFloat = 20

  public init?(point: CGPoint, in screen: CGRect) {
    let left = point.x - screen.minX
    let right = screen.maxX - point.x
    let bottom = point.y - screen.minY
    let top = screen.maxY - point.y
    guard min(left, right, bottom, top) <= Self.edgeDistance else { return nil }
    let corner = Self.cornerLength
    if top <= corner && left <= corner {
      self = .topLeft
    } else if top <= corner && right <= corner {
      self = .topRight
    } else if bottom <= corner && left <= corner {
      self = .bottomLeft
    } else if bottom <= corner && right <= corner {
      self = .bottomRight
    } else if left <= Self.edgeDistance {
      self = .left
    } else if right <= Self.edgeDistance {
      self = .right
    } else if top <= Self.edgeDistance {
      self = .top
    } else {
      self = .bottom
    }
  }
}

public enum WindowLayout {
  static let halfCycle: [CGFloat] = [1 / 2, 2 / 3, 1 / 3]

  public static func frame(_ action: WindowAction, in screen: CGRect, fraction: CGFloat = 1 / 2, gap: CGFloat = 0)
    -> CGRect
  {
    let inner = screen.insetBy(dx: gap, dy: gap)
    let width = ((inner.width + gap) * fraction - gap).rounded()
    let third = ((inner.width + gap) / 3 - gap).rounded()
    let twoThirds = ((inner.width + gap) * 2 / 3 - gap).rounded()
    let halfWidth = ((inner.width - gap) / 2).rounded()
    let halfHeight = ((inner.height - gap) / 2).rounded()
    let top = inner.maxY - halfHeight
    switch action {
    case .leftHalf: return CGRect(x: inner.minX, y: inner.minY, width: width, height: inner.height)
    case .rightHalf: return CGRect(x: inner.maxX - width, y: inner.minY, width: width, height: inner.height)
    case .topHalf: return CGRect(x: inner.minX, y: top, width: inner.width, height: halfHeight)
    case .bottomHalf: return CGRect(x: inner.minX, y: inner.minY, width: inner.width, height: halfHeight)
    case .topLeft: return CGRect(x: inner.minX, y: top, width: halfWidth, height: halfHeight)
    case .topRight: return CGRect(x: inner.maxX - halfWidth, y: top, width: halfWidth, height: halfHeight)
    case .bottomLeft: return CGRect(x: inner.minX, y: inner.minY, width: halfWidth, height: halfHeight)
    case .bottomRight: return CGRect(x: inner.maxX - halfWidth, y: inner.minY, width: halfWidth, height: halfHeight)
    case .maximize: return inner
    case .firstThird: return CGRect(x: inner.minX, y: inner.minY, width: third, height: inner.height)
    case .centerThird:
      return CGRect(x: (inner.minX + (inner.width + gap) / 3).rounded(), y: inner.minY, width: third, height: inner.height)
    case .lastThird: return CGRect(x: inner.maxX - third, y: inner.minY, width: third, height: inner.height)
    case .firstTwoThirds: return CGRect(x: inner.minX, y: inner.minY, width: twoThirds, height: inner.height)
    case .lastTwoThirds: return CGRect(x: inner.maxX - twoThirds, y: inner.minY, width: twoThirds, height: inner.height)
    }
  }

  public static func nextFraction(
    _ action: WindowAction, window: CGRect, in screen: CGRect, gap: CGFloat = 0, last: CGFloat?
  ) -> CGFloat {
    let current = last ?? halfCycle.first { frame(action, in: screen, fraction: $0, gap: gap).isClose(to: window) }
    guard let current, let index = halfCycle.firstIndex(of: current) else { return halfCycle[0] }
    return halfCycle[(index + 1) % halfCycle.count]
  }
}

extension CGRect {
  func isClose(to other: CGRect) -> Bool {
    abs(minX - other.minX) <= 2 && abs(minY - other.minY) <= 2 && abs(width - other.width) <= 2
      && abs(height - other.height) <= 2
  }
}

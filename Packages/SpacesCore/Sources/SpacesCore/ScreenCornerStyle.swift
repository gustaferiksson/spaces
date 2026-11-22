import Foundation

/// Display-specific preferences. A zero radius leaves that context square.
public struct ScreenCornerStyle: Codable, Equatable, Sendable {
  public var enabled = true
  public var desktopRadius: Double = 24
  public var fullScreenRadius: Double = 24
  public var topLeft = true
  public var topRight = true
  public var bottomLeft = true
  public var bottomRight = true
  public var continuous = true

  public init() {}

  public func radius(fullScreen: Bool, width: Double, height: Double) -> Double {
    let value = fullScreen ? fullScreenRadius : desktopRadius
    guard enabled, value.isFinite, width.isFinite, height.isFinite else { return 0 }
    return max(0, min(value, 100, width / 2, height / 2))
  }
}

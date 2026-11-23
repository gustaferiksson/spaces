import Foundation

/// Display-specific corner preferences.
public struct ScreenCornerStyle: Codable, Equatable, Sendable {
  public enum SizePreset: String, Codable, Sendable {
    case smaller, standard, larger
  }

  public var enabled = true
  public var topLeft = true
  public var topRight = true
  public var bottomLeft = true
  public var bottomRight = true
  public var continuous = true
  private var storedSizePreset: SizePreset?

  public var sizePreset: SizePreset {
    get { storedSizePreset ?? .standard }
    set { storedSizePreset = newValue == .standard ? nil : newValue }
  }

  public init() {}

  public func radius(for size: CGSize) -> CGFloat {
    guard enabled, size.width.isFinite, size.height.isFinite else { return 0 }
    // macOS does not expose the panel's physical corner radius. Scale a subtle
    // software curve to the shorter edge so it stays proportional in portrait.
    let proportion: CGFloat = switch sizePreset {
    case .smaller: 0.02
    case .standard: 0.025
    case .larger: 0.03
    }
    return max(0, min(size.width, size.height)) * proportion
  }
}

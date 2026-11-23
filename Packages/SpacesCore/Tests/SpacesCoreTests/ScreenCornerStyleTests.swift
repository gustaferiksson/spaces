import Foundation
import Testing

@testable import SpacesCore

struct ScreenCornerStyleTests {
  @Test func radiusScalesWithTheShorterEdge() {
    var style = ScreenCornerStyle()
    #expect(style.radius(for: CGSize(width: 1440, height: 960)) == 24)
    #expect(style.radius(for: CGSize(width: 960, height: 2560)) == 24)
    #expect(style.radius(for: CGSize(width: 2560, height: 1440)) == 36)
    #expect(style.radius(for: .zero) == 0)
    style.sizePreset = .smaller
    #expect(style.radius(for: CGSize(width: 1440, height: 960)) < 24)
    style.sizePreset = .larger
    #expect(style.radius(for: CGSize(width: 1440, height: 960)) > 24)
    style.enabled = false
    #expect(style.radius(for: CGSize(width: 1440, height: 960)) == 0)
  }

  @Test func existingPreferencesKeepTheirShapeAndCornerChoices() throws {
    let data = Data("""
      {"enabled":true,"desktopRadius":42,"fullScreenRadius":0,"topLeft":true,
       "topRight":false,"bottomLeft":false,"bottomRight":true,"continuous":false}
      """.utf8)
    let style = try JSONDecoder().decode(ScreenCornerStyle.self, from: data)
    #expect(style.enabled)
    #expect(style.topLeft && style.bottomRight)
    #expect(!style.topRight && !style.bottomLeft && !style.continuous)
    #expect(style.sizePreset == .standard)
    #expect(style.radius(for: CGSize(width: 1440, height: 960)) == 24)
  }

  @Test func displayPreferencesRoundTripIndependently() throws {
    var external = ScreenCornerStyle()
    external.enabled = false
    external.topLeft = false
    external.bottomRight = false
    external.continuous = false
    external.sizePreset = .larger
    let styles = ["built-in-uuid": ScreenCornerStyle(), "external-uuid": external]
    let restored = try JSONDecoder().decode([String: ScreenCornerStyle].self, from: JSONEncoder().encode(styles))
    #expect(restored == styles)
  }
}

import Foundation
import Testing

@testable import SpacesCore

struct ScreenCornerStyleTests {
  @Test func desktopAndFullScreenAreIndependent() {
    var style = ScreenCornerStyle()
    style.desktopRadius = 32
    style.fullScreenRadius = 0
    #expect(style.radius(fullScreen: false, width: 1440, height: 900) == 32)
    #expect(style.radius(fullScreen: true, width: 1440, height: 900) == 0)
    style.enabled = false
    #expect(style.radius(fullScreen: false, width: 1440, height: 900) == 0)
  }

  @Test func radiusCannotExceedDisplayOrSupportedRange() {
    var style = ScreenCornerStyle()
    style.desktopRadius = 500
    #expect(style.radius(fullScreen: false, width: 1440, height: 900) == 100)
    #expect(style.radius(fullScreen: false, width: 80, height: 60) == 30)
    style.desktopRadius = -10
    #expect(style.radius(fullScreen: false, width: 1440, height: 900) == 0)
    style.desktopRadius = .nan
    #expect(style.radius(fullScreen: false, width: 1440, height: 900) == 0)
  }

  @Test func displayPreferencesRoundTripIndependently() throws {
    var external = ScreenCornerStyle()
    external.enabled = false
    external.topLeft = false
    external.bottomRight = false
    external.continuous = false
    external.fullScreenRadius = 12
    let styles = ["built-in-uuid": ScreenCornerStyle(), "external-uuid": external]
    let restored = try JSONDecoder().decode([String: ScreenCornerStyle].self, from: JSONEncoder().encode(styles))
    #expect(restored == styles)
  }
}

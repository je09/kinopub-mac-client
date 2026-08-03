import XCTest
import ViewInspector
@testable import KinoPub

@MainActor
final class ScreenHierarchyTests: XCTestCase {
  func testAuthLoadingHierarchyExposesScreenAndLoadingState() throws {
    let errorHandler = ErrorHandler()
    let model = makeAuthModel(errorHandler: errorHandler)
    let view = AuthView(model: model).environmentObject(errorHandler)

    XCTAssertNoThrow(try view.inspect().find(text: "Requesting a device code…"))
    XCTAssertNoThrow(try view.inspect().find(text: "Open Activation Page"))
  }

  func testHomeLoadingHierarchyRendersSkeletonShelf() throws {
    let errorHandler = ErrorHandler()
    let authState = AuthState(
      authService: AuthorizationServiceMock(),
      accessTokenService: AccessTokenServiceMock(),
      deviceService: DeviceServiceMock()
    )
    let view = HomeView(model: HomeModel(itemsService: VideoContentServiceMock(),
                                         authState: authState,
                                         errorHandler: errorHandler))
      .environmentObject(NavigationState())
      .environmentObject(errorHandler)
      .environmentObject(authState)

    XCTAssertNoThrow(try view.inspect().find(text: "Popular Movies"))
    XCTAssertNoThrow(try view.inspect().find(text: "Popular Series"))
  }

  func testAuthLoadedHierarchyExposesCodeAndActivationAction() throws {
    let errorHandler = ErrorHandler()
    let model = makeAuthModel(errorHandler: errorHandler)
    model.deviceCode = "ABCD-1234"
    model.verificationURL = "https://example.invalid/device"
    let view = AuthView(model: model).environmentObject(errorHandler)

    let code = try view.inspect().find(text: "ABCD-1234")
    XCTAssertEqual(try code.string(), "ABCD-1234")
    XCTAssertNoThrow(try view.inspect().find(button: "Open Activation Page"))
  }

  private func makeAuthModel(errorHandler: ErrorHandler) -> AuthModel {
    AuthModel(
      authService: AuthorizationServiceMock(),
      authState: AuthState(
        authService: AuthorizationServiceMock(),
        accessTokenService: AccessTokenServiceMock(),
        deviceService: DeviceServiceMock()
      ),
      errorHandler: errorHandler
    )
  }
}

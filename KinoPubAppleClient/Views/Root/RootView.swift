//
//  RootView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 17.07.2023.
//

import SwiftUI
import KinoPubUI
import KinoPubKit

/// Stable identifiers for UI automation and accessibility regression tests. Keep these semantic;
/// they deliberately describe user-visible regions/states rather than view implementation details.
enum AccessibilityID {
  static let authScreen = "auth.screen"
  static let authLoading = "auth.device-code.loading"
  static let authCode = "auth.device-code.value"
  static let authActivation = "auth.open-activation"
  static let homeScreen = "home.screen"
  static let homeLoading = "home.loading"
  static let detailScreen = "detail.screen"
  static let bookmarkPicker = "detail.bookmark-picker"
  static let playerError = "player.error"
}

private struct SectionEmbeddedKey: EnvironmentKey {
  static let defaultValue = false
}

/// The active hero visual, rendered behind the entire split view so poster or trailer continues
/// beneath the translucent sidebar instead of starting at the column divider.
struct WindowHeroMedia: Equatable {
  let posterURL: String?
  let videoURL: String?
  let revealVideo: Bool
  let height: CGFloat
  /// Keeps the detail-page text scrim fixed to the window during scroll rubber-banding.
  let strongTextScrim: Bool
}

struct WindowHeroMediaPreferenceKey: PreferenceKey {
  static let defaultValue: WindowHeroMedia? = nil

  static func reduce(value: inout WindowHeroMedia?, nextValue: () -> WindowHeroMedia?) {
    value = nextValue() ?? value
  }
}

extension EnvironmentValues {
  var sectionEmbedded: Bool {
    get { self[SectionEmbeddedKey.self] }
    set { self[SectionEmbeddedKey.self] = newValue }
  }
}

extension View {
  func moreBackButton() -> some View { self }

  /// Supplies every app-wide observable dependency for previews. The preview runner evaluates all
  /// providers in one process, so a missing object aborts that process before Canvas can render.
  func appPreviewEnvironment() -> some View {
    environmentObject(NavigationState())
      .environmentObject(AuthState(authService: AuthorizationServiceMock(),
                                   accessTokenService: AccessTokenServiceMock(),
                                   deviceService: DeviceServiceMock()))
      .environmentObject(ErrorHandler())
      .environmentObject(NetworkMonitor())
      .environmentObject(AppearanceSettings())
      .environmentObject(AppContext.shared.libraryState)
  }
}

struct RootView: View {
  @EnvironmentObject private var appearance: AppearanceSettings

  var body: some View {
    SidebarView()
      .tint(appearance.accent.color)
      // Custom drawing uses `Color.accentColor`; keep it synchronized with native control tint.
      .accentColor(appearance.accent.color)
  }
}

struct RootView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
      .appPreviewEnvironment()
  }
}

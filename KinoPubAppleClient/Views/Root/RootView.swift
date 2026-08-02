//
//  RootView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 17.07.2023.
//

import SwiftUI
import KinoPubUI

private struct SectionEmbeddedKey: EnvironmentKey {
  static let defaultValue = false
}

/// Home's active visual, rendered behind the entire split view so poster or trailer continues
/// beneath the translucent sidebar instead of starting at the column divider.
struct WindowHeroMedia: Equatable {
  let posterURL: String?
  let videoURL: String?
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
      .environmentObject(AppearanceSettings())
  }
}

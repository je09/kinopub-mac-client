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
  var body: some View {
    SidebarView()
      .tint(Color.KinoPub.accent)
  }
}

struct RootView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
  }
}

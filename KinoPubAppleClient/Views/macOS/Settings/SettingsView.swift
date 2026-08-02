//
//  SettingsView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 28.10.2023.
//

import SwiftUI
import KinoPubUI

struct SettingsView: View {
  @EnvironmentObject private var windowSettings: WindowSettings
  @State private var cacheSize = ImageCache.shared.formattedDiskUsage()

  var body: some View {
    TabView {
      generalSettings
        .tabItem { Label("General".localized, systemImage: "gearshape") }

      storageSettings
        .tabItem { Label("Storage".localized, systemImage: "internaldrive") }
    }
    .padding(20)
    .frame(width: 480, height: 250)
  }

  private var generalSettings: some View {
    Form {
      Section {
        Toggle("AlwaysOnTop".localized, isOn: $windowSettings.alwaysOnTop)
      }

      Section {
        LabeledContent("App version".localized,
                       value: "\(Bundle.main.appVersionLong) (\(Bundle.main.appBuild))")
      }
    }
    .formStyle(.grouped)
  }

  private var storageSettings: some View {
    Form {
      Section {
        LabeledContent("Image cache".localized, value: cacheSize)
        HStack {
          Spacer()
          Button("Clear image cache".localized) {
            ImageCache.shared.clear()
            cacheSize = ImageCache.shared.formattedDiskUsage()
          }
          .disabled(ImageCache.shared.diskUsageBytes() == 0)
        }
      }
    }
    .formStyle(.grouped)
  }
}

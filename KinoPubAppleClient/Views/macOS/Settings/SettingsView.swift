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
  @EnvironmentObject private var appearance: AppearanceSettings
  @State private var cacheSize = ImageCache.shared.formattedDiskUsage()
  
  var body: some View {
    TabView {
      appearanceSettings
        .tabItem { Label("Appearance".localized, systemImage: "paintbrush") }
      
      generalSettings
        .tabItem { Label("General".localized, systemImage: "gearshape") }
      
      storageSettings
        .tabItem { Label("Storage".localized, systemImage: "internaldrive") }
    }
    .padding(20)
    .frame(width: 520, height: 390)
  }
  
  private var appearanceSettings: some View {
    Form {
      Section("Accent color".localized) {
        accentSwatches
      }
      
      Section("Sidebar".localized) {
        Picker("Background".localized, selection: $appearance.sidebarAppearance) {
          ForEach(SidebarAppearance.allCases) { style in
            Text(style.title.localized).tag(style)
          }
        }
        .pickerStyle(.segmented)
        
        Picker("Icons".localized, selection: $appearance.sidebarIcons) {
          ForEach(SidebarIconStyle.allCases) { style in
            Text(style.title.localized).tag(style)
          }
        }
        
        Picker("Density".localized, selection: $appearance.sidebarDensity) {
          ForEach(SidebarDensity.allCases) { density in
            Text(density.title.localized).tag(density)
          }
        }
        .pickerStyle(.segmented)
        
        Toggle("Show section headers".localized, isOn: $appearance.showsSectionHeaders)
      }
      
      Section {
        HStack {
          Spacer()
          Button("Restore Defaults".localized) { appearance.reset() }
        }
      }
    }
    .formStyle(.grouped)
  }
  
  private var accentSwatches: some View {
    HStack(spacing: 14) {
      ForEach(AppAccent.allCases) { accent in
        Button {
          withAnimation(.easeInOut(duration: 0.15)) { appearance.accent = accent }
        } label: {
          ZStack {
            Circle()
              .fill(accent.color)
              .frame(width: 25, height: 25)
            if appearance.accent == accent {
              Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .shadow(radius: 1)
            }
          }
          .padding(3)
          .overlay {
            Circle()
              .stroke(appearance.accent == accent ? Color.primary : Color.clear, lineWidth: 2)
          }
        }
        .buttonStyle(.plain)
        .help(accent.title.localized)
        .accessibilityLabel(accent.title.localized)
        .accessibilityAddTraits(appearance.accent == accent ? .isSelected : [])
      }
      Spacer()
      Text(appearance.accent.title.localized)
        .foregroundStyle(.secondary)
    }
  }
  
  private var generalSettings: some View {
    Form {
      Section {
        Toggle("AlwaysOnTop".localized, isOn: $windowSettings.alwaysOnTop)
      }
      
      Section {
        LabeledContent(
          "App version".localized,
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

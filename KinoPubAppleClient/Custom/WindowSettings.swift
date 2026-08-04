//
//  WindowSettings.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 28.10.2023.
//

import AppKit
import Foundation
import SwiftUI
import KinoPubUI

enum AppAccent: String, CaseIterable, Identifiable {
  case system, kinoPub, blue, purple, pink, orange, green
  
  var id: String { rawValue }
  
  var title: String {
    switch self {
    case .system: return "System"
    case .kinoPub: return "KinoPub Red"
    case .blue: return "Blue"
    case .purple: return "Purple"
    case .pink: return "Pink"
    case .orange: return "Orange"
    case .green: return "Green"
    }
  }
  
  var color: Color {
    switch self {
    case .system: return Color(nsColor: .controlAccentColor)
    case .kinoPub: return Color.KinoPub.accent
    case .blue: return .blue
    case .purple: return .purple
    case .pink: return .pink
    case .orange: return .orange
    case .green: return .green
    }
  }
}

enum SidebarAppearance: String, CaseIterable, Identifiable {
  case system, tinted, solid
  
  var id: String { rawValue }
  var title: String {
    switch self {
    case .system: return "System"
    case .tinted: return "Tinted"
    case .solid: return "Solid"
    }
  }
}

enum SidebarIconStyle: String, CaseIterable, Identifiable {
  case monochrome, accent, colorful
  
  var id: String { rawValue }
  var title: String {
    switch self {
    case .monochrome: return "Monochrome"
    case .accent: return "Accent color"
    case .colorful: return "Colorful"
    }
  }
}

enum SidebarDensity: String, CaseIterable, Identifiable {
  case compact, comfortable, spacious
  
  var id: String { rawValue }
  var title: String {
    switch self {
    case .compact: return "Compact"
    case .comfortable: return "Comfortable"
    case .spacious: return "Spacious"
    }
  }
  
  var rowHeight: CGFloat {
    switch self {
    case .compact: return 24
    case .comfortable: return 30
    case .spacious: return 36
    }
  }
  
  var idealWidth: CGFloat {
    switch self {
    case .compact: return 220
    case .comfortable: return 250
    case .spacious: return 280
    }
  }
}

final class AppearanceSettings: ObservableObject {
  private enum Key {
    static let accent = "appearance.accent"
    static let sidebarAppearance = "appearance.sidebarStyle"
    static let sidebarIcons = "appearance.sidebarIcons"
    static let sidebarDensity = "appearance.sidebarDensity"
    static let sectionHeaders = "appearance.sidebarSectionHeaders"
  }
  
  @Published var accent: AppAccent {
    didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
  }
  @Published var sidebarAppearance: SidebarAppearance {
    didSet { defaults.set(sidebarAppearance.rawValue, forKey: Key.sidebarAppearance) }
  }
  @Published var sidebarIcons: SidebarIconStyle {
    didSet { defaults.set(sidebarIcons.rawValue, forKey: Key.sidebarIcons) }
  }
  @Published var sidebarDensity: SidebarDensity {
    didSet { defaults.set(sidebarDensity.rawValue, forKey: Key.sidebarDensity) }
  }
  @Published var showsSectionHeaders: Bool {
    didSet { defaults.set(showsSectionHeaders, forKey: Key.sectionHeaders) }
  }
  
  private let defaults: UserDefaults
  
  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    accent = AppAccent(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .system
    sidebarAppearance =
    SidebarAppearance(
      rawValue: defaults.string(forKey: Key.sidebarAppearance) ?? ""
    ) ?? .system
    sidebarIcons = SidebarIconStyle(rawValue: defaults.string(forKey: Key.sidebarIcons) ?? "") ?? .accent
    sidebarDensity =
    SidebarDensity(
      rawValue: defaults.string(forKey: Key.sidebarDensity) ?? ""
    ) ?? .comfortable
    showsSectionHeaders = defaults.object(forKey: Key.sectionHeaders) as? Bool ?? true
  }
  
  func reset() {
    accent = .system
    sidebarAppearance = .system
    sidebarIcons = .accent
    sidebarDensity = .comfortable
    showsSectionHeaders = true
  }
}

/// A class that manages the window settings, including the "always on top" feature.
class WindowSettings: ObservableObject {
  @Published var alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop") {
    didSet {
      UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
      updateWindowLevel()
    }
  }
  
  /// Updates the window level based on the "always on top" setting.
  func updateWindowLevel() {
    if alwaysOnTop {
      NSApp.windows.forEach { window in
        window.level = .floating
      }
    } else {
      NSApp.windows.forEach { window in
        window.level = .normal
      }
    }
  }
}

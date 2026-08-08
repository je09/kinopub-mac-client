//
//  KinoPubAppleClientApp.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 17.07.2023.
//

import AppKit
import SwiftUI
import KinoPubKit

enum WindowMetrics {
  static let minimum = CGSize(width: 900, height: 600)
  static let preferred = CGSize(width: 1280, height: 800)
}

@main
struct KinoPubAppleClientApp: App {

  @StateObject var navigationState = NavigationState()
  @StateObject var errorHandler = ErrorHandler()
  @StateObject var authState: AuthState
  @StateObject var networkMonitor = NetworkMonitor()

  @StateObject var windowSettings = WindowSettings()
  @StateObject var appearanceSettings = AppearanceSettings()
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

  /// Composition root: every service is created here once and injected into the view tree.
  private let dependencies: AppDependencies

  init() {
    let dependencies = AppDependencies.make()
    self.dependencies = dependencies
    _authState = StateObject(
      wrappedValue: AuthState(
        authService: dependencies.authService,
        accessTokenService: dependencies.accessTokenService,
        deviceService: dependencies.deviceService,
        onLogout: { await dependencies.libraryState.deactivate() }))
  }

  var body: some Scene {
    // A blank scene title falls back to the bundle name in AppKit. Use an invisible title so a
    // navigation destination without its own title never displays the default “KinoPub” label.
    WindowGroup("\u{200B}") {
      RootView()
        // The app is dark-only; the color assets' "Any" (light) appearance is authored inconsistently
        // (dark background but black text), so on a Light-mode Mac text/icons render invisible. Force
        // dark so the assets always resolve their Dark variant.
        .preferredColorScheme(.dark)
        .environment(\.dependencies, dependencies)
        .environmentObject(navigationState)
        .environmentObject(authState)
        .environmentObject(errorHandler)
        .environmentObject(networkMonitor)
        .environmentObject(appearanceSettings)
        .environmentObject(dependencies.libraryState)
        .onAppear { windowSettings.updateWindowLevel() }
        // Register this device's name once authorized, so it isn't listed as "unknown".
        .task(id: authState.userState) {
          if authState.userState == .authorized {
            await dependencies.deviceService.registerDeviceName()
            // Advertise HEVC/4K so kino.pub serves HEVC + HDR10 streams to the native player.
            await dependencies.deviceService.syncCapabilities()
          }
        }
        // Ask once for permission to post download-complete notifications.
        .task {
          // Hosted unit tests launch the app process; never prompt for system permissions there.
          guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
          await dependencies.downloadNotificationManager.requestPermission()
        }
        .frame(
          minWidth: WindowMetrics.minimum.width,
          minHeight: WindowMetrics.minimum.height)
    }
    .defaultSize(
      width: WindowMetrics.preferred.width,
      height: WindowMetrics.preferred.height
    )
    .windowResizability(.contentMinSize)
    .commands {
      SidebarCommands()
      KinoPubCommands(navigationState: navigationState)
    }

    Settings {
      SettingsView()
        .environmentObject(windowSettings)
        .environmentObject(appearanceSettings)
        .tint(appearanceSettings.accent.color)
        .accentColor(appearanceSettings.accent.color)
        .preferredColorScheme(.dark)
    }
  }
}

private struct KinoPubCommands: Commands {
  @ObservedObject var navigationState: NavigationState

  var body: some Commands {
    CommandMenu("Navigate") {
      Button("Home".localized) { navigationState.sidebarSelection = .new }
        .keyboardShortcut("1", modifiers: .command)
      Button("Search".localized) { navigationState.sidebarSelection = .search }
        .keyboardShortcut("f", modifiers: .command)
      Button("Watching".localized) { navigationState.sidebarSelection = .watching }
        .keyboardShortcut("2", modifiers: .command)
      Button("Bookmarks".localized) { navigationState.sidebarSelection = .bookmarks }
        .keyboardShortcut("3", modifiers: .command)
      Button("History".localized) { navigationState.sidebarSelection = .history }
        .keyboardShortcut("4", modifiers: .command)
      Button("Downloads".localized) { navigationState.sidebarSelection = .downloads }
        .keyboardShortcut("5", modifiers: .command)
      Divider()
      Button("Profile".localized) { navigationState.sidebarSelection = .profile }
        .keyboardShortcut("6", modifiers: .command)
    }
  }
}

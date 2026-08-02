//
//  SidebarView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 11.08.2023.
//

import AppKit
import Foundation
import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubKit

struct SidebarView: View {

  @Environment(\.appContext) var appContext
  @EnvironmentObject var navigationState: NavigationState
  @EnvironmentObject var errorHandler: ErrorHandler
  @EnvironmentObject var authState: AuthState
  @EnvironmentObject var networkMonitor: NetworkMonitor

  @State private var sectionBeforeOffline: SidebarItem?
  @State private var showReconnected = false

  var body: some View {
    // Show auth as full-window content (not a modal sheet): a macOS sheet disables the window's
    // close button, trapping the user on the activation screen with no way to quit the app.
    if authState.shouldShowAuthentication {
      authSheet
    } else {
      mainContent
    }
  }

  private var mainContent: some View {
    // Every section's detail NavigationStack now uses the shared `Route` element type, so the
    // NavigationSplitView detail column reconciles cleanly across section switches (no
    // AnyNavigationPath.comparisonTypeMismatch). That means no per-selection `.id` hack — the
    // sidebar keeps its identity, scroll position, and selection animation.
    NavigationSplitView(columnVisibility: $navigationState.columnVisibility) {
      Sidebar(selection: $navigationState.sidebarSelection)
    } detail: {
      SidebarNavigationDetail(selection: $navigationState.sidebarSelection)
        // Keep the offline banner inside the detail column so it never covers the sidebar.
        .safeAreaInset(edge: .top, spacing: 0) {
          if let banner = bannerState {
            OfflineBanner(tone: banner.tone, title: banner.title)
          }
        }
    }
    .background(InitialFocusReset())
    .toolbar {
      if navigationState.sidebarSelection != .search {
        ToolbarItem(placement: .primaryAction) {
          Button(action: openSearch) {
            Label("Search".localized, systemImage: "magnifyingglass")
          }
          .help("Search".localized)
        }
      }
    }
    .animation(.easeInOut(duration: 0.25), value: networkMonitor.isOnline)
    .animation(.easeInOut(duration: 0.25), value: showReconnected)
    .onChange(of: networkMonitor.isOnline) { online in
      handleConnectivityChange(online: online)
    }
    .onChange(of: navigationState.sidebarSelection) { selection in
      // Bounce a tap on a locked (network-only) row back to Downloads while offline.
      if !networkMonitor.isOnline, let selection, !selection.isAvailableOffline {
        navigationState.sidebarSelection = .downloads
      }
    }
    // Tapping a download notification selects the Downloads section.
    .onReceive(NotificationCenter.default.publisher(for: .openDownloads)) { _ in
      navigationState.sidebarSelection = .downloads
    }
    .environmentObject(navigationState)
    .environmentObject(errorHandler)
    .task {
      await authState.check()
    }
  }

  private func openSearch() {
    navigationState.sidebarSelection = .search
    focusToolbarSearchField()
  }

  /// The searchable field belongs to AVKit's/AppKit's merged window toolbar and appears one run-loop
  /// after the detail destination changes. Retry briefly, then hand it first responder status.
  private func focusToolbarSearchField(attemptsRemaining: Int = 6) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
      if let window = NSApp.keyWindow,
         let item = window.toolbar?.items.compactMap({ $0 as? NSSearchToolbarItem }).first {
        window.makeFirstResponder(item.searchField)
      } else if attemptsRemaining > 1 {
        self.focusToolbarSearchField(attemptsRemaining: attemptsRemaining - 1)
      }
    }
  }

  // MARK: - Offline mode

  private var bannerState: (tone: OfflineBanner.Tone, title: String)? {
    if !networkMonitor.isOnline {
      return (.warning, "You're offline — your downloads are available".localized)
    }
    if showReconnected {
      return (.success, "Back online".localized)
    }
    return nil
  }

  private func handleConnectivityChange(online: Bool) {
    if !online {
      let current = navigationState.sidebarSelection ?? .new
      if !current.isAvailableOffline { sectionBeforeOffline = current }
      navigationState.sidebarSelection = .downloads
    } else {
      showReconnected = true
      if navigationState.downloadsRoutes.isEmpty, let previous = sectionBeforeOffline {
        navigationState.sidebarSelection = previous
      }
      sectionBeforeOffline = nil
      Task {
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        showReconnected = false
      }
    }
  }

  var authSheet: some View {
    AuthView(model: AuthModel(authService: appContext.authService,
                              authState: authState,
                              errorHandler: errorHandler))
  }

}

/// NavigationSplitView assigns keyboard focus to its sidebar-toggle toolbar item when the window
/// first opens. Clear that automatic selection without affecting deliberate keyboard navigation.
private struct InitialFocusReset: NSViewRepresentable {
  func makeNSView(context: Context) -> FocusResetView { FocusResetView() }
  func updateNSView(_ view: FocusResetView, context: Context) {}

  final class FocusResetView: NSView {
    private var didReset = false

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard !didReset, let window else { return }
      didReset = true
      DispatchQueue.main.async { [weak window] in window?.makeFirstResponder(nil) }
      // SwiftUI installs its automatic toolbar key view one run-loop later.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak window] in
        window?.makeFirstResponder(nil)
      }
    }
  }
}

struct SideBarView_Previews: PreviewProvider {
  static var previews: some View {
    SidebarView()
  }
}

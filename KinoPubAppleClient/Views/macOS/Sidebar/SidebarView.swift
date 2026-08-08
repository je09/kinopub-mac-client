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
  
  @Environment(\.dependencies) var dependencies
  @EnvironmentObject var navigationState: NavigationState
  @EnvironmentObject var errorHandler: ErrorHandler
  @EnvironmentObject var authState: AuthState
  @EnvironmentObject var networkMonitor: NetworkMonitor
  
  @State private var sectionBeforeOffline: SidebarItem?
  @State private var showReconnected = false
  @State private var windowHeroMedia: WindowHeroMedia?
  @State private var readyHeroVideoURL: String?
  
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
    .background {
      ZStack {
        Color.KinoPub.background
        
        if let video = windowHeroMedia?.videoURL, let url = URL(string: video) {
          CinematicBackdropVideo(
            url: url,
            isPlaying: windowHeroMedia?.revealVideo == true
          ) {
            guard windowHeroMedia?.videoURL == video else { return }
            withAnimation(.easeInOut(duration: 0.7)) { readyHeroVideoURL = video }
          }
          .id(video)
        }
        
        if let poster = windowHeroMedia?.posterURL {
          CachedAsyncImage(url: URL(string: poster)) { image in
            image
              .resizable()
              .renderingMode(.original)
              .aspectRatio(contentMode: .fill)
          } placeholder: {
            Color.KinoPub.background
          }
          .id(poster)
          .transition(.opacity)
          .opacity(shouldRevealHeroVideo ? 0 : 1)
        }
        
        if let media = windowHeroMedia {
          windowHeroTextGradient(height: media.height, strong: media.strongTextScrim)
        }
      }
      .animation(.easeInOut(duration: 0.7), value: windowHeroMedia?.posterURL)
      .animation(.easeInOut(duration: 0.7), value: shouldRevealHeroVideo)
      .clipped()
      .ignoresSafeArea()
    }
    .onPreferenceChange(WindowHeroMediaPreferenceKey.self) { media in
      // Preference delivery occurs during SwiftUI's update pass. Defer @State writes to the next
      // main-loop turn to avoid "Publishing changes from within view updates" and undefined layout.
      DispatchQueue.main.async {
        if media?.videoURL != windowHeroMedia?.videoURL { readyHeroVideoURL = nil }
        withAnimation(.easeInOut(duration: 0.7)) { windowHeroMedia = media }
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
      // Hosted unit tests launch the app; avoid keychain access and token refresh in that process.
      guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
      await authState.check()
    }
  }
  
  private var shouldRevealHeroVideo: Bool {
    guard let media = windowHeroMedia, media.revealVideo, let video = media.videoURL else { return false }
    return readyHeroVideoURL == video
  }
  
  /// Window-level artwork needs a window-level scrim so both poster/video and their gradient span
  /// behind the sidebar and detail column. The lower edge follows each screen's hero height.
  @ViewBuilder
  private func windowHeroTextGradient(height: CGFloat, strong: Bool) -> some View {
    if strong {
      // Keep this scrim at window level rather than inside the ScrollView. It therefore continues
      // behind the hero when macOS rubber-bands the detail page downward instead of exposing a
      // bright, unshaded strip above the moving content.
      GeometryReader { proxy in
        // The artwork/video is window-sized, so its scrim must be window-sized too. Keep the
        // original hero ramp, then hold its darkest value below the hero rather than ending it.
        // Drawing here (outside NavigationSplitView's columns) also carries it beneath the sidebar
        // and titlebar instead of clipping it to the detail page.
        let heroEnd = min(max(height / max(proxy.size.height, 1), 0), 1)
        ZStack {
          LinearGradient(
            stops: [
              .init(color: .black.opacity(0.48), location: 0),
              .init(color: .black.opacity(0.52), location: heroEnd * 0.58),
              .init(color: .black.opacity(0.88), location: heroEnd),
              .init(color: .black.opacity(0.88), location: 1),
            ], startPoint: .top, endPoint: .bottom)
          
          LinearGradient(
            stops: [
              .init(color: .black.opacity(0.28), location: 0),
              .init(color: .black.opacity(0.12), location: 0.62),
              .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
      }
      .allowsHitTesting(false)
    } else {
      let gradientHeight = min(height * 0.76, 420)
      VStack(spacing: 0) {
        Spacer().frame(height: max(height - gradientHeight, 0))
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0),
            .init(color: .black.opacity(0.22), location: 0.42),
            .init(color: .black.opacity(0.82), location: 1),
          ], startPoint: .top, endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: gradientHeight)
        Spacer(minLength: 0)
      }
      .allowsHitTesting(false)
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
    AuthView(
      model: AuthModel(
        authService: dependencies.authService,
        authState: authState,
        errorHandler: errorHandler))
  }
  
}

struct SideBarView_Previews: PreviewProvider {
  static var previews: some View {
    SidebarView()
      .appPreviewEnvironment()
  }
}

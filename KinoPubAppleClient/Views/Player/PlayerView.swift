//
//  PlayerView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 3.08.2023.
//

import Foundation
import SwiftUI
import AVKit

struct PlayerView: View {

  @StateObject private var playerManager: PlayerManager
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var navigationState: NavigationState
  @State private var columnVisibilityBeforePlayback: NavigationSplitViewVisibility?

  init(manager: @autoclosure @escaping () -> PlayerManager) {
    _playerManager = StateObject(wrappedValue: manager())
  }

  var body: some View {
    // Native macOS player (AVKit): floating controls, scrubber, volume, fullscreen, and PiP.
    MacNativePlayer(
      player: playerManager.player,
      streamQuality: playerManager.streamQuality,
      maximumStreamResolution: playerManager.maximumStreamResolution,
      showsQualityControl: playerManager.offersStreamQualitySelection,
      onQualityChange: playerManager.setStreamQuality
    )
    // The window titlebar is a transient overlay; video fills its reserved safe area beneath it.
    .ignoresSafeArea(.all)
    .onExitCommand { closePlayer() }
    .onAppear {
      hideSidebarForPlayback()
      playerManager.player.play()
      Task {
        await playerManager.fetchWatchMark()
        playerManager.seekToContinueWatching()
      }
    }
    .onChange(of: playerManager.shouldReturnToContent) { shouldReturn in
      if shouldReturn { closePlayer() }
    }
    .onDisappear {
      playerManager.stopPlayback()
      restoreSidebarAfterPlayback()
    }
    .playbackErrorAlert(
      title: playerManager.playbackErrorTitle,
      error: $playerManager.playbackError,
      onDismiss: { closePlayer() })
  }

  private func closePlayer() {
    playerManager.stopPlayback()
    restoreSidebarAfterPlayback()
    dismiss()
  }

  private func hideSidebarForPlayback() {
    guard columnVisibilityBeforePlayback == nil else { return }
    columnVisibilityBeforePlayback = navigationState.columnVisibility
    navigationState.columnVisibility = .detailOnly
  }

  private func restoreSidebarAfterPlayback() {
    guard let previous = columnVisibilityBeforePlayback else { return }
    withAnimation(.easeInOut(duration: 0.25)) {
      navigationState.columnVisibility = previous
    }
    columnVisibilityBeforePlayback = nil
  }
}

/// The native macOS video view (AVKit `AVPlayerView`) with standard playback controls.
private struct MacNativePlayer: NSViewRepresentable {
  let player: AVPlayer
  let streamQuality: StreamQuality
  let maximumStreamResolution: Int?
  let showsQualityControl: Bool
  let onQualityChange: (StreamQuality) -> Void

  func makeNSView(context: Context) -> PlayerChromeView {
    // PiP inserts an AVKit-owned player-layer view alongside this view. Returning the AVPlayerView
    // itself is required: when it is nested below another representable view, AVKit instead tries
    // to insert that layer into NSHostingController.view, which AppKit explicitly rejects.
    let view = PlayerChromeView()
    view.controlsStyle = .floating
    view.showsFullScreenToggleButton = true
    view.allowsPictureInPicturePlayback = true
    view.videoGravity = .resizeAspect
    view.focusRingType = .none
    view.player = player
    view.pictureInPictureDelegate = view
    view.observeChrome(for: player)
    view.configureQualityControl(
      selection: streamQuality,
      maximumResolution: maximumStreamResolution,
      isVisible: showsQualityControl,
      onChange: onQualityChange)
    return view
  }

  func updateNSView(_ view: PlayerChromeView, context: Context) {
    if view.player !== player { view.player = player }
    view.observeChrome(for: player)
    view.configureQualityControl(
      selection: streamQuality,
      maximumResolution: maximumStreamResolution,
      isVisible: showsQualityControl,
      onChange: onQualityChange)
  }

  static func dismantleNSView(_ view: PlayerChromeView, coordinator: ()) {
    view.pictureInPictureDelegate = nil
    view.restoreWindowChrome()
    view.player?.pause()
    view.player = nil
  }
}

private extension View {
  /// Presents the player's failure diagnosis (and pops the player on dismiss) so an unplayable
  /// stream is visible on-device rather than just a silent crossed-out play.
  func playbackErrorAlert(
    title: String,
    error: Binding<String?>,
    onDismiss: @escaping () -> Void
  ) -> some View {
    alert(
      title.localized,
      isPresented: Binding(
        get: { error.wrappedValue != nil },
        set: { if !$0 { error.wrappedValue = nil } })
    ) {
      Button("OK", role: .cancel) { onDismiss() }
    } message: {
      if let message = error.wrappedValue {
        Text(message)
          .accessibilityIdentifier(AccessibilityID.playerError)
      }
    }
  }
}

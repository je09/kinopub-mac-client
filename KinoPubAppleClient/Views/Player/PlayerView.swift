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

  init(manager: @autoclosure @escaping () -> PlayerManager) {
    _playerManager = StateObject(wrappedValue: manager())
  }

  var body: some View {
    // Native macOS player (AVKit): floating controls, scrubber, volume, the system fullscreen toggle
    // and PiP — the standard QuickTime-style experience. No custom close button; exit with Esc, or the
    // standard back button in the window toolbar once out of fullscreen.
    MacNativePlayer(player: playerManager.player)
      // The window titlebar is a transient overlay; video fills its reserved safe area beneath it.
      .ignoresSafeArea(.all)
      .onExitCommand { closePlayer() }
      .onAppear {
        toggleSidebar()
        playerManager.player.play()
        Task {
          await playerManager.fetchWatchMark()
          playerManager.seekToContinueWatching()
        }
      }
    .playbackErrorAlert($playerManager.playbackError, onDismiss: { dismiss() })
  }

  private func closePlayer() {
    playerManager.player.pause()
    dismiss()
  }

  private func toggleSidebar() {
    navigationState.columnVisibility = .detailOnly
  }
}

/// The native macOS video view (AVKit `AVPlayerView`) — floating controls, scrubber, volume, the
/// system fullscreen toggle and PiP, matching how video plays elsewhere on the system.
private struct MacNativePlayer: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> PlayerChromeView {
    let view = PlayerChromeView()
    view.player = player
    view.controlsStyle = .floating
    view.showsFullScreenToggleButton = true
    view.allowsPictureInPicturePlayback = true
    view.videoGravity = .resizeAspect
    view.observeToolbar(for: player)
    return view
  }

  func updateNSView(_ view: PlayerChromeView, context: Context) {
    if view.player !== player { view.player = player }
    view.observeToolbar(for: player)
  }

  static func dismantleNSView(_ view: PlayerChromeView, coordinator: ()) {
    view.restoreToolbar()
    view.player?.pause()
    view.player = nil
  }
}

/// Makes titlebar controls a transient overlay, like AVKit's controls, without changing the
/// content layout. `fullSizeContentView` is the AppKit-supported way to avoid a toolbar resize.
private final class PlayerChromeView: AVPlayerView {
  private var trackingArea: NSTrackingArea?
  private var rateObservation: NSKeyValueObservation?
  private weak var observedPlayer: AVPlayer?
  private var hideWorkItem: DispatchWorkItem?
  private var originalStyleMask: NSWindow.StyleMask?
  private var originalTitleVisibility: NSWindow.TitleVisibility?
  private var originalTitlebarTransparency: Bool?
  private var originalToolbarVisibility: Bool?

  deinit { hideWorkItem?.cancel() }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    configureOverlayTitlebar()
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseMoved(with event: NSEvent) { showWindowControls() }
  override func mouseDown(with event: NSEvent) {
    showWindowControls()
    super.mouseDown(with: event)
  }

  func observeToolbar(for player: AVPlayer) {
    guard player !== observedPlayer else { return }
    observedPlayer = player
    rateObservation = player.observe(\.rate, options: [.initial, .new]) { [weak self] player, _ in
      DispatchQueue.main.async { self?.updateWindowControls(forPlaying: player.rate > 0) }
    }
  }

  func restoreToolbar() {
    guard let window, let originalStyleMask else { return }
    window.styleMask = originalStyleMask
    window.titleVisibility = originalTitleVisibility ?? .visible
    window.titlebarAppearsTransparent = originalTitlebarTransparency ?? false
    if let originalToolbarVisibility { window.toolbar?.isVisible = originalToolbarVisibility }
    setWindowButtons(hidden: false, in: window)
  }

  private func configureOverlayTitlebar() {
    guard let window else { return }
    if originalStyleMask == nil {
      originalStyleMask = window.styleMask
      originalTitleVisibility = window.titleVisibility
      originalTitlebarTransparency = window.titlebarAppearsTransparent
      originalToolbarVisibility = window.toolbar?.isVisible
    }
    window.styleMask.insert(.fullSizeContentView)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    // Hide the app navigation toolbar permanently in playback; only native traffic lights overlay.
    window.toolbar?.isVisible = false
  }

  private func updateWindowControls(forPlaying isPlaying: Bool) {
    hideWorkItem?.cancel()
    guard isPlaying else {
      showWindowControls()
      return
    }
    let work = DispatchWorkItem { [weak self] in self?.hideWindowControls() }
    hideWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
  }

  private func showWindowControls() {
    hideWorkItem?.cancel()
    configureOverlayTitlebar()
    guard let window else { return }
    setWindowButtons(hidden: false, in: window)
    if observedPlayer?.rate ?? 0 > 0 { updateWindowControls(forPlaying: true) }
  }

  private func hideWindowControls() {
    guard observedPlayer?.rate ?? 0 > 0, let window else { return }
    setWindowButtons(hidden: true, in: window)
  }

  private func setWindowButtons(hidden: Bool, in window: NSWindow) {
    window.standardWindowButton(.closeButton)?.isHidden = hidden
    window.standardWindowButton(.miniaturizeButton)?.isHidden = hidden
    window.standardWindowButton(.zoomButton)?.isHidden = hidden
  }
}

private extension View {
  /// Presents the player's failure diagnosis (and pops the player on dismiss) so an unplayable
  /// stream is visible on-device rather than just a silent crossed-out play.
  func playbackErrorAlert(_ error: Binding<String?>, onDismiss: @escaping () -> Void) -> some View {
    alert("Playback failed".localized,
          isPresented: Binding(get: { error.wrappedValue != nil },
                               set: { if !$0 { error.wrappedValue = nil } })) {
      Button("OK", role: .cancel) { onDismiss() }
    } message: {
      Text(error.wrappedValue ?? "")
    }
  }
}

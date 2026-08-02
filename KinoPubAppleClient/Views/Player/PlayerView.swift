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
    // Native macOS player (AVKit): floating controls, scrubber, volume, the system fullscreen toggle
    // and PiP — the standard QuickTime-style experience. No custom close button; exit with Esc, or the
    // standard back button in the window toolbar once out of fullscreen.
    MacNativePlayer(player: playerManager.player)
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
      .onDisappear { restoreSidebarAfterPlayback() }
    .playbackErrorAlert($playerManager.playbackError, onDismiss: { closePlayer() })
  }

  private func closePlayer() {
    playerManager.player.pause()
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

/// The native macOS video view (AVKit `AVPlayerView`) — floating controls, scrubber, volume, the
/// system fullscreen toggle and PiP, matching how video plays elsewhere on the system.
private struct MacNativePlayer: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> PlayerContainerView {
    let view = PlayerContainerView()
    view.playerView.player = player
    view.playerView.observeToolbar(for: player)
    return view
  }

  func updateNSView(_ view: PlayerContainerView, context: Context) {
    if view.playerView.player !== player { view.playerView.player = player }
    view.playerView.observeToolbar(for: player)
  }

  static func dismantleNSView(_ view: PlayerContainerView, coordinator: ()) {
    view.playerView.restoreToolbar()
    view.playerView.player?.pause()
    view.playerView.player = nil
    view.unmountPlayer()
  }
}

/// Keep AVKit below a regular AppKit container rather than making it SwiftUI's representable root.
private final class PlayerContainerView: NSView {
  let playerView = PlayerChromeView()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    playerView.controlsStyle = .floating
    playerView.showsFullScreenToggleButton = true
    playerView.allowsPictureInPicturePlayback = true
    playerView.videoGravity = .resizeAspect
    playerView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(playerView)
    NSLayoutConstraint.activate([
      playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
      playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
      playerView.topAnchor.constraint(equalTo: topAnchor),
      playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  func unmountPlayer() {
    playerView.removeFromSuperview()
  }
}

/// Makes titlebar controls a transient overlay, like AVKit's controls, without changing the
/// content layout. `fullSizeContentView` is the AppKit-supported way to avoid a toolbar resize.
private final class PlayerChromeView: AVPlayerView {
  private var trackingArea: NSTrackingArea?
  private var rateObservation: NSKeyValueObservation?
  private weak var observedPlayer: AVPlayer?
  private var hideWorkItem: DispatchWorkItem?
  private weak var hostWindow: NSWindow?
  private var originalStyleMask: NSWindow.StyleMask?
  private var originalTitleVisibility: NSWindow.TitleVisibility?
  private var originalTitlebarTransparency: Bool?
  private var originalToolbarVisibility: Bool?
  private var didClearInitialControlFocus = false

  deinit { hideWorkItem?.cancel() }

  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // AVKit can temporarily attach parts of the player to its own PiP window. Keep all titlebar
    // changes scoped to the app window; mutating the private PiP window can crash AVKit and leave
    // the app toolbar hidden when playback closes.
    if hostWindow == nil { hostWindow = window }
    if window === hostWindow { configureOverlayTitlebar() }
    // AVKit focuses the play/pause button when playback opens, leaving an accent-colored selection
    // behind even though the user did not navigate to it. Keep keyboard handling on the player view
    // itself while leaving the controls visually neutral.
    if !didClearInitialControlFocus {
      didClearInitialControlFocus = true
      DispatchQueue.main.async { [weak self] in
        guard let self, let window = self.window else { return }
        window.makeFirstResponder(self)
      }
    }
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
    guard let window = hostWindow, let originalStyleMask else { return }
    window.styleMask = originalStyleMask
    window.titleVisibility = originalTitleVisibility ?? .visible
    window.titlebarAppearsTransparent = originalTitlebarTransparency ?? false
    if let originalToolbarVisibility { window.toolbar?.isVisible = originalToolbarVisibility }
    setWindowButtons(hidden: false, in: window)
  }

  private func configureOverlayTitlebar() {
    guard let window = hostWindow, self.window === window else { return }
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
    guard let window = hostWindow else { return }
    setWindowButtons(hidden: false, in: window)
    if observedPlayer?.rate ?? 0 > 0 { updateWindowControls(forPlaying: true) }
  }

  private func hideWindowControls() {
    guard observedPlayer?.rate ?? 0 > 0, let window = hostWindow else { return }
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

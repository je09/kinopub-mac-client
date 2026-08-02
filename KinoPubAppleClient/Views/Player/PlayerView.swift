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
    // Native macOS player (AVKit): floating controls, scrubber, volume, and the system fullscreen
    // toggle. PiP is deliberately disabled: AVKit's PiP service crashes this ad-hoc distributed app
    // during the window hand-off. Re-enable only after a crash-log-backed lifecycle fix.
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
      .onChange(of: playerManager.shouldReturnToContent) { shouldReturn in
        if shouldReturn { closePlayer() }
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

/// The native macOS video view (AVKit `AVPlayerView`) with standard playback controls.
private struct MacNativePlayer: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> PlayerContainerView {
    let view = PlayerContainerView()
    view.playerView.player = player
    view.playerView.observeChrome(for: player)
    return view
  }

  func updateNSView(_ view: PlayerContainerView, context: Context) {
    if view.playerView.player !== player { view.playerView.player = player }
    view.playerView.observeChrome(for: player)
  }

  static func dismantleNSView(_ view: PlayerContainerView, coordinator: ()) {
    view.playerView.restoreWindowChrome()
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
    playerView.allowsPictureInPicturePlayback = false
    playerView.videoGravity = .resizeAspect
    playerView.focusRingType = .none
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

/// Keeps the app titlebar in sync with AVKit's floating controls: mouse activity or pause shows
/// both; after a short period of active playback both disappear. PiP remains disabled, so AVKit
/// never reparents this view into a private window while we adjust the host window.
private final class PlayerChromeView: AVPlayerView {
  private weak var hostWindow: NSWindow?
  private weak var observedPlayer: AVPlayer?
  private var rateObservation: NSKeyValueObservation?
  private var trackingArea: NSTrackingArea?
  private var hideWorkItem: DispatchWorkItem?
  private var mouseUpMonitor: Any?
  private var originalStyleMask: NSWindow.StyleMask?
  private var originalTitleVisibility: NSWindow.TitleVisibility?
  private var originalTitlebarTransparency: Bool?
  private var originalToolbarVisibility: Bool?
  private var didClearInitialControlFocus = false
  private var gestureSeekTarget: Double?
  private var wasPlayingBeforeGestureSeek = false
  private var gestureSeekEndWorkItem: DispatchWorkItem?

  deinit {
    hideWorkItem?.cancel()
    gestureSeekEndWorkItem?.cancel()
    if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
  }

  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }
    if hostWindow == nil { hostWindow = window }
    guard window === hostWindow else { return }
    configureOverlayTitlebar()
    showWindowChrome()

    // AVKit otherwise auto-focuses and accent-highlights its first playback control on entry. Keep
    // keyboard events on the player itself without selecting any individual button.
    if !didClearInitialControlFocus {
      didClearInitialControlFocus = true
      clearControlFocus(in: window)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak window] in
        guard let self, let window, self.window === window else { return }
        self.clearControlFocus(in: window)
      }
    }

    if mouseUpMonitor == nil {
      mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self, weak window] event in
        guard let self, let window, event.window === window else { return event }
        let point = self.convert(event.locationInWindow, from: nil)
        guard self.bounds.contains(point) else { return event }
        // AVKit makes a clicked play/pause/seek control the first responder and leaves it tinted.
        // Clear that transient selection after AppKit finishes dispatching the click.
        DispatchQueue.main.async { [weak self, weak window] in
          guard let self, let window else { return }
          self.clearControlFocus(in: window)
        }
        return event
      }
    }
  }

  private func clearControlFocus(in window: NSWindow) {
    window.makeFirstResponder(self)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(rect: .zero,
                              options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseMoved(with event: NSEvent) {
    showWindowChrome()
    super.mouseMoved(with: event)
  }

  override func mouseDown(with event: NSEvent) {
    showWindowChrome()
    super.mouseDown(with: event)
  }

  /// Two-finger horizontal scrolling scrubs continuously in either direction. Keep one logical
  /// target across gesture and momentum events so rapid deltas do not repeatedly seek from a stale
  /// `currentTime`; pause while scrubbing, then resume only if playback was active beforehand.
  override func scrollWheel(with event: NSEvent) {
    let horizontal = event.scrollingDeltaX
    guard abs(horizontal) > abs(event.scrollingDeltaY), abs(horizontal) > 0.01,
          let player,
          let item = player.currentItem,
          item.status == .readyToPlay else {
      super.scrollWheel(with: event)
      return
    }

    let duration = item.duration.seconds
    guard duration.isFinite, duration > 0 else {
      super.scrollWheel(with: event)
      return
    }

    showWindowChrome()
    if gestureSeekTarget == nil {
      gestureSeekTarget = player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0
      wasPlayingBeforeGestureSeek = player.rate > 0
      player.pause()
    }

    // Precise trackpad deltas are points; this gives a deliberate swipe roughly 8–15 seconds while
    // retaining frame-level control for small movements. Traditional wheel ticks move farther.
    let sensitivity = event.hasPreciseScrollingDeltas ? 0.10 : 2.0
    let target = min(max((gestureSeekTarget ?? 0) + horizontal * sensitivity, 0), max(duration - 0.05, 0))
    gestureSeekTarget = target
    player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                toleranceBefore: CMTime(seconds: 0.12, preferredTimescale: 600),
                toleranceAfter: CMTime(seconds: 0.12, preferredTimescale: 600))

    gestureSeekEndWorkItem?.cancel()
    let finish = DispatchWorkItem { [weak self] in self?.finishGestureSeek() }
    gestureSeekEndWorkItem = finish
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: finish)

    if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
      finishGestureSeek()
    }
  }

  private func finishGestureSeek() {
    gestureSeekEndWorkItem?.cancel()
    gestureSeekEndWorkItem = nil
    guard let player, let target = gestureSeekTarget else { return }
    gestureSeekTarget = nil
    let resume = wasPlayingBeforeGestureSeek
    wasPlayingBeforeGestureSeek = false
    player.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero) { finished in
      guard finished, resume else { return }
      DispatchQueue.main.async { [weak player] in player?.play() }
    }
  }

  func observeChrome(for player: AVPlayer) {
    guard player !== observedPlayer else { return }
    observedPlayer = player
    rateObservation = player.observe(\.rate, options: [.initial, .new]) { [weak self] player, _ in
      Task { @MainActor in
        guard let self else { return }
        if player.rate > 0 {
          self.scheduleChromeHide()
        } else {
          self.showWindowChrome(scheduleHide: false)
        }
      }
    }
  }

  func restoreWindowChrome() {
    hideWorkItem?.cancel()
    guard let window = hostWindow else { return }
    if let originalStyleMask { window.styleMask = originalStyleMask }
    window.titleVisibility = originalTitleVisibility ?? .visible
    window.titlebarAppearsTransparent = originalTitlebarTransparency ?? false
    if let originalToolbarVisibility { window.toolbar?.isVisible = originalToolbarVisibility }
    setTrafficLights(hidden: false, in: window)
  }

  private func configureOverlayTitlebar() {
    guard let window = hostWindow else { return }
    if originalStyleMask == nil {
      originalStyleMask = window.styleMask
      originalTitleVisibility = window.titleVisibility
      originalTitlebarTransparency = window.titlebarAppearsTransparent
      originalToolbarVisibility = window.toolbar?.isVisible
    }
    window.styleMask.insert(.fullSizeContentView)
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
  }

  private func showWindowChrome(scheduleHide: Bool = true) {
    hideWorkItem?.cancel()
    configureOverlayTitlebar()
    guard let window = hostWindow else { return }
    window.toolbar?.isVisible = originalToolbarVisibility ?? true
    setTrafficLights(hidden: false, in: window)
    if scheduleHide, observedPlayer?.rate ?? 0 > 0 { scheduleChromeHide() }
  }

  private func scheduleChromeHide() {
    hideWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.hideWindowChrome() }
    hideWorkItem = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
  }

  private func hideWindowChrome() {
    guard observedPlayer?.rate ?? 0 > 0, let window = hostWindow else { return }
    window.toolbar?.isVisible = false
    setTrafficLights(hidden: true, in: window)
  }

  private func setTrafficLights(hidden: Bool, in window: NSWindow) {
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
      if let message = error.wrappedValue { Text(message) }
    }
  }
}

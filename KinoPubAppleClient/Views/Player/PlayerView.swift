//
//  PlayerView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 3.08.2023.
//

import Foundation
import SwiftUI
import AVKit
import QuartzCore

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
    MacNativePlayer(player: playerManager.player,
                    streamQuality: playerManager.streamQuality,
                    maximumStreamResolution: playerManager.maximumStreamResolution,
                    showsQualityControl: playerManager.offersStreamQualitySelection,
                    onQualityChange: playerManager.setStreamQuality)
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
    .playbackErrorAlert(title: playerManager.playbackErrorTitle,
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
    view.configureQualityControl(selection: streamQuality,
                                 maximumResolution: maximumStreamResolution,
                                 isVisible: showsQualityControl,
                                 onChange: onQualityChange)
    return view
  }

  func updateNSView(_ view: PlayerChromeView, context: Context) {
    if view.player !== player { view.player = player }
    view.observeChrome(for: player)
    view.configureQualityControl(selection: streamQuality,
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

/// Keeps the app titlebar in sync with AVKit's floating controls: mouse activity or pause shows
/// both; after a short period of active playback both disappear. AVKit can reparent this view for
/// PiP, so all window changes remain scoped to the original host window.
private final class PlayerChromeView: AVPlayerView, AVPlayerViewPictureInPictureDelegate {
  private weak var hostWindow: NSWindow?
  private weak var observedPlayer: AVPlayer?
  private var rateObservation: NSKeyValueObservation?
  private var trackingArea: NSTrackingArea?
  private var hideWorkItem: DispatchWorkItem?
  private var chromeTransitionGeneration = 0
  private var mouseUpMonitor: Any?
  private var windowFocusObservers: [NSObjectProtocol] = []
  private var displaySleepActivity: NSObjectProtocol?
  private var insertedFullSizeContentView = false
  private var originalTitleVisibility: NSWindow.TitleVisibility?
  private var originalTitlebarTransparency: Bool?
  private var originalToolbarVisibility: Bool?
  private var didClearInitialControlFocus = false
  private var gestureSeekTarget: Double?
  private var wasPlayingBeforeGestureSeek = false
  private var gestureSeekEndWorkItem: DispatchWorkItem?
  private var qualityMenu: NSMenu?
  private var qualityMenuRootItem: NSMenuItem?
  private var qualityMenuItems: [NSMenuItem] = []
  private var onQualityChange: ((StreamQuality) -> Void)?

  deinit {
    hideWorkItem?.cancel()
    gestureSeekEndWorkItem?.cancel()
    if let mouseUpMonitor { NSEvent.removeMonitor(mouseUpMonitor) }
    windowFocusObservers.forEach(NotificationCenter.default.removeObserver)
    stopPreventingDisplaySleep()
  }

  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }
    if hostWindow == nil {
      hostWindow = window
      observeWindowFocus(window)
    }
    guard window === hostWindow else { return }
    configureOverlayTitlebar()
    showWindowChrome()
    updateDisplaySleepPrevention()

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

  // Keep the SwiftUI player route mounted for the entire PiP session. Letting AVKit automatically
  // dismiss or miniaturize this host races its layer hand-off against SwiftUI's hosting hierarchy.
  // The documented delegate also gives AVKit an explicit, synchronous restoration acknowledgement.
  func playerViewShouldAutomaticallyDismissAtPicture(inPictureStart playerView: AVPlayerView) -> Bool {
    false
  }

  func playerViewWillStartPicture(inPicture playerView: AVPlayerView) {
    showWindowChrome(scheduleHide: false)
  }

  func playerView(_ playerView: AVPlayerView,
                  restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
    showWindowChrome(scheduleHide: false)
    completionHandler(true)
  }

  /// Uses AVKit's native action menu so quality appears with the standard audio, subtitle,
  /// zoom, and playback-speed controls, including in fullscreen.
  func configureQualityControl(selection: StreamQuality,
                               maximumResolution: Int?,
                               isVisible: Bool,
                               onChange: @escaping (StreamQuality) -> Void) {
    self.onQualityChange = onChange

    if qualityMenu == nil {
      let menu = NSMenu(title: "Video Quality".localized)
      let qualityItem = NSMenuItem(title: "Video Quality".localized,
                                   action: nil,
                                   keyEquivalent: "")
      let submenu = NSMenu(title: "Video Quality".localized)
      qualityMenuItems = StreamQuality.allCases.map { quality in
        let item = NSMenuItem(title: quality.title,
                              action: #selector(qualitySelectionChanged(_:)),
                              keyEquivalent: "")
        item.target = self
        item.representedObject = quality.rawValue
        submenu.addItem(item)
        return item
      }
      menu.addItem(qualityItem)
      menu.setSubmenu(submenu, for: qualityItem)
      qualityMenuRootItem = qualityItem
      qualityMenu = menu
    }

    qualityMenuRootItem?.title = maximumResolution.map {
      "\("Video Quality".localized) · \($0)p"
    } ?? "Video Quality".localized

    // A cap above the source maximum has the same effect as Auto for this title. Hide those
    // impossible choices while preserving the stored preference for titles that do offer them.
    let effectiveSelection: StreamQuality
    if let maximumResolution,
       let selectedCap = selection.maxResolution,
       Int(selectedCap.height) > maximumResolution {
      effectiveSelection = .auto
    } else {
      effectiveSelection = selection
    }
    for item in qualityMenuItems {
      guard let rawValue = item.representedObject as? String,
            let quality = StreamQuality(rawValue: rawValue) else { continue }
      item.isHidden = maximumResolution.map { maximum in
        quality.maxResolution.map { Int($0.height) > maximum } ?? false
      } ?? false
      item.state = quality == effectiveSelection ? .on : .off
    }
    actionPopUpButtonMenu = isVisible ? qualityMenu : nil
  }

  @objc private func qualitySelectionChanged(_ sender: NSMenuItem) {
    guard let rawValue = sender.representedObject as? String,
          let quality = StreamQuality(rawValue: rawValue) else { return }
    onQualityChange?(quality)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(rect: .zero,
                              options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                              owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    showWindowChrome(scheduleHide: window?.isKeyWindow ?? true)
    super.mouseEntered(with: event)
  }

  override func mouseExited(with event: NSEvent) {
    if window?.isKeyWindow == false {
      hideWindowChrome(requiresActivePlayback: false)
    } else if observedPlayer?.rate ?? 0 > 0 {
      scheduleChromeHide()
    }
    super.mouseExited(with: event)
  }

  override func mouseMoved(with event: NSEvent) {
    showWindowChrome(scheduleHide: window?.isKeyWindow ?? true)
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
        self.updateDisplaySleepPrevention()
      }
    }
  }

  func restoreWindowChrome() {
    hideWorkItem?.cancel()
    stopPreventingDisplaySleep()
    guard let window = hostWindow else { return }
    // Never assign a captured style mask here. AppKit adds transient bits (notably `.fullScreen`),
    // and replacing them while SwiftUI dismantles the representable raises an NSWindow exception.
    // Remove only the bit this view actually added, and do it after the current graph transaction.
    if insertedFullSizeContentView {
      insertedFullSizeContentView = false
      DispatchQueue.main.async { [weak window] in
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        window.styleMask.remove(.fullSizeContentView)
      }
    }
    chromeTransitionGeneration += 1
    titlebarContainer(in: window)?.layer?.removeAnimation(forKey: "playerChromeTransition")
    window.titleVisibility = originalTitleVisibility ?? .visible
    window.titlebarAppearsTransparent = originalTitlebarTransparency ?? false
    if let originalToolbarVisibility { window.toolbar?.isVisible = originalToolbarVisibility }
    setTrafficLights(hidden: false, in: window)
  }

  private func observeWindowFocus(_ window: NSWindow) {
    let center = NotificationCenter.default
    windowFocusObservers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification,
                                                    object: window,
                                                    queue: .main) { [weak self] _ in
      self?.updateDisplaySleepPrevention()
    })
    windowFocusObservers.append(center.addObserver(forName: NSWindow.didResignKeyNotification,
                                                    object: window,
                                                    queue: .main) { [weak self] _ in
      guard let self else { return }
      self.updateDisplaySleepPrevention()
      if self.isMouseInsidePlayer(in: window) {
        self.showWindowChrome(scheduleHide: false)
      } else {
        self.hideWindowChrome(requiresActivePlayback: false)
      }
    })
  }

  private func isMouseInsidePlayer(in window: NSWindow) -> Bool {
    let windowPoint = window.convertPoint(fromScreen: NSEvent.mouseLocation)
    return bounds.contains(convert(windowPoint, from: nil))
  }

  private func updateDisplaySleepPrevention() {
    let shouldPreventSleep = hostWindow?.isKeyWindow == true && (observedPlayer?.rate ?? 0) > 0
    if shouldPreventSleep, displaySleepActivity == nil {
      displaySleepActivity = ProcessInfo.processInfo.beginActivity(
        options: .idleDisplaySleepDisabled,
        reason: "Video playback in focused window"
      )
    } else if !shouldPreventSleep {
      stopPreventingDisplaySleep()
    }
  }

  private func stopPreventingDisplaySleep() {
    guard let displaySleepActivity else { return }
    ProcessInfo.processInfo.endActivity(displaySleepActivity)
    self.displaySleepActivity = nil
  }

  private func configureOverlayTitlebar() {
    guard let window = hostWindow else { return }
    if originalTitleVisibility == nil {
      originalTitleVisibility = window.titleVisibility
      originalTitlebarTransparency = window.titlebarAppearsTransparent
      originalToolbarVisibility = window.toolbar?.isVisible
      if !window.styleMask.contains(.fullSizeContentView) {
        insertedFullSizeContentView = true
        window.styleMask.insert(.fullSizeContentView)
      }
    }
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
  }

  private func showWindowChrome(scheduleHide: Bool = true) {
    hideWorkItem?.cancel()
    configureOverlayTitlebar()
    guard let window = hostWindow else { return }

    chromeTransitionGeneration += 1
    let generation = chromeTransitionGeneration
    let wasHidden = window.toolbar?.isVisible == false
    window.toolbar?.isVisible = originalToolbarVisibility ?? true
    setTrafficLights(hidden: false, in: window)
    if wasHidden {
      animateTitlebar(in: window, showing: true, generation: generation)
    } else {
      titlebarContainer(in: window)?.layer?.removeAnimation(forKey: "playerChromeTransition")
    }
    if scheduleHide, observedPlayer?.rate ?? 0 > 0 { scheduleChromeHide() }
  }

  private func scheduleChromeHide() {
    hideWorkItem?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.hideWindowChrome() }
    hideWorkItem = work

    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
  }

  private func hideWindowChrome(requiresActivePlayback: Bool = true) {
    if requiresActivePlayback, observedPlayer?.rate ?? 0 <= 0 { return }
    guard let window = hostWindow else { return }
    chromeTransitionGeneration += 1
    animateTitlebar(in: window, showing: false, generation: chromeTransitionGeneration)
  }

  private func animateTitlebar(in window: NSWindow, showing: Bool, generation: Int) {
    guard let container = titlebarContainer(in: window) else {
      if !showing {
        window.toolbar?.isVisible = false
        setTrafficLights(hidden: true, in: window)
      }
      return
    }
    container.wantsLayer = true
    guard let layer = container.layer else { return }
    layer.removeAnimation(forKey: "playerChromeTransition")

    let distance = max(container.bounds.height, 44)
    let translation = CABasicAnimation(keyPath: "transform.translation.y")
    translation.fromValue = showing ? distance : 0
    translation.toValue = showing ? 0 : distance
    let opacity = CABasicAnimation(keyPath: "opacity")
    opacity.fromValue = showing ? 0 : 1
    opacity.toValue = showing ? 1 : 0

    let group = CAAnimationGroup()
    group.animations = [translation, opacity]
    group.duration = 0.22
    group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    // Keep it hidden until AppKit has actually removes the toolbar
    if !showing {
      group.fillMode = .forwards
      group.isRemovedOnCompletion = false
    }
    CATransaction.begin()
    CATransaction.setCompletionBlock { [weak self, weak window, weak layer] in
      guard let self, let window,
            generation == self.chromeTransitionGeneration,
            !showing else { return }
      self.setTrafficLights(hidden: true, in: window)
      window.toolbar?.isVisible = false
      layer?.removeAnimation(forKey: "playerChromeTransition")
    }
    layer.add(group, forKey: "playerChromeTransition")
    CATransaction.commit()
  }

  private func titlebarContainer(in window: NSWindow) -> NSView? {
    guard let frameView = window.contentView?.superview,
          var candidate = window.standardWindowButton(.closeButton) as NSView? else { return nil }
    while let parent = candidate.superview, parent !== frameView {
      candidate = parent
    }
    return candidate.superview === frameView ? candidate : nil
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
  func playbackErrorAlert(title: String,
                          error: Binding<String?>,
                          onDismiss: @escaping () -> Void) -> some View {
    alert(title.localized,
          isPresented: Binding(get: { error.wrappedValue != nil },
                               set: { if !$0 { error.wrappedValue = nil } })) {
      Button("OK", role: .cancel) { onDismiss() }
    } message: {
      if let message = error.wrappedValue { Text(message) }
    }
  }
}

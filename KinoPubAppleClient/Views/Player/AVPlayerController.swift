//
//  AVPlayerController.swift
//  KinoPubAppleClient
//
//  Owns the AVFoundation object graph: `AVPlayer`/`AVPlayerItem` construction, KVO and
//  notification observers, the periodic time observer, media-selection restore/capture, and
//  playback primitives (see plans/refactor.md Phase 6). All AVKit-touching work stays here so the
//  state machine and source policy can be tested without AVPlayer. Teardown is idempotent and
//  removes every observer exactly once.
//

import Foundation
import AVFoundation
import CoreGraphics
import KinoPubBackend

@MainActor
final class AVPlayerController {
  /// Item became ready to play (fires on the main actor; also fires for an item that is already
  /// ready when it is installed).
  var onReadyToPlay: (() -> Void)?
  /// The current item failed (item.status == .failed). The item is still the current item.
  var onPlaybackFailure: ((AVPlayerItem) -> Void)?
  /// The current item played to its end.
  var onEndOfPlayback: (() -> Void)?
  /// Periodic playback tick (10s), for watch marks.
  var onPeriodicTick: ((TimeInterval) -> Void)?
  /// Playback rate crossed zero (paused) or became positive (playing).
  var onRateChange: ((Bool) -> Void)?

  /// Number of live KVO observations + notification observers. Test hook for teardown checks.
  var liveObservationCount: Int {
    [rateObservation, statusObservation, audioStatusObservation, seekObservation]
      .compactMap { $0 }.count
      + (mediaSelectionObserver == nil ? 0 : 1)
      + (endOfPlaybackObserver == nil ? 0 : 1)
  }

  private(set) lazy var player: AVPlayer = {
    let player = AVPlayer()
    // We explicitly apply the HLS default legible track below. Leaving automatic criteria enabled
    // can replace that selection while the player is starting, yielding a checked but invisible
    // subtitle track in AVKit's menu.
    player.appliesMediaSelectionCriteriaAutomatically = false
    // Let AVPlayer delay/recover playback until enough media is available instead of repeatedly
    // starting and stalling on variable-bandwidth streams.
    player.automaticallyWaitsToMinimizeStalling = true
    return player
  }()

  private let preferences: MediaPreferenceStore

  private var rateObservation: NSKeyValueObservation?
  private var statusObservation: NSKeyValueObservation?
  private var audioStatusObservation: NSKeyValueObservation?
  private var seekObservation: NSKeyValueObservation?
  private var mediaSelectionObserver: NSObjectProtocol?
  private var endOfPlaybackObserver: NSObjectProtocol?
  private var timeObserver: PlayerTimeObserver?
  /// The metadata id of the item currently installed (drives preference lookup/capture).
  private var currentItemID: Int?
  /// Whether audio/subtitle restore + capture is enabled (media mode only; trailers skip it).
  private var appliesMediaSelection = false
  private var isTornDown = false

  init(preferences: MediaPreferenceStore) {
    self.preferences = preferences
    rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
      let isPlaying = player.rate > 0
      Task { @MainActor in
        self?.onRateChange?(isPlaying)
      }
    }
    timeObserver = PlayerTimeObserver(
      player: player,
      period: 10.0,
      timeUpdateHandler: { [weak self] time in
        Task { @MainActor in
          guard let self else { return }
          self.onPeriodicTick?(time)
          if self.appliesMediaSelection {
            await self.captureCurrentMediaSelection()
          }
        }
      })
  }

  // MARK: - Item lifecycle

  /// Swap in `source` as the current item. Applies the 3D video composition, the HLS quality cap,
  /// and (in media mode) the remembered audio/subtitle selection once the item is ready.
  func replaceItem(
    with source: PlaybackSource,
    itemID: Int,
    is3D: Bool,
    maxResolution: CGSize?,
    appliesMediaSelection: Bool
  ) {
    precondition(!isTornDown, "replaceItem after teardown")
    self.currentItemID = itemID
    self.appliesMediaSelection = appliesMediaSelection

    let item = AVPlayerItem(url: source.url)
    if is3D, let composition = ThreeDVideoComposition.make(for: item.asset, mode: preferences.preferredThreeDMode) {
      item.videoComposition = composition
    }
    // Cap the adaptive HLS stream to the user's chosen quality. kino.pub serves one master
    // playlist with every rendition, so this is the lever that limits quality — `.auto` leaves
    // it untouched. Harmless for local/trailer playback (no effect on non-HLS items).
    if appliesMediaSelection, let maxResolution {
      item.preferredMaximumResolution = maxResolution
    }

    removeItemObservations()
    player.replaceCurrentItem(with: item)
    installItemObservations(on: item)
  }

  /// Detach the current item so AVPlayer stops retrying a denied stream while a replacement URL
  /// is being minted. Late callbacks from the old item are ignored by the `=== item` guards.
  func detachCurrentItem() {
    removeItemObservations()
    player.replaceCurrentItem(with: nil)
  }

  // MARK: - Playback primitives

  func play() { player.play() }
  func pause() { player.pause() }

  /// Seek to `time` now if the item is ready; otherwise wait for readiness and seek once. Seeking
  /// a not-yet-ready item is silently dropped, which is why resume sometimes "played from start".
  func seekWhenReady(to time: TimeInterval) {
    guard time > 0 else { return }
    let seekTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    if player.currentItem?.status == .readyToPlay {
      player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
    } else {
      seekObservation?.invalidate()
      seekObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
        guard item.status == .readyToPlay else { return }
        Task { @MainActor in
          guard let self, self.player.currentItem === item else { return }
          self.player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
          self.seekObservation?.invalidate()
          self.seekObservation = nil
        }
      }
    }
  }

  /// Remove every observer exactly once; safe to call repeatedly (player teardown + deinit).
  func teardown() {
    guard !isTornDown else { return }
    isTornDown = true
    removeItemObservations()
    rateObservation?.invalidate()
    rateObservation = nil
    timeObserver = nil  // deinit removes the periodic time observer from the player
    player.pause()
  }

  // MARK: - Failure diagnosis

  /// A user-facing diagnosis for a failed item: the exact reason the native player shows the
  /// "crossed-out play" (item failed to load), so an unplayable stream is diagnosable on-device.
  func failureDiagnosis(for item: AVPlayerItem) -> PlaybackFailureDiagnosis {
    let error = item.error as NSError?
    let event = item.errorLog()?.events.last
    // CDN stream links are signed and can expire while a detail/player route remains alive.
    let isForbidden =
      event?.errorStatusCode == 403
      || event?.errorComment?.localizedCaseInsensitiveContains("403") == true
      || (error?.domain == NSURLErrorDomain && error?.code == NSURLErrorNoPermissionsToReadFile)

    var parts: [String] = []
    if let error {
      parts.append("\(error.domain) \(error.code)")
      parts.append(error.localizedDescription)
      if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
        parts.append("underlying \(underlying.domain) \(underlying.code)")
      }
    }
    // The error log carries the server/format comment AVPlayer recorded (often the real reason).
    if let event {
      if let comment = event.errorComment, !comment.isEmpty { parts.append(comment) }
      parts.append("status \(event.errorStatusCode)")
    }
    let message = parts.isEmpty ? "Unknown playback error" : parts.joined(separator: "\n")
    return PlaybackFailureDiagnosis(isForbidden403: isForbidden, message: message)
  }

  // MARK: - Audio/subtitle restore + capture

  /// Restore the user's audio choice. On first playback, prefer a track explicitly marked as the
  /// original language instead of whichever dub happens to be first in the HLS playlist.
  private func applyPreferredAudio() async {
    guard appliesMediaSelection, let itemID = currentItemID,
      let item = player.currentItem,
      let group = try? await item.asset.loadMediaSelectionGroup(for: .audible)
    else { return }

    let options = group.options
    let preference = preferences.audioPreference(itemId: itemID)
    let desired: AVMediaSelectionOption?
    if let preference {
      desired =
        options.first(where: { $0.displayName == preference.displayName })
        ?? options.first(where: {
          $0.extendedLanguageTag != nil && $0.extendedLanguageTag == preference.languageTag
        })
        ?? (options.indices.contains(preference.index) ? options[preference.index] : nil)
    } else {
      desired = options.first(where: isOriginalAudioOption) ?? group.defaultOption
    }

    if let desired { item.select(desired, in: group) }
  }

  private func isOriginalAudioOption(_ option: AVMediaSelectionOption) -> Bool {
    let name = option.displayName
      .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
      .lowercased()
    return name.contains("original") || name.contains("оригинал")
  }

  /// Restore the user's subtitle track, including an explicit Off choice. If no preference exists,
  /// use the playlist default. Repeat only while the selection is unchanged so a quick user choice
  /// is never overwritten while AVKit attaches its renderer.
  private func restorePreferredSubtitle(for item: AVPlayerItem) async {
    guard appliesMediaSelection,
      let group = try? await item.asset.loadMediaSelectionGroup(for: .legible)
    else { return }

    let preference = preferences.subtitlePreference(itemId: currentItemID ?? 0)
    let desired: AVMediaSelectionOption?
    if let preference {
      if preference.isEnabled {
        desired =
          group.options.first(where: { $0.displayName == preference.displayName })
          ?? group.options.first(where: {
            $0.extendedLanguageTag != nil && $0.extendedLanguageTag == preference.languageTag
          })
          ?? preference.index.flatMap { group.options.indices.contains($0) ? group.options[$0] : nil }
          ?? group.defaultOption
      } else {
        desired = nil
      }
    } else {
      desired = group.defaultOption
    }

    item.select(desired, in: group)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak item] in
      Task { @MainActor in
        guard let self, let item, self.player.currentItem === item else { return }
        let current = item.currentMediaSelection.selectedMediaOption(in: group)
        let selectionIsUnchanged = (current == nil && desired == nil) || current === desired
        guard selectionIsUnchanged else { return }
        item.select(desired, in: group)
      }
    }
  }

  /// Remember the audio option currently selected in the player, so the next episode/launch
  /// resumes it.
  private func captureCurrentAudio() async {
    guard appliesMediaSelection, let itemID = currentItemID,
      let item = player.currentItem,
      let group = try? await item.asset.loadMediaSelectionGroup(for: .audible),
      let selected = item.currentMediaSelection.selectedMediaOption(in: group),
      let index = group.options.firstIndex(of: selected)
    else { return }
    let preference = LibraryAudioPreference(
      displayName: selected.displayName,
      languageTag: selected.extendedLanguageTag,
      index: index)
    await preferences.setAudioPreference(itemId: itemID, preference)
  }

  /// Remember the selected subtitle immediately; nil is a meaningful explicit Off selection.
  private func captureCurrentSubtitle() async {
    guard appliesMediaSelection, let itemID = currentItemID,
      let item = player.currentItem,
      let group = try? await item.asset.loadMediaSelectionGroup(for: .legible)
    else { return }

    let selected = item.currentMediaSelection.selectedMediaOption(in: group)
    let preference: LibrarySubtitlePreference
    if let selected {
      preference = .init(
        isEnabled: true,
        displayName: selected.displayName,
        languageTag: selected.extendedLanguageTag,
        index: group.options.firstIndex(of: selected))
    } else {
      preference = .init(isEnabled: false, displayName: nil, languageTag: nil, index: nil)
    }
    await preferences.setSubtitlePreference(itemId: itemID, preference)
  }

  private func captureCurrentMediaSelection() async {
    await captureCurrentAudio()
    await captureCurrentSubtitle()
  }

  // MARK: - Observation wiring

  private func removeItemObservations() {
    statusObservation?.invalidate()
    statusObservation = nil
    audioStatusObservation?.invalidate()
    audioStatusObservation = nil
    if let mediaSelectionObserver {
      NotificationCenter.default.removeObserver(mediaSelectionObserver)
      self.mediaSelectionObserver = nil
    }
    if let endOfPlaybackObserver {
      NotificationCenter.default.removeObserver(endOfPlaybackObserver)
      self.endOfPlaybackObserver = nil
    }
  }

  private func installItemObservations(on item: AVPlayerItem) {
    // Surface the exact reason the native player shows the "crossed-out play" (item failed to
    // load), so an unplayable stream is diagnosable on-device instead of failing silently.
    statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard item.status == .failed else { return }
      Task { @MainActor in
        guard let self, self.player.currentItem === item else { return }
        self.onPlaybackFailure?(item)
      }
    }

    // Re-apply the remembered audio track (озвучка) once the item is ready, so the user's last dub
    // choice carries across episodes and launches without any custom UI.
    if appliesMediaSelection {
      audioStatusObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
        guard item.status == .readyToPlay else { return }
        Task { @MainActor in
          guard let self, self.player.currentItem === item else { return }
          self.onReadyToPlay?()
          await self.applyPreferredAudio()
          await self.restorePreferredSubtitle(for: item)
          self.audioStatusObservation?.invalidate()
          self.audioStatusObservation = nil
        }
      }
      observeMediaSelection(on: item)
    }

    // Playing to the very end marks the title watched (see `markFinished` in WatchProgressSync).
    if appliesMediaSelection {
      endOfPlaybackObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
      ) { [weak self] _ in
        Task { @MainActor in self?.onEndOfPlayback?() }
      }
    }
  }

  private func observeMediaSelection(on item: AVPlayerItem) {
    mediaSelectionObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.mediaSelectionDidChangeNotification,
      object: item,
      queue: .main
    ) { [weak self, weak item] _ in
      Task { @MainActor in
        guard let self, let item, self.player.currentItem === item else { return }
        await self.captureCurrentMediaSelection()
      }
    }
  }
}

/// Result of inspecting a failed `AVPlayerItem`: whether the failure is a denied (403) CDN link
/// and the raw diagnosis message (domain/code, error log comments, status).
struct PlaybackFailureDiagnosis: Equatable {
  let isForbidden403: Bool
  let message: String
}

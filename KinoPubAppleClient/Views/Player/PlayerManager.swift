//
//  PlayerManager.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 3.08.2023.
//

import Foundation
import SwiftUI
import Combine
import KinoPubBackend
import KinoPubKit
import KinoPubUI
import AVFoundation
import OSLog
import KinoPubLogging

/// How the player route is entered: full media playback or a standalone trailer.
enum WatchMode {
  case media
  case trailer
}

/// Composition façade for playback (see plans/refactor.md Phase 6). Owns no AVFoundation objects
/// itself — the state machine (`PlaybackSession`), source policy (`PlaybackSourceRepository`),
/// watch-mark reporting (`WatchProgressSync`), preferences (`MediaPreferenceStore`), the player
/// object graph (`AVPlayerController`), and remote controls (`RemoteCommandController`) are all
/// separate and individually testable. The initializer and published surface are unchanged, so
/// call sites and the rollback path stay intact.
@MainActor
final class PlayerManager: ObservableObject {

  @Published var isPlaying: Bool = false
  @Published var watchMark: WatchData?
  @Published var continueTime: TimeInterval?
  /// Human-readable diagnosis shown when the item can't be played (the native "crossed-out play"),
  /// so failures (e.g. an HLS stream AVPlayer rejects) surface on-device instead of silently.
  @Published var playbackError: String?
  @Published private(set) var playbackErrorTitle = "Playback failed"
  @Published private(set) var hasNextEpisode = false
  @Published private(set) var hasPreviousEpisode = false
  /// Signals the player route to pop after a movie or the final queued episode completes.
  @Published private(set) var shouldReturnToContent = false
  /// The HLS resolution cap shown by the in-player quality menu.
  @Published private(set) var streamQuality: StreamQuality

  /// Whether the playing title is a 3D (stereoscopic) release, so the player offers 3D view modes.
  var is3D: Bool { FeatureFlags.threeDEnabled && (playItem as? MediaItem)?.type.lowercased() == "3d" }
  /// Quality selection only affects remote adaptive streams, not trailers, downloads, or 3D MP4s.
  var offersStreamQualitySelection: Bool {
    watchMode == .media && !is3D && currentSource?.isHLS == true
  }
  /// Highest quality advertised for this title; `quality` handles anamorphic files better than `h`.
  var maximumStreamResolution: Int? {
    let resolution = effectiveFiles.map { max($0.resolution, $0.h) }.max() ?? 0
    return resolution > 0 ? resolution : nil
  }
  /// Current 3D view mode (Off for non-3D titles).
  @Published var threeDMode: ThreeDMode = .off

  /// The `AVPlayer` consumed by the native view. All object lifecycle lives in `AVPlayerController`.
  var player: AVPlayer { controller.player }

  /// Last-used 3D view mode, persisted across launches and switched live in the player. Defaults
  /// to Side-by-Side 2D — the common packing, shown flat so it's watchable without glasses.
  /// (Shared with `MediaItemModel`; the instance player reads through `MediaPreferenceStore`.)
  static var preferredThreeDMode: ThreeDMode {
    get { MediaPreferenceStore.preferredThreeDMode(in: .standard) }
    set { MediaPreferenceStore.setPreferredThreeDMode(newValue, in: .standard) }
  }

  private var playItem: any PlayableItem
  private let watchMode: WatchMode
  private let actionsService: UserActionsService
  private let localProgressStore: LocalWatchProgressStore
  private let session: PlaybackSession
  private let sourceRepository: PlaybackSourceRepository
  private let watchProgressSync: WatchProgressSync
  private var preferences: MediaPreferenceStore
  private let controller: AVPlayerController
  private let remoteCommands: RemoteCommandController

  /// The source currently installed in the player (drives quality-menu policy + recovery routing).
  private var currentSource: PlaybackSource?
  /// Mirror of `sourceRepository.currentFiles` so view bodies can read it synchronously.
  private var effectiveFiles: [FileInfo]
  private var didHandlePlaybackEnd = false
  private var playbackRecoveryTask: Task<Void, Never>?

  init(
    playItem: any PlayableItem,
    watchMode: WatchMode,
    downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>,
    actionsService: UserActionsService,
    contentService: VideoContentService,
    localProgressStore: LocalWatchProgressStore,
    libraryState: LibraryViewState,
    episodeQueue: [Episode] = []
  ) {
    self.playItem = playItem
    self.watchMode = watchMode
    self.actionsService = actionsService
    self.localProgressStore = localProgressStore
    self.effectiveFiles = playItem.files
    let preferences = MediaPreferenceStore(libraryState: libraryState)
    self.preferences = preferences
    self.streamQuality = preferences.streamQuality
    self.session = PlaybackSession(playItem: playItem, episodeQueue: episodeQueue)
    self.sourceRepository = PlaybackSourceRepository(
      downloadedFilesDatabase: downloadedFilesDatabase,
      contentService: contentService)
    self.watchProgressSync = WatchProgressSync(
      actionsService: actionsService,
      localProgressStore: localProgressStore)
    let controller = AVPlayerController(preferences: preferences)
    self.controller = controller
    self.remoteCommands = RemoteCommandController()

    // Release silent Home/detail previews before AVPlayer creates the real CDN session. Keeping a
    // trailer alive behind this route can consume the account's concurrent-stream allowance.
    PreviewPlaybackCoordinator.shared.beginExclusivePlayback()

    // A 3D title starts in the user's last-chosen mode (default: one eye as 2D, so it's watchable —
    // raw packed stereo would show a doubled image).
    if watchMode == .media, is3D {
      threeDMode = preferences.preferredThreeDMode
    }

    // Seed the resume point synchronously from the local store so the native "Continue" prompt can
    // appear the moment the player presents (no race with the async server fetch, which only
    // refines it). Covers the "open from Continue Watching" case that previously started at 0.
    if watchMode == .media,
      let local = localProgressStore.entry(
        forId: playItem.metadata.id,
        season: playItem.metadata.season,
        episode: playItem.metadata.video),
      local.position > 0
    {
      continueTime = local.position
    }

    controller.onReadyToPlay = { [weak self] in self?.session.markReady() }
    controller.onPlaybackFailure = { [weak self] item in
      Task { await self?.handlePlaybackFailure(item) }
    }
    controller.onEndOfPlayback = { [weak self] in
      Task { await self?.playbackDidFinish() }
    }
    controller.onPeriodicTick = { [weak self] time in
      Task { await self?.handlePeriodicTick(time) }
    }
    controller.onRateChange = { [weak self] isPlaying in self?.isPlaying = isPlaying }

    currentSource = sourceRepository.initialSource(
      for: playItem,
      mode: watchMode,
      is3D: is3D,
      maxResolution: streamQuality.maxResolution)
    if let source = currentSource {
      controller.replaceItem(
        with: source,
        itemID: playItem.metadata.id,
        is3D: is3D,
        maxResolution: streamQuality.maxResolution,
        appliesMediaSelection: watchMode == .media)
    }
    session.prepare()
    updateNavigation()
    if !episodeQueue.isEmpty {
      remoteCommands.configure(
        onPrevious: { [weak self] in self?.playPreviousEpisode() },
        onNext: { [weak self] in self?.playNextEpisode() })
    }
  }

  deinit {
    playbackRecoveryTask?.cancel()
    // A @MainActor object is always deallocated on the main actor; assume it so observers are
    // removed exactly once even when the view never ran `stopPlayback`. (The watch-mark worker
    // holds the sync weakly and exits on its own when the sync goes away.)
    MainActor.assumeIsolated {
      controller.teardown()
      remoteCommands.teardown()
    }
  }

  // MARK: - Episode navigation

  func playNextEpisode() { _ = playAdjacentEpisode(offset: 1) }
  func playPreviousEpisode() { _ = playAdjacentEpisode(offset: -1) }

  private func playbackDidFinish() async {
    guard !didHandlePlaybackEnd else { return }
    didHandlePlaybackEnd = true
    await markFinished()
    if !playAdjacentEpisode(offset: 1) {
      controller.pause()
      session.finish()
      shouldReturnToContent = true
    }
  }

  /// Returns whether an adjacent episode was found and started.
  @discardableResult
  private func playAdjacentEpisode(offset: Int) -> Bool {
    guard let target = session.adjacentEpisode(to: playItem, offset: offset) else { return false }
    controller.pause()
    playItem = target
    continueTime = nil
    session.move(to: target)
    sourceRepository.reset()
    currentSource = sourceRepository.initialSource(
      for: playItem,
      mode: watchMode,
      is3D: is3D,
      maxResolution: streamQuality.maxResolution)
    guard let source = currentSource else { return false }
    effectiveFiles = playItem.files
    didHandlePlaybackEnd = false
    controller.replaceItem(
      with: source,
      itemID: playItem.metadata.id,
      is3D: is3D,
      maxResolution: streamQuality.maxResolution,
      appliesMediaSelection: watchMode == .media)
    controller.play()
    updateNavigation()
    return true
  }

  private func updateNavigation() {
    hasPreviousEpisode = session.hasPreviousEpisode
    hasNextEpisode = session.hasNextEpisode
    remoteCommands.updateNavigation(hasPrevious: hasPreviousEpisode, hasNext: hasNextEpisode)
  }

  // MARK: - Failure diagnostics and recovery

  func stopPlayback() {
    playbackRecoveryTask?.cancel()
    playbackRecoveryTask = nil
    controller.pause()
    controller.teardown()
    remoteCommands.teardown()
    Task { await watchProgressSync.cancel() }
    PreviewPlaybackCoordinator.shared.endExclusivePlayback()
  }

  private func handlePlaybackFailure(_ item: AVPlayerItem) async {
    guard controller.player.currentItem === item else { return }
    let diagnosis = controller.failureDiagnosis(for: item)
    let isRemoteMedia = watchMode == .media && currentSource?.isRemote == true
    if isRemoteMedia, diagnosis.isForbidden403 {
      // CDN stream links are signed and can expire while a detail/player route remains alive. A
      // 403 can also mean the account reached its concurrent-session limit; report that directly
      // instead of hammering the CDN.
      playbackRecoveryTask?.cancel()
      controller.pause()
      playbackErrorTitle = "Session limit reached".localized
      playbackError =
        "Your kino.pub account has reached its simultaneous viewing session limit. Stop playback on another device, wait a moment, and try again."
        .localized
      Logger.app.error("Playback denied: kino.pub user session limit reached")
      return
    }
    if isRemoteMedia {
      // A fresh item response carries a new URL; retry the ladder and preserve the current time.
      await recoverPlayback(afterFailureOf: item)
    } else {
      playbackErrorTitle = "Playback failed"
      playbackError = diagnosis.message
      session.fail(diagnosis.message)
    }
  }

  /// Uses the API's dedicated media-link endpoints. Item details are metadata and may keep
  /// returning the same denied URL; `media-video-link` explicitly mints a new signed URL for the
  /// raw file path, walking hls4 → hls2 → one progressive file with a backoff between attempts.
  private func recoverPlayback(afterFailureOf failedItem: AVPlayerItem) async {
    let resumeTime = failedItem.currentTime()
    controller.pause()
    // Detach immediately so AVPlayer stops retrying every denied HLS segment while the API mints a
    // replacement URL. The old item's late callbacks are ignored by the `=== item` guards.
    controller.detachCurrentItem()

    do {
      let attempt = session.beginRecovery()
      // A CDN 403 can represent a concurrent-session slot that has not expired yet. Back off after
      // releasing the failed AVPlayer instead of immediately opening another server-side session.
      try await Task.sleep(for: .seconds(session.recoveryDelay(forAttempt: attempt)))

      let source = try await sourceRepository.refreshSource(
        for: playItem,
        recoveryAttempt: attempt,
        maxResolution: streamQuality.maxResolution)
      currentSource = source
      effectiveFiles = sourceRepository.currentFiles(for: playItem)
      playbackError = nil
      didHandlePlaybackEnd = false
      controller.replaceItem(
        with: source,
        itemID: playItem.metadata.id,
        is3D: is3D,
        maxResolution: streamQuality.maxResolution,
        appliesMediaSelection: watchMode == .media)
      if resumeTime.isNumeric, resumeTime.seconds > 0 {
        await player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero)
      }
      controller.play()
      Logger.app.info("Playback URL regenerated as \(source.streamType ?? "unknown")")
    } catch is CancellationError {
      return
    } catch {
      Logger.app.error("Playback recovery failed: \(error)")
      session.fail(error.localizedDescription)
      playbackError = "HTTP 403: Forbidden\nCould not obtain an accessible playback URL.\n\(error.localizedDescription)"
    }
  }

  // MARK: - Preferences

  /// Applies an HLS quality cap immediately and remembers it for later playback sessions.
  func setStreamQuality(_ quality: StreamQuality) {
    streamQuality = quality
    preferences.streamQuality = quality
    guard watchMode == .media else { return }
    player.currentItem?.preferredMaximumResolution = quality.maxResolution ?? .zero
  }

  /// Switch the 3D rendering live (rebuilds the per-frame composition on the current item).
  func setThreeDMode(_ mode: ThreeDMode) {
    threeDMode = mode
    preferences.preferredThreeDMode = mode
    guard let item = player.currentItem else { return }
    item.videoComposition = ThreeDVideoComposition.make(for: item.asset, mode: mode)
  }

  // MARK: - Watch marks

  /// Periodic tick: persist a local resume point and queue the remote mark. Trailers only queue
  /// the remote mark (no local progress).
  private func handlePeriodicTick(_ time: TimeInterval) async {
    if watchMode == .media {
      let duration = player.currentItem?.duration.seconds ?? 0
      await watchProgressSync.recordProgress(
        mediaId: playItem.metadata.id,
        position: time,
        duration: duration,
        season: playItem.metadata.season,
        episode: playItem.metadata.video)
    } else {
      await watchProgressSync.enqueueMark(
        id: playItem.metadata.id,
        video: playItem.metadata.video,
        season: playItem.metadata.season,
        time: Int(time))
    }
  }

  /// Kept as the façade entry point for the periodic tick (and the watch-mark integration test).
  func saveWatchMark(time: TimeInterval) {
    Task { await handlePeriodicTick(time) }
  }

  /// Reaching the end marks the title watched (see `WatchProgressSync.markFinished`).
  private func markFinished() async {
    guard watchMode == .media else { return }
    let duration = player.currentItem?.duration.seconds ?? 0
    await watchProgressSync.markFinished(
      mediaId: playItem.metadata.id,
      season: playItem.metadata.season,
      episode: playItem.metadata.video,
      duration: duration)
  }

  func fetchWatchMark() async {
    // Only media has a resume point (live/trailers don't).
    guard watchMode == .media else { return }

    var remoteContinueTime: TimeInterval = 0
    do {
      watchMark = try await actionsService.fetchWatchMark(
        id: playItem.metadata.id, video: playItem.metadata.video, season: playItem.metadata.season)
      if let watchMark {
        remoteContinueTime =
          watchMark.item.videos?.first?.time ?? watchMark.item.seasons?.first?.episodes.first?.time ?? 0
      }
    } catch {
      Logger.app.error("Failed to fetch watch mark: \(error)")
    }

    // Fall back to the local resume point: a movie/episode watched in-app records its position
    // locally on every tick, so it resumes even when the server mark lags or the fetch fails.
    let localContinueTime =
      localProgressStore
      .entry(forId: playItem.metadata.id, season: playItem.metadata.season, episode: playItem.metadata.video)?
      .position ?? 0

    let best = max(remoteContinueTime, localContinueTime)
    // Keep any value we already seeded synchronously if the refined fetch somehow comes back empty.
    if best > 0 { continueTime = best }
  }

  // MARK: - Continue watching

  func seekToContinueWatching() {
    guard let continueTime else { return }
    self.continueTime = nil
    controller.seekWhenReady(to: continueTime)
  }

  func cancelContinueWatching() {
    self.continueTime = nil
  }
}

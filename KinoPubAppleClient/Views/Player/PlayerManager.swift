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
import AVFoundation
import MediaPlayer
import CoreImage
import KinoPubLogging
import OSLog

/// How a stereoscopic source is shown on a flat Mac display: one-eye 2D or red-cyan anaglyph.
/// The source can be packed Side-by-Side (two eyes left/right) or Over-Under (top/bottom).
enum ThreeDMode: String, CaseIterable, Identifiable {
  case off
  case sbsMono
  case sbsAnaglyph
  case ouMono
  case ouAnaglyph

  var id: String { rawValue }

  var title: String {
    switch self {
    case .off: return "3D: Off"
    case .sbsMono: return "Side-by-Side · 2D"
    case .sbsAnaglyph: return "Side-by-Side · Anaglyph"
    case .ouMono: return "Over-Under · 2D"
    case .ouAnaglyph: return "Over-Under · Anaglyph"
    }
  }

  var isSideBySide: Bool { self == .sbsMono || self == .sbsAnaglyph }
  var isAnaglyph: Bool { self == .sbsAnaglyph || self == .ouAnaglyph }
}

/// Builds an `AVVideoComposition` that reshapes each frame of a packed-stereo video into a flat
/// image: one eye scaled to full frame (2D), or a red-cyan anaglyph combining both eyes.
enum ThreeDVideoComposition {
  static func make(for asset: AVAsset, mode: ThreeDMode) -> AVVideoComposition? {
    guard mode != .off else { return nil }
    let sideBySide = mode.isSideBySide
    let anaglyph = mode.isAnaglyph
    return AVMutableVideoComposition(asset: asset) { request in
      let src = request.sourceImage
      let e = src.extent

      // Each eye cropped from its half and stretched back to the full frame (half-packed sources
      // squeeze each eye, so un-squeezing restores the correct aspect).
      func leftEye() -> CIImage {
        if sideBySide {
          return src.cropped(to: CGRect(x: e.minX, y: e.minY, width: e.width / 2, height: e.height))
            .transformed(by: CGAffineTransform(scaleX: 2, y: 1))
        } else { // Over-Under: left eye on top (CI origin is bottom-left → upper half)
          return src.cropped(to: CGRect(x: e.minX, y: e.midY, width: e.width, height: e.height / 2))
            .transformed(by: CGAffineTransform(translationX: 0, y: -e.height / 2))
            .transformed(by: CGAffineTransform(scaleX: 1, y: 2))
        }
      }
      func rightEye() -> CIImage {
        if sideBySide {
          return src.cropped(to: CGRect(x: e.midX, y: e.minY, width: e.width / 2, height: e.height))
            .transformed(by: CGAffineTransform(translationX: -e.width / 2, y: 0))
            .transformed(by: CGAffineTransform(scaleX: 2, y: 1))
        } else {
          return src.cropped(to: CGRect(x: e.minX, y: e.minY, width: e.width, height: e.height / 2))
            .transformed(by: CGAffineTransform(scaleX: 1, y: 2))
        }
      }

      let output: CIImage
      if anaglyph {
        let leftRed = leftEye().applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
        let rightCyan = rightEye().applyingFilter("CIColorMatrix", parameters: [
          "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0)])
        output = leftRed.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: rightCyan])
      } else {
        output = leftEye()
      }
      request.finish(with: output.cropped(to: e), context: nil)
    }
  }
}

enum WatchMode {
  case media
  case trailer
}

@MainActor
class PlayerManager: ObservableObject {
  
  @Published var isPlaying: Bool = false
  @Published var watchMark: WatchData?
  @Published var continueTime: TimeInterval?
  /// Human-readable diagnosis shown when the item can't be played (the native "crossed-out play"),
  /// so failures (e.g. an HLS stream AVPlayer rejects) surface on-device instead of silently.
  @Published var playbackError: String?
  @Published private(set) var hasNextEpisode = false
  @Published private(set) var hasPreviousEpisode = false
  
  /// Whether the playing title is a 3D (stereoscopic) release, so the player offers 3D view modes.
  var is3D: Bool { FeatureFlags.threeDEnabled && (playItem as? MediaItem)?.type.lowercased() == "3d" }
  /// Current 3D view mode (Off for non-3D titles).
  @Published var threeDMode: ThreeDMode = .off

  /// Last-used 3D view mode, persisted across launches and switched live in the player.
  /// Defaults to Side-by-Side 2D — the common packing, shown
  /// flat so it's watchable without glasses.
  private static let threeDModeKey = "preferredThreeDMode"
  static var preferredThreeDMode: ThreeDMode {
    get { ThreeDMode(rawValue: UserDefaults.standard.string(forKey: threeDModeKey) ?? "") ?? .sbsMono }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: threeDModeKey) }
  }

  lazy var player: AVPlayer = {
    guard let fileURL else { return AVPlayer() }
    let item = AVPlayerItem(url: fileURL)
    if is3D, let comp = ThreeDVideoComposition.make(for: item.asset, mode: threeDMode) {
      item.videoComposition = comp
    }
    // Cap the adaptive HLS stream to the user's chosen quality. kino.pub serves one master
    // playlist with every rendition, so this is the lever that limits quality — `.auto` leaves
    // it untouched. Harmless for local/trailer playback (no effect on non-HLS items).
    if watchMode == .media, let maxResolution = StreamQuality.current.maxResolution {
      item.preferredMaximumResolution = maxResolution
    }
    let player = AVPlayer(playerItem: item)
    // We explicitly apply the HLS default legible track below. Leaving automatic criteria enabled
    // can replace that selection while the player is starting, yielding a checked but invisible
    // subtitle track in AVKit's menu.
    player.appliesMediaSelectionCriteriaAutomatically = false
    return player
  }()

  private var playerTimeObserver: PlayerTimeObserver?
  private var playItem: any PlayableItem
  private var watchMode: WatchMode
  private var downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>
  private var rateObservation: NSKeyValueObservation?
  private var seekObservation: NSKeyValueObservation?
  private var audioObservation: NSKeyValueObservation?
  private var failureObservation: NSKeyValueObservation?
  private var mediaSelectionObserver: NSObjectProtocol?
  private var endOfPlaybackObserver: NSObjectProtocol?
  private var actionsService: UserActionsService
  private let episodeQueue: [Episode]
  private var didHandlePlaybackEnd = false
  private var nextTrackCommandTarget: Any?
  private var previousTrackCommandTarget: Any?
  
  private var fileURL: URL? {
    switch watchMode {
    case .media:
      // A download is saved under the SERIES content id (DownloadMeta.id == mediaItem.id), but the
      // identity differs by entry point: an Episode's `id` is the episode id while its `metadata.id`
      // is the series id; a DownloadMeta is the reverse. Match on either so an already-downloaded
      // movie/episode opened from the detail page plays the local file instead of streaming.
      let contentIds: Set<Int> = [playItem.id, playItem.metadata.id]
      let downloadedFiles = downloadedFilesDatabase.readData() ?? []
      let sameItem = downloadedFiles.filter { contentIds.contains($0.metadata.id) }
      // For a series there can be several downloads under the same (series) id, plus stale rows whose
      // file was deleted. Pick the row whose source URL matches THIS item's files (the right episode),
      // then any same-item row — but only when the file is actually present on disk. Otherwise fall
      // through to streaming instead of handing AVPlayer a missing file (the "crossed-out play" icon).
      let playURLs = Set(playItem.files.map { $0.url.http })
      let chosen = sameItem.first(where: { playURLs.contains($0.originalURL.absoluteString) }) ?? sameItem.first
      if let chosen, FileManager.default.fileExists(atPath: chosen.localFileURL.path) {
        return chosen.localFileURL
      }
      // A 3D title needs a progressive (non-HLS) source: AVVideoComposition (the SBS/OU/anaglyph
      // reshaping) is ignored on HLS, so streaming via hls4 would just show the raw packed image.
      // Use the direct mp4 URL so the 3D composition actually applies.
      if is3D {
        let mp4 = BestVideoQualityFinder.bestProgressiveURL(for: playItem.files)
        if !mp4.isEmpty, let url = URL(string: mp4) { return url }
      }
      let urlString = BestVideoQualityFinder.findBestURL(for: playItem.files)
      guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
      return url
    case .trailer:
      guard let urlString = playItem.trailer?.url, !urlString.isEmpty,
            let url = URL(string: urlString) else { return nil }
      return url
    }
  }
  
  init(playItem: any PlayableItem,
       watchMode: WatchMode,
       downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>,
       actionsService: UserActionsService,
       episodeQueue: [Episode] = []) {
    self.playItem = playItem
    self.watchMode = watchMode
    self.actionsService = actionsService
    self.downloadedFilesDatabase = downloadedFilesDatabase
    self.episodeQueue = episodeQueue
    // A 3D title starts in the user's last-chosen mode (default: one eye as 2D, so it's watchable —
    // raw packed stereo would show a doubled image).
    if watchMode == .media, is3D {
      threeDMode = PlayerManager.preferredThreeDMode
    }
    // Seed the resume point synchronously from the local store so the native "Continue" prompt can
    // appear the moment the player presents (no race with the async server fetch, which only
    // refines it). Covers the "open from Continue Watching" case that previously started at 0.
    if watchMode == .media,
       let local = AppContext.shared.localProgressStore.entry(forId: playItem.metadata.id,
                                                              season: playItem.metadata.season,
                                                              episode: playItem.metadata.video),
       local.position > 0 {
      continueTime = local.position
    }
    rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
      DispatchQueue.main.async {
        self?.isPlaying = player.rate > 0
      }
    }

    // Re-apply the remembered audio track (озвучка) once the item is ready, so the user's last dub
    // choice carries across episodes and launches without any custom UI.
    if watchMode == .media {
      audioObservation = player.currentItem?.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
        guard item.status == .readyToPlay else { return }
        DispatchQueue.main.async {
          guard let self, self.player.currentItem === item else { return }
          self.applyPreferredAudio()
          self.restorePreferredSubtitle(for: item)
          self.audioObservation?.invalidate()
          self.audioObservation = nil
        }
      }
    }

    // Surface the exact reason the native player shows the "crossed-out play" (item failed to load),
    // so an unplayable stream is diagnosable on-device instead of failing silently.
    failureObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard item.status == .failed else { return }
      DispatchQueue.main.async { self?.reportPlaybackFailure(item) }
    }
    observeMediaSelection(on: player.currentItem)

    playerTimeObserver = PlayerTimeObserver(player: player, period: 10.0, timeUpdateHandler: { [weak self] time in
      DispatchQueue.main.async {
        self?.saveWatchMark(time: time)
        self?.captureCurrentMediaSelection()
      }
    })

    // Playing to the very end marks the title watched (see `markFinished`).
    if watchMode == .media {
      endOfPlaybackObserver = NotificationCenter.default.addObserver(
        forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
          self?.playbackDidFinish()
      }
    }
    updateEpisodeNavigation()
    configureRemoteCommands()
  }

  deinit {
    if let mediaSelectionObserver { NotificationCenter.default.removeObserver(mediaSelectionObserver) }
    if let endOfPlaybackObserver { NotificationCenter.default.removeObserver(endOfPlaybackObserver) }
    let commands = MPRemoteCommandCenter.shared()
    if let nextTrackCommandTarget { commands.nextTrackCommand.removeTarget(nextTrackCommandTarget) }
    if let previousTrackCommandTarget { commands.previousTrackCommand.removeTarget(previousTrackCommandTarget) }
  }

  // MARK: - Episode navigation

  func playNextEpisode() { playAdjacentEpisode(offset: 1) }
  func playPreviousEpisode() { playAdjacentEpisode(offset: -1) }

  private func playbackDidFinish() {
    guard !didHandlePlaybackEnd else { return }
    didHandlePlaybackEnd = true
    markFinished()
    playNextEpisode()
  }

  private func playAdjacentEpisode(offset: Int) {
    guard let current = playItem as? Episode,
          let index = episodeQueue.firstIndex(where: { $0.id == current.id }) else { return }
    let targetIndex = index + offset
    guard episodeQueue.indices.contains(targetIndex) else { return }
    player.pause()
    playItem = episodeQueue[targetIndex]
    continueTime = nil
    replacePlayerItem()
    player.play()
  }

  private func updateEpisodeNavigation() {
    guard let current = playItem as? Episode,
          let index = episodeQueue.firstIndex(where: { $0.id == current.id }) else {
      hasNextEpisode = false
      hasPreviousEpisode = false
      let commands = MPRemoteCommandCenter.shared()
      commands.previousTrackCommand.isEnabled = false
      commands.nextTrackCommand.isEnabled = false
      return
    }
    hasPreviousEpisode = index > 0
    hasNextEpisode = index + 1 < episodeQueue.count
    let commands = MPRemoteCommandCenter.shared()
    commands.previousTrackCommand.isEnabled = hasPreviousEpisode
    commands.nextTrackCommand.isEnabled = hasNextEpisode
  }

  private func configureRemoteCommands() {
    guard !episodeQueue.isEmpty else { return }
    let commands = MPRemoteCommandCenter.shared()
    previousTrackCommandTarget = commands.previousTrackCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async { self?.playPreviousEpisode() }
      return .success
    }
    nextTrackCommandTarget = commands.nextTrackCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async { self?.playNextEpisode() }
      return .success
    }
    commands.previousTrackCommand.isEnabled = hasPreviousEpisode
    commands.nextTrackCommand.isEnabled = hasNextEpisode
  }

  private func replacePlayerItem() {
    guard let url = fileURL else { return }
    let item = AVPlayerItem(url: url)
    if watchMode == .media, let maxResolution = StreamQuality.current.maxResolution {
      item.preferredMaximumResolution = maxResolution
    }
    if let endOfPlaybackObserver { NotificationCenter.default.removeObserver(endOfPlaybackObserver) }
    didHandlePlaybackEnd = false
    player.replaceCurrentItem(with: item)
    failureObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
      guard item.status == .failed else { return }
      DispatchQueue.main.async { self?.reportPlaybackFailure(item) }
    }
    audioObservation = item.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
      guard item.status == .readyToPlay else { return }
      DispatchQueue.main.async {
        guard let self, self.watchMode == .media, self.player.currentItem === item else { return }
        self.applyPreferredAudio()
        self.restorePreferredSubtitle(for: item)
        self.audioObservation?.invalidate()
        self.audioObservation = nil
      }
    }
    observeMediaSelection(on: item)
    endOfPlaybackObserver = NotificationCenter.default.addObserver(
      forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
    ) { [weak self] _ in
      self?.playbackDidFinish()
    }
    updateEpisodeNavigation()
  }

  // MARK: - Failure diagnostics

  private func reportPlaybackFailure(_ item: AVPlayerItem) {
    let error = item.error as NSError?
    var parts: [String] = []
    if let error {
      parts.append("\(error.domain) \(error.code)")
      parts.append(error.localizedDescription)
      if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
        parts.append("underlying \(underlying.domain) \(underlying.code)")
      }
    }
    // The error log carries the server/format comment AVPlayer recorded (often the real reason).
    if let event = item.errorLog()?.events.last {
      if let comment = event.errorComment, !comment.isEmpty { parts.append(comment) }
      parts.append("status \(event.errorStatusCode)")
    }
    let message = parts.isEmpty ? "Unknown playback error" : parts.joined(separator: "\n")
    Logger.app.error("Playback failed: \(message)")
    playbackError = message
  }

  // MARK: - Audio track preference (озвучка)

  /// Restore the user's audio choice. On first playback, prefer a track explicitly marked as the
  /// original language instead of whichever dub happens to be first in the HLS playlist.
  private func applyPreferredAudio() {
    guard watchMode == .media,
          let item = player.currentItem,
          let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
    else { return }

    let options = group.options
    let preference = AppContext.shared.libraryState.audioPreference(itemId: playItem.metadata.id)
    let desired: AVMediaSelectionOption?
    if let preference {
      desired = options.first(where: { $0.displayName == preference.displayName })
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
  private func restorePreferredSubtitle(for item: AVPlayerItem) {
    guard watchMode == .media,
          let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
    else { return }

    let preference = AppContext.shared.libraryState.subtitlePreference(itemId: playItem.metadata.id)
    let desired: AVMediaSelectionOption?
    if let preference {
      if preference.isEnabled {
        desired = group.options.first(where: { $0.displayName == preference.displayName })
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
      guard let self, let item, self.player.currentItem === item else { return }
      let current = item.currentMediaSelection.selectedMediaOption(in: group)
      let selectionIsUnchanged = (current == nil && desired == nil) || current === desired
      guard selectionIsUnchanged else { return }
      item.select(desired, in: group)
    }
  }

  private func observeMediaSelection(on item: AVPlayerItem?) {
    if let mediaSelectionObserver {
      NotificationCenter.default.removeObserver(mediaSelectionObserver)
      self.mediaSelectionObserver = nil
    }
    guard watchMode == .media, let item else { return }
    mediaSelectionObserver = NotificationCenter.default.addObserver(
      forName: AVPlayerItem.mediaSelectionDidChangeNotification,
      object: item,
      queue: .main
    ) { [weak self, weak item] _ in
      guard let self, let item, self.player.currentItem === item else { return }
      self.captureCurrentMediaSelection()
    }
  }

  private func captureCurrentMediaSelection() {
    captureCurrentAudio()
    captureCurrentSubtitle()
  }

  /// Remember the audio option currently selected in the player, so the next episode/launch resumes it.
  private func captureCurrentAudio() {
    guard watchMode == .media,
          let item = player.currentItem,
          let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
          let selected = item.currentMediaSelection.selectedMediaOption(in: group),
          let index = group.options.firstIndex(of: selected)
    else { return }
    let preference = MediaLibraryStore.AudioPreference(displayName: selected.displayName,
                                                       languageTag: selected.extendedLanguageTag,
                                                       index: index)
    AppContext.shared.libraryState.setAudioPreference(itemId: playItem.metadata.id, preference)
  }

  /// Remember the selected subtitle immediately; nil is a meaningful explicit Off selection.
  private func captureCurrentSubtitle() {
    guard watchMode == .media,
          let item = player.currentItem,
          let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)
    else { return }

    let selected = item.currentMediaSelection.selectedMediaOption(in: group)
    let preference: MediaLibraryStore.SubtitlePreference
    if let selected {
      preference = .init(isEnabled: true,
                         displayName: selected.displayName,
                         languageTag: selected.extendedLanguageTag,
                         index: group.options.firstIndex(of: selected))
    } else {
      preference = .init(isEnabled: false, displayName: nil, languageTag: nil, index: nil)
    }
    AppContext.shared.libraryState.setSubtitlePreference(itemId: playItem.metadata.id, preference)
  }
  
  // MARK: - Watch marks
  
  func saveWatchMark(time: TimeInterval) {
    // Persist a local resume point so "Continue Watching" reflects what the user actually
    // started, independent of the backend (skips live/trailers via the non-finite duration).
    if watchMode == .media {
      let duration = player.currentItem?.duration.seconds ?? 0
      AppContext.shared.localProgressStore.recordProgress(mediaId: playItem.metadata.id,
                                                          position: time,
                                                          duration: duration,
                                                          season: playItem.metadata.season,
                                                          episode: playItem.metadata.video)
    }

    Task.detached(priority: .utility) { [weak self] in
      guard let self else { return }
      do {
        try await self.actionsService.markWatch(id: self.playItem.metadata.id,
                                                time: Int(time), video: self.playItem.metadata.video,
                                                season: self.playItem.metadata.season)
      } catch {
        Logger.app.error("Failed to save watch mark: \(error)")
      }
    }
  }

  /// Reaching the end marks the title watched. kino.pub derives watched status from the position you
  /// report via `marktime` (there's no separate "set watched" call — `toggle` only flips it), so we
  /// send one final marktime at the full duration to push it over the threshold server-side, and
  /// clear the local resume point so Continue Watching drops it immediately (Netflix-style).
  private func markFinished() {
    guard watchMode == .media else { return }
    let duration = player.currentItem?.duration.seconds ?? 0
    guard duration.isFinite, duration > 0 else { return }
    let metadata = playItem.metadata
    let actionsService = actionsService
    AppContext.shared.localProgressStore.clear(id: metadata.id)
    Task.detached(priority: .utility) {
      do {
        try await actionsService.markWatch(id: metadata.id,
                                           time: Int(duration), video: metadata.video,
                                           season: metadata.season)
      } catch {
        Logger.app.error("Failed to mark finished: \(error)")
      }
    }
  }

  func fetchWatchMark() async {
    // Only media has a resume point (live/trailers don't).
    guard watchMode == .media else { return }

    var remoteContinueTime: TimeInterval = 0
    do {
      watchMark = try await actionsService.fetchWatchMark(id: playItem.metadata.id, video: playItem.metadata.video, season: playItem.metadata.season)
      if let watchMark {
        remoteContinueTime = watchMark.item.videos?.first?.time ?? watchMark.item.seasons?.first?.episodes.first?.time ?? 0
      }
    } catch {
      Logger.app.error("Failed to fetch watch mark: \(error)")
    }

    // Fall back to the local resume point: a movie/episode watched in-app records its position
    // locally on every tick, so it resumes even when the server mark lags or the fetch fails.
    let localContinueTime = AppContext.shared.localProgressStore
      .entry(forId: playItem.metadata.id, season: playItem.metadata.season, episode: playItem.metadata.video)?
      .position ?? 0

    let best = max(remoteContinueTime, localContinueTime)
    // Keep any value we already seeded synchronously if the refined fetch somehow comes back empty.
    if best > 0 { continueTime = best }
  }
  
  // MARK: - Continue watching
  
  func seekToContinueWatching() {
    guard let continueTime else {
      return
    }
    let seekTime = CMTime(seconds: continueTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
    self.continueTime = nil

    // Seek now if the item is ready; otherwise wait for it to become ready and seek once. Seeking
    // a not-yet-ready item is silently dropped, which is why resume sometimes "played from start".
    if player.currentItem?.status == .readyToPlay {
      player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
    } else {
      seekObservation = player.currentItem?.observe(\.status, options: [.new]) { [weak self] item, _ in
        guard item.status == .readyToPlay else { return }
        DispatchQueue.main.async {
          guard let self, self.player.currentItem === item else { return }
          self.player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
          self.seekObservation?.invalidate()
          self.seekObservation = nil
        }
      }
    }
  }
  
  func cancelContinueWatching() {
    self.continueTime = nil
  }

  // MARK: - 3D view mode

  /// Switch the 3D rendering live (rebuilds the per-frame composition on the current item).
  func setThreeDMode(_ mode: ThreeDMode) {
    threeDMode = mode
    PlayerManager.preferredThreeDMode = mode
    guard let item = player.currentItem else { return }
    item.videoComposition = ThreeDVideoComposition.make(for: item.asset, mode: mode)
  }

}

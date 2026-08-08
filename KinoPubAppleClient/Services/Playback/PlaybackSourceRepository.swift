//
//  PlaybackSourceRepository.swift
//  KinoPubAppleClient
//
//  Turns a `PlayableItem` into a concrete `PlaybackSource`: local download first, then the remote
//  ladder (hls4 → hls2 → progressive), with signed-URL refresh for expired/denied links. Owns
//  the recovery state (refreshed file list, generated URL, current ladder rung) so `PlayerManager`
//  stays a thin coordinator (see plans/refactor.md Phase 6). Testable without AVPlayer: the file
//  existence check and the content service are injected. Deliberately a plain class, not an
//  actor: `PlayerManager` (MainActor) is its only writer; the single network method is only
//  called from the already-async recovery path.
//

import Foundation
import CoreGraphics
import KinoPubBackend
import KinoPubKit

/// Injectable file-existence check so local-source resolution is testable without real files.
protocol FileExistenceChecking {
  func fileExists(atPath path: String) -> Bool
}

struct DefaultFileExistenceChecker: FileExistenceChecking {
  func fileExists(atPath path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
  }
}

final class PlaybackSourceRepository {
  /// The recovery ladder rung currently in use for the remote stream.
  private enum StreamLadder: Equatable {
    case hls4
    case hls2
    case progressive

    var kind: PlaybackSource.Kind { self == .progressive ? .remoteProgressive : .remoteHLS }

    var streamType: String {
      switch self {
      case .hls4: return "hls4"
      case .hls2: return "hls2"
      case .progressive: return "http"
      }
    }
  }

  enum PlaybackRefreshError: LocalizedError, Equatable {
    case missingFiles
    case missingFilePath
    case missingURL

    var errorDescription: String? {
      switch self {
      case .missingFiles: return "The media-links response did not include files."
      case .missingFilePath: return "The media file did not include a path for URL generation."
      case .missingURL: return "The server did not generate a playback URL."
      }
    }
  }

  private let downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>
  private let contentService: VideoContentService
  private let fileExistence: FileExistenceChecking

  private var refreshedFiles: [FileInfo]?
  private var generatedStreamURL: URL?
  private var remoteStreamSource: StreamLadder = .hls4

  init(
    downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>,
    contentService: VideoContentService,
    fileExistence: FileExistenceChecking = DefaultFileExistenceChecker()
  ) {
    self.downloadedFilesDatabase = downloadedFilesDatabase
    self.contentService = contentService
    self.fileExistence = fileExistence
  }

  /// Forget recovery state (episode switch / new session).
  func reset() {
    refreshedFiles = nil
    generatedStreamURL = nil
    remoteStreamSource = .hls4
  }

  /// The file list that should drive quality decisions: the refreshed media-links response when
  /// a refresh happened, otherwise the item's own files.
  func currentFiles(for item: any PlayableItem) -> [FileInfo] {
    refreshedFiles ?? item.files
  }

  /// Resolve the initial source for `item`. Prefers an existing local download, then a
  /// progressive URL for 3D titles (AVVideoComposition is ignored on HLS), then the current
  /// remote ladder rung. Returns nil only when no playable URL exists.
  func initialSource(
    for item: any PlayableItem,
    mode: WatchMode,
    is3D: Bool,
    maxResolution: CGSize?
  ) -> PlaybackSource? {
    switch mode {
    case .trailer:
      guard let urlString = item.trailer?.url, !urlString.isEmpty,
        let url = URL(string: urlString)
      else { return nil }
      return PlaybackSource(url: url, kind: .trailer)

    case .media:
      if let localURL = localDownloadURL(for: item) {
        return PlaybackSource(url: localURL, kind: .localFile)
      }
      // A 3D title needs a progressive (non-HLS) source: AVVideoComposition (the SBS/OU/anaglyph
      // reshaping) is ignored on HLS, so streaming via hls4 would just show the raw packed image.
      if is3D {
        let mp4 = BestVideoQualityFinder.bestProgressiveURL(for: item.files)
        if !mp4.isEmpty, let url = URL(string: mp4) {
          return PlaybackSource(url: url, kind: .remoteProgressive)
        }
      }
      if let generatedStreamURL {
        return PlaybackSource(url: generatedStreamURL, kind: .remoteHLS)
      }
      return remoteLadderSource(for: item, maxResolution: maxResolution)
    }
  }

  /// Mint a fresh signed URL for `item`, advancing the ladder by `recoveryAttempt`:
  /// 0 → hls4, 1 → hls2, ≥2 → progressive http. Uses the dedicated media-link endpoints so a
  /// denied URL is replaced rather than re-fetched (item details may keep returning the same one).
  func refreshSource(
    for item: any PlayableItem,
    recoveryAttempt: Int,
    maxResolution: CGSize?
  ) async throws -> PlaybackSource {
    if refreshedFiles == nil {
      let mediaID = (item as? MediaItem)?.videos?.first?.id ?? item.id
      let links = try await contentService.fetchMediaLinks(mediaID: mediaID)
      guard !links.files.isEmpty else { throw PlaybackRefreshError.missingFiles }
      refreshedFiles = links.files
    }

    guard let file = preferredFile(in: currentFiles(for: item), maxResolution: maxResolution),
      let rawPath = file.file, !rawPath.isEmpty
    else {
      throw PlaybackRefreshError.missingFilePath
    }

    let streamType: String
    switch recoveryAttempt {
    case 0:
      streamType = "hls4"
      remoteStreamSource = .hls4
    case 1:
      streamType = "hls2"
      remoteStreamSource = .hls2
    default:
      streamType = "http"
      remoteStreamSource = .progressive
    }

    let link = try await contentService.fetchMediaVideoLink(file: rawPath, type: streamType)
    guard let freshURL = URL(string: link.url), !link.url.isEmpty else {
      throw PlaybackRefreshError.missingURL
    }
    generatedStreamURL = freshURL
    return PlaybackSource(url: freshURL, kind: remoteStreamSource.kind, streamType: streamType)
  }

  /// The best file under the optional resolution cap (`.auto` passes nil). Anamorphic files are
  /// gated by their width via `h`, so `max(resolution, h)` is the effective size.
  func preferredFile(in files: [FileInfo], maxResolution: CGSize?) -> FileInfo? {
    guard !files.isEmpty else { return nil }
    let cap = maxResolution.map { Int($0.height) }
    let eligible = cap.map { limit in files.filter { max($0.resolution, $0.h) <= limit } } ?? files
    let candidates = eligible.isEmpty ? files : eligible
    return candidates.max { max($0.resolution, $0.h) < max($1.resolution, $1.h) }
  }

  // MARK: - Source selection internals

  /// A download is saved under the SERIES content id (DownloadMeta.id == mediaItem.id), but the
  /// identity differs by entry point: an Episode's `id` is the episode id while its `metadata.id`
  /// is the series id; a DownloadMeta is the reverse. Match on either so an already-downloaded
  /// movie/episode opened from the detail page plays the local file instead of streaming.
  private func localDownloadURL(for item: any PlayableItem) -> URL? {
    let contentIds: Set<Int> = [item.id, item.metadata.id]
    let downloadedFiles = downloadedFilesDatabase.readData() ?? []
    let sameItem = downloadedFiles.filter { contentIds.contains($0.metadata.id) }
    // For a series there can be several downloads under the same (series) id, plus stale rows whose
    // file was deleted. Pick the row whose source URL matches THIS item's files (the right episode),
    // then any same-item row — but only when the file is actually present on disk. Otherwise fall
    // through to streaming instead of handing AVPlayer a missing file (the "crossed-out play" icon).
    let playURLs = Set(item.files.map { $0.url.http })
    let chosen = sameItem.first(where: { playURLs.contains($0.originalURL.absoluteString) }) ?? sameItem.first
    if let chosen, fileExistence.fileExists(atPath: chosen.localFileURL.path) {
      return chosen.localFileURL
    }
    return nil
  }

  private func remoteLadderSource(for item: any PlayableItem, maxResolution: CGSize?) -> PlaybackSource? {
    let files = currentFiles(for: item)
    let urlString: String
    switch remoteStreamSource {
    case .hls4:
      urlString = files.first?.url.hls4 ?? ""
    case .hls2:
      urlString = files.first?.url.hls2 ?? ""
    case .progressive:
      urlString = preferredFile(in: files, maxResolution: maxResolution)?.url.http ?? ""
    }
    guard !urlString.isEmpty, let url = URL(string: urlString) else { return nil }
    return PlaybackSource(url: url, kind: remoteStreamSource.kind, streamType: remoteStreamSource.streamType)
  }
}

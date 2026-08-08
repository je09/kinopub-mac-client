//
//  LibraryCommand.swift
//  KinoPubAppleClient
//
//  The typed command API of the library repository: every user mutation of bookmark/watch/watchlist
//  state. Features send commands through `LibraryViewState`; they never call bookmark/watch mutation
//  endpoints directly.
//

import Foundation

/// Every user mutation of library state.
enum LibraryCommand: Equatable {
  case toggleBookmark(itemId: Int, folderId: Int)
  case setBookmark(itemId: Int, folderId: Int, isOn: Bool)
  case toggleWatchlist(itemId: Int)
  case setWatchlist(itemId: Int, value: Bool)
  case toggleMovieWatched(itemId: Int)
  case toggleEpisodeWatched(itemId: Int, episodeId: Int, video: Int, season: Int)

  /// The per-item serialization key. Conflicting mutations on the same key are serialized and
  /// coalesced; mutations on different keys run concurrently.
  var syncKey: LibrarySyncKey {
    switch self {
    case .toggleBookmark(let itemId, let folderId), .setBookmark(let itemId, let folderId, _):
      return .bookmark(itemId: itemId, folderId: folderId)
    case .toggleWatchlist(let itemId), .setWatchlist(let itemId, _):
      return .watchlist(itemId: itemId)
    case .toggleMovieWatched(let itemId):
      return .watchedMovie(itemId: itemId)
    case .toggleEpisodeWatched(let itemId, let episodeId, _, _):
      return .watchedEpisode(itemId: itemId, episodeId: episodeId)
    }
  }
}

/// Serialization key for the command journal — identifies which per-item mutation stream a command
/// belongs to. The remote call parameters live on the command, not the key.
enum LibrarySyncKey: Hashable {
  case bookmark(itemId: Int, folderId: Int)
  case watchlist(itemId: Int)
  case watchedMovie(itemId: Int)
  case watchedEpisode(itemId: Int, episodeId: Int)
}

/// Result of submitting a `LibraryCommand`, delivered to the awaiting feature model.
enum LibraryCommandOutcome {
  /// Optimistic state confirmed by a successful remote call (or no call was needed).
  case applied
  /// Repeated toggles paired off: state applied, nothing to send. Net effect was a no-op.
  case coalesced
  /// Aborted (e.g. logout) before the remote call completed; optimistic state rolled back.
  case cancelled
  /// Remote call failed; optimistic state was rolled back.
  case failed(Error)
}

enum LibraryRepositoryError: Error {
  case deactivated
}

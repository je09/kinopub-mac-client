//
//  LibraryRepository+Sync.swift
//  KinoPubAppleClient
//
//  Server-data API of `LibraryRepository`: seeding and reconciliation from authoritative fetches,
//  the bookmark-folder session cache, folder CRUD, and the locally-persisted preferences/votes.
//  (The optimistic command journal lives in LibraryRepository.swift; persistence is delegated to
//  LibraryPersistence.)
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import OSLog

extension LibraryRepository {

  // MARK: Seeding / reconciliation (authoritative server data)

  /// Seed an item's library state from authoritative server data the first time we see it, without
  /// clobbering optimistic edits the user may have made. Server truth is tracked on every call so
  /// set commands can skip redundant remote toggles.
  func seedIfAbsent(itemId: Int, folderIds: [Int], inWatchlist: Bool) async {
    guard isActive else { return }
    for folderId in folderIds {
      serverValue[.bookmark(itemId: itemId, folderId: folderId)] = true
    }
    serverValue[.watchlist(itemId: itemId)] = inWatchlist
    guard records[itemId] == nil else { return }
    records[itemId] = LibraryRecord(bookmarkFolderIds: folderIds.sorted(), inWatchlist: inWatchlist)
    schedulePersist()
    publish()
  }

  /// Fetch the item's folder membership from the server and seed local records (used by the Search
  /// bookmark sheet so it renders the same checkmarks as the detail screen). Does not touch the
  /// watchlist.
  func seedBookmarkMembership(itemId: Int) async {
    guard isActive else { return }
    do {
      let folderIds = try await actionsService.foldersContaining(itemId: itemId)
      for folderId in folderIds {
        serverValue[.bookmark(itemId: itemId, folderId: folderId)] = true
      }
      guard records[itemId] == nil else { return }
      records[itemId] = LibraryRecord(bookmarkFolderIds: folderIds.sorted(), inWatchlist: nil)
      schedulePersist()
      publish()
    } catch {
      Logger.app.debug("Library: seed bookmark membership failed for \(itemId): \(error)")
    }
  }

  /// Drop optimistic watched overrides that fresh server data now confirms, so the server drives
  /// again; overrides that still differ (a toggle still in flight) are kept.
  func reconcileWatched(movieItemId: Int, serverMovieWatched: Bool?, episodes: [(id: Int, watched: Bool)]) async {
    guard isActive else { return }
    var changed = false
    if let server = serverMovieWatched {
      serverValue[.watchedMovie(itemId: movieItemId)] = server
      if movieWatchedOverride[movieItemId] == server {
        movieWatchedOverride[movieItemId] = nil
        changed = true
      }
    }
    for episode in episodes {
      serverValue[.watchedEpisode(itemId: movieItemId, episodeId: episode.id)] = episode.watched
      if episodeWatchedOverride[episode.id] == episode.watched {
        episodeWatchedOverride[episode.id] = nil
        changed = true
      }
    }
    if changed {
      schedulePersist()
    }
    publish()
  }

  // MARK: Bookmark folders (session cache)

  /// Load the user's bookmark folders once per session; subsequent calls are no-ops.
  func loadBookmarkFoldersIfNeeded() async {
    guard isActive, !bookmarkFoldersLoaded, !bookmarkFoldersLoading else { return }
    await reloadBookmarkFolders()
  }

  /// Force a fresh fetch (e.g. pull-to-refresh on the Bookmarks tab, or after creating a folder).
  func reloadBookmarkFolders() async {
    guard isActive, !bookmarkFoldersLoading else { return }
    bookmarkFoldersLoading = true
    defer { bookmarkFoldersLoading = false }
    do {
      bookmarkFolders = try await actionsService.fetchBookmarks()
      bookmarkFoldersLoaded = true
      publish()
    } catch {
      // Leave any previously cached folders in place; callers surface their own errors if needed.
      Logger.app.debug("Library: reload bookmark folders failed: \(error)")
    }
  }

  /// Drop a folder from the cached list after it's deleted on its detail screen, so the Bookmarks
  /// list (which observes this) removes it without a full refetch. Also clears item→folder records
  /// and marks the folder as gone on the server.
  func removeCachedBookmarkFolder(id: Int) async {
    bookmarkFolders.removeAll { $0.id == id }
    for (itemId, var record) in records where record.bookmarkFolderIds.contains(id) {
      record.bookmarkFolderIds.removeAll { $0 == id }
      records[itemId] = record
      serverValue[.bookmark(itemId: itemId, folderId: id)] = false
    }
    schedulePersist()
    publish()
  }

  // MARK: Folder CRUD

  func createBookmarkFolder(title: String) async throws -> Int {
    guard isActive else { throw LibraryRepositoryError.deactivated }
    let folderId = try await actionsService.createBookmarkFolder(title: title)
    // Refresh the cached list so every screen sees the new folder immediately.
    await reloadBookmarkFolders()
    return folderId
  }

  func removeBookmarkFolder(id: Int) async throws {
    guard isActive else { throw LibraryRepositoryError.deactivated }
    try await actionsService.removeBookmarkFolder(id: id)
    await removeCachedBookmarkFolder(id: id)
  }

  // MARK: Preferences / votes (local persistence only, no remote)

  func setAudioPreference(itemId: Int, _ preference: LibraryAudioPreference) async {
    guard isActive, audioPreferences[itemId] != preference else { return }
    audioPreferences[itemId] = preference
    schedulePersist()
    publish()
  }

  func setSubtitlePreference(itemId: Int, _ preference: LibrarySubtitlePreference) async {
    guard isActive, subtitlePreferences[itemId] != preference else { return }
    subtitlePreferences[itemId] = preference
    schedulePersist()
    publish()
  }

  func setUserVote(itemId: Int, up: Bool) async {
    guard isActive, userVotes[itemId] != up else { return }
    userVotes[itemId] = up
    schedulePersist()
    publish()
  }

  func clearUserVote(itemId: Int) async {
    guard isActive, userVotes[itemId] != nil else { return }
    userVotes[itemId] = nil
    schedulePersist()
    publish()
  }
}

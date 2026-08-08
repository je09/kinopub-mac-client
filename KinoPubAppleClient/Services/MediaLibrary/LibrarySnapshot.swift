//
//  LibrarySnapshot.swift
//  KinoPubAppleClient
//
//  Value types for the library state owned by `LibraryRepository`. The snapshot is the published
//  view handed to the UI projection (`LibraryViewState`); the smaller types are its parts and the
//  on-disk building blocks.
//

import Foundation
import KinoPubBackend

/// A value snapshot of everything the library repository owns, published to the UI projection.
/// Views read state through the projection, never the actor directly.
struct LibrarySnapshot: Equatable {
  var records: [Int: LibraryRecord] = [:]
  var movieWatchedOverride: [Int: Bool] = [:]
  var episodeWatchedOverride: [Int: Bool] = [:]
  var audioPreferences: [Int: LibraryAudioPreference] = [:]
  var subtitlePreferences: [Int: LibrarySubtitlePreference] = [:]
  var userVotes: [Int: Bool] = [:]
  var bookmarkFolders: [Bookmark] = []

  static let empty = LibrarySnapshot()
}

/// Per-item library record: which bookmark folders contain the item, plus watchlist membership.
struct LibraryRecord: Codable, Equatable {
  var bookmarkFolderIds: [Int] = []
  var inWatchlist: Bool?
}

/// A remembered audio-track selection, captured from the AVPlayer's own media-selection option.
struct LibraryAudioPreference: Codable, Equatable {
  var displayName: String
  var languageTag: String?
  var index: Int
}

/// `isEnabled == false` preserves the user's explicit subtitle Off selection.
struct LibrarySubtitlePreference: Codable, Equatable {
  var isEnabled: Bool
  var displayName: String?
  var languageTag: String?
  var index: Int?
}

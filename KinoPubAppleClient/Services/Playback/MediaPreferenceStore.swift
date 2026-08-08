//
//  MediaPreferenceStore.swift
//  KinoPubAppleClient
//
//  Owns playback preferences (see plans/refactor.md Phase 6): audio/subtitle live in the library
//  snapshot (account-scoped, optimistic — Phase 4), stream quality and 3D mode live in
//  UserDefaults (device-scoped). The injected UserDefaults suite keeps tests isolated from the
//  real preferences.
//

import Foundation

@MainActor
struct MediaPreferenceStore {
  static let threeDModeKey = "preferredThreeDMode"

  private let libraryState: LibraryViewState
  private let defaults: UserDefaults

  init(libraryState: LibraryViewState, defaults: UserDefaults = .standard) {
    self.libraryState = libraryState
    self.defaults = defaults
  }

  // MARK: - Audio / subtitle (account-scoped, via the library snapshot)

  func audioPreference(itemId: Int) -> LibraryAudioPreference? {
    libraryState.audioPreference(itemId: itemId)
  }

  func subtitlePreference(itemId: Int) -> LibrarySubtitlePreference? {
    libraryState.subtitlePreference(itemId: itemId)
  }

  func setAudioPreference(itemId: Int, _ preference: LibraryAudioPreference) async {
    await libraryState.setAudioPreference(itemId: itemId, preference)
  }

  func setSubtitlePreference(itemId: Int, _ preference: LibrarySubtitlePreference) async {
    await libraryState.setSubtitlePreference(itemId: itemId, preference)
  }

  // MARK: - Stream quality / 3D mode (device-scoped, UserDefaults)

  var streamQuality: StreamQuality {
    get {
      defaults.string(forKey: StreamQuality.userDefaultsKey).flatMap(StreamQuality.init(rawValue:)) ?? .auto
    }
    set {
      defaults.set(newValue.rawValue, forKey: StreamQuality.userDefaultsKey)
    }
  }

  var preferredThreeDMode: ThreeDMode {
    get { Self.preferredThreeDMode(in: defaults) }
    set { Self.setPreferredThreeDMode(newValue, in: defaults) }
  }

  /// Last-used 3D view mode, persisted across launches. Defaults to Side-by-Side 2D — the common
  /// packing, shown flat so it is watchable without glasses.
  static func preferredThreeDMode(in defaults: UserDefaults) -> ThreeDMode {
    defaults.string(forKey: threeDModeKey).flatMap(ThreeDMode.init(rawValue:)) ?? .sbsMono
  }

  static func setPreferredThreeDMode(_ mode: ThreeDMode, in defaults: UserDefaults) {
    defaults.set(mode.rawValue, forKey: threeDModeKey)
  }
}

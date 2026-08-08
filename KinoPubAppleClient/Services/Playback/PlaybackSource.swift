//
//  PlaybackSource.swift
//  KinoPubAppleClient
//
//  A resolved playback entry point (see plans/refactor.md Phase 6). `PlaybackSourceRepository`
//  computes these; `AVPlayerController` consumes them. The value is small and immutable so both
//  sides can be tested without AVPlayer or network.
//

import Foundation

struct PlaybackSource: Equatable {
  enum Kind: Equatable {
    /// A file previously downloaded by the app (must exist on disk at resolve time).
    case localFile
    /// A remote adaptive HLS stream (quality cap applies).
    case remoteHLS
    /// A remote progressive (mp4) stream, used for 3D titles and as the recovery fallback.
    case remoteProgressive
    /// The item's trailer.
    case trailer
  }

  let url: URL
  let kind: Kind
  /// Stream-type label minted by signed-URL refresh ("hls4"/"hls2"/"http"), for diagnostics.
  let streamType: String?

  init(url: URL, kind: Kind, streamType: String? = nil) {
    self.url = url
    self.kind = kind
    self.streamType = streamType
  }

  var isRemote: Bool { kind == .remoteHLS || kind == .remoteProgressive }
  var isHLS: Bool { kind == .remoteHLS }
}

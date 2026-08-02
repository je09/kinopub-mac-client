
//
//  BestVideoQualityFinder.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 11.08.2023.
//

import Foundation
import KinoPubBackend

struct BestVideoQualityFinder {
  static func findBestURL(for files: [FileInfo]) -> String {
    files.first?.url.hls4 ?? ""
  }

  /// Best progressive (non-HLS) mp4 URL — the highest-resolution `http` file. 3D playback needs this
  /// because `AVVideoComposition` (the SBS/OU/anaglyph reshaping) is ignored on HLS streams, so a 3D
  /// title streamed via hls4 would just show the raw packed image.
  static func bestProgressiveURL(for files: [FileInfo]) -> String {
    let best = files.max(by: { $0.resolution < $1.resolution }) ?? files.first
    return best?.url.http ?? ""
  }
}

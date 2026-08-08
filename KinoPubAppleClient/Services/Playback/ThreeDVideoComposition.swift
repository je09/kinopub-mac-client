//
//  ThreeDVideoComposition.swift
//  KinoPubAppleClient
//
//  Pure media utilities for stereoscopic (3D) playback, extracted from PlayerManager so the
//  packing/mode policy is testable without an AVPlayer (see plans/refactor.md Phase 6).
//

import Foundation
import AVFoundation
import CoreImage

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
  /// Returns `nil` for `.off` (no composition needed).
  static func make(for asset: AVAsset, mode: ThreeDMode) -> AVVideoComposition? {
    guard mode != .off else { return nil }
    return AVMutableVideoComposition(asset: asset) { request in
      let output = composite(
        sourceImage: request.sourceImage,
        sideBySide: mode.isSideBySide,
        anaglyph: mode.isAnaglyph)
      request.finish(with: output.cropped(to: request.sourceImage.extent), context: nil)
    }
  }

  /// Pure per-frame pipeline: crop each eye from its packed half, un-squeeze it back to the full
  /// frame, and optionally combine them into a red-cyan anaglyph. Exposed for focused tests.
  static func composite(sourceImage: CIImage, sideBySide: Bool, anaglyph: Bool) -> CIImage {
    let e = sourceImage.extent

    // Each eye cropped from its half and stretched back to the full frame (half-packed sources
    // squeeze each eye, so un-squeezing restores the correct aspect).
    func leftEye() -> CIImage {
      if sideBySide {
        return sourceImage.cropped(to: CGRect(x: e.minX, y: e.minY, width: e.width / 2, height: e.height))
          .transformed(by: CGAffineTransform(scaleX: 2, y: 1))
      } else {  // Over-Under: left eye on top (CI origin is bottom-left → upper half)
        return sourceImage.cropped(to: CGRect(x: e.minX, y: e.midY, width: e.width, height: e.height / 2))
          .transformed(by: CGAffineTransform(translationX: 0, y: -e.height / 2))
          .transformed(by: CGAffineTransform(scaleX: 1, y: 2))
      }
    }
    func rightEye() -> CIImage {
      if sideBySide {
        return sourceImage.cropped(to: CGRect(x: e.midX, y: e.minY, width: e.width / 2, height: e.height))
          .transformed(by: CGAffineTransform(translationX: -e.width / 2, y: 0))
          .transformed(by: CGAffineTransform(scaleX: 2, y: 1))
      } else {
        return sourceImage.cropped(to: CGRect(x: e.minX, y: e.minY, width: e.width, height: e.height / 2))
          .transformed(by: CGAffineTransform(scaleX: 1, y: 2))
      }
    }

    if anaglyph {
      let leftRed = leftEye().applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0),
        ])
      let rightCyan = rightEye().applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
        ])
      return leftRed.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: rightCyan])
    }
    return leftEye()
  }
}

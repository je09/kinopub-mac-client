//
//  ThreeDVideoCompositionTests.swift
//  KinoPubAppleClientTests
//
//  Phase 6: focused tests for the pure 3D media utility — mode geometry, the nil-for-off rule,
//  and the per-frame composite pipeline rendered through CoreImage (no AVPlayer, no network).
//

import XCTest
import CoreImage
import CoreGraphics
import AVFoundation
import KinoPubBackend
@testable import KinoPub

final class ThreeDVideoCompositionTests: XCTestCase {
  // MARK: - Mode geometry

  func testModeGeometry() {
    XCTAssertTrue(ThreeDMode.sbsMono.isSideBySide)
    XCTAssertTrue(ThreeDMode.sbsAnaglyph.isSideBySide)
    XCTAssertFalse(ThreeDMode.ouMono.isSideBySide)
    XCTAssertFalse(ThreeDMode.ouAnaglyph.isSideBySide)

    XCTAssertTrue(ThreeDMode.sbsAnaglyph.isAnaglyph)
    XCTAssertTrue(ThreeDMode.ouAnaglyph.isAnaglyph)
    XCTAssertFalse(ThreeDMode.sbsMono.isAnaglyph)
    XCTAssertFalse(ThreeDMode.ouMono.isAnaglyph)
    XCTAssertFalse(ThreeDMode.off.isAnaglyph)
  }

  func testOffModeProducesNoComposition() {
    let asset = AVURLAsset(url: URL(fileURLWithPath: "/tmp/does-not-exist.mp4"))
    XCTAssertNil(ThreeDVideoComposition.make(for: asset, mode: .off))
  }

  // MARK: - Composite pipeline (rendered via CIContext)

  /// A 4×2 image: left half red, right half green.
  private func makeSideBySideSource() -> CIImage {
    let red = CIColor(red: 1, green: 0, blue: 0)
    let green = CIColor(red: 0, green: 1, blue: 0)
    let left = CIImage(color: red).cropped(to: CGRect(x: 0, y: 0, width: 2, height: 2))
    let right = CIImage(color: green).cropped(to: CGRect(x: 2, y: 0, width: 2, height: 2))
    return left.composited(over: right)
  }

  /// A 4×2 image: top half red, bottom half green (CI origin is bottom-left).
  private func makeOverUnderSource() -> CIImage {
    let red = CIColor(red: 1, green: 0, blue: 0)
    let green = CIColor(red: 0, green: 1, blue: 0)
    let top = CIImage(color: red).cropped(to: CGRect(x: 0, y: 2, width: 4, height: 2))
    let bottom = CIImage(color: green).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 2))
    return top.composited(over: bottom)
  }

  private func sample(_ image: CIImage, x: CGFloat, y: CGFloat) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
    var pixel = [UInt8](repeating: 0, count: 4)
    let context = CIContext(options: [.workingColorSpace: NSNull()])
    context.render(
      image,
      toBitmap: &pixel,
      rowBytes: 4,
      bounds: CGRect(x: x, y: y, width: 1, height: 1),
      format: .RGBA8,
      colorSpace: CGColorSpaceCreateDeviceRGB())
    return (CGFloat(pixel[0]) / 255, CGFloat(pixel[1]) / 255, CGFloat(pixel[2]) / 255)
  }

  func testMonoSideBySideUsesLeftEyeScaledToFullFrame() {
    let output = ThreeDVideoComposition.composite(
      sourceImage: makeSideBySideSource(), sideBySide: true, anaglyph: false)
    // The left (red) eye is stretched over the whole frame.
    let left = sample(output, x: 0.5, y: 1)
    let right = sample(output, x: 3.5, y: 1)
    XCTAssertGreaterThan(left.r, 0.8, "left eye must be red")
    XCTAssertLessThan(left.g, 0.2)
    XCTAssertGreaterThan(right.r, 0.8, "right side must be the stretched left eye, not blue")
    XCTAssertLessThan(right.b, 0.2)
  }

  func testMonoOverUnderUsesTopHalf() {
    let output = ThreeDVideoComposition.composite(
      sourceImage: makeOverUnderSource(), sideBySide: false, anaglyph: false)
    // The top (red) eye fills the whole frame.
    let top = sample(output, x: 2, y: 3)
    let bottom = sample(output, x: 2, y: 0.5)
    XCTAssertGreaterThan(top.r, 0.8)
    XCTAssertGreaterThan(bottom.r, 0.8, "bottom must be the stretched top eye, not blue")
    XCTAssertLessThan(bottom.b, 0.2)
  }

  func testAnaglyphKeepsLeftRedAndRightGreenChannels() {
    let output = ThreeDVideoComposition.composite(
      sourceImage: makeSideBySideSource(), sideBySide: true, anaglyph: true)
    // The matrix keeps the left eye's red and the right eye's green+blue (its "cyan" channel —
    // only red is dropped): red-left + green-right composites to yellow (1,1,0).
    let pixel = sample(output, x: 1.5, y: 1)
    XCTAssertGreaterThan(pixel.r, 0.8, "left red channel preserved")
    XCTAssertGreaterThan(pixel.g, 0.8, "right green channel preserved")
    XCTAssertLessThan(pixel.b, 0.2, "no blue anywhere")
  }

  func testAnaglyphOverUnderBlendsBothEyesEverywhere() {
    let output = ThreeDVideoComposition.composite(
      sourceImage: makeOverUnderSource(), sideBySide: false, anaglyph: true)
    let top = sample(output, x: 2, y: 3)
    let bottom = sample(output, x: 2, y: 0.5)
    XCTAssertGreaterThan(top.r, 0.8)
    XCTAssertGreaterThan(top.g, 0.8)
    XCTAssertGreaterThan(bottom.r, 0.8, "bottom must also blend both eyes, not raw green")
    XCTAssertGreaterThan(bottom.g, 0.8)
    XCTAssertLessThan(bottom.b, 0.2)
  }
}

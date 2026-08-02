//
//  HeroBackdrop.swift
//
//
//  Apple TV-style cinematic hero header: full-bleed backdrop with a frosted/gradient
//  fade into the background and an overlay slot for title / metadata / actions.
//

import AppKit
import AVFoundation
import SwiftUI

public struct HeroBackdrop<Overlay: View>: View {

  private let imageURLs: [String]
  private let videoURL: String?
  private let height: CGFloat
  private let tallBlur: Bool
  private let blurReduction: CGFloat
  private let leadingScrim: Bool
  private let transparentBase: Bool
  private let overlay: Overlay

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var imageIndex = 0
  @State private var isHoveringControls = false
  @State private var artworkScale: CGFloat = 1
  @State private var videoPaused = false

  public init(imageURL: String?,
              videoURL: String? = nil,
              height: CGFloat = 460,
              tallBlur: Bool = false,
              blurReduction: CGFloat = 0,
              leadingScrim: Bool = false,
              transparentBase: Bool = false,
              @ViewBuilder overlay: () -> Overlay) {
    self.init(imageURLs: imageURL.map { [$0] } ?? [],
              videoURL: videoURL,
              height: height,
              tallBlur: tallBlur,
              blurReduction: blurReduction,
              leadingScrim: leadingScrim,
              transparentBase: transparentBase,
              overlay: overlay)
  }

  /// Creates a gently animated backdrop carousel. Empty and duplicate URLs are discarded.
  public init(imageURLs: [String],
              videoURL: String? = nil,
              height: CGFloat = 460,
              tallBlur: Bool = false,
              blurReduction: CGFloat = 0,
              leadingScrim: Bool = false,
              transparentBase: Bool = false,
              @ViewBuilder overlay: () -> Overlay) {
    var seen = Set<String>()
    self.imageURLs = imageURLs.filter { !$0.isEmpty && seen.insert($0).inserted }
    self.videoURL = videoURL.flatMap { $0.isEmpty ? nil : $0 }
    self.height = height
    self.tallBlur = tallBlur
    self.blurReduction = blurReduction
    self.leadingScrim = leadingScrim
    self.transparentBase = transparentBase
    self.overlay = overlay()
  }

  public var body: some View {
    // A base view pinned to the available width keeps every layer (artwork, scrims,
    // and the bottom-leading overlay) anchored to the screen.
    (transparentBase ? Color.clear : Color.KinoPub.background)
      .frame(maxWidth: .infinity)
      .frame(height: height)
      // A trailer and poster are mutually exclusive. Layering a translucent video over artwork
      // produces ghosted faces/titles whenever their compositions differ.
      .overlay {
        if !transparentBase && playableVideoURL == nil { animatedArtwork }
      }
      .overlay {
        if !transparentBase, let url = playableVideoURL {
          LoopingBackdropVideo(url: url, isPlaying: !videoPaused)
        }
      }
      .overlay(alignment: .topTrailing) {
        if !transparentBase { carouselControls }
      }
      .overlay(alignment: .bottomLeading) {
        overlay
          .padding(.horizontal, 36)
          .padding(.bottom, 16)
      }
      .frame(height: height)
      .clipped()
      .allowsHitTesting(true)
      .task(id: imageURLs) { await runCarousel() }
  }

  private var playableVideoURL: URL? {
    guard !reduceMotion, let videoURL, !videoURL.isEmpty else { return nil }
    return URL(string: videoURL)
  }

  private var currentImageURL: String? {
    guard imageURLs.indices.contains(imageIndex) else { return imageURLs.first }
    return imageURLs[imageIndex]
  }

  private var animatedArtwork: some View {
    ZStack {
      CachedAsyncImage(url: URL(string: currentImageURL ?? "")) { image in
        image
          .resizable()
          .renderingMode(.original)
          .aspectRatio(contentMode: .fill)
      } placeholder: {
        Color.KinoPub.skeleton
      }
      .id(currentImageURL)
      .transition(.opacity)
      .scaleEffect(artworkScale)
    }
    .animation(reduceMotion ? nil : .easeInOut(duration: 1.1), value: imageIndex)
    .onAppear { animateArtwork() }
    .onChange(of: imageIndex) { _ in animateArtwork() }
  }

  @ViewBuilder
  private var carouselControls: some View {
    if imageURLs.count > 1 || videoURL != nil {
      HStack(spacing: 10) {
        if videoURL != nil, !reduceMotion {
          Button { videoPaused.toggle() } label: {
            Image(systemName: videoPaused ? "play.fill" : "pause.fill")
          }
          .help(videoPaused ? "Play preview" : "Pause preview")
        }
        if imageURLs.count > 1 {
          Button { selectPrevious() } label: {
            Image(systemName: "chevron.left")
          }
          Text("\(imageIndex + 1) / \(imageURLs.count)")
            .font(.caption.monospacedDigit())
            .frame(minWidth: 34)
          Button { selectNext() } label: {
            Image(systemName: "chevron.right")
          }
        }
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.ultraThinMaterial, in: Capsule())
      .opacity(isHoveringControls ? 1 : 0.72)
      .onHover { hovering in
        withAnimation(.easeOut(duration: 0.15)) { isHoveringControls = hovering }
      }
      .padding(16)
      .accessibilityElement(children: .contain)
      .accessibilityLabel("Backdrop carousel")
    }
  }

  @MainActor
  private func runCarousel() async {
    if !imageURLs.indices.contains(imageIndex) { imageIndex = 0 }
    guard imageURLs.count > 1, !reduceMotion else { return }
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 6_000_000_000)
      guard !Task.isCancelled else { return }
      selectNext()
    }
  }

  private func selectPrevious() {
    guard !imageURLs.isEmpty else { return }
    withAnimation(.easeInOut(duration: 1.1)) {
      imageIndex = (imageIndex - 1 + imageURLs.count) % imageURLs.count
    }
  }

  private func selectNext() {
    guard !imageURLs.isEmpty else { return }
    withAnimation(.easeInOut(duration: 1.1)) {
      imageIndex = (imageIndex + 1) % imageURLs.count
    }
  }

  private func animateArtwork() {
    artworkScale = 1
    guard !reduceMotion else { return }
    withAnimation(.linear(duration: 6)) { artworkScale = 1.035 }
  }
}

/// A control-free, muted, looping video intended for a full-window cinematic backdrop.
public struct CinematicBackdropVideo: View {
  private let url: URL
  private let isPlaying: Bool
  private let onReady: () -> Void

  public init(url: URL, isPlaying: Bool = true, onReady: @escaping () -> Void = {}) {
    self.url = url
    self.isPlaying = isPlaying
    self.onReady = onReady
  }

  public var body: some View {
    LoopingBackdropVideo(url: url, isPlaying: isPlaying, onReady: onReady)
  }
}

/// Control-free, muted and looping—the Apple TV-style preview remains decorative while the real
/// trailer button opens the normal player with sound and transport controls.
private struct LoopingBackdropVideo: NSViewRepresentable {
  let url: URL
  let isPlaying: Bool
  var onReady: () -> Void = {}

  func makeNSView(context: Context) -> BackdropVideoView {
    let view = BackdropVideoView()
    view.onReady = onReady
    view.configure(url: url)
    view.setPlaying(isPlaying)
    return view
  }

  func updateNSView(_ view: BackdropVideoView, context: Context) {
    view.onReady = onReady
    view.configure(url: url)
    view.setPlaying(isPlaying)
  }

  static func dismantleNSView(_ view: BackdropVideoView, coordinator: Void) {
    view.stop()
  }
}

private final class BackdropVideoView: NSView {
  private let playerLayer = AVPlayerLayer()
  private var player: AVQueuePlayer?
  private var looper: AVPlayerLooper?
  private var currentURL: URL?
  private var readyObservation: NSKeyValueObservation?
  private var didReportReady = false
  var onReady: () -> Void = {}

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    // Apple TV fills the cinematic stage edge-to-edge. Crop the trailer as needed rather than
    // introducing letterbox bars above/below a very wide hero.
    playerLayer.backgroundColor = NSColor.clear.cgColor
    layer?.addSublayer(playerLayer)
    readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
      guard layer.isReadyForDisplay, let self, !self.didReportReady else { return }
      self.didReportReady = true
      DispatchQueue.main.async { [weak self] in self?.onReady() }
    }
  }

  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    playerLayer.frame = bounds
    playerLayer.videoGravity = .resizeAspectFill
  }

  func configure(url: URL) {
    guard currentURL != url else { return }
    stop()
    currentURL = url
    didReportReady = false
    let item = AVPlayerItem(url: url)
    item.preferredForwardBufferDuration = 5
    item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
    let player = AVQueuePlayer()
    player.isMuted = true
    player.actionAtItemEnd = .none
    player.automaticallyWaitsToMinimizeStalling = true
    self.player = player
    looper = AVPlayerLooper(player: player, templateItem: item)
    // Attaching the paused player starts asset/first-frame loading. Do not call `preroll` until the
    // player is ready—AVFoundation raises an Objective-C exception rather than returning an error.
    playerLayer.player = player
  }

  func setPlaying(_ playing: Bool) {
    if playing { player?.play() } else { player?.pause() }
  }

  func stop() {
    player?.pause()
    looper?.disableLooping()
    looper = nil
    player = nil
    playerLayer.player = nil
    currentURL = nil
  }
}

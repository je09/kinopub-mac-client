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
              @ViewBuilder overlay: () -> Overlay) {
    self.init(imageURLs: imageURL.map { [$0] } ?? [],
              videoURL: videoURL,
              height: height,
              tallBlur: tallBlur,
              blurReduction: blurReduction,
              overlay: overlay)
  }

  /// Creates a gently animated backdrop carousel. Empty and duplicate URLs are discarded.
  public init(imageURLs: [String],
              videoURL: String? = nil,
              height: CGFloat = 460,
              tallBlur: Bool = false,
              blurReduction: CGFloat = 0,
              @ViewBuilder overlay: () -> Overlay) {
    var seen = Set<String>()
    self.imageURLs = imageURLs.filter { !$0.isEmpty && seen.insert($0).inserted }
    self.videoURL = videoURL.flatMap { $0.isEmpty ? nil : $0 }
    self.height = height
    self.tallBlur = tallBlur
    self.blurReduction = blurReduction
    self.overlay = overlay()
  }

  public var body: some View {
    // A base view pinned to the available width keeps every layer (artwork, scrims,
    // and the bottom-leading overlay) anchored to the screen.
    Color.KinoPub.background
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .overlay { animatedArtwork }
      .overlay {
        if let videoURL, let url = URL(string: videoURL), !reduceMotion {
          LoopingBackdropVideo(url: url, isPlaying: !videoPaused)
            .opacity(0.9)
            .transition(.opacity)
        }
      }
      .overlay(alignment: .bottom) {
        // Frosted blur over the lower portion so overlay text never mixes with busy artwork.
        Rectangle()
          .fill(.ultraThinMaterial)
          .frame(height: max(height - blurReduction, 0))
          .mask(
            LinearGradient(colors: tallBlur ? [.clear, .black, .black] : [.clear, .clear, .black],
                           startPoint: .top,
                           endPoint: .bottom)
          )
      }
      .overlay {
        LinearGradient(
          colors: [
            Color.KinoPub.background.opacity(0.0),
            Color.KinoPub.background.opacity(0.5),
            Color.KinoPub.background
          ],
          startPoint: .center,
          endPoint: .bottom
        )
      }
      .overlay(alignment: .top) {
        // Keep titlebar labels legible while artwork still visibly extends beneath the glass.
        LinearGradient(colors: [Color.black.opacity(0.48), Color.black.opacity(0.16), .clear],
                       startPoint: .top,
                       endPoint: .bottom)
          .frame(height: 120)
      }
      .overlay(alignment: .topTrailing) { carouselControls }
      .overlay(alignment: .bottomLeading) {
        overlay
          .padding(.horizontal, 20)
          .padding(.bottom, 16)
      }
      .frame(height: height)
      .clipped()
      .allowsHitTesting(true)
      .task(id: imageURLs) { await runCarousel() }
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

/// Control-free, muted and looping—the Apple TV-style preview remains decorative while the real
/// trailer button opens the normal player with sound and transport controls.
private struct LoopingBackdropVideo: NSViewRepresentable {
  let url: URL
  let isPlaying: Bool

  func makeNSView(context: Context) -> BackdropVideoView {
    let view = BackdropVideoView()
    view.configure(url: url)
    view.setPlaying(isPlaying)
    return view
  }

  func updateNSView(_ view: BackdropVideoView, context: Context) {
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

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    // Trailers are usually 16:9 while the hero is much wider. Preserve the authored frame—burned-in
    // titles and faces near the top/bottom otherwise get visibly chopped by aspect-fill cropping.
    playerLayer.videoGravity = .resizeAspect
    playerLayer.backgroundColor = NSColor.clear.cgColor
    layer?.addSublayer(playerLayer)
  }

  required init?(coder: NSCoder) { nil }

  override func layout() {
    super.layout()
    playerLayer.frame = bounds
  }

  func configure(url: URL) {
    guard currentURL != url else { return }
    stop()
    currentURL = url
    let item = AVPlayerItem(url: url)
    let player = AVQueuePlayer()
    player.isMuted = true
    player.actionAtItemEnd = .none
    self.player = player
    looper = AVPlayerLooper(player: player, templateItem: item)
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

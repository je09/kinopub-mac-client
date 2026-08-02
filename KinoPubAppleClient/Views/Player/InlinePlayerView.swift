//
//  InlinePlayerView.swift
//  KinoPubAppleClient
//
//  An embedded (non-modal) 16:9 player with native controls and a fullscreen toggle,
//  used by the wide-screen Sport layout to play a live channel right in the third column.
//

import SwiftUI
import AVKit
import AVFoundation

struct InlinePlayerView: View {
  let url: URL

  var body: some View {
    PlatformInlinePlayer(url: url)
      .aspectRatio(16.0 / 9.0, contentMode: .fit)
      .background(Color.black)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

struct PlatformInlinePlayer: NSViewRepresentable {
  let url: URL

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.player = AVPlayer(url: url)
    view.controlsStyle = .inline
    view.showsFullScreenToggleButton = true
    // PiP currently crashes the ad-hoc macOS build during AVKit's window hand-off.
    view.allowsPictureInPicturePlayback = false
    view.player?.play()
    return view
  }

  func updateNSView(_ view: AVPlayerView, context: Context) {}

  static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
    view.player?.pause()
    view.player = nil
  }
}

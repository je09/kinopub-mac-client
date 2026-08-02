//
//  ScreenStyle.swift
//  KinoPubUI
//
//  One shared modifier for every top-level screen's navigation chrome, so titles, background and
//  toolbar look and take up space identically across the native macOS app.
//  its own navigationTitle / display-mode / toolbar combination).
//

import AppKit
import SwiftUI

public extension View {
  /// Standard top-level macOS screen chrome: title and app background.
  func kinoScreen(_ title: String) -> some View {
    modifier(KinoScreenModifier(title: title))
  }

  /// Compatibility no-op retained for existing screen call sites; macOS owns its toolbar material.
  @ViewBuilder
  func navBarBlurBackground() -> some View {
    self
  }

  /// Extends cinematic content beneath a permanently translucent unified toolbar. This avoids the
  /// native scroll-edge transition switching between glass and an opaque titlebar while the hero
  /// carousel changes or settles at the top.
  @ViewBuilder
  func heroNavBar() -> some View {
    self
      .ignoresSafeArea(.container, edges: .top)
      .background(WindowGlassProbe())
  }

  /// Shapes the context-menu "lift" preview to a rounded rectangle so a surrounding ScrollView /
  /// LazyVGrid / horizontal stack doesn't clip the lifted cell on long-press (rawtherapy technique:
  /// `.contentShape(.contextMenuPreview, …)` renders the preview in its own un-clipped layer). Apply
  /// to the same view that carries `.contextMenu`.
  @ViewBuilder
  func contextMenuPreviewShape(cornerRadius: CGFloat = 12) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    self.contentShape(shape)
  }

  /// Wraps content in a floating capsule "island": real Liquid Glass on OS 26, an ultra-thin material
  /// capsule on older systems. Use for pinned/sticky section headers so they read as Apple-style
  /// floating islands over the scrolling content instead of a flat opaque bar.
  @ViewBuilder
  func glassCapsule() -> some View {
    // `glassEffect` only exists in the macOS 26 SDK (Xcode 26 = Swift 6.2). Compile-time gate so
    // older toolchains (e.g. CI on Xcode 16) still build, falling back to a material capsule.
#if compiler(>=6.2)
    if #available(macOS 26.0, *) {
      self.glassEffect(.regular, in: Capsule())
    } else {
      self.background(.ultraThinMaterial, in: Capsule())
    }
#else
    self.background(.ultraThinMaterial, in: Capsule())
#endif
  }
}

private struct WindowGlassProbe: NSViewRepresentable {
  func makeNSView(context: Context) -> GlassProbeView { GlassProbeView() }
  func updateNSView(_ view: GlassProbeView, context: Context) { view.configureWindow() }

  final class GlassProbeView: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      configureWindow()
      DispatchQueue.main.async { [weak self] in self?.configureWindow() }
    }

    func configureWindow() {
      guard let window else { return }
      window.styleMask.insert(.fullSizeContentView)
      window.titlebarAppearsTransparent = true
      window.toolbarStyle = .unified
      window.toolbar?.showsBaselineSeparator = false
    }
  }
}

private struct KinoScreenModifier: ViewModifier {
  let title: String

  func body(content: Content) -> some View {
    content
      .navigationTitle(title)
      .background(Color.KinoPub.background)
  }
}

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

  /// Places content on the system Liquid Glass material. Unlike a hand-built blur/material, the
  /// system effect follows the user's Clear/Tinted Liquid Glass choice and accessibility settings.
  /// Older macOS releases retain the existing material treatment.
  @ViewBuilder
  func systemGlass<S: Shape>(in shape: S) -> some View {
    // `glassEffect` only exists in the macOS 26 SDK (Xcode 26 = Swift 6.2). Compile-time gate so
    // older toolchains (e.g. CI on Xcode 16) still build.
#if compiler(>=6.2)
    if #available(macOS 26.0, *) {
      self.glassEffect(.regular, in: shape)
    } else {
      self.background(.ultraThinMaterial, in: shape)
    }
#else
    self.background(.ultraThinMaterial, in: shape)
#endif
  }

  /// Adds noninteractive system glass behind controls that must remain above the effect layer.
  @ViewBuilder
  func systemGlassBackground<S: Shape>(in shape: S) -> some View {
#if compiler(>=6.2)
    if #available(macOS 26.0, *) {
      self.background {
        shape
          .fill(.clear)
          .glassEffect(.regular, in: shape)
          .allowsHitTesting(false)
      }
    } else {
      self.background(.ultraThinMaterial, in: shape)
    }
#else
    self.background(.ultraThinMaterial, in: shape)
#endif
  }

  /// Wraps content in a floating capsule "island" using the system-selected glass appearance.
  func glassCapsule() -> some View {
    systemGlass(in: Capsule())
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

//
//  ScreenStyle.swift
//  KinoPubUI
//
//  One shared modifier for every top-level screen's navigation chrome, so titles, background and
//  toolbar look and take up space identically across the native macOS app.
//  its own navigationTitle / display-mode / toolbar combination).
//

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

  /// Compatibility no-op; the native macOS toolbar controls the titlebar appearance.
  @ViewBuilder
  func heroNavBar() -> some View {
    self
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

private struct KinoScreenModifier: ViewModifier {
  let title: String

  func body(content: Content) -> some View {
    content
      .navigationTitle(title)
      .background(Color.KinoPub.background)
  }
}

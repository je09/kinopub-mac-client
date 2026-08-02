//
//  RootView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 17.07.2023.
//

import AppKit
import SwiftUI
import KinoPubUI

private struct SectionEmbeddedKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var sectionEmbedded: Bool {
    get { self[SectionEmbeddedKey.self] }
    set { self[SectionEmbeddedKey.self] = newValue }
  }
}

extension View {
  func moreBackButton() -> some View { self }

  /// Preserve the primary vertical scroll view while a sidebar destination is temporarily removed
  /// from the SwiftUI hierarchy. The data model is cached separately; this restores its viewport.
  func rememberScreenScrollPosition(_ id: String) -> some View {
    background(ScreenScrollPositionProbe(id: id))
  }
}

private final class ScreenScrollPositionStore {
  static let shared = ScreenScrollPositionStore()
  var positions: [String: NSPoint] = [:]
}

private struct ScreenScrollPositionProbe: NSViewRepresentable {
  let id: String

  func makeCoordinator() -> Coordinator { Coordinator(id: id) }

  func makeNSView(context: Context) -> ProbeView {
    let view = ProbeView()
    view.onAttach = { [weak coordinator = context.coordinator, weak view] in
      guard let view else { return }
      coordinator?.connect(from: view)
    }
    return view
  }

  func updateNSView(_ view: ProbeView, context: Context) {
    context.coordinator.id = id
    DispatchQueue.main.async { [weak coordinator = context.coordinator, weak view] in
      guard let view else { return }
      coordinator?.connect(from: view)
    }
  }

  static func dismantleNSView(_ view: ProbeView, coordinator: Coordinator) {
    coordinator.disconnect(saving: true)
  }

  final class Coordinator {
    var id: String
    private weak var scrollView: NSScrollView?
    private var boundsObserver: NSObjectProtocol?

    init(id: String) { self.id = id }
    deinit { disconnect(saving: true) }

    func connect(from probe: NSView) {
      guard let found = primaryScrollView(near: probe) else { return }
      if scrollView === found { return }
      disconnect(saving: false)
      scrollView = found

      let clipView = found.contentView
      clipView.postsBoundsChangedNotifications = true
      if let saved = ScreenScrollPositionStore.shared.positions[id] {
        let maxX = max(0, (found.documentView?.bounds.width ?? 0) - clipView.bounds.width)
        let maxY = max(0, (found.documentView?.bounds.height ?? 0) - clipView.bounds.height)
        clipView.scroll(to: NSPoint(x: min(max(saved.x, 0), maxX),
                                    y: min(max(saved.y, 0), maxY)))
        found.reflectScrolledClipView(clipView)
      }
      boundsObserver = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification,
        object: clipView,
        queue: .main
      ) { [weak self, weak clipView] _ in
        guard let self, let clipView else { return }
        ScreenScrollPositionStore.shared.positions[self.id] = clipView.bounds.origin
      }
    }

    func disconnect(saving: Bool) {
      if saving, let scrollView {
        ScreenScrollPositionStore.shared.positions[id] = scrollView.contentView.bounds.origin
      }
      if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
      boundsObserver = nil
      scrollView = nil
    }

    /// Search only as far up as needed, avoiding the sidebar's own list. The largest vertically
    /// scrollable view at the nearest level is the destination's main viewport rather than a shelf.
    private func primaryScrollView(near probe: NSView) -> NSScrollView? {
      var ancestor = probe.superview
      for _ in 0..<6 {
        guard let current = ancestor else { break }
        let candidates = scrollViews(in: current).filter { scroll in
          guard let document = scroll.documentView else { return false }
          return document.bounds.height > scroll.contentView.bounds.height + 1
        }
        if let best = candidates.max(by: { score($0) < score($1) }) { return best }
        ancestor = current.superview
      }
      return nil
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
      var result: [NSScrollView] = []
      if let scroll = view as? NSScrollView { result.append(scroll) }
      for child in view.subviews { result.append(contentsOf: scrollViews(in: child)) }
      return result
    }

    private func score(_ scroll: NSScrollView) -> CGFloat {
      scroll.contentView.bounds.width * scroll.contentView.bounds.height
    }
  }
}

private final class ProbeView: NSView {
  var onAttach: (() -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard window != nil else { return }
    DispatchQueue.main.async { [weak self] in self?.onAttach?() }
  }
}

struct RootView: View {
  @EnvironmentObject private var appearance: AppearanceSettings

  var body: some View {
    SidebarView()
      .tint(appearance.accent.color)
  }
}

struct RootView_Previews: PreviewProvider {
  static var previews: some View {
    RootView()
      .environmentObject(AppearanceSettings())
  }
}

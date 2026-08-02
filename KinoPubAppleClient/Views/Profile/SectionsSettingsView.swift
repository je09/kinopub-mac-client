//
//  SectionsSettingsView.swift
//  KinoPubAppleClient
//
//  Sidebar visibility settings. Reordering is available directly from the sidebar's Customize menu.
//

import SwiftUI

struct SectionsSettingsView: View {
  @ObservedObject private var visibility = SectionVisibilityStore.shared

  var body: some View {
    Form {
      Section(header: Text("Discover".localized)) {
        ForEach(visibility.discoverItems) { row($0) }
      }
      Section(header: Text("Library".localized)) {
        ForEach(visibility.libraryItems) { row($0) }
      }
      Section(header: Text("My Library".localized),
              footer: Text("Hover over Library in the sidebar, then choose Edit to reorder items by dragging.".localized)) {
        ForEach(visibility.personalItems) { row($0) }
      }
      Section {
        Button("Restore Sidebar Defaults".localized) { visibility.reset() }
      }
    }
    .scrollContentBackground(.hidden)
    .background(Color.KinoPub.background)
    .navigationTitle("Sections".localized)
  }

  private func row(_ item: SidebarItem) -> some View {
    Toggle(isOn: Binding(
      get: { visibility.isVisible(item) },
      set: { visibility.setVisible(item, $0) }
    )) {
      Label(item.title.localized, systemImage: item.systemImage)
        .foregroundStyle(Color.KinoPub.text)
    }
    .disabled(!visibility.canHide(item))
  }
}

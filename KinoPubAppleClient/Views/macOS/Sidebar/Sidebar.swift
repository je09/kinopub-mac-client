//
//  Sidebar.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 11.08.2023.
//

import SwiftUI
import KinoPubBackend
import KinoPubKit
import KinoPubUI

struct Sidebar: View {
  @Binding var selection: SidebarItem?

  @EnvironmentObject private var navigationState: NavigationState
  @EnvironmentObject private var networkMonitor: NetworkMonitor
  @ObservedObject private var visibility = SectionVisibilityStore.shared

  var body: some View {
    List(selection: selectionBinding) {
      row(.new)
      row(.search)

      Section("Library".localized) {
        ForEach(SidebarItem.libraryCategories, id: \.self) { type in
          if visibility.isVisible(.category(type)) { row(.category(type)) }
        }
        ForEach(CatalogPreset.visible) { preset in
          if visibility.isVisible(.preset(preset)) { row(.preset(preset)) }
        }
        if visibility.isVisible(.sport) { row(.sport) }
        row(.collections)
      }

      Section("Other".localized) {
        ForEach(SectionVisibilityStore.editableOther) { item in
          if visibility.isVisible(item) { row(item) }
        }
      }

      Section {
        row(.profile)
      }
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .background(Color.KinoPub.background)
    .navigationTitle("KinoPub")
    .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
  }

  private var selectionBinding: Binding<SidebarItem?> {
    Binding(
      get: { selection },
      set: { newValue in
        selection = newValue
        if let newValue { navigationState.popToRoot(for: newValue) }
      }
    )
  }

  private func row(_ item: SidebarItem) -> some View {
    let locked = !networkMonitor.isOnline && !item.isAvailableOffline
    return Label {
      HStack {
        Text(item.title.localized)
        if locked {
          Spacer(minLength: 6)
          Image(systemName: "lock.fill")
            .font(.caption2)
            .accessibilityLabel("Needs a connection".localized)
        }
      }
    } icon: {
      Image(systemName: item.systemImage)
    }
    .foregroundStyle(locked ? Color.KinoPub.subtitle : Color.KinoPub.text)
    .tag(item)
    .disabled(locked)
    .help(locked ? "Needs a connection".localized : item.title.localized)
  }
}

struct Sidebar_Previews: PreviewProvider {
  struct Preview: View {
    @State private var selection: SidebarItem? = .new

    var body: some View {
      Sidebar(selection: $selection)
        .environmentObject(NavigationState())
        .environmentObject(NetworkMonitor())
    }
  }

  static var previews: some View {
    NavigationSplitView {
      Preview()
    } detail: {
      Text("Detail")
    }
  }
}

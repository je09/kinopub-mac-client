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
  @EnvironmentObject private var appearance: AppearanceSettings
  @EnvironmentObject private var libraryState: MediaLibraryStore
  @ObservedObject private var visibility = SectionVisibilityStore.shared
  @State private var isEditingSections = false
  @State private var isHoveringLibraryHeader = false

  var body: some View {
    List(selection: selectionBinding) {
      Section {
        row(.new)
        ForEach(SectionVisibilityStore.editableDiscover) { item in
          if isEditingSections || visibility.isVisible(item) { row(item) }
        }
      } header: {
        sectionHeader("Discover")
      }

      Section {
        ForEach(SidebarItem.libraryCategories, id: \.self) { type in
          if isEditingSections || visibility.isVisible(.category(type)) { row(.category(type)) }
        }
        ForEach(CatalogPreset.visible) { preset in
          if isEditingSections || visibility.isVisible(.preset(preset)) { row(.preset(preset)) }
        }
        if isEditingSections || visibility.isVisible(.sport) { row(.sport) }
        row(.collections)
      } header: {
        libraryHeader
      }

      if isEditingSections || visibility.isVisible(.bookmarks) {
        Section {
          row(.bookmarks)
          if !isEditingSections {
            ForEach(libraryState.bookmarkFolders) { folder in
              bookmarkFolderRow(folder)
            }
          }
        } header: {
          sectionHeader("Bookmarks")
        }
      }

      Section {
        row(.profile)
      }
    }
    .listStyle(.sidebar)
    .environment(\.defaultMinListRowHeight, appearance.sidebarDensity.rowHeight)
    .modifier(SidebarBackground(style: appearance.sidebarAppearance,
                                accent: appearance.accent.color))
    .navigationTitle("KinoPub")
    .navigationSplitViewColumnWidth(min: 200,
                                    ideal: appearance.sidebarDensity.idealWidth,
                                    max: 340)
    .animation(.easeInOut(duration: 0.2), value: appearance.sidebarDensity)
    .animation(.easeInOut(duration: 0.2), value: appearance.sidebarAppearance)
    .animation(.easeInOut(duration: 0.2), value: isEditingSections)
    .task(id: networkMonitor.isOnline) {
      if networkMonitor.isOnline { await libraryState.loadBookmarkFoldersIfNeeded() }
    }
    .onChange(of: libraryState.bookmarkFolders.map(\.id)) { folderIDs in
      guard case .bookmarkFolder(let id) = selection, !folderIDs.contains(id) else { return }
      selection = .bookmarks
    }
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

  @ViewBuilder
  private func sectionHeader(_ title: String) -> some View {
    if appearance.showsSectionHeaders {
      Text(title.localized)
    }
  }

  @ViewBuilder
  private var libraryHeader: some View {
    if appearance.showsSectionHeaders {
      HStack(spacing: 8) {
        Text("Library".localized)
        Spacer()
        Button(isEditingSections ? "Done".localized : "Edit".localized) {
          withAnimation(.easeInOut(duration: 0.2)) { isEditingSections.toggle() }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.trailing, 12)
        .contentShape(Rectangle())
        .opacity(isHoveringLibraryHeader || isEditingSections ? 1 : 0)
        .allowsHitTesting(isHoveringLibraryHeader || isEditingSections)
        .help("Customize Sidebar".localized)
      }
      .contentShape(Rectangle())
      .onHover { hovering in
        withAnimation(.easeOut(duration: 0.12)) { isHoveringLibraryHeader = hovering }
      }
    }
  }

  @ViewBuilder
  private func row(_ item: SidebarItem) -> some View {
    let locked = !networkMonitor.isOnline && !item.isAvailableOffline
    if isEditingSections && isConfigurable(item) {
      let visible = visibility.isVisible(item)
      Button {
        withAnimation(.easeInOut(duration: 0.15)) {
          visibility.setVisible(item, !visible)
        }
      } label: {
        Label {
          HStack {
            Text(item.title.localized)
              .foregroundStyle(visible ? Color.primary : Color.secondary)
            Spacer(minLength: 6)
            Image(systemName: visible ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(visible ? appearance.accent.color : Color.secondary)
          }
        } icon: {
          Image(systemName: item.systemImage)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(visible ? iconColor(for: item) : Color.secondary)
            .frame(width: 18)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(!visibility.canHide(item))
    } else {
      Label {
        HStack {
          Text(item.title.localized)
          if locked {
            Spacer(minLength: 6)
            Image(systemName: "lock.fill")
              .font(.caption2)
              .accessibilityLabel("Needs a connection".localized)
          }
        }
        .foregroundStyle(locked ? Color.secondary : Color.primary)
      } icon: {
        Image(systemName: item.systemImage)
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(locked ? Color.secondary : iconColor(for: item))
          .frame(width: 18)
      }
      .tag(item)
      .disabled(locked)
      .help(locked ? "Needs a connection".localized : item.title.localized)
    }
  }

  private func isConfigurable(_ item: SidebarItem) -> Bool {
    SectionVisibilityStore.editableDiscover.contains(item)
      || SectionVisibilityStore.editableLibrary.contains(item)
      || SectionVisibilityStore.editableBookmarks.contains(item)
  }

  private func bookmarkFolderRow(_ folder: Bookmark) -> some View {
    let item = SidebarItem.bookmarkFolder(folder.id)
    let locked = !networkMonitor.isOnline
    return Label {
      Text(folder.title)
        .foregroundStyle(locked ? Color.secondary : Color.primary)
    } icon: {
      Image(systemName: item.systemImage)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(locked ? Color.secondary : iconColor(for: item))
        .frame(width: 18)
    }
      .tag(item)
      .disabled(locked)
      .help(locked ? "Needs a connection".localized : folder.title)
  }

  private func iconColor(for item: SidebarItem) -> Color {
    switch appearance.sidebarIcons {
    case .monochrome:
      return .primary
    case .accent:
      return appearance.accent.color
    case .colorful:
      switch item {
      case .search: return .blue
      case .new: return .orange
      case .category: return appearance.accent.color
      case .preset: return .pink
      case .sport: return .green
      case .collections: return .purple
      case .newEpisodes: return .pink
      case .watching: return .cyan
      case .bookmarks: return .yellow
      case .bookmarkFolder: return .secondary
      case .history: return .indigo
      case .downloads: return .mint
      case .profile: return appearance.accent.color
      }
    }
  }
}

private struct SidebarBackground: ViewModifier {
  let style: SidebarAppearance
  let accent: Color

  @ViewBuilder
  func body(content: Content) -> some View {
    switch style {
    case .system:
      content
    case .tinted:
      content
        .scrollContentBackground(.hidden)
        .background(
          LinearGradient(colors: [accent.opacity(0.14), Color.KinoPub.background.opacity(0.92)],
                         startPoint: .topLeading,
                         endPoint: .bottomTrailing)
        )
    case .solid:
      content
        .scrollContentBackground(.hidden)
        .background(Color.KinoPub.background)
    }
  }
}

struct Sidebar_Previews: PreviewProvider {
  struct Preview: View {
    @State private var selection: SidebarItem? = .new

    var body: some View {
      Sidebar(selection: $selection)
        .environmentObject(NavigationState())
        .environmentObject(NetworkMonitor())
        .environmentObject(AppearanceSettings())
        .environmentObject(AppContext.shared.libraryState)
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

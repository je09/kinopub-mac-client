//
//  Sidebar.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 11.08.2023.
//

import SwiftUI
import UniformTypeIdentifiers
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
  @State private var draggedItem: SidebarItem?

  var body: some View {
    List(selection: selectionBinding) {
      // Apple TV keeps its two primary destinations above the first labeled group.
      Section {
        row(.search)
        row(.new)
        ForEach(visibility.discoverItems) { item in
          if isEditingSections || visibility.isVisible(item) { row(item) }
        }
      }

      Section {
        ForEach(visibility.libraryItems) { item in
          if isEditingSections || visibility.isVisible(item) { row(item) }
        }
      } header: {
        libraryHeader
      }

      if isEditingSections || visibility.personalItems.contains(where: visibility.isVisible) {
        Section {
          ForEach(visibility.personalItems) { item in
            if isEditingSections || visibility.isVisible(item) {
              row(item)
              if item == .bookmarks, !isEditingSections, visibility.isVisible(.bookmarks) {
                ForEach(libraryState.bookmarkFolders) { folder in
                  bookmarkFolderRow(folder)
                }
              }
            }
          }
        } header: {
          sectionHeader("My Library")
        }
      }

    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      profileRow
    }
    .environment(\.defaultMinListRowHeight, appearance.sidebarDensity.rowHeight)
    .modifier(SidebarBackground(style: appearance.sidebarAppearance,
                                accent: appearance.accent.color))
    .navigationTitle(Text(verbatim: "\u{200B}"))
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

  private var profileRow: some View {
    Button {
      selection = .profile
      navigationState.popToRoot(for: .profile)
    } label: {
      Label {
        Text("Profile".localized)
          .foregroundStyle(Color.primary)
        Spacer(minLength: 0)
      } icon: {
        Image(systemName: "person.crop.circle.fill")
          .font(.system(size: 24))
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(selection == .profile ? Color.white : iconColor(for: .profile))
          .frame(width: 26)
      }
      .padding(.horizontal, 8)
      .frame(height: 36)
      .contentShape(Rectangle())
      .background {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(selection == .profile ? appearance.accent.color : Color.clear)
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 8)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private func sectionHeader(_ title: String) -> some View {
    if appearance.showsSectionHeaders {
      Text(title.localized)
    }
  }

  private var libraryHeader: some View {
    HStack(spacing: 8) {
      if appearance.showsSectionHeaders { Text("Library".localized) }
      Spacer()
      Button(isEditingSections ? "Done".localized : "Edit".localized) {
        withAnimation(.easeInOut(duration: 0.2)) { isEditingSections.toggle() }
      }
      .buttonStyle(.plain)
      .foregroundStyle(.secondary)
      .opacity(isHoveringLibraryHeader || isEditingSections ? 1 : 0)
      .allowsHitTesting(isHoveringLibraryHeader || isEditingSections)
      .help("Customize Sidebar".localized)
    }
    .font(.caption)
    .padding(.trailing, 8)
    .contentShape(Rectangle())
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) { isHoveringLibraryHeader = hovering }
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
      .onDrag {
        draggedItem = item
        return NSItemProvider(object: item.id as NSString)
      }
      .onDrop(of: [UTType.text], delegate: SidebarItemDropDelegate(
        target: item,
        draggedItem: $draggedItem,
        visibility: visibility
      ))
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
      || SectionVisibilityStore.editablePersonal.contains(item)
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

private struct SidebarItemDropDelegate: DropDelegate {
  let target: SidebarItem
  @Binding var draggedItem: SidebarItem?
  let visibility: SectionVisibilityStore

  func dropEntered(info: DropInfo) {
    guard let draggedItem, draggedItem != target else { return }
    withAnimation(.easeInOut(duration: 0.15)) {
      visibility.move(draggedItem, before: target)
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    DropProposal(operation: .move)
  }

  func performDrop(info: DropInfo) -> Bool {
    draggedItem = nil
    return true
  }

  func dropExited(info: DropInfo) {}
}

private struct SidebarBackground: ViewModifier {
  let style: SidebarAppearance
  let accent: Color

  @ViewBuilder
  func body(content: Content) -> some View {
    switch style {
    case .system:
      // Keep the sidebar's structural material seamless with the titlebar. A standalone glass
      // effect draws its own top edge below the toolbar, which looks like an unwanted divider.
      content
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
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

//
//  SectionVisibilityStore.swift
//  KinoPubAppleClient
//
//  Persisted visibility and ordering for the native macOS sidebar.
//

import Combine
import Foundation

final class SectionVisibilityStore: ObservableObject {
  static let shared = SectionVisibilityStore()

  private let hiddenKey = "hiddenSectionIDs"
  private let discoverOrderKey = "sidebarDiscoverOrder"
  private let libraryOrderKey = "sidebarLibraryOrder"
  private let personalOrderKey = "sidebarPersonalOrder"

  @Published private(set) var hidden: Set<String>
  @Published private var discoverOrder: [String]
  @Published private var libraryOrder: [String]
  @Published private var personalOrder: [String]

  /// Defaults are grouped by purpose rather than by the original iOS tab layout.
  static let editableDiscover: [SidebarItem] = [.newEpisodes, .watching]
  static var editableLibrary: [SidebarItem] {
    SidebarItem.libraryCategories.map { .category($0) }
      + CatalogPreset.visible.map { .preset($0) }
      + [.sport, .collections]
  }
  static let editablePersonal: [SidebarItem] = [.bookmarks, .history, .downloads]

  private init() {
    let defaults = UserDefaults.standard
    hidden = Set(defaults.stringArray(forKey: hiddenKey) ?? [])
    discoverOrder = Self.restoredOrder(for: discoverOrderKey, defaults: Self.editableDiscover)
    libraryOrder = Self.restoredOrder(for: libraryOrderKey, defaults: Self.editableLibrary)
    personalOrder = Self.restoredOrder(for: personalOrderKey, defaults: Self.editablePersonal)
  }

  var discoverItems: [SidebarItem] { Self.items(for: discoverOrder, defaults: Self.editableDiscover) }
  var libraryItems: [SidebarItem] { Self.items(for: libraryOrder, defaults: Self.editableLibrary) }
  var personalItems: [SidebarItem] { Self.items(for: personalOrder, defaults: Self.editablePersonal) }

  func canHide(_ item: SidebarItem) -> Bool { true }
  func isVisible(_ item: SidebarItem) -> Bool { !hidden.contains(item.id) }

  func setVisible(_ item: SidebarItem, _ visible: Bool) {
    if visible { hidden.remove(item.id) } else { hidden.insert(item.id) }
    UserDefaults.standard.set(Array(hidden), forKey: hiddenKey)
  }

  /// Reorder on pointer entry, matching Music's immediate drag feedback. Items stay in their group.
  func move(_ item: SidebarItem, before target: SidebarItem) {
    if Self.reorder(&discoverOrder, item.id, before: target.id) {
      UserDefaults.standard.set(discoverOrder, forKey: discoverOrderKey)
    } else if Self.reorder(&libraryOrder, item.id, before: target.id) {
      UserDefaults.standard.set(libraryOrder, forKey: libraryOrderKey)
    } else if Self.reorder(&personalOrder, item.id, before: target.id) {
      UserDefaults.standard.set(personalOrder, forKey: personalOrderKey)
    }
  }

  private static func reorder(_ order: inout [String], _ id: String, before targetID: String) -> Bool {
    guard id != targetID,
          let sourceIndex = order.firstIndex(of: id),
          let targetIndex = order.firstIndex(of: targetID) else { return false }
    order.remove(at: sourceIndex)
    order.insert(id, at: min(targetIndex, order.endIndex))
    return true
  }

  func reset() {
    hidden.removeAll()
    discoverOrder = Self.editableDiscover.map(\.id)
    libraryOrder = Self.editableLibrary.map(\.id)
    personalOrder = Self.editablePersonal.map(\.id)
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: hiddenKey)
    defaults.removeObject(forKey: discoverOrderKey)
    defaults.removeObject(forKey: libraryOrderKey)
    defaults.removeObject(forKey: personalOrderKey)
  }

  private static func restoredOrder(for key: String, defaults: [SidebarItem]) -> [String] {
    let valid = defaults.map(\.id)
    let saved = UserDefaults.standard.stringArray(forKey: key) ?? []
    return saved.filter { valid.contains($0) } + valid.filter { !saved.contains($0) }
  }

  private static func items(for ids: [String], defaults: [SidebarItem]) -> [SidebarItem] {
    let byID = Dictionary(uniqueKeysWithValues: defaults.map { ($0.id, $0) })
    return ids.compactMap { byID[$0] }
  }
}

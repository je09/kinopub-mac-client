//
//  DownloadsView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 22.07.2023.
//

import SwiftUI
import KinoPubBackend
import KinoPubKit
import KinoPubUI

struct DownloadsView: View {
  
  @EnvironmentObject var navigationState: NavigationState
  @EnvironmentObject var errorHandler: ErrorHandler
  @StateObject private var catalog: DownloadsCatalog
  @Environment(\.dependencies) private var dependencies
  @Environment(\.sectionEmbedded) private var sectionEmbedded
  @State private var showStorage = false
  
  init(catalog: @autoclosure @escaping () -> DownloadsCatalog) {
    _catalog = StateObject(wrappedValue: catalog())
  }
  
  var body: some View {
    if sectionEmbedded {
      sectionContent
    } else {
      NavigationStack(path: $navigationState.downloadsRoutes) {
        sectionContent.routeDestinations()
      }
    }
  }
  
  private var sectionContent: some View {
    ZStack {
      if catalog.isEmpty {
        emptyView
      } else {
        downloadsList
      }
    }
    .kinoScreen("Downloads".localized)
    .onAppear(perform: {
      catalog.refresh()
    })
    .sheet(isPresented: $showStorage, onDismiss: { catalog.refresh() }) {
      StorageBreakdownView(
        store: StorageBreakdownStore(
          repository: dependencies.storageUsageRepository,
          downloadedFilesDatabase: dependencies.downloadedFilesDatabase))
    }
  }
  
  private var hasActive: Bool { !catalog.activeDownloads.isEmpty }
  private var hasCompleted: Bool { !catalog.downloadedItems.isEmpty }
  
  var downloadsList: some View {
    List {
      if hasActive {
        Section {
          activeDownloadsList
        } header: {
          sectionHeader("Active")
        }
      }
      if hasCompleted {
        Section {
          downloadedFilesList
        } header: {
          sectionHeader("Downloaded")
        }
      }
      if catalog.totalBytes > 0 {
        Button {
          showStorage = true
        } label: {
          HStack {
            Image(systemName: "internaldrive")
            Text("Storage used".localized)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: catalog.totalBytes, countStyle: .file))
              .foregroundStyle(Color.KinoPub.subtitle)
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Color.KinoPub.subtitle)
          }
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Color.KinoPub.text)
        }
        .listRowBackground(Color.clear)
      }
    }
    .listStyle(.inset)
    .scrollContentBackground(.hidden)
    .background(Color.KinoPub.background)
  }
  
  /// Floating glass-capsule section header — matches the History sticky headers (Liquid Glass on OS 26).
  private func sectionHeader(_ key: String) -> some View {
    Text(key.localized)
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(Color.KinoPub.text)
      .textCase(nil)
      .padding(.horizontal, 14)
      .padding(.vertical, 7)
      .glassCapsule()
    // Match the History sticky headers' left indent (20pt), not the List's default tight inset.
      .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 6, trailing: 4))
      .listRowBackground(Color.clear)
  }
  
  /// `NavigationLink` in a macOS `List` row can lose the click to the row itself, so push directly.
  private func playRow<Label: View>(_ route: Route, @ViewBuilder label: () -> Label) -> some View {
    Button {
      navigationState.downloadsRoutes.append(route)
    } label: {
      label()
    }
    .buttonStyle(.plain)
  }
  
  var activeDownloadsList: some View {
    // In-progress downloads are NOT navigable (file isn't ready) — so the pause/resume button
    // is tappable instead of the whole row opening the player.
    ForEach(catalog.activeDownloads, id: \.url) { download in
      DownloadedItemView(
        mediaItem: download.metadata,
        progress: download.progress,
        speed: download.speed,
        remaining: download.remainingTime
      ) { _ in
        catalog.toggle(download: download)
      }
      .contextMenu { detailLink(for: download.metadata) }
    }
    .onDelete(perform: { indexSet in
      catalog.deleteActiveDownload(at: indexSet)
    })
    .listRowBackground(Color.KinoPub.background)
  }
  
  var downloadedFilesList: some View {
    ForEach(catalog.downloadedItems, id: \.originalURL) { fileInfo in
      playRow(Route.player(fileInfo.metadata)) {
        DownloadedItemView(mediaItem: fileInfo.metadata, progress: nil, fileURL: fileInfo.localFileURL, fileSize: catalog.fileSizes[fileInfo.localFileURL]) { _ in }
      }
      .contextMenu { detailLink(for: fileInfo.metadata) }
    }
    .onDelete(perform: { indexSet in
      catalog.deleteDownloadedItem(at: indexSet)
    })
    .listRowBackground(Color.KinoPub.background)
  }
  
  /// Long-press menu entry to jump from a download to its movie/series detail page.
  /// `DownloadMeta.id` is the series/movie content id, so detailsByID opens the right title.
  @ViewBuilder
  private func detailLink(for meta: DownloadMeta) -> some View {
    // A series episode always carries a season/episode number; a movie has neither — reliable even
    // for older saved entries whose `episode` label may be wrong.
    let isSeries = meta.metadata.season != nil || meta.metadata.video != nil
    NavigationLink(value: Route.detailsByID(meta.id)) {
      Label(
        isSeries ? "Go to Series".localized : "Go to Movie".localized,
        systemImage: "info.circle")
    }
  }
  
  var emptyView: some View {
    EmptyStateView(systemImage: "arrow.down.circle", title: "You don't have any downloads yet".localized)
      .background(Color.KinoPub.background)
  }
}

// MARK: - Storage breakdown

/// Native macOS storage breakdown for downloads, cache, EPG data, and other app files. Renders
/// `StorageUsage` snapshots from the store and forwards clear intents; it never touches the
/// filesystem or caches itself.
struct StorageBreakdownView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var store: StorageBreakdownStore

  init(store: @autoclosure @escaping () -> StorageBreakdownStore) {
    _store = StateObject(wrappedValue: store())
  }

  var body: some View {
    NavigationStack {
      List {
        if let breakdown = store.breakdown {
          Section {
            row("Downloads".localized, breakdown.downloads)
            row("Image cache".localized, breakdown.imageCache)
            row("EPG", breakdown.epg)
            row("Other".localized, breakdown.other)
          }
          Section {
            HStack {
              Text("Total".localized).bold(); Spacer(); Text(format(breakdown.total)).bold()
            }
          }
          Section {
            Button("Clear image cache".localized) {
              store.clearImageCache()
            }
            Button("Clear EPG cache".localized) {
              store.clearEPGCache()
            }
          }
        } else {
          HStack {
            Spacer(); ProgressView(); Spacer()
          }
        }
      }
      .navigationTitle("Storage".localized)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done".localized) { dismiss() }
        }
      }
    }
    .toast(message: $store.toast)
    .onAppear(perform: store.refresh)
  }

  private func row(_ title: String, _ bytes: Int64) -> some View {
    HStack {
      Text(title); Spacer(); Text(format(bytes)).foregroundStyle(Color.KinoPub.subtitle)
    }
  }

  private func format(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }
}

struct DownloadsView_Previews: PreviewProvider {
  static var previews: some View {
    
    let database = DownloadedFilesDatabase<DownloadMeta>(fileSaver: FileSaver())
    
    let downloadManager = DownloadManager<DownloadMeta>(fileSaver: FileSaver(), database: database)
    
    DownloadsView(
      catalog: DownloadsCatalog(
        downloadsDatabase: database,
        downloadManager: downloadManager,
        storageRepository: StorageUsageRepository(epgService: EPGServiceMock()))
    )
    .appPreviewEnvironment()
  }
}

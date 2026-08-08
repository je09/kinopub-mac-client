//
//  DownloadsCatalog.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 8.08.2023.
//

import Combine
import Foundation
import KinoPubBackend
import KinoPubKit

@MainActor
final class DownloadsCatalog: ObservableObject {
  private let downloadsDatabase: DownloadedFilesDatabase<DownloadMeta>
  private let downloadManager: DownloadManager<DownloadMeta>
  private let storageRepository: StorageUsageRepository
  
  @Published var downloadedItems: [DownloadedFileInfo<DownloadMeta>] = []
  @Published var activeDownloads: [Download<DownloadMeta>] = []
  @Published var totalBytes: Int64 = 0
  /// On-disk sizes of downloaded files, computed off the main actor (keyed by local file URL).
  @Published var fileSizes: [URL: Int64] = [:]
  
  private var cancellables = [AnyCancellable]()
  
  var isEmpty: Bool { downloadedItems.isEmpty && activeDownloads.isEmpty }
  
  init(
    downloadsDatabase: DownloadedFilesDatabase<DownloadMeta>,
    downloadManager: DownloadManager<DownloadMeta>,
    storageRepository: StorageUsageRepository
  ) {
    self.downloadsDatabase = downloadsDatabase
    self.downloadManager = downloadManager
    self.storageRepository = storageRepository
  }
  
  func refresh() {
    let stored = downloadsDatabase.readData() ?? []
    var present: [DownloadedFileInfo<DownloadMeta>] = []
    for info in stored {
      if FileManager.default.fileExists(atPath: info.localFileURL.path) {
        present.append(info)
      } else {
        downloadsDatabase.remove(fileInfo: info)
      }
    }
    downloadedItems = present
    activeDownloads = Array(downloadManager.activeDownloads.values)
    cancellables.removeAll()
    recomputeTotalSize()
    
    for download in activeDownloads {
      download.objectWillChange
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.objectWillChange.send() }
        .store(in: &cancellables)
    }
  }
  
  func deleteDownloadedItem(at indexSet: IndexSet) {
    for index in indexSet {
      downloadsDatabase.remove(fileInfo: downloadedItems[index])
    }
    downloadedItems.remove(atOffsets: indexSet)
    recomputeTotalSize()
  }
  
  func deleteActiveDownload(at indexSet: IndexSet) {
    for index in indexSet {
      downloadManager.removeDownload(for: activeDownloads[index].url)
    }
    activeDownloads.remove(atOffsets: indexSet)
    recomputeTotalSize()
  }
  
  func toggle(download: Download<DownloadMeta>) {
    download.state == .inProgress ? download.pause() : download.resume()
  }
  
  private func recomputeTotalSize() {
    let urls = downloadedItems.map(\.localFileURL)
    Task {
      var bytes: Int64 = 0
      var sizes: [URL: Int64] = [:]
      for url in urls {
        let size = await storageRepository.byteSize(of: url)
        sizes[url] = size
        bytes += size
      }
      totalBytes = bytes
      fileSizes = sizes
    }
  }
}

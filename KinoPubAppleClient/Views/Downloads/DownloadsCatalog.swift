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

  @Published var downloadedItems: [DownloadedFileInfo<DownloadMeta>] = []
  @Published var activeDownloads: [Download<DownloadMeta>] = []
  @Published var totalBytes: Int64 = 0

  private var cancellables = [AnyCancellable]()

  var isEmpty: Bool { downloadedItems.isEmpty && activeDownloads.isEmpty }

  init(downloadsDatabase: DownloadedFilesDatabase<DownloadMeta>,
       downloadManager: DownloadManager<DownloadMeta>) {
    self.downloadsDatabase = downloadsDatabase
    self.downloadManager = downloadManager
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
    Task.detached(priority: .utility) {
      let bytes = urls.reduce(Int64(0)) { total, url in
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return total + ((attributes?[.size] as? Int64) ?? 0)
      }
      await MainActor.run { [weak self] in self?.totalBytes = bytes }
    }
  }
}

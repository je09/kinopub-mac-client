//
//  StorageBreakdownStore.swift
//  KinoPubAppleClient
//
//  State + intents for the Storage breakdown screen. Owns the `StorageUsage` snapshot and the
//  clear-cache intents; the view only renders state and forwards button taps.
//

import Foundation
import KinoPubKit
import KinoPubUI

@MainActor
final class StorageBreakdownStore: ObservableObject {

  @Published private(set) var breakdown: StorageUsage?
  @Published private(set) var busy = false
  /// Transient confirmation of a cleanup action (freed bytes), presented by the view as a toast.
  @Published var toast: ToastMessage?

  private let repository: StorageUsageRepository
  private let downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>

  init(
    repository: StorageUsageRepository,
    downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>
  ) {
    self.repository = repository
    self.downloadedFilesDatabase = downloadedFilesDatabase
  }

  /// Recomputes the on-disk usage snapshot off the main actor.
  func refresh() {
    busy = true
    let downloadURLs = (downloadedFilesDatabase.readData() ?? []).map { $0.localFileURL }
    Task {
      let result = await repository.usage(downloadURLs: downloadURLs)
      breakdown = result
      busy = false
    }
  }

  /// Clears the image cache and confirms how much was freed.
  func clearImageCache() {
    Task {
      let freed = await repository.clearImageCache()
      announce(freed: freed)
      refresh()
    }
  }

  /// Clears the EPG cache and confirms how much was freed.
  func clearEPGCache() {
    Task {
      let freed = await repository.clearEPGCache()
      announce(freed: freed)
      refresh()
    }
  }

  private func announce(freed: Int64) {
    if freed > 0 {
      toast = .success(String(format: "Freed %@".localized, ByteCountFormatter.string(fromByteCount: freed, countStyle: .file)))
    } else {
      toast = .info("Nothing to clear".localized)
    }
  }
}

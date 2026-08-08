//
//  StorageUsageRepository.swift
//  KinoPubAppleClient
//
//  Filesystem traversal and size accounting for the Downloads/Storage screens. An actor so disk
//  walks never block the main actor; views receive immutable `StorageUsage` snapshots and send
//  clear/delete intents through a store instead of touching the filesystem themselves.
//

import Foundation
import KinoPubUI

/// Computed on-disk usage buckets. `total` is the whole app data container (Documents + Library + tmp).
struct StorageUsage: Equatable {
  let total: Int64
  let downloads: Int64
  let imageCache: Int64
  let epg: Int64

  var other: Int64 { max(0, total - downloads - imageCache - epg) }
}

/// Filesystem-backed storage accounting: whole-container usage, per-download sizes (a `.movpkg`
/// bundle must be summed recursively), and cache clearing with freed-byte reporting.
actor StorageUsageRepository {

  private let epgService: any EPGService

  init(epgService: any EPGService) {
    self.epgService = epgService
  }

  /// Total usage of the app data container + download files + image/EPG caches.
  func usage(downloadURLs: [URL]) async -> StorageUsage {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let containers = ["Documents", "Library", "tmp"].map { home.appendingPathComponent($0) }
    let total = containers.reduce(Int64(0)) { $0 + directorySize(at: $1) }
    var downloads: Int64 = 0
    for url in downloadURLs {
      // Use the same bundle-aware path as `byteSize(of:)`: an HLS `.movpkg` download is a
      // directory, so `attributesOfItem` alone would report only the tiny directory entry.
      downloads += await byteSize(of: url)
    }
    return StorageUsage(
      total: total,
      downloads: downloads,
      imageCache: Int64(ImageCache.shared.diskUsageBytes()),
      epg: EPGServiceImpl.diskUsageBytes())
  }

  /// On-disk size of a single download. An mp4 is a single file; an HLS download is a `.movpkg`
  /// *bundle* (a directory), so `attributesOfItem` returns only the tiny directory entry — we must
  /// sum the contents to report the real size.
  func byteSize(of url: URL) async -> Int64 {
    let fm = FileManager.default
    var isDirectory: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
    guard isDirectory.boolValue else {
      let attrs = try? fm.attributesOfItem(atPath: url.path)
      return (attrs?[.size] as? Int64) ?? 0
    }
    let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey]
    guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
    var total: Int64 = 0
    for case let child as URL in enumerator {
      let values = try? child.resourceValues(forKeys: Set(keys))
      total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0)
    }
    return total
  }

  /// Clears the shared image cache; returns the number of bytes freed (for the confirmation toast).
  func clearImageCache() async -> Int64 {
    let before = Int64(ImageCache.shared.diskUsageBytes())
    ImageCache.shared.clear()
    return before
  }

  /// Clears the EPG cache; returns the number of bytes freed.
  func clearEPGCache() async -> Int64 {
    let before = EPGServiceImpl.diskUsageBytes()
    await epgService.clearCache()
    return before
  }

  private func directorySize(at url: URL) -> Int64 {
    guard
      let enumerator = FileManager.default.enumerator(
        at: url,
        includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else { return 0 }
    var bytes: Int64 = 0
    for case let fileURL as URL in enumerator {
      let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      if values?.isRegularFile == true { bytes += Int64(values?.fileSize ?? 0) }
    }
    return bytes
  }
}

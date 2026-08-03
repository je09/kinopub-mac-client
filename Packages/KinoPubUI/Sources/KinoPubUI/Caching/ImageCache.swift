//
//  ImageCache.swift
//
//
//  A lightweight two-tier (memory + disk) image cache with a time-based expiry.
//  Disk entries older than `ttl` are treated as stale and purged; the whole cache
//  can be cleared on demand (e.g. from Settings).
//

import Foundation
import CryptoKit

import AppKit
public typealias KinoPlatformImage = NSImage

public final class ImageCache: @unchecked Sendable {

  /// Shared instance. Default time-to-live is ~6 months.
  public static let shared = ImageCache(ttl: 60 * 60 * 24 * 182)

  private let memory = NSCache<NSString, KinoPlatformImage>()
  /// Short-lived negative cache for permanent-looking HTTP failures (not transport errors). Without
  /// it, every appearance of the same missing actor/avatar image repeats the same 403 request.
  private let negativeResponses = NSCache<NSString, NSDate>()
  private let fileManager = FileManager.default
  private let directory: URL
  private let ttl: TimeInterval
  private let maxDiskBytes = 512 * 1024 * 1024
  private let ioQueue = DispatchQueue(label: "com.kinopub.imagecache.io", qos: .utility)
  private let inFlightLock = NSLock()
  private var inFlight: [String: [CheckedContinuation<KinoPlatformImage?, Never>]] = [:]

  public init(ttl: TimeInterval) {
    self.ttl = ttl
    let caches = (try? fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    directory = caches.appendingPathComponent("KinoPubImageCache", isDirectory: true)
    try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    memory.countLimit = 300
  }

  // MARK: - Keys

  private func key(for url: URL) -> String {
    let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private func fileURL(for url: URL) -> URL {
    directory.appendingPathComponent(key(for: url))
  }

  // MARK: - Reads

  /// Synchronous memory-only lookup (cheap; safe to call during view updates).
  public func cachedImage(for url: URL) -> KinoPlatformImage? {
    memory.object(forKey: key(for: url) as NSString)
  }

  /// Returns a fresh image from memory, disk (if not expired), or the network. Disk work runs on a
  /// utility queue and concurrent requests for the same URL share one load/download.
  public func image(for url: URL) async -> KinoPlatformImage? {
    let cacheKey = key(for: url)
    let nsKey = cacheKey as NSString
    if let image = memory.object(forKey: nsKey) { return image }
    if let expiry = negativeResponses.object(forKey: nsKey) {
      if expiry.timeIntervalSinceNow > 0 { return nil }
      negativeResponses.removeObject(forKey: nsKey)
    }

    return await withCheckedContinuation { continuation in
      let shouldStart = inFlightLock.withLock {
        if inFlight[cacheKey] != nil {
          inFlight[cacheKey]?.append(continuation)
          return false
        }
        inFlight[cacheKey] = [continuation]
        return true
      }
      guard shouldStart else { return }

      Task.detached(priority: .utility) { [weak self] in
        guard let self else { continuation.resume(returning: nil); return }
        let result = await self.loadImage(for: url, cacheKey: cacheKey)
        let waiters = self.inFlightLock.withLock {
          self.inFlight.removeValue(forKey: cacheKey) ?? []
        }
        waiters.forEach { $0.resume(returning: result) }
      }
    }
  }

  private func loadImage(for url: URL, cacheKey: String) async -> KinoPlatformImage? {
    let nsKey = cacheKey as NSString
    let file = fileURL(for: url)
    if let image: KinoPlatformImage = ioQueue.sync(execute: {
      guard let attrs = try? fileManager.attributesOfItem(atPath: file.path),
            let modified = attrs[.modificationDate] as? Date else { return nil }
      guard Date().timeIntervalSince(modified) < ttl else {
        try? fileManager.removeItem(at: file)
        return nil
      }
      guard let data = try? Data(contentsOf: file) else { return nil }
      return KinoPlatformImage(data: data)
    }) {
      memory.setObject(image, forKey: nsKey)
      return image
    }

    // Reject non-2xx responses (e.g. the actor portrait CDN returns 403 for a missing photo). Cache
    // that miss for a day so repeated cards do not keep asking for a resource known to be absent.
    guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      negativeResponses.setObject(NSDate(timeIntervalSinceNow: 86_400), forKey: nsKey)
      return nil
    }
    guard let image = KinoPlatformImage(data: data) else { return nil }
    memory.setObject(image, forKey: nsKey)
    ioQueue.sync { try? data.write(to: file, options: .atomic) }
    return image
  }

  // MARK: - Maintenance

  /// Removes every cached entry (memory + disk).
  public func clear() {
    memory.removeAllObjects()
    negativeResponses.removeAllObjects()
    ioQueue.sync {
      if let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
        for item in items { try? fileManager.removeItem(at: item) }
      }
    }
  }

  /// Runs the full disk scan at most weekly. Individual reads already evict stale entries, so doing
  /// this scan on every launch only blocks the serial disk queue—and makes cached Home images appear
  /// to load slowly—without improving correctness.
  public func purgeExpiredIfNeeded(minimumInterval: TimeInterval = 7 * 24 * 60 * 60) {
    let key = "KinoPubImageCacheLastMaintenance"
    let defaults = UserDefaults.standard
    let lastRun = defaults.object(forKey: key) as? Date ?? .distantPast
    guard Date().timeIntervalSince(lastRun) >= minimumInterval else { return }
    defaults.set(Date(), forKey: key)
    purgeExpired()
  }

  /// Drops disk entries older than `ttl` and enforces the disk-size cap.
  public func purgeExpired() {
    ioQueue.async { [self] in
      guard let items = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
      ) else { return }
      let now = Date()
      var fresh: [(url: URL, date: Date, size: Int)] = []
      for item in items {
        let values = try? item.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let date = values?.contentModificationDate else { continue }
        if now.timeIntervalSince(date) >= ttl {
          try? fileManager.removeItem(at: item)
        } else {
          fresh.append((item, date, values?.fileSize ?? 0))
        }
      }
      var total = fresh.reduce(0) { $0 + $1.size }
      for entry in fresh.sorted(by: { $0.date < $1.date }) where total > maxDiskBytes {
        try? fileManager.removeItem(at: entry.url)
        total -= entry.size
      }
    }
  }

  /// Total size of the on-disk cache in bytes.
  public func diskUsageBytes() -> Int {
    ioQueue.sync {
      guard let items = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.fileSizeKey]
      ) else { return 0 }
      return items.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
  }

  /// Human-readable on-disk cache size (e.g. "12.4 MB").
  public func formattedDiskUsage() -> String {
    ByteCountFormatter.string(fromByteCount: Int64(diskUsageBytes()), countStyle: .file)
  }
}

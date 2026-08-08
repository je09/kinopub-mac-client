//
//  WatchProgressSync.swift
//  KinoPubAppleClient
//
//  Actor that owns watch-mark reporting (see plans/refactor.md Phase 6): one serial, coalescing
//  queue per media identity so a delayed periodic tick can never move an item backwards, plus the
//  local resume-point recording. Marks are idempotent server-side (identity + monotonic time), so
//  a failed send is logged and the next tick re-queues the latest position rather than retrying
//  stale values.
//

import Foundation
import KinoPubBackend
import OSLog
import KinoPubLogging

actor WatchProgressSync {
  /// A snapshot of the media identity at enqueue time, so an episode switch can never make an old
  /// tick report the wrong item (the original out-of-order bug this queue was built to fix).
  private struct PendingWatchMark {
    let id: Int
    let video: Int?
    let season: Int?
    var time: Int

    func matches(_ other: PendingWatchMark) -> Bool {
      id == other.id && video == other.video && season == other.season
    }
  }

  private let actionsService: UserActionsService
  private let localProgressStore: LocalWatchProgressStore

  private var watchMarkQueue: [PendingWatchMark] = []
  private var latestWatchMarkTimes: [String: Int] = [:]
  private var worker: Task<Void, Never>?

  init(actionsService: UserActionsService, localProgressStore: LocalWatchProgressStore) {
    self.actionsService = actionsService
    self.localProgressStore = localProgressStore
  }

  /// Stop the worker and drop queued marks (player teardown).
  func cancel() {
    worker?.cancel()
    worker = nil
    watchMarkQueue.removeAll()
  }

  /// Periodic tick: persist a local resume point AND queue the remote mark (media only — callers
  /// route trailers through `enqueueMark`).
  func recordProgress(mediaId: Int, position: Double, duration: Double, season: Int?, episode: Int?) {
    localProgressStore.recordProgress(
      mediaId: mediaId,
      position: position,
      duration: duration,
      season: season,
      episode: episode)
    enqueueWatchMark(.init(id: mediaId, video: episode, season: season, time: Int(position)))
  }

  /// Reaching the end marks the title watched: kino.pub derives watched status from the position
  /// reported via `marktime` (there is no separate "set watched" call), so one final mark at the
  /// full duration pushes it over the threshold server-side, and the local resume point is cleared
  /// so Continue Watching drops it immediately (Netflix-style).
  func markFinished(mediaId: Int, season: Int?, episode: Int?, duration: Double) {
    guard duration.isFinite, duration > 0 else { return }
    localProgressStore.clear(id: mediaId)
    enqueueWatchMark(.init(id: mediaId, video: episode, season: season, time: Int(duration)))
  }

  /// Queue a remote mark without touching local progress (trailer-mode ticks).
  func enqueueMark(id: Int, video: Int?, season: Int?, time: Int) {
    enqueueWatchMark(.init(id: id, video: video, season: season, time: time))
  }

  // MARK: - Queue

  private func enqueueWatchMark(_ mark: PendingWatchMark) {
    let key = "\(mark.id)|\(mark.season.map(String.init) ?? "-")|\(mark.video.map(String.init) ?? "-")"
    // Never let a delayed/older periodic callback move this media backwards.
    guard mark.time > (latestWatchMarkTimes[key] ?? -1) else { return }
    latestWatchMarkTimes[key] = mark.time
    if let index = watchMarkQueue.lastIndex(where: { $0.matches(mark) }) {
      // Coalesce repeated toggles for the same identity into the newest position.
      watchMarkQueue[index].time = max(watchMarkQueue[index].time, mark.time)
    } else {
      watchMarkQueue.append(mark)
    }
    guard worker == nil else { return }
    startWorker()
  }

  private func startWorker() {
    worker = Task(priority: .utility) { [weak self] in
      await self?.drainQueue()
    }
  }

  /// Send one mark at a time: independent detached requests can complete out of order, and an
  /// old tick used to read the current item after an episode switch.
  private func drainQueue() async {
    while !Task.isCancelled, !watchMarkQueue.isEmpty {
      let next = watchMarkQueue.removeFirst()
      do {
        try await actionsService.markWatch(
          id: next.id,
          time: next.time,
          video: next.video,
          season: next.season)
      } catch is CancellationError {
        break
      } catch {
        Logger.app.error("Failed to save watch mark: \(error)")
      }
    }
    worker = nil
    // Marks enqueued while the final drain step ran must not be stranded without a worker.
    if !Task.isCancelled, !watchMarkQueue.isEmpty {
      startWorker()
    }
  }
}

//
//  AppDependencies.swift
//  KinoPubAppleClient
//
//  Immutable composition root for the app. Every service is created here once (in
//  `AppDependencies.make()`), injected into the view tree via `\.dependencies`, and consumed by
//  feature models through required initializer parameters. There is deliberately no `shared`
//  singleton and no live `EnvironmentKey` default: a missing injection fails loudly instead of
//  silently starting production behavior in a preview or test.
//
//  Dependency lifecycle (see plans/refactor.md Phase 3):
//   - App: `AppDependencies` itself, `LibraryRepository`/`LibraryViewState`, `DownloadManager`, session caches.
//   - Session: `AuthState`, `AccessTokenService`, account-scoped caches.
//   - Feature: each feature model/store, owned by its screen (`@StateObject`) or the sidebar cache.
//   - Transient: views and presentation-only helpers.
//

import Foundation
import SwiftUI
import KinoPubBackend
import KinoPubData
import KinoPubDomain
import KinoPubKit

// MARK: - Environment key

private struct AppDependenciesKey: EnvironmentKey {
  // No LIVE default: the fallback is an in-memory preview fixture, never the production
  // composition root, so a missing injection can never silently start production services or
  // make a production network request. (SwiftUI materializes this value during window setup,
  // before per-view `.environment()` modifiers apply, so the fallback must be a real value.)
  // Every real app view is under `.environment(\.dependencies, AppDependencies.make())`.
  static let defaultValue: AppDependencies = AppDependencies.preview()
}

extension EnvironmentValues {
  var dependencies: AppDependencies {
    get { self[AppDependenciesKey.self] }
    set { self[AppDependenciesKey.self] = newValue }
  }
}

// MARK: - AppDependencies

struct AppDependencies {
  let configuration: Configuration
  let authService: AuthorizationService
  let contentService: VideoContentService
  let epgService: EPGService
  let collectionsService: CollectionsService
  let deviceService: DeviceService
  let accessTokenService: AccessTokenService
  let userService: UserService
  let keychainStorage: KeychainStorage
  let fileSaver: FileSaving
  let downloadManager: DownloadManager<DownloadMeta>
  let downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>
  let downloadNotificationManager: DownloadNotificationManager
  let seasonDownloadManager: SeasonDownloadManager
  let actionsService: UserActionsService
  let localProgressStore: LocalWatchProgressStore
  let libraryState: LibraryViewState
  let storageUsageRepository: StorageUsageRepository
  let commentsRepository: any CommentsRepository
  let searchRepository: any SearchRepository

  // MARK: - Production factory

  static func make() -> AppDependencies {
    let configuration = BundleConfiguration()
    let keychainStorage = KeychainStorageImpl()
    let accessTokenService = AccessTokenServiceImpl(storage: keychainStorage)

    // Downloads

    let fileSaver = FileSaver()
    let downloadedFilesDatabase = DownloadedFilesDatabase<DownloadMeta>(fileSaver: fileSaver)
    let downloadsControlDatabase = DownloadsControlDatabase<DownloadMeta>(fileSaver: fileSaver)
    let downloadManager = DownloadManager<DownloadMeta>(
      fileSaver: fileSaver,
      database: downloadedFilesDatabase,
      controlDatabase: downloadsControlDatabase)
    let downloadNotificationManager = DownloadNotificationManager()
    let seasonDownloadManager = SeasonDownloadManager(
      downloadManager: downloadManager,
      notifications: downloadNotificationManager)
    // Post a local notification when a download finishes/fails. Episodes that belong to a bulk
    // season download are folded into a single "season downloaded" notification instead.
    downloadManager.onDownloadFinished = { [weak seasonDownloadManager, weak downloadNotificationManager] url, meta in
      let handledBySeason = seasonDownloadManager?.handleFinished(url: url) ?? false
      if !handledBySeason {
        downloadNotificationManager?.notifyFinished(title: meta.notificationTitle, identifier: "\(meta.id)")
      }
    }
    downloadManager.onDownloadFailed = { [weak downloadNotificationManager] _, meta, _ in
      downloadNotificationManager?.notifyFailed(title: meta.notificationTitle, identifier: "\(meta.id)")
    }
    // API client. Token refresh uses a separate unauthenticated transport to avoid replay loops;
    // both startup refresh and 401 recovery share the same single-flight refresher.
    let credentialRefresher = AccessTokenCredentialRefresher(
      baseURL: configuration.baseURL,
      configuration: configuration,
      accessTokenService: accessTokenService)
    let apiClient = makeApiClient(
      with: configuration.baseURL,
      accessTokenService: accessTokenService,
      credentialRefresher: credentialRefresher)
    let actionsService = UserActionsServiceImpl(apiClient: apiClient)

    // Single client-side library state: optimistic bookmarks/watchlist/watched + cached bookmark
    // folders + audio-track prefs — one source of truth behind the typed command API. Download
    // status and watch progress stay separate sources joined into the view state's read model.
    let localProgressStore = LocalWatchProgressStore()
    let libraryRepository = LibraryRepository(actionsService: actionsService)
    let libraryDownloadStatus = LibraryDownloadStatusAdapter(
      downloadManager: downloadManager,
      downloadedFilesDatabase: downloadedFilesDatabase)
    // App bootstrap runs on the main thread (App.init / previews / window setup), which is where
    // the @MainActor UI projection must be built.
    let libraryState = MainActor.assumeIsolated {
      LibraryViewState(
        repository: libraryRepository,
        downloadStatus: libraryDownloadStatus)
    }

    let authService = AuthorizationServiceImpl(
      apiClient: apiClient,
      configuration: configuration,
      accessTokenService: accessTokenService,
      credentialRefresher: credentialRefresher)
    let epgService = EPGServiceImpl()
    return AppDependencies(
      configuration: configuration,
      authService: authService,
      contentService: VideoContentServiceImpl(apiClient: apiClient),
      epgService: epgService,
      collectionsService: CollectionsServiceImpl(apiClient: apiClient),
      deviceService: DeviceServiceImpl(apiClient: apiClient),
      accessTokenService: accessTokenService,
      userService: UserServiceImpl(apiClient: apiClient),
      keychainStorage: keychainStorage,
      fileSaver: fileSaver,
      downloadManager: downloadManager,
      downloadedFilesDatabase: downloadedFilesDatabase,
      downloadNotificationManager: downloadNotificationManager,
      seasonDownloadManager: seasonDownloadManager,
      actionsService: actionsService,
      localProgressStore: localProgressStore,
      libraryState: libraryState,
      storageUsageRepository: StorageUsageRepository(epgService: epgService),
      commentsRepository: CommentsRepositoryAdapter(client: apiClient),
      searchRepository: SearchRepositoryAdapter(client: apiClient))
  }

  // MARK: - Preview fixture factory

  /// In-memory dependency set for previews and feature tests. Never performs a production network
  /// request: services are mocks and persisted stores are backed by the temporary directory.
  static func preview() -> AppDependencies {
    let configuration = BundleConfiguration()
    let fileSaver = PreviewFileSaver()
    let downloadedFilesDatabase = DownloadedFilesDatabase<DownloadMeta>(fileSaver: fileSaver)
    let downloadManager = DownloadManager<DownloadMeta>(
      fileSaver: fileSaver,
      database: downloadedFilesDatabase)
    let downloadNotificationManager = DownloadNotificationManager()
    let seasonDownloadManager = SeasonDownloadManager(
      downloadManager: downloadManager,
      notifications: downloadNotificationManager)
    let actionsService = UserActionsServiceMock()
    let localProgressStore = LocalWatchProgressStore(fileURL: PreviewURLs.progress)
    let libraryRepository = LibraryRepository(
      actionsService: actionsService,
      fileURL: PreviewURLs.library)
    let libraryDownloadStatus = LibraryDownloadStatusAdapter(
      downloadManager: downloadManager,
      downloadedFilesDatabase: downloadedFilesDatabase)
    // App bootstrap runs on the main thread (App.init / previews / window setup), which is where
    // the @MainActor UI projection must be built.
    let libraryState = MainActor.assumeIsolated {
      LibraryViewState(
        repository: libraryRepository,
        downloadStatus: libraryDownloadStatus)
    }
    return AppDependencies(
      configuration: configuration,
      authService: AuthorizationServiceMock(),
      contentService: VideoContentServiceMock(),
      epgService: EPGServiceMock(),
      collectionsService: CollectionsServiceMock(),
      deviceService: DeviceServiceMock(),
      accessTokenService: AccessTokenServiceMock(),
      userService: UserServiceMock(),
      keychainStorage: PreviewKeychainStorage(),
      fileSaver: fileSaver,
      downloadManager: downloadManager,
      downloadedFilesDatabase: downloadedFilesDatabase,
      downloadNotificationManager: downloadNotificationManager,
      seasonDownloadManager: seasonDownloadManager,
      actionsService: actionsService,
      localProgressStore: localProgressStore,
      libraryState: libraryState,
      storageUsageRepository: StorageUsageRepository(epgService: EPGServiceMock()),
      commentsRepository: PreviewCommentsRepository(),
      searchRepository: SearchRepositoryStub())
  }

  // MARK: - API Client building

  private static func makeApiClient(
    with baseURL: String,
    accessTokenService: AccessTokenService,
    credentialRefresher: any CredentialRefreshing
  ) -> APIClient {
    APIClient(
      baseUrl: baseURL,
      // Never install the cURL/response debug plugins here: they include bearer tokens,
      // OAuth responses, and account data in unified logs.
      plugins: [AccessTokenPlugin(accessTokenService: accessTokenService)],
      cache: ResponseCache(),
      credentialRefresher: credentialRefresher,
      cachePartitionProvider: AccessTokenCachePartitionProvider(accessTokenService: accessTokenService))
  }
}

// MARK: - Preview fixtures (in-memory, no production side effects)

private enum PreviewURLs {
  static let directory: URL = {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("KinoPubPreview-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }()
  static let progress = directory.appendingPathComponent("progress.json")
  static let library = directory.appendingPathComponent("library.json")
}

/// In-memory keychain so previews never touch the real keychain.
private final class PreviewKeychainStorage: KeychainStorage {
  private var storage: [String: Data] = [:]
  private let lock = NSLock()

  func object<Value>(for key: Key<Value>) -> Value? where Value: Codable {
    lock.lock(); defer { lock.unlock() }
    guard let data = storage[key.rawValue] else { return nil }
    return try? JSONDecoder().decode(Value.self, from: data)
  }

  func setObject<Value>(_ object: Value?, for key: Key<Value>) where Value: Codable {
    lock.lock(); defer { lock.unlock() }
    if let object, let data = try? JSONEncoder().encode(object) {
      storage[key.rawValue] = data
    } else {
      storage.removeValue(forKey: key.rawValue)
    }
  }

  func clear() {
    lock.lock(); defer { lock.unlock() }
    storage.removeAll()
  }
}

/// Writes preview persistence into the temporary directory instead of the app container.
private struct PreviewFileSaver: FileSaving {
  func saveFile(from sourceURL: URL, to destinationURL: URL) throws {
    try? FileManager.default.removeItem(at: destinationURL)
    try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
  }

  func removeFile(at sourceURL: URL) throws {
    try FileManager.default.removeItem(at: sourceURL)
  }

  func getDocumentsDirectoryURL(forFilename filename: String) -> URL {
    PreviewURLs.directory.appendingPathComponent(filename)
  }
}

/// Empty comments feed for previews.
private struct PreviewCommentsRepository: CommentsRepository {
  func comments(for mediaID: Int) async throws -> [KinoPubDomain.Comment] { [] }
}

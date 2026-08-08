//
//  AppContext.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 26.07.2023.
//

import Foundation
import SwiftUI
import KinoPubBackend
import KinoPubData
import KinoPubDomain
import KinoPubKit

// MARK: - Env key

private struct AppContextKey: EnvironmentKey {
  static let defaultValue: AppContextProtocol = AppContext.shared
}

extension EnvironmentValues {
  var appContext: AppContextProtocol {
    get { self[AppContextKey.self] }
    set { self[AppContextKey.self] = newValue }
  }
}

// MARK: - AppContextProtocol

protocol CommentsRepositoryProvider {
  var commentsRepository: any CommentsRepository { get }
}

protocol SearchRepositoryProvider {
  var searchRepository: any SearchRepository { get }
}

typealias AppContextProtocol = AuthorizationServiceProvider
& VideoContentServiceProvider
& CollectionsServiceProvider
& DeviceServiceProvider
& ConfigurationProvider
& KeychainStorageProvider
& AccessTokenServiceProvider
& DownloadManagerProvider
& DownloadedFilesDatabaseProvider
& FileSaverProvider
& UserServiceProvider
& UserActionsServiceProvider
& LocalWatchProgressProvider
& MediaLibraryProvider
& EPGServiceProvider
& CommentsRepositoryProvider
& SearchRepositoryProvider

// MARK: - AppContext

struct AppContext: AppContextProtocol {
  
  var configuration: Configuration
  var authService: AuthorizationService
  var contentService: VideoContentService
  var epgService: EPGService
  var collectionsService: CollectionsService
  var deviceService: DeviceService
  var accessTokenService: AccessTokenService
  var userService: UserService
  var keychainStorage: KeychainStorage
  var fileSaver: FileSaving
  var downloadManager: DownloadManager<DownloadMeta>
  var downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>
  var downloadNotificationManager: DownloadNotificationManager
  var seasonDownloadManager: SeasonDownloadManager
  var actionsService: UserActionsService
  var localProgressStore: LocalWatchProgressStore
  var libraryState: MediaLibraryStore
  let commentsRepository: any CommentsRepository
  let searchRepository: any SearchRepository
  
  static let shared: AppContext = {
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
    // folders + audio-track prefs + a façade over downloads and watch progress — one source of truth.
    let localProgressStore = LocalWatchProgressStore()
    let libraryState = MediaLibraryStore(
      downloadManager: downloadManager,
      downloadedFilesDatabase: downloadedFilesDatabase,
      progressStore: localProgressStore,
      actionsService: actionsService)
    
    let authService = AuthorizationServiceImpl(
      apiClient: apiClient,
      configuration: configuration,
      accessTokenService: accessTokenService,
      credentialRefresher: credentialRefresher)
    return AppContext(
      configuration: configuration,
      authService: authService,
      contentService: VideoContentServiceImpl(apiClient: apiClient),
      epgService: EPGServiceImpl(),
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
      commentsRepository: CommentsRepositoryAdapter(client: apiClient),
      searchRepository: SearchRepositoryAdapter(client: apiClient))
  }()
  
  // MARK: - API Client building
  
  private static func makeApiClient(with baseURL: String,
                                    accessTokenService: AccessTokenService,
                                    credentialRefresher: any CredentialRefreshing) -> APIClient {
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

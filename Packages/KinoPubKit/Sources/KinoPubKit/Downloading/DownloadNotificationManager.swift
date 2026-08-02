//
//  DownloadNotificationManager.swift
//  KinoPubKit
//
//  Native macOS notifications for completed and failed downloads.
//

import Foundation
import KinoPubLogging
import OSLog
import UserNotifications

public extension Notification.Name {
  /// Posted when the user opens a download notification.
  static let openDownloads = Notification.Name("com.kinopub.openDownloads")
}

public final class DownloadNotificationManager: NSObject, ObservableObject {
  @Published public private(set) var permissionGranted = false

  private let center = UNUserNotificationCenter.current()

  public override init() {
    super.init()
    center.delegate = self
    refreshPermission()
  }

  @discardableResult
  public func requestPermission() async -> Bool {
    do {
      let granted = try await center.requestAuthorization(options: [.alert, .sound])
      await MainActor.run { self.permissionGranted = granted }
      return granted
    } catch {
      Logger.kit.error("[NOTIFICATIONS] Authorization request failed: \(error)")
      return false
    }
  }

  public func notifyFinished(title: String, identifier: String) {
    post(title: NSLocalizedString("Download complete", comment: ""),
         body: title,
         identifier: "download_done_\(identifier)")
  }

  public func notifyFailed(title: String, identifier: String) {
    post(title: NSLocalizedString("Download failed", comment: ""),
         body: title,
         identifier: "download_failed_\(identifier)")
  }

  public func notifySeasonFinished(title: String, identifier: String) {
    post(title: NSLocalizedString("Season downloaded", comment: ""),
         body: title,
         identifier: "season_done_\(identifier)")
  }

  private func post(title: String, body: String, identifier: String) {
    guard permissionGranted else { return }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { error in
      if let error { Logger.kit.error("[NOTIFICATIONS] Failed to post \(identifier): \(error)") }
    }
  }

  private func refreshPermission() {
    center.getNotificationSettings { [weak self] settings in
      DispatchQueue.main.async {
        self?.permissionGranted = settings.authorizationStatus == .authorized ||
          settings.authorizationStatus == .provisional
      }
    }
  }
}

extension DownloadNotificationManager: UNUserNotificationCenterDelegate {
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    await MainActor.run {
      NotificationCenter.default.post(name: .openDownloads, object: nil)
    }
  }
}

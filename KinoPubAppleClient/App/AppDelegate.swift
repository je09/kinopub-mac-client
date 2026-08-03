//
//  AppDelegate.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 24.07.2023.
//

import AppKit
import KinoPubUI

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    // Let startup image reads win the cache I/O queue. A maintenance scan on every launch used to
    // serialize ahead of them, making an already-cached Home screen look like a cold network load.
    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
      ImageCache.shared.purgeExpiredIfNeeded()
    }
  }

  /// Closing the last window quits the app, including from the activation screen.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

//
//  AuthPlatformActions.swift
//  KinoPubAppleClient
//
//  Platform capabilities the activation screen needs (clipboard + opening a URL), injected so the
//  auth store stays testable and free of AppKit. Production wiring is `.live`; tests inject stubs.
//

import AppKit
import Foundation

struct AuthPlatformActions {
  var copyToClipboard: (String) -> Void
  var openURL: (URL) -> Void

  static let live = AuthPlatformActions(
    copyToClipboard: { text in
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text, forType: .string)
    },
    openURL: { url in
      NSWorkspace.shared.open(url)
    }
  )
}

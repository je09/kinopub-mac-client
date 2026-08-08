//
//  SettingsModel.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 9.08.2023.
//

import Foundation
import KinoPubBackend
import KinoPubLogging
import OSLog

@MainActor
class ProfileModel: ObservableObject {
  
  private var userService: UserService
  private var errorHandler: ErrorHandler
  private var authState: AuthState
  
  @Published public var userData: UserData = UserData.mock()
  @Published var selectedLanguage: String
  /// Caps streaming quality (shared with the player via `StreamQuality.userDefaultsKey`).
  @Published var streamQuality: StreamQuality = .current
  @Published var shouldShowExitAlert: Bool = false
  /// True while the async logout (deregister device → clear session) is in flight, so the UI can
  /// disable the button and show a spinner.
  @Published var isLoggingOut: Bool = false
  /// Flips true once logout finishes, so the presenting Profile modal can dismiss itself.
  @Published var didLogout: Bool = false
  
  let availableLanguages = [
    "en": "English",
    "ru": "Русский",
    "uk": "Українська",
    "be": "Беларуская",
    "kk": "Қазақша",
    "uz": "Oʻzbekcha",
    "hy": "Հայերեն",
    "az": "Azərbaycan",
    "ka": "ქართული",
    "lt": "Lietuvių",
    "lv": "Latviešu",
    "et": "Eesti",
    "ky": "Кыргызча",
    "tg": "Тоҷикӣ",
    "tk": "Türkmençe",
    "ro": "Română",
  ]
  
  init(
    userService: UserService,
    errorHandler: ErrorHandler,
    authState: AuthState
  ) {
    self.userService = userService
    self.errorHandler = errorHandler
    self.authState = authState
    self.selectedLanguage =
    UserDefaults.standard.string(forKey: "selectedLanguage")
    ?? (Locale.current.language.languageCode?.identifier ?? "en")
  }
  func fetch() {
    Task {
      do {
        self.userData = try await userService.fetchUserData()
      } catch {
        errorHandler.setError(error)
      }
    }
  }
  
  func logout() {
    guard !isLoggingOut else { return }
    isLoggingOut = true
    Task {
      await authState.logout()
      isLoggingOut = false
      didLogout = true
    }
  }
  
  func changeLanguage(to language: String) {
    selectedLanguage = language
    UserDefaults.standard.set(language, forKey: "selectedLanguage")
    UserDefaults.standard.setValue([language], forKey: "AppleLanguages")
    UserDefaults.standard.synchronize()
    shouldShowExitAlert = true
  }

  /// Caps streaming quality and persists it for the player (same key as `PlayerManager`).
  func setStreamQuality(_ quality: StreamQuality) {
    streamQuality = quality
    UserDefaults.standard.set(quality.rawValue, forKey: StreamQuality.userDefaultsKey)
  }
}

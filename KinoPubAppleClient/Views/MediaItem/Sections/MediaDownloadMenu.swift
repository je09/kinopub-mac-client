//
//  MediaDownloadMenu.swift
//  KinoPubAppleClient
//
//  Download menu content (Season ▸ Episode ▸ Quality) for the media detail hero. Placed inside the
//  hero's `Menu` as its content; render-only, all intents go to `MediaItemModel`.
//

import SwiftUI
import KinoPubBackend
import KinoPubUI

/// Menu content used by the hero's download button: per-season episode lists with per-quality
/// choices, plus the "download whole season" shortcut.
struct MediaDownloadMenu: View {
  @ObservedObject var model: MediaItemModel
  @EnvironmentObject private var libraryState: LibraryViewState

  private var mediaItem: MediaItem { model.mediaItem }

  @ViewBuilder
  var body: some View {
    if mediaItem.isSeries, let seasons = mediaItem.seasons, !seasons.isEmpty {
      ForEach(seasons, id: \.number) { season in
        Menu("\("Season".localized) \(season.number)") {
          seasonDownloadMenu(for: season)
          ForEach(season.episodes, id: \.id) { episode in
            episodeDownloadSubmenu(episode, in: season)
          }
        }
      }
    } else {
      switch libraryState.downloadStatus(itemId: mediaItem.id, video: nil, season: nil) {
      case .downloaded:
        Button {
        } label: {
          Label("Downloaded".localized, systemImage: "checkmark.circle.fill")
        }
        .disabled(true)
      case .downloading:
        Button {
        } label: {
          Label("Downloading…".localized, systemImage: "arrow.down.circle")
        }
        .disabled(true)
      case .none:
        qualityButtons(for: movieDownloadable)
      }
    }
  }

  /// Per-episode entry in the season download menu. Shows the episode name (not just "S1E1") and
  /// disables itself when that episode is already downloaded or downloading.
  @ViewBuilder
  private func episodeDownloadSubmenu(_ episode: Episode, in season: Season) -> some View {
    let title = episodeMenuTitle(episode, in: season)
    switch libraryState.downloadStatus(itemId: mediaItem.id, video: episode.number, season: season.number) {
    case .downloaded:
      Button {
      } label: {
        Label(title, systemImage: "checkmark.circle.fill")
      }.disabled(true)
    case .downloading:
      Button {
      } label: {
        Label(title, systemImage: "arrow.down.circle")
      }.disabled(true)
    case .none:
      Menu(title) { qualityButtons(for: episodeDownloadable(episode, in: season)) }
    }
  }

  /// "S1E1 · Episode name" (or just "S1E1" when the episode has no distinct title).
  private func episodeMenuTitle(_ episode: Episode, in season: Season) -> String {
    let code = "S\(season.number)E\(episode.number)"
    let name = episode.title.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? code : "\(code) · \(name)"
  }

  /// "Download whole season" entry: one tap per quality (plus a best-available option) that queues
  /// every episode of the season at once.
  @ViewBuilder
  private func seasonDownloadMenu(for season: Season) -> some View {
    let qualities = SeasonDownloadManager.availableQualities(in: season)
    Menu {
      Button("Best quality".localized) {
        model.downloadSeason(season, quality: nil)
      }
      ForEach(qualities, id: \.self) { quality in
        Button(quality) {
          model.downloadSeason(season, quality: quality)
        }
      }
    } label: {
      Label("Download whole season".localized, systemImage: "square.and.arrow.down.on.square")
    }
  }

  private var movieDownloadable: DownloadableMediaItem {
    DownloadableMediaItem(
      name: mediaItem.title,
      files: mediaItem.files,
      mediaItem: mediaItem,
      watchingMetadata: WatchingMetadata(id: mediaItem.id, video: nil, season: nil))
  }

  private func episodeDownloadable(_ episode: Episode, in season: Season) -> DownloadableMediaItem {
    DownloadableMediaItem(
      name: "S\(season.number)E\(episode.number)",
      files: episode.files,
      mediaItem: mediaItem,
      watchingMetadata: WatchingMetadata(id: episode.id, video: episode.number, season: season.number))
  }

  @ViewBuilder
  private func qualityButtons(for item: DownloadableMediaItem) -> some View {
    ForEach(item.files.dedupedByQuality) { file in
      Button(file.quality) {
        model.startDownload(item: item, file: file)
      }
    }
  }

  /// Download entry in an episode's context menu. Once an episode is downloaded (or downloading) we
  /// show a disabled status row instead of the quality picker, so it can't be queued twice.
  @ViewBuilder
  private func episodeDownloadMenu(_ episode: Episode, in season: Season) -> some View {
    switch libraryState.downloadStatus(itemId: mediaItem.id, video: episode.number, season: season.number) {
    case .downloaded:
      Button {
      } label: {
        Label("Downloaded".localized, systemImage: "checkmark.circle.fill")
      }
      .disabled(true)
    case .downloading:
      Button {
      } label: {
        Label("Downloading…".localized, systemImage: "arrow.down.circle")
      }
      .disabled(true)
    case .none:
      Menu {
        qualityButtons(for: episodeDownloadable(episode, in: season))
      } label: {
        Label("Download".localized, systemImage: "arrow.down.circle")
      }
    }
  }

  /// Long-press preview for an episode card — the card on a padded background so its rounded corners
  /// (and the text under the thumbnail) aren't clipped by the context-menu lift.
  func episodePreview(_ episode: Episode, in season: Season, progress: Double?) -> some View {
    EpisodeCard(
      imageURL: episode.thumbnail,
      overline: "\("Episode".localized) \(episode.number)",
      title: episode.fixedTitle,
      footnote: "\(max(episode.duration / 60, 1)) мин",
      progress: progress
    )
    .padding(14)
    .background(Color.KinoPub.background)
  }

  /// Context-menu download entry for an episode card.
  @ViewBuilder
  func downloadMenu(for episode: Episode, in season: Season) -> some View {
    episodeDownloadMenu(episode, in: season)
  }
}

/// Small badge on an episode card showing whether it's downloaded or downloading.
struct MediaDownloadBadge: View {
  @ObservedObject var libraryState: LibraryViewState
  let itemId: Int
  let video: Int?
  let season: Int?

  var body: some View {
    switch libraryState.downloadStatus(itemId: itemId, video: video, season: season) {
    case .downloaded:
      Image(systemName: "arrow.down.circle.fill")
        .font(.system(size: 18))
        .foregroundStyle(.white, Color.accentColor)
        .padding(8)
    case .downloading:
      ProgressView()
        .controlSize(.small)
        .padding(8)
    case .none:
      EmptyView()
    }
  }
}

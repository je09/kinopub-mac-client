//
//  MediaEpisodesSection.swift
//  KinoPubAppleClient
//
//  Season picker + horizontal episode shelf for series detail pages. Render-only; watched/download
//  intents go through `MediaItemModel` and the shared library state.
//

import SwiftUI
import KinoPubBackend
import KinoPubUI

/// Season picker + episode cards for a series. Owns only the selected-season local state.
struct MediaEpisodesSection: View {
  @ObservedObject var model: MediaItemModel
  @EnvironmentObject private var libraryState: LibraryViewState
  @State private var selectedSeasonNumber: Int?

  private var mediaItem: MediaItem { model.mediaItem }

  @ViewBuilder
  var body: some View {
    if mediaItem.isSeries, let seasons = mediaItem.seasons, !seasons.isEmpty {
      let season = currentSeason(in: seasons)
      VStack(alignment: .leading, spacing: 12) {
        seasonPicker(seasons: seasons, current: season)
        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 14) {
              ForEach(season.episodes, id: \.id) { episode in
                NavigationLink(
                  value: model.linkProvider.episodePlayer(
                    for: filledEpisode(episode, in: season),
                    queue: episodeQueue)
                ) {
                  EpisodeCard(
                    imageURL: episode.thumbnail,
                    overline: "\("Episode".localized) \(episode.number)",
                    title: episode.fixedTitle,
                    footnote: "\(max(episode.duration / 60, 1)) мин",
                    progress: episodeProgress(episode, in: season)
                  )
                  .overlay(alignment: .topTrailing) {
                    if model.isEpisodeWatched(episode) {
                      // Neutral "watched" eye (not the loud accent checkmark).
                      Image(systemName: "eye.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .padding(8)
                    }
                  }
                  .overlay(alignment: .bottomTrailing) {
                    // Downloads are keyed on the series id (DownloadMeta.id == mediaItem.id), not the
                    // episode id — so the badge must query the series id to actually match.
                    MediaDownloadBadge(
                      libraryState: libraryState,
                      itemId: mediaItem.id,
                      video: episode.number,
                      season: season.number)
                  }
                }
                .buttonStyle(.plain)
                .id(episode.id)
                .contextMenu {
                  Button {
                    model.toggleEpisodeWatched(episode: episode, season: season.number)
                  } label: {
                    let watched = model.isEpisodeWatched(episode)
                    Label(
                      watched ? "Mark as Unwatched".localized : "Mark as Watched".localized,
                      systemImage: watched ? "eye.fill" : "eye")
                  }
                  MediaDownloadMenu(model: model).downloadMenu(for: episode, in: season)
                } preview: {
                  // Custom preview: the default lift clips the card's rounded bottom corners (over the
                  // text). Render the card on its own padded platter so nothing is cut off.
                  MediaDownloadMenu(model: model)
                    .episodePreview(episode, in: season, progress: episodeProgress(episode, in: season))
                }
              }
            }
            .padding(.horizontal, 20)
          }
          // Once the real item loads, jump to the last episode the user watched.
          .onChange(of: model.itemLoaded) { loaded in
            if loaded { scrollToResume(proxy: proxy, seasons: seasons) }
          }
          .onAppear {
            if model.itemLoaded { scrollToResume(proxy: proxy, seasons: seasons) }
          }
        }
      }
    }
  }

  /// The most recently watched (or in-progress) episode across all seasons.
  private func lastWatchedEpisode(in seasons: [Season]) -> (season: Season, episode: Episode)? {
    var best: (season: Season, episode: Episode)?
    for season in seasons {
      for episode in season.episodes where episode.watched > 0 || episode.watching.time > 0 {
        if let current = best {
          if (season.number, episode.number) > (current.season.number, current.episode.number) {
            best = (season, episode)
          }
        } else {
          best = (season, episode)
        }
      }
    }
    return best
  }

  /// Default to the season holding the last watched episode; fall back to the first season.
  private func currentSeason(in seasons: [Season]) -> Season {
    if let number = selectedSeasonNumber, let match = seasons.first(where: { $0.number == number }) {
      return match
    }
    return lastWatchedEpisode(in: seasons)?.season ?? seasons[0]
  }

  private func scrollToResume(proxy: ScrollViewProxy, seasons: [Season]) {
    // Only auto-scroll while showing the auto-selected season (don't fight manual season changes).
    guard selectedSeasonNumber == nil,
          let target = lastWatchedEpisode(in: seasons),
          target.season.number == currentSeason(in: seasons).number
    else { return }
    withAnimation {
      // Center the current episode horizontally so it's the focus when the series page opens.
      proxy.scrollTo(target.episode.id, anchor: .center)
    }
  }

  @ViewBuilder
  private func seasonPicker(seasons: [Season], current: Season) -> some View {
    if seasons.count > 1 {
      Menu {
        ForEach(seasons) { season in
          Button {
            selectedSeasonNumber = season.number
          } label: {
            if season.number == current.number {
              Label(season.fixedTitle, systemImage: "checkmark")
            } else {
              Text(season.fixedTitle)
            }
          }
        }
      } label: {
        HStack(spacing: 6) {
          Text(current.fixedTitle)
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(Color.KinoPub.text)
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(Color.KinoPub.subtitle)
        }
      }
      .padding(.horizontal, 20)
    } else {
      Text(current.fixedTitle)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(Color.KinoPub.text)
        .padding(.horizontal, 20)
    }
  }

  private func filledEpisode(_ episode: Episode, in season: Season) -> Episode {
    episode.seasonNumber = season.number
    episode.mediaId = season.mediaId ?? mediaItem.id
    episode.mediaTitle = mediaItem.localizedTitle
    return episode
  }

  private var episodeQueue: [Episode] {
    mediaItem.orderedEpisodes.map { filledEpisode($0.episode, in: $0.season) }
  }

  private func episodeProgress(_ episode: Episode, in season: Season) -> Double? {
    if model.isEpisodeWatched(episode) { return 1.0 }
    let serverProgress = episode.watching.time > 0 ? episode.watchProgress.fraction : nil
    // Overlay the local resume point so a just-watched episode shows progress instantly.
    let localProgress = model.localProgressFraction(season: season.number, episode: episode.number)
    guard let best = [serverProgress, localProgress].compactMap({ $0 }).max() else { return nil }
    return min(max(best, 0.02), 1.0)
  }
}

//
//  MediaHeroSection.swift
//  KinoPubAppleClient
//
//  Hero block of the media detail page: backdrop, title, plot, badges, ratings, vote pills and the
//  primary/secondary action buttons. Render-only: all behavior goes through `MediaItemModel`.
//

import SwiftUI
import KinoPubBackend
import KinoPubUI

/// Hero + action row. The download menu's content lives in `MediaDownloadMenu`.
struct MediaHeroSection: View {
  @ObservedObject var model: MediaItemModel
  @EnvironmentObject private var libraryState: LibraryViewState
  @Binding var plotExpanded: Bool
  @Binding var showCreateFolder: Bool
  @Binding var newFolderName: String
  let usesSidebar: Bool

  private var mediaItem: MediaItem { model.mediaItem }
  private var isSkeleton: Bool { !model.itemLoaded }

  private let heroHeight: CGFloat = 552

  var body: some View {
    HeroBackdrop(
      imageURL: nil,
      height: heroHeight,
      tallBlur: true,
      blurReduction: 50,
      bottomScrim: false,
      transparentBase: true
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Text(mediaItem.localizedTitle)
          .font(.system(size: 34, weight: .bold))
          .foregroundStyle(.white)
          .skeleton(enabled: isSkeleton, size: CGSize(width: 240, height: 36))

        Text(genreLine)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.white)
          .skeleton(enabled: isSkeleton, size: CGSize(width: 180, height: 16))

        if !mediaItem.plot.isEmpty {
          VStack(alignment: .leading, spacing: 4) {
            Text(mediaItem.plot)
              .font(.system(size: 14))
              .foregroundStyle(.white.opacity(0.95))
              .lineLimit(plotExpanded ? nil : 2)
              .multilineTextAlignment(.leading)
            Button(plotExpanded ? "Свернуть" : "ЕЩЕ") {
              withAnimation { plotExpanded.toggle() }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
          }
        }

        MetadataRow(items: heroBadges, textColor: .white.opacity(0.82))

        // kino.pub / КП / IMDb badges in the hero (no background pill here).
        // Ratings + the user's like/dislike, side by side — wraps to two rows on narrow screens.
        let ratings = ContentItemRatingView(
          imdbScore: mediaItem.imdbRating,
          kinopoiskScore: mediaItem.kinopoiskRating,
          kinopubScore: mediaItem.ratingPercentage > 0 ? mediaItem.ratingPercentage / 10.0 : nil,
          showsBackground: false)
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) {
            ratings; voteControl
          }
          VStack(alignment: .leading, spacing: 8) {
            ratings; voteControl
          }
        }

        heroActions
          .padding(.top, 6)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var genreLine: String {
    let typeTitle = (MediaType(rawValue: mediaItem.type)?.title) ?? ""
    var parts: [String] = []
    if !typeTitle.isEmpty { parts.append(typeTitle) }
    parts.append(contentsOf: mediaItem.genres.compactMap { $0.title })
    return parts.joined(separator: " · ")
  }

  private var heroBadges: [MetadataRow.Item] {
    var items: [MetadataRow.Item] = []
    if mediaItem.year > 0 {
      items.append(.init(text: "\(mediaItem.year)", isBadge: false))
    }
    // Year + country in the hero for both movies and series.
    if let country = mediaItem.countries.first?.title, !country.isEmpty {
      items.append(.init(text: country, isBadge: false))
    }
    // Movies also show their runtime in the hero; for series the durations live in the info block.
    if !mediaItem.isSeries {
      let duration = mediaItem.duration.totalFormatted
      if !duration.isEmpty {
        items.append(.init(text: duration, isBadge: false))
      }
    }
    if let quality = qualityBadgeText {
      items.append(.init(text: quality, isBadge: true))
    }
    if let ac3 = mediaItem.ac3, ac3 > 0 {
      items.append(.init(text: "AC3", isBadge: true))
    }
    return items
  }

  /// Best-effort quality badge. `quality` carries the max vertical resolution
  /// (e.g. 2160, 1080). We only show a badge when the value is meaningful.
  private var qualityBadgeText: String? {
    switch mediaItem.quality {
    case let q where q >= 2160: return "4K"
    case let q where q >= 720: return "HD"
    default: return nil
    }
  }

  // MARK: - Hero actions

  @ViewBuilder
  private var heroActions: some View {
    if usesSidebar {
      // Wide Mac window: everything on one row.
      HStack(spacing: 12) {
        playButton
        secondaryActions
      }
    } else {
      // Narrow Mac window: the play button gets a full-width row; circle actions sit below.
      VStack(spacing: 14) {
        playButton
        HStack(spacing: 12) {
          secondaryActions
          Spacer(minLength: 0)
        }
      }
    }
  }

  @ViewBuilder
  private var secondaryActions: some View {
    // Watchlist ("Буду смотреть") is a serials-only feature on kino.pub; for movies use Bookmarks.
    if mediaItem.isSeries {
      watchlistButton
    } else {
      // Whole-item "watched" applies to movies; series are marked per-episode (long-press).
      watchedButton
    }
    bookmarkMenu
    downloadButton
    if FeatureFlags.threeDEnabled, mediaItem.type.lowercased() == "3d" {
      threeDModeButton
    }
    // Trailer button removed from the hero — the Trailers shelf below already exposes it.
    // Like/dislike moved next to the ratings (see `voteControl`).
  }

  /// 3D view-mode picker for 3D titles (Side-by-Side / Over-Under × 2D / Anaglyph). Writes the
  /// shared preference the player reads — on a flat screen true stereo can't be shown, so it's either
  /// one eye as 2D or a red-cyan anaglyph (for glasses).
  @ViewBuilder
  private var threeDModeButton: some View {
    Menu {
      ForEach(ThreeDMode.allCases) { mode in
        Button {
          model.setThreeDMode(mode)
        } label: {
          if model.threeDMode == mode {
            Label(mode.title.localized, systemImage: "checkmark")
          } else {
            Text(mode.title.localized)
          }
        }
      }
    } label: {
      circleIcon("cube")
    }
    .menuIndicator(.hidden)
    .menuStyle(.button)
    .buttonStyle(.plain)
    .fixedSize()
    .accessibilityLabel("3D mode")
  }

  private var watchlistButton: some View {
    // Optimistic client state first, server flag as the fallback.
    let inWatchlist = libraryState.inWatchlist(itemId: mediaItem.id) ?? (mediaItem.inWatchlist == true)
    return circleIconButton(
      inWatchlist ? "checkmark" : "plus",
      accessibility: inWatchlist ? "Remove from Watchlist" : "Add to Watchlist"
    ) {
      model.toggleWatchlist()
    }
  }

  /// Like / dislike pills with their counts, shown next to the ratings. kino.pub voting is one-time.
  private var voteControl: some View {
    HStack(spacing: 8) {
      voteButton(up: true)
      voteButton(up: false)
    }
  }

  private func voteButton(up: Bool) -> some View {
    let active = model.myVote == (up ? .up : .down)
    let count = up ? model.likeCount : model.dislikeCount
    let filled = up ? "hand.thumbsup.fill" : "hand.thumbsdown.fill"
    let outline = up ? "hand.thumbsup" : "hand.thumbsdown"
    // Active like uses the kino.pub chip colour so it reads as part of the rating; dislike turns red.
    let activeColor: Color = up ? RatingBrand.kinopubTeal : Color(red: 0.88, green: 0.36, blue: 0.36)
    let activeForeground: Color = up ? .black : .white
    return Button {
      model.vote(up: up)
    } label: {
      HStack(spacing: 5) {
        Image(systemName: active ? filled : outline)
          .font(.system(size: 13, weight: .semibold))
        if count > 0 {
          Text(NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal))
            .font(.system(size: 13, weight: .semibold))
        }
      }
      .foregroundStyle(active ? activeForeground : Color.KinoPub.text)
      .padding(.horizontal, 11)
      .padding(.vertical, 6)
      .background(
        Capsule(style: .continuous)
          .fill(active ? activeColor : Color.KinoPub.selectionBackground))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(up ? "Like" : "Dislike")
  }

  private var watchedButton: some View {
    let watched = model.isMovieWatched
    return circleIconButton(
      watched ? "eye.fill" : "eye",
      accessibility: watched ? "Mark as Unwatched" : "Mark as Watched"
    ) {
      model.toggleWatched()
    }
  }

  @ViewBuilder
  private var bookmarkMenu: some View {
    Menu {
      ForEach(libraryState.bookmarkFolders) { folder in
        let isOn = libraryState.isBookmarked(itemId: mediaItem.id, folderId: folder.id)
        Button {
          model.toggleBookmark(folderId: folder.id, folderTitle: folder.title)
        } label: {
          // A checkmark marks folders this item is already in (was previously write-only/blind).
          if isOn {
            Label(folder.title, systemImage: "checkmark")
          } else {
            Text(folder.title)
          }
        }
      }
      Divider()
      Button {
        newFolderName = ""
        showCreateFolder = true
      } label: {
        Label("New folder…".localized, systemImage: "folder.badge.plus")
      }
    } label: {
      // Fill the icon when the item is in at least one folder.
      circleIcon(libraryState.isInAnyBookmarkFolder(itemId: mediaItem.id) ? "folder.fill" : "folder")
    }
    .menuIndicator(.hidden)
    // `.button` + `.plain` renders our circle label faithfully (borderlessButton strips the
    // background and tints the symbol with the accent colour).
    .menuStyle(.button)
    .buttonStyle(.plain)
    .fixedSize()
    .accessibilityLabel("Add to Bookmark")
    .accessibilityIdentifier(AccessibilityID.bookmarkPicker)
  }

  private var downloadButton: some View {
    Menu {
      MediaDownloadMenu(model: model)
    } label: {
      circleIcon(movieDownloadGlyph)
    }
    .menuIndicator(.hidden)
    .menuStyle(.button)
    .buttonStyle(.plain)
    .fixedSize()
    .accessibilityLabel("Download")
  }

  // MARK: - Play / Continue

  @ViewBuilder
  private var playButton: some View {
    let title = (hasResume ? "Continue" : (mediaItem.isSeries ? "Watch" : "Play")).localized
    // On a narrow screen the play button spans the full width on its own row.
    let fullWidth = !usesSidebar
    if mediaItem.isSeries, let episode = seriesPlayEpisode {
      NavigationLink(value: model.linkProvider.episodePlayer(for: episode, queue: episodeQueue)) {
        playLabel(title, subtitle: resumeSubtitle, fullWidth: fullWidth)
      }
      .buttonStyle(.plain)
    } else {
      NavigationLink(value: model.linkProvider.player(for: mediaItem)) {
        playLabel(title, subtitle: resumeSubtitle, fullWidth: fullWidth)
      }
      .buttonStyle(.plain)
    }
  }

  /// The series episode to continue (shared logic with the Home shelf). Falls back to the local
  /// store so a just-watched episode resumes instantly, before the server refetch lands.
  private var continueTarget: (season: Season, episode: Episode)? {
    mediaItem.continueEpisode() ?? model.localSeriesContinue()
  }

  /// Whether the play button should read "Continue" rather than "Play"/"Watch".
  private var hasResume: Bool {
    if mediaItem.isSeries { return continueTarget != nil }
    let serverTime = mediaItem.videos?.first?.watching.time ?? 0
    let localTime = model.localResumeSeconds(season: nil, episode: mediaItem.videos?.first?.number)
    return serverTime > 0 || localTime > 0
  }

  /// Episode to start for a series: the continue target if any, else the first episode.
  private var seriesPlayEpisode: Episode? {
    if let target = continueTarget {
      return filledEpisode(target.episode, in: target.season)
    }
    return firstPlayableEpisode
  }

  private func playLabel(_ title: String, subtitle: String? = nil, fullWidth: Bool = false) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "play.fill")
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 16, weight: .semibold))
        if let subtitle {
          Text(subtitle)
            .font(.system(size: 11, weight: .medium))
            .opacity(0.85)
        }
      }
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 22)
    .padding(.vertical, subtitle == nil ? 12 : 8)
    .frame(maxWidth: fullWidth ? .infinity : nil)
    .background(Capsule().fill(Color.accentColor))
  }

  /// Resume detail shown under "Continue": "S{n} · E{n} · {time}" for series, just time for movies.
  private var resumeSubtitle: String? {
    guard hasResume else { return nil }
    if mediaItem.isSeries, let target = continueTarget {
      let base = "S\(target.season.number) · E\(target.episode.number)"
      let time = max(
        target.episode.watching.time,
        model.localResumeSeconds(season: target.season.number, episode: target.episode.number))
      return time > 0 ? "\(base) · \(Self.resumeTime(time))" : base
    }
    let time = max(
      mediaItem.videos?.first?.watching.time ?? 0,
      model.localResumeSeconds(season: nil, episode: mediaItem.videos?.first?.number))
    return time > 0 ? Self.resumeTime(time) : nil
  }

  private static func resumeTime(_ seconds: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
    formatter.unitsStyle = .positional
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: TimeInterval(seconds)) ?? ""
  }

  private func circleIcon(_ systemName: String) -> some View {
    Image(systemName: systemName)
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 50, height: 50)
      .background(Circle().fill(Color.white.opacity(0.18)))
  }

  /// Download icon glyph for a movie's download button, reflecting the client library state.
  private var movieDownloadGlyph: String {
    guard !mediaItem.isSeries else { return "arrow.down.to.line" }
    switch libraryState.downloadStatus(itemId: mediaItem.id, video: mediaItem.videos?.first?.number, season: nil) {
    case .downloaded: return "arrow.down.circle.fill"
    case .downloading: return "arrow.down.circle"
    case .none: return "arrow.down.to.line"
    }
  }

  private func circleIconButton(
    _ systemName: String,
    accessibility: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      circleIcon(systemName)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibility)
  }

  // MARK: - Resume helpers shared with the episodes section

  func filledEpisode(_ episode: Episode, in season: Season) -> Episode {
    episode.seasonNumber = season.number
    episode.mediaId = season.mediaId ?? mediaItem.id
    episode.mediaTitle = mediaItem.localizedTitle
    return episode
  }

  private var firstPlayableEpisode: Episode? {
    guard let season = mediaItem.seasons?.first,
          let episode = season.episodes.first
    else { return nil }
    return filledEpisode(episode, in: season)
  }

  /// Every episode in playback order, with the parent metadata needed for watch sync.
  private var episodeQueue: [Episode] {
    mediaItem.orderedEpisodes.map { filledEpisode($0.episode, in: $0.season) }
  }
}

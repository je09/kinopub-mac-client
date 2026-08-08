//
//  MediaMetadataSection.swift
//  KinoPubAppleClient
//
//  Apple TV-style "Information" + "Languages" block for the media detail page. Prefers a two-column
//  layout and falls back to a stacked one when too narrow. Preserves the IMDB / Kinopoisk deep
//  links (issue #44).
//

import SwiftUI
import KinoPubBackend
import KinoPubUI

struct MediaMetadataSection: View {

  let mediaItem: MediaItem
  @ObservedObject var model: MediaItemModel
  let usesSidebar: Bool
  let openSection: (MediaItemsFilter) -> Void

  /// A tappable facet that deep-links into a section (wide) or pushes a filtered catalog (compact).
  @ViewBuilder
  private func sectionFacet<Label: View>(
    filter: MediaItemsFilter,
    route: (any Hashable)?,
    @ViewBuilder label: () -> Label
  ) -> some View {
    if usesSidebar {
      Button {
        openSection(filter)
      } label: {
        label()
      }
      .buttonStyle(.plain)
    } else {
      facetLink(route, label: label)
    }
  }

  var body: some View {
    // Prefer a two-column layout, but fall back to a stacked layout when the
    // available width is too narrow to fit both columns comfortably.
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .top, spacing: 48) {
        information
        languages
        Spacer(minLength: 0)
      }
      VStack(alignment: .leading, spacing: 24) {
        information
        languages
      }
    }
    .padding(.horizontal, 20)
  }

  // MARK: - Information

  private var information: some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle("Information".localized)

      if mediaItem.year > 0 {
        facetRow(
          label: "Premiere".localized,
          value: "\(mediaItem.year)",
          filter: model.yearFilter(mediaItem.year),
          route: model.yearRoute(mediaItem.year))
      }

      if !mediaItem.countries.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          Text("Country".localized.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.KinoPub.subtitle)
          FlowLayout(spacing: 10, lineSpacing: 6) {
            ForEach(Array(mediaItem.countries.enumerated()), id: \.offset) { _, country in
              sectionFacet(
                filter: model.countryFilter(id: country.id),
                route: model.countryRoute(id: country.id, title: country.title)
              ) {
                facetValueText(country.title, isLink: true)
              }
            }
          }
        }
      }

      if !model.directorNames.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          Text("Director".localized.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.KinoPub.subtitle)
          FlowLayout(spacing: 10, lineSpacing: 6) {
            ForEach(Array(model.directorNames.enumerated()), id: \.offset) { _, name in
              facetLink(model.directorRoute(name)) {
                facetValueText(name, isLink: model.directorRoute(name) != nil)
              }
            }
          }
        }
      }

      if (mediaItem.imdbRating ?? 0) > 0 || (mediaItem.kinopoiskRating ?? 0) > 0 || (kinopubScore ?? 0) > 0 {
        VStack(alignment: .leading, spacing: 4) {
          Text("Rating".localized.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.KinoPub.subtitle)
          RatingsDetailRow(
            kinopubScore: kinopubScore,
            kinopubVotes: mediaItem.ratingVotes,
            imdbScore: mediaItem.imdbRating,
            imdbVotes: mediaItem.imdbVotes,
            kinopoiskScore: mediaItem.kinopoiskRating,
            kinopoiskVotes: mediaItem.kinopoiskVotes)
        }
      }

      if mediaItem.isSeries {
        infoRow(label: "Status".localized, value: statusValue)
        if let total = totalValue {
          infoRow(label: "Total".localized, value: total)
        }
        infoRow(label: "Duration".localized, value: durationValue)
      }
    }
  }

  // MARK: - Series info helpers

  private var statusValue: String {
    mediaItem.finished ? "Finished".localized : "Ongoing".localized
  }

  private var totalValue: String? {
    guard let seasons = mediaItem.seasons, !seasons.isEmpty else { return nil }
    let episodes = seasons.reduce(0) { $0 + $1.episodes.count }
    return "\(seasons.count) \("seasons".localized), \(episodes) \("episodes".localized)"
  }

  private var durationValue: String {
    let average = mediaItem.duration.average
    let total = mediaItem.duration.total
    var parts: [String] = []
    if average > 0 {
      let minutes = Int(average / 60)
      parts.append("≈ \(Self.clock(average)) (\(minutes) \("min".localized))")
    }
    if total > 0 {
      parts.append("\("total".localized): \(Self.abbreviated(total))")
    }
    return parts.joined(separator: ", ")
  }

  private static func clock(_ seconds: Double) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute, .second]
    formatter.unitsStyle = .positional
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: seconds) ?? ""
  }

  private static func abbreviated(_ seconds: Double) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.day, .hour, .minute]
    formatter.unitsStyle = .abbreviated
    return formatter.string(from: seconds) ?? ""
  }

  // MARK: - Languages

  @ViewBuilder
  private var languages: some View {
    let voice = mediaItem.voice?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !voice.isEmpty {
      VStack(alignment: .leading, spacing: 12) {
        sectionTitle("Languages".localized)
        infoRow(label: "Audio", value: voice)
      }
    }
  }

  // MARK: - Building blocks

  private func sectionTitle(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 22, weight: .bold))
      .foregroundStyle(Color.KinoPub.text)
  }

  private func infoRow(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.KinoPub.subtitle)
      Text(value)
        .font(.system(size: 14))
        .foregroundStyle(Color.KinoPub.text)
    }
  }

  /// An info row whose value is tappable (when a `route` exists) to open a
  /// filtered catalog (e.g. year).
  @ViewBuilder
  private func facetRow(
    label: String, value: String, filter: MediaItemsFilter? = nil, route: (any Hashable)?
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label.uppercased())
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Color.KinoPub.subtitle)
      if let filter {
        sectionFacet(filter: filter, route: route) {
          facetValueText(value, isLink: route != nil)
        }
      } else {
        facetLink(route) {
          facetValueText(value, isLink: route != nil)
        }
      }
    }
  }

  @ViewBuilder
  private func facetLink<Label: View>(_ route: (any Hashable)?, @ViewBuilder label: () -> Label) -> some View {
    if let route {
      NavigationLink(value: route) {
        label()
      }
      .buttonStyle(.plain)
    } else {
      label()
    }
  }

  private func facetValueText(_ value: String, isLink: Bool) -> some View {
    Text(value)
      .font(.system(size: 14, weight: isLink ? .semibold : .regular))
      .foregroundStyle(isLink ? Color.accentColor : Color.KinoPub.text)
  }

  // MARK: - Deep links (issue #44)

  /// kino.pub's own rating on a 0–10 scale (the API gives it as a 0–100 percentage). nil when unrated.
  private var kinopubScore: Double? {
    mediaItem.ratingPercentage > 0 ? mediaItem.ratingPercentage / 10.0 : nil
  }

  private var imdbURL: URL? {
    guard let imdb = mediaItem.imdb, imdb > 0 else { return nil }
    return URL(string: "https://www.imdb.com/title/tt\(String(format: "%07d", imdb))/")
  }

  private var kinopoiskURL: URL? {
    guard let kinopoisk = mediaItem.kinopoisk, kinopoisk > 0 else { return nil }
    return URL(string: "https://www.kinopoisk.ru/film/\(kinopoisk)/")
  }
}

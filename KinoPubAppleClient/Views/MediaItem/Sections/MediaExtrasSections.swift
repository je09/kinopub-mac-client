//
//  MediaExtrasSections.swift
//  KinoPubAppleClient
//
//  Kinopoisk extras on the media detail page: stills, facts, reviews — plus their cards, sheets and
//  full-screen stills viewer. Render-only; data comes from `MediaExtrasLoader`.
//

import SwiftUI
import KinoPubBackend
import KinoPubUI

// MARK: - Shared extras header

/// A titled vertical section header with an optional "see all" chevron, matching the shelf headers.
struct MediaExtrasHeader: View {
  let title: String
  let action: (() -> Void)?

  var body: some View {
    Button(action: { action?() }) {
      HStack(spacing: 6) {
        Text(title)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(Color.KinoPub.text)
        if action != nil {
          Image(systemName: "chevron.right")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Color.KinoPub.subtitle)
        }
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
      .padding(.horizontal, 20)
    }
    .buttonStyle(.plain)
    .disabled(action == nil)
  }
}

// MARK: - Stills (Images)

/// Still thumbnail shelf; opens the full-screen viewer.
struct MediaStillsSection: View {
  @ObservedObject var extras: MediaExtrasLoader
  let itemLoaded: Bool
  @Binding var stillSelection: StillSelection?

  @ViewBuilder
  var body: some View {
    if !extras.images.isEmpty {
      let preview = Array(extras.images.prefix(15))
      let hasMore = extras.images.count > preview.count
      MediaShelf(
        title: "Images".localized,
        showsChevron: hasMore,
        onHeaderTap: hasMore ? { stillSelection = StillSelection(index: 0) } : nil
      ) {
        ForEach(Array(preview.enumerated()), id: \.offset) { idx, image in
          Button {
            stillSelection = StillSelection(index: idx)
          } label: {
            StillThumbnail(url: image.previewUrl ?? image.imageUrl)
          }
          .buttonStyle(.plain)
        }
      }
    } else if itemLoaded && !extras.extrasLoaded {
      skeletonImagesShelf
    }
  }

  private var skeletonImagesShelf: some View {
    // StillThumbnail with no URL renders its skeleton fill at the exact still size.
    MediaShelf(title: "Images".localized, showsChevron: false) {
      ForEach(0..<6, id: \.self) { _ in StillThumbnail(url: nil) }
    }
  }
}

// MARK: - Facts

/// Facts shelf (top 3, expandable to a sheet).
struct MediaFactsSection: View {
  @ObservedObject var extras: MediaExtrasLoader
  let itemLoaded: Bool
  @Binding var showFacts: Bool

  @ViewBuilder
  var body: some View {
    if !extras.facts.isEmpty {
      VStack(alignment: .leading, spacing: 14) {
        MediaExtrasHeader(title: "Facts".localized, action: extras.facts.count > 3 ? { showFacts = true } : nil)
        VStack(spacing: 10) {
          ForEach(extras.facts.prefix(3)) { fact in
            FactCard(fact: fact)
          }
        }
        .padding(.horizontal, 20)
      }
    } else if itemLoaded && !extras.extrasLoaded {
      skeletonTextSection("Facts".localized, rows: 3, rowHeight: 56)
    }
  }

  private func skeletonTextSection(_ title: String, rows: Int, rowHeight: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      MediaExtrasHeader(title: title, action: nil)
      VStack(spacing: 10) {
        ForEach(0..<rows, id: \.self) { _ in
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.KinoPub.skeleton)
            .frame(height: rowHeight)
        }
      }
      .padding(.horizontal, 20)
    }
  }
}

// MARK: - Reviews

/// Reviews shelf (top 2, expandable to a sheet).
struct MediaReviewsSection: View {
  @ObservedObject var extras: MediaExtrasLoader
  let itemLoaded: Bool
  @Binding var showReviews: Bool

  @ViewBuilder
  var body: some View {
    if !extras.reviews.items.isEmpty {
      VStack(alignment: .leading, spacing: 14) {
        MediaExtrasHeader(title: "Reviews".localized, action: extras.reviews.items.count > 2 ? { showReviews = true } : nil)
        VStack(spacing: 10) {
          ForEach(extras.reviews.items.prefix(2)) { review in
            ReviewCard(review: review)
          }
        }
        .padding(.horizontal, 20)
      }
    } else if itemLoaded && !extras.extrasLoaded {
      skeletonTextSection("Reviews".localized, rows: 2, rowHeight: 110)
    }
  }

  private func skeletonTextSection(_ title: String, rows: Int, rowHeight: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      MediaExtrasHeader(title: title, action: nil)
      VStack(spacing: 10) {
        ForEach(0..<rows, id: \.self) { _ in
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.KinoPub.skeleton)
            .frame(height: rowHeight)
        }
      }
      .padding(.horizontal, 20)
    }
  }
}

// MARK: - Components

/// Identifiable wrapper so the stills viewer can be presented via `.sheet(item:)`.
struct StillSelection: Identifiable {
  let index: Int
  var id: Int { index }
}

/// A 16:9 still thumbnail for the Images shelf.
struct StillThumbnail: View {
  let url: String?
  var body: some View {
    Color.KinoPub.skeleton
      .frame(width: 200, height: 112)
      .overlay {
        CachedAsyncImage(url: URL(string: url ?? "")) { image in
          image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
          Color.KinoPub.skeleton
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

/// A single trivia fact / goof card. The icon is chosen from trigger words in the text (money, awards,
/// camera, cast, music, …) and sits in a tinted rounded square.
struct FactCard: View {
  let fact: KpFact

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      let glyph = FactGlyph.for(fact)
      Image(systemName: glyph.symbol)
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(glyph.color.opacity(0.85))
        .frame(width: 22, alignment: .center)
        .padding(.top, 1)
      Text(KinopoiskTextSanitizer.plain(fact.text))
        .font(.system(size: 14))
        .foregroundStyle(Color.KinoPub.text)
        .lineSpacing(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.KinoPub.selectionBackground))
  }
}

/// Maps a fact's text to a tasteful SF Symbol + tint by scanning for trigger words (Russian + a few
/// English). First match wins, so the list is ordered most-specific → general.
enum FactGlyph {
  static func `for`(_ fact: KpFact) -> (symbol: String, color: Color) {
    let text = fact.text.lowercased()
    func has(_ words: [String]) -> Bool { words.contains { text.contains($0) } }

    if fact.isBlooper { return ("exclamationmark.bubble.fill", Color(red: 0.45, green: 0.48, blue: 0.55)) }
    if has(["оскар", "преми", "награ", "номина", "глобус", "канн", "бафта", "пальм"]) {
      return ("trophy.fill", Color(red: 0.84, green: 0.66, blue: 0.16))
    }
    if has(["бюджет", "млн", "миллион", "миллиард", "доллар", "гонорар", "сбор", "касс", "$", "заработа", "стои"]) {
      return ("dollarsign.circle.fill", Color(red: 0.20, green: 0.70, blue: 0.42))
    }
    if has([
      "роль", "сыгра", "актёр", "актер", "актрис", "кастинг", "пробы", "дублёр", "дублер", "каскадёр", "каскадер",
      "сниматься",
    ]) {
      return ("theatermasks.fill", Color(red: 0.56, green: 0.36, blue: 0.80))
    }
    if has(["режиссёр", "режиссер", "постанов", "снял фильм", "снимать фильм"]) {
      return ("megaphone.fill", Color(red: 0.95, green: 0.56, blue: 0.20))
    }
    if has(["камер", "плёнк", "пленк", "imax", "кадр", "съёмк", "съемк", "оператор", "объектив", "снима"]) {
      return ("camera.fill", Color(red: 0.20, green: 0.55, blue: 0.92))
    }
    if has(["музык", "саундтрек", "композитор", "песн", "мелоди", "звук"]) {
      return ("music.note", Color(red: 0.92, green: 0.36, blue: 0.56))
    }
    if has(["книг", "сценари", "роман", "основан на", "по мотивам", "автор"]) {
      return ("book.fill", Color(red: 0.30, green: 0.62, blue: 0.60))
    }
    if has(["компьютер", "cgi", "эффект", "график", "грим", "технолог", "взрыв"]) {
      return ("wand.and.stars", Color(red: 0.38, green: 0.42, blue: 0.86))
    }
    if has(["травм", "погиб", "опасн", "ранен", "несчаст", "пострада"]) {
      return ("exclamationmark.triangle.fill", Color(red: 0.88, green: 0.32, blue: 0.32))
    }
    if has(["впервые", "рекорд", "первый", "единствен", "самый"]) {
      return ("star.fill", Color(red: 0.95, green: 0.74, blue: 0.20))
    }
    if has(["язык", "перевод", "дубляж", "стран"]) {
      return ("globe", Color(red: 0.18, green: 0.66, blue: 0.66))
    }
    if has(["час", "минут", "год", " лет", "длил", "снимал"]) {
      return ("clock.fill", Color(red: 0.42, green: 0.52, blue: 0.64))
    }
    return ("lightbulb.fill", Color(red: 0.95, green: 0.66, blue: 0.18))
  }
}

/// A review card with an editorial serif body, clamped to 4 lines and expandable in place.
struct ReviewCard: View {
  let review: KpReview
  @State private var expanded = false

  private var bodyText: String { KinopoiskTextSanitizer.plain(review.description ?? "") }
  /// Kinopoisk reviews are long-form; show the expand toggle when the body clearly exceeds ~4 lines.
  private var isExpandable: Bool { bodyText.count > 220 }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // Sentiment dot + author + date.
      HStack(spacing: 7) {
        Circle().fill(typeColor).frame(width: 7, height: 7)
        Group {
          if let author = review.author, !author.isEmpty {
            Text(author)
          } else {
            Text("Anonymous".localized)
          }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.KinoPub.text)
        .lineLimit(1)
        if let date = formattedDate {
          Text("·").font(.system(size: 12)).foregroundStyle(Color.KinoPub.subtitle)
          Text(date).font(.system(size: 12)).foregroundStyle(Color.KinoPub.subtitle)
        }
        Spacer(minLength: 0)
      }

      if let title = review.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
        Text(title)
          .font(.system(.headline, design: .serif).weight(.semibold))
          .foregroundStyle(Color.KinoPub.text)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
      }

      Text(bodyText)
        .font(.system(.subheadline, design: .serif))
        .foregroundStyle(Color.KinoPub.text.opacity(0.92))
        .lineSpacing(3)
        .lineLimit(expanded ? nil : 4)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

      if isExpandable {
        Button(expanded ? "Show less".localized : "Show more".localized) {
          withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.accentColor)
        .buttonStyle(.plain)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.KinoPub.selectionBackground))
  }

  private var typeColor: Color {
    switch (review.type ?? "").uppercased() {
    case "POSITIVE": return Color(red: 0.30, green: 0.78, blue: 0.45)
    case "NEGATIVE": return Color(red: 0.90, green: 0.36, blue: 0.36)
    default: return Color.KinoPub.subtitle
    }
  }

  private var formattedDate: String? {
    guard let raw = review.date, !raw.isEmpty else { return nil }
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    guard let date = parser.date(from: raw) else { return nil }
    let out = DateFormatter()
    out.dateStyle = .long
    out.timeStyle = .none
    return out.string(from: date)
  }
}

/// Full Facts sheet.
struct FactsView: View {
  let facts: [KpFact]
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach(facts) { FactCard(fact: $0) }
        }
        .padding(16)
      }
      .background(Color.KinoPub.background)
      .navigationTitle("Facts".localized)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done".localized) { dismiss() } } }
    }
  }
}

/// Full Reviews sheet.
struct ReviewsView: View {
  let reviews: KpReviewsPage
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(reviews.items) { review in
            ReviewCard(review: review)
          }
        }
        .padding(16)
      }
      .background(Color.KinoPub.background)
      .navigationTitle("Reviews".localized)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done".localized) { dismiss() } } }
    }
  }
}

/// Full-screen swipeable stills viewer.
struct StillsViewer: View {
  let images: [KpImage]
  let startIndex: Int
  @Environment(\.dismiss) private var dismiss
  @State private var index: Int

  init(images: [KpImage], startIndex: Int) {
    self.images = images
    self.startIndex = startIndex
    _index = State(initialValue: startIndex)
  }

  var body: some View {
    NavigationStack {
      TabView(selection: $index) {
        ForEach(Array(images.enumerated()), id: \.offset) { i, image in
          CachedAsyncImage(url: URL(string: image.imageUrl ?? image.previewUrl ?? "")) { img in
            img.resizable().aspectRatio(contentMode: .fit)
          } placeholder: {
            ProgressView()
          }
          .tag(i)
        }
      }
      .background(Color.black.ignoresSafeArea())
      .navigationTitle("\(min(index + 1, images.count)) / \(images.count)")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done".localized) { dismiss() } } }
    }
  }
}

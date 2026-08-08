//
//  SearchDisplayHelpers.swift
//  KinoPubAppleClient
//
//  Small presentation helpers shared by the search subviews.
//

import Foundation
import KinoPubDomain

extension PersonSearchResult {
  var roleLabel: String {
    switch (isActor, isDirector) {
    case (true, true): return "\("Actor".localized) · \("Director".localized)"
    case (false, true): return "Director".localized
    default: return "Actor".localized
    }
  }
}

extension MediaSummary {
  /// "Type · Genre · Year" metadata line for search rows and top-result cards.
  var searchMetaLine: String {
    var parts: [String] = []
    if !typeTitle.isEmpty { parts.append(typeTitle) }
    if let genre = primaryGenreTitle, !genre.isEmpty { parts.append(genre) }
    if year > 0 { parts.append("\(year)") }
    return parts.joined(separator: " · ")
  }
}

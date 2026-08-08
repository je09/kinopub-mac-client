//
//  KinopoiskTextSanitizer.swift
//  KinoPubAppleClient
//
//  Light HTML→plain-text cleanup for Kinopoisk facts / review bodies (tags + named & numeric
//  entities). Deliberately outside the UI layer: pure Foundation, no SwiftUI.
//

import Foundation

enum KinopoiskTextSanitizer {
  static func plain(_ html: String) -> String {
    var s = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    let entities = [
      "&nbsp;": " ", "&mdash;": "—", "&ndash;": "–", "&laquo;": "«", "&raquo;": "»",
      "&quot;": "\"", "&hellip;": "…", "&amp;": "&", "&lt;": "<", "&gt;": ">",
      "&rsquo;": "’", "&lsquo;": "‘", "&ldquo;": "“", "&rdquo;": "”",
    ]
    for (k, v) in entities { s = s.replacingOccurrences(of: k, with: v) }
    s = decodeNumericEntities(s)
    s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Replace decimal (`&#171;`) and hex (`&#xAB;`) HTML character references with their characters.
  private static func decodeNumericEntities(_ s: String) -> String {
    guard s.contains("&#"), let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);") else { return s }
    let ns = s as NSString
    let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else { return s }
    var result = ""
    var cursor = 0
    for m in matches {
      result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
      let isHex = !ns.substring(with: m.range(at: 1)).isEmpty
      let digits = ns.substring(with: m.range(at: 2))
      if let code = UInt32(digits, radix: isHex ? 16 : 10), let scalar = Unicode.Scalar(code) {
        result.unicodeScalars.append(scalar)
      } else {
        result += ns.substring(with: m.range)  // malformed — leave untouched
      }
      cursor = m.range.location + m.range.length
    }
    result += ns.substring(from: cursor)
    return result
  }
}

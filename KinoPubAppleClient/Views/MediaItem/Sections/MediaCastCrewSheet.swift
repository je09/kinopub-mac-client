//
//  MediaCastCrewSheet.swift
//  KinoPubAppleClient
//
//  Full "Cast & Crew" roster, shown when the user taps the shelf header on the media detail page.
//  Apple-TV-style grouped grid of circular avatars. Prefers the Kinopoisk crew (photos + characters,
//  grouped by profession); falls back to kino.pub's plain director/actor names with CDN photos.
//

import SwiftUI
import KinoPubBackend
import KinoPubUI

struct CastCrewView: View {
  let directors: [String]
  let actors: [String]
  let staff: [KpStaffMember]
  /// Called when a person is tapped: (name, field) where field is "cast" or "director". The view
  /// dismisses itself first, then the presenter opens that person's section (like More with / More from).
  var onSelect: ((_ name: String, _ field: String) -> Void)?
  @Environment(\.dismiss) private var dismiss

  private let columns = [GridItem(.adaptive(minimum: 100), spacing: 14, alignment: .top)]

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          if !staff.isEmpty {
            staffContent
          } else {
            if !directors.isEmpty { namesSection(title: "Directors".localized, names: directors, field: "director") }
            if !actors.isEmpty { namesSection(title: "Cast".localized, names: actors, field: "cast") }
          }
        }
        .padding(.vertical, 16)
      }
      .background(Color.KinoPub.background)
      .navigationTitle("Cast & Crew".localized)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done".localized) { dismiss() }
        }
      }
    }
  }

  /// Kinopoisk crew grouped by profession ("Режиссёры", "Актёры", …), preserving the API order.
  @ViewBuilder
  private var staffContent: some View {
    let groups = orderedProfessionGroups
    ForEach(groups, id: \.0) { profession, members in
      VStack(alignment: .leading, spacing: 14) {
        sectionTitle(profession)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
          ForEach(members) { member in
            personButton(
              name: member.displayName,
              field: member.professionKey == "DIRECTOR" ? "director" : "cast"
            ) {
              CastAvatarView(
                imageURL: member.posterUrl,
                name: member.displayName,
                role: member.description?.isEmpty == false ? member.description : nil,
                diameter: 80)
            }
          }
        }
        .padding(.horizontal, 20)
      }
    }
  }

  /// Wraps a person avatar so tapping it dismisses the modal and opens that person's section.
  @ViewBuilder
  private func personButton<Label: View>(name: String, field: String, @ViewBuilder label: () -> Label) -> some View {
    Button {
      onSelect?(name, field)
      dismiss()
    } label: {
      label()
    }
    .buttonStyle(.plain)
  }

  private var orderedProfessionGroups: [(String, [KpStaffMember])] {
    var order: [String] = []
    var map: [String: [KpStaffMember]] = [:]
    for member in staff {
      let key = (member.professionText ?? "—")
      if map[key] == nil { order.append(key) }
      map[key, default: []].append(member)
    }
    return order.map { ($0, map[$0] ?? []) }
  }

  @ViewBuilder
  private func namesSection(title: String, names: [String], field: String) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      sectionTitle(title)
      LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
        ForEach(names, id: \.self) { name in
          personButton(name: name, field: field) {
            CastAvatarView(
              imageURL: ActorImageProvider.photoURLString(for: name),
              name: name, diameter: 80)
          }
        }
      }
      .padding(.horizontal, 20)
    }
  }

  private func sectionTitle(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 20, weight: .bold))
      .foregroundStyle(Color.KinoPub.text)
      .padding(.horizontal, 20)
  }
}

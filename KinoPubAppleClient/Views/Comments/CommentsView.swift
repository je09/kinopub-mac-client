//
//  CommentsView.swift
//  KinoPubAppleClient
//
//  Comments for a film/episode. Presented as a sheet from MediaItemView.
//

import SwiftUI
import KinoPubDomain
import KinoPubUI

struct CommentsView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var store: CommentsStore

  init(store: @autoclosure @escaping () -> CommentsStore) {
    _store = StateObject(wrappedValue: store())
  }

  var body: some View {
    NavigationStack {
      content
        .background(Color.KinoPub.background)
        .navigationTitle("Comments".localized)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("Done".localized) { dismiss() }
          }
        }
        .task { await store.load() }
    }
  }

  @ViewBuilder
  private var content: some View {
    switch store.state {
    case .idle, .loading:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .empty:
      emptyState(failed: false)
    case .failed:
      emptyState(failed: true)
    case .loaded(let comments):
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(comments.map(CommentRowModel.init)) { comment in
            CommentRow(model: comment)
            Divider().background(Color.white.opacity(0.08))
          }
        }
        .padding(.vertical, 8)
      }
    }
  }

  private func emptyState(failed: Bool) -> some View {
    KinoPubUI.EmptyStateView(
      systemImage: "bubble.left.and.bubble.right",
      title: failed ? "Couldn't load comments".localized : "No comments yet".localized,
      message: failed ? nil : "Be the first to discuss this title".localized
    )
  }
}

private struct CommentRowModel: Identifiable {
  let id: Int
  let authorName: String
  let avatarURL: URL?
  let formattedDate: String
  let rating: Int?
  let message: String
  let depth: Int

  init(comment: Comment) {
    id = comment.id
    authorName = comment.author.name
    avatarURL = comment.author.avatarURL
    formattedDate = comment.createdAt.formatted(date: .abbreviated, time: .shortened)
    rating = comment.rating
    message = comment.message
    depth = comment.depth
  }
}

private struct CommentRow: View {
  let model: CommentRowModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 10) {
        avatar
        VStack(alignment: .leading, spacing: 2) {
          Text(model.authorName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.KinoPub.text)
          Text(model.formattedDate)
            .font(.system(size: 11))
            .foregroundStyle(Color.KinoPub.subtitle)
        }
        Spacer()
        if let rating = model.rating {
          HStack(spacing: 2) {
            Image(systemName: rating > 0 ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
            Text("\(rating > 0 ? "+" : "")\(rating)")
          }
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(rating > 0 ? Color.accentColor : Color.red.opacity(0.8))
        }
      }
      Text(model.message)
        .font(.system(size: 14))
        .foregroundStyle(Color.KinoPub.text)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
    .padding(.leading, CGFloat(min(model.depth, 4)) * 16)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  private var avatar: some View {
    CachedAsyncImage(url: model.avatarURL) { image in
      image.resizable().aspectRatio(contentMode: .fill)
    } placeholder: {
      Circle()
        .fill(Color.accentColor.opacity(0.25))
        .overlay(
          Text(String(model.authorName.prefix(1)).uppercased())
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.accentColor)
        )
    }
    .frame(width: 36, height: 36)
    .clipShape(Circle())
  }
}

//
//  View+Skeleton.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 2.08.2023.
//

import SwiftUI

/// Local placeholder treatment used while content is loading. Keeping this deliberately small and
/// based on SwiftUI's native redaction avoids a runtime dependency for a purely visual effect.
public extension View {
  func skeleton(enabled: Bool, size: CGSize? = nil) -> some View {
    modifier(KinoPubSkeletonModifier(enabled: enabled, size: size))
  }

  func multilineSkeleton(enabled: Bool, size: CGSize? = nil) -> some View {
    modifier(KinoPubSkeletonModifier(enabled: enabled, size: size))
  }
}

private struct KinoPubSkeletonModifier: ViewModifier {
  let enabled: Bool
  let size: CGSize?

  func body(content: Content) -> some View {
    content
      .frame(
        width: enabled ? size?.width : nil,
        height: enabled ? size?.height : nil,
        alignment: .leading
      )
      .redacted(reason: enabled ? .placeholder : [])
      .overlay {
        if enabled, size != nil {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.KinoPub.skeleton.opacity(0.85))
            .allowsHitTesting(false)
        }
      }
      .accessibilityHidden(enabled)
  }
}

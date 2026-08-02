//
//  WidthThresholdReader.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 31.07.2023.
//

import Foundation
import SwiftUI

/**
 A view useful for determining if a child view should act like it is horizontally compressed.
 
 Width and Dynamic Type size determine whether the child should use its compact layout.
 */
struct WidthThresholdReader<Content: View>: View {
  var widthThreshold: Double = 400
  var dynamicTypeThreshold: DynamicTypeSize = .xxLarge
  @ViewBuilder var content: (WidthThresholdProxy) -> Content
  
  @Environment(\.dynamicTypeSize) private var dynamicType
  
  var body: some View {
    GeometryReader { geometryProxy in
      let compressionProxy = WidthThresholdProxy(
        width: geometryProxy.size.width,
        isCompact: isCompact(width: geometryProxy.size.width)
      )
      content(compressionProxy)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
  
  func isCompact(width: Double) -> Bool {
    if dynamicType >= dynamicTypeThreshold {
      return true
    }
    if width < widthThreshold {
      return true
    }
    return false
  }
}

struct WidthThresholdProxy: Equatable {
  var width: Double
  var isCompact: Bool
}

struct WidthThresholdReader_Previews: PreviewProvider {
  static var previews: some View {
    VStack(spacing: 40) {
      WidthThresholdReader { proxy in
        Label {
          Text("Standard")
        } icon: {
          compactIndicator(proxy: proxy)
        }
      }
      .border(.quaternary)
      
      WidthThresholdReader { proxy in
        Label {
          Text("200 Wide")
        } icon: {
          compactIndicator(proxy: proxy)
        }
      }
      .frame(width: 200)
      .border(.quaternary)
      
      WidthThresholdReader { proxy in
        Label {
          Text("X Large Type")
        } icon: {
          compactIndicator(proxy: proxy)
        }
      }
      .dynamicTypeSize(.xxxLarge)
      .border(.quaternary)
      
    }
  }
  
  @ViewBuilder
  static func compactIndicator(proxy: WidthThresholdProxy) -> some View {
    if proxy.isCompact {
      Image(systemName: "arrowtriangle.right.and.line.vertical.and.arrowtriangle.left.fill")
        .foregroundStyle(.red)
    } else {
      Image(systemName: "checkmark.circle")
        .foregroundStyle(.secondary)
    }
  }
}

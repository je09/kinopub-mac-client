//
//  Color+Extension.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import SwiftUI

extension Color {
  public struct KinoPub {
    public static let accent = Color("accent_color", bundle: .module)
    public static let accentRed = Color("accent_red_color", bundle: .module)
    public static let accentBlue = Color("accent_blue_color", bundle: .module)
    public static let background = Color("background_color", bundle: .module)
    // Semantic system colors remain visible even if a SwiftPM asset bundle resolves before the
    // window's dark appearance is installed (observed in optimized Release builds).
    public static let text = Color.primary
    public static let subtitle = Color.secondary
    public static let selectionBackground = Color("selection_background_color", bundle: .module)
    public static let skeleton = Color("skeleton_color", bundle: .module)
  }
}

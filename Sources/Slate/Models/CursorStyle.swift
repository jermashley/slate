import Foundation
import SwiftTerm

enum CursorStyle: String, CaseIterable, Identifiable, Codable {
    case block
    case bar
    case underline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .block:
            "Block"
        case .bar:
            "Bar"
        case .underline:
            "Underline"
        }
    }

    var swiftTermStyle: SwiftTerm.CursorStyle {
        switch self {
        case .block:
            .steadyBlock
        case .bar:
            .steadyBar
        case .underline:
            .steadyUnderline
        }
    }
}

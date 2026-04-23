import Foundation

enum SessionStyle: String, CaseIterable, Identifiable, Codable {
    case classic
    case block

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic:
            "Classic"
        case .block:
            "Block"
        }
    }
}

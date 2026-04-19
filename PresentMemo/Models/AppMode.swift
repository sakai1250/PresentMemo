import Foundation

enum AppMode: String, Codable, CaseIterable {
    case `default` = "default"
    case pdfAnalysis = "pdfAnalysis"
    case powerPoint = "powerPoint"

    var localizedName: String {
        switch self {
        case .default:    return NSLocalizedString("mode.default", comment: "")
        case .pdfAnalysis: return NSLocalizedString("mode.pdf", comment: "")
        case .powerPoint: return NSLocalizedString("mode.pptx", comment: "")
        }
    }

    var iconName: String {
        switch self {
        case .default:    return "books.vertical.fill"
        case .pdfAnalysis: return "doc.text.magnifyingglass"
        case .powerPoint: return "rectangle.on.rectangle.angled.fill"
        }
    }

    var accentColor: String {
        switch self {
        case .default:    return "blue"
        case .pdfAnalysis: return "red"
        case .powerPoint: return "orange"
        }
    }
}

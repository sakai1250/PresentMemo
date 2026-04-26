import Foundation

enum AppMode: String, Codable, CaseIterable {
    case `default` = "default"
    case manualInput = "manualInput"
    case csvImport = "csvImport"
    case pdfAnalysis = "pdfAnalysis"
    case powerPoint = "powerPoint"

    var localizedName: String {
        switch self {
        case .default: return NSLocalizedString("mode.default", comment: "")
        case .manualInput: return NSLocalizedString("mode.manual", comment: "")
        case .csvImport: return NSLocalizedString("mode.csv", comment: "")
        case .pdfAnalysis: return NSLocalizedString("mode.pdf", comment: "")
        case .powerPoint: return NSLocalizedString("mode.pptx", comment: "")
        }
    }

    var iconName: String {
        switch self {
        case .default: return "books.vertical.fill"
        case .manualInput: return "square.and.pencil"
        case .csvImport: return "tablecells"
        case .pdfAnalysis: return "doc.text.magnifyingglass"
        case .powerPoint: return "rectangle.on.rectangle.angled.fill"
        }
    }

    var accentColor: String {
        switch self {
        case .default: return "blue"
        case .manualInput: return "teal"
        case .csvImport: return "indigo"
        case .pdfAnalysis: return "red"
        case .powerPoint: return "orange"
        }
    }
}

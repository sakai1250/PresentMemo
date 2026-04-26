import Foundation

struct SlideScore: Identifiable {
    let id = UUID()
    let slideIndex: Int
    let rawScore: Float
    let normalizedScore: Int
    let hasImage: Bool
    let hasText: Bool

    var tier: ScoreTier {
        switch normalizedScore {
        case 80...100: return .excellent
        case 60..<80:  return .good
        case 40..<60:  return .fair
        default:       return .poor
        }
    }

    /// CLIP cosine similarity (often around -0.05–0.30) -> 0–100
    static func normalize(_ raw: Float, min: Float = -0.05, max: Float = 0.30) -> Int {
        let clamped = Swift.min(Swift.max(raw, min), max)
        let linear = (clamped - min) / (max - min)
        // Slightly ease lower scores upward so near-miss explanations are not all zero.
        let curved = pow(Double(linear), 0.75)
        var score = Int(curved * 100.0)
        if raw > -0.08 {
            score = Swift.max(score, 10)
        }
        return score
    }
}

enum ScoreTier {
    case excellent, good, fair, poor

    var colorName: String {
        switch self {
        case .excellent: return "green"
        case .good:      return "blue"
        case .fair:      return "orange"
        case .poor:      return "red"
        }
    }

    var iconName: String {
        switch self {
        case .excellent: return "star.fill"
        case .good:      return "hand.thumbsup.fill"
        case .fair:      return "exclamationmark.triangle.fill"
        case .poor:      return "xmark.circle.fill"
        }
    }

    var labelKey: String {
        switch self {
        case .excellent: return "scoring.tier.excellent"
        case .good:      return "scoring.tier.good"
        case .fair:      return "scoring.tier.fair"
        case .poor:      return "scoring.tier.poor"
        }
    }
}

import Foundation

/// Preview zoom ladder for ⌘+ / ⌘-. Values off the ladder (after a pinch) snap to the next step.
nonisolated enum Zoom {
    static let steps: [Double] = [0.75, 0.9, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]
    static let storageKey = "previewZoom"

    static func larger(than value: Double) -> Double { steps.first { $0 > value + 0.001 } ?? steps.last! }
    static func smaller(than value: Double) -> Double { steps.last { $0 < value - 0.001 } ?? steps.first! }
}

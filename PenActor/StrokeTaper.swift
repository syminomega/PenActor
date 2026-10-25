import Foundation
import CoreGraphics

/// Entry is causal; ending is applied by the delayed event queue after lift-off.
struct StrokeTaperSettings: Codable, Equatable, Sendable {
    var entryEnabled = false
    var entryDistance = 12.0
    var entryDurationMS = 60.0
    var exitEnabled = false
    var exitDurationMS = 60.0

    var isValid: Bool {
        entryDistance.isFinite && (1...200).contains(entryDistance)
            && entryDurationMS.isFinite && (10...500).contains(entryDurationMS)
            && exitDurationMS.isFinite && (10...200).contains(exitDurationMS)
    }
}

struct StrokeTaperDiagnostic: Codable, Equatable, Sendable {
    let curvePressure: Double
    let tabletCurvePressure: Double
    let entryFactor: Double
    let exitFactor: Double
    let tabletExitFactor: Double
    let distance: Double
    let elapsedMS: Double
    let phase: String
}

/// State belongs to one physical stroke, shared by both pressure fields and event forms.
struct StrokeTaperState {
    private var startTime: Double?
    private var lastTime = 0.0
    private var lastLocation: CGPoint?
    private(set) var distance = 0.0
    private var entryProgress = 0.0

    mutating func apply(settings: StrokeTaperSettings, input: Double, tabletInput: Double,
                        curvePressure: Double, tabletCurvePressure: Double,
                        timestamp: Double, location: CGPoint, isEnding: Bool)
        -> (pressure: Double, tabletPressure: Double, diagnostic: StrokeTaperDiagnostic) {
        if startTime == nil { startTime = timestamp; lastTime = timestamp }
        let forward = timestamp >= lastTime
        if forward {
            if location.x.isFinite && location.y.isFinite {
                if let previous = lastLocation {
                    let step = hypot(location.x-previous.x, location.y-previous.y)
                    if step.isFinite { distance += step }
                }
                lastLocation = location
            }
            lastTime = timestamp
        }
        let elapsed = max(0, lastTime-(startTime ?? lastTime))*1000
        // Whichever arrives first finishes entry; the time limit lets stationary dots recover.
        entryProgress = max(entryProgress, min(1, max(distance/settings.entryDistance, elapsed/settings.entryDurationMS)))
        let entry = settings.entryEnabled ? Self.smoothstep(entryProgress) : 1
        let output = input <= 0 ? 0 : curvePressure*entry
        let tabletOutput = tabletInput <= 0 ? 0 : tabletCurvePressure*entry
        let phase = isEnding ? "抬笔 / 等待尾部修整" : settings.entryEnabled && entryProgress < 1 ? "入锋" : "正常"
        return (output, tabletOutput, .init(curvePressure: curvePressure, tabletCurvePressure: tabletCurvePressure,
            entryFactor: entry, exitFactor: 1, tabletExitFactor: 1, distance: distance, elapsedMS: elapsed, phase: phase))
    }

    private static func smoothstep(_ t: Double) -> Double { t*t*(3-2*t) }
}

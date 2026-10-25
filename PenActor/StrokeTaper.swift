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

struct TrajectorySmoothingSettings: Codable, Equatable, Sendable {
    var enabled = false
    /// 0 is exact passthrough; 1 favors stability. Independent of event frequency.
    var strength = 0.35
    var isValid: Bool { strength.isFinite && (0...1).contains(strength) }
}

struct TrajectoryPosition: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    init(_ point: CGPoint) { x = point.x; y = point.y }
    var point: CGPoint { CGPoint(x: x, y: y) }
}

struct TrajectorySmoothingDiagnostic: Codable, Equatable, Sendable {
    var enabled: Bool
    var strength: Double
    var inputTablet: TrajectoryPosition
    var outputTablet: TrajectoryPosition
}

/// One Euro filter, with one speed-dependent coefficient for both coordinate representations.
/// Screen points determine speed; tablet coordinates retain their own units and precision.
struct TrajectorySmoothingState {
    private var time: Double?
    private var raw = CGPoint.zero
    private var velocity = CGPoint.zero
    private(set) var screen = CGPoint.zero
    private(set) var tablet = CGPoint.zero
    var hasValue: Bool { time != nil }

    mutating func apply(screen input: CGPoint, tablet tabletInput: CGPoint, timestamp: Double,
                        settings: TrajectorySmoothingSettings, ending: Bool = false) -> (screen: CGPoint, tablet: CGPoint) {
        guard input.x.isFinite, input.y.isFinite, tabletInput.x.isFinite, tabletInput.y.isFinite, timestamp.isFinite else {
            return (input, tabletInput)
        }
        guard settings.enabled, settings.strength > 0 else { return (input, tabletInput) }
        if ending, time != nil { return (screen, tablet) }
        guard let previousTime = time else {
            time = timestamp; raw = input; screen = input; tablet = tabletInput
            return (screen, tablet)
        }
        let dt = timestamp-previousTime
        guard dt > 0 else { return (screen, tablet) }
        if dt > 0.25 {
            self = Self()
            return apply(screen: input, tablet: tabletInput, timestamp: timestamp, settings: settings)
        }
        func alpha(_ cutoff: Double) -> Double { 1 / (1 + 1 / (2 * .pi * cutoff * dt)) }
        let derivativeAlpha = alpha(1)
        velocity.x += derivativeAlpha * ((input.x-raw.x)/dt-velocity.x)
        velocity.y += derivativeAlpha * ((input.y-raw.y)/dt-velocity.y)
        let strength = settings.strength
        let minCutoff = 12 * pow(0.1, strength) // 12 ... 1.2 Hz
        let beta = 0.08 * (1-strength) + 0.005
        let a = alpha(minCutoff + beta * hypot(velocity.x, velocity.y))
        screen.x += a*(input.x-screen.x); screen.y += a*(input.y-screen.y)
        tablet.x += a*(tabletInput.x-tablet.x); tablet.y += a*(tabletInput.y-tablet.y)
        time = timestamp; raw = input
        return (screen, tablet)
    }
}

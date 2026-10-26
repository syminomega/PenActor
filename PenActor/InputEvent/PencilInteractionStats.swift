import Foundation

enum PencilDoubleTapSource: String, Codable {
    case appKit = "NSEvent.changeMode"
    case swiftUI = "SwiftUI"
}

enum PencilSqueezeStatus: String, Codable {
    case waiting = "尚未收到"
    case active = "正在挤压"
    case ended = "挤压已结束"
    case failed = "失败 / 取消"
    case interrupted = "监听停止 / 窗口失活，已中断"

    var label: String {
        switch self {
        case .waiting: String(localized: "Not received yet")
        case .active: String(localized: "Squeezing")
        case .ended: String(localized: "Squeeze ended")
        case .failed: String(localized: "Failed / canceled")
        case .interrupted: String(localized: "Interrupted: monitoring stopped or window lost focus")
        }
    }
}

struct PencilInteractionStats {
    private(set) var doubleTapCount = 0
    private(set) var lastDoubleTapAt: Date?
    private(set) var lastDoubleTapSource: PencilDoubleTapSource?
    private(set) var doubleTapPaired = false
    private var lastDoubleTapUptime: TimeInterval?
    private(set) var squeezeCount = 0
    private(set) var squeezeCompletedCount = 0
    private(set) var squeezeFailedCount = 0
    private(set) var squeezeStatus: PencilSqueezeStatus = .waiting
    private(set) var lastSqueezeAt: Date?

    mutating func doubleTap(source: PencilDoubleTapSource, uptime: TimeInterval, date: Date) {
        // SwiftUI and AppKit can report the same double tap. Pair one callback
        // from each source within 150 ms; never debounce repeated same-source taps.
        if let previous = lastDoubleTapUptime, source != lastDoubleTapSource,
           !doubleTapPaired, uptime >= previous, uptime - previous <= 0.15 {
            doubleTapPaired = true
            return
        }
        doubleTapCount += 1
        lastDoubleTapAt = date
        lastDoubleTapSource = source
        lastDoubleTapUptime = uptime
        doubleTapPaired = false
    }

    mutating func squeeze(_ status: PencilSqueezeStatus, date: Date) {
        guard status == .active || status == .ended || status == .failed else { return }
        // Ignore a late terminal callback from the gesture interrupted by stop/focus loss.
        if squeezeStatus == .interrupted && status != .active { return }
        let wasActive = squeezeStatus == .active
        if status == .active {
            if !wasActive { squeezeCount += 1 }
        } else {
            // A framework may deliver only the terminal callback.
            if !wasActive { squeezeCount += 1 }
            if status == .ended { squeezeCompletedCount += 1 }
            else { squeezeFailedCount += 1 }
        }
        squeezeStatus = status
        lastSqueezeAt = date
    }

    mutating func interrupt(date: Date) {
        lastDoubleTapUptime = nil
        if squeezeStatus == .active {
            squeezeStatus = .interrupted
            lastSqueezeAt = date
        }
    }
}

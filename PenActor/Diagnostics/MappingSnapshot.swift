import Foundation

struct MappingDiagnostic: Codable, Sendable, Equatable {
    let timestamp: Double
    let device: PenIdentity?
    let targetPID: Int32
    let targetBundleID: String?
    let profileID: UUID?
    let inputPressure: Double
    var outputPressure: Double
    let tabletInputPressure: Double
    var tabletOutputPressure: Double
    let reason: String
    var taper: StrokeTaperDiagnostic? = nil
    var delivery: String = "直接输出"
}

struct MappingSnapshot: Codable, Sendable, Equatable {
    var isRunning = false
    var isStarting = false
    var status = "映射已暂停"
    var modifiedEventCount: UInt64 = 0
    var diagnostics: [MappingDiagnostic] = []
    var activeProfiles: [PressureProfile] = []
    var bufferedEventCount = 0
    var defaults = MappingDefaults()
}


extension MappingSnapshot {
    var localizedStatus: String {
        NSLocalizedString(status, comment: "Mapping service status; raw status is stable in JSON logs.")
    }
}

extension MappingDiagnostic {
    var localizedReason: String {
        NSLocalizedString(reason, comment: "Pressure mapping result; raw reason is stable in JSON logs.")
    }
}

import Foundation

struct PressureProfile: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var device: PenIdentity
    var curve = PressureCurve.linear
    var targetBundleIDs: [String] = []
    var taper = StrokeTaperSettings()
    var usesDefaults = false
    /// nil identifies a legacy profile; an empty array is a new profile with no target applications.
    var applicationRules: [ApplicationPressureRule]?
    var effectiveTargetBundleIDs: [String] { applicationRules?.map(\.bundleID) ?? targetBundleIDs }

    init(id: UUID = UUID(), name: String, device: PenIdentity, curve: PressureCurve = .linear,
         targetBundleIDs: [String] = [], taper: StrokeTaperSettings = StrokeTaperSettings(), usesDefaults: Bool = false, applicationRules: [ApplicationPressureRule]? = nil) {
        self.id = id; self.name = name; self.device = device; self.curve = curve
        self.targetBundleIDs = targetBundleIDs; self.taper = taper; self.usesDefaults = usesDefaults
        self.applicationRules = applicationRules
    }
    private enum CodingKeys: String, CodingKey { case id, name, device, curve, targetBundleIDs, taper, usesDefaults, applicationRules }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        device = try container.decode(PenIdentity.self, forKey: .device)
        curve = try container.decode(PressureCurve.self, forKey: .curve)
        targetBundleIDs = try container.decode([String].self, forKey: .targetBundleIDs)
        taper = try container.decodeIfPresent(StrokeTaperSettings.self, forKey: .taper) ?? StrokeTaperSettings()
        usesDefaults = try container.decodeIfPresent(Bool.self, forKey: .usesDefaults) ?? false
        applicationRules = try container.decodeIfPresent([ApplicationPressureRule].self, forKey: .applicationRules)
    }
    var isValid: Bool { device.level != .session && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && curve.isValid && taper.isValid
        && (applicationRules.map { $0.count <= 256 && Set($0.map(\.bundleID)).count == $0.count && $0.allSatisfy(\.isValid) } ?? true)
        && targetBundleIDs.allSatisfy { !$0.isEmpty && $0.rangeOfCharacter(from: .whitespacesAndNewlines) == nil } }
}

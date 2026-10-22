import Foundation

struct PressureConfiguration: Codable, Equatable, Sendable {
    var curve = PressureCurve.linear
    var taper = StrokeTaperSettings()
    var isValid: Bool { curve.isValid && taper.isValid }
}

struct ApplicationPressureRule: Identifiable, Codable, Equatable, Sendable {
    enum Mode: String, CaseIterable, Codable, Sendable {
        case inherit, custom, passthrough
        var title: String {
            switch self { case .inherit: "继承设备默认"; case .custom: "单独覆盖"; case .passthrough: "不映射" }
        }
    }
    var id: String { bundleID }
    var bundleID: String
    var name: String
    var mode = Mode.inherit
    var configuration = PressureConfiguration()
    var isValid: Bool {
        !bundleID.isEmpty && bundleID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && configuration.isValid
    }
}

struct DevicePressureDefaults: Identifiable, Codable, Equatable, Sendable {
    var id: PenIdentity { device }
    var device: PenIdentity
    var name = ""
    var configuration = PressureConfiguration()
    var isValid: Bool { device.level != .session && name.count <= 128 && configuration.isValid }
}

struct MappingDefaults: Codable, Equatable, Sendable {
    var schemaVersion = 2
    // Read-only compatibility data: used only when migrating profiles created before 0.5.
    var global = PressureConfiguration()
    var applications: [ApplicationPressureRule] = []
    var devices: [DevicePressureDefaults] = []
    init() { }
    private enum CodingKeys: String, CodingKey { case schemaVersion, global, applications, devices }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        global = try c.decodeIfPresent(PressureConfiguration.self, forKey: .global) ?? PressureConfiguration()
        applications = try c.decodeIfPresent([ApplicationPressureRule].self, forKey: .applications) ?? []
        devices = try c.decodeIfPresent([DevicePressureDefaults].self, forKey: .devices) ?? []
    }
    var isValid: Bool {
        [1, 2].contains(schemaVersion) && global.isValid && applications.count <= 256
            && Set(applications.map(\.bundleID)).count == applications.count && applications.allSatisfy(\.isValid)
            && devices.count <= 256 && Set(devices.map(\.device)).count == devices.count && devices.allSatisfy(\.isValid)
    }
    func settings(for device: PenIdentity) -> DevicePressureDefaults {
        devices.first { $0.device == device } ?? DevicePressureDefaults(device: device)
    }
    /// A rule belongs to a profile of exactly one device. No other device's defaults can participate.
    func resolve(_ profile: PressureProfile, bundleID: String) -> PressureProfile? {
        if let rules = profile.applicationRules {
            guard let rule = rules.first(where: { $0.bundleID == bundleID }), rule.mode != .passthrough else { return nil }
            let configuration = rule.mode == .custom ? rule.configuration : settings(for: profile.device).configuration
            var result = profile; result.curve = configuration.curve; result.taper = configuration.taper
            return result
        }
        // Legacy resolver is retained solely for lossless migration and old diagnostic fixtures.
        let app = applications.first { $0.bundleID == bundleID }
        guard app?.mode != .passthrough else { return nil }
        guard profile.usesDefaults else { return profile }
        let configuration = app?.mode == .custom ? app!.configuration : global
        var result = profile; result.curve = configuration.curve; result.taper = configuration.taper
        return result
    }
    func migrating(_ profiles: [PressureProfile]) -> (defaults: MappingDefaults, profiles: [PressureProfile]) {
        var defaults = self; defaults.schemaVersion = 2
        var migrated = profiles
        for profile in profiles where !defaults.devices.contains(where: { $0.device == profile.device }) {
            // First saved profile seeds the device default. Per-app overrides preserve every other profile.
            let configuration = profile.applicationRules == nil && !profile.usesDefaults
                ? PressureConfiguration(curve: profile.curve, taper: profile.taper)
                : profile.applicationRules == nil ? global : PressureConfiguration()
            defaults.devices.append(DevicePressureDefaults(device: profile.device, configuration: configuration))
        }
        for i in migrated.indices where migrated[i].applicationRules == nil {
            let old = profiles[i]
            let base = defaults.settings(for: old.device).configuration
            var seen = Set<String>()
            migrated[i].applicationRules = old.targetBundleIDs.filter { seen.insert($0).inserted }.map { id in
                let resolved = resolve(old, bundleID: id)
                let configuration = resolved.map { PressureConfiguration(curve: $0.curve, taper: $0.taper) } ?? base
                var rule = ApplicationPressureRule(bundleID: id, name: applications.first { $0.bundleID == id }?.name ?? id)
                rule.mode = resolved == nil ? .passthrough : configuration == base ? .inherit : .custom
                rule.configuration = configuration
                return rule
            }
        }
        return (defaults, migrated)
    }
}

struct MappingDefaultsRepository {
    let url: URL
    init(url: URL = URL.applicationSupportDirectory.appending(path: "PenActor/defaults.json")) { self.url = url }
    func load() throws -> MappingDefaults {
        guard FileManager.default.fileExists(atPath: url.path) else { return MappingDefaults() }
        let result = try JSONDecoder().decode(MappingDefaults.self, from: Data(contentsOf: url))
        guard result.isValid else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
    func save(_ value: MappingDefaults) throws {
        guard value.isValid else { throw CocoaError(.fileWriteInvalidFileName) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

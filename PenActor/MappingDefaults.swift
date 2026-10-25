import Foundation

struct PressureConfiguration: Codable, Equatable, Sendable {
    var curve = PressureCurve.linear
    var taper = StrokeTaperSettings()
    var isValid: Bool { curve.isValid && taper.isValid }
    init(curve: PressureCurve = .linear, taper: StrokeTaperSettings = .init()) {
        self.curve = curve; self.taper = taper
    }
    private enum CodingKeys: String, CodingKey { case curve, taper }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        curve = try c.decode(PressureCurve.self, forKey: .curve)
        taper = try c.decodeIfPresent(StrokeTaperSettings.self, forKey: .taper) ?? .init()
    }
}

enum ConfigurationComponent: String, CaseIterable, Codable, Sendable {
    case curve, entry, exit
    var title: String {
        switch self { case .curve: "压力曲线"; case .entry: "入锋"; case .exit: "出锋" }
    }
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
    // nil retains pre-v5 custom semantics until migration; new UI always writes an explicit set.
    var overrides: Set<ConfigurationComponent>?
    init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
    private enum CodingKeys: String, CodingKey { case bundleID, name, mode, configuration, overrides }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try c.decode(String.self, forKey: .bundleID)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .inherit
        configuration = try c.decodeIfPresent(PressureConfiguration.self, forKey: .configuration) ?? .init()
        if let fields = try c.decodeIfPresent([String].self, forKey: .overrides) {
            overrides = []
            for field in fields {
                // Compatibility only: discard the removed experimental component.
                if field == "smoothing" { continue }
                guard let component = ConfigurationComponent(rawValue: field) else {
                    throw DecodingError.dataCorruptedError(forKey: .overrides, in: c, debugDescription: "Unknown component: \(field)")
                }
                overrides?.insert(component)
            }
            if mode == .custom && overrides?.isEmpty == true { mode = .inherit }
        }
    }
    var effectiveOverrides: Set<ConfigurationComponent> {
        mode == .custom ? overrides ?? [.curve, .entry, .exit] : []
    }
    var summary: String {
        if mode == .passthrough { return "不映射" }
        let custom = ConfigurationComponent.allCases.filter { effectiveOverrides.contains($0) }.map(\.title)
        return custom.isEmpty ? "全部继承设备默认" : "单独设置：" + custom.joined(separator: "、") + "；其余继承"
    }
    func resolved(base: PressureConfiguration) -> PressureConfiguration {
        var value = base
        for component in effectiveOverrides { value.copy(component, from: configuration) }
        return value
    }
    mutating func setOverride(_ component: ConfigurationComponent, enabled: Bool, base: PressureConfiguration) {
        var fields = effectiveOverrides
        if enabled { configuration.copy(component, from: resolved(base: base)); fields.insert(component) }
        else { fields.remove(component) }
        overrides = fields; mode = fields.isEmpty ? .inherit : .custom
    }
    var isValid: Bool {
        !bundleID.isEmpty && bundleID.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && configuration.isValid
    }
}

extension PressureConfiguration {
    mutating func copy(_ component: ConfigurationComponent, from other: Self) {
        switch component {
        case .curve: curve = other.curve
        case .entry:
            taper.entryEnabled = other.taper.entryEnabled; taper.entryDistance = other.taper.entryDistance
            taper.entryDurationMS = other.taper.entryDurationMS
        case .exit: taper.exitEnabled = other.taper.exitEnabled; taper.exitDurationMS = other.taper.exitDurationMS
        }
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
    var schemaVersion = 4
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
        [1, 2, 3, 4].contains(schemaVersion) && global.isValid && applications.count <= 256
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
            let configuration = rule.resolved(base: settings(for: profile.device).configuration)
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
        var defaults = self; defaults.schemaVersion = 4
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
        for i in migrated.indices {
            guard let rules = migrated[i].applicationRules else { continue }
            migrated[i].applicationRules = rules.map { old in
                var rule = old
                if rule.overrides == nil { rule.overrides = rule.effectiveOverrides }
                if rule.mode == .custom && rule.overrides?.isEmpty == true { rule.mode = .inherit }
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

import Foundation

enum ConfigurationComponent: String, CaseIterable, Codable, Sendable {
    case curve, entry, exit
    var title: String {
        switch self { case .curve: String(localized: "压力曲线"); case .entry: String(localized: "入锋"); case .exit: String(localized: "出锋") }
    }
}

struct ApplicationPressureRule: Identifiable, Codable, Equatable, Sendable {
    enum Mode: String, CaseIterable, Codable, Sendable {
        case inherit, custom, passthrough
        var title: String {
            switch self { case .inherit: String(localized: "继承设备默认"); case .custom: String(localized: "单独覆盖"); case .passthrough: String(localized: "不映射") }
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
        if mode == .passthrough { return String(localized: "不映射") }
        let custom = ConfigurationComponent.allCases.filter { effectiveOverrides.contains($0) }.map(\.title)
        return custom.isEmpty ? String(localized: "全部继承设备默认") : String(localized: "单独设置：\(ListFormatter.localizedString(byJoining: custom))；其余继承")
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

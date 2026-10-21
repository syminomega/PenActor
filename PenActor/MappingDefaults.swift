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
            switch self { case .inherit: "沿用全局默认"; case .custom: "应用自定义"; case .passthrough: "此应用透传" }
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

struct MappingDefaults: Codable, Equatable, Sendable {
    var schemaVersion = 1
    var global = PressureConfiguration()
    var applications: [ApplicationPressureRule] = []
    var isValid: Bool {
        schemaVersion == 1 && global.isValid && applications.count <= 256
            && Set(applications.map(\.bundleID)).count == applications.count && applications.allSatisfy(\.isValid)
    }
    /// Device membership and target-app filtering happen before resolution. Defaults never opt in a device.
    func resolve(_ profile: PressureProfile, bundleID: String) -> PressureProfile? {
        let app = applications.first { $0.bundleID == bundleID }
        guard app?.mode != .passthrough else { return nil }
        guard profile.usesDefaults else { return profile }
        let configuration = app?.mode == .custom ? app!.configuration : global
        var result = profile
        result.curve = configuration.curve; result.taper = configuration.taper
        return result
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

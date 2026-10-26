import Foundation

struct PressureProfileFile: Codable {
    var schemaVersion = 6
    var profiles: [PressureProfile]
}

/// Validates supported schemas before use and replaces saved JSON atomically.
struct PressureProfileRepository {
    let url: URL
    init(url: URL = URL.applicationSupportDirectory.appending(path: "PenActor/profiles.json")) { self.url = url }
    func load() throws -> [PressureProfile] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try JSONDecoder().decode(PressureProfileFile.self, from: Data(contentsOf: url))
        guard [1, 2, 3, 4, 5, 6].contains(file.schemaVersion), file.profiles.count <= 256,
              Set(file.profiles.map(\.id)).count == file.profiles.count,
              file.profiles.allSatisfy(\.isValid) else { throw CocoaError(.fileReadCorruptFile) }
        return file.profiles
    }
    func needsUpgrade() throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let file = try JSONDecoder().decode(PressureProfileFile.self, from: Data(contentsOf: url))
        return file.schemaVersion != PressureProfileFile(profiles: []).schemaVersion
    }
    func save(_ profiles: [PressureProfile]) throws {
        guard profiles.count <= 256, Set(profiles.map(\.id)).count == profiles.count, profiles.allSatisfy(\.isValid) else { throw CocoaError(.fileWriteInvalidFileName) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(PressureProfileFile(profiles: profiles))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

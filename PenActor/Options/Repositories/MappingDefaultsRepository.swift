import Foundation

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

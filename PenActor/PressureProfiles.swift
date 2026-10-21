import Foundation

struct PressurePoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}

struct PressureCurve: Codable, Equatable, Sendable {
    var points: [PressurePoint]
    static let linear = Self(points: [.init(x: 0, y: 0), .init(x: 1, y: 1)])
    static let light = Self(points: [.init(x: 0, y: 0), .init(x: 0.25, y: 0.5), .init(x: 0.5, y: 0.8), .init(x: 1, y: 1)])
    var isValid: Bool {
        guard (2...32).contains(points.count), points.first == PressurePoint(x: 0, y: 0),
              points.last == PressurePoint(x: 1, y: 1) else { return false }
        return points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }
            && zip(points, points.dropFirst()).allSatisfy { $0.x < $1.x && $0.y <= $1.y }
    }
    func map(_ input: Double) -> Double {
        guard input.isFinite else { return 0 }
        let x = min(1, max(0, input))
        guard isValid, x > 0, x < 1 else { return x }
        // Weighted harmonic tangents (PCHIP) preserve monotonicity and flat segments.
        let n = points.count
        let h = (0..<n-1).map { points[$0+1].x - points[$0].x }
        let d = (0..<n-1).map { (points[$0+1].y - points[$0].y) / h[$0] }
        var m = Array(repeating: 0.0, count: n)
        m[0] = d[0]; m[n-1] = d[n-2]
        if n > 2 {
            for i in 1..<n-1 where d[i-1] > 0 && d[i] > 0 {
                let a = 2*h[i]+h[i-1], b = h[i]+2*h[i-1]
                m[i] = (a+b)/(a/d[i-1]+b/d[i])
            }
        }
        let i = (0..<n-1).first { x <= points[$0+1].x } ?? n-2
        let t = (x-points[i].x)/h[i], t2 = t*t, t3 = t*t*t
        let y = (2*t3-3*t2+1)*points[i].y + (t3-2*t2+t)*h[i]*m[i]
            + (-2*t3+3*t2)*points[i+1].y + (t3-t2)*h[i]*m[i+1]
        return min(points[i+1].y, max(points[i].y, y))
    }
}

struct PressureProfile: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var device: PenIdentity
    var curve = PressureCurve.linear
    var targetBundleIDs: [String] = []
    var isValid: Bool { device.level != .session && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && curve.isValid && targetBundleIDs.allSatisfy { !$0.isEmpty && $0.rangeOfCharacter(from: .whitespacesAndNewlines) == nil } }
}

struct PressureProfileFile: Codable {
    var schemaVersion = 1
    var profiles: [PressureProfile]
}

struct PressureProfileRepository {
    let url: URL
    init(url: URL = URL.applicationSupportDirectory.appending(path: "PenActor/profiles.json")) { self.url = url }
    func load() throws -> [PressureProfile] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try JSONDecoder().decode(PressureProfileFile.self, from: Data(contentsOf: url))
        guard file.schemaVersion == 1, file.profiles.count <= 256,
              Set(file.profiles.map(\.id)).count == file.profiles.count,
              file.profiles.allSatisfy(\.isValid) else { throw CocoaError(.fileReadCorruptFile) }
        return file.profiles
    }
    func save(_ profiles: [PressureProfile]) throws {
        guard profiles.count <= 256, Set(profiles.map(\.id)).count == profiles.count, profiles.allSatisfy(\.isValid) else { throw CocoaError(.fileWriteInvalidFileName) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(PressureProfileFile(profiles: profiles))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

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

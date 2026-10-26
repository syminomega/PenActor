import Foundation

/// A draft is dirty only when its values differ, never merely because a field sent a setter.
struct DeviceProfileDraftState {
    var device: DevicePressureDefaults?
    var profile: PressureProfile?
    private var savedDevice: DevicePressureDefaults?
    private var savedProfile: PressureProfile?
    var hasChanges: Bool { device != savedDevice || profile != savedProfile }
    mutating func load(device: DevicePressureDefaults?, profile: PressureProfile?) {
        self.device = device; self.profile = profile
        savedDevice = device; savedProfile = profile
    }
    mutating func setDeviceName(_ name: String, for identity: PenIdentity) {
        guard device?.device == identity else { return }
        device?.name = name
    }
    mutating func setProfileName(_ name: String, for id: UUID?) {
        guard let id, profile?.id == id else { return }
        profile?.name = name
    }
    mutating func didSaveDevice(_ value: DevicePressureDefaults) { savedDevice = value }
    mutating func didSaveProfile(_ value: PressureProfile) { savedProfile = value }
}

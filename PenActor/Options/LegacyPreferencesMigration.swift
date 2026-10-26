import Foundation

/// Preserve app preferences when moving to dev.SyminStudio.PenActor; pressure JSON stays in the same folder.
enum LegacyPreferencesMigration {
    static let marker = "didMigrateLegacyBundlePreferences"
    static func migrate(legacy: [String: Any], into preferences: UserDefaults) {
        guard !preferences.bool(forKey: marker) else { return }
        for key in ["startMonitoringOnLaunch", "showSettingsOnLaunch", "automaticallySwitchDevices", "NSWindow Frame PenActorCompactPreferences"] {
            if preferences.object(forKey: key) == nil, let value = legacy[key] { preferences.set(value, forKey: key) }
        }
        preferences.set(true, forKey: marker)
    }
}

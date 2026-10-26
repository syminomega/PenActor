import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PressureMappingTests {
    @MainActor func testPrivacySettingsNavigationUsesCorrectPagesAndFallback() {
        for pane in [PrivacySettingsPane.inputMonitoring, .accessibility] {
            var opened: [URL] = []
            let navigator = PrivacySettingsNavigator(openURL: { opened.append($0); return true })
            XCTAssertTrue(navigator.open(pane))
            XCTAssertEqual(opened.count, 1)
            XCTAssertEqual(opened.first?.query, pane == .inputMonitoring ? "Privacy_ListenEvent" : "Privacy_Accessibility")
            XCTAssertEqual(opened.first?.scheme, "x-apple.systempreferences")
        }
        var opened: [URL] = []
        let fallback = PrivacySettingsNavigator(openURL: { opened.append($0); return opened.count == 2 })
        XCTAssertTrue(fallback.open(.inputMonitoring))
        XCTAssertEqual(opened.count, 2)
        XCTAssertNil(opened.last?.query)
        let unavailable = PrivacySettingsNavigator(openURL: { _ in false })
        XCTAssertFalse(unavailable.open(.accessibility))
    }

    func testLegacyBundlePreferencesMigrateOnceWithoutOverwritingNewSettings() throws {
        let suite = "PenActorTests." + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "showSettingsOnLaunch")
        let legacy: [String: Any] = ["showSettingsOnLaunch": false, "automaticallySwitchDevices": false,
            "touchBlockingTargets": ["test.app"], "unrelatedKey": "ignore"]
        LegacyPreferencesMigration.migrate(legacy: legacy, into: preferences)
        XCTAssertTrue(preferences.bool(forKey: "showSettingsOnLaunch"))
        XCTAssertEqual(preferences.object(forKey: "automaticallySwitchDevices") as? Bool, false)
        XCTAssertNil(preferences.stringArray(forKey: "touchBlockingTargets"))
        XCTAssertNil(preferences.object(forKey: "unrelatedKey"))
        preferences.removeObject(forKey: "automaticallySwitchDevices")
        LegacyPreferencesMigration.migrate(legacy: legacy, into: preferences)
        XCTAssertNil(preferences.object(forKey: "automaticallySwitchDevices"))
    }

    func testEditorDraftIgnoresNoOpCallbacksAndRestoredValues() {
        var state = DeviceProfileDraftState()
        let settings = DevicePressureDefaults(device: identity, name: "Pencil")
        let p = deviceProfile()
        state.load(device: settings, profile: p)
        state.setDeviceName("Pencil", for: identity)
        state.setProfileName(p.name, for: p.id)
        XCTAssertFalse(state.hasChanges)
        state.setDeviceName("Changed", for: identity); XCTAssertTrue(state.hasChanges)
        state.setDeviceName("Pencil", for: identity); XCTAssertFalse(state.hasChanges)
        state.profile?.applicationRules?[0].mode = .custom; XCTAssertTrue(state.hasChanges)
        state.profile = p; XCTAssertFalse(state.hasChanges)
        state.device?.configuration.curve = .light; XCTAssertTrue(state.hasChanges)
    }

    func testEditorDraftRejectsLateCallbacksAfterSwitchingDevicesAndProfiles() {
        var state = DeviceProfileDraftState()
        let oldProfile = deviceProfile()
        let other = PenIdentity(key: "v1:tool:56a:123:pen", level: .uniqueTool)
        let currentProfile = deviceProfile(other)
        let settings = DevicePressureDefaults(device: other, name: "Wacom")
        state.load(device: settings, profile: currentProfile)
        state.setDeviceName("Old pencil field editor", for: identity)
        state.setProfileName("Old profile field editor", for: oldProfile.id)
        XCTAssertEqual(state.device, settings)
        XCTAssertEqual(state.profile, currentProfile)
        XCTAssertFalse(state.hasChanges)
    }

    func testSavingDeviceNameDoesNotClearUnsavedCurveOrProfileChanges() throws {
        var state = DeviceProfileDraftState()
        let settings = DevicePressureDefaults(device: identity, name: "Pencil")
        let p = deviceProfile()
        state.load(device: settings, profile: p)
        state.device?.configuration.curve = .light
        state.setDeviceName("My Pencil", for: identity)
        state.profile?.name = "Edited profile"
        var savedName = settings; savedName.name = "My Pencil"
        state.didSaveDevice(savedName)
        XCTAssertTrue(state.hasChanges)
        state.didSaveDevice(try XCTUnwrap(state.device))
        XCTAssertTrue(state.hasChanges, "Saving the device must not discard unsaved profile changes")
        state.didSaveProfile(try XCTUnwrap(state.profile))
        XCTAssertFalse(state.hasChanges)
    }
}

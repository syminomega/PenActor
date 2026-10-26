import XCTest
import AppKit
import SwiftUI
@testable import PenActor

extension PressureMappingTests {
    func testDefaultsResolutionAndApplicationPassthroughPriority() throws {
        var defaults = MappingDefaults()
        defaults.global.curve = .light
        var p = profile(curve: .linear)
        XCTAssertEqual(defaults.resolve(p, bundleID: "com.adobe.Photoshop")?.curve, .linear)
        p.usesDefaults = true
        XCTAssertEqual(defaults.resolve(p, bundleID: "com.adobe.Photoshop")?.curve, .light)
        var rule = ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "Photoshop")
        rule.mode = .custom
        rule.configuration.taper.entryEnabled = true
        defaults.applications = [rule]
        XCTAssertEqual(defaults.resolve(p, bundleID: rule.bundleID)?.curve, .linear)
        XCTAssertTrue(try XCTUnwrap(defaults.resolve(p, bundleID: rule.bundleID)).taper.entryEnabled)
        XCTAssertEqual(defaults.resolve(p, bundleID: "other.app")?.curve, .light)
        p.usesDefaults = false
        XCTAssertFalse(try XCTUnwrap(defaults.resolve(p, bundleID: rule.bundleID)).taper.entryEnabled)
        defaults.applications[0].mode = .passthrough
        XCTAssertNil(defaults.resolve(p, bundleID: rule.bundleID))
    }

    func testDefaultsAreLatchedAndNeverOptInUnknownHardwareOrTargets() throws {
        var p = profile(curve: .linear); p.usesDefaults = true
        var m = processor(p); m.defaults.global.curve = .light
        m.process(try proximity())
        let first = try point(0.5); m.process(first)
        XCTAssertEqual(first.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        m.defaults.global.curve = .linear
        let held = try point(0.5); m.process(held)
        XCTAssertEqual(held.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        m.process(try point(0))
        let next = try point(0.5); m.process(next)
        XCTAssertEqual(next.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        m.process(try point(0)); m.defaults.global.curve = .light
        let other = try point(0.5, pid: 43); m.process(other)
        XCTAssertEqual(other.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        m.process(try proximity(id: 18, vendor: 1386))
        let wacom = try point(0.5, id: 18); m.process(wacom)
        XCTAssertEqual(wacom.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
    }

    func testApplicationPassthroughChangeWaitsForNextStroke() throws {
        var m = processor(); m.process(try proximity()); m.process(try point(0.5))
        var rule = ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "Photoshop")
        rule.mode = .passthrough; m.defaults.applications = [rule]
        let held = try point(0.5); m.process(held)
        XCTAssertEqual(held.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        m.process(try point(0)); let next = try point(0.5); m.process(next)
        XCTAssertEqual(next.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        XCTAssertNil(m.snapshot.diagnostics.last?.profileID)
    }

    func testDefaultsRepositoryRoundtripAndInvalidDataDoNotOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = MappingDefaultsRepository(url: root.appending(path: "defaults.json"))
        XCTAssertEqual(try repo.load(), MappingDefaults())
        var defaults = MappingDefaults(); defaults.global.curve = .light
        defaults.applications = [.init(bundleID: "com.adobe.Photoshop", name: "Photoshop")]
        try repo.save(defaults)
        XCTAssertEqual(try repo.load(), defaults)
        var invalid = defaults; invalid.applications.append(invalid.applications[0])
        XCTAssertThrowsError(try repo.save(invalid))
        XCTAssertEqual(try repo.load(), defaults)
        invalid = defaults; invalid.schemaVersion = 99
        try JSONEncoder().encode(invalid).write(to: repo.url)
        XCTAssertThrowsError(try repo.load())
    }

    func testDeviceDefaultsAreIndependentAndOverridesStayWithinProfile() throws {
        let wacom = PenIdentity(key: "v1:model:56a:129a:0:pen", level: .model)
        var defaults = MappingDefaults()
        defaults.global.curve = .light // Retired global fields cannot affect new-style profiles.
        var retiredRule = ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "retired")
        retiredRule.mode = .passthrough; defaults.applications = [retiredRule]
        defaults.devices = [.init(device: identity, name: "我的 Pencil", configuration: .init(curve: .light)), .init(device: wacom, name: "我的 Wacom")]
        var pencil = deviceProfile()
        let tablet = deviceProfile(wacom)
        XCTAssertEqual(defaults.resolve(pencil, bundleID: "com.adobe.Photoshop")?.curve, .light)
        XCTAssertEqual(defaults.resolve(tablet, bundleID: "com.adobe.Photoshop")?.curve, .linear)
        pencil.applicationRules?[0].mode = .custom
        pencil.applicationRules?[0].configuration.taper.entryEnabled = true
        XCTAssertEqual(defaults.resolve(pencil, bundleID: "com.adobe.Photoshop")?.curve, .linear)
        XCTAssertTrue(try XCTUnwrap(defaults.resolve(pencil, bundleID: "com.adobe.Photoshop")).taper.entryEnabled)
        XCTAssertEqual(defaults.resolve(pencil, bundleID: "other.app")?.curve, .light)
        XCTAssertFalse(try XCTUnwrap(defaults.resolve(tablet, bundleID: "com.adobe.Photoshop")).taper.entryEnabled)
        pencil.applicationRules?[0].mode = .passthrough
        XCTAssertNil(defaults.resolve(pencil, bundleID: "com.adobe.Photoshop"))
        XCTAssertNotNil(defaults.resolve(tablet, bundleID: "com.adobe.Photoshop"))
        XCTAssertNil(defaults.resolve(pencil, bundleID: "unlisted.app"))
    }

    func testDeviceDefaultChangesLatchUntilNextStrokeAndDoNotChangeOverrides() throws {
        var p = deviceProfile()
        p.applicationRules?[1].mode = .custom
        p.applicationRules?[1].configuration.curve = .light
        var m = processor(p)
        m.defaults.devices = [.init(device: identity, configuration: .init(curve: .light))]
        m.process(try proximity())
        let first = try point(0.5); m.process(first)
        XCTAssertEqual(first.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        m.defaults.devices[0].configuration.curve = .linear
        let held = try point(0.5); m.process(held)
        XCTAssertEqual(held.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        m.process(try point(0))
        let next = try point(0.5); m.process(next)
        XCTAssertEqual(next.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        m.process(try point(0))
        let override = try point(0.5, pid: 43); m.process(override)
        XCTAssertEqual(override.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
    }

    func testQuartzSeparatesDevicesWithSameTargetAndKeepsUnconfiguredDevicesUntouched() throws {
        let wacom = PenIdentity(key: "v1:model:56a:129a:0:pen", level: .model)
        var m = processor(deviceProfile())
        m.setProfiles([deviceProfile(), deviceProfile(wacom)])
        m.defaults.devices = [.init(device: identity, configuration: .init(curve: .light)), .init(device: wacom)]
        m.process(try proximity()); m.process(try proximity(id: 18, vendor: 1386))
        let pencil = try point(0.5), tablet = try point(0.5, id: 18)
        m.process(pencil); m.process(tablet)
        XCTAssertEqual(pencil.getDoubleValueField(.tabletEventPointPressure), 0.8, accuracy: 0.005)
        XCTAssertEqual(tablet.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
        m.process(try proximity(id: 19, vendor: 99))
        let unknown = try point(0.5, id: 19); m.process(unknown)
        XCTAssertEqual(unknown.getDoubleValueField(.tabletEventPointPressure), 0.5, accuracy: 0.005)
    }

    func testMigrationPreservesPerApplicationBehaviorAndIsRepeatable() throws {
        var defaults = MappingDefaults(); defaults.schemaVersion = 1; defaults.global.curve = .linear
        var ps = ApplicationPressureRule(bundleID: "com.adobe.Photoshop", name: "Photoshop")
        ps.mode = .custom; ps.configuration.curve = .light; ps.configuration.taper.entryEnabled = true
        var blocked = ApplicationPressureRule(bundleID: "other.app", name: "excluded"); blocked.mode = .passthrough
        defaults.applications = [ps, blocked]
        var a = profile(); a.targetBundleIDs.append("other.app")
        var b = profile(curve: .linear); b.targetBundleIDs.append("other.app")
        var c = profile(); c.device = PenIdentity(key: "another-device", level: .uniqueTool)
        c.usesDefaults = true; c.targetBundleIDs.append("other.app")
        let old = [a, b, c]
        let migration = defaults.migrating(old)
        XCTAssertEqual(migration.defaults.devices.count, 2)
        XCTAssertEqual(migration.profiles.map(\.id), old.map(\.id))
        for (before, after) in zip(old, migration.profiles) {
            XCTAssertEqual(after.effectiveTargetBundleIDs, before.targetBundleIDs)
            for id in before.targetBundleIDs {
                let original = defaults.resolve(before, bundleID: id)
                let resolved = migration.defaults.resolve(after, bundleID: id)
                XCTAssertEqual(original?.curve, resolved?.curve)
                XCTAssertEqual(original?.taper, resolved?.taper)
            }
        }
        XCTAssertEqual(migration.profiles[1].applicationRules?.first?.mode, .custom)
        let again = migration.defaults.migrating(migration.profiles)
        XCTAssertEqual(again.defaults, migration.defaults); XCTAssertEqual(again.profiles, migration.profiles)
        // Simulate interruption after defaults.json saved, but before profiles.json replaced.
        XCTAssertEqual(migration.defaults.migrating(old).profiles, migration.profiles)
    }

    @MainActor func testMonitorMigrationBacksUpOriginalsAndDeviceRenamePersistsAfterProfileDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        let defaultsRepo = MappingDefaultsRepository(url: root.appending(path: "defaults.json"))
        try repo.save([profile()]); try defaultsRepo.save(MappingDefaults())
        let original = try Data(contentsOf: repo.url)
        let monitor = PenMonitor(profileRepository: repo)
        XCTAssertNotNil(monitor.profiles.first?.applicationRules)
        let folders = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Backups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(folders.count, 1)
        XCTAssertEqual(try Data(contentsOf: folders[0].appending(path: "profiles.json")), original)
        var settings = monitor.mappingDefaults.settings(for: identity); settings.name = "我的笔"
        XCTAssertTrue(monitor.saveDeviceSettings(settings))
        let id = try XCTUnwrap(monitor.profiles.first?.id)
        monitor.deleteProfile(id)
        let restored = PenMonitor(profileRepository: repo)
        XCTAssertTrue(restored.profiles.isEmpty)
        XCTAssertEqual(restored.deviceDisplayName(identity), "我的笔")
        XCTAssertEqual(restored.mappingDefaults.settings(for: identity).configuration.curve, .light)
        XCTAssertTrue(restored.enabledProfileIDs.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root.appending(path: "Backups"), includingPropertiesForKeys: nil).count, 1)
    }

    func testDeviceScopedValidationRejectsDuplicateApplicationsAndDevices() {
        var p = deviceProfile()
        let duplicate = p.applicationRules![0]; p.applicationRules?.append(duplicate); XCTAssertFalse(p.isValid)
        p = deviceProfile(); p.applicationRules?[0].configuration.curve.points = []; XCTAssertFalse(p.isValid)
        var defaults = MappingDefaults()
        defaults.devices = [.init(device: identity), .init(device: identity)]; XCTAssertFalse(defaults.isValid)
        defaults.devices = [.init(device: .session(17))]; XCTAssertFalse(defaults.isValid)
    }

    @MainActor func testCorruptDefaultsBlockMigrationSavingAndDeletion() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        try repo.save([profile()])
        let original = try Data(contentsOf: repo.url)
        let bad = root.appending(path: "defaults.json")
        try Data("invalid".utf8).write(to: bad)
        let monitor = PenMonitor(profileRepository: repo)
        XCTAssertNotNil(monitor.profileError)
        XCTAssertFalse(monitor.saveProfile(deviceProfile()))
        XCTAssertFalse(monitor.saveDefaults(MappingDefaults()))
        monitor.deleteProfile(try XCTUnwrap(monitor.profiles.first?.id))
        XCTAssertEqual(try Data(contentsOf: repo.url), original)
        XCTAssertEqual(try Data(contentsOf: bad), Data("invalid".utf8))
    }

    func testProfilePersistenceAndInvalidFileIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let repo = PressureProfileRepository(url:root.appending(path:"profiles.json"))
        XCTAssertTrue(try repo.load().isEmpty)
        try repo.save([profile()]); XCTAssertEqual(try repo.load().first?.curve,.light)
        let original = try Data(contentsOf:repo.url); var invalid = profile(); invalid.device = .session(1)
        XCTAssertThrowsError(try repo.save([invalid])); XCTAssertEqual(try Data(contentsOf:repo.url),original)
        try Data("{\"schemaVersion\":99,\"profiles\":[]}".utf8).write(to:repo.url)
        XCTAssertThrowsError(try repo.load())
    }

    func testLegacyProfilesPreserveCustomValuesAndSaveAsVersionSix() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = PressureProfileRepository(url: root.appending(path: "profiles.json"))
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile())) as? [String: Any])
        old.removeValue(forKey: "taper"); old.removeValue(forKey: "usesDefaults")
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "profiles": [old]]).write(to: repo.url)
        let loaded = try repo.load()
        XCTAssertEqual(loaded.first?.taper, StrokeTaperSettings())
        XCTAssertEqual(loaded.first?.usesDefaults, false)
        XCTAssertEqual(loaded.first?.curve, .light)
        try repo.save(loaded)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: repo.url)) as? [String: Any])
        XCTAssertEqual(saved["schemaVersion"] as? Int, 6)
    }

    func testPressureComponentsStillInheritIndependently() throws {
        var base = PressureConfiguration(curve: .light)
        base.taper.entryEnabled = true; base.taper.exitEnabled = true
        var rule = ApplicationPressureRule(bundleID: "ps",name: "Photoshop")
        rule.setOverride(.entry,enabled: true,base: base)
        XCTAssertEqual(rule.configuration.taper.entryEnabled,true)
        rule.configuration.taper.entryDurationMS = 90
        base.curve = .linear; base.taper.entryDurationMS = 120; base.taper.exitDurationMS = 100
        XCTAssertEqual(rule.resolved(base: base).curve,.linear)
        XCTAssertEqual(rule.resolved(base: base).taper.entryDurationMS,90)
        XCTAssertEqual(rule.resolved(base: base).taper.exitDurationMS,100)
        rule.setOverride(.exit,enabled: true,base: base);rule.configuration.taper.exitEnabled = false
        XCTAssertFalse(rule.resolved(base: base).taper.exitEnabled)
        rule.setOverride(.entry,enabled: false,base: base)
        XCTAssertEqual(rule.resolved(base: base).taper.entryDurationMS,120)
        rule.setOverride(.curve,enabled: true,base: base);rule.configuration.curve = .light
        XCTAssertEqual(rule.resolved(base: base).curve,.light)
        XCTAssertEqual(ConfigurationComponent.allCases,[.curve,.entry,.exit])
    }

    @MainActor func testRemovedExperimentalFieldsMigrateWithBackupAndPreservePressureSettings() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true)
        var p = deviceProfile()
        p.applicationRules?[0].mode = .custom
        p.applicationRules?[1].mode = .custom
        p.applicationRules?[1].configuration.curve = .light
        p.applicationRules?[1].configuration.taper.entryDurationMS = 125
        var rawProfile = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any])
        rawProfile["smoothing"] = ["enabled": true,"strength": 0.35]
        var rules = rawProfile["applicationRules"] as! [[String: Any]]
        for i in rules.indices {
            rules[i]["overrides"] = i == 0 ? ["smoothing"] : ["smoothing","curve","entry"]
            var c = rules[i]["configuration"] as! [String: Any]
            c["smoothing"] = ["enabled": true,"strength": 0.7];rules[i]["configuration"] = c
        }
        rawProfile["applicationRules"] = rules
        let originalProfile = try JSONSerialization.data(withJSONObject: ["schemaVersion":5,"profiles":[rawProfile]])
        try originalProfile.write(to: root.appending(path:"profiles.json"))
        var defaults = MappingDefaults(); defaults.schemaVersion = 3
        defaults.devices = [.init(device: identity,name: "我的 Pencil",configuration: .init(curve: .light,taper: .init(exitEnabled:true)))]
        var rawDefaults = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(defaults)) as? [String: Any])
        var devices = rawDefaults["devices"] as! [[String:Any]]
        var c = devices[0]["configuration"] as! [String:Any]
        c["smoothing"] = ["enabled": true,"strength": 1];devices[0]["configuration"] = c;rawDefaults["devices"] = devices
        let originalDefaults = try JSONSerialization.data(withJSONObject:rawDefaults)
        try originalDefaults.write(to:root.appending(path:"defaults.json"))
        let preferences = UserDefaults(suiteName: "PenActor-removal-"+UUID().uuidString)!
        preferences.set(["ps"],forKey:"touchBlockingTargets")
        let monitor = PenMonitor(preferences:preferences,profileRepository:.init(url:root.appending(path:"profiles.json")))
        XCTAssertNil(monitor.profileError)
        XCTAssertNil(preferences.object(forKey:"touchBlockingTargets"))
        XCTAssertEqual(monitor.profiles.first?.id,p.id)
        XCTAssertEqual(monitor.profiles.first?.applicationRules?[0].mode,.inherit)
        XCTAssertEqual(monitor.profiles.first?.applicationRules?[0].overrides,[])
        XCTAssertEqual(monitor.profiles.first?.applicationRules?[1].overrides,[.curve,.entry])
        let migrated = try XCTUnwrap(monitor.profiles.first)
        let inherited = try XCTUnwrap(monitor.mappingDefaults.resolve(migrated,bundleID:"com.adobe.Photoshop"))
        XCTAssertEqual(inherited.curve,.light);XCTAssertTrue(inherited.taper.exitEnabled)
        let custom = try XCTUnwrap(monitor.mappingDefaults.resolve(migrated,bundleID:"other.app"))
        XCTAssertEqual(custom.curve,.light);XCTAssertEqual(custom.taper.entryDurationMS,125);XCTAssertTrue(custom.taper.exitEnabled)
        XCTAssertEqual(monitor.deviceDisplayName(identity),"我的 Pencil")
        XCTAssertTrue(monitor.enabledProfileIDs.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(at:root.appending(path:"Backups"),includingPropertiesForKeys:nil)
        XCTAssertEqual(backups.count,1)
        XCTAssertEqual(try Data(contentsOf:backups[0].appending(path:"profiles.json")),originalProfile)
        XCTAssertEqual(try Data(contentsOf:backups[0].appending(path:"defaults.json")),originalDefaults)
        for name in ["profiles.json","defaults.json"] {
            let content = try String(contentsOf:root.appending(path:name),encoding:.utf8)
            XCTAssertFalse(content.contains("smoothing"))
            let data = try XCTUnwrap(JSONSerialization.jsonObject(with:Data(content.utf8)) as? [String: Any])
            XCTAssertEqual(data["schemaVersion"] as? Int,name == "profiles.json" ? 6 : 4)
        }
        let export = try monitor.makeLogDocument().jsonData()
        let text = String(decoding:export,as:UTF8.self)
        for removed in ["smoothing","touchBlocking","coordinateProbes","eventData"] { XCTAssertFalse(text.contains(removed)) }
        let restarted = PenMonitor(preferences:preferences,profileRepository:.init(url:root.appending(path:"profiles.json")))
        XCTAssertEqual(restarted.profiles,monitor.profiles)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at:root.appending(path:"Backups"),includingPropertiesForKeys:nil).count,1)
        // An interrupted previous migration may have saved defaults first, leaving the old profile file.
        try originalProfile.write(to:root.appending(path:"profiles.json"))
        let recovered = PenMonitor(preferences:preferences,profileRepository:.init(url:root.appending(path:"profiles.json")))
        XCTAssertEqual(recovered.profiles,monitor.profiles)
        XCTAssertFalse(try String(contentsOf:root.appending(path:"profiles.json"),encoding:.utf8).contains("smoothing"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at:root.appending(path:"Backups"),includingPropertiesForKeys:nil).count,2)
        var invalid = rules[1];invalid["overrides"] = ["unknown-future-option"]
        XCTAssertThrowsError(try JSONDecoder().decode(ApplicationPressureRule.self,from:JSONSerialization.data(withJSONObject:invalid)))
    }
}

import XCTest
import AppKit
import SwiftUI
@testable import PenActor

final class LocalizationTests: XCTestCase {
    private func languageBundle(_ language: String) throws -> Bundle {
        let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"))
        return try XCTUnwrap(Bundle(url: url))
    }

    func testBothLanguagesAreBundledAndTranslateRuntimeLabels() throws {
        let english = try languageBundle("en")
        let chinese = try languageBundle("zh-Hans")
        for (key, translation) in [
            ("General", "通用"), ("Profiles", "配置"),
            ("Input Monitoring", "输入监控"), ("Accessibility", "辅助功能"),
            ("Mapping paused", "映射已暂停"), ("This app", "本应用"),
            ("Pen", "笔"), ("Squeezing", "正在挤压")
        ] {
            XCTAssertEqual(english.localizedString(forKey: key, value: nil, table: nil), key)
            XCTAssertEqual(chinese.localizedString(forKey: key, value: nil, table: nil), translation)
        }
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
    }

    func testTranslatedFormatsPreserveCountsNamesAndErrorDetails() throws {
        let english = try languageBundle("en")
        let chinese = try languageBundle("zh-Hans")
        for (bundle, expected) in [(english, "Profile 3"), (chinese, "配置 3")] {
            let format = bundle.localizedString(forKey: "Profile %lld", value: nil, table: nil)
            XCTAssertEqual(String(format: format, Int64(3)), expected)
        }
        let name = "自定义 Profile %"
        let format = english.localizedString(forKey: "Enabled · %@", value: nil, table: nil)
        XCTAssertEqual(String(format: format, name), "Enabled · " + name)
        let error = english.localizedString(forKey: "Could not save configuration: %@", value: nil, table: nil)
        XCTAssertEqual(String(format: error, "fixture error"), "Could not save configuration: fixture error")
    }

    func testLegacyDiagnosticsUseEnglishKeysWithoutChangingRawValues() {
        for (raw, key) in [
            ("映射已暂停", "Mapping paused"),
            ("正在创建事件 tap…", "Creating event tap…"),
            ("无法创建事件 tap，请检查辅助功能权限", "Could not create the event tap. Check Accessibility access."),
            ("正在映射（等待匹配事件）", "Mapping active (waiting for matching input)"),
            ("事件线程已结束；映射已停止，请手动重新启用", "The event thread ended. Mapping stopped; enable it again manually."),
            ("系统停用了事件 tap；映射已停止，请手动重新启用", "The system disabled the event tap. Mapping stopped; enable it again manually.")
        ] {
            var snapshot = MappingSnapshot()
            snapshot.status = raw
            XCTAssertEqual(snapshot.localizedStatus, Bundle.main.localizedString(forKey: key, value: nil, table: nil))
            XCTAssertEqual(snapshot.status, raw)
        }
        for (raw, key) in [
            ("已应用曲线", "Curve applied"),
            ("等待 proximity 识别设备", "Waiting for proximity metadata to identify the device"),
            ("目标应用未知", "Target app unknown"),
            ("设备或应用未启用配置 / 本笔透传", "No enabled profile for this device or app / Passing through this stroke"),
            ("暂停 / 禁用：缓存恢复原输入", "Paused / Disabled: queued input restored")
        ] {
            let diagnostic = MappingDiagnostic(timestamp: 0, device: nil, targetPID: 0,
                targetBundleID: nil, profileID: nil, inputPressure: 0, outputPressure: 0,
                tabletInputPressure: 0, tabletOutputPressure: 0, reason: raw)
            XCTAssertEqual(diagnostic.localizedReason, Bundle.main.localizedString(forKey: key, value: nil, table: nil))
            XCTAssertEqual(diagnostic.reason, raw)
        }
        var custom = MappingSnapshot()
        custom.status = "Fixture-specific status"
        XCTAssertEqual(custom.localizedStatus, custom.status)
    }

    func testPresentationLocalizationDoesNotChangePersistedOrDiagnosticValues() throws {
        XCTAssertEqual(EventSource.local.rawValue, "本应用")
        XCTAssertEqual(PencilSqueezeStatus.active.rawValue, "正在挤压")
        XCTAssertEqual(ConfigurationComponent.curve.rawValue, "curve")
        let info = PenDeviceInfo(vendorID: 1452, tabletID: 4762, pointingDeviceID: 1,
                                 systemTabletID: 1, vendorPointingDeviceType: 0,
                                 serialNumber: 0, uniqueID: 0, capabilityMask: 0, toolType: "笔")
        let identity = PenIdentity.resolve(info: info, deviceID: 17)
        _ = info.localizedToolType
        XCTAssertEqual(identity.key, "v1:model:5ac:129a:0:pen")
        XCTAssertEqual(info.toolType, "笔")
        XCTAssertEqual(MappingSnapshot().status, "映射已暂停")
        let encoded = try JSONEncoder().encode(EventSource.local)
        XCTAssertEqual(String(decoding: encoded, as: UTF8.self), "\"本应用\"")
    }
}

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
            ("通用", "General"), ("配置", "Profiles"),
            ("输入监控", "Input Monitoring"), ("辅助功能", "Accessibility"),
            ("映射已暂停", "Mapping paused"), ("本应用", "This app"),
            ("笔", "Pen"), ("正在挤压", "Squeezing")
        ] {
            XCTAssertEqual(english.localizedString(forKey: key, value: nil, table: nil), translation)
            XCTAssertEqual(chinese.localizedString(forKey: key, value: nil, table: nil), key)
        }
    }

    func testTranslatedFormatsPreserveCountsNamesAndErrorDetails() throws {
        let english = try languageBundle("en")
        let chinese = try languageBundle("zh-Hans")
        for (bundle, expected) in [(english, "Profile 3"), (chinese, "配置 3")] {
            let format = bundle.localizedString(forKey: "配置 %lld", value: nil, table: nil)
            XCTAssertEqual(String(format: format, Int64(3)), expected)
        }
        let name = "自定义 Profile %"
        let format = english.localizedString(forKey: "已启用 · %@", value: nil, table: nil)
        XCTAssertEqual(String(format: format, name), "Enabled · " + name)
        let error = english.localizedString(forKey: "保存配置失败：%@", value: nil, table: nil)
        XCTAssertEqual(String(format: error, "fixture error"), "Could not save configuration: fixture error")
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

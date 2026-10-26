import AppKit

// System Settings deep links are best-effort; fall back to the privacy overview.
enum PrivacySettingsPane {
    case inputMonitoring, accessibility
    var title: String { self == .inputMonitoring ? String(localized: "Input Monitoring") : String(localized: "Accessibility") }
    var url: URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?" + (self == .inputMonitoring ? "Privacy_ListenEvent" : "Privacy_Accessibility"))!
    }
}
@MainActor
struct PrivacySettingsNavigator {
    var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    func open(_ pane: PrivacySettingsPane) -> Bool {
        if openURL(pane.url) { return true }
        return openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
    }
}

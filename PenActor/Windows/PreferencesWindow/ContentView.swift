import SwiftUI
import AppKit

/// Hosts preferences pages and shared controls; each page owns its transient UI state.
struct ContentView: View {
    @ObservedObject var monitor: PenMonitor

    var section: PreferencesSection = .general
    private var debugSection = DebugSection.live
    private var pencilDetailsExpanded = false
    var onContentHeightChange: ((CGFloat) -> Void)?
    typealias DebugSection = DebugPreferencesView.Section

    init(monitor: PenMonitor, section: PreferencesSection = .general, debugSection: DebugSection = .live, pencilDetailsExpanded: Bool = false, onContentHeightChange: ((CGFloat) -> Void)? = nil) {
        self.monitor = monitor; self.section = section
        self.onContentHeightChange = onContentHeightChange
        self.debugSection = debugSection
        self.pencilDetailsExpanded = pencilDetailsExpanded
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch section {
                case .general: GeneralPreferencesView(monitor: monitor).fixedSize(horizontal: false, vertical: true).measurePreferencesHeight("page")
                case .profiles: DeviceProfilesPreferencesView(monitor: monitor)
                case .debug: DebugPreferencesView(monitor: monitor, debugSection: debugSection).fixedSize(horizontal: false, vertical: true).measurePreferencesHeight("page")
                case .testing: PenTestingPreferencesView(monitor: monitor, pencilDetailsExpanded: pencilDetailsExpanded)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            globalStatusBar.measurePreferencesHeight("footer")
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: section.minimumSize.width, minHeight: section.minimumSize.height)
        .background(WindowConfiguration(alwaysOnTop: monitor.alwaysOnTop))
        .onPreferenceChange(PreferencesHeightKey.self) { values in
            if let page = values["page"], let footer = values["footer"], page > 0 {
                onContentHeightChange?(ceil(page + footer + 1))
            }
        }
    }

    private var globalStatusBar: some View {
        HStack(spacing: 10) {
            Label(monitor.mapping.isRunning ? String(localized: "映射已启用") : monitor.mapping.isStarting ? String(localized: "映射正在启动") : String(localized: "映射已暂停"),
                  systemImage: monitor.mapping.isRunning ? "arrow.triangle.2.circlepath" : "pause.circle")
            Divider().frame(height: 12)
            Button(String(localized: "暂停全部映射"), systemImage: "pause.fill") { monitor.pauseMapping() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!monitor.mapping.isRunning && !monitor.mapping.isStarting && monitor.enabledProfileIDs.isEmpty)
                .help(String(localized: "暂停所有设备的压力映射，不停止输入服务（⌘⇧R）"))
            Spacer(minLength: 20)
            Label(monitor.isRunning ? String(localized: "输入服务运行中") : String(localized: "输入服务已停止"), systemImage: monitor.isRunning ? "waveform" : "pause.circle")
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(nsColor: .underPageBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "全局运行状态与控制"))
    }

}

// Measure intrinsic page content, independently of the available window height.
private struct PreferencesHeightKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private extension View {
    func measurePreferencesHeight(_ part: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: PreferencesHeightKey.self, value: [part: proxy.size.height])
        })
    }
}

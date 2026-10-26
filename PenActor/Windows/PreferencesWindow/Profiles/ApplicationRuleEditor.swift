import SwiftUI

struct ApplicationRuleRow: View {
    @Binding var rule: ApplicationPressureRule
    let base: PressureConfiguration
    var remove: () -> Void
    @State private var editing = false
    private var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
    var body: some View {
        HStack(spacing: 12) {
            if let icon { Image(nsImage: icon).resizable().frame(width: 28, height: 28) }
            else { Image(systemName: "app").font(.title2).frame(width: 28) }
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name).lineLimit(1)
                Text(rule.summary).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { editing = true } label: { Image(systemName: "slider.horizontal.3") }
                .help(String(localized: "设置此应用的继承、覆盖或透传"))
                .popover(isPresented: $editing, arrowEdge: .trailing) {
                    ApplicationRuleEditor(rule: $rule, base: base).padding(16).frame(width: 600)
                }
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }.help(String(localized: "移除此应用"))
        }.padding(10)
    }
}

struct ApplicationRuleEditor: View {
    @Binding var rule: ApplicationPressureRule
    let base: PressureConfiguration
    @State private var component = ConfigurationComponent.curve
    private var inherits: Bool { !rule.effectiveOverrides.contains(component) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PreferencesPageHeader(title: rule.name, subtitle: String(localized: "各项独立继承设备默认；完成后保存配置。"))
            Text(rule.bundleID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Toggle(String(localized: "在此应用中处理输入"), isOn: Binding(get: { rule.mode != .passthrough }, set: { enabled in
                rule.mode = enabled ? ((rule.overrides ?? []).isEmpty ? .inherit : .custom) : .passthrough
            })).toggleStyle(.checkbox)
            if rule.mode != .passthrough {
                Picker(String(localized: "设置项目"), selection: $component) {
                    ForEach(ConfigurationComponent.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Toggle(String(localized: "继承设备默认"), isOn: Binding(get: { inherits }, set: { inherit in
                    rule.setOverride(component, enabled: !inherit, base: base)
                })).toggleStyle(.checkbox)
                PressureConfigurationEditor(configuration: Binding(get: {
                    rule.resolved(base: base)
                }, set: { value in
                    guard !inherits else { return }
                    rule.configuration.copy(component, from: value)
                }), component: component)
                    .disabled(inherits)
                Text(inherits ? String(localized: "当前值来自设备默认，设备默认保存后会从下一笔跟随更新。") : String(localized: "只覆盖本项；其它继承项仍跟随设备默认。"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(String(localized: "保留系统输入，不应用此配置的压力曲线、笔锋或轨迹平滑。"))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

import SwiftUI

struct GeneralPreferencesView: View {
    @ObservedObject var monitor: PenMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PreferencesPageHeader(title: String(localized: "通用"), subtitle: String(localized: "PenActor 在菜单栏持续运行，关闭设置窗口后仍会处理已启用的笔输入。"))
            GroupBox(String(localized: "运行与启动")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(monitor.isRunning ? String(localized: "输入服务运行中") : String(localized: "输入服务已停止"), systemImage: monitor.isRunning ? "checkmark.circle.fill" : "pause.circle")
                            .foregroundStyle(monitor.isRunning ? Color.green : Color.secondary)
                        Spacer()
                        Button(monitor.isRunning ? String(localized: "停止服务") : String(localized: "启动服务")) { if monitor.isRunning { monitor.stop() } else { monitor.start() } }
                    }
                    Toggle(String(localized: "启动 PenActor 后自动监听"), isOn: Binding(get: { monitor.startMonitoringOnLaunch }, set: { monitor.setStartMonitoringOnLaunch($0) }))
                    Toggle(String(localized: "启动时打开设置窗口"), isOn: Binding(get: { monitor.showSettingsOnLaunch }, set: { monitor.setShowSettingsOnLaunch($0) }))
                    Text(String(localized: "重启程序后映射默认关闭，需手动启用硬件配置。可从菜单栏随时打开设置、暂停映射或退出。"))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(10).toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(String(localized: "访问权限")) {
                VStack(spacing: 12) {
                    permissionRow(String(localized: "输入监控"), allowed: monitor.listenAccess) { monitor.requestPermission() }
                    permissionRow(String(localized: "辅助功能"), allowed: monitor.accessibilityAccess) { monitor.requestAccessibility() }
                    HStack { Text(String(localized: "本窗口测试可在未授予输入监控权限时使用。")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(String(localized: "重新检查")) { monitor.refreshPermission() } }
                    Text(String(localized: "若列表中没有 PenActor，请点 + 添加 /Applications/PenActor.app。授权后按系统提示重新打开应用；窗口内测试无需输入监控权限。"))
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    if let error = monitor.permissionError { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }.padding(10)
            }
            errorMessage
        }.padding(16)
    }
    private var errorMessage: some View { Group { if let error = monitor.profileError { Text(error).foregroundStyle(.red).textSelection(.enabled) } } }
    private func permissionRow(_ name: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack { Label(name, systemImage: allowed ? "checkmark.shield" : "lock"); Spacer(); Text(allowed ? String(localized: "已允许") : String(localized: "未允许 / 待确认")).foregroundStyle(.secondary); Button(String(localized: "请求权限"), action: action).disabled(allowed) }
    }
}

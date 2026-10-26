import SwiftUI

struct GeneralPreferencesView: View {
    @ObservedObject var monitor: PenMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PreferencesPageHeader(title: String(localized: "General"), subtitle: String(localized: "PenActor runs in the menu bar and keeps processing enabled pen input after settings close."))
            GroupBox(String(localized: "Service and startup")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(monitor.isRunning ? String(localized: "Input service running") : String(localized: "Input service stopped"), systemImage: monitor.isRunning ? "checkmark.circle.fill" : "pause.circle")
                            .foregroundStyle(monitor.isRunning ? Color.green : Color.secondary)
                        Spacer()
                        Button(monitor.isRunning ? String(localized: "Stop Service") : String(localized: "Start Service")) { if monitor.isRunning { monitor.stop() } else { monitor.start() } }
                    }
                    Toggle(String(localized: "Start monitoring when PenActor launches"), isOn: Binding(get: { monitor.startMonitoringOnLaunch }, set: { monitor.setStartMonitoringOnLaunch($0) }))
                    Toggle(String(localized: "Open settings at launch"), isOn: Binding(get: { monitor.showSettingsOnLaunch }, set: { monitor.setShowSettingsOnLaunch($0) }))
                    Text(String(localized: "Mapping starts paused after a restart. Enable a profile manually. Use the menu bar to open settings, pause mapping, or quit."))
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(10).toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox(String(localized: "Permissions")) {
                VStack(spacing: 12) {
                    permissionRow(String(localized: "Input Monitoring"), allowed: monitor.listenAccess) { monitor.requestPermission() }
                    permissionRow(String(localized: "Accessibility"), allowed: monitor.accessibilityAccess) { monitor.requestAccessibility() }
                    HStack { Text(String(localized: "Local testing works without Input Monitoring permission.")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(String(localized: "Recheck")) { monitor.refreshPermission() } }
                    Text(String(localized: "If PenActor is missing, click + and add /Applications/PenActor.app. Relaunch if requested. Local testing does not require Input Monitoring."))
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    if let error = monitor.permissionError { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                }.padding(10)
            }
            errorMessage
        }.padding(16)
    }
    private var errorMessage: some View { Group { if let error = monitor.profileError { Text(error).foregroundStyle(.red).textSelection(.enabled) } } }
    private func permissionRow(_ name: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack { Label(name, systemImage: allowed ? "checkmark.shield" : "lock"); Spacer(); Text(allowed ? String(localized: "Allowed") : String(localized: "Not allowed / Pending")).foregroundStyle(.secondary); Button(String(localized: "Request Access"), action: action).disabled(allowed) }
    }
}

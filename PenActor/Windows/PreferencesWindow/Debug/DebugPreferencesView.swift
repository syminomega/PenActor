import SwiftUI
import AppKit

struct DebugPreferencesView: View {
    @ObservedObject var monitor: PenMonitor
    private var device: DeviceState? { monitor.snapshot.selectedDevice }
    private var sample: PenSample? { device?.lastSampleEvent?.sample }
    @State var debugSection = Section.live
    enum Section: String, CaseIterable {
        case live = "实时数值", device = "设备详情", events = "事件记录"

        var title: String {
            switch self {
            case .live: String(localized: "Live Values")
            case .device: String(localized: "Device Details")
            case .events: String(localized: "Events")
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Live Debug")).font(.title3.bold())
                Spacer()
                Toggle(String(localized: "Keep on Top"), isOn: $monitor.alwaysOnTop).toggleStyle(.checkbox)
                Button(String(localized: "Export JSON"), systemImage: "square.and.arrow.up") { monitor.exportLog() }.disabled(monitor.isExporting)
                Button(String(localized: "Clear"), systemImage: "trash") { monitor.clear() }
            }
            HStack {
                Picker(String(localized: "Device"), selection: Binding(get: { monitor.snapshot.selectedIdentity }, set: { monitor.selectDevice($0) })) {
                    Text(String(localized: "Waiting for pen input")).tag(PenIdentity?.none)
                    ForEach(monitor.snapshot.devices) { Text(monitor.deviceDisplayName($0.id)).tag(Optional($0.id)) }
                }.frame(maxWidth: 340)
                Toggle(String(localized: "Follow the active pen"), isOn: Binding(get: { monitor.automaticallySwitchDevices }, set: { monitor.setAutomaticSwitching($0) })).toggleStyle(.checkbox)
                Spacer()
            }
            HStack {
                Picker(String(localized: "Debug view"), selection: $debugSection) {
                    ForEach(Section.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().frame(width: 330)
                Spacer()
                Text(device?.status ?? String(localized: "Bring the pen into range and draw")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            switch debugSection {
            case .live:
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        samplePanel.frame(maxWidth: .infinity)
                        trendPanel.frame(width: 225)
                    }.fixedSize(horizontal: false, vertical: true)
                    mappingPanel
                    DisclosureGroup(String(localized: "Monitoring status and reading notes")) {
                        VStack(alignment: .leading, spacing: 5) {
                            status(String(localized: "Local"), installed: monitor.installation.local, received: monitor.receivedLocal)
                            status(String(localized: "Global"), installed: monitor.installation.global, received: monitor.receivedGlobal)
                            Text(String(localized: "NSEvent may already include mapped pressure. Tap diagnostics record input and output separately; the streams do not match event for event."))
                        }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    }.font(.caption)
                }
            case .device:
                hardwarePanel
            case .events:
                eventsPanel.frame(height: 320)
            }
        }.padding(16)
        .alert(String(localized: "Export Failed"), isPresented: Binding(get: { monitor.exportError != nil }, set: { if !$0 { monitor.exportError = nil } })) {
            Button(String(localized: "OK")) { monitor.exportError = nil }
        } message: { Text(monitor.exportError ?? "") }
    }

    private var mappingPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Pressure mapping")).font(.headline)
                Spacer()
                Text(String(localized: "Modified \(monitor.mapping.modifiedEventCount) · Queued \(monitor.mapping.bufferedEventCount)")).font(.caption).foregroundStyle(.secondary)
            }
            Text(monitor.mapping.localizedStatus).font(.callout)
            if let last = monitor.mapping.diagnostics.last {
                HStack(spacing: 16) {
                    Text(String(localized: "Input \(number(last.inputPressure)) → Output \(number(last.outputPressure))")).monospacedDigit()
                    Text(last.localizedReason).foregroundStyle(.secondary).lineLimit(2)
                }.font(.callout)
                DisclosureGroup(String(localized: "Match details")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Target: \(last.targetBundleID ?? String(localized: "Unknown app")) · PID \(last.targetPID)"))
                        Text(String(localized: "Device: \(last.device?.key ?? String(localized: "Unidentified"))"))
                        Text(String(localized: "Profile: \(monitor.profiles.first { $0.id == last.profileID }?.name ?? String(localized: "Pass through this stroke"))"))
                        Text(String(localized: "A modified callback does not confirm delivery to the target app. Export a log for analysis."))
                    }.font(.caption).textSelection(.enabled).padding(.top, 6)
                }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private func status(_ title: String, installed: Bool, received: Bool) -> some View {
        Text(String(localized: "\(title): \(installed ? String(localized: "Monitor installed") : String(localized: "Not installed")) · \(received ? String(localized: "Pen events received") : String(localized: "No pen events received yet"))"))
    }

    private var hardwarePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(String(localized: "Hardware metadata"), systemImage: "pencil.tip").font(.headline)
            if let device {
                field(String(localized: "Identity matching"), device.id.level.label)
                field(String(localized: "Match key"), device.id.key)
                field(String(localized: "Session device ID"), identifierText(device.lastEvent.deviceID))
                Divider()
                if let info = device.info {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            field(String(localized: "Tool type"), info.localizedToolType)
                            field(String(localized: "Vendor ID"), identifierText(info.vendorID))
                            field(String(localized: "Tablet ID"), identifierText(info.tabletID))
                            field(String(localized: "System tablet"), identifierText(info.systemTabletID))
                            field(String(localized: "Pointing device"), identifierText(info.pointingDeviceID))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 8) {
                            field(String(localized: "Vendor tool type"), identifierText(info.vendorPointingDeviceType))
                            field(String(localized: "Serial number"), identifierText(info.serialNumber))
                            field(String(localized: "Unique ID"), identifierText(info.uniqueID))
                            field(String(localized: "Capability mask"), identifierText(info.capabilityMask))
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else { Text(String(localized: "Waiting for hardware metadata. Move the pen out of range and back in.")).foregroundStyle(.secondary) }
            } else { Text(String(localized: "Waiting for pen input. Connect Sidecar or a tablet, bring the pen into range, and draw.")).foregroundStyle(.secondary) }
            Text(String(localized: "IDs are reported by the system or driver; zero may be a placeholder. Model groups cannot distinguish pens without unique IDs. Silence does not mean disconnection. Up to 32 identities are retained."))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).panel()
    }

    private var samplePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "AppKit event readings")).font(.headline)
                Spacer()
                if let event = device?.lastSampleEvent {
                    Text(event.source.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(number(sample?.pressure.map(Double.init))).font(.system(size: 24, weight: .medium, design: .monospaced))
                Text(String(localized: "Pressure / 1")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(PenCapability.pressure.support(mask: device?.info?.capabilityMask)).font(.caption2).foregroundStyle(.tertiary)
            }
            PressureLevelBar(pressure: sample?.pressure.map(Double.init))
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow {
                    metric(String(localized: "Tilt X"), number(sample?.tiltX), capability: .tiltX)
                    metric(String(localized: "Tilt Y"), number(sample?.tiltY), capability: .tiltY)
                    metric(String(localized: "Barrel rotation °"), number(sample.map { Double($0.rotation) }), capability: .rotation)
                }
                GridRow {
                    metric(String(localized: "Tangential pressure"), number(sample.map { Double($0.tangentialPressure) }), capability: .tangentialPressure)
                    metric(String(localized: "Absolute X / Y / Z"), sample.map { "\($0.absoluteX) / \($0.absoluteY) / \($0.absoluteZ)" } ?? String(localized: "Unavailable"))
                    metric(String(localized: "Button mask"), sample.map { identifierText($0.buttons) } ?? String(localized: "Unavailable"), capability: .buttons)
                }
            }
            if let event = device?.lastSampleEvent {
                Text("\(event.typeName) · \(event.foregroundApp)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                DisclosureGroup(String(localized: "Timing and coordinate context")) {
                    Text(String(localized: "Screen coordinates: \(number(event.screenX)) / \(number(event.screenY))")).font(.caption.monospaced()).textSelection(.enabled)
                    Text(String(localized: "uptime \(event.timestamp.formatted(.number.precision(.fractionLength(4)))) s · Last \(event.receivedAt.formatted(date: .omitted, time: .standard)) · Foreground app is observation context only"))
                        .font(.caption.monospaced()).textSelection(.enabled)
                }.font(.caption)
            }
        }.frame(maxHeight: .infinity, alignment: .top).panel()
    }

    private var trendPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "Pressure history")).font(.headline)
                Spacer()
                Text(String(localized: "Last 5 seconds")).font(.caption).foregroundStyle(.secondary)
            }
            PressureTrend(events: device?.history ?? [])
                .frame(minHeight: 74, maxHeight: .infinity)
            Text(String(localized: "Up to 600 samples. History remains when input stops; missing values leave gaps."))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxHeight: .infinity).panel()
    }

    private var eventsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = monitor.lastExportURL {
                Text(String(localized: "Exported: \(url.lastPathComponent)")).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text(String(localized: "Recent events")).font(.headline)
                Spacer()
                Text(String(localized: "All devices · Latest 500 events · Newest first")).font(.caption).foregroundStyle(.secondary)
            }
            Table(Array(monitor.snapshot.events.reversed())) {
                TableColumn(String(localized: "Time")) { event in
                    Text(event.receivedAt.formatted(date: .omitted, time: .standard))
                }.width(75)
                TableColumn(String(localized: "Source")) { Text($0.source.label) }.width(65)
                TableColumn(String(localized: "Device")) { Text(String($0.deviceID)) }.width(55)
                TableColumn(String(localized: "Type")) { Text($0.typeName) }
                TableColumn(String(localized: "Pressure")) { event in Text(number(event.sample?.pressure.map(Double.init))) }.width(70)
                TableColumn(String(localized: "Range")) { event in
                    Text(event.proximity.map { $0 ? String(localized: "Entered") : String(localized: "Exited") } ?? "—")
                }.width(45)
                TableColumn(String(localized: "Foreground app (context)")) { Text($0.foregroundApp) }
            }.frame(minHeight: 240, maxHeight: .infinity)
        }.panel()
    }

    private func number(_ value: Double?) -> String {
        value.map { String(format: "%.4f", $0) } ?? String(localized: "Unavailable")
    }

    private func metric(_ title: String, _ value: String, capability: PenCapability? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let capability {
                    Text(capability.support(mask: device?.info?.capabilityMask)).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Text(value).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
            Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
        }
    }
}

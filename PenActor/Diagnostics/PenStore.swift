import Foundation

/// Bounded diagnostic history and device selection; never drives event remapping.
struct PenStore {
    static let eventLimit = 500
    static let historyLimit = 600
    static let deviceLimit = 32
    static let sessionLimit = 128
    private(set) var devices: [DeviceState] = []
    private(set) var events: [PenEvent] = []
    private(set) var totalEvents: UInt64 = 0
    var selectedIdentity: PenIdentity?
    private(set) var lastActiveIdentity: PenIdentity?
    var automaticallySwitchDevices = true
    private var sessions: [Int: PenIdentity] = [:]
    private var sessionOrder: [Int] = []

    var selectedDevice: DeviceState? { devices.first { $0.id == selectedIdentity } }

    mutating func ingest(_ incoming: PenEvent) {
        totalEvents += 1
        var event = incoming
        event.id = totalEvents
        let previousIdentity = sessions[event.deviceID]
        let reportedIdentity = event.info.map { PenIdentity.resolve(info: $0, deviceID: event.deviceID) }
        // An incomplete departure packet must not demote an already identified device.
        let identity: PenIdentity
        if let previousIdentity, event.proximity == false {
            identity = previousIdentity
        } else if let reportedIdentity, reportedIdentity.level != .session {
            identity = reportedIdentity
        } else {
            identity = previousIdentity ?? .session(event.deviceID)
        }
        event.identityAtCapture = identity

        // Promote a provisional row when proximity metadata arrives. If the stable row
        // already exists, merge into it instead of leaving a duplicate row behind.
        if let previousIdentity, previousIdentity != identity, previousIdentity.level == .session,
           let provisional = devices.first(where: { $0.id == previousIdentity }) {
            if let target = devices.firstIndex(where: { $0.id == identity }) {
                if provisional.lastSampleEvent != nil {
                    devices[target].lastSampleEvent = provisional.lastSampleEvent
                    devices[target].history += provisional.history
                    devices[target].history.sort { $0.id < $1.id }
                    devices[target].history = Array(devices[target].history.suffix(Self.historyLimit))
                }
                devices[target].lastEvent = provisional.lastEvent
            } else {
                devices.append(DeviceState(id: identity, lastEvent: provisional.lastEvent,
                                           lastSampleEvent: provisional.lastSampleEvent, history: provisional.history))
            }
            devices.removeAll { $0.id == previousIdentity }
            if selectedIdentity == previousIdentity { selectedIdentity = identity }
            if lastActiveIdentity == previousIdentity { lastActiveIdentity = identity }
        } else if let previousIdentity, previousIdentity != identity,
                  let old = devices.firstIndex(where: { $0.id == previousIdentity }),
                  devices[old].lastEvent.deviceID == event.deviceID {
            // A recycled session ID now refers to a different pen.
            devices[old].proximity = false
        }
        rememberSession(event.deviceID, identity: identity)

        if !devices.contains(where: { $0.id == identity }) {
            if devices.count >= Self.deviceLimit {
                let removed = devices.removeFirst()
                let obsolete = Set(sessions.filter { $0.value == removed.id }.map(\.key))
                sessions = sessions.filter { !obsolete.contains($0.key) }
                sessionOrder.removeAll { obsolete.contains($0) }
                if selectedIdentity == removed.id { selectedIdentity = nil }
                if lastActiveIdentity == removed.id { lastActiveIdentity = nil }
            }
            devices.append(DeviceState(id: identity, lastEvent: event))
        }
        guard let index = devices.firstIndex(where: { $0.id == identity }) else { return }
        // Ignore late departures from a previous connection after this device reconnects.
        let retiredSession = event.proximity == false && devices[index].lastEvent.deviceID != event.deviceID
        let outOfOrder = event.timestamp < devices[index].lastEvent.timestamp
        if !retiredSession && !outOfOrder {
            if let info = event.info, reportedIdentity == identity { devices[index].info = info }
            if event.proximity == true, let previousSample = devices[index].lastSampleEvent,
               previousSample.deviceID != event.deviceID {
                devices[index].lastSampleEvent = nil
            }
            if let proximity = event.proximity { devices[index].proximity = proximity }
            devices[index].lastEvent = event
            if event.sample != nil {
                devices[index].lastSampleEvent = event
                devices[index].history.append(event)
                if devices[index].history.count > Self.historyLimit {
                    devices[index].history.removeFirst(devices[index].history.count - Self.historyLimit)
                }
            }
            // Departures never steal selection. Repeated packets from the same active
            // pen do not undo a manual selection until the active pen actually changes.
            if event.proximity == true || event.sample != nil {
                if automaticallySwitchDevices && lastActiveIdentity != identity { selectedIdentity = identity }
                lastActiveIdentity = identity
            }
        }
        if selectedIdentity == nil { selectedIdentity = identity }
        events.append(event)
        if events.count > Self.eventLimit { events.removeFirst(events.count - Self.eventLimit) }
    }

    mutating func setAutomaticSwitching(_ enabled: Bool) {
        automaticallySwitchDevices = enabled
        if enabled, let lastActiveIdentity { selectedIdentity = lastActiveIdentity }
    }

    private mutating func rememberSession(_ deviceID: Int, identity: PenIdentity) {
        if sessions[deviceID] == nil { sessionOrder.append(deviceID) }
        sessions[deviceID] = identity
        while sessionOrder.count > Self.sessionLimit {
            sessions.removeValue(forKey: sessionOrder.removeFirst())
        }
    }

    mutating func clear() {
        let automatic = automaticallySwitchDevices
        self = PenStore()
        automaticallySwitchDevices = automatic
    }
}

#!/usr/bin/env swift
import AppKit

// Offline only: no event tap, posting, cursor movement, or application interaction.
// Usage: swift scripts/analyze-coordinate-probes.swift /path/to/PenActor-log.json
struct ProbeLog: Decodable {
    struct Mapping: Decodable { var coordinateProbes: [Probe]? }
    struct Probe: Decodable { var eventType: UInt32; var eventData: Data }
    var mapping: Mapping
}
struct FieldChange: Encodable {
    var field: String
    var before: Double
    var after: Double
}
struct Position: Encodable, Equatable {
    var x: Double
    var y: Double
    init(_ point: CGPoint) { x = point.x; y = point.y }
}
struct Result: Encodable {
    var operation: String
    var originalBytes: Int
    var resultBytes: Int
    var byteIdentical: Bool
    var inputPosition: Position
    var outputPosition: Position
    var windowNumber: Int?
    var fieldChanges: [FieldChange]
}
struct Sample: Encodable {
    var eventType: UInt32
    var results: [Result]
}
let fields: [(String, CGEventField)] = [
    ("subtype", .mouseEventSubtype), ("deltaX", .mouseEventDeltaX), ("deltaY", .mouseEventDeltaY),
    ("eventNumber", .mouseEventNumber), ("clickCount", .mouseEventClickState),
    ("tabletX", .tabletEventPointX), ("tabletY", .tabletEventPointY), ("tabletZ", .tabletEventPointZ),
    ("tabletButtons", .tabletEventPointButtons), ("deviceID", .tabletEventDeviceID),
    ("mousePressure", .mouseEventPressure), ("tabletPressure", .tabletEventPointPressure),
    ("tiltX", .tabletEventTiltX), ("tiltY", .tabletEventTiltY), ("rotation", .tabletEventRotation),
    ("targetPID", .eventTargetUnixProcessID),
    ("windowUnderPointer", .mouseEventWindowUnderMousePointer),
    ("handlingWindowUnderPointer", .mouseEventWindowUnderMousePointerThatCanHandleThisEvent)
]
func analyze(_ probe: ProbeLog.Probe) throws -> Sample {
    guard let original = CGEvent(withDataAllocator: nil, data: probe.eventData as CFData) else {
        throw NSError(domain: "PenActorProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid Quartz event data"])
    }
    // Validate the payload itself before calling any type-specific AppKit accessors.
    guard original.type == .tabletPointer || [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(original.type),
          original.type.rawValue == probe.eventType else {
        throw NSError(domain: "PenActorProbe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected a pen event"])
    }
    let operations = ["copy", "pressureOnly", "sameGlobalLocation", "shiftGlobalLocation", "shiftTabletCoordinates", "mouseDeltaOnly"]
    var results: [Result] = []
    for operation in operations {
        guard let event = original.copy() else { continue }
        let position = original.location
        switch operation {
        case "pressureOnly":
            event.setDoubleValueField(.tabletEventPointPressure, value: original.getDoubleValueField(.tabletEventPointPressure) * 0.5)
            if original.type != .tabletPointer {
                event.setDoubleValueField(.mouseEventPressure, value: original.getDoubleValueField(.mouseEventPressure) * 0.5)
            }
        case "sameGlobalLocation": event.location = position
        case "shiftGlobalLocation": event.location = CGPoint(x: position.x + 2, y: position.y + 3)
        case "shiftTabletCoordinates":
            event.setIntegerValueField(.tabletEventPointX, value: original.getIntegerValueField(.tabletEventPointX) + 2)
            event.setIntegerValueField(.tabletEventPointY, value: original.getIntegerValueField(.tabletEventPointY) + 3)
        case "mouseDeltaOnly":
            if original.type != .tabletPointer {
                event.setIntegerValueField(.mouseEventDeltaX, value: 2)
                event.setIntegerValueField(.mouseEventDeltaY, value: 3)
            }
        default: break
        }
        guard let cfData = event.data else { continue }
        let data = cfData as Data
        let changes = fields.compactMap { name, field -> FieldChange? in
            let before = original.getDoubleValueField(field), after = event.getDoubleValueField(field)
            return before == after ? nil : FieldChange(field: name, before: before, after: after)
        }
        results.append(Result(operation: operation, originalBytes: probe.eventData.count,
            resultBytes: data.count, byteIdentical: data == probe.eventData,
            inputPosition: Position(position), outputPosition: Position(event.location),
            windowNumber: NSEvent(cgEvent: event)?.windowNumber, fieldChanges: changes))
    }
    return Sample(eventType: probe.eventType, results: results)
}
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: swift scripts/analyze-coordinate-probes.swift /path/to/PenActor-log.json\n".utf8))
    exit(2)
}
let input = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let log = try JSONDecoder().decode(ProbeLog.self, from: input)
let result = try (log.mapping.coordinateProbes ?? []).map(analyze)
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
FileHandle.standardOutput.write(try encoder.encode(result))
FileHandle.standardOutput.write(Data("\n".utf8))

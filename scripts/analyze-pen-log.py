#!/usr/bin/env python3
"""Read-only comparison of observed event rates; never identifies hardware report rates."""
import argparse
import json
import statistics


def summary(intervals):
    intervals = sorted(t * 1000 for t in intervals if t > 0)
    if not intervals:
        return None
    return {
        "intervalCount": len(intervals),
        "observedEventsPerSecond": round(1000 / statistics.mean(intervals), 3),
        "meanMS": round(statistics.mean(intervals), 3),
        "medianMS": round(statistics.median(intervals), 3),
        "p95MS": round(intervals[int((len(intervals) - 1) * 0.95)], 3),
        "maxMS": round(intervals[-1], 3),
        "over16_667MS": sum(t > 1000 / 60 for t in intervals),
    }


def analyze(path):
    with open(path, encoding="utf-8") as file:
        document = json.load(file)
    strokes, current = [], None
    # Keep contacts of different devices separate. Only complete primary-button strokes qualify.
    for event in document["events"]:
        key = event["deviceID"]
        if event["eventTypeCode"] == 1:
            if current is not None:
                current.pop(key, None)
            else:
                current = {}
            current[key] = [event]
        elif current is not None and key in current and event["eventTypeCode"] in (6, 2):
            current[key].append(event)
            if event["eventTypeCode"] == 2:
                strokes.append(current.pop(key))
    intervals, output = [], []
    diagnostics = document.get("mapping", {}).get("diagnostics", [])
    for stroke in strokes:
        drag = [event for event in stroke if event["eventTypeCode"] == 6]
        dt = [b["timestamp"] - a["timestamp"] for a, b in zip(drag, drag[1:])]
        intervals.extend(dt)
        start, end = stroke[0]["timestamp"], stroke[-1]["timestamp"]
        identity = stroke[0].get("identityAtCapture")
        tap = [event for event in diagnostics if start <= event["timestamp"] <= end
               and event.get("device") == identity]
        times = sorted(set(event["timestamp"] for event in tap))
        # Schema 2 lacks event type; count all tap records and explicitly label that limitation.
        output.append({
            "dragEvents": len(drag), "durationSeconds": round(end - start, 6),
            "applicationDragRate": summary(dt),
            "tapRecords": len(tap),
            "tapWindowCovered": bool(times and diagnostics[0]["timestamp"] <= start),
            "tapAllEventRate": summary([b - a for a, b in zip(times, times[1:])]),
        })
    return {"file": path, "discardedEvents": document.get("discardedEventCount"),
            "strokes": output, "combinedApplicationDragRate": summary(intervals),
            "note": "Observed delivery rates only. Tap forms may include companion packets. Not hardware report rates."}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+")
    args = parser.parse_args()
    print(json.dumps([analyze(path) for path in args.logs], ensure_ascii=False, indent=2))

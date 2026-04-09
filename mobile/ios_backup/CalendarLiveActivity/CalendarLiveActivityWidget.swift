// CalendarLiveActivityWidget.swift
// SwiftUI views for Lock Screen banner + Dynamic Island
//
// Minimum deployment: iOS 16.2
// Add this file + CalendarLiveActivityAttributes.swift to a new
// "Widget Extension" target in Xcode named "CalendarLiveActivity".
// Enable "Live Activities" in the extension's Info.plist:
//   NSSupportsLiveActivities = YES

import ActivityKit
import SwiftUI
import WidgetKit

// ─── Accent colour from task type ────────────────────────────────────────────
private func accentColor(for taskType: String) -> Color {
    switch taskType {
    case "plan":  return Color(red: 0.659, green: 0.333, blue: 0.969)  // #A855F7 purple
    case "task":  return Color(red: 0.133, green: 0.773, blue: 0.369)  // #22C55E green
    case "ical":  return Color(red: 0.580, green: 0.639, blue: 0.722)  // #94A3B8 slate
    default:      return Color(red: 0.376, green: 0.647, blue: 0.980)  // #60A5FA blue
    }
}

// ─── Time formatting helper ───────────────────────────────────────────────────
private func timeString(_ date: Date) -> String {
    let fmt = DateFormatter()
    fmt.dateFormat = "h:mm a"
    return fmt.string(from: date)
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Lock Screen / Banner View
// ─────────────────────────────────────────────────────────────────────────────
struct LockScreenView: View {
    let attributes: CalendarLiveActivityAttributes
    let state:      CalendarLiveActivityAttributes.CalendarTaskState

    var body: some View {
        let accent = accentColor(for: attributes.taskType)

        HStack(spacing: 12) {
            // Coloured time pill
            VStack(spacing: 2) {
                Text(timeString(state.startTime))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(accent)
                if let end = state.endTime {
                    Text(timeString(end))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 58)

            // Divider line
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3)
                .frame(maxHeight: 40)

            // Title + location
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let loc = state.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text(state.isCompleted ? "Completed ✓" : "Upcoming")
                        .font(.system(size: 12))
                        .foregroundColor(state.isCompleted ? .green : .secondary)
                }
            }

            Spacer()

            // Calendar icon
            Image(systemName: "calendar")
                .font(.system(size: 20))
                .foregroundColor(accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Dynamic Island Views
// ─────────────────────────────────────────────────────────────────────────────

// Compact leading (small left side of pill)
struct CompactLeadingView: View {
    let attributes: CalendarLiveActivityAttributes
    let state:      CalendarLiveActivityAttributes.CalendarTaskState

    var body: some View {
        Image(systemName: "calendar")
            .foregroundColor(accentColor(for: attributes.taskType))
            .font(.system(size: 14, weight: .semibold))
    }
}

// Compact trailing (small right side of pill)
struct CompactTrailingView: View {
    let state: CalendarLiveActivityAttributes.CalendarTaskState

    var body: some View {
        Text(timeString(state.startTime))
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
    }
}

// Minimal (tiny dot shown when another app owns the island)
struct MinimalView: View {
    let attributes: CalendarLiveActivityAttributes

    var body: some View {
        Image(systemName: "calendar")
            .foregroundColor(accentColor(for: attributes.taskType))
            .font(.system(size: 12))
    }
}

// Expanded (full Dynamic Island when tapped / long-pressed)
struct ExpandedView: View {
    let attributes: CalendarLiveActivityAttributes
    let state:      CalendarLiveActivityAttributes.CalendarTaskState

    var body: some View {
        let accent = accentColor(for: attributes.taskType)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(accent)
                Text("Calendar++")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(timerInterval(state.startTime))
                    .font(.caption2.bold())
                    .foregroundColor(accent)
            }

            Text(state.title)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(2)

            HStack(spacing: 16) {
                Label(timeString(state.startTime), systemImage: "clock")
                    .font(.caption.bold())
                    .foregroundColor(accent)

                if let loc = state.location, !loc.isEmpty {
                    Label(loc, systemImage: "mappin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
    }

    private func timerInterval(_ start: Date) -> String {
        let diff = start.timeIntervalSinceNow
        if diff <= 0 { return "Now" }
        let mins = Int(diff / 60)
        if mins < 60 { return "in \(mins)m" }
        let hrs = mins / 60
        let rem = mins % 60
        return rem == 0 ? "in \(hrs)h" : "in \(hrs)h \(rem)m"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Widget Configuration
// ─────────────────────────────────────────────────────────────────────────────
@main
struct CalendarLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        CalendarLiveActivityWidget()
    }
}

struct CalendarLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(
            for: CalendarLiveActivityAttributes.self
        ) { context in
            // Lock Screen / banner
            LockScreenView(
                attributes: context.attributes,
                state:      context.state
            )
            .activityBackgroundTint(Color(UIColor.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    CompactLeadingView(
                        attributes: context.attributes,
                        state:      context.state
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedView(
                        attributes: context.attributes,
                        state:      context.state
                    )
                }
            } compactLeading: {
                CompactLeadingView(
                    attributes: context.attributes,
                    state:      context.state
                )
            } compactTrailing: {
                CompactTrailingView(state: context.state)
            } minimal: {
                MinimalView(attributes: context.attributes)
            }
            .keylineTint(accentColor(for: context.attributes.taskType))
        }
    }
}

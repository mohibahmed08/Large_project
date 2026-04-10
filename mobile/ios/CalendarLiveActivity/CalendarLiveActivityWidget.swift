import ActivityKit
import SwiftUI
import WidgetKit

private let sharedWidgetSuite = "group.com.jonathan.calendar.shared"
private let sharedUpcomingTasksKey = "upcomingTasks"

private struct SharedUpcomingTask: Identifiable, Hashable {
    let id: String
    let title: String
    let startTime: Date
    let endTime: Date?
    let location: String?
    let taskType: String
    let isCompleted: Bool
    let reminderEnabled: Bool
    let reminderMinutesBefore: Int
}

private struct AgendaEntry: TimelineEntry {
    let date: Date
    let tasks: [SharedUpcomingTask]
}

private func taskAccentColor(for taskType: String) -> Color {
    switch taskType {
    case "plan":
        return Color(red: 0.659, green: 0.333, blue: 0.969)
    case "task":
        return Color(red: 0.133, green: 0.773, blue: 0.369)
    case "ical":
        return Color(red: 0.580, green: 0.639, blue: 0.722)
    default:
        return Color(red: 0.376, green: 0.647, blue: 0.980)
    }
}

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    return formatter.string(from: date)
}

private func taskDeepLink(taskId: String) -> URL? {
    URL(string: "calendarplusplus://task/\(taskId)")
}

private enum LiveActivityPhase {
    case future
    case upcoming
    case ongoing
    case completed
}

private let liveActivityUpcomingWindow: TimeInterval = 45 * 60

private func liveActivityPhase(
    startTime: Date,
    endTime: Date?,
    isCompleted: Bool
) -> LiveActivityPhase {
    if isCompleted {
        return .completed
    }

    let now = Date()
    if now >= startTime && (endTime == nil || now <= endTime!) {
        return .ongoing
    }

    let timeUntilStart = startTime.timeIntervalSince(now)
    if timeUntilStart > liveActivityUpcomingWindow {
        return .future
    }

    return .upcoming
}

private func liveActivityStatusText(
    startTime: Date,
    endTime: Date?,
    isCompleted: Bool
) -> String {
    switch liveActivityPhase(startTime: startTime, endTime: endTime, isCompleted: isCompleted) {
    case .completed:
        return "Done"
    case .ongoing:
        return "Live"
    case .upcoming:
        return "Upcoming"
    case .future:
        return "Future"
    }
}

private func liveActivityStatusColor(
    startTime: Date,
    endTime: Date?,
    isCompleted: Bool
) -> Color {
    switch liveActivityPhase(startTime: startTime, endTime: endTime, isCompleted: isCompleted) {
    case .completed:
        return .green
    case .ongoing:
        return Color(red: 0.208, green: 0.627, blue: 0.980)
    case .upcoming:
        return Color(red: 0.365, green: 0.690, blue: 0.980)
    case .future:
        return Color(red: 0.478, green: 0.604, blue: 0.780)
    }
}

private func liveActivityPrimaryTimeText(
    startTime: Date,
    endTime: Date?,
    isCompleted: Bool
) -> String {
    switch liveActivityPhase(startTime: startTime, endTime: endTime, isCompleted: isCompleted) {
    case .ongoing:
        if let endTime {
            return "Ends \(timeString(endTime))"
        }
        return "Live now"
    case .completed:
        if let endTime {
            return "Ended \(timeString(endTime))"
        }
        return "Completed"
    case .upcoming, .future:
        return "Starts \(timeString(startTime))"
    }
}

private func compactIslandTimeText(
    startTime: Date,
    endTime: Date?,
    isCompleted: Bool
) -> String? {
    switch liveActivityPhase(startTime: startTime, endTime: endTime, isCompleted: isCompleted) {
    case .ongoing:
        return endTime.map(timeString) ?? "Now"
    case .upcoming:
        return timeString(startTime)
    case .future:
        return nil
    case .completed:
        return "Done"
    }
}

private func phaseSymbolName(
    startTime: Date,
    endTime: Date?,
    isCompleted: Bool
) -> String {
    switch liveActivityPhase(startTime: startTime, endTime: endTime, isCompleted: isCompleted) {
    case .completed:
        return "checkmark"
    case .ongoing:
        return "dot.radiowaves.left.and.right"
    case .upcoming:
        return "bell"
    case .future:
        return "calendar"
    }
}

private func relativeTimerText(to date: Date) -> String {
    let difference = date.timeIntervalSinceNow
    if difference <= 0 {
        return "Now"
    }

    let minutes = Int(difference / 60)
    if minutes < 60 {
        return "\(minutes)m"
    }

    let hours = minutes / 60
    let remainder = minutes % 60
    return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
}

private func descriptionPreview(_ description: String?) -> String? {
    guard let description else { return nil }
    let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.count <= 90 {
        return trimmed
    }
    return String(trimmed.prefix(87)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
}

private final class UpcomingTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry {
        AgendaEntry(
            date: .now,
            tasks: [
                SharedUpcomingTask(
                    id: "placeholder",
                    title: "Team check-in",
                    startTime: .now.addingTimeInterval(60 * 5),
                    endTime: .now.addingTimeInterval(60 * 35),
                    location: "Studio",
                    taskType: "task",
                    isCompleted: false,
                    reminderEnabled: true,
                    reminderMinutesBefore: 15
                )
            ]
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        let entry = loadEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadEntry() -> AgendaEntry {
        let defaults = UserDefaults(suiteName: sharedWidgetSuite)
        let rawTasks = defaults?.array(forKey: sharedUpcomingTasksKey) as? [[String: Any]] ?? []

        let tasks = rawTasks.compactMap { raw -> SharedUpcomingTask? in
            guard
                let id = raw["id"] as? String,
                let title = raw["title"] as? String,
                let taskType = raw["taskType"] as? String,
                let startMs = raw["startTime"] as? Double
            else {
                return nil
            }

            let endMs = raw["endTime"] as? Double
            return SharedUpcomingTask(
                id: id,
                title: title,
                startTime: Date(timeIntervalSince1970: startMs / 1000),
                endTime: endMs.map { Date(timeIntervalSince1970: $0 / 1000) },
                location: raw["location"] as? String,
                taskType: taskType,
                isCompleted: raw["isCompleted"] as? Bool ?? false,
                reminderEnabled: raw["reminderEnabled"] as? Bool ?? false,
                reminderMinutesBefore: raw["reminderMinutesBefore"] as? Int ?? 0
            )
        }

        return AgendaEntry(date: .now, tasks: tasks)
    }
}

private struct LockScreenView: View {
    let attributes: CalendarLiveActivityAttributes
    let state: CalendarLiveActivityAttributes.CalendarTaskState

    var body: some View {
        let accent = taskAccentColor(for: attributes.taskType)
        let statusText = liveActivityStatusText(
            startTime: state.startTime,
            endTime: state.endTime,
            isCompleted: state.isCompleted
        )
        let statusColor = liveActivityStatusColor(
            startTime: state.startTime,
            endTime: state.endTime,
            isCompleted: state.isCompleted
        )

        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3)
                .frame(maxHeight: 72)

            VStack(alignment: .leading, spacing: 6) {
                Text(liveActivityPrimaryTimeText(
                    startTime: state.startTime,
                    endTime: state.endTime,
                    isCompleted: state.isCompleted
                ))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

                Text(state.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let preview = descriptionPreview(state.description) {
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(statusText.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.14), in: Capsule())

                    if let location = state.location, !location.isEmpty {
                        Label(location, systemImage: "mappin")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "calendar")
                .font(.system(size: 18))
                .foregroundColor(accent)
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct CompactLeadingView: View {
    let attributes: CalendarLiveActivityAttributes
    let state: CalendarLiveActivityAttributes.CalendarTaskState

    var body: some View {
        let accent = taskAccentColor(for: attributes.taskType)
        let phase = liveActivityPhase(
            startTime: state.startTime,
            endTime: state.endTime,
            isCompleted: state.isCompleted
        )

        ZStack {
            Circle()
                .fill(accent.opacity(phase == .future ? 0.18 : 0.28))
                .frame(width: 24, height: 24)

            Image(
                systemName: phaseSymbolName(
                    startTime: state.startTime,
                    endTime: state.endTime,
                    isCompleted: state.isCompleted
                )
            )
            .foregroundColor(accent)
            .font(.system(size: 12, weight: .semibold))
        }
    }
}

private struct CompactTrailingView: View {
    let state: CalendarLiveActivityAttributes.CalendarTaskState

    var body: some View {
        let phase = liveActivityPhase(
            startTime: state.startTime,
            endTime: state.endTime,
            isCompleted: state.isCompleted
        )

        Group {
            if let text = compactIslandTimeText(
                startTime: state.startTime,
                endTime: state.endTime,
                isCompleted: state.isCompleted
            ) {
                Text(text)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        phase == .ongoing
                            ? Color.white.opacity(0.16)
                            : Color.white.opacity(0.08),
                        in: Capsule()
                    )
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
            }
        }
    }
}

private struct MinimalView: View {
    let attributes: CalendarLiveActivityAttributes
    let state: CalendarLiveActivityAttributes.CalendarTaskState

    var body: some View {
        let accent = taskAccentColor(for: attributes.taskType)

        ZStack {
            Circle()
                .fill(accent.opacity(0.22))
                .frame(width: 28, height: 28)

            Image(
                systemName: phaseSymbolName(
                    startTime: state.startTime,
                    endTime: state.endTime,
                    isCompleted: state.isCompleted
                )
            )
            .foregroundColor(accent)
            .font(.system(size: 12, weight: .bold))
        }
    }
}

private struct ExpandedView: View {
    let attributes: CalendarLiveActivityAttributes
    let state: CalendarLiveActivityAttributes.CalendarTaskState

    var body: some View {
        let accent = taskAccentColor(for: attributes.taskType)
        let phase = liveActivityPhase(
            startTime: state.startTime,
            endTime: state.endTime,
            isCompleted: state.isCompleted
        )
        let statusColor = liveActivityStatusColor(
            startTime: state.startTime,
            endTime: state.endTime,
            isCompleted: state.isCompleted
        )

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(accent)
                Text("Calendar++")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(liveActivityStatusText(
                    startTime: state.startTime,
                    endTime: state.endTime,
                    isCompleted: state.isCompleted
                ))
                    .font(.caption2.bold())
                    .foregroundColor(statusColor)
                Spacer()
                Text(headerTimeText(phase: phase))
                    .font(.caption2.bold())
                    .foregroundColor(accent)
            }

            Text(state.title)
                .font(.headline)
                .foregroundColor(.primary)
                .lineLimit(2)

            if let preview = descriptionPreview(state.description) {
                Text(preview)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 16) {
                Label(
                    liveActivityPrimaryTimeText(
                        startTime: state.startTime,
                        endTime: state.endTime,
                        isCompleted: state.isCompleted
                    ),
                    systemImage: phase == .ongoing ? "hourglass.bottomhalf.filled" : "clock"
                )
                    .font(.caption.bold())
                    .foregroundColor(accent)
            }

            HStack(spacing: 12) {
                Text(
                    liveActivityStatusText(
                        startTime: state.startTime,
                        endTime: state.endTime,
                        isCompleted: state.isCompleted
                    )
                )
                    .font(.caption)
                    .foregroundColor(statusColor)

                if let location = state.location, !location.isEmpty {
                    Label(location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(12)
    }

    private func headerTimeText(phase: LiveActivityPhase) -> String {
        switch phase {
        case .ongoing:
            if let endTime = state.endTime {
                return "until \(timeString(endTime))"
            }
            return "live"
        case .completed:
            return "done"
        case .upcoming, .future:
            return timerInterval(state.startTime)
        }
    }

    private func timerInterval(_ start: Date) -> String {
        let difference = start.timeIntervalSinceNow
        if difference <= 0 {
            return "now"
        }
        let minutes = Int(difference / 60)
        if minutes < 60 {
            return "in \(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "in \(hours)h" : "in \(hours)h \(remainder)m"
    }
}

private struct ExpandedTrailingView: View {
    let state: CalendarLiveActivityAttributes.CalendarTaskState

    var body: some View {
        let phase = liveActivityPhase(
            startTime: state.startTime,
            endTime: state.endTime,
            isCompleted: state.isCompleted
        )
        let accent = liveActivityStatusColor(
            startTime: state.startTime,
            endTime: state.endTime,
            isCompleted: state.isCompleted
        )

        VStack(alignment: .trailing, spacing: 8) {
            Text(
                phase == .ongoing
                    ? (state.endTime.map(relativeTimerText) ?? "Now")
                    : relativeTimerText(to: state.startTime)
            )
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundColor(accent)

            Text(
                phase == .ongoing
                    ? "until \(state.endTime.map(timeString) ?? "now")"
                    : "starts \(timeString(state.startTime))"
            )
            .font(.caption2)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct AgendaWidgetView: View {
    let entry: AgendaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            accessoryView
        default:
            standardView
        }
    }

    private var standardView: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.09, blue: 0.15),
                    Color(red: 0.14, green: 0.18, blue: 0.24),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Up Next")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                    Spacer()
                    Text("\(entry.tasks.count) items")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                }

                if entry.tasks.isEmpty {
                    Text("Nothing queued right now.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                } else {
                    ForEach(entry.tasks.prefix(3)) { task in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(taskAccentColor(for: task.taskType))
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(task.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(taskLine(task))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                                    .lineLimit(1)
                            }

                            Spacer()
                        }
                    }
                }
            }
            .padding(16)
        }
        .widgetURL(entry.tasks.first.flatMap { taskDeepLink(taskId: $0.id) })
        .containerBackground(for: .widget) {
            Color.clear
        }
    }

    private var accessoryView: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let task = entry.tasks.first {
                Text(task.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(taskLine(task))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            } else {
                Text("No upcoming items")
                    .font(.system(size: 13, weight: .semibold))
                Text("Open Calendar++")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .widgetURL(entry.tasks.first.flatMap { taskDeepLink(taskId: $0.id) })
    }

    private func taskLine(_ task: SharedUpcomingTask) -> String {
        if let location = task.location, !location.isEmpty {
            return "\(timeString(task.startTime)) • \(location)"
        }

        return "\(timeString(task.startTime)) • \(taskStatusLabel(for: task))"
    }

    private func taskStatusLabel(for task: SharedUpcomingTask) -> String {
        liveActivityStatusText(
            startTime: task.startTime,
            endTime: task.endTime,
            isCompleted: task.isCompleted
        )
    }
}

private struct CalendarAgendaWidget: Widget {
    let kind = "CalendarAgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpcomingTasksProvider()) { entry in
            AgendaWidgetView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("Shows the next Calendar++ items on your Home Screen or Lock Screen.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

private struct CalendarLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CalendarLiveActivityAttributes.self) { context in
            LockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .activityBackgroundTint(Color(UIColor.systemBackground))
            .widgetURL(taskDeepLink(taskId: context.attributes.taskId))
            } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CompactLeadingView(attributes: context.attributes, state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedView(
                        attributes: context.attributes,
                        state: context.state
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(state: context.state)
                }
            } compactLeading: {
                CompactLeadingView(attributes: context.attributes, state: context.state)
            } compactTrailing: {
                CompactTrailingView(state: context.state)
            } minimal: {
                MinimalView(attributes: context.attributes, state: context.state)
            }
            .keylineTint(taskAccentColor(for: context.attributes.taskType))
            .widgetURL(taskDeepLink(taskId: context.attributes.taskId))
        }
    }
}

@main
struct CalendarLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        CalendarLiveActivityWidget()
        CalendarAgendaWidget()
    }
}

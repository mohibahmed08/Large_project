// CalendarLiveActivityAttributes.swift
// Defines the static + dynamic data for the Calendar++ Live Activity
//
// Requires iOS 16.2+ / Xcode 14.1+
// Add ActivityKit.framework and WidgetKit.framework to the extension target.

import ActivityKit
import Foundation

// ─── Attribute struct (static data that doesn't change) ──────────────────────
public struct CalendarLiveActivityAttributes: ActivityAttributes {
    public typealias ContentState = CalendarTaskState

    /// Task identifier (used to route tap back to the app)
    public let taskId: String

    /// Calendar task type drives the accent colour shown in the widget
    public let taskType: String   // "task" | "plan" | "event" | "ical"

    public init(taskId: String, taskType: String) {
        self.taskId   = taskId
        self.taskType = taskType
    }

    // ─── Dynamic state (updated via push-to-update or local update) ──────────
    public struct CalendarTaskState: Codable, Hashable {
        public var title:       String
        public var startTime:   Date
        public var endTime:     Date?
        public var location:    String?
        public var isCompleted: Bool

        public init(
            title:       String,
            startTime:   Date,
            endTime:     Date?    = nil,
            location:    String?  = nil,
            isCompleted: Bool     = false
        ) {
            self.title       = title
            self.startTime   = startTime
            self.endTime     = endTime
            self.location    = location
            self.isCompleted = isCompleted
        }
    }
}

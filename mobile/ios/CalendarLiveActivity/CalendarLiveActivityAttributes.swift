import ActivityKit
import Foundation

public struct CalendarLiveActivityAttributes: ActivityAttributes {
    public typealias ContentState = CalendarTaskState

    public let taskId: String
    public let taskType: String

    public init(taskId: String, taskType: String) {
        self.taskId = taskId
        self.taskType = taskType
    }

    public struct CalendarTaskState: Codable, Hashable {
        public var title: String
        public var startTime: Date
        public var endTime: Date?
        public var description: String?
        public var location: String?
        public var isCompleted: Bool

        public init(
            title: String,
            startTime: Date,
            endTime: Date? = nil,
            description: String? = nil,
            location: String? = nil,
            isCompleted: Bool = false
        ) {
            self.title = title
            self.startTime = startTime
            self.endTime = endTime
            self.description = description
            self.location = location
            self.isCompleted = isCompleted
        }
    }
}

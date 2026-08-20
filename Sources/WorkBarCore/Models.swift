import Foundation

public enum WorkBarCore {
    public static let schemaVersion = 1
}

public enum TaskStatus: String, Codable, Equatable, Sendable {
    case pending
    case completed
}

public struct TaskItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var title: String
    public var budgetSeconds: TimeInterval
    public var elapsedSeconds: TimeInterval
    public var status: TaskStatus
    public var sortOrder: Int
    public var externalID: String?

    public init(
        id: UUID = UUID(),
        title: String,
        budgetSeconds: TimeInterval,
        elapsedSeconds: TimeInterval = 0,
        status: TaskStatus = .pending,
        sortOrder: Int = 0,
        externalID: String? = nil)
    {
        self.id = id
        self.title = title
        self.budgetSeconds = max(0, budgetSeconds)
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.status = status
        self.sortOrder = sortOrder
        self.externalID = externalID
    }
}

public struct DayPlan: Codable, Equatable, Sendable {
    public var dateKey: String
    public var totalBudgetSeconds: TimeInterval
    public var tasks: [TaskItem]

    public init(
        dateKey: String,
        totalBudgetSeconds: TimeInterval = 8 * 60 * 60,
        tasks: [TaskItem] = [])
    {
        self.dateKey = dateKey
        self.totalBudgetSeconds = max(0, totalBudgetSeconds)
        self.tasks = tasks
    }
}

public struct ActiveTimer: Codable, Equatable, Sendable {
    public var dayKey: String
    public var taskID: UUID
    public var startedAt: Date

    public init(dayKey: String, taskID: UUID, startedAt: Date) {
        self.dayKey = dayKey
        self.taskID = taskID
        self.startedAt = startedAt
    }
}

public struct AppState: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var selectedDate: String
    public var dayPlans: [String: DayPlan]
    public var activeTimer: ActiveTimer?

    public init(
        selectedDate: String,
        dayPlans: [String: DayPlan] = [:],
        activeTimer: ActiveTimer? = nil,
        schemaVersion: Int = WorkBarCore.schemaVersion)
    {
        self.schemaVersion = schemaVersion
        self.selectedDate = selectedDate
        self.dayPlans = dayPlans
        self.activeTimer = activeTimer
    }
}

public struct DaySummary: Equatable, Sendable {
    public let totalBudgetSeconds: TimeInterval
    public let assignedBudgetSeconds: TimeInterval
    public let elapsedSeconds: TimeInterval

    public var unallocatedSeconds: TimeInterval {
        max(0, self.totalBudgetSeconds - self.assignedBudgetSeconds)
    }

    public var overAllocatedSeconds: TimeInterval {
        max(0, self.assignedBudgetSeconds - self.totalBudgetSeconds)
    }
}

public enum WorkBarDate {
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0)
    }
}

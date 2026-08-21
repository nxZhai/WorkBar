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
    public var showCompletedTasks: Bool

    public init(
        selectedDate: String,
        dayPlans: [String: DayPlan] = [:],
        activeTimer: ActiveTimer? = nil,
        showCompletedTasks: Bool = true,
        schemaVersion: Int = WorkBarCore.schemaVersion)
    {
        self.schemaVersion = schemaVersion
        self.selectedDate = selectedDate
        self.dayPlans = dayPlans
        self.activeTimer = activeTimer
        self.showCompletedTasks = showCompletedTasks
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case selectedDate
        case dayPlans
        case activeTimer
        case showCompletedTasks
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        self.selectedDate = try values.decode(String.self, forKey: .selectedDate)
        self.dayPlans = try values.decode([String: DayPlan].self, forKey: .dayPlans)
        self.activeTimer = try values.decodeIfPresent(ActiveTimer.self, forKey: .activeTimer)
        self.showCompletedTasks = try values.decodeIfPresent(Bool.self, forKey: .showCompletedTasks) ?? true
    }
}

public struct ReminderTaskSpec: Equatable, Sendable {
    public let title: String
    public let budgetSeconds: TimeInterval

    public init(title: String, budgetSeconds: TimeInterval) {
        self.title = title
        self.budgetSeconds = budgetSeconds
    }
}

public enum ReminderTaskParser {
    public static func parse(_ reminderTitle: String) -> ReminderTaskSpec? {
        let pattern = #"^\[(?:(\d+)h|(\d+)m|(\d+)h(\d+)m)\]\s*(.+)$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: reminderTitle,
                range: NSRange(reminderTitle.startIndex..<reminderTitle.endIndex, in: reminderTitle))
        else { return nil }

        func capturedInt(_ index: Int) -> Int? {
            let range = match.range(at: index)
            guard range.location != NSNotFound,
                  let valueRange = Range(range, in: reminderTitle)
            else { return nil }
            return Int(reminderTitle[valueRange])
        }

        func hasCapture(_ index: Int) -> Bool {
            match.range(at: index).location != NSNotFound
        }

        let hours = capturedInt(1) ?? capturedInt(3) ?? 0
        let minutes = capturedInt(2) ?? capturedInt(4) ?? 0
        guard (!hasCapture(1) || capturedInt(1) != nil),
              (!hasCapture(2) || capturedInt(2) != nil),
              (!hasCapture(3) || capturedInt(3) != nil),
              (!hasCapture(4) || capturedInt(4) != nil)
        else { return nil }
        guard let titleRange = Range(match.range(at: 5), in: reminderTitle) else { return nil }
        let title = reminderTitle[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
        let budgetSeconds = Double(hours) * 60 * 60 + Double(minutes) * 60
        guard !title.isEmpty, budgetSeconds.isFinite else { return nil }
        return ReminderTaskSpec(title: title, budgetSeconds: budgetSeconds)
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

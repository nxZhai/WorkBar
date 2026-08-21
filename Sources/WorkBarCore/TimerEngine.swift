import Foundation

public struct TimerEngine: Sendable {
    public private(set) var state: AppState
    private let calendar: Calendar

    public init(state: AppState, calendar: Calendar = .current) {
        self.state = state
        self.calendar = calendar
    }

    public init(now: Date = Date(), totalBudgetSeconds: TimeInterval = 8 * 60 * 60, calendar: Calendar = .current) {
        self.calendar = calendar
        let dayKey = WorkBarDate.key(for: now, calendar: calendar)
        self.state = AppState(
            selectedDate: dayKey,
            dayPlans: [dayKey: DayPlan(dateKey: dayKey, totalBudgetSeconds: totalBudgetSeconds)])
    }

    public var today: DayPlan {
        self.state.dayPlans[self.state.selectedDate]
            ?? DayPlan(dateKey: self.state.selectedDate)
    }

    public var activeTaskID: UUID? {
        self.state.activeTimer?.taskID
    }

    public mutating func addTask(
        title: String,
        budgetSeconds: TimeInterval,
        externalID: String? = nil) -> UUID?
    {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var plan = self.ensureSelectedPlan()
        let id = UUID()
        plan.tasks.append(TaskItem(
            id: id,
            title: trimmed,
            budgetSeconds: budgetSeconds,
            sortOrder: plan.tasks.count,
            externalID: externalID))
        self.state.dayPlans[plan.dateKey] = plan
        return id
    }

    public mutating func updateTask(
        id: UUID,
        title: String,
        budgetSeconds: TimeInterval) -> Bool
    {
        guard let index = self.taskIndex(id: id, in: self.state.selectedDate) else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        var plan = self.ensureSelectedPlan()
        plan.tasks[index].title = trimmed
        plan.tasks[index].budgetSeconds = max(0, budgetSeconds)
        self.state.dayPlans[plan.dateKey] = plan
        return true
    }

    public mutating func deleteTask(id: UUID, now: Date) -> Bool {
        if self.activeTaskID == id {
            self.pause(at: now)
        }
        var plan = self.ensureSelectedPlan()
        guard let index = plan.tasks.firstIndex(where: { $0.id == id }) else { return false }
        plan.tasks.remove(at: index)
        self.reindex(&plan)
        self.state.dayPlans[plan.dateKey] = plan
        return true
    }

    public mutating func setCompleted(_ completed: Bool, id: UUID, now: Date) -> Bool {
        if self.activeTaskID == id {
            self.pause(at: now)
        }
        var plan = self.ensureSelectedPlan()
        guard let index = plan.tasks.firstIndex(where: { $0.id == id }) else { return false }
        plan.tasks[index].status = completed ? .completed : .pending
        self.state.dayPlans[plan.dateKey] = plan
        return true
    }

    public mutating func moveTask(id: UUID, to destination: Int) -> Bool {
        var plan = self.ensureSelectedPlan()
        guard let source = plan.tasks.firstIndex(where: { $0.id == id }), !plan.tasks.isEmpty else {
            return false
        }
        let item = plan.tasks.remove(at: source)
        let target = min(max(destination, 0), plan.tasks.count)
        plan.tasks.insert(item, at: target)
        self.reindex(&plan)
        self.state.dayPlans[plan.dateKey] = plan
        return true
    }

    public mutating func moveTask(id: UUID, before targetID: UUID) -> Bool {
        let plan = self.ensureSelectedPlan()
        guard let source = plan.tasks.firstIndex(where: { $0.id == id }),
              let target = plan.tasks.firstIndex(where: { $0.id == targetID }),
              source != target
        else { return false }
        let destination = source < target ? target - 1 : target
        guard source != destination else { return false }
        return self.moveTask(id: id, to: destination)
    }

    public mutating func moveTask(id: UUID, after targetID: UUID) -> Bool {
        let plan = self.ensureSelectedPlan()
        guard let source = plan.tasks.firstIndex(where: { $0.id == id }),
              let target = plan.tasks.firstIndex(where: { $0.id == targetID }),
              source != target
        else { return false }
        let destination = source < target ? target : target + 1
        return self.moveTask(id: id, to: destination)
    }

    public mutating func setTotalBudget(seconds: TimeInterval) {
        var plan = self.ensureSelectedPlan()
        plan.totalBudgetSeconds = max(0, seconds)
        self.state.dayPlans[plan.dateKey] = plan
    }

    public mutating func start(taskID: UUID, at now: Date) -> Bool {
        self.settleActive(at: now)
        let dayKey = WorkBarDate.key(for: now, calendar: self.calendar)
        self.state.selectedDate = dayKey
        let plan = self.ensureSelectedPlan()
        guard let task = plan.tasks.first(where: { $0.id == taskID }), task.status == .pending else {
            return false
        }
        self.state.activeTimer = ActiveTimer(dayKey: dayKey, taskID: taskID, startedAt: now)
        return true
    }

    public mutating func pause(at now: Date) {
        self.settleActive(at: now)
        self.state.activeTimer = nil
        self.state.selectedDate = WorkBarDate.key(for: now, calendar: self.calendar)
        _ = self.ensureSelectedPlan()
    }

    public mutating func settle(at now: Date) {
        self.settleActive(at: now)
    }

    public func elapsedSeconds(for taskID: UUID, at now: Date) -> TimeInterval {
        guard let task = self.today.tasks.first(where: { $0.id == taskID }) else { return 0 }
        guard let active = self.state.activeTimer,
              active.taskID == taskID,
              active.dayKey == self.state.selectedDate
        else { return task.elapsedSeconds }
        return task.elapsedSeconds + max(0, now.timeIntervalSince(active.startedAt))
    }

    public func remainingSeconds(for taskID: UUID, at now: Date) -> TimeInterval {
        guard let task = self.today.tasks.first(where: { $0.id == taskID }) else { return 0 }
        return task.budgetSeconds - self.elapsedSeconds(for: taskID, at: now)
    }

    public func summary(at now: Date) -> DaySummary {
        let plan = self.today
        return DaySummary(
            totalBudgetSeconds: plan.totalBudgetSeconds,
            assignedBudgetSeconds: plan.tasks.reduce(0) { $0 + $1.budgetSeconds },
            elapsedSeconds: plan.tasks.reduce(0) { $0 + self.elapsedSeconds(for: $1.id, at: now) })
    }

    private mutating func settleActive(at now: Date) {
        guard var active = self.state.activeTimer else {
            self.state.selectedDate = WorkBarDate.key(for: now, calendar: self.calendar)
            _ = self.ensureSelectedPlan()
            return
        }
        let nowKey = WorkBarDate.key(for: now, calendar: self.calendar)
        if active.dayKey != nowKey {
            let boundary = self.calendar.date(
                byAdding: .day,
                value: 1,
                to: self.calendar.startOfDay(for: active.startedAt)) ?? now
            self.addElapsed(
                max(0, min(now.timeIntervalSince(active.startedAt), boundary.timeIntervalSince(active.startedAt))),
                to: active.taskID,
                in: active.dayKey)
            self.state.activeTimer = nil
            self.state.selectedDate = nowKey
            _ = self.ensureSelectedPlan()
            return
        }
        let delta = max(0, now.timeIntervalSince(active.startedAt))
        self.addElapsed(delta, to: active.taskID, in: active.dayKey)
        active.startedAt = now
        self.state.activeTimer = active
        self.state.selectedDate = nowKey
    }

    private mutating func addElapsed(_ seconds: TimeInterval, to taskID: UUID, in dayKey: String) {
        guard seconds > 0, var plan = self.state.dayPlans[dayKey],
              let index = plan.tasks.firstIndex(where: { $0.id == taskID })
        else { return }
        plan.tasks[index].elapsedSeconds += seconds
        self.state.dayPlans[dayKey] = plan
    }

    private mutating func ensureSelectedPlan() -> DayPlan {
        if let plan = self.state.dayPlans[self.state.selectedDate] {
            return plan
        }
        let plan = DayPlan(dateKey: self.state.selectedDate)
        self.state.dayPlans[plan.dateKey] = plan
        return plan
    }

    private func taskIndex(id: UUID, in dayKey: String) -> Int? {
        self.state.dayPlans[dayKey]?.tasks.firstIndex(where: { $0.id == id })
    }

    private func reindex(_ plan: inout DayPlan) {
        for index in plan.tasks.indices {
            plan.tasks[index].sortOrder = index
        }
    }
}

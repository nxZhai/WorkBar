import Foundation
import Observation
import WorkBarCore

@MainActor
@Observable
final class WorkBarModel {
    var engine: TimerEngine
    var now: Date
    var errorMessage: String?
    var importMessage: String?
    var isImportingReminders = false
    var onChange: (@MainActor () -> Void)?

    private let store: StateStore
    private let remindersImporter = RemindersImporter()
    private let reminderRefreshInterval: TimeInterval = 15 * 60
    private var ticker: Timer?
    private var lastReminderSyncAt: Date?
    private var persistenceDisabled = false

    init(now: Date = Date(), store: StateStore = StateStore()) {
        self.store = store
        self.now = now
        let hadStateFile = FileManager.default.fileExists(atPath: store.fileURL.path)

        do {
            let state = try store.loadOrCreate(now: now)
            self.engine = TimerEngine(state: state)
        } catch let error as StateStoreError {
            self.errorMessage = error.localizedDescription
            self.persistenceDisabled = true
            self.engine = TimerEngine(now: now)
        } catch {
            self.errorMessage = error.localizedDescription
            self.persistenceDisabled = true
            self.engine = TimerEngine(now: now)
        }

        let oldState = self.engine.state
        self.engine.settle(at: now)
        if oldState != self.engine.state || !hadStateFile {
            self.persist()
        }
        self.startTicker()
        self.syncRemindersOnLaunch()
    }

    var tasks: [TaskItem] {
        self.engine.today.tasks.sorted { $0.sortOrder < $1.sortOrder }
    }

    var summary: DaySummary {
        self.engine.summary(at: self.now)
    }

    var history: [DayPlan] {
        self.engine.state.dayPlans.values
            .filter { $0.dateKey != self.engine.state.selectedDate }
            .sorted { $0.dateKey > $1.dateKey }
    }

    func isActive(_ taskID: UUID) -> Bool {
        self.engine.activeTaskID == taskID
    }

    func elapsed(for taskID: UUID) -> TimeInterval {
        self.engine.elapsedSeconds(for: taskID, at: self.now)
    }

    func remaining(for taskID: UUID) -> TimeInterval {
        self.engine.remainingSeconds(for: taskID, at: self.now)
    }

    func start(_ taskID: UUID) {
        let current = Date()
        guard self.engine.start(taskID: taskID, at: current) else { return }
        self.now = current
        self.persist()
    }

    func pause() {
        self.pause(at: Date())
    }

    func pauseForSystemEvent() {
        self.pause(at: Date())
    }

    func toggle(_ taskID: UUID) {
        if self.isActive(taskID) {
            self.pause()
        } else {
            self.start(taskID)
        }
    }

    func addTask(title: String, budgetMinutes: Double) {
        guard self.engine.addTask(title: title, budgetSeconds: max(0, budgetMinutes) * 60) != nil else {
            return
        }
        self.persist()
    }

    func updateTask(id: UUID, title: String, budgetMinutes: Double) {
        guard self.engine.updateTask(
            id: id,
            title: title,
            budgetSeconds: max(0, budgetMinutes) * 60)
        else { return }
        self.persist()
    }

    func deleteTask(_ taskID: UUID) {
        _ = self.engine.deleteTask(id: taskID, now: Date())
        self.persist()
    }

    func setCompleted(_ completed: Bool, taskID: UUID) {
        guard self.engine.setCompleted(completed, id: taskID, now: Date()) else { return }
        self.persist()

        guard let externalID = self.engine.today.tasks.first(where: { $0.id == taskID })?.externalID else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try self.remindersImporter.setReminderCompleted(completed, id: externalID)
            } catch {
                self.errorMessage = error.localizedDescription
                self.onChange?()
            }
        }
    }

    func moveTask(_ taskID: UUID, by offset: Int) {
        guard let index = self.tasks.firstIndex(where: { $0.id == taskID }) else { return }
        guard self.engine.moveTask(id: taskID, to: index + offset) else { return }
        self.persist()
    }

    func setTotalBudget(minutes: Double) {
        self.engine.setTotalBudget(seconds: max(0, minutes) * 60)
        self.persist()
    }

    func refreshReminders() {
        self.syncReminders()
    }

    private func syncRemindersOnLaunch() {
        self.syncReminders()
    }

    private func syncReminders() {
        guard !self.isImportingReminders else { return }
        self.isImportingReminders = true
        self.lastReminderSyncAt = Date()
        self.importMessage = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isImportingReminders = false }
            do {
                let reminders = try await self.remindersImporter.fetchIncompleteReminders()
                var added = 0
                var updated = 0
                for reminder in reminders {
                    if let task = self.engine.today.tasks.first(where: { $0.externalID == reminder.id }) {
                        if task.title != reminder.title,
                           self.engine.updateTask(
                               id: task.id,
                               title: reminder.title,
                               budgetSeconds: task.budgetSeconds)
                        {
                            updated += 1
                        }
                    } else if self.engine.addTask(
                        title: reminder.title,
                        budgetSeconds: 30 * 60,
                        externalID: reminder.id) != nil
                    {
                        added += 1
                    }
                }
                if added > 0 || updated > 0 {
                    self.persist()
                }
                self.importMessage = if added == 0, updated == 0 {
                    "提醒事项已是最新。"
                } else {
                    "同步完成：新增 \(added) 项，更新 \(updated) 项。"
                }
                self.onChange?()
            } catch {
                self.errorMessage = error.localizedDescription
                self.onChange?()
            }
        }
    }

    func shutdown() {
        self.ticker?.invalidate()
        self.ticker = nil
        self.pause(at: Date())
    }

    private func pause(at date: Date) {
        self.engine.pause(at: date)
        self.now = date
        self.persist()
    }

    private func startTicker() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        self.ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let current = Date()
        let currentKey = WorkBarDate.key(for: current)
        if currentKey != self.engine.state.selectedDate {
            self.engine.settle(at: current)
            self.persist()
        }
        self.now = current
        if let lastSync = self.lastReminderSyncAt,
           current.timeIntervalSince(lastSync) >= self.reminderRefreshInterval
        {
            self.syncReminders()
        }
        self.onChange?()
    }

    private func persist() {
        if !self.persistenceDisabled {
            do {
                try self.store.save(self.engine.state)
                self.errorMessage = nil
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
        self.onChange?()
    }
}

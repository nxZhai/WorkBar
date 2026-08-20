import Foundation
import Testing
@testable import WorkBarCore

private let calendar: Calendar = {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(secondsFromGMT: 0)!
    return value
}()

private let start = Date(timeIntervalSince1970: 1_700_000_000)

private func temporaryStore() throws -> (StateStore, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("WorkBarTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return (StateStore(fileURL: directory.appendingPathComponent("state.json")), directory)
}

@Test
func startingAndPausingAccumulatesOnlyActiveTask() {
    var engine = TimerEngine(now: start, calendar: calendar)
    let first = engine.addTask(title: "English", budgetSeconds: 120)!
    let second = engine.addTask(title: "Code", budgetSeconds: 240)!

    let startedFirst = engine.start(taskID: first, at: start)
    #expect(startedFirst)
    engine.pause(at: start.addingTimeInterval(30))
    #expect(engine.elapsedSeconds(for: first, at: start.addingTimeInterval(30)) == 30)
    #expect(engine.elapsedSeconds(for: second, at: start.addingTimeInterval(30)) == 0)

    let startedSecond = engine.start(taskID: second, at: start.addingTimeInterval(40))
    #expect(startedSecond)
    engine.pause(at: start.addingTimeInterval(55))
    #expect(engine.elapsedSeconds(for: first, at: start.addingTimeInterval(55)) == 30)
    #expect(engine.elapsedSeconds(for: second, at: start.addingTimeInterval(55)) == 15)
}

@Test
func summaryKeepsUnallocatedAndOverAllocatedSeparate() {
    var engine = TimerEngine(now: start, totalBudgetSeconds: 8 * 60 * 60, calendar: calendar)
    _ = engine.addTask(title: "English", budgetSeconds: 2 * 60 * 60)
    _ = engine.addTask(title: "Code", budgetSeconds: 4 * 60 * 60)
    #expect(engine.summary(at: start).unallocatedSeconds == 2 * 60 * 60)
    _ = engine.addTask(title: "Other", budgetSeconds: 4 * 60 * 60)
    #expect(engine.summary(at: start).overAllocatedSeconds == 2 * 60 * 60)
}

@Test
func switchingTaskSettlesPreviousTask() {
    var engine = TimerEngine(now: start, calendar: calendar)
    let first = engine.addTask(title: "First", budgetSeconds: 60)!
    let second = engine.addTask(title: "Second", budgetSeconds: 60)!
    let startedFirst = engine.start(taskID: first, at: start)
    #expect(startedFirst)
    let startedSecond = engine.start(taskID: second, at: start.addingTimeInterval(10))
    #expect(startedSecond)
    #expect(engine.elapsedSeconds(for: first, at: start.addingTimeInterval(10)) == 10)
    #expect(engine.activeTaskID == second)
}

@Test
func completedTaskCannotStartAgain() {
    var engine = TimerEngine(now: start, calendar: calendar)
    let task = engine.addTask(title: "Done", budgetSeconds: 60)!
    let completed = engine.setCompleted(true, id: task, now: start)
    #expect(completed)
    let restarted = engine.start(taskID: task, at: start)
    #expect(!restarted)
}

@Test
func midnightStopsActiveTaskAndCreatesNextDayPlan() {
    let late = calendar.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 23, minute: 59, second: 50))!
    var engine = TimerEngine(now: late, calendar: calendar)
    let task = engine.addTask(title: "Late", budgetSeconds: 120)!
    let started = engine.start(taskID: task, at: late)
    #expect(started)
    let afterMidnight = late.addingTimeInterval(20)
    engine.settle(at: afterMidnight)
    #expect(engine.activeTaskID == nil)
    #expect(engine.state.selectedDate == WorkBarDate.key(for: afterMidnight, calendar: calendar))
    #expect(engine.state.dayPlans[WorkBarDate.key(for: late, calendar: calendar)]?.tasks.first?.elapsedSeconds == 10)
}

@Test
func stateStoreRoundTripsAndCreatesParentDirectory() throws {
    let (store, directory) = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    var engine = TimerEngine(now: start, calendar: calendar)
    _ = engine.addTask(title: "Saved", budgetSeconds: 60)

    try store.save(engine.state)
    let loaded = try store.load()
    #expect(loaded == engine.state)
}

@Test
func stateStoreRejectsCorruptedJsonWithoutReplacingIt() throws {
    let (store, directory) = try temporaryStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("{not-json".utf8).write(to: store.fileURL)

    do {
        _ = try store.load()
        Issue.record("Expected corrupted state to throw")
    } catch let error as StateStoreError {
        #expect(error == .corrupted(store.fileURL))
        #expect(try Data(contentsOf: store.fileURL) == Data("{not-json".utf8))
    }
}

@Test
func importedTaskKeepsExternalReminderIdentifier() {
    var engine = TimerEngine(now: start, calendar: calendar)
    let taskID = engine.addTask(
        title: "From Reminders",
        budgetSeconds: 30 * 60,
        externalID: "reminder-123")!
    #expect(engine.today.tasks.first(where: { $0.id == taskID })?.externalID == "reminder-123")
}

@Test
func updatingImportedTaskTitleKeepsBudgetAndElapsedTime() {
    var engine = TimerEngine(now: start, calendar: calendar)
    let taskID = engine.addTask(
        title: "Old reminder title",
        budgetSeconds: 30 * 60,
        externalID: "reminder-123")!
    let started = engine.start(taskID: taskID, at: start)
    #expect(started)
    engine.pause(at: start.addingTimeInterval(45))

    let updated = engine.updateTask(id: taskID, title: "Updated reminder title", budgetSeconds: 30 * 60)
    #expect(updated)
    let task = engine.today.tasks.first(where: { $0.id == taskID })
    #expect(task?.title == "Updated reminder title")
    #expect(task?.budgetSeconds == 1_800.0)
    #expect(task?.elapsedSeconds == 45)
}

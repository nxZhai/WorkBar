import EventKit
import Foundation
import WorkBarCore

struct ReminderImportItem: Identifiable, Sendable {
    let id: String
    let title: String
    let budgetSeconds: TimeInterval
    let listTitle: String
}

enum RemindersImportError: LocalizedError {
    case denied
    case restricted
    case requestFailed(String)
    case reminderNotFound
    case updateFailed(String)

    var errorDescription: String? {
        switch self {
        case .denied:
            "WorkBar 没有提醒事项权限，请在“系统设置 → 隐私与安全性 → 提醒事项”中允许访问。"
        case .restricted:
            "当前 macOS 用户无法访问提醒事项。"
        case let .requestFailed(message):
            "无法读取提醒事项：\(message)"
        case .reminderNotFound:
            "找不到对应的提醒事项，可能已被删除。"
        case let .updateFailed(message):
            "无法更新提醒事项：\(message)"
        }
    }
}

final class RemindersImporter: @unchecked Sendable {
    private let eventStore = EKEventStore()

    func fetchIncompleteReminders() async throws -> [ReminderImportItem] {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        switch status {
        case .fullAccess:
            break
        case .denied:
            throw RemindersImportError.denied
        case .writeOnly:
            throw RemindersImportError.denied
        case .restricted:
            throw RemindersImportError.restricted
        case .notDetermined:
            do {
                guard try await self.eventStore.requestFullAccessToReminders() else {
                    throw RemindersImportError.denied
                }
            } catch let error as RemindersImportError {
                throw error
            } catch {
                throw RemindersImportError.requestFailed(error.localizedDescription)
            }
        @unknown default:
            throw RemindersImportError.denied
        }

        let predicate = self.eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: nil)
        return await withCheckedContinuation { continuation in
            self.eventStore.fetchReminders(matching: predicate) { reminders in
                let items = (reminders ?? []).compactMap { reminder -> ReminderImportItem? in
                    let identifier = reminder.calendarItemIdentifier
                    guard let parsed = ReminderTaskParser.parse(reminder.title) else { return nil }
                    return ReminderImportItem(
                        id: identifier,
                        title: parsed.title,
                        budgetSeconds: parsed.budgetSeconds,
                        listTitle: reminder.calendar?.title ?? "")
                }
                continuation.resume(returning: items)
            }
        }
    }

    func setReminderCompleted(_ completed: Bool, id: String) throws {
        guard let reminder = self.eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersImportError.reminderNotFound
        }
        reminder.isCompleted = completed
        do {
            try self.eventStore.save(reminder, commit: true)
        } catch {
            throw RemindersImportError.updateFailed(error.localizedDescription)
        }
    }
}

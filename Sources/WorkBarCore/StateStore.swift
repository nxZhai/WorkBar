import Foundation

public enum StateStoreError: Error, Equatable, LocalizedError {
    case corrupted(URL)
    case unsupportedSchema(Int)
    case fileSystem(String)

    public var errorDescription: String? {
        switch self {
        case let .corrupted(url):
            "WorkBar 数据文件损坏：\(url.path)"
        case let .unsupportedSchema(version):
            "WorkBar 数据版本暂不支持：\(version)"
        case let .fileSystem(message):
            "WorkBar 无法保存数据：\(message)"
        }
    }
}

public struct StateStore {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL = StateStore.defaultURL(), fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("WorkBar", isDirectory: true)
            .appendingPathComponent("state.json")
    }

    public func load() throws -> AppState? {
        guard self.fileManager.fileExists(atPath: self.fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: self.fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(AppState.self, from: data)
            guard state.schemaVersion <= WorkBarCore.schemaVersion else {
                throw StateStoreError.unsupportedSchema(state.schemaVersion)
            }
            return state
        } catch let error as StateStoreError {
            throw error
        } catch {
            throw StateStoreError.corrupted(self.fileURL)
        }
    }

    public func loadOrCreate(
        now: Date = Date(),
        totalBudgetSeconds: TimeInterval = 8 * 60 * 60,
        calendar: Calendar = .current) throws -> AppState
    {
        if let state = try self.load() {
            return state
        }
        let dateKey = WorkBarDate.key(for: now, calendar: calendar)
        return AppState(
            selectedDate: dateKey,
            dayPlans: [dateKey: DayPlan(dateKey: dateKey, totalBudgetSeconds: totalBudgetSeconds)])
    }

    public func save(_ state: AppState) throws {
        do {
            try self.fileManager.createDirectory(
                at: self.fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: self.fileURL, options: .atomic)
        } catch let error as StateStoreError {
            throw error
        } catch {
            throw StateStoreError.fileSystem(error.localizedDescription)
        }
    }
}

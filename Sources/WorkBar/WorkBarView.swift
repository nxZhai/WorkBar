import SwiftUI
import WorkBarCore

struct WorkBarView: View {
    @Bindable var model: WorkBarModel
    let onQuit: () -> Void

    @State private var showingAddTask = false
    @State private var showingBudgetEditor = false
    @State private var showingHistory = false
    @State private var editingTask: TaskItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("WorkBar")
                        .font(.headline)
                    Text(self.model.engine.state.selectedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: self.onQuit) {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("退出 WorkBar")
            }

            self.summaryView

            if let errorMessage = self.model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            if self.model.tasks.isEmpty {
                ContentUnavailableView(
                    "今天还没有任务",
                    systemImage: "checklist",
                    description: Text("添加一个任务，然后开始记录时间。"))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(self.model.tasks) { task in
                            TaskRow(
                                task: task,
                                model: self.model,
                                index: self.model.tasks.firstIndex(where: { $0.id == task.id }) ?? 0,
                                onEdit: { self.editingTask = task })
                        }
                    }
                }
            }

            HStack {
                Button {
                    self.showingAddTask = true
                } label: {
                    Label("添加任务", systemImage: "plus")
                }
                .keyboardShortcut("n")

                Button {
                    self.showingBudgetEditor = true
                } label: {
                    Label("今日预算", systemImage: "clock")
                }

                Button {
                    self.showingHistory = true
                } label: {
                    Label("历史", systemImage: "calendar")
                }

                Spacer()
            }
        }
        .padding(14)
        .frame(width: 380, height: 460)
        .sheet(isPresented: self.$showingAddTask) {
            TaskEditorView(title: "添加任务", onSave: { title, minutes in
                self.model.addTask(title: title, budgetMinutes: minutes)
            })
        }
        .sheet(item: self.$editingTask) { task in
            TaskEditorView(
                title: "编辑任务",
                initialTitle: task.title,
                initialMinutes: task.budgetSeconds / 60,
                onSave: { title, minutes in
                    self.model.updateTask(id: task.id, title: title, budgetMinutes: minutes)
                })
        }
        .sheet(isPresented: self.$showingBudgetEditor) {
            TaskEditorView(
                title: "今日总预算",
                initialTitle: "",
                initialMinutes: self.model.engine.today.totalBudgetSeconds / 60,
                titleEditable: false,
                onSave: { _, minutes in
                    self.model.setTotalBudget(minutes: minutes)
                })
        }
        .sheet(isPresented: self.$showingHistory) {
            HistoryView(plans: self.model.history)
        }
    }

    private var summaryView: some View {
        let summary = self.model.summary
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("今日工作预算")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(workBarDuration(summary.totalBudgetSeconds))
                    .fontWeight(.semibold)
            }
            HStack(spacing: 12) {
                Text("已用 \(workBarDuration(summary.elapsedSeconds))")
                if summary.overAllocatedSeconds > 0 {
                    Text("超额 \(workBarDuration(summary.overAllocatedSeconds))")
                        .foregroundStyle(.orange)
                } else {
                    Text("未分配 \(workBarDuration(summary.unallocatedSeconds))")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
    }
}

private struct HistoryView: View {
    let plans: [DayPlan]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("历史记录")
                    .font(.headline)
                Spacer()
                Button("完成") { self.dismiss() }
            }

            if self.plans.isEmpty {
                ContentUnavailableView("还没有历史记录", systemImage: "calendar")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(self.plans, id: \.dateKey) { plan in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(plan.dateKey)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text("计划 \(workBarDuration(plan.totalBudgetSeconds))")
                                        .foregroundStyle(.secondary)
                                }
                                Text("已用 \(workBarDuration(plan.tasks.reduce(0) { $0 + $1.elapsedSeconds })) · \(plan.tasks.count) 个任务")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 330, height: 360)
    }
}

private struct TaskRow: View {
    let task: TaskItem
    @Bindable var model: WorkBarModel
    let index: Int
    let onEdit: () -> Void
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    self.model.setCompleted(task.status != .completed, taskID: task.id)
                } label: {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(task.status == .completed ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(task.status == .completed ? "恢复任务" : "完成任务")

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .fontWeight(self.model.isActive(task.id) ? .semibold : .regular)
                        .strikethrough(task.status == .completed)
                        .lineLimit(1)
                    Text("预算 \(workBarDuration(task.budgetSeconds)) · 已用 \(workBarDuration(self.model.elapsed(for: task.id)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(workBarRemaining(self.model.remaining(for: task.id)))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(self.model.remaining(for: task.id) < 0 ? .orange : .secondary)

                Button {
                    self.model.toggle(task.id)
                } label: {
                    Image(systemName: self.model.isActive(task.id) ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.borderless)
                .disabled(task.status == .completed)
                .accessibilityLabel(self.model.isActive(task.id) ? "暂停任务" : "开始任务")

                Menu {
                    Button("编辑", action: self.onEdit)
                    Button("上移") { self.model.moveTask(task.id, by: -1) }
                        .disabled(self.index == 0)
                    Button("下移") { self.model.moveTask(task.id, by: 1) }
                        .disabled(self.index == self.model.tasks.count - 1)
                    Divider()
                    Button("删除", role: .destructive) { self.showingDeleteConfirmation = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("任务菜单")
            }

            if task.budgetSeconds > 0 {
                ProgressView(
                    value: min(1, max(0, self.model.elapsed(for: task.id) / task.budgetSeconds)))
                    .tint(self.model.remaining(for: task.id) < 0 ? .orange : .accentColor)
            }
        }
        .padding(9)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
        .confirmationDialog(
            "删除这个任务？",
            isPresented: self.$showingDeleteConfirmation,
            titleVisibility: .visible)
        {
            Button("删除", role: .destructive) { self.model.deleteTask(task.id) }
            Button("取消", role: .cancel) {}
        }
    }
}

private struct TaskEditorView: View {
    let title: String
    let titleEditable: Bool
    let onSave: (String, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var taskTitle: String
    @State private var minutes: Double

    init(
        title: String,
        initialTitle: String = "",
        initialMinutes: Double = 30,
        titleEditable: Bool = true,
        onSave: @escaping (String, Double) -> Void)
    {
        self.title = title
        self.titleEditable = titleEditable
        self.onSave = onSave
        self._taskTitle = State(initialValue: initialTitle)
        self._minutes = State(initialValue: initialMinutes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(self.title)
                .font(.headline)
            if self.titleEditable {
                TextField("任务名称", text: self.$taskTitle)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Text("预算")
                TextField("分钟", value: self.$minutes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                Text("分钟")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("取消") { self.dismiss() }
                Button("保存") {
                    self.onSave(self.taskTitle, max(0, self.minutes))
                    self.dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(self.titleEditable && self.taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
    }
}

private func workBarDuration(_ seconds: TimeInterval) -> String {
    let totalMinutes = max(0, Int(seconds.rounded(.down)) / 60)
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60
    if hours > 0 {
        return "\(hours)小时 \(minutes)分"
    }
    return "\(minutes)分"
}

private func workBarRemaining(_ seconds: TimeInterval) -> String {
    let sign = seconds < 0 ? "+" : ""
    let total = abs(Int(seconds.rounded(.down)))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let remainingSeconds = total % 60
    if hours > 0 {
        return "\(sign)\(hours):\(String(format: "%02d", minutes))"
    }
    return "\(sign)\(minutes):\(String(format: "%02d", remainingSeconds))"
}

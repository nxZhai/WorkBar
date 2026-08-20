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
            self.headerView
            self.summaryView

            if let errorMessage = self.model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Text("今日任务")
                    .font(.headline)
                Spacer()
                Button {
                    self.model.refreshReminders()
                } label: {
                    if self.model.isImportingReminders {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(self.model.isImportingReminders)
                .help("刷新提醒事项")
                .accessibilityLabel("刷新提醒事项")
            }

            if self.model.tasks.isEmpty {
                ContentUnavailableView(
                    "今天还没有任务",
                    systemImage: "checklist",
                    description: Text("添加任务，或从提醒事项同步。"))
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(self.model.tasks) { task in
                            TaskRow(
                                task: task,
                                model: self.model,
                                index: self.model.tasks.firstIndex(where: { $0.id == task.id }) ?? 0,
                                onEdit: { self.editingTask = task })
                        }
                    }
                }
                .frame(maxHeight: 240)
                .scrollIndicators(.hidden)
            }

            VStack(spacing: 6) {
                self.actionRow(title: "添加任务", systemImage: "plus") {
                    self.showingAddTask = true
                }
                .keyboardShortcut("n")
                self.actionRow(title: "今日预算", systemImage: "clock") {
                    self.showingBudgetEditor = true
                }
                self.actionRow(title: "历史", systemImage: "calendar") {
                    self.showingHistory = true
                }
            }

            if let importMessage = self.model.importMessage {
                Label(importMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(width: 420, height: 580)
        .background(.regularMaterial)
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

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))

            Spacer()

            Button(action: self.onQuit) {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("退出 WorkBar")
            .accessibilityLabel("退出 WorkBar")
        }
    }

    private var summaryView: some View {
        let summary = self.model.summary
        let progress = min(summary.totalBudgetSeconds, summary.elapsedSeconds)
        return VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日工作预算")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(workBarDuration(summary.totalBudgetSeconds))
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                }
                Spacer(minLength: 12)
                ProgressView(value: progress, total: max(1, summary.totalBudgetSeconds))
                    .progressViewStyle(.circular)
                    .tint(.accentColor)
                    .frame(width: 34, height: 34)
            }
            HStack(spacing: 12) {
                Label("已用 \(workBarDuration(summary.elapsedSeconds))", systemImage: "play.fill")
                if summary.overAllocatedSeconds > 0 {
                    Label("超额 \(workBarDuration(summary.overAllocatedSeconds))", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else {
                    Label("未分配 \(workBarDuration(summary.unallocatedSeconds))", systemImage: "square.dashed")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(15)
        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
    }

    private func actionRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                Text(title)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
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
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    self.model.setCompleted(task.status != .completed, taskID: task.id)
                } label: {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.status == .completed ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(task.status == .completed ? "恢复任务" : "完成任务")

                Button {
                    self.isExpanded.toggle()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(task.title)
                                .fontWeight(self.model.isActive(task.id) ? .semibold : .regular)
                                .strikethrough(task.status == .completed)
                                .lineLimit(self.isExpanded ? nil : 2)
                                .multilineTextAlignment(.leading)
                            Image(systemName: self.isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text("预算 \(workBarDuration(task.budgetSeconds)) · 已用 \(workBarDuration(self.model.elapsed(for: task.id)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityLabel(task.title)
                .accessibilityValue(self.isExpanded ? "已展开" : "已收起")
                .accessibilityHint(self.isExpanded ? "点击收起完整内容" : "点击展开完整内容")

                Spacer()

                Text(workBarRemaining(self.model.remaining(for: task.id)))
                    .font(.system(.callout, design: .monospaced).weight(.medium))
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

        }
        .padding(12)
        .background {
            GeometryReader { proxy in
                let shape = RoundedRectangle(cornerRadius: 14)
                ZStack(alignment: .leading) {
                    shape.fill(self.rowBackground)
                    shape.fill(self.progressColor.opacity(0.14))
                        .frame(width: proxy.size.width * self.remainingFraction)
                }
                .clipShape(shape)
            }
        }
        .overlay {
            if self.model.isActive(task.id) {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
            }
        }
        .confirmationDialog(
            "删除这个任务？",
            isPresented: self.$showingDeleteConfirmation,
            titleVisibility: .visible)
        {
            Button("删除", role: .destructive) { self.model.deleteTask(task.id) }
            Button("取消", role: .cancel) {}
        }
    }

    private var remainingFraction: Double {
        guard task.status != .completed, task.budgetSeconds > 0 else { return 0 }
        return min(1, max(0, self.model.remaining(for: task.id) / task.budgetSeconds))
    }

    private var progressColor: Color {
        self.model.remaining(for: task.id) < 0 ? .orange : .accentColor
    }

    private var rowBackground: Color {
        if self.model.remaining(for: task.id) < 0 {
            return .orange.opacity(0.10)
        }
        return self.model.isActive(task.id)
            ? Color.accentColor.opacity(0.12)
            : Color.primary.opacity(0.045)
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

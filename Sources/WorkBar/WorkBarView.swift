import SwiftUI
import WorkBarCore

struct WorkBarView: View {
    @Bindable var model: WorkBarModel
    let onQuit: () -> Void

    @State private var showingHistory = false
    @State private var editingTask: TaskItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.headerView
                .padding(.horizontal, 16)
            self.summaryView
                .padding(.horizontal, 16)
                .padding(.top, 12)

            if let errorMessage = self.model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 9)
            }

            self.taskSection

            self.footerView
                .padding(.horizontal, 16)
                .padding(.top, 12)

            if let importMessage = self.model.importMessage {
                Label(importMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            if let budgetUpdateMessage = self.model.budgetUpdateMessage {
                Label(budgetUpdateMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .padding(.vertical, 10)
        .frame(width: 392, height: 590)
        .background(.ultraThinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .sheet(item: self.$editingTask) { task in
            TaskEditorView(
                title: "编辑任务",
                initialTitle: task.title,
                initialMinutes: task.budgetSeconds / 60,
                onSave: { title, minutes in
                    self.model.updateTask(id: task.id, title: title, budgetMinutes: minutes)
                })
        }
        .sheet(isPresented: self.$showingHistory) {
            HistoryView(plans: self.model.history)
        }
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: "hourglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.background)
                .frame(width: 32, height: 32)
                .background(.primary.opacity(0.86), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("WorkBar")
                    .font(.headline.weight(.semibold))
                Text("今日工作计划")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 3) {
                self.utilityButton(
                    systemImage: "arrow.clockwise",
                    label: "刷新提醒事项",
                    action: self.model.refreshReminders)
                    .overlay {
                        if self.model.isImportingReminders {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .disabled(self.model.isImportingReminders)
                self.utilityButton(systemImage: "power", label: "退出 WorkBar", action: self.onQuit)
            }
        }
    }

    private var summaryView: some View {
        let summary = self.model.summary
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日预算")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(workBarDuration(summary.totalBudgetSeconds))
                        .font(.system(size: 27, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("累计已用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(workBarDuration(summary.elapsedSeconds))
                        .font(.system(.body, design: .monospaced).weight(.medium))
                }
            }
            VStack(spacing: 7) {
                self.summaryProgress(
                    title: "预算分配",
                    value: summary.assignedBudgetSeconds,
                    total: summary.totalBudgetSeconds,
                    tint: summary.overAllocatedSeconds > 0 ? .orange : .primary)
                self.summaryProgress(
                    title: "实际使用",
                    value: summary.elapsedSeconds,
                    total: summary.totalBudgetSeconds,
                    tint: summary.elapsedSeconds > summary.totalBudgetSeconds ? .orange : .primary)
            }
            HStack(spacing: 0) {
                self.summaryMetric("已分配", workBarDuration(summary.assignedBudgetSeconds))
                Divider()
                    .frame(height: 22)
                    .padding(.horizontal, 12)
                if summary.overAllocatedSeconds > 0 {
                    self.summaryMetric("超额", workBarDuration(summary.overAllocatedSeconds), color: .orange)
                } else if summary.unallocatedSeconds > 0 {
                    self.summaryMetric("未分配", workBarDuration(summary.unallocatedSeconds))
                } else {
                    self.summaryMetric("计划", "已分配完")
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
    }

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("今日任务")
                    .font(.headline.weight(.semibold))
                Text("\(self.model.tasks.count)")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.07), in: Capsule())
                Spacer()
                Text(self.model.isImportingReminders ? "同步中" : "提醒事项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)

            if self.model.tasks.isEmpty {
                ContentUnavailableView(
                    self.model.hasHiddenCompletedTasks ? "已隐藏已完成任务" : "今天还没有任务",
                    systemImage: "checklist",
                    description: Text(
                        self.model.hasHiddenCompletedTasks
                            ? "打开“显示已完成任务”即可查看。"
                            : "请在提醒事项中添加带预算前缀的任务，WorkBar 会自动同步。"))
                    .frame(maxWidth: .infinity, minHeight: 92)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                    }
                    .padding(.horizontal, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(self.model.tasks) { task in
                            TaskRow(
                                task: task,
                                model: self.model,
                                onEdit: { self.editingTask = task })
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(maxHeight: 202)
                .scrollIndicators(.hidden)
            }
        }
    }

    private var footerView: some View {
        VStack(spacing: 8) {
            BudgetEditorView(model: self.model)
            Toggle(
                "显示已完成任务",
                isOn: Binding(
                    get: { self.model.showCompletedTasks },
                    set: { self.model.setShowCompletedTasks($0) }))
                .font(.callout)
            self.actionTile(title: "历史", systemImage: "calendar") {
                self.showingHistory = true
            }
        }
    }

    private func utilityButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private func actionTile(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.callout.weight(.medium))
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func summaryMetric(_ title: String, _ value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.medium))
                .foregroundStyle(color ?? .primary)
        }
    }

    private func summaryProgress(
        title: String,
        value: TimeInterval,
        total: TimeInterval,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            ProgressView(value: min(max(0, value), max(1, total)), total: max(1, total))
                .progressViewStyle(.linear)
                .tint(tint)
                .scaleEffect(x: 1, y: 0.7, anchor: .center)
        }
    }
}

private struct BudgetEditorView: View {
    @Bindable var model: WorkBarModel
    @State private var minutesText: String

    init(model: WorkBarModel) {
        self.model = model
        self._minutesText = State(initialValue: Self.displayMinutes(model.engine.today.totalBudgetSeconds))
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 13, weight: .medium))
            Text("今日预算")
                .font(.callout.weight(.medium))
            Spacer(minLength: 8)
            TextField("分钟", text: self.$minutesText)
                .textFieldStyle(.plain)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .multilineTextAlignment(.trailing)
                .frame(width: 58)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .onChange(of: self.minutesText) { _, value in
                    self.save(value)
                }
                .onSubmit {
                    self.commit()
                }
            Text("分钟")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("今日预算，分钟")
        .onChange(of: self.model.engine.state.selectedDate) { _, _ in
            self.minutesText = Self.displayMinutes(self.model.engine.today.totalBudgetSeconds)
        }
    }

    private func save(_ rawValue: String) {
        guard let minutes = Double(rawValue), minutes.isFinite, minutes >= 0 else { return }
        self.model.setTotalBudget(minutes: minutes)
    }

    private func commit() {
        guard let minutes = Double(self.minutesText), minutes.isFinite, minutes >= 0 else {
            self.minutesText = Self.displayMinutes(self.model.engine.today.totalBudgetSeconds)
            return
        }
        self.model.setTotalBudget(minutes: minutes)
        self.minutesText = Self.displayMinutes(minutes * 60)
    }

    private static func displayMinutes(_ seconds: TimeInterval) -> String {
        String(Int(max(0, seconds).rounded(.down) / 60))
    }
}

private struct HistoryView: View {
    let plans: [DayPlan]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("历史记录")
                        .font(.title3.weight(.semibold))
                    Text("每天的计划和实际用时")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { self.dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.bottom, 16)

            if self.plans.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor.opacity(0.12), in: Circle())
                    Text("还没有历史记录")
                        .font(.headline)
                    Text("跨天后，WorkBar 会把每日计划保存在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(self.plans, id: \.dateKey) { plan in
                            let elapsed = plan.tasks.reduce(0) { $0 + $1.elapsedSeconds }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 28, height: 28)
                                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(plan.dateKey)
                                            .font(.callout.weight(.semibold))
                                        Text("\(plan.tasks.count) 个任务")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("已用")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(workBarDuration(elapsed))
                                            .font(.system(.callout, design: .monospaced).weight(.medium))
                                    }
                                }
                                ProgressView(value: min(elapsed, plan.totalBudgetSeconds), total: max(1, plan.totalBudgetSeconds))
                                    .tint(.accentColor)
                                HStack {
                                    Text("计划 \(workBarDuration(plan.totalBudgetSeconds))")
                                    Spacer()
                                    Text("完成率 \(historyCompletion(elapsed, budget: plan.totalBudgetSeconds))")
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.16), lineWidth: 0.75)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 350, height: 390)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func historyCompletion(_ elapsed: TimeInterval, budget: TimeInterval) -> String {
        guard budget > 0 else { return "—" }
        return "\(Int(min(100, max(0, elapsed / budget * 100)).rounded()))%"
    }
}

private struct TaskTitleHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TaskSingleLineHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TaskRowHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TaskRow: View {
    let task: TaskItem
    @Bindable var model: WorkBarModel
    let onEdit: () -> Void
    @State private var showingDeleteConfirmation = false
    @State private var isExpanded = false
    @State private var isDropTarget = false
    @State private var rowHeight: CGFloat = 0
    @State private var titleHeight: CGFloat = 0
    @State private var singleLineTitleHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button {
                    self.model.setCompleted(task.status != .completed, taskID: task.id)
                } label: {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                        .font(.body)
                        .foregroundStyle(task.status == .completed ? .green : .secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(task.status == .completed ? "恢复任务" : "完成任务")

                self.titleControl

                HStack(spacing: 6) {
                    Text(workBarRemaining(self.model.remaining(for: task.id)))
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(self.model.remaining(for: task.id) < 0 ? .orange : .secondary)
                        .frame(minWidth: 34, alignment: .trailing)

                    Button {
                        self.model.toggle(task.id)
                    } label: {
                        Image(systemName: self.model.isActive(task.id) ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .disabled(task.status == .completed)
                    .accessibilityLabel(self.model.isActive(task.id) ? "暂停任务" : "开始任务")

                    Button(action: self.onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("编辑任务")
                    .accessibilityLabel("编辑任务")

                    Button(role: .destructive) {
                        self.showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("删除任务")
                    .accessibilityLabel("删除任务")
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .onPreferenceChange(TaskTitleHeightKey.self) { height in
            if !self.isExpanded {
                self.titleHeight = height
            }
        }
        .onPreferenceChange(TaskSingleLineHeightKey.self) { height in
            self.singleLineTitleHeight = height
        }
        .onPreferenceChange(TaskRowHeightKey.self) { self.rowHeight = $0 }
        .padding(7)
        .background {
            GeometryReader { proxy in
                let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
                ZStack(alignment: .leading) {
                    shape.fill(.thinMaterial)
                    shape.fill(self.rowBackground)
                    shape.fill(self.progressColor.opacity(0.14))
                        .frame(width: proxy.size.width * self.remainingFraction)
                }
                .clipShape(shape)
                .preference(key: TaskRowHeightKey.self, value: proxy.size.height)
            }
        }
        .overlay {
            if self.model.isActive(task.id) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
            } else if self.isDropTarget {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.75), lineWidth: 1)
            }
        }
        .opacity(task.status == .completed ? 0.7 : 1)
        .draggable(task.id.uuidString)
        .dropDestination(for: String.self) { items, location in
            guard let sourceID = items.first.flatMap(UUID.init(uuidString:)), sourceID != task.id else {
                return false
            }
            if location.y > self.rowHeight / 2 {
                self.model.moveTask(sourceID, after: task.id)
            } else {
                self.model.moveTask(sourceID, before: task.id)
            }
            return true
        } isTargeted: { isTargeted in
            self.isDropTarget = isTargeted
        }
        .accessibilityHint("按住并拖动以调整任务顺序")
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
        self.model.remaining(for: task.id) < 0 ? .orange : .white
    }

    private var rowBackground: Color {
        if self.model.remaining(for: task.id) < 0 {
            return .orange.opacity(0.08)
        }
        return self.model.isActive(task.id)
            ? Color.white.opacity(0.12)
            : Color.white.opacity(0.08)
    }

    private var canExpand: Bool {
        self.singleLineTitleHeight > 0
            && self.titleHeight > self.singleLineTitleHeight * 1.35
    }

    @ViewBuilder
    private var titleControl: some View {
        if self.canExpand {
            Button {
                self.isExpanded.toggle()
            } label: {
                self.taskTitleContent
            }
            .buttonStyle(.plain)
            .layoutPriority(1)
            .accessibilityLabel(task.title)
            .accessibilityValue(self.isExpanded ? "已展开" : "已收起")
            .accessibilityHint(self.isExpanded ? "点击收起完整内容" : "点击展开完整内容")
        } else {
            self.taskTitleContent
                .layoutPriority(1)
                .accessibilityLabel(task.title)
        }
    }

    private var taskTitleContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(task.title)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .font(.callout)
                    .fontWeight(self.model.isActive(task.id) ? .semibold : .regular)
                    .strikethrough(task.status == .completed)
                    .lineLimit(self.isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TaskTitleHeightKey.self,
                                value: proxy.size.height)
                        }
                    }
                if self.canExpand {
                    Image(systemName: self.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) {
                Text(task.title)
                    .font(.callout)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .hidden()
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TaskSingleLineHeightKey.self,
                                value: proxy.size.height)
                        }
                    }
            }
            Text("预算 \(workBarDuration(task.budgetSeconds)) · 已用 \(workBarDuration(self.model.elapsed(for: task.id)))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        initialMinutes: Double = 0,
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
    return "\(sign)\(String(format: "%02d:%02d:%02d", hours, minutes, remainingSeconds))"
}

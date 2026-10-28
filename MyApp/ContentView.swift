import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @State private var store = TodoStore()
    @State private var editingItem: TodoItem?
    @State private var isAddingList = false
    @State private var isEditingList = false
    @State private var isSidebarCompact = false

    var body: some View {
        ZStack {
            TodoWorkspace(
                store: store,
                editingItem: $editingItem,
                isAddingList: $isAddingList,
                isEditingList: $isEditingList,
                isSidebarCompact: $isSidebarCompact
            )

            if let reminderID = store.presentedReminderID,
               let item = store.items.first(where: { $0.id == reminderID }) {
                FocusReminderOverlay(
                    title: item.title,
                    notes: item.notes,
                    dueDate: item.dueDate,
                    onComplete: store.completePresentedReminder,
                    onSnooze: { store.snoozePresentedReminder() },
                    onDismiss: store.dismissPresentedReminder
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .frame(minWidth: isSidebarCompact ? 284 : 400, minHeight: 380)
        .ignoresSafeArea(.container, edges: .top)
        #if os(macOS)
        .background(WindowChromeConfigurator(isCompact: isSidebarCompact))
        #endif
        .preferredColorScheme(.dark)
        .sheet(item: $editingItem) { item in
            TaskEditor(item: item, lists: store.lists) { updated in
                store.updateItem(updated)
            }
        }
        .sheet(isPresented: $isAddingList) {
            ListEditor(mode: .add) { name, symbol, color in
                store.addList(name: name, symbol: symbol, color: color)
            }
        }
        .sheet(isPresented: $isEditingList) {
            if let list = store.selectedList {
                ListEditor(mode: .edit(list)) { name, symbol, color in
                    var updated = list
                    updated.name = name
                    updated.symbol = symbol
                    updated.color = color
                    store.updateList(updated)
                }
            }
        }
        .task {
            store.checkReminders()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                store.checkReminders()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: store.presentedReminderID)
    }
}

struct TodoWorkspace: View {
    let store: TodoStore
    @Binding var editingItem: TodoItem?
    @Binding var isAddingList: Bool
    @Binding var isEditingList: Bool
    @Binding var isSidebarCompact: Bool

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                store: store,
                isAddingList: $isAddingList,
                isEditingList: $isEditingList,
                isCompact: $isSidebarCompact
            )
            .frame(width: isSidebarCompact ? 44 : 160)

            Divider()

            TaskListView(store: store, editingItem: $editingItem)
        }
        .background {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.12, blue: 0.16),
                    Color(red: 0.035, green: 0.04, blue: 0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .animation(.easeInOut(duration: 0.30), value: isSidebarCompact)
    }
}

struct SidebarView: View {
    @Bindable var store: TodoStore
    @Binding var isAddingList: Bool
    @Binding var isEditingList: Bool
    @Binding var isCompact: Bool

    var body: some View {
        VStack(spacing: 0) {
            SidebarWindowControls(isCompact: isCompact)

            SidebarHeader(
                activeCount: store.activeCount,
                isCompact: isCompact,
                onToggleCompact: { isCompact.toggle() }
            )

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.lists) { list in
                        Button {
                            store.selectedListID = list.id
                        } label: {
                            SidebarRow(
                                name: list.name,
                                symbol: list.symbol,
                                color: list.color.color,
                                count: store.items.filter {
                                    $0.listID == list.id && !$0.isCompleted
                                }.count,
                                isSelected: store.selectedListID == list.id,
                                isCompact: isCompact
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit List") {
                                store.selectedListID = list.id
                                isEditingList = true
                            }
                            Button("Delete List", role: .destructive) {
                                store.selectedListID = list.id
                                store.deleteSelectedList()
                            }
                            .disabled(store.lists.count <= 1)
                        }
                    }
                }
                .padding(.horizontal, isCompact ? 5 : 9)
                .padding(.vertical, 8)
            }

            SidebarFooter(
                canDelete: store.lists.count > 1,
                isCompact: isCompact,
                onAdd: { isAddingList = true },
                onEdit: { isEditingList = true },
                onDelete: store.deleteSelectedList
            )
        }
        .background(.ultraThinMaterial)
    }
}

struct SidebarHeader: View {
    let activeCount: Int
    let isCompact: Bool
    let onToggleCompact: () -> Void

    var body: some View {
        ZStack {
            HStack(spacing: 7) {
                Text("to-do")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .italic()
                    .tracking(-0.35)

                Spacer()

                Text(activeCount, format: .number)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)

                SidebarToggleButton(
                    isCompact: false,
                    action: onToggleCompact
                )
            }
            .opacity(isCompact ? 0 : 1)
            .allowsHitTesting(!isCompact)

            SidebarToggleButton(
                isCompact: true,
                action: onToggleCompact
            )
            .opacity(isCompact ? 1 : 0)
            .allowsHitTesting(isCompact)
        }
        .padding(.horizontal, isCompact ? 0 : 13)
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.28)
        }
    }
}

struct SidebarToggleButton: View {
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isCompact ? "sidebar.left" : "sidebar.leading")
                .font(.system(size: 10, weight: .medium))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(isCompact ? "Expand sidebar" : "Compact sidebar")
    }
}

struct SidebarRow: View {
    let name: String
    let symbol: String
    let color: Color
    let count: Int
    let isSelected: Bool
    let isCompact: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 20)

                Text(name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if count > 0 {
                    Text(count, format: .number)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(isCompact ? 0 : 1)

            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 27, height: 27)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(
                            isSelected ? color.opacity(0.9) : Color.clear,
                            lineWidth: 1.25
                        )
                }
                .opacity(isCompact ? 1 : 0)
        }
        .padding(.horizontal, isCompact ? 0 : 8)
        .frame(height: 30)
        .background(
            isSelected && !isCompact ? Color.white.opacity(0.075) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
        .help(name)
    }
}

struct SidebarFooter: View {
    let canDelete: Bool
    let isCompact: Bool
    let onAdd: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let layout = isCompact
            ? AnyLayout(VStackLayout(spacing: 3))
            : AnyLayout(HStackLayout(spacing: 2))

        layout {
            CompactIconButton(symbol: "plus", help: "Add list", action: onAdd)
            CompactIconButton(symbol: "pencil", help: "Edit selected list", action: onEdit)
            CompactIconButton(symbol: "trash", help: "Delete selected list", action: onDelete)
                .disabled(!canDelete)
        }
        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
        .padding(isCompact ? 5 : 8)
        .frame(height: isCompact ? 88 : 38)
        .overlay(alignment: .top) {
            Divider().opacity(0.28)
        }
    }
}

struct SidebarWindowControls: View {
    let isCompact: Bool

    var body: some View {
        let layout = isCompact
            ? AnyLayout(VStackLayout(spacing: 7))
            : AnyLayout(HStackLayout(spacing: 7))

        layout {
            WindowActionButton(symbol: "xmark", color: .red, help: "Close") {
                #if os(macOS)
                NSApp.keyWindow?.performClose(nil)
                #endif
            }
            WindowActionButton(symbol: "minus", color: .yellow, help: "Minimize") {
                #if os(macOS)
                NSApp.keyWindow?.performMiniaturize(nil)
                #endif
            }
            WindowActionButton(symbol: "plus", color: .green, help: "Zoom") {
                #if os(macOS)
                NSApp.keyWindow?.performZoom(nil)
                #endif
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: isCompact ? .center : .leading
        )
        .padding(.leading, isCompact ? 0 : 13)
        .frame(height: isCompact ? 70 : 32)
        .animation(.easeInOut(duration: 0.30), value: isCompact)
    }
}

struct WindowActionButton: View {
    @State private var isHovered = false

    let symbol: String
    let color: Color
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 6.5, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 12, height: 12)
                .opacity(isHovered ? 1 : 0)
                .overlay {
                    Circle()
                        .stroke(
                            isHovered ? color : Color.secondary.opacity(0.55),
                            lineWidth: isHovered ? 1.35 : 1
                        )
                        .shadow(
                            color: isHovered ? color.opacity(0.9) : .clear,
                            radius: isHovered ? 4 : 0
                        )
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.22)) {
                isHovered = hovering
            }
        }
        .help(help)
    }
}

struct TaskListView: View {
    @Bindable var store: TodoStore
    @Binding var editingItem: TodoItem?

    var body: some View {
        VStack(spacing: 0) {
            TaskListHeader(
                title: store.selectedList?.name ?? "Tasks",
                count: store.visibleItems.filter { !$0.isCompleted }.count,
                onAdd: addItem
            )

            if store.visibleItems.isEmpty {
                EmptyTasksView(onAdd: addItem)
            } else {
                List(selection: $store.selectedItemID) {
                    ForEach(store.visibleItems) { item in
                        TaskRow(
                            title: item.title,
                            notes: item.notes,
                            isCompleted: item.isCompleted,
                            hasSchedule: item.hasSchedule,
                            dueDate: item.dueDate,
                            hasFocusReminder: item.hasFocusReminder,
                            onToggle: { store.toggleCompleted(item.id) }
                        )
                        .tag(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            editingItem = item
                        }
                        .contextMenu {
                            Button("Edit") { editingItem = item }
                            Divider()
                            Button("Delete", role: .destructive) {
                                store.deleteItem(item.id)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            store.deleteItem(store.visibleItems[index].id)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            TaskListFooter(
                selectionExists: store.selectedItem != nil,
                onEdit: {
                    editingItem = store.selectedItem
                },
                onDelete: {
                    if let id = store.selectedItemID {
                        store.deleteItem(id)
                    }
                }
            )
        }
        .background(.ultraThinMaterial)
    }

    private func addItem() {
        editingItem = store.addItem()
    }
}

struct TaskListHeader: View {
    let title: String
    let count: Int
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Text("\(count) open")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("New task")
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }
}

struct TaskRow: View {
    let title: String
    let notes: String
    let isCompleted: Bool
    let hasSchedule: Bool
    let dueDate: Date
    let hasFocusReminder: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isCompleted ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "Untitled task" : title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isCompleted ? .tertiary : .primary)
                    .strikethrough(isCompleted)
                    .lineLimit(1)
                    .layoutPriority(1)

                if !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if hasFocusReminder {
                Image(systemName: "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 9))
                    .foregroundStyle(.orange)
                    .help("Focus reminder enabled")
            }

            if hasSchedule {
                Text(dueDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(dueDate < Date() && !isCompleted ? .red : .secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 6)
        .frame(minHeight: 39)
    }
}

struct TaskListFooter: View {
    let selectionExists: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            CompactIconButton(symbol: "pencil", help: "Edit selected task", action: onEdit)
                .disabled(!selectionExists)
            CompactIconButton(symbol: "trash", help: "Delete selected task", action: onDelete)
                .disabled(!selectionExists)
            Spacer()
            Text("Double-click a task to edit")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
    }
}

struct EmptyTasksView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing here")
                .font(.system(size: 13, weight: .medium))
            Text("Keep it clear, or add something new.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Button("Add Task", action: onAdd)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CompactIconButton: View {
    let symbol: String
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
    }
}

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TodoItem
    let lists: [TodoList]
    let onSave: (TodoItem) -> Void

    init(item: TodoItem, lists: [TodoList], onSave: @escaping (TodoItem) -> Void) {
        _draft = State(initialValue: item)
        self.lists = lists
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(title: draft.title.isEmpty ? "New task" : "Edit task")

            Form {
                TextField("Task", text: $draft.title)
                    .font(.system(size: 13, weight: .medium))
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(2...5)

                Picker("List", selection: $draft.listID) {
                    ForEach(lists) { list in
                        Label(list.name, systemImage: list.symbol)
                            .tag(list.id)
                    }
                }

                Toggle("Set date & time", isOn: $draft.hasSchedule)
                if draft.hasSchedule {
                    DatePicker(
                        "Due",
                        selection: $draft.dueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    Toggle("Full-screen focus reminder", isOn: $draft.hasFocusReminder)
                    if draft.hasFocusReminder {
                        Text("When due, this task takes over the app with a dark, dim reminder.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .overlay(alignment: .top) {
                Divider().opacity(0.45)
            }
        }
        .frame(width: 430, height: 410)
        .background(Color.black.opacity(0.16))
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct EditorHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.45)
        }
    }
}

enum ListEditorMode {
    case add
    case edit(TodoList)
}

struct ListEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var color: ListColor
    let mode: ListEditorMode
    let onSave: (String, String, ListColor) -> Void

    init(mode: ListEditorMode, onSave: @escaping (String, String, ListColor) -> Void) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _symbol = State(initialValue: "list.bullet")
            _color = State(initialValue: .blue)
        case .edit(let list):
            _name = State(initialValue: list.name)
            _symbol = State(initialValue: list.symbol)
            _color = State(initialValue: list.color)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(title: modeTitle)
            Form {
                TextField("Name", text: $name)
                ListIconPicker(selection: $symbol)
                ListColorPalette(selection: $color)
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), symbol, color)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(14)
            .overlay(alignment: .top) {
                Divider().opacity(0.45)
            }
        }
        .frame(width: 430, height: 490)
        .background(Color.black.opacity(0.16))
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var modeTitle: LocalizedStringKey {
        switch mode {
        case .add: "New list"
        case .edit: "Edit list"
        }
    }
}

struct ListIconPicker: View {
    @Binding var selection: String

    private let symbols = [
        "list.bullet", "checklist", "tray", "archivebox",
        "briefcase", "person", "person.2", "house",
        "cart", "bag", "fork.knife", "cup.and.saucer",
        "lightbulb", "book", "graduationcap", "pencil",
        "heart", "star", "flag", "bookmark",
        "figure.run", "dumbbell", "airplane", "car",
        "gamecontroller", "music.note", "camera", "gift"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Icon")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                spacing: 6
            ) {
                ForEach(symbols, id: \.self) { symbol in
                    Button {
                        selection = symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                selection == symbol
                                    ? Color.white.opacity(0.14)
                                    : Color.white.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(
                                        selection == symbol
                                            ? Color.white.opacity(0.34)
                                            : Color.white.opacity(0.07),
                                        lineWidth: 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help(symbol)
                }
            }
        }
    }
}

struct ListColorPalette: View {
    @Binding var selection: ListColor

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Color")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(ColorFamily.allCases) { family in
                    HStack(spacing: 7) {
                        ForEach(0..<5, id: \.self) { shade in
                            let option = ListColor(family: family, shade: shade)
                            Button {
                                selection = option
                            } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(option.color)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 18)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(
                                                selection == option
                                                    ? Color.white
                                                    : Color.white.opacity(0.10),
                                                lineWidth: selection == option ? 2 : 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                            .help("\(family.rawValue.capitalized), shade \(shade + 1)")
                        }
                    }
                }
            }
        }
    }
}

struct FocusReminderOverlay: View {
    @State private var enteredFullScreen = false

    let title: String
    let notes: String
    let dueDate: Date
    let onComplete: () -> Void
    let onSnooze: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Label("FOCUS REMINDER", systemImage: "bell.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(.orange)
                    Spacer()
                    Text(dueDate, format: .dateTime.hour().minute())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 28, weight: .semibold))
                        .textSelection(.enabled)
                    if !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                }

                HStack(spacing: 8) {
                    Button("Complete", action: onComplete)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button("Snooze 10 min", action: onSnooze)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    Spacer()
                    Button("Dismiss", action: onDismiss)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(30)
            .frame(maxWidth: 620)
            .background(Color.white.opacity(0.055))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(40)
        }
        .onAppear(perform: enterFullScreenIfNeeded)
        .onDisappear(perform: restoreWindowMode)
    }

    private func enterFullScreenIfNeeded() {
        #if os(macOS)
        guard let window = NSApp.keyWindow,
              !window.styleMask.contains(.fullScreen) else { return }
        enteredFullScreen = true
        window.toggleFullScreen(nil)
        #endif
    }

    private func restoreWindowMode() {
        #if os(macOS)
        guard enteredFullScreen,
              let window = NSApp.keyWindow,
              window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
        #endif
    }
}

extension Color {
    static let appBackground = Color(red: 0.055, green: 0.058, blue: 0.065)
    static let sidebarBackground = Color(red: 0.072, green: 0.076, blue: 0.085)
    static let editorBackground = Color(red: 0.085, green: 0.089, blue: 0.10)
}

#Preview {
    ContentView()
        .frame(width: 900, height: 600)
}

import SwiftUI

#if os(macOS)
import AppKit
import ServiceManagement
#endif

enum DeletionKind {
    case task
    case list
    case divider
}

struct PendingDeletion: Identifiable {
    let id = UUID()
    let kind: DeletionKind
    let targetIDs: [UUID]
    let title: String
    let name: String
    let detail: String
}

struct ContentView: View {
    let appState: AppNavigationState

    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = false
    @State private var store = TodoStore()
    @State private var editingItem: TodoItem?
    @State private var isAddingList = false
    @State private var isEditingList = false
    @State private var isSidebarCompact = false
    @State private var pendingDeletion: PendingDeletion?

    var body: some View {
        ZStack {
            TodoWorkspace(
                store: store,
                editingItem: $editingItem,
                isAddingList: $isAddingList,
                isEditingList: $isEditingList,
                isSidebarCompact: $isSidebarCompact,
                onRequestDeletion: requestDeletion
            )

            if appState.isShowingAbout {
                AboutAppView {
                    appState.isShowingAbout = false
                }
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(5)
            }

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

            if let pendingDeletion {
                DeleteConfirmationView(
                    title: pendingDeletion.title,
                    name: pendingDeletion.name,
                    detail: pendingDeletion.detail,
                    onCancel: { self.pendingDeletion = nil },
                    onDelete: { performDeletion(pendingDeletion) }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                .zIndex(20)
            }
        }
        .frame(minWidth: 284, minHeight: 380)
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
        .modifier(ListMenuSyncModifier(appState: appState, store: store))
        .animation(.easeInOut(duration: 0.22), value: store.presentedReminderID)
        .animation(.easeInOut(duration: 0.22), value: appState.isShowingAbout)
        .animation(.easeOut(duration: 0.14), value: pendingDeletion?.id)
    }

    private func requestDeletion(_ deletion: PendingDeletion) {
        if confirmBeforeDeleting {
            pendingDeletion = deletion
        } else {
            performDeletion(deletion)
        }
    }

    private func performDeletion(_ deletion: PendingDeletion) {
        switch deletion.kind {
        case .task:
            deletion.targetIDs.forEach(store.deleteItem)
        case .list:
            if let id = deletion.targetIDs.first {
                store.deleteList(id)
            }
        case .divider:
            if let id = deletion.targetIDs.first {
                store.deleteDivider(id)
            }
        }
        pendingDeletion = nil
    }
}

struct ListMenuSyncModifier: ViewModifier {
    let appState: AppNavigationState
    let store: TodoStore

    func body(content: Content) -> some View {
        content
            .onAppear {
                syncListNames(store.orderedLists)
            }
            .onChange(of: store.lists) {
                syncListNames(store.orderedLists)
            }
            .onChange(of: store.sidebarEntries) {
                syncListNames(store.orderedLists)
            }
            .onChange(of: appState.listSelectionRevision) {
                selectRequestedList()
            }
    }

    private func syncListNames(_ lists: [TodoList]) {
        appState.listNames = lists.map(\.name)
    }

    private func selectRequestedList() {
        let index = appState.requestedListIndex
        let orderedLists = store.orderedLists
        guard orderedLists.indices.contains(index) else {
            return
        }

        store.selectedListID = orderedLists[index].id
        appState.isShowingAbout = false
    }
}

struct TodoWorkspace: View {
    let store: TodoStore
    @Binding var editingItem: TodoItem?
    @Binding var isAddingList: Bool
    @Binding var isEditingList: Bool
    @Binding var isSidebarCompact: Bool
    let onRequestDeletion: (PendingDeletion) -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                store: store,
                isAddingList: $isAddingList,
                isEditingList: $isEditingList,
                isCompact: $isSidebarCompact,
                onRequestDeletion: onRequestDeletion
            )
            .frame(width: isSidebarCompact ? 44 : 160)

            Divider()

            TaskListView(
                store: store,
                editingItem: $editingItem,
                onRequestDeletion: onRequestDeletion
            )
        }
        .background(Color.clear)
        .animation(.easeInOut(duration: 0.30), value: isSidebarCompact)
    }
}

struct SidebarView: View {
    @Bindable var store: TodoStore
    @Binding var isAddingList: Bool
    @Binding var isEditingList: Bool
    @Binding var isCompact: Bool
    let onRequestDeletion: (PendingDeletion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SidebarWindowControls(isCompact: isCompact)

            SidebarHeader(
                isCompact: isCompact,
                onToggleCompact: {
                    withAnimation(.easeInOut(duration: 0.30)) {
                        isCompact.toggle()
                    }
                }
            )

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(store.sidebarEntries) { entry in
                        SidebarEntryRow(
                            entry: entry,
                            store: store,
                            isCompact: isCompact,
                            onRequestDeletion: onRequestDeletion,
                            onEditList: { listID in
                                store.selectedListID = listID
                                isEditingList = true
                            }
                        )
                    }
                    .reorderable()
                }
                .reorderContainer(for: SidebarEntry.self) { difference in
                    withAnimation(.easeInOut(duration: 0.20)) {
                        store.applySidebarReorder(difference)
                    }
                }
                .padding(.horizontal, isCompact ? 5 : 9)
                .padding(.vertical, 8)
            }

            SidebarFooter(
                canDelete: store.lists.count > 1,
                isCompact: isCompact,
                onAddList: { isAddingList = true },
                onAddDivider: store.addDivider,
                onEdit: { isEditingList = true },
                onDelete: requestSelectedListDeletion
            )
        }
        .background(.thinMaterial)
        .animation(.easeInOut(duration: 0.30), value: isCompact)
    }

    private func requestSelectedListDeletion() {
        guard let list = store.selectedList else { return }
        onRequestDeletion(Self.deletion(for: list))
    }

    static func deletion(for list: TodoList) -> PendingDeletion {
        PendingDeletion(
            kind: .list,
            targetIDs: [list.id],
            title: "Delete list",
            name: list.name,
            detail: "Type “delete” below to permanently remove this list and all of its tasks. Press ESC to cancel this process."
        )
    }
}

struct SidebarEntryRow: View {
    let entry: SidebarEntry
    let store: TodoStore
    let isCompact: Bool
    let onRequestDeletion: (PendingDeletion) -> Void
    let onEditList: (UUID) -> Void

    var body: some View {
        switch entry.kind {
        case .list(let listID):
            if let list = store.lists.first(where: { $0.id == listID }) {
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
                        onEditList(list.id)
                    }
                    Button("Delete List", role: .destructive) {
                        onRequestDeletion(SidebarView.deletion(for: list))
                    }
                    .disabled(store.lists.count <= 1)
                }
            }
        case .divider:
            SidebarDividerRow(isCompact: isCompact)
                .contextMenu {
                    Button("Delete Divider", role: .destructive) {
                        onRequestDeletion(
                            PendingDeletion(
                                kind: .divider,
                                targetIDs: [entry.id],
                                title: "Delete divider",
                                name: "List divider",
                                detail: "Type “delete” below to permanently remove this divider. Press ESC to cancel this process."
                            )
                        )
                    }
                }
        }
    }
}

struct SidebarDividerRow: View {
    let isCompact: Bool

    var body: some View {
        HStack(spacing: 5) {
            Rectangle()
                .fill(Color.secondary.opacity(0.34))
                .frame(height: 1)

            if !isCompact {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: 18)
        .contentShape(Rectangle())
        .help("Drag to reorder divider")
    }
}

struct SidebarHeader: View {
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
    @State private var isShowingOptions = false

    let canDelete: Bool
    let isCompact: Bool
    let onAddList: () -> Void
    let onAddDivider: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SidebarFooterLayout(compactProgress: isCompact ? 1 : 0) {
            SidebarAddMenu(
                onAddList: onAddList,
                onAddDivider: onAddDivider
            )
            CompactIconButton(symbol: "pencil", help: "Edit selected list", action: onEdit)
            CompactIconButton(symbol: "trash", help: "Delete selected list", action: onDelete)
                .disabled(!canDelete)
            SidebarOptionsButton(isPresented: $isShowingOptions)
        }
        .padding(.horizontal, isCompact ? 0 : 8)
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 118 : 38)
        .animation(.easeInOut(duration: 0.30), value: isCompact)
        .overlay(alignment: .top) {
            Divider().opacity(0.28)
        }
    }
}

struct SidebarAddMenu: View {
    let onAddList: () -> Void
    let onAddDivider: () -> Void

    var body: some View {
        Menu {
            Button("New List", systemImage: "plus", action: onAddList)
            Button(
                "Add Divider",
                systemImage: "rectangle.split.1x2",
                action: onAddDivider
            )
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Add list or divider")
    }
}

struct SidebarFooterLayout: Layout, Animatable {
    var compactProgress: CGFloat

    var animatableData: CGFloat {
        get { compactProgress }
        set { compactProgress = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let contentWidth = sizes.reduce(0) { $0 + $1.width } + 4
        let contentHeight = sizes.reduce(0) { $0 + $1.height } + 12

        return CGSize(
            width: proposal.width ?? contentWidth,
            height: proposal.height ?? contentHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let verticalSpacing: CGFloat = 4
        let totalVerticalHeight = sizes.reduce(0) { $0 + $1.height }
            + verticalSpacing * CGFloat(max(0, subviews.count - 1))

        var horizontalX = bounds.minX
        var verticalY = bounds.midY - totalVerticalHeight / 2

        for (index, subview) in subviews.enumerated() {
            let size = sizes[index]
            let horizontalPosition = CGPoint(
                x: index == subviews.count - 1 ? bounds.maxX - size.width : horizontalX,
                y: bounds.midY - size.height / 2
            )
            let verticalPosition = CGPoint(
                x: bounds.midX - size.width / 2,
                y: verticalY
            )
            let position = CGPoint(
                x: horizontalPosition.x
                    + (verticalPosition.x - horizontalPosition.x) * compactProgress,
                y: horizontalPosition.y
                    + (verticalPosition.y - horizontalPosition.y) * compactProgress
            )

            subview.place(
                at: position,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            if index < subviews.count - 1 {
                horizontalX += size.width + 2
                verticalY += size.height + verticalSpacing
            }
        }
    }
}

struct SidebarOptionsButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        CompactIconButton(symbol: "gearshape", help: "Options") {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            OptionsPopover()
        }
    }
}

struct OptionsPopover: View {
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = false
    @State private var launchesAtLogin: Bool
    @State private var requiresApproval = false
    @State private var errorMessage: String?

    init() {
        #if os(macOS)
        let status = SMAppService.mainApp.status
        _launchesAtLogin = State(
            initialValue: status == .enabled || status == .requiresApproval
        )
        _requiresApproval = State(initialValue: status == .requiresApproval)
        #else
        _launchesAtLogin = State(initialValue: false)
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Options")
                .font(.system(size: 13, weight: .semibold))

            Toggle("Open at login", isOn: $launchesAtLogin)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: launchesAtLogin) { _, isEnabled in
                    updateLaunchAtLogin(isEnabled)
                }

            Toggle("Confirm before deleting", isOn: $confirmBeforeDeleting)
                .toggleStyle(.switch)
                .controlSize(.small)

            if requiresApproval {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Approval is required in System Settings before the app can open at login.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    Button("Open Login Items Settings") {
                        #if os(macOS)
                        SMAppService.openSystemSettingsLoginItems()
                        #endif
                    }
                    .font(.system(size: 10, weight: .medium))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 280)
        .background(.thinMaterial)
    }

    private func updateLaunchAtLogin(_ isEnabled: Bool) {
        #if os(macOS)
        errorMessage = nil

        do {
            let service = SMAppService.mainApp
            if isEnabled {
                if service.status == .notRegistered || service.status == .notFound {
                    try service.register()
                }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }

            let status = service.status
            requiresApproval = status == .requiresApproval
            launchesAtLogin = status == .enabled || status == .requiresApproval
        } catch {
            let status = SMAppService.mainApp.status
            requiresApproval = status == .requiresApproval
            launchesAtLogin = status == .enabled || status == .requiresApproval
            errorMessage = error.localizedDescription
        }
        #endif
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
    let onRequestDeletion: (PendingDeletion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TaskListHeader(
                title: store.selectedList?.name ?? "Tasks",
                count: store.visibleItems.filter { !$0.isCompleted }.count,
                sortMode: store.selectedTaskSortMode,
                onSortModeChange: store.setTaskSortMode,
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
                                requestDeletion(for: [item])
                            }
                        }
                    }
                    .reorderable()
                    .onDelete { offsets in
                        let items = offsets.compactMap { index in
                            store.visibleItems.indices.contains(index) ? store.visibleItems[index] : nil
                        }
                        requestDeletion(for: items)
                    }
                }
                .reorderContainer(for: TodoItem.self) { difference in
                    withAnimation(.easeInOut(duration: 0.20)) {
                        store.applyItemReorder(difference)
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
                    if let item = store.selectedItem {
                        requestDeletion(for: [item])
                    }
                }
            )
        }
        .background(.ultraThinMaterial)
    }

    private func addItem() {
        editingItem = store.addItem()
    }

    private func requestDeletion(for items: [TodoItem]) {
        guard !items.isEmpty else { return }
        let isMultiple = items.count > 1
        onRequestDeletion(
            PendingDeletion(
                kind: .task,
                targetIDs: items.map(\.id),
                title: isMultiple ? "Delete tasks" : "Delete task",
                name: isMultiple ? "\(items.count) selected tasks" : displayName(for: items[0]),
                detail: isMultiple
                    ? "Type “delete” below to permanently remove these tasks. Press ESC to cancel this process."
                    : "Type “delete” below to permanently remove this task. Press ESC to cancel this process."
            )
        )
    }

    private func displayName(for item: TodoItem) -> String {
        item.title.isEmpty ? "Untitled task" : item.title
    }
}

struct TaskListHeader: View {
    let title: String
    let count: Int
    let sortMode: TaskSortMode
    let onSortModeChange: (TaskSortMode) -> Void
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
            TaskOrganizeMenu(
                selection: sortMode,
                onSelect: onSortModeChange
            )
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

struct TaskOrganizeMenu: View {
    let selection: TaskSortMode
    let onSelect: (TaskSortMode) -> Void

    var body: some View {
        Menu {
            Button {
                onSelect(.custom)
            } label: {
                Label("Custom", systemImage: selection == .custom ? "checkmark" : "hand.draw")
            }

            Divider()

            Menu("Date & Time", systemImage: "calendar") {
                sortButton("Ascending", systemImage: "arrow.up", mode: .dateAscending)
                sortButton("Descending", systemImage: "arrow.down", mode: .dateDescending)
            }

            Menu("ABC", systemImage: "textformat") {
                sortButton("Ascending", systemImage: "arrow.up", mode: .alphabeticalAscending)
                sortButton("Descending", systemImage: "arrow.down", mode: .alphabeticalDescending)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 7, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Organize tasks")
    }

    private func sortButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        mode: TaskSortMode
    ) -> some View {
        Button {
            onSelect(mode)
        } label: {
            Label(title, systemImage: selection == mode ? "checkmark" : systemImage)
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
                let isOverdue = dueDate < Date() && !isCompleted
                let overdueColor = Color(red: 1, green: 0.38, blue: 0.36)

                Text(dueDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(
                        .system(
                            size: 9,
                            weight: isOverdue ? .semibold : .medium,
                            design: .rounded
                        )
                    )
                    .foregroundStyle(isOverdue ? overdueColor : Color.secondary)
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

struct DeleteConfirmationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isTextFieldFocused: Bool
    @State private var confirmationText = ""
    @State private var isBursting = false

    let title: String
    let name: String
    let detail: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    private let requiredText = "delete"

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            confirmationCard
                .scaleEffect(isBursting ? 1.08 : 1)
                .opacity(isBursting ? 0 : 1)
                .blur(radius: isBursting ? 4 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isTextFieldFocused = true
        }
        .onExitCommand(perform: onCancel)
    }

    private var confirmationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(progressColor)
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            Divider()

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("delete", text: $confirmationText)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(fieldBackground, in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(progressColor.opacity(validPrefix ? 0.35 + progress * 0.55 : 0.18))
                }
                .focused($isTextFieldFocused)
                .onSubmit(confirmDeletion)

            HStack(spacing: 6) {
                Text("Press ENTER to confirm. You can’t go back.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .opacity(isComplete ? 1 : 0)

                Spacer()

                HStack(spacing: 3) {
                    ForEach(0..<requiredText.count, id: \.self) { index in
                        Capsule()
                            .fill(
                                validPrefix && index < confirmationText.count
                                    ? Color.red.opacity(0.35 + progress * 0.65)
                                    : Color.secondary.opacity(0.18)
                            )
                            .frame(width: 9, height: 3)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(height: 13)
        }
        .padding(14)
        .frame(width: 336)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(progressColor.opacity(validPrefix ? 0.16 + progress * 0.38 : 0.1))
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .keyframeAnimator(
            initialValue: CGFloat.zero,
            trigger: confirmationText
        ) { content, offset in
            content.offset(x: offset)
        } keyframes: { _ in
            let amount = validPrefix ? 1.5 + progress * 7 : 0
            LinearKeyframe(-amount, duration: 0.035)
            LinearKeyframe(amount, duration: 0.05)
            LinearKeyframe(-amount * 0.7, duration: 0.045)
            LinearKeyframe(amount * 0.45, duration: 0.04)
            LinearKeyframe(0, duration: 0.035)
        }
        .animation(.easeOut(duration: 0.12), value: progress)
        .animation(.easeOut(duration: 0.1), value: isComplete)
    }

    private var validPrefix: Bool {
        !confirmationText.isEmpty && requiredText.hasPrefix(confirmationText)
    }

    private var isComplete: Bool {
        confirmationText == requiredText
    }

    private var progress: Double {
        guard validPrefix else { return 0 }
        return min(1, Double(confirmationText.count) / Double(requiredText.count))
    }

    private var progressColor: Color {
        validPrefix ? .red.opacity(0.35 + progress * 0.65) : .secondary
    }

    private var fieldBackground: Color {
        validPrefix ? .red.opacity(0.04 + progress * 0.14) : .secondary.opacity(0.08)
    }

    private func confirmDeletion() {
        guard isComplete, !isBursting else { return }

        if reduceMotion {
            onDelete()
            return
        }

        withAnimation(.easeOut(duration: 0.05)) {
            isBursting = true
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(35))
            onDelete()
        }
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
            ListEditorFields(
                name: $name,
                symbol: $symbol,
                color: $color
            )
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
        .frame(width: 430)
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

struct ListEditorFields: View {
    @Binding var name: String
    @Binding var symbol: String
    @Binding var color: ListColor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            ListIconPicker(selection: $symbol)
            ListColorPalette(selection: $color)
        }
        .padding(16)
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

    private let paletteFamilies: [ColorFamily] = [
        .orange, .green, .blue, .pink, .gray
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Color")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ForEach(paletteFamilies) { family in
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
                            .help("\(family.displayName), shade \(shade + 1)")
                        }
                    }
                }
            }
        }
    }
}

struct AboutAppView: View {
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                Text("to-do")
                    .font(.system(size: 68, weight: .semibold, design: .serif))
                    .italic()
                    .tracking(-1.4)
                    .accessibilityAddTraits(.isHeader)

                Text("Version \(appVersion)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Button("Source code", action: openSourceCode)
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Spacer()

                Button("Developed by Sebastian", action: openDeveloperProfile)
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .underline(true, color: Color.secondary.opacity(0.35))
                    .help("Open github.com/mxphwd")
                    .padding(.bottom, 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(14)
            .help("Close About")
            .keyboardShortcut(.cancelAction)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private func openSourceCode() {
        #if os(macOS)
        guard let url = URL(string: "https://github.com/mxphwd/better-todo-list") else {
            return
        }
        NSWorkspace.shared.open(url)
        #endif
    }

    private func openDeveloperProfile() {
        #if os(macOS)
        guard let url = URL(string: "https://github.com/mxphwd") else {
            return
        }
        NSWorkspace.shared.open(url)
        #endif
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
    ContentView(appState: AppNavigationState())
        .frame(width: 900, height: 600)
}

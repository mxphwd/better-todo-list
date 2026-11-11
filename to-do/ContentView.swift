import SwiftUI

#if os(macOS)
import AppKit
import ServiceManagement
#endif

extension Animation {
    static var sidebarTransition: Animation {
        .timingCurve(0.42, 0, 0.58, 1, duration: 0.34)
    }
}

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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let appState: AppNavigationState

    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = false
    @AppStorage("appearanceMode") private var appearanceMode = "dark"
    @AppStorage("desktopMode") private var desktopMode = false
    @AppStorage("fixDesktopLocation") private var fixDesktopLocation = false
    @AppStorage("glassOpacity") private var glassOpacity = 0.82
    @State private var store = TodoStore()
    @State private var editingItem: TodoItem?
    @State private var isAddingList = false
    @State private var newListKind: TodoListKind = .standard
    @State private var isEditingList = false
    @State private var isSidebarCompact = false
    @State private var pendingDeletion: PendingDeletion?
    @State private var isShowingResetConfirmation = false

    var body: some View {
        ZStack {
            TodoWorkspace(
                store: store,
                editingItem: $editingItem,
                isAddingList: $isAddingList,
                newListKind: $newListKind,
                isEditingList: $isEditingList,
                isSidebarCompact: $isSidebarCompact,
                onRequestDeletion: requestDeletion,
                onResetAllData: { isShowingResetConfirmation = true }
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
                TripleDeleteConfirmationView(
                    title: pendingDeletion.title,
                    name: pendingDeletion.name,
                    detail: pendingDeletion.detail,
                    onCancel: { self.pendingDeletion = nil },
                    onDelete: { performDeletion(pendingDeletion) }
                )
                .transition(deletePromptTransition)
                .zIndex(20)
            }

            if isShowingResetConfirmation {
                DeleteConfirmationView(
                    title: "Reset all lists",
                    name: "This wipes the app clean",
                    detail: "Type “delete” below to remove every custom list and item. Nothing can be recovered, and the app will restart completely empty.",
                    onCancel: { isShowingResetConfirmation = false },
                    onDelete: {
                        store.resetAllData()
                        isShowingResetConfirmation = false
                    }
                )
                .transition(deletePromptTransition)
                .zIndex(30)
            }
        }
        .frame(minWidth: 284, minHeight: 380)
        .ignoresSafeArea(.container, edges: .top)
        #if os(macOS)
        .background(
            WindowChromeConfigurator(
                isCompact: isSidebarCompact,
                isDesktopMode: desktopMode,
                isLocationFixed: desktopMode && fixDesktopLocation,
                glassOpacity: glassOpacity
            )
        )
        #endif
        .preferredColorScheme(selectedColorScheme)
        .sheet(item: $editingItem) { item in
            TaskEditor(item: item, lists: store.lists.filter { $0.listKind.usesStandardTasks }) { updated in
                store.updateItem(updated)
            }
        }
        .sheet(isPresented: $isAddingList) {
            ListEditor(mode: .add, kind: newListKind) { name, symbol, color in
                store.addList(name: name, symbol: symbol, color: color, kind: newListKind)
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
        .animation(deletePromptAnimation, value: pendingDeletion?.id)
        .animation(deletePromptAnimation, value: isShowingResetConfirmation)
    }

    private var selectedColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light":
            .light
        case "dark":
            .dark
        default:
            nil
        }
    }

    private var deletePromptTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }

        return .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.99))
                .combined(with: .offset(y: 5)),
            removal: .opacity
                .combined(with: .scale(scale: 0.995))
                .combined(with: .offset(y: 2))
        )
    }

    private var deletePromptAnimation: Animation {
        reduceMotion
            ? .linear(duration: 0.1)
            : .easeOut(duration: 0.16)
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
    @AppStorage("desktopMode") private var desktopMode = false
    @AppStorage("desktopCalendarMode") private var desktopCalendarMode = false
    let store: TodoStore
    @Binding var editingItem: TodoItem?
    @Binding var isAddingList: Bool
    @Binding var newListKind: TodoListKind
    @Binding var isEditingList: Bool
    @Binding var isSidebarCompact: Bool
    let onRequestDeletion: (PendingDeletion) -> Void
    let onResetAllData: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                store: store,
                isAddingList: $isAddingList,
                newListKind: $newListKind,
                isEditingList: $isEditingList,
                isCompact: $isSidebarCompact,
                onRequestDeletion: onRequestDeletion,
                onResetAllData: onResetAllData
            )
            .modifier(
                SidebarAnimatedContainerModifier(compactProgress: isSidebarCompact ? 1 : 0)
            )

            Divider()

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    detailContent
                        .frame(
                            maxWidth: .infinity,
                            minHeight: desktopMode && desktopCalendarMode
                                ? proxy.size.height * 0.56
                                : proxy.size.height,
                            maxHeight: desktopMode && desktopCalendarMode
                                ? proxy.size.height * 0.56
                                : proxy.size.height
                        )

                    if desktopMode && desktopCalendarMode {
                        Divider()

                        DesktopCalendarView(store: store)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .background(Color.clear)
    }

    @ViewBuilder
    private var detailContent: some View {
        if let selectedList = store.selectedList, !selectedList.listKind.usesStandardTasks {
            SpecialListDetailView(store: store, list: selectedList)
        } else {
            TaskListView(
                store: store,
                editingItem: $editingItem,
                onRequestDeletion: onRequestDeletion
            )
        }
    }
}

struct DesktopCalendarView: View {
    @AppStorage("glassOpacity") private var glassOpacity = 0.82
    @State private var displayedMonth = Date()

    let store: TodoStore

    private let calendar = Calendar.autoupdatingCurrent
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        VStack(spacing: 7) {
            calendarHeader
            weekdayHeader

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(monthDates, id: \.self) { date in
                    calendarDay(date)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(glassOpacity)
        }
    }

    private var calendarHeader: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(displayedMonth, format: .dateTime.month(.wide))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(displayedMonth, format: .dateTime.year())
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Today") {
                displayedMonth = Date()
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)

            monthButton(symbol: "chevron.left", offset: -1)
            monthButton(symbol: "chevron.right", offset: 1)
        }
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.quaternary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func calendarDay(_ date: Date) -> some View {
        let colors = taskColors(on: date)
        let isToday = calendar.isDateInToday(date)
        let belongsToMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)

        return VStack(spacing: 2) {
            Text(date, format: .dateTime.day())
                .font(.system(size: 10, weight: isToday ? .bold : .medium, design: .rounded))
                .foregroundStyle(belongsToMonth ? .primary : .quaternary)

            HStack(spacing: 2) {
                ForEach(colors, id: \.self) { listColor in
                    Capsule()
                        .fill(listColor.color)
                        .frame(width: colors.count == 1 ? 12 : 5, height: 2.5)
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, minHeight: 20)
        .background(
            isToday ? Color.primary.opacity(0.09) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isToday ? Color.primary.opacity(0.16) : .clear, lineWidth: 1)
        }
    }

    private func monthButton(symbol: String, offset: Int) -> some View {
        Button {
            if let month = calendar.date(byAdding: .month, value: offset, to: displayedMonth) {
                displayedMonth = month
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 18, height: 18)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    private var monthDates: [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        return (0..<42).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: firstWeek.start)
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let firstIndex = max(0, min(calendar.firstWeekday - 1, symbols.count - 1))
        return Array(symbols[firstIndex...]) + Array(symbols[..<firstIndex])
    }

    private func taskColors(on date: Date) -> [ListColor] {
        let listColors = Dictionary(uniqueKeysWithValues: store.lists.map { ($0.id, $0.color) })
        var seen = Set<ListColor>()

        return store.items.compactMap { item in
            guard item.hasSchedule,
                  !item.isCompleted,
                  calendar.isDate(item.dueDate, inSameDayAs: date),
                  let color = listColors[item.listID],
                  seen.insert(color).inserted else {
                return nil
            }
            return color
        }
        .prefix(3)
        .map { $0 }
    }
}

struct SidebarAnimatedContainerModifier: AnimatableModifier {
    @AppStorage("glassOpacity") private var glassOpacity = 0.82

    var compactProgress: CGFloat

    var animatableData: CGFloat {
        get { compactProgress }
        set { compactProgress = newValue }
    }

    func body(content: Content) -> some View {
        let expandedWidth: CGFloat = 160
        let compactWidth: CGFloat = 44
        let width = expandedWidth + (compactWidth - expandedWidth) * compactProgress

        ZStack(alignment: .leading) {
            Rectangle()
                .fill(.thinMaterial)
                .opacity(glassOpacity)
                .frame(width: expandedWidth)

            content
                .frame(width: width)
        }
        .frame(width: width, alignment: .leading)
        .clipped(antialiased: false)
    }
}

struct SidebarView: View {
    @AppStorage("desktopMode") private var desktopMode = false
    @Bindable var store: TodoStore
    @Binding var isAddingList: Bool
    @Binding var newListKind: TodoListKind
    @Binding var isEditingList: Bool
    @Binding var isCompact: Bool
    let onRequestDeletion: (PendingDeletion) -> Void
    let onResetAllData: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !desktopMode {
                SidebarWindowControls(isCompact: isCompact)
            }

            SidebarHeader(
                isCompact: isCompact,
                onToggleCompact: {
                    withAnimation(.sidebarTransition) {
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
                canDelete: store.selectedList != nil,
                isCompact: isCompact,
                onAddList: { kind in
                    newListKind = kind
                    isAddingList = true
                },
                onAddDivider: store.addDivider,
                onEdit: { isEditingList = true },
                onDelete: requestSelectedListDeletion,
                onResetAllData: onResetAllData
            )
        }
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
            detail: "Click Delete three times to permanently remove this list and all of its items. Press ESC to cancel."
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
                        count: store.itemCount(in: list),
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
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button("Delete", role: .destructive) {
                        onRequestDeletion(SidebarView.deletion(for: list))
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 28)
                        .onEnded { value in
                            guard value.translation.width > 72,
                                  abs(value.translation.width) > abs(value.translation.height) * 1.5 else {
                                return
                            }
                            onRequestDeletion(SidebarView.deletion(for: list))
                        }
                )
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
                                detail: "Click Delete three times to permanently remove this divider. Press ESC to cancel."
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
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.secondary.opacity(0.34))
                .frame(height: 1)
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
        ZStack(alignment: .leading) {
            HStack(spacing: 7) {
                Text("to-do")
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .italic()
                    .tracking(-0.35)
                    .fixedSize()

                Spacer()

                SidebarToggleButton(
                    isCompact: false,
                    action: onToggleCompact
                )
            }
            .frame(width: 134)
            .opacity(isCompact ? 0 : 1)
            .offset(x: 13)
            .allowsHitTesting(!isCompact)

            SidebarToggleButton(
                isCompact: true,
                action: onToggleCompact
            )
            .frame(maxWidth: .infinity, alignment: .center)
            .opacity(isCompact ? 1 : 0)
            .allowsHitTesting(isCompact)
        }
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
            .offset(x: isCompact ? -10 : 0)

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
            isSelected && !isCompact ? Color.primary.opacity(0.075) : Color.clear,
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
    let onAddList: (TodoListKind) -> Void
    let onAddDivider: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onResetAllData: () -> Void

    var body: some View {
        SidebarFooterLayout(compactProgress: isCompact ? 1 : 0) {
            SidebarAddMenu(
                onAddList: onAddList,
                onAddDivider: onAddDivider
            )
            CompactIconButton(symbol: "pencil", help: "Edit selected list", action: onEdit)
            CompactIconButton(symbol: "trash", help: "Delete selected list", action: onDelete)
                .disabled(!canDelete)
            SidebarOptionsButton(
                isPresented: $isShowingOptions,
                onResetAllData: onResetAllData
            )
        }
        .padding(.horizontal, isCompact ? 0 : 8)
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 118 : 38)
        .overlay(alignment: .top) {
            Divider().opacity(0.28)
        }
    }
}

struct SidebarAddMenu: View {
    let onAddList: (TodoListKind) -> Void
    let onAddDivider: () -> Void

    var body: some View {
        Menu {
            Button("New Custom List", systemImage: "list.bullet") {
                onAddList(.standard)
            }
            Menu("Special List", systemImage: "sparkles") {
                Button("Shopping List", systemImage: "cart") {
                    onAddList(.shopping)
                }
                Button("Recurring List", systemImage: "repeat") {
                    onAddList(.recurring)
                }
                Button("Assignment Tracker", systemImage: "graduationcap") {
                    onAddList(.assignments)
                }
                Button("College Admission Tracker", systemImage: "building.columns") {
                    onAddList(.collegeAdmissions)
                }
                Divider()
                Button("Packing List", systemImage: "suitcase") {
                    onAddList(.packing)
                }
                Button("Meal Planner", systemImage: "fork.knife") {
                    onAddList(.mealPlanner)
                }
                Button("Habit List", systemImage: "flame") {
                    onAddList(.habits)
                }
            }
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
    let onResetAllData: () -> Void

    var body: some View {
        CompactIconButton(symbol: "gearshape", help: "Options") {
            isPresented.toggle()
        }
        .popover(isPresented: $isPresented, arrowEdge: .leading) {
            OptionsPopover {
                isPresented = false
                onResetAllData()
            }
        }
    }
}

struct OptionsPopover: View {
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = false
    @AppStorage("glassOpacity") private var glassOpacity = 0.82
    @AppStorage("appearanceMode") private var appearanceMode = "dark"
    @AppStorage("desktopMode") private var desktopMode = false
    @AppStorage("fixDesktopLocation") private var fixDesktopLocation = false
    @AppStorage("desktopCalendarMode") private var desktopCalendarMode = false
    @State private var launchesAtLogin: Bool
    @State private var requiresApproval = false
    @State private var errorMessage: String?
    let onResetAllData: () -> Void

    init(onResetAllData: @escaping () -> Void) {
        self.onResetAllData = onResetAllData
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
        VStack(alignment: .leading, spacing: 14) {
            header

            AppearanceToggle(selection: $appearanceMode)

            VStack(spacing: 0) {
                OptionToggleCard(
                    title: "Open at login",
                    detail: "Start to-do when you sign in.",
                    symbol: "power",
                    isOn: $launchesAtLogin
                )
                .onChange(of: launchesAtLogin) { _, isEnabled in
                    updateLaunchAtLogin(isEnabled)
                }

                Divider()
                    .padding(.leading, 42)
                    .opacity(0.35)

                OptionToggleCard(
                    title: "Desktop mode",
                    detail: "Keep to-do behind your other windows.",
                    symbol: "desktopcomputer",
                    isOn: $desktopMode
                )

                if desktopMode {
                    Divider()
                        .padding(.leading, 42)
                        .opacity(0.35)

                    OptionToggleCard(
                        title: "Fix location",
                        detail: "Prevent the window from being dragged.",
                        symbol: "pin",
                        isOn: $fixDesktopLocation
                    )

                    Divider()
                        .padding(.leading, 42)
                        .opacity(0.35)

                    OptionToggleCard(
                        title: "Calendar mode",
                        detail: "Show scheduled to-dos below your list.",
                        symbol: "calendar",
                        isOn: $desktopCalendarMode
                    )
                }

                Divider()
                    .padding(.leading, 42)
                    .opacity(0.35)

                OptionToggleCard(
                    title: "Confirm deletions",
                    detail: "Ask before removing anything.",
                    symbol: "checkmark.shield",
                    isOn: $confirmBeforeDeleting
                )
            }
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(.primary.opacity(0.065), lineWidth: 1)
            }

            Divider()
                .opacity(0.35)

            glassControl

            if requiresApproval {
                approvalNotice
                    .transition(.opacity)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            Divider()
                .opacity(0.35)

            resetButton
        }
        .padding(16)
        .frame(width: 330)
        .background(.thinMaterial)
        .animation(.easeInOut(duration: 0.2), value: requiresApproval)
        .animation(.easeInOut(duration: 0.2), value: desktopMode)
        .animation(.easeOut(duration: 0.18), value: errorMessage)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Options")
                    .font(.system(size: 14, weight: .semibold))
                Text("to-do preferences")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Image(systemName: "gearshape")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    private var glassControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Glass opacity")
                        .font(.system(size: 13, weight: .medium))
                    Text("Adjust the workspace background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 9) {
                    Text(glassOpacity, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.secondary)

                    Button {
                        withAnimation(.easeOut(duration: 0.16)) {
                            glassOpacity = 0.82
                        }
                    } label: {
                        Label("Default", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .disabled(abs(glassOpacity - 0.82) < 0.005)
                    .opacity(abs(glassOpacity - 0.82) < 0.005 ? 0.35 : 1)
                    .help("Restore default glass opacity")
                }
            }

            GlassOpacitySlider(value: $glassOpacity)

            HStack {
                Text("Clear")
                Spacer()
                Text("Frosted")
            }
            .font(.system(size: 9))
            .foregroundStyle(.quaternary)
            .offset(y: -3)
        }
    }

    private var approvalNotice: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Allow this app in Login Items to finish setup.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Open Login Items Settings") {
                #if os(macOS)
                SMAppService.openSystemSettingsLoginItems()
                #endif
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }

    private var resetButton: some View {
        Button(role: .destructive, action: onResetAllData) {
            HStack {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 22)
                Text("Reset all lists…")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red.opacity(0.85))
        .padding(.horizontal, 2)
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

struct AppearanceToggle: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            appearanceButton(title: "System", symbol: "circle.lefthalf.filled", value: "system")
            appearanceButton(title: "Dark", symbol: "moon.fill", value: "dark")
            appearanceButton(title: "Light", symbol: "sun.max.fill", value: "light")
        }
        .padding(3)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }

    private func appearanceButton(
        title: LocalizedStringKey,
        symbol: String,
        value: String
    ) -> some View {
        let isSelected = selection == value

        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selection = value
            }
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isSelected ? .primary : .tertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    isSelected ? Color.primary.opacity(0.09) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct OptionToggleCard: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isOn ? .primary : .tertiary)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ZStack {
                    Capsule()
                        .fill(isOn ? Color.primary.opacity(0.42) : Color.primary.opacity(0.10))
                        .frame(width: 34, height: 19)

                    Circle()
                        .fill(isOn ? Color.primary : Color.primary.opacity(0.62))
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .frame(width: 15, height: 15)
                        .offset(x: isOn ? 7.5 : -7.5)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietOptionButtonStyle())
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

struct QuietOptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.primary.opacity(0.035) : Color.clear)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct GlassOpacitySlider: View {
    @Binding var value: Double

    private let range = 0.0...1.0
    private let dotCount = 9
    private let knobSize: CGFloat = 24

    var body: some View {
        GeometryReader { proxy in
            let availableWidth = max(proxy.size.width - knobSize, 1)
            let progress = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let knobX = (knobSize / 2) + (availableWidth * progress)

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    ForEach(0..<dotCount, id: \.self) { index in
                        let dotProgress = Double(index) / Double(dotCount - 1)
                        Circle()
                            .fill(Color.primary.opacity(0.12 + (dotProgress * 0.68)))
                            .frame(
                                width: 3 + (dotProgress * 2.5),
                                height: 3 + (dotProgress * 2.5)
                            )
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, knobSize / 2)

                Circle()
                    .fill(.regularMaterial)
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        Circle()
                            .stroke(.primary.opacity(0.42), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                    .overlay {
                        Circle()
                            .fill(.primary.opacity(0.72))
                            .frame(width: 5, height: 5)
                    }
                    .position(x: knobX, y: proxy.size.height / 2)
                    .animation(.easeOut(duration: 0.12), value: value)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let location = min(max(gesture.location.x - knobSize / 2, 0), availableWidth)
                        value = range.lowerBound
                            + (location / availableWidth) * (range.upperBound - range.lowerBound)
                    }
            )
        }
        .frame(height: 36)
        .accessibilityElement()
        .accessibilityLabel("Glass opacity")
        .accessibilityValue(Text(value, format: .percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(value + 0.05, range.upperBound)
            case .decrement:
                value = max(value - 0.05, range.lowerBound)
            @unknown default:
                break
            }
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
            WindowActionButton(
                symbol: "xmark",
                color: Color(red: 0.85, green: 0.55, blue: 0.55),
                help: "Close"
            ) {
                #if os(macOS)
                NSApp.keyWindow?.performClose(nil)
                #endif
            }
            WindowActionButton(
                symbol: "minus",
                color: Color(red: 0.85, green: 0.76, blue: 0.48),
                help: "Minimize"
            ) {
                #if os(macOS)
                NSApp.keyWindow?.performMiniaturize(nil)
                #endif
            }
            WindowActionButton(
                symbol: "plus",
                color: Color(red: 0.53, green: 0.75, blue: 0.57),
                help: "Zoom"
            ) {
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
                            Color.secondary.opacity(isHovered ? 0.8 : 0.55),
                            lineWidth: isHovered ? 1.35 : 1
                        )
                        .shadow(
                            color: isHovered ? Color.secondary.opacity(0.3) : .clear,
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
    @AppStorage("glassOpacity") private var glassOpacity = 0.82
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
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
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
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(glassOpacity)
        }
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
                    ? "Click Delete three times to permanently remove these tasks. Press ESC to cancel."
                    : "Click Delete three times to permanently remove this task. Press ESC to cancel."
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

struct TripleDeleteConfirmationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clickCount = 0
    @State private var isBursting = false

    let title: String
    let name: String
    let detail: String
    let onCancel: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(clickCount == 0 ? Color.secondary : Color.red)
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.headline)
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

                Button(action: registerDeleteClick) {
                    HStack(spacing: 7) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                        Text(deleteButtonTitle)
                            .font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("⇧ click to delete now")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(buttonForeground.opacity(0.68))
                    }
                    .foregroundStyle(buttonForeground)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(buttonBackground, in: RoundedRectangle(cornerRadius: 7))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.red.opacity(0.24 + Double(clickCount) * 0.22))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)

                HStack {
                    Text("Press three times to confirm. ESC cancels.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(width: 336)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.1 + Double(clickCount) * 0.13))
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            .scaleEffect(isBursting ? 1.08 : 1)
            .opacity(isBursting ? 0 : 1)
            .blur(radius: isBursting ? 4 : 0)
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: clickCount) { content, offset in
                content.offset(x: offset)
            } keyframes: { _ in
                let amount = CGFloat(clickCount) * 2.5
                LinearKeyframe(-amount, duration: 0.035)
                LinearKeyframe(amount, duration: 0.05)
                LinearKeyframe(-amount * 0.5, duration: 0.04)
                LinearKeyframe(0, duration: 0.035)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: onCancel)
    }

    private var deleteButtonTitle: String {
        clickCount == 0 ? "Delete · first press" : "Delete · \(clickCount + 1) of 3"
    }

    private var buttonBackground: Color {
        switch clickCount {
        case 0: Color.red.opacity(0.08)
        case 1: Color.red.opacity(0.24)
        default: Color.red.opacity(0.52)
        }
    }

    private var buttonForeground: Color {
        clickCount >= 2 ? .white : .red
    }

    private func registerDeleteClick() {
        guard !isBursting else { return }

        #if os(macOS)
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            onDelete()
            return
        }
        #endif

        withAnimation(.easeOut(duration: 0.13)) {
            clickCount += 1
        }
        guard clickCount >= 3 else { return }
        if reduceMotion {
            onDelete()
            return
        }
        withAnimation(.easeOut(duration: 0.05)) { isBursting = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(35))
            onDelete()
        }
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

    init(
        mode: ListEditorMode,
        kind: TodoListKind = .standard,
        onSave: @escaping (String, String, ListColor) -> Void
    ) {
        self.mode = mode
        self.onSave = onSave
        switch mode {
        case .add:
            let preset = Self.preset(for: kind)
            _name = State(initialValue: preset.name)
            _symbol = State(initialValue: preset.symbol)
            _color = State(initialValue: preset.color)
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

    private static func preset(
        for kind: TodoListKind
    ) -> (name: String, symbol: String, color: ListColor) {
        switch kind {
        case .standard: ("", "list.bullet", .blue)
        case .shopping: ("Shopping", "cart", .orange)
        case .recurring: ("Recurring", "repeat", .mint)
        case .assignments: ("Assignments", "graduationcap", .blue)
        case .collegeAdmissions: ("College Admissions", "building.columns", .pink)
        case .packing: ("Packing", "suitcase", .orange)
        case .mealPlanner: ("Meal Planner", "fork.knife", .mint)
        case .habits: ("Habits", "flame", .pink)
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
                                    ? Color.primary.opacity(0.14)
                                    : Color.primary.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(
                                        selection == symbol
                                            ? Color.primary.opacity(0.34)
                                            : Color.primary.opacity(0.07),
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
                                                    ? Color.primary
                                                    : Color.primary.opacity(0.10),
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

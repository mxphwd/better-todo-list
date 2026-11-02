import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ShoppingItem: Identifiable, Codable, Equatable {
    let id: UUID
    var listID: UUID
    var name: String
    var price: Decimal
    var quantity: Int
    var siteName: String
    var urlString: String
    var notes: String
    var isPurchased: Bool

    init(
        id: UUID = UUID(),
        listID: UUID,
        name: String = "",
        price: Decimal = 0,
        quantity: Int = 1,
        siteName: String = "",
        urlString: String = "",
        notes: String = "",
        isPurchased: Bool = false
    ) {
        self.id = id
        self.listID = listID
        self.name = name
        self.price = price
        self.quantity = quantity
        self.siteName = siteName
        self.urlString = urlString
        self.notes = notes
        self.isPurchased = isPurchased
    }
}

enum RecurrenceFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .daily: "Every day"
        case .weekly: "Every week"
        case .monthly: "Every month"
        case .yearly: "Every year"
        }
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        let component: Calendar.Component
        switch self {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .yearly: component = .year
        }
        return calendar.date(byAdding: component, value: 1, to: date) ?? date
    }
}

struct RecurringItem: Identifiable, Codable, Equatable {
    let id: UUID
    var listID: UUID
    var title: String
    var notes: String
    var frequency: RecurrenceFrequency
    var nextDueDate: Date
    var includesTime: Bool
    var isBill: Bool
    var amount: Decimal

    init(
        id: UUID = UUID(),
        listID: UUID,
        title: String = "",
        notes: String = "",
        frequency: RecurrenceFrequency = .monthly,
        nextDueDate: Date = .now,
        includesTime: Bool = true,
        isBill: Bool = false,
        amount: Decimal = 0
    ) {
        self.id = id
        self.listID = listID
        self.title = title
        self.notes = notes
        self.frequency = frequency
        self.nextDueDate = nextDueDate
        self.includesTime = includesTime
        self.isBill = isBill
        self.amount = amount
    }
}

struct AssignmentItem: Identifiable, Codable, Equatable {
    let id: UUID
    var listID: UUID
    var title: String
    var subject: String
    var teacher: String
    var dueDate: Date
    var notes: String
    var isCompleted: Bool

    init(
        id: UUID = UUID(),
        listID: UUID,
        title: String = "",
        subject: String = "",
        teacher: String = "",
        dueDate: Date = .now,
        notes: String = "",
        isCompleted: Bool = false
    ) {
        self.id = id
        self.listID = listID
        self.title = title
        self.subject = subject
        self.teacher = teacher
        self.dueDate = dueDate
        self.notes = notes
        self.isCompleted = isCompleted
    }
}

enum AdmissionWindowKind: String, Codable, Equatable {
    case regular
    case early
}

struct AdmissionWindow: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: AdmissionWindowKind
    var opens: Date
    var closes: Date
    var results: Date

    init(
        id: UUID = UUID(),
        kind: AdmissionWindowKind = .regular,
        opens: Date,
        closes: Date,
        results: Date
    ) {
        self.id = id
        self.kind = kind
        self.opens = opens
        self.closes = closes
        self.results = results
    }
}

struct CollegeApplication: Identifiable, Codable, Equatable {
    let id: UUID
    var listID: UUID
    var schoolName: String
    var programName: String
    var facultyName: String
    var windows: [AdmissionWindow]
    var isStarred: Bool

    init(
        id: UUID = UUID(),
        listID: UUID,
        schoolName: String = "",
        programName: String = "",
        facultyName: String = "",
        windows: [AdmissionWindow] = [],
        isStarred: Bool = false
    ) {
        self.id = id
        self.listID = listID
        self.schoolName = schoolName
        self.programName = programName
        self.facultyName = facultyName
        self.windows = windows
        self.isStarred = isStarred
    }
}

enum AdmissionStatus {
    case waiting
    case open
    case waitingForResult
    case resultsOut

    var title: LocalizedStringResource {
        switch self {
        case .waiting: "Waiting"
        case .open: "Admissions open"
        case .waitingForResult: "Waiting for result"
        case .resultsOut: "Results out"
        }
    }

    var color: Color {
        switch self {
        case .waiting: .secondary
        case .open: .blue
        case .waitingForResult: .cyan
        case .resultsOut: .green
        }
    }
}

struct AdmissionTimeline {
    let status: AdmissionStatus
    let countdown: String
    let eventName: LocalizedStringResource
    let remainingDays: Int?

    init(window: AdmissionWindow, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let opens = calendar.startOfDay(for: window.opens)
        let closes = calendar.startOfDay(for: window.closes)
        let results = calendar.startOfDay(for: window.results)

        if today < opens {
            status = .waiting
            remainingDays = Self.days(from: today, to: opens, calendar: calendar)
            eventName = "opens"
        } else if today <= closes {
            status = .open
            remainingDays = Self.days(from: today, to: closes, calendar: calendar)
            eventName = "closes"
        } else if today < results {
            status = .waitingForResult
            remainingDays = Self.days(from: today, to: results, calendar: calendar)
            eventName = "results"
        } else {
            status = .resultsOut
            remainingDays = nil
            eventName = ""
        }
        countdown = remainingDays.map { $0 == 0 ? "Today" : "D-\($0)" } ?? "Released"
    }

    var isUrgent: Bool {
        status == .open && (remainingDays ?? .max) <= 7
    }

    private static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }
}

extension TodoStore {
    func itemCount(in list: TodoList) -> Int {
        switch list.listKind {
        case .standard, .packing, .mealPlanner, .habits:
            items.filter { $0.listID == list.id && !$0.isCompleted }.count
        case .shopping:
            shoppingItems.filter { $0.listID == list.id && !$0.isPurchased }.count
        case .recurring:
            recurringItems.filter { $0.listID == list.id }.count
        case .assignments:
            assignments.filter { $0.listID == list.id && !$0.isCompleted }.count
        case .collegeAdmissions:
            collegeApplications.filter { $0.listID == list.id }.count
        }
    }

    func shoppingItems(in listID: UUID) -> [ShoppingItem] {
        shoppingItems.filter { $0.listID == listID }
    }

    func saveShoppingItem(_ item: ShoppingItem) {
        upsert(item, in: &shoppingItems)
        save()
    }

    func deleteShoppingItem(_ id: UUID) {
        shoppingItems.removeAll { $0.id == id }
        save()
    }

    func toggleShoppingItem(_ id: UUID) {
        guard let index = shoppingItems.firstIndex(where: { $0.id == id }) else { return }
        shoppingItems[index].isPurchased.toggle()
        save()
    }

    func recurringItems(in listID: UUID) -> [RecurringItem] {
        recurringItems.filter { $0.listID == listID }.sorted { $0.nextDueDate < $1.nextDueDate }
    }

    func saveRecurringItem(_ item: RecurringItem) {
        upsert(item, in: &recurringItems)
        save()
    }

    func completeRecurringItem(_ id: UUID) {
        guard let index = recurringItems.firstIndex(where: { $0.id == id }) else { return }
        recurringItems[index].nextDueDate = recurringItems[index].frequency.nextDate(
            after: recurringItems[index].nextDueDate
        )
        save()
    }

    func deleteRecurringItem(_ id: UUID) {
        recurringItems.removeAll { $0.id == id }
        save()
    }

    func assignments(in listID: UUID) -> [AssignmentItem] {
        assignments
            .filter { $0.listID == listID }
            .sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                return $0.dueDate < $1.dueDate
            }
    }

    func saveAssignment(_ item: AssignmentItem) {
        upsert(item, in: &assignments)
        save()
    }

    func toggleAssignment(_ id: UUID) {
        guard let index = assignments.firstIndex(where: { $0.id == id }) else { return }
        assignments[index].isCompleted.toggle()
        save()
    }

    func deleteAssignment(_ id: UUID) {
        assignments.removeAll { $0.id == id }
        save()
    }

    func collegeApplications(in listID: UUID) -> [CollegeApplication] {
        collegeApplications
            .filter { $0.listID == listID }
            .sorted {
                if $0.isStarred != $1.isStarred { return $0.isStarred }
                return ($0.windows.map(\.opens).min() ?? .distantFuture)
                    < ($1.windows.map(\.opens).min() ?? .distantFuture)
            }
    }

    func saveCollegeApplication(_ application: CollegeApplication) {
        upsert(application, in: &collegeApplications)
        save()
    }

    func toggleCollegeApplicationStar(_ id: UUID) {
        guard let index = collegeApplications.firstIndex(where: { $0.id == id }) else { return }
        collegeApplications[index].isStarred.toggle()
        save()
    }

    func deleteCollegeApplication(_ id: UUID) {
        collegeApplications.removeAll { $0.id == id }
        save()
    }

    private func upsert<Value: Identifiable & Equatable>(_ value: Value, in values: inout [Value])
    where Value.ID == UUID {
        if let index = values.firstIndex(where: { $0.id == value.id }) {
            values[index] = value
        } else {
            values.append(value)
        }
    }
}

struct SpecialListDetailView: View {
    @Bindable var store: TodoStore
    let list: TodoList

    var body: some View {
        VStack(spacing: 0) {
            switch list.listKind {
            case .shopping:
                ShoppingListView(store: store, list: list)
            case .recurring:
                RecurringListView(store: store, list: list)
            case .assignments:
                AssignmentListView(store: store, list: list)
            case .collegeAdmissions:
                CollegeAdmissionListView(store: store, list: list)
            case .standard, .packing, .mealPlanner, .habits:
                EmptyView()
            }
        }
        .background(.ultraThinMaterial)
    }
}

struct SpecialListHeader: View {
    let title: String
    let subtitle: LocalizedStringResource
    let addHelp: LocalizedStringKey
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
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
            .help(addHelp)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .overlay(alignment: .bottom) { Divider().opacity(0.45) }
    }
}

struct ShoppingListView: View {
    @Bindable var store: TodoStore
    let list: TodoList
    @State private var editingItem: ShoppingItem?

    var body: some View {
        let items = store.shoppingItems(in: list.id)
        VStack(spacing: 0) {
            SpecialListHeader(
                title: list.name,
                subtitle: "Shopping · \(items.count) items",
                addHelp: "Add shopping item",
                onAdd: { editingItem = ShoppingItem(listID: list.id) }
            )

            if items.isEmpty {
                SpecialEmptyView(symbol: "cart", title: "Nothing to buy yet")
            } else {
                List {
                    ForEach(items) { item in
                        ShoppingItemRow(
                            item: item,
                            currencyCode: currencyCode,
                            onToggle: { store.toggleShoppingItem(item.id) },
                            onEdit: { editingItem = item }
                        )
                        .contextMenu {
                            Button("Edit") { editingItem = item }
                            Button("Delete", role: .destructive) {
                                store.deleteShoppingItem(item.id)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                store.deleteShoppingItem(item.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)

                HStack {
                    Text("Estimated total")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(total(for: items), format: .currency(code: currencyCode))
                        .fontWeight(.semibold)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 16)
                .frame(height: 36)
                .overlay(alignment: .top) { Divider().opacity(0.45) }
            }
        }
        .sheet(item: $editingItem) { item in
            ShoppingItemEditor(item: item, currencyCode: currencyCode) {
                store.saveShoppingItem($0)
            }
        }
    }

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private func total(for items: [ShoppingItem]) -> Decimal {
        items.filter { !$0.isPurchased }.reduce(Decimal.zero) {
            $0 + ($1.price * Decimal($1.quantity))
        }
    }
}

struct ShoppingItemRow: View {
    let item: ShoppingItem
    let currencyCode: String
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isPurchased ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? "Untitled item" : item.name)
                    .font(.system(size: 12, weight: .medium))
                    .strikethrough(item.isPurchased)
                if !item.siteName.isEmpty || !item.notes.isEmpty {
                    Text([item.siteName, item.notes].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !item.urlString.isEmpty {
                Button(action: openProductPage) {
                    HStack(spacing: 3) {
                        Text("Buy")
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Color.blue, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Open product page")
            }

            Text(item.price * Decimal(item.quantity), format: .currency(code: currencyCode))
                .font(.system(size: 10, weight: .medium, design: .rounded))
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }

    private func openProductPage() {
        #if os(macOS)
        let trimmed = item.urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: address),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        NSWorkspace.shared.open(url)
        #endif
    }
}

struct ShoppingItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ShoppingItem
    let currencyCode: String
    let onSave: (ShoppingItem) -> Void

    init(item: ShoppingItem, currencyCode: String, onSave: @escaping (ShoppingItem) -> Void) {
        _draft = State(initialValue: item)
        self.currencyCode = currencyCode
        self.onSave = onSave
    }

    var body: some View {
        SpecialEditorContainer(title: draft.name.isEmpty ? "Add shopping item" : "Edit shopping item") {
            Form {
                TextField("Item", text: $draft.name)
                TextField("Price (\(currencyCode))", value: $draft.price, format: .number)
                Stepper("Quantity: \(draft.quantity)", value: $draft.quantity, in: 1...999)
                TextField("Site name", text: $draft.siteName)
                TextField("Product URL", text: $draft.urlString)
                TextField("Notes", text: $draft.notes, axis: .vertical)
            }
            .formStyle(.grouped)
        } onSave: {
            onSave(draft)
            dismiss()
        }
    }
}

struct RecurringListView: View {
    @Bindable var store: TodoStore
    let list: TodoList
    @State private var editingItem: RecurringItem?

    var body: some View {
        let items = store.recurringItems(in: list.id)
        VStack(spacing: 0) {
            SpecialListHeader(
                title: list.name,
                subtitle: "Recurring · \(items.count) routines",
                addHelp: "Add recurring item",
                onAdd: { editingItem = RecurringItem(listID: list.id) }
            )
            if items.isEmpty {
                SpecialEmptyView(symbol: "repeat", title: "No recurring items")
            } else {
                List {
                    ForEach(items) { item in
                        RecurringItemRow(
                            item: item,
                            onComplete: { store.completeRecurringItem(item.id) },
                            onEdit: { editingItem = item }
                        )
                        .contextMenu {
                            Button("Edit") { editingItem = item }
                            Button("Delete", role: .destructive) {
                                store.deleteRecurringItem(item.id)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                store.deleteRecurringItem(item.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(item: $editingItem) { item in
            RecurringItemEditor(item: item) { store.saveRecurringItem($0) }
        }
    }
}

struct RecurringItemRow: View {
    let item: RecurringItem
    let onComplete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onComplete) {
                Image(systemName: "arrow.clockwise.circle")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
            .help("Complete and schedule next occurrence")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled recurring item" : item.title)
                    .font(.system(size: 12, weight: .medium))
                HStack(spacing: 5) {
                    Text(item.frequency.title)
                    if item.isBill {
                        Text("·")
                        Text(item.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            }

            Spacer()
            Text(
                item.nextDueDate,
                format: item.includesTime
                    ? .dateTime.month(.abbreviated).day().hour().minute()
                    : .dateTime.month(.abbreviated).day()
            )
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(item.nextDueDate < .now ? .red : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}

struct RecurringItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: RecurringItem
    let onSave: (RecurringItem) -> Void

    init(item: RecurringItem, onSave: @escaping (RecurringItem) -> Void) {
        _draft = State(initialValue: item)
        self.onSave = onSave
    }

    var body: some View {
        SpecialEditorContainer(title: draft.title.isEmpty ? "Add recurring item" : "Edit recurring item") {
            Form {
                TextField("Title", text: $draft.title)
                TextField("Notes", text: $draft.notes, axis: .vertical)
                Picker("Repeats", selection: $draft.frequency) {
                    ForEach(RecurrenceFrequency.allCases) { frequency in
                        Text(frequency.title).tag(frequency)
                    }
                }
                Toggle("Include time", isOn: $draft.includesTime)
                DatePicker(
                    "Next due",
                    selection: $draft.nextDueDate,
                    displayedComponents: draft.includesTime ? [.date, .hourAndMinute] : [.date]
                )
                Toggle("This is a bill", isOn: $draft.isBill)
                if draft.isBill {
                    TextField("Amount", value: $draft.amount, format: .number)
                }
            }
            .formStyle(.grouped)
        } onSave: {
            onSave(draft)
            dismiss()
        }
    }
}

struct AssignmentListView: View {
    @Bindable var store: TodoStore
    let list: TodoList
    @State private var editingItem: AssignmentItem?

    var body: some View {
        let items = store.assignments(in: list.id)
        VStack(spacing: 0) {
            SpecialListHeader(
                title: list.name,
                subtitle: "Assignments · \(items.filter { !$0.isCompleted }.count) due",
                addHelp: "Add assignment",
                onAdd: { editingItem = AssignmentItem(listID: list.id) }
            )
            if items.isEmpty {
                SpecialEmptyView(symbol: "graduationcap", title: "No assignments")
            } else {
                List {
                    ForEach(items) { item in
                        AssignmentItemRow(
                            item: item,
                            onToggle: { store.toggleAssignment(item.id) },
                            onEdit: { editingItem = item }
                        )
                        .contextMenu {
                            Button("Edit") { editingItem = item }
                            Button("Delete", role: .destructive) {
                                store.deleteAssignment(item.id)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                store.deleteAssignment(item.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(item: $editingItem) { item in
            AssignmentItemEditor(item: item) { store.saveAssignment($0) }
        }
    }
}

struct AssignmentItemRow: View {
    let item: AssignmentItem
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.isEmpty ? "Untitled assignment" : item.title)
                    .font(.system(size: 12, weight: .medium))
                    .strikethrough(item.isCompleted)
                Text([item.subject, item.teacher].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(item.dueDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(item.dueDate < .now && !item.isCompleted ? .red : .secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
    }
}

struct AssignmentItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AssignmentItem
    let onSave: (AssignmentItem) -> Void

    init(item: AssignmentItem, onSave: @escaping (AssignmentItem) -> Void) {
        _draft = State(initialValue: item)
        self.onSave = onSave
    }

    var body: some View {
        SpecialEditorContainer(title: draft.title.isEmpty ? "Add assignment" : "Edit assignment") {
            Form {
                TextField("Assignment", text: $draft.title)
                TextField("Subject", text: $draft.subject)
                TextField("Teacher", text: $draft.teacher)
                DatePicker("Due", selection: $draft.dueDate)
                TextField("Notes", text: $draft.notes, axis: .vertical)
            }
            .formStyle(.grouped)
        } onSave: {
            onSave(draft)
            dismiss()
        }
    }
}

struct CollegeAdmissionListView: View {
    @Bindable var store: TodoStore
    let list: TodoList
    @State private var editingApplication: CollegeApplication?

    var body: some View {
        let applications = store.collegeApplications(in: list.id)
        VStack(spacing: 0) {
            SpecialListHeader(
                title: list.name,
                subtitle: "College admissions timeline",
                addHelp: "Add a school",
                onAdd: { editingApplication = blankApplication }
            )
            if applications.isEmpty {
                SpecialEmptyView(symbol: "building.columns", title: "No applications yet")
            } else {
                List {
                    ForEach(applications) { application in
                        CollegeApplicationRow(
                            application: application,
                            onToggleStar: {
                                store.toggleCollegeApplicationStar(application.id)
                            },
                            onEdit: { editingApplication = application }
                        )
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) {
                                store.deleteCollegeApplication(application.id)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .sheet(item: $editingApplication) { application in
            CollegeApplicationEditor(application: application) {
                store.saveCollegeApplication($0)
            } onDelete: {
                store.deleteCollegeApplication(application.id)
            }
        }
    }

    private var blankApplication: CollegeApplication {
        let opens = Date.now
        let closes = Calendar.current.date(byAdding: .day, value: 14, to: opens) ?? opens
        let results = Calendar.current.date(byAdding: .day, value: 30, to: closes) ?? closes
        return CollegeApplication(
            listID: list.id,
            windows: [AdmissionWindow(opens: opens, closes: closes, results: results)]
        )
    }
}

struct CollegeApplicationRow: View {
    let application: CollegeApplication
    let onToggleStar: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(application.schoolName)
                        .font(.system(size: 12, weight: .medium))
                    Button(action: onToggleStar) {
                        Image(systemName: application.isStarred ? "star.fill" : "star")
                            .foregroundStyle(application.isStarred ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text([application.programName, application.facultyName].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(application.windows.prefix(2)) { window in
                    AdmissionStatusView(window: window)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit", action: onEdit)
        }
    }
}

struct AdmissionStatusView: View {
    let window: AdmissionWindow

    var body: some View {
        let timeline = AdmissionTimeline(window: window)
        HStack(spacing: 5) {
            Circle()
                .fill(timeline.status.color)
                .frame(width: 6, height: 6)
                .shadow(color: timeline.status == .open ? timeline.status.color : .clear, radius: 4)
            Text(timeline.status.title)
                .foregroundStyle(timeline.status.color)
            Text(timeline.countdown)
                .fontWeight(.semibold)
                .foregroundStyle(timeline.isUrgent ? .red : .primary)
                .monospacedDigit()
        }
        .font(.system(size: 9))
    }
}

struct CollegeApplicationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CollegeApplication
    let onSave: (CollegeApplication) -> Void
    let onDelete: () -> Void

    init(
        application: CollegeApplication,
        onSave: @escaping (CollegeApplication) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: application)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(title: draft.schoolName.isEmpty ? "Add school" : "Edit school")
            Form {
                Section("School") {
                    TextField("School name", text: $draft.schoolName)
                    TextField("Program", text: $draft.programName)
                    TextField("Faculty or school", text: $draft.facultyName)
                    Toggle("Star application", isOn: $draft.isStarred)
                }
                Section("Admission periods") {
                    ForEach($draft.windows) { $window in
                        AdmissionWindowEditor(
                            window: $window,
                            canDelete: draft.windows.count > 1,
                            onDelete: { draft.windows.removeAll { $0.id == window.id } }
                        )
                    }
                    HStack {
                        if regularWindowCount < 3 {
                            Button("Add application window", systemImage: "plus") {
                                addWindow(kind: .regular)
                            }
                        }
                        if !hasEarlyWindow {
                            Button("Add early admission", systemImage: "plus") {
                                addWindow(kind: .early)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !draft.schoolName.isEmpty {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") {
                    draft.windows.sort { $0.opens < $1.opens }
                    onSave(draft)
                    dismiss()
                }
                .disabled(!isValid)
            }
            .padding(14)
            .overlay(alignment: .top) { Divider().opacity(0.45) }
        }
        .frame(width: 500, height: 560)
        .background(Color.black.opacity(0.16))
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 9))
    }

    private var regularWindowCount: Int {
        draft.windows.filter { $0.kind == .regular }.count
    }

    private var hasEarlyWindow: Bool {
        draft.windows.contains { $0.kind == .early }
    }

    private var isValid: Bool {
        !draft.schoolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.programName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draft.windows.allSatisfy { $0.opens <= $0.closes && $0.closes <= $0.results }
    }

    private func addWindow(kind: AdmissionWindowKind) {
        let latestDate = draft.windows.map(\.closes).max() ?? .now
        let opens = kind == .early
            ? Calendar.current.date(byAdding: .day, value: -30, to: draft.windows.map(\.opens).min() ?? .now) ?? .now
            : Calendar.current.date(byAdding: .day, value: 30, to: latestDate) ?? latestDate
        let closes = Calendar.current.date(byAdding: .day, value: 14, to: opens) ?? opens
        let results = Calendar.current.date(byAdding: .day, value: 30, to: closes) ?? closes
        draft.windows.append(
            AdmissionWindow(kind: kind, opens: opens, closes: closes, results: results)
        )
    }
}

struct AdmissionWindowEditor: View {
    @Binding var window: AdmissionWindow
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(window.kind == .early ? "Early admission" : "Application window")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
            DatePicker("Applications open", selection: $window.opens, displayedComponents: .date)
            DatePicker("Applications close", selection: $window.closes, displayedComponents: .date)
            DatePicker("Results released", selection: $window.results, displayedComponents: .date)
            if window.opens > window.closes || window.closes > window.results {
                Label("Dates must be in chronological order.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SpecialEditorContainer<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content
    let onSave: () -> Void

    init(
        title: LocalizedStringKey,
        @ViewBuilder content: () -> Content,
        onSave: @escaping () -> Void
    ) {
        self.title = title
        self.content = content()
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorHeader(title: title)
            content
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: onSave)
            }
            .padding(14)
            .overlay(alignment: .top) { Divider().opacity(0.45) }
        }
        .frame(width: 430, height: 430)
        .background(Color.black.opacity(0.16))
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 9))
    }

    @Environment(\.dismiss) private var dismiss
}

struct SpecialEmptyView: View {
    let symbol: String
    let title: LocalizedStringKey

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

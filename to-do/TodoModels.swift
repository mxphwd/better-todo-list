import Foundation
import Observation
import SwiftUI

struct TodoList: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var symbol: String
    var color: ListColor
}

struct TodoItem: Identifiable, Codable, Equatable {
    let id: UUID
    var listID: UUID
    var title: String
    var notes: String
    var isCompleted: Bool
    var hasSchedule: Bool
    var dueDate: Date
    var hasFocusReminder: Bool
    var reminderWasShown: Bool
    var createdAt: Date
}

enum ColorFamily: String, Codable, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case mint
    case blue
    case purple
    case pink
    case gray

    var id: Self { self }

    var displayName: String {
        switch self {
        case .red: "Coral"
        case .orange: "Warm orange"
        case .yellow: "Butter"
        case .green: "Soft green"
        case .mint: "Seafoam"
        case .blue: "Soft blue"
        case .purple: "Lavender"
        case .pink: "Soft pink"
        case .gray: "Grayscale"
        }
    }
}

struct ListColor: Codable, Hashable, Identifiable {
    var family: ColorFamily
    var shade: Int

    var id: String { "\(family.rawValue)-\(shade)" }

    var color: Color {
        let clampedShade = min(max(shade, 0), 4)
        let palette: [Color]

        switch family {
        case .orange:
            palette = [
                Color(red: 0.96, green: 0.76, blue: 0.64),
                Color(red: 0.91, green: 0.64, blue: 0.49),
                Color(red: 0.85, green: 0.49, blue: 0.34),
                Color(red: 0.74, green: 0.37, blue: 0.24),
                Color(red: 0.59, green: 0.27, blue: 0.17)
            ]
        case .green:
            palette = [
                Color(red: 0.76, green: 0.86, blue: 0.73),
                Color(red: 0.63, green: 0.78, blue: 0.61),
                Color(red: 0.49, green: 0.68, blue: 0.48),
                Color(red: 0.36, green: 0.56, blue: 0.37),
                Color(red: 0.25, green: 0.43, blue: 0.28)
            ]
        case .blue:
            palette = [
                Color(red: 0.77, green: 0.86, blue: 0.95),
                Color(red: 0.64, green: 0.78, blue: 0.91),
                Color(red: 0.50, green: 0.69, blue: 0.86),
                Color(red: 0.37, green: 0.57, blue: 0.76),
                Color(red: 0.27, green: 0.44, blue: 0.63)
            ]
        case .pink:
            palette = [
                Color(red: 0.95, green: 0.80, blue: 0.85),
                Color(red: 0.90, green: 0.68, blue: 0.76),
                Color(red: 0.84, green: 0.55, blue: 0.67),
                Color(red: 0.73, green: 0.42, blue: 0.56),
                Color(red: 0.60, green: 0.31, blue: 0.45)
            ]
        case .gray:
            palette = [
                Color(red: 0.88, green: 0.88, blue: 0.86),
                Color(red: 0.68, green: 0.68, blue: 0.66),
                Color(red: 0.47, green: 0.47, blue: 0.45),
                Color(red: 0.27, green: 0.27, blue: 0.26),
                Color(red: 0.06, green: 0.06, blue: 0.055)
            ]
        case .red:
            palette = ListColor.fallbackPalette(hue: 0.01)
        case .yellow:
            palette = ListColor.fallbackPalette(hue: 0.135)
        case .mint:
            palette = ListColor.fallbackPalette(hue: 0.45)
        case .purple:
            palette = ListColor.fallbackPalette(hue: 0.72)
        }

        return palette[clampedShade]
    }

    private static func fallbackPalette(hue: Double) -> [Color] {
        (0..<5).map { shade in
            Color(
                hue: hue,
                saturation: 0.30 + (Double(shade) * 0.06),
                brightness: 0.98 - (Double(shade) * 0.05)
            )
        }
    }

    static let blue = ListColor(family: .blue, shade: 2)
    static let mint = ListColor(family: .mint, shade: 2)
    static let orange = ListColor(family: .orange, shade: 2)
    static let pink = ListColor(family: .pink, shade: 2)
    static let violet = ListColor(family: .purple, shade: 2)
    static let gray = ListColor(family: .gray, shade: 3)

    static let allCases: [ListColor] = ColorFamily.allCases.flatMap { family in
        (0..<5).map { ListColor(family: family, shade: $0) }
    }

    private enum CodingKeys: String, CodingKey {
        case family
        case shade
    }

    init(family: ColorFamily, shade: Int) {
        self.family = family
        self.shade = min(max(shade, 0), 4)
    }

    init(from decoder: Decoder) throws {
        if let legacy = try? decoder.singleValueContainer().decode(String.self) {
            switch legacy {
            case "mint": self = .mint
            case "orange": self = .orange
            case "pink": self = .pink
            case "violet": self = .violet
            case "gray": self = .gray
            default: self = .blue
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        family = try container.decode(ColorFamily.self, forKey: .family)
        shade = min(max(try container.decode(Int.self, forKey: .shade), 0), 4)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(family, forKey: .family)
        try container.encode(shade, forKey: .shade)
    }
}

struct SidebarEntry: Identifiable, Codable, Equatable {
    enum Kind: Codable, Equatable {
        case list(UUID)
        case divider
    }

    let id: UUID
    var kind: Kind
}

struct TodoSnapshot: Codable {
    var lists: [TodoList]
    var items: [TodoItem]
    var sidebarEntries: [SidebarEntry]?
}

@MainActor
@Observable
final class TodoStore {
    var lists: [TodoList] = []
    var items: [TodoItem] = []
    var sidebarEntries: [SidebarEntry] = []
    var selectedListID: UUID?
    var selectedItemID: UUID?
    var presentedReminderID: UUID?

    private let storageKey = "focus.todo.snapshot.v1"

    init() {
        load()
    }

    var selectedList: TodoList? {
        lists.first { $0.id == selectedListID }
    }

    var orderedLists: [TodoList] {
        sidebarEntries.compactMap { entry in
            guard case .list(let listID) = entry.kind else {
                return nil
            }
            return lists.first { $0.id == listID }
        }
    }

    var selectedItem: TodoItem? {
        items.first { $0.id == selectedItemID }
    }

    var visibleItems: [TodoItem] {
        guard let selectedListID else { return [] }
        return items
            .filter { $0.listID == selectedListID }
            .sorted {
                if $0.isCompleted != $1.isCompleted {
                    return !$0.isCompleted
                }
                if $0.hasSchedule != $1.hasSchedule {
                    return $0.hasSchedule
                }
                return $0.hasSchedule ? $0.dueDate < $1.dueDate : $0.createdAt > $1.createdAt
            }
    }

    var activeCount: Int {
        items.filter { !$0.isCompleted }.count
    }

    func addList(name: String, symbol: String, color: ListColor) {
        let list = TodoList(id: UUID(), name: name, symbol: symbol, color: color)
        lists.append(list)
        sidebarEntries.append(
            SidebarEntry(id: UUID(), kind: .list(list.id))
        )
        selectedListID = list.id
        save()
    }

    func updateList(_ list: TodoList) {
        guard let index = lists.firstIndex(where: { $0.id == list.id }) else { return }
        lists[index] = list
        save()
    }

    func deleteSelectedList() {
        guard let selectedListID, lists.count > 1 else { return }
        deleteList(selectedListID)
    }

    func deleteList(_ id: TodoList.ID) {
        guard lists.contains(where: { $0.id == id }), lists.count > 1 else { return }
        items.removeAll { $0.listID == id }
        lists.removeAll { $0.id == id }
        sidebarEntries.removeAll { entry in
            entry.kind == .list(id)
        }
        if selectedListID == id {
            selectedListID = orderedLists.first?.id
        }
        selectedItemID = nil
        save()
    }

    func addDivider() {
        let divider = SidebarEntry(id: UUID(), kind: .divider)

        if let selectedListID,
           let selectedEntryIndex = sidebarEntries.firstIndex(where: {
               $0.kind == .list(selectedListID)
           }) {
            sidebarEntries.insert(divider, at: selectedEntryIndex + 1)
        } else {
            sidebarEntries.append(divider)
        }

        save()
    }

    func deleteDivider(_ id: SidebarEntry.ID) {
        sidebarEntries.removeAll { entry in
            entry.id == id && entry.kind == .divider
        }
        save()
    }

    func applySidebarReorder(
        _ difference: ReorderDifference<
            SidebarEntry.ID,
            ReorderableSingleCollectionIdentifier
        >
    ) {
        var movedEntries: [SidebarEntry] = []

        for id in difference.sources {
            if let entry = sidebarEntries.first(where: { $0.id == id }) {
                movedEntries.append(entry)
            }
        }

        sidebarEntries.removeAll { difference.sources.contains($0.id) }

        switch difference.destination.position {
        case .before(let targetID):
            guard let targetIndex = sidebarEntries.firstIndex(where: {
                $0.id == targetID
            }) else {
                sidebarEntries.append(contentsOf: movedEntries)
                save()
                return
            }
            sidebarEntries.insert(contentsOf: movedEntries, at: targetIndex)
        case .end:
            sidebarEntries.append(contentsOf: movedEntries)
        }

        save()
    }

    func addItem() -> TodoItem? {
        guard let listID = selectedListID else { return nil }
        return TodoItem(
            id: UUID(),
            listID: listID,
            title: "",
            notes: "",
            isCompleted: false,
            hasSchedule: false,
            dueDate: Date().addingTimeInterval(3600),
            hasFocusReminder: false,
            reminderWasShown: false,
            createdAt: Date()
        )
    }

    func updateItem(_ item: TodoItem) {
        var revised = item
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            let old = items[index]
            if revised.dueDate != old.dueDate || revised.hasFocusReminder != old.hasFocusReminder {
                revised.reminderWasShown = false
            }
            items[index] = revised
        } else {
            items.append(revised)
        }
        selectedItemID = revised.id
        save()
    }

    func toggleCompleted(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isCompleted.toggle()
        if items[index].isCompleted {
            items[index].reminderWasShown = true
        }
        save()
    }

    func deleteItem(_ id: UUID) {
        items.removeAll { $0.id == id }
        if selectedItemID == id {
            selectedItemID = nil
        }
        save()
    }

    func checkReminders(at date: Date = Date()) {
        guard presentedReminderID == nil else { return }
        guard let index = items.firstIndex(where: {
            !$0.isCompleted &&
            $0.hasSchedule &&
            $0.hasFocusReminder &&
            !$0.reminderWasShown &&
            $0.dueDate <= date
        }) else { return }

        items[index].reminderWasShown = true
        presentedReminderID = items[index].id
        save()
    }

    func completePresentedReminder() {
        guard let id = presentedReminderID else { return }
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].isCompleted = true
        }
        presentedReminderID = nil
        save()
    }

    func snoozePresentedReminder(minutes: Int = 10) {
        guard let id = presentedReminderID,
              let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].dueDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        items[index].reminderWasShown = false
        presentedReminderID = nil
        save()
    }

    func dismissPresentedReminder() {
        presentedReminderID = nil
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(TodoSnapshot.self, from: data),
           !snapshot.lists.isEmpty {
            lists = snapshot.lists
            items = snapshot.items
            sidebarEntries = sanitizedSidebarEntries(
                snapshot.sidebarEntries,
                lists: lists
            )
            selectedListID = orderedLists.first?.id
            return
        }

        let today = TodoList(id: UUID(), name: "Today", symbol: "sun.max", color: .orange)
        let work = TodoList(id: UUID(), name: "Work", symbol: "briefcase", color: .blue)
        let personal = TodoList(id: UUID(), name: "Personal", symbol: "person", color: .mint)
        lists = [today, work, personal]
        sidebarEntries = lists.map { list in
            SidebarEntry(id: UUID(), kind: .list(list.id))
        }
        selectedListID = today.id
        items = [
            TodoItem(
                id: UUID(),
                listID: today.id,
                title: "Plan the day",
                notes: "Choose the three outcomes that matter most.",
                isCompleted: false,
                hasSchedule: true,
                dueDate: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date(),
                hasFocusReminder: false,
                reminderWasShown: false,
                createdAt: Date()
            ),
            TodoItem(
                id: UUID(),
                listID: work.id,
                title: "Review project notes",
                notes: "",
                isCompleted: false,
                hasSchedule: false,
                dueDate: Date(),
                hasFocusReminder: false,
                reminderWasShown: false,
                createdAt: Date()
            )
        ]
        save()
    }

    private func sanitizedSidebarEntries(
        _ savedEntries: [SidebarEntry]?,
        lists: [TodoList]
    ) -> [SidebarEntry] {
        let validListIDs = Set(lists.map(\.id))
        var entries = (savedEntries ?? []).filter { entry in
            switch entry.kind {
            case .list(let listID):
                validListIDs.contains(listID)
            case .divider:
                true
            }
        }

        let referencedListIDs = Set(entries.compactMap { entry -> UUID? in
            guard case .list(let listID) = entry.kind else {
                return nil
            }
            return listID
        })

        for list in lists where !referencedListIDs.contains(list.id) {
            entries.append(SidebarEntry(id: UUID(), kind: .list(list.id)))
        }

        return entries
    }

    private func save() {
        let snapshot = TodoSnapshot(
            lists: lists,
            items: items,
            sidebarEntries: sidebarEntries
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

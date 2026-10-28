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

    var id: Self { self }

    var hue: Double {
        switch self {
        case .red: 0.00
        case .orange: 0.08
        case .yellow: 0.14
        case .green: 0.34
        case .mint: 0.46
        case .blue: 0.59
        case .purple: 0.75
        case .pink: 0.92
        }
    }
}

struct ListColor: Codable, Hashable, Identifiable {
    var family: ColorFamily
    var shade: Int

    var id: String { "\(family.rawValue)-\(shade)" }

    var color: Color {
        let clampedShade = min(max(shade, 0), 4)
        let saturation = 0.48 + (Double(clampedShade) * 0.09)
        let brightness = 0.98 - (Double(clampedShade) * 0.105)
        return Color(hue: family.hue, saturation: saturation, brightness: brightness)
    }

    static let blue = ListColor(family: .blue, shade: 2)
    static let mint = ListColor(family: .mint, shade: 2)
    static let orange = ListColor(family: .orange, shade: 2)
    static let pink = ListColor(family: .pink, shade: 2)
    static let violet = ListColor(family: .purple, shade: 2)
    static let gray = ListColor(family: .blue, shade: 4)

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

struct TodoSnapshot: Codable {
    var lists: [TodoList]
    var items: [TodoItem]
}

@MainActor
@Observable
final class TodoStore {
    var lists: [TodoList] = []
    var items: [TodoItem] = []
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
        items.removeAll { $0.listID == selectedListID }
        lists.removeAll { $0.id == selectedListID }
        self.selectedListID = lists.first?.id
        selectedItemID = nil
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
            selectedListID = lists.first?.id
            return
        }

        let today = TodoList(id: UUID(), name: "Today", symbol: "sun.max", color: .orange)
        let work = TodoList(id: UUID(), name: "Work", symbol: "briefcase", color: .blue)
        let personal = TodoList(id: UUID(), name: "Personal", symbol: "person", color: .mint)
        lists = [today, work, personal]
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

    private func save() {
        let snapshot = TodoSnapshot(lists: lists, items: items)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

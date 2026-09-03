import WidgetKit
import SwiftUI
import AppIntents

// The app group + deep-link scheme are duplicated as literals here so the widget
// extension stays dependency-free (no KharchaKit import needed for a pure
// open-the-app widget). Keep these in sync with KharchaContainerFactory.appGroupID
// and the CFBundleURLSchemes entry in the app's Info.plist.
private let appGroupID = "group.com.manish.jebkharcha"
private let addExpenseURL = URL(string: "jebkharcha://add")!

// MARK: - Home Screen widget ("＋ Add Expense")

struct QuickAddEntry: TimelineEntry {
    let date: Date
}

struct QuickAddProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickAddEntry { QuickAddEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickAddEntry) -> Void) {
        completion(QuickAddEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickAddEntry>) -> Void) {
        // Static content — no scheduled refresh needed.
        completion(Timeline(entries: [QuickAddEntry(date: .now)], policy: .never))
    }
}

struct QuickAddWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.tint)
            Text("Add Expense")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
        // Whole tile is tappable — opens the app straight to the add form.
        .widgetURL(addExpenseURL)
    }
}

struct QuickAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickAddWidget", provider: QuickAddProvider()) { _ in
            QuickAddWidgetView()
        }
        .configurationDisplayName("Quick Add")
        .description("Add an expense in one tap.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Control Center / Lock Screen control

/// Opens the app and flags an add-expense request in the shared App Group defaults;
/// the app consumes the flag when it becomes active and presents the add form.
struct QuickAddControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static var openAppWhenRun: Bool { true }

    init() {}

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: appGroupID)?.set(true, forKey: "pendingAddExpense")
        return .result()
    }
}

struct QuickAddControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "QuickAddControl") {
            ControlWidgetButton(action: QuickAddControlIntent()) {
                Label("Add Expense", systemImage: "plus.circle.fill")
            }
        }
        .displayName("Add Expense")
        .description("Add an expense in jebkharcha.")
    }
}

// MARK: - Bundle

@main
struct KharchaWidgetBundle: WidgetBundle {
    var body: some Widget {
        QuickAddWidget()
        QuickAddControl()
    }
}

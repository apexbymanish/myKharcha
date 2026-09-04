import Foundation
import KharchaKit

#if DEBUG
/// A month and a half of plausible spending, for App Store screenshots.
///
/// Screenshots are the strongest conversion lever a listing has, and
/// `fastlane/screenshots` was empty — whatever is live was captured by hand at
/// some point and cannot be reproduced. This makes the shots a build product:
/// same data, same figures, every time, in any language the simulator is set
/// to.
///
/// Debug builds only, and only when asked for by launch argument, so it cannot
/// reach a real user or a release binary.
enum DemoData {
    static let launchArgument = "-seedDemo"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// One day's spending. Amounts are Korean won, the currency the screenshots
    /// are shot in.
    private struct Entry {
        let daysAgo: Int
        let category: String
        let amount: Decimal
        let note: String?
    }

    /// Shaped rather than random: a rent day and a payday that dwarf everything
    /// else, a few no-spend days, and ordinary days in between. A chart of
    /// uniform bars would flatter the app and show none of what it does — the
    /// category stacking, the outlier handling, the empty-day stubs.
    private static let expenses: [Entry] = [
        .init(daysAgo: 0,  category: "Food",          amount: 12_400,  note: "Lunch"),
        .init(daysAgo: 0,  category: "Transport",     amount: 2_800,   note: nil),
        .init(daysAgo: 1,  category: "Food",          amount: 31_600,  note: "Groceries"),
        .init(daysAgo: 1,  category: "Entertainment", amount: 18_000,  note: "Cinema"),
        .init(daysAgo: 2,  category: "Food",          amount: 8_900,   note: "Coffee"),
        .init(daysAgo: 3,  category: "Health",        amount: 85_555,  note: "Dentist"),
        .init(daysAgo: 3,  category: "Transport",     amount: 1_400,   note: nil),
        .init(daysAgo: 5,  category: "Shopping",      amount: 47_400,  note: "Winter coat"),
        .init(daysAgo: 6,  category: "Food",          amount: 21_500,  note: "Dinner with Sana"),
        .init(daysAgo: 8,  category: "Subscriptions", amount: 17_000,  note: "Streaming"),
        .init(daysAgo: 8,  category: "Food",          amount: 9_200,   note: nil),
        .init(daysAgo: 9,  category: "Transport",     amount: 28_500,  note: "Train home"),
        .init(daysAgo: 11, category: "Food",          amount: 14_800,  note: nil),
        .init(daysAgo: 12, category: "Rent",          amount: 681_020, note: "Monthly rent"),
        .init(daysAgo: 12, category: "Food",          amount: 6_300,   note: nil),
        .init(daysAgo: 14, category: "Shopping",      amount: 31_630,  note: "Shoes"),
        .init(daysAgo: 15, category: "Food",          amount: 11_900,  note: "Lunch"),
        .init(daysAgo: 17, category: "Health",        amount: 24_000,  note: "Pharmacy"),
        .init(daysAgo: 18, category: "Food",          amount: 16_700,  note: nil),
        .init(daysAgo: 18, category: "Entertainment", amount: 12_000,  note: nil),
        .init(daysAgo: 20, category: "Transport",     amount: 3_200,   note: nil),
        .init(daysAgo: 22, category: "Food",          amount: 27_400,  note: "Groceries"),
        .init(daysAgo: 23, category: "Subscriptions", amount: 9_900,   note: "Music"),
        .init(daysAgo: 25, category: "Food",          amount: 13_100,  note: nil),
        .init(daysAgo: 26, category: "Shopping",      amount: 129_900, note: "Headphones"),
        .init(daysAgo: 28, category: "Food",          amount: 19_600,  note: "Dinner"),
        .init(daysAgo: 30, category: "Transport",     amount: 2_800,   note: nil),
        .init(daysAgo: 33, category: "Food",          amount: 22_300,  note: nil),
        .init(daysAgo: 36, category: "Health",        amount: 40_000,  note: "Check-up"),
        .init(daysAgo: 39, category: "Food",          amount: 15_400,  note: nil),
    ]

    private static let income: [Entry] = [
        .init(daysAgo: 12, category: "Salary", amount: 3_000_000, note: "September salary"),
        .init(daysAgo: 42, category: "Salary", amount: 3_000_000, note: "August salary"),
        .init(daysAgo: 4,  category: "Gift",   amount: 50_000,    note: "Birthday"),
    ]

    /// Seeds only into an empty ledger. Running the screenshot pass twice must
    /// not double every figure.
    static func seedIfRequested(store: ExpenseStore) async {
        guard isRequested else { return }
        do {
            guard try await store.txnRows().isEmpty else { return }
            try await store.seedDefaultCategoriesIfNeeded()
            let categories = try await store.categories()
            func id(_ name: String) -> UUID? { categories.first { $0.name == name }?.id }

            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())

            for entry in expenses {
                guard let date = calendar.date(byAdding: .day, value: -entry.daysAgo, to: today) else { continue }
                try await store.addTxn(amount: entry.amount, kind: .expense,
                                       categoryID: id(entry.category), note: entry.note,
                                       date: date, source: .manual)
            }
            for entry in income {
                guard let date = calendar.date(byAdding: .day, value: -entry.daysAgo, to: today) else { continue }
                try await store.addTxn(amount: entry.amount, kind: .income,
                                       categoryID: id(entry.category), note: entry.note,
                                       date: date, source: .manual)
            }

            // Past onboarding, with a pay cycle set, so Home has its plan card
            // rather than its empty nudge.
            UserDefaults.standard.set(true, forKey: "onboardingDone")
            // Won, to match the amounts above. Left to the device locale the
            // screenshots came out as "NPR 255,755.00" — a currency the figures
            // were not written for, and two decimal places that make every label
            // wider than its bar.
            UserDefaults.standard.set("KRW", forKey: CurrencyPreference.defaultsKey)
            AmountFormatter.currencyCode = "KRW"
            PayPreference.defaults.set(3_000_000.0, forKey: PayPreference.salaryKey)
            PayPreference.defaults.set(25, forKey: PayPreference.dayKey)
        } catch {
            print("[demo] seeding failed: \(error)")
        }
    }
}
#endif

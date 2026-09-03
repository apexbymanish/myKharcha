import Testing
import Foundation
@testable import KharchaKit

@Suite
struct HistoryViewModelTests {
    @Test
    @MainActor
    func groupsTransactionsByMonthNewestFirst() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)

        // Add transactions in July and August
        _ = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 7, 15), source: .manual)
        _ = try await store.addTxn(amount: 3_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 7, 10), source: .manual)
        _ = try await store.addTxn(amount: 12_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 20), source: .manual)
        _ = try await store.addTxn(amount: 8_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 5), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)

        #expect(vm.state.sections.count == 2)
        #expect(vm.state.sections[0].title == "August 2026")
        #expect(vm.state.sections[0].rows.count == 2)
        #expect(vm.state.sections[0].rows.first?.amount == 12_000)  // August newest first
        #expect(vm.state.sections[1].title == "July 2026")
        #expect(vm.state.sections[1].rows.first?.amount == 5_000)   // July newest first
    }

    @Test
    @MainActor
    func kindFilterHidesIncome() async throws {
        let store = try makeStore()
        _ = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 10), source: .manual)
        _ = try await store.addTxn(amount: 3_000_000, kind: .income, categoryID: nil, note: nil, date: d(2026, 8, 5), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        #expect(vm.state.sections[0].rows.count == 2)

        await vm.setKindFilter(.expense, calendar: testCal)
        #expect(vm.state.filterKind == .expense)
        #expect(vm.state.sections[0].rows.count == 1)
        #expect(vm.state.sections[0].rows.first?.amount == 5_000)
    }

    @Test
    @MainActor
    func categoryFilterByName() async throws {
        let store = try makeStore()
        let food = try await store.addCategory(name: "Food", symbol: "fork.knife", colorHex: "#E07A5F", monthlyBudget: nil)
        let transport = try await store.addCategory(name: "Transport", symbol: "bus", colorHex: "#3D405B", monthlyBudget: nil)

        _ = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: food.id, note: nil, date: d(2026, 8, 10), source: .manual)
        _ = try await store.addTxn(amount: 3_000, kind: .expense, categoryID: transport.id, note: nil, date: d(2026, 8, 5), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        #expect(vm.state.sections[0].rows.count == 2)

        await vm.setCategoryFilter("Food", calendar: testCal)
        #expect(vm.state.filterCategoryName == "Food")
        #expect(vm.state.sections[0].rows.count == 1)
        #expect(vm.state.sections[0].rows.first?.categoryName == "Food")
    }

    @Test
    @MainActor
    func deleteRemovesRow() async throws {
        let store = try makeStore()
        let id = try await store.addTxn(amount: 5_000, kind: .expense, categoryID: nil, note: nil, date: d(2026, 8, 10), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        #expect(vm.state.sections[0].rows.count == 1)

        await vm.delete(id, calendar: testCal)
        #expect(vm.state.sections.isEmpty)
    }

    @Test
    @MainActor
    func chartSummaryDescribesTheScrolledToPeriodNotToday() async throws {
        // The original defect: the chart reported the current real-world period no
        // matter which month the user was looking at. Scrolling the chart to July
        // must make the header describe July.
        let store = try makeStore()
        _ = try await store.addTxn(amount: 9_200, kind: .expense, categoryID: nil,
                                   note: nil, date: d(2026, 8, 10), source: .manual)
        _ = try await store.addTxn(amount: 10_000, kind: .expense, categoryID: nil,
                                   note: nil, date: d(2026, 7, 10), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        await vm.setChartAnchor(d(2026, 8, 15), calendar: testCal)
        #expect(vm.state.chartSummary?.expense == 9_200)

        await vm.setChartAnchor(d(2026, 7, 15), calendar: testCal)
        #expect(vm.state.chartSummary?.expense == 10_000)
        #expect(vm.state.chartSummary?.barCount == 31)   // July has 31 days
    }

    @Test
    @MainActor
    func chartAllowanceSpreadsCategoryBudgetsAcrossTheAnchoredMonth() async throws {
        // Bar colours need a per-day allowance, derived from the category budgets
        // divided by the length of the month the chart is anchored to.
        let store = try makeStore()
        _ = try await store.addCategory(name: "Food", symbol: "fork.knife",
                                        colorHex: "#E07A5F", monthlyBudget: 1_240_000)
        _ = try await store.addCategory(name: "Travel", symbol: "car",
                                        colorHex: "#3D405B", monthlyBudget: 620_000)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        await vm.setChartAnchor(d(2026, 8, 15), calendar: testCal)   // August has 31 days

        #expect(vm.state.chartAllowance == 60_000)   // 1,860,000 / 31
    }

    @Test
    @MainActor
    func scrollingUpdatesTheHeadlineImmediatelyButNotTheSettledPeriod() async throws {
        // While a fling is in flight the sentence above the chart should track the
        // bars under the finger, but the list must not thrash through a month per
        // frame. `settledAnchor` only moves once scrolling stops.
        let store = try makeStore()
        _ = try await store.addTxn(amount: 10_000, kind: .expense, categoryID: nil,
                                   note: nil, date: d(2026, 7, 10), source: .manual)
        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        await vm.setChartAnchor(d(2026, 8, 15), calendar: testCal)
        await vm.settleChartAnchor(calendar: testCal)

        // Mid-fling: anchor and headline move, settled period stays put.
        await vm.setChartAnchor(d(2026, 5, 15), calendar: testCal)
        #expect(testCal.component(.month, from: vm.state.chartAnchor) == 5)
        #expect(vm.state.chartSummary?.expense == 0)              // May has nothing
        #expect(testCal.component(.month, from: vm.state.settledAnchor) == 8)

        // Scrolling stops — the list's period catches up.
        await vm.settleChartAnchor(calendar: testCal)
        #expect(testCal.component(.month, from: vm.state.settledAnchor) == 5)
    }

    @Test
    @MainActor
    func scrollingTheChartDoesNotGrowItsScrollableDomain() async throws {
        // The domain is fixed by the data (plus today). If the anchor fed back into
        // it, every scroll would extend the timeline and the chart could be dragged
        // backwards forever.
        let store = try makeStore()
        _ = try await store.addTxn(amount: 10_000, kind: .expense, categoryID: nil,
                                   note: nil, date: d(2026, 7, 10), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        await vm.setChartAnchor(d(2026, 7, 15), calendar: testCal)
        let barsBefore = vm.state.chartBars.count

        await vm.setChartAnchor(d(2020, 1, 15), calendar: testCal)

        #expect(vm.state.chartBars.count == barsBefore)
    }

    @Test
    @MainActor
    func switchingScopeKeepsTheAnchorRatherThanJumpingToToday() async throws {
        // Viewing July and tapping "W" must land in a week *of July*. Resetting to
        // the current week would throw away where the user had navigated to.
        let store = try makeStore()
        _ = try await store.addTxn(amount: 10_000, kind: .expense, categoryID: nil,
                                   note: nil, date: d(2026, 7, 10), source: .manual)

        let vm = HistoryViewModel(store: store)
        await vm.load(calendar: testCal)
        await vm.setChartAnchor(d(2026, 7, 15), calendar: testCal)

        await vm.setChartPeriod(.week, calendar: testCal)

        let start = try #require(vm.state.chartSummary?.start)
        #expect(vm.state.chartPeriod == .week)
        #expect(vm.state.chartSummary?.barCount == 7)
        #expect(testCal.component(.month, from: start) == 7)   // still July
        #expect(testCal.component(.weekday, from: start) == 1) // Sunday-aligned
    }

}

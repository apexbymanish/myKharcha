import Testing
import Foundation
@testable import KharchaKit

@Test func categoryResolverReturnsAllAndByID() async throws {
    let store = try makeStore()
    try await store.seedDefaultCategoriesIfNeeded()
    let all = try await CategoryEntityResolver.all(store: store)
    #expect(all.count == 8)
    let food = all.first { $0.name == "Food" }!
    let byID = try await CategoryEntityResolver.matching(ids: [food.id, UUID()], store: store)
    #expect(byID.map(\.name) == ["Food"])
}

@Test func friendResolverUsesFuzzyRanking() async throws {
    let store = try makeStore()
    _ = try await store.addFriend(name: "Ramesh", phone: nil)
    let ram = try await store.addFriend(name: "Ram", phone: nil)
    _ = try await store.addFriend(name: "Sita", phone: nil)

    let matches = try await FriendEntityResolver.matching("ram", store: store)
    #expect(matches.map(\.name) == ["Ram", "Ramesh"])
    let byID = try await FriendEntityResolver.matching(ids: [ram.id], store: store)
    #expect(byID.map(\.name) == ["Ram"])
    #expect(try await FriendEntityResolver.matching("xyz", store: store).isEmpty)
}

@Test func periodAppEnumMapsToPeriod() {
    #expect(PeriodAppEnum.today.period == .today)
    #expect(PeriodAppEnum.week.period == .week)
    #expect(PeriodAppEnum.month.period == .month)
}

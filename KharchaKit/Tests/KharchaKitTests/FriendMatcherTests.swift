import Testing
import Foundation
@testable import KharchaKit

private func f(_ name: String) -> FriendSnapshot { FriendSnapshot(id: UUID(), name: name) }

@Test func normalizeFoldsCaseDiacriticsAndSpaces() {
    #expect(FriendMatcher.normalize("  Rám Pŕasad ") == "ramprasad")
}

@Test func exactBeatsPrefixBeatsContains() {
    let ram = f("Ram")
    let ramesh = f("Ramesh")
    let biram = f("Biram")
    let ranked = FriendMatcher.rank(query: "ram", candidates: [biram, ramesh, ram])
    #expect(ranked.map(\.name) == ["Ram", "Ramesh", "Biram"])
}

@Test func noMatchReturnsEmpty() {
    #expect(FriendMatcher.rank(query: "xyz", candidates: [f("Ram")]).isEmpty)
    #expect(FriendMatcher.rank(query: "", candidates: [f("Ram")]).isEmpty)
}

@Test func koreanNamesMatchByPrefix() {
    let ranked = FriendMatcher.rank(query: "김", candidates: [f("이수민"), f("김민수")])
    #expect(ranked.map(\.name) == ["김민수"])
}

@Test func sameTierMatchesAreOrderedDeterministically() {
    // "Ravi" and "Rakesh" are both prefix matches for "ra" (tier 1) — the
    // tie must break on normalized name, not input/insertion order.
    let ravi = f("Ravi")
    let rakesh = f("Rakesh")
    let ranked1 = FriendMatcher.rank(query: "ra", candidates: [ravi, rakesh])
    let ranked2 = FriendMatcher.rank(query: "ra", candidates: [rakesh, ravi])
    #expect(ranked1.map(\.name) == ["Rakesh", "Ravi"])
    #expect(ranked2.map(\.name) == ["Rakesh", "Ravi"])
}

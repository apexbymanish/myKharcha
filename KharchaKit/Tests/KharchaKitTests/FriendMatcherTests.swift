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

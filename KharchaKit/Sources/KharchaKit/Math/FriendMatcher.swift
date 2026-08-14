import Foundation

public enum FriendMatcher {

    public static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { !$0.isWhitespace }
    }

    /// Exact-normalized match first, then prefix, then contains.
    public static func rank(query: String, candidates: [FriendSnapshot]) -> [FriendSnapshot] {
        let q = normalize(query)
        guard !q.isEmpty else { return [] }

        func score(_ name: String) -> Int? {
            let n = normalize(name)
            if n == q { return 0 }
            if n.hasPrefix(q) { return 1 }
            if n.contains(q) { return 2 }
            return nil
        }

        return candidates
            .compactMap { c in score(c.name).map { (c, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }
}

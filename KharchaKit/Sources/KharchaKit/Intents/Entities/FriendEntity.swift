import Foundation

public enum FriendEntityResolver {
    public static func all(store: ExpenseStore) async throws -> [FriendSnapshot] {
        try await store.friends()
    }
    public static func matching(_ query: String, store: ExpenseStore) async throws -> [FriendSnapshot] {
        FriendMatcher.rank(query: query, candidates: try await store.friends())
    }
    public static func matching(ids: [UUID], store: ExpenseStore) async throws -> [FriendSnapshot] {
        let wanted = Set(ids)
        return try await store.friends().filter { wanted.contains($0.id) }
    }
}

import AppIntents

public struct FriendEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Friend"
    public static let defaultQuery = FriendEntityQuery()
    public var id: UUID
    public var name: String
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    public init(snapshot: FriendSnapshot) {
        self.id = snapshot.id
        self.name = snapshot.name
    }
}

public struct FriendEntityQuery: EntityStringQuery {
    public init() {}
    public func entities(matching string: String) async throws -> [FriendEntity] {
        try await FriendEntityResolver.matching(string, store: IntentStoreProvider.store()).map(FriendEntity.init)
    }
    public func entities(for identifiers: [UUID]) async throws -> [FriendEntity] {
        try await FriendEntityResolver.matching(ids: identifiers, store: IntentStoreProvider.store()).map(FriendEntity.init)
    }
    public func suggestedEntities() async throws -> [FriendEntity] {
        try await FriendEntityResolver.all(store: IntentStoreProvider.store()).map(FriendEntity.init)
    }
}

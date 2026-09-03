import Foundation

public enum CategoryEntityResolver {
    public static func all(store: ExpenseStore) async throws -> [CategorySnapshot] {
        try await store.categories()
    }
    public static func matching(ids: [UUID], store: ExpenseStore) async throws -> [CategorySnapshot] {
        let wanted = Set(ids)
        return try await store.categories().filter { wanted.contains($0.id) }
    }
}

import AppIntents

public struct CategoryEntity: AppEntity {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    public static let defaultQuery = CategoryEntityQuery()
    public var id: UUID
    public var name: String
    public var isFallback: Bool
    public var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    public init(snapshot: CategorySnapshot) {
        self.id = snapshot.id
        self.name = snapshot.name
        self.isFallback = snapshot.isFallback
    }
}

public struct CategoryEntityQuery: EntityQuery {
    public init() {}
    public func entities(for identifiers: [UUID]) async throws -> [CategoryEntity] {
        try await CategoryEntityResolver.matching(ids: identifiers, store: IntentStoreProvider.store()).map(CategoryEntity.init)
    }
    public func suggestedEntities() async throws -> [CategoryEntity] {
        try await CategoryEntityResolver.all(store: IntentStoreProvider.store()).map(CategoryEntity.init)
    }
}

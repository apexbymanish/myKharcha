import Foundation
import SwiftData

/// Records that a record (identified by its original id) was deleted, so the
/// deletion can propagate to other devices through sync instead of the record
/// being resurrected on the next pull. `collection` matches the Firestore
/// collection name ("txns", "friends", "categories", "debts", "rules").
@Model
public final class Tombstone {
    public var id: UUID
    public var collection: String
    public var deletedAt: Date

    public init(id: UUID, collection: String, deletedAt: Date = .now) {
        self.id = id
        self.collection = collection
        self.deletedAt = deletedAt
    }
}

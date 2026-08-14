import Foundation

public struct FriendSnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct DebtSnapshot: Sendable, Equatable {
    public let id: UUID
    public let friendID: UUID?
    public let friendName: String
    public let amount: Decimal
    public let direction: DebtDirection
    public let remaining: Decimal
    public let settled: Bool
    public let dueDate: Date?

    public init(
        id: UUID,
        friendID: UUID?,
        friendName: String,
        amount: Decimal,
        direction: DebtDirection,
        remaining: Decimal,
        settled: Bool,
        dueDate: Date?
    ) {
        self.id = id
        self.friendID = friendID
        self.friendName = friendName
        self.amount = amount
        self.direction = direction
        self.remaining = remaining
        self.settled = settled
        self.dueDate = dueDate
    }
}

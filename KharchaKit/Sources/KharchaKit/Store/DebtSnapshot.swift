import Foundation

public struct FriendSnapshot: Sendable, Equatable {
    public let id: UUID
    public let name: String
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
}

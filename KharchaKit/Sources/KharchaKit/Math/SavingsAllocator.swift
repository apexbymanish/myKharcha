import Foundation

/// One thing a savings pot should cover — a recurring bill (Rent, Netflix) or a
/// savings goal (Emergency). `priority` decides reserve order: **lower reserves
/// first**. Callers encode "soonest due" as a lower priority.
public struct SavingsObligation: Sendable, Equatable {
    public let name: String
    public let amount: Decimal
    public let priority: Int
    public init(name: String, amount: Decimal, priority: Int = 0) {
        self.name = name
        self.amount = amount
        self.priority = priority
    }
}

/// How much of the pot was reserved for one obligation, and how much it fell short.
public struct SavingsAllocationLine: Sendable, Equatable {
    public let name: String
    public let reserved: Decimal
    public let shortfall: Decimal
    public init(name: String, reserved: Decimal, shortfall: Decimal) {
        self.name = name
        self.reserved = reserved
        self.shortfall = shortfall
    }
}

/// The result of splitting a pot: per-obligation reserves (in priority order),
/// leftover `free` savings, and the total unfunded amount.
public struct SavingsAllocation: Sendable, Equatable {
    public let lines: [SavingsAllocationLine]
    public let free: Decimal
    public let totalShortfall: Decimal
    public var isFullyFunded: Bool { totalShortfall == 0 }
    public init(lines: [SavingsAllocationLine], free: Decimal, totalShortfall: Decimal) {
        self.lines = lines
        self.free = free
        self.totalShortfall = totalShortfall
    }
}

/// Pure envelope allocator: given a savings balance and a set of obligations,
/// reserve money for each in priority order (stable within equal priority),
/// leaving the remainder as free savings and reporting any shortfall.
public enum SavingsAllocator {
    public static func plan(balance: Decimal, obligations: [SavingsObligation]) -> SavingsAllocation {
        // Stable sort: primary by priority ascending, tie-break by original order.
        let ordered = obligations.enumerated()
            .sorted { lhs, rhs in
                lhs.element.priority != rhs.element.priority
                    ? lhs.element.priority < rhs.element.priority
                    : lhs.offset < rhs.offset
            }
            .map(\.element)

        var remaining = max(balance, 0)
        var lines: [SavingsAllocationLine] = []
        var totalShortfall: Decimal = 0

        for obligation in ordered {
            let needed = max(obligation.amount, 0)
            let reserved = min(remaining, needed)
            let shortfall = needed - reserved
            remaining -= reserved
            totalShortfall += shortfall
            lines.append(SavingsAllocationLine(name: obligation.name, reserved: reserved, shortfall: shortfall))
        }

        return SavingsAllocation(lines: lines, free: remaining, totalShortfall: totalShortfall)
    }
}

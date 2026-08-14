import Foundation
import SwiftData
@testable import KharchaKit

var testCal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    c.firstWeekday = 2
    return c
}

func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12) -> Date {
    testCal.date(from: DateComponents(timeZone: testCal.timeZone, year: y, month: m, day: day, hour: h))!
}

func makeStore() throws -> ExpenseStore {
    let container = try ModelContainer(
        for: Schema(KharchaSchema.models),
        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
    )
    return ExpenseStore(modelContainer: container)
}

import Testing
import Foundation
@testable import KharchaKit

struct ExpenseTextParserTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test func parsesAmountsAndNotesPerLine() {
        let now = date(2026, 8, 20)
        let text = """
        Lunch 500
        Coffee ₹120
        this line has no money
        Groceries 1,250.50
        """
        let items = ExpenseTextParser.parse(text, now: now, calendar: cal)
        #expect(items.count == 3)
        #expect(items[0].amount == 500)
        #expect(items[0].note == "Lunch")
        #expect(items[1].amount == 120)
        #expect(items[1].note == "Coffee")
        #expect(items[2].amount == Decimal(string: "1250.50"))
        #expect(items[2].note == "Groceries")
    }

    @Test func usesDetectedDateAndDoesNotTreatYearAsAmount() {
        let now = date(2026, 8, 20)
        let items = ExpenseTextParser.parse("Taxi 1,200 on Jan 5 2026", now: now, calendar: cal)
        #expect(items.count == 1)
        #expect(items[0].amount == 1_200)               // not 2026, not 5
        #expect(cal.dateComponents([.year, .month, .day], from: items[0].date)
                == DateComponents(year: 2026, month: 1, day: 5))
    }

    @Test func linesWithoutAmountsAreSkipped() {
        let items = ExpenseTextParser.parse("just a note\nhello world", now: date(2026, 8, 20), calendar: cal)
        #expect(items.isEmpty)
    }

    @Test func dedupKeyMatchesOnAmountDayAndNote() {
        let a = ExpenseTextParser.dedupKey(amount: 500, date: date(2026, 8, 20), note: "Lunch", calendar: cal)
        let b = ExpenseTextParser.dedupKey(amount: 500, date: date(2026, 8, 20), note: "lunch", calendar: cal)
        let c = ExpenseTextParser.dedupKey(amount: 500, date: date(2026, 8, 21), note: "Lunch", calendar: cal)
        #expect(a == b)   // case/whitespace-insensitive, same day
        #expect(a != c)   // different day
    }

    @Test func decimalParsingStripsSymbolsAndSeparators() {
        #expect(ExpenseTextParser.decimal(from: "₹1,200") == 1_200)
        #expect(ExpenseTextParser.decimal(from: "$12.50") == Decimal(string: "12.50"))
        #expect(ExpenseTextParser.decimal(from: "abc") == nil)
        #expect(ExpenseTextParser.decimal(from: "0") == nil)     // must be positive
    }
}

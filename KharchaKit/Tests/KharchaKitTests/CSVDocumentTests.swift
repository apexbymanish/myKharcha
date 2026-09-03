import Testing
import Foundation
@testable import KharchaKit

@Test func documentHasBOMAndTrailingNewline() {
    let rows = [TxnRow(id: UUID(), date: d(2026, 8, 14), kind: .expense, amount: 12_000, categoryName: "Food", note: "점심", source: .manual)]
    let doc = CSVDocumentBuilder.document(rows, timeZone: testCal.timeZone)
    #expect(doc.hasPrefix("\u{FEFF}date,kind,amount,category,note"))
    #expect(doc.hasSuffix("\n"))
    #expect(doc.contains("점심"))
}

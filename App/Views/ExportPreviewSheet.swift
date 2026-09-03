import SwiftUI
import KharchaKit

/// What the export contains, shown before it leaves the app.
///
/// Export used to hand straight to the share sheet, so the first look anyone
/// got at their own data was in whatever app they sent it to. Listing the
/// transactions themselves — category, note, signed amount, grouped by day —
/// answers "is this the right period, and is this everything?" while the file
/// is still yours, which is the question people actually have at the moment
/// they tap Export.
struct ExportPreviewSheet: View {
    let rows: [TxnRow]
    let periodLabel: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var privacy: PrivacyManager

    /// A day and everything on it, newest first.
    ///
    /// The preview lists transactions rather than daily totals because that is
    /// what the file holds. A roll-up looked tidier and answered the wrong
    /// question: "₩900,000 on the 26th" tells you nothing you can check, where
    /// "Other · Loan payed · ₩900,000" is the line you either recognise or
    /// don't. Days are the grouping so the list stays scannable, not the unit.
    private struct DayGroup: Identifiable {
        let id: Date
        let rows: [TxnRow]
        let spent: Decimal
        let received: Decimal
    }

    private var dayGroups: [DayGroup] {
        let cal = Calendar.current
        return Dictionary(grouping: rows) { cal.startOfDay(for: $0.date) }
            .map { date, dayRows in
                DayGroup(
                    id: date,
                    // Largest first within a day: the entry worth checking is
                    // almost always the big one.
                    rows: dayRows.sorted { $0.amount > $1.amount },
                    spent: dayRows.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount },
                    received: dayRows.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
                )
            }
            .sorted { $0.id > $1.id }
    }

    private var exportURL: URL? {
        CSVFileWriter.write(CSVExporter.export(rows, timeZone: .current))
    }

    private func money(_ amount: Decimal) -> String {
        privacy.isRevealed ? AmountFormatter.money(amount) : "••••"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                List {
                    ForEach(dayGroups) { day in
                        Section {
                            ForEach(day.rows, id: \.id) { row in
                                ExportRowView(row: row, isRevealed: privacy.isRevealed)
                            }
                        } header: {
                            dayHeader(day)
                        }
                    }
                }
                .listStyle(.plain)

                exportButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    /// The date, and the day's two totals in the signs the rows use, so a day
    /// can be checked against its parts without adding them up yourself.
    @ViewBuilder private func dayHeader(_ day: DayGroup) -> some View {
        HStack(spacing: 8) {
            Text(day.id.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 4)
            if day.spent > 0 {
                Text("−" + money(day.spent))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.moneyOut)
            }
            if day.received > 0 {
                Text("+" + money(day.received))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.moneyIn)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text("Export Data").font(.title2.bold())
                Text(periodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.18), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// A `ShareLink` rather than a button that opens one: the file is written
    /// when the view is built, so the share sheet has something to hand over
    /// the moment it is tapped rather than after a round trip through state.
    @ViewBuilder private var exportButton: some View {
        if let url = exportURL {
            ShareLink(item: url, preview: SharePreview("Kharcha-Export.csv")) {
                Text("Export")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.brandPrimary, in: Capsule())
                    .foregroundStyle(.white)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        } else {
            // The writer returns nil when the file cannot be created — a full
            // disk, or a sandbox that has gone away. Saying so beats a button
            // that does nothing when tapped.
            Text("Couldn't prepare the export.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
    }
}

/// One transaction as it will appear in the file: its category, whatever note
/// was written on it, and the amount signed by direction.
///
/// The note is the whole point of previewing at all. "Other · ₩900,000" is a
/// figure you have to trust; "Other · Loan payed · ₩900,000" is one you can
/// check. Where a row has no note the category stands alone rather than leaving
/// an empty line under it.
private struct ExportRowView: View {
    let row: TxnRow
    let isRevealed: Bool

    private var category: String {
        row.categoryName.isEmpty ? String(localized: "Uncategorized") : row.categoryName
    }

    private var note: String? {
        guard let note = row.note?.trimmingCharacters(in: .whitespacesAndNewlines),
              !note.isEmpty else { return nil }
        return note
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(category)
                    .font(.subheadline)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 4)
            Text((row.kind == .expense ? "−" : "+") + (isRevealed ? AmountFormatter.money(row.amount) : "••••"))
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(row.kind == .expense ? Color.moneyOut : Color.moneyIn)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}

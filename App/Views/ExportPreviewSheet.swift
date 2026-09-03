import SwiftUI
import KharchaKit

/// What the export contains, shown before it leaves the app.
///
/// Export used to hand straight to the share sheet, so the first look anyone
/// got at their own data was in whatever app they sent it to. A day-by-day
/// table answers "is this the right period, and is this everything?" while the
/// file is still yours — which is the question people actually have at the
/// moment they tap Export.
struct ExportPreviewSheet: View {
    let rows: [TxnRow]
    let periodLabel: String

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var privacy: PrivacyManager

    /// One line per day, newest first, both directions on the same row so a day
    /// that earned and spent reads as one day rather than two entries.
    private struct DayLine: Identifiable {
        let id: Date
        let spent: Decimal
        let received: Decimal
    }

    private var lines: [DayLine] {
        let cal = Calendar.current
        return Dictionary(grouping: rows) { cal.startOfDay(for: $0.date) }
            .map { date, dayRows in
                DayLine(
                    id: date,
                    spent: dayRows.filter { $0.kind == .expense }.reduce(Decimal(0)) { $0 + $1.amount },
                    received: dayRows.filter { $0.kind == .income }.reduce(Decimal(0)) { $0 + $1.amount }
                )
            }
            .sorted { $0.id > $1.id }
    }

    /// The CSV carries every transaction, not the daily roll-up above. The table
    /// is there to be read; the file is there to be worked with, and collapsing
    /// it to one line a day would throw away the categories and notes that make
    /// it worth exporting at all.
    private var exportURL: URL? {
        CSVFileWriter.write(CSVExporter.export(rows, timeZone: .current))
    }

    private func money(_ amount: Decimal) -> String {
        guard privacy.isRevealed else { return "••••" }
        return amount > 0 ? AmountFormatter.money(amount) : "—"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                // A glyph per column instead of a heading per column: three
                // words of header would wrap at large text sizes and push the
                // first row of real data off the screen.
                HStack(spacing: 0) {
                    Image(systemName: "calendar")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(Color.moneyOut)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.moneyIn)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.footnote)
                .padding(.horizontal)
                .padding(.bottom, 6)
                .accessibilityHidden(true)

                List(lines) { line in
                    HStack(spacing: 0) {
                        Text(line.id.formatted(.dateTime.month(.abbreviated).day().year()))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(money(line.spent))
                            .monospacedDigit()
                            .foregroundStyle(line.spent > 0 ? Color.moneyOut : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(money(line.received))
                            .monospacedDigit()
                            .foregroundStyle(line.received > 0 ? Color.moneyIn : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .accessibilityElement(children: .combine)
                }
                .listStyle(.plain)

                exportButton
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
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

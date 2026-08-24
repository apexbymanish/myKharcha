import SwiftUI
import UIKit
import Charts
import KharchaKit

// MARK: - Pay-cycle preference keys

/// App-side pay-cycle preference, stored in the shared App Group defaults (same
/// suite as `CurrencyPreference`) so Home and Settings resolve the same values.
/// `dayKey` is a day-of-month (1...31, clamped per month); `salaryKey` is a
/// monthly salary as a Double (0 means "not configured", planning stays hidden).
enum PayPreference {
    static let dayKey = "payday.dayOfMonth"
    static let salaryKey = "payday.monthlySalary"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: KharchaContainerFactory.appGroupID) ?? .standard
    }
}

// MARK: - Color

extension Color {
    /// Display-only decoding of a category's stored `colorHex` (e.g. "#E07A5F").
    /// Purely visual — never used for any decision logic. Resolves to a dynamic
    /// color so a dark stored hue (e.g. deep navy) stays legible against the
    /// dark-mode background; light mode renders the stored color unchanged.
    init(hex: String) {
        self.init(uiColor: UIColor(categoryHex: hex))
    }
}

private extension UIColor {
    convenience init(categoryHex hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        let base = UIColor(red: r, green: g, blue: b, alpha: 1)

        self.init { traits in
            guard traits.userInterfaceStyle == .dark else { return base }
            // In dark mode, floor the brightness and ease saturation so very
            // dark stored colors don't disappear on the dark background.
            var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
            base.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
            return UIColor(
                hue: h,
                saturation: s * 0.85,
                brightness: max(br, 0.72),
                alpha: a
            )
        }
    }
}

// MARK: - Money palette (WCAG-compliant income / expense colors)

extension Color {
    /// Positive / income / "owes you". System `.green` is only ~2.2:1 on white;
    /// this darkens in light mode (~4.6:1) and brightens in dark mode.
    static let moneyIn = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.85, blue: 0.39, alpha: 1)
            : UIColor(red: 0.00, green: 0.50, blue: 0.20, alpha: 1)
    })

    /// Negative / expense / "you owe" / over-budget. System `.red` is ~3.55:1
    /// on white; this reaches ~4.5:1 in light mode and brightens in dark mode.
    static let moneyOut = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.42, blue: 0.38, alpha: 1)
            : UIColor(red: 0.80, green: 0.00, blue: 0.05, alpha: 1)
    })
}

// MARK: - Stat block (reusable label + amount pair)

/// A titled amount used in summary headers. Kept alignment-agnostic so the same
/// component serves both the leading "Spent" column and the trailing "Income"
/// column, and so `ViewThatFits` can reflow a row of these into a column
/// without any size math.
struct StatBlock: View {
    let title: String
    let amount: String
    var tint: Color = .primary
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(amount)
                .font(.title2.bold())
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

// MARK: - Inline error (reusable error row)

/// Standard inline error shown by every screen's ViewModel error state.
/// Uses the adaptive `moneyOut` red (≥4.5:1) instead of system `.red`, and
/// pairs it with a warning glyph so the meaning is not conveyed by color alone.
struct InlineError: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .foregroundStyle(Color.moneyOut)
    }
}

// MARK: - Category chip (used by TxnFormView's grid)

struct CategoryChip: View {
    let category: CategorySnapshot
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: category.symbol)
                .font(.title3)
                .foregroundStyle(isSelected ? .white : Color(hex: category.colorHex))
                .frame(width: 44, height: 44)
                .background(isSelected ? Color(hex: category.colorHex) : Color(hex: category.colorHex).opacity(0.15))
                .clipShape(Circle())
            Text(category.name)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        // Read as one element ("Food, selected") rather than icon + label separately.
        // The enclosing Button contributes the `.isButton` trait.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Budget bar (app-side version of KharchaKit's Siri BudgetCard row)

struct BudgetBar: View {
    let status: BudgetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.categoryName).font(.callout)
                Spacer()
                Text("\(AmountFormatter.money(status.spent)) / \(AmountFormatter.money(status.budget))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(status.isOver ? Color.moneyOut : .secondary)
            }
            ProgressView(
                value: min((status.spent as NSDecimalNumber).doubleValue, (status.budget as NSDecimalNumber).doubleValue),
                total: max((status.budget as NSDecimalNumber).doubleValue, 1)
            )
            .tint(status.isOver ? Color.moneyOut : .accentColor)
        }
        // "Over budget" must be conveyed to VoiceOver too — the red tint alone isn't perceivable.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.categoryName)
        .accessibilityValue(
            "\(AmountFormatter.money(status.spent)) of \(AmountFormatter.money(status.budget))"
            + (status.isOver ? ", over budget" : "")
        )
    }
}

// MARK: - Friend debt chip (Home's horizontal friends strip)

struct FriendDebtChip: View {
    let row: DebtRow

    private var phrase: String {
        row.amount > 0
            ? "\(row.name) owes you \(AmountFormatter.money(row.amount))"
            : "You owe \(row.name) \(AmountFormatter.money(abs(row.amount)))"
    }

    var body: some View {
        Text(phrase)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background((row.amount > 0 ? Color.moneyIn : Color.moneyOut).opacity(0.22))
            .foregroundStyle(row.amount > 0 ? Color.moneyIn : Color.moneyOut)
            .clipShape(Capsule())
    }
}

// MARK: - Transaction row (Home's recent list + History)

struct TxnRowView: View {
    let row: TxnRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.categoryName.isEmpty ? "Uncategorized" : row.categoryName)
                    .font(.body)
                if let note = row.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text((row.kind == .expense ? "-" : "+") + AmountFormatter.money(row.amount))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(row.kind == .expense ? Color.primary : Color.moneyIn)
                Text(row.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        // Merge the four fragments into a single spoken row.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Text-field alert helper

/// Wraps `.alert(title, isPresented:)` with a single TextField + Save/Cancel so
/// the five "add X" / "set X" flows (Budgets, Reminders*, Friends, Settings,
/// FriendDetail settle) don't each hand-roll the same alert boilerplate.
/// *Reminders' multi-field add flow uses a full sheet instead — see RemindersView.
private struct TextFieldAlert: ViewModifier {
    @Binding var isPresented: Bool
    let title: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    let initialText: String
    let onSave: (String) -> Void

    @State private var text = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: $isPresented) {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboardType)
                Button("Save") {
                    onSave(text)
                    text = ""
                }
                Button("Cancel", role: .cancel) { text = "" }
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue { text = initialText }
            }
    }
}

extension View {
    func textFieldAlert(
        isPresented: Binding<Bool>,
        title: String,
        placeholder: String,
        keyboardType: UIKeyboardType = .default,
        initialText: String = "",
        onSave: @escaping (String) -> Void
    ) -> some View {
        modifier(TextFieldAlert(
            isPresented: isPresented,
            title: title,
            placeholder: placeholder,
            keyboardType: keyboardType,
            initialText: initialText,
            onSave: onSave
        ))
    }
}

// MARK: - Pay-cycle card (Home's salary planning summary)

/// Shows days-until-payday plus money-left and a safe daily spend for the current
/// cycle. Rendered only when the user has configured a payday + salary in Settings.
struct PayCycleCard: View {
    let plan: PayCyclePlan

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("\(plan.daysUntilPayday) days to payday", systemImage: "calendar")
                    .font(.callout)
                Spacer()
                Text(plan.nextPayday, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // At AX sizes the two stat blocks are too wide to sit side-by-side;
            // stack them so the amounts stay readable.
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    StatBlock(
                        title: String(localized: "Left this cycle"),
                        amount: AmountFormatter.money(plan.remaining),
                        tint: plan.isOverspent ? .moneyOut : .primary
                    )
                    StatBlock(
                        title: String(localized: "Safe to spend / day"),
                        amount: AmountFormatter.money(plan.safeToSpendPerDay),
                        tint: plan.isOverspent ? .moneyOut : .moneyIn
                    )
                }
            } else {
                HStack {
                    StatBlock(
                        title: String(localized: "Left this cycle"),
                        amount: AmountFormatter.money(plan.remaining),
                        tint: plan.isOverspent ? .moneyOut : .primary
                    )
                    StatBlock(
                        title: String(localized: "Safe to spend / day"),
                        amount: AmountFormatter.money(plan.safeToSpendPerDay),
                        tint: plan.isOverspent ? .moneyOut : .moneyIn,
                        alignment: .trailing
                    )
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pay cycle")
        .accessibilityValue(
            "\(plan.daysUntilPayday) days until payday. "
            + "\(AmountFormatter.money(plan.remaining)) left this cycle"
            + (plan.isOverspent ? ", over your salary" : "")
            + ". Safe to spend \(AmountFormatter.money(plan.safeToSpendPerDay)) per day."
        )
    }
}

// MARK: - Month at a glance (Home's inline budget health + due-soon strip)

/// A compact status strip shown below the balance hero — never requires a tap.
/// Shows budget health (on track vs over) and any installment due within 7 days.
/// Hidden by HomeView when both sets are empty.
struct MonthGlanceCard: View {
    let budgets: [BudgetStatus]
    let dueSoonItems: [HomeViewModel.State.DueSoonItem]

    private var onTrack: Int { budgets.filter { !$0.isOver }.count }
    private var overBudget: Int { budgets.filter { $0.isOver }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !budgets.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: overBudget > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(overBudget > 0 ? Color.moneyOut : Color.moneyIn)
                        .font(.subheadline)
                    Text(budgetLabel)
                        .font(.subheadline)
                }
            }
            if !budgets.isEmpty && !dueSoonItems.isEmpty {
                Divider()
            }
            if !dueSoonItems.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                    Text(dueSoonLabel)
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([budgetLabel, dueSoonItems.isEmpty ? nil : dueSoonLabel]
            .compactMap { $0 }.joined(separator: ". "))
    }

    private var budgetLabel: String {
        if overBudget > 0 {
            let plural = overBudget == 1 ? "budget" : "budgets"
            return "\(overBudget) \(plural) over · \(onTrack) on track"
        }
        return onTrack == 1 ? "1 budget on track" : "All \(onTrack) budgets on track"
    }

    private var dueSoonLabel: String {
        guard !dueSoonItems.isEmpty else { return "" }
        if dueSoonItems.count == 1 {
            let item = dueSoonItems[0]
            return "\(item.name) · \(AmountFormatter.money(item.amount)) due soon"
        }
        return "\(dueSoonItems.count) payments due soon"
    }
}

// MARK: - Spending donut chart (Home's "by category" breakdown)

/// A donut of the month's expenses by category, colored to match each category's
/// stored hue, with the total in the center and a compact legend beneath.
struct SpendingDonutChart: View {
    let breakdown: SpendingBreakdown
    let colors: [UUID: String]

    private struct Slice: Identifiable {
        let id = UUID()
        let name: String
        let amount: Double
        let color: Color
    }

    private var slices: [Slice] {
        breakdown.categories.map { c in
            let color = c.categoryID.flatMap { colors[$0] }.map { Color(hex: $0) } ?? .secondary
            return Slice(name: c.categoryName, amount: (c.amount as NSDecimalNumber).doubleValue, color: color)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Amount", slice.amount),
                    innerRadius: .ratio(0.62),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Category", slice.name))
            }
            .chartForegroundStyleScale(domain: slices.map(\.name), range: slices.map(\.color))
            .chartLegend(.hidden)
            .frame(height: 200)
            .overlay {
                VStack(spacing: 2) {
                    Text("Total").font(.caption).foregroundStyle(.secondary)
                    Text(AmountFormatter.money(breakdown.total))
                        .font(.headline.monospacedDigit())
                }
            }
            // Own legend (up to 6 rows) so colors line up with the category chips
            // used elsewhere and the layout stays readable with many categories.
            VStack(spacing: 6) {
                ForEach(slices.prefix(6)) { slice in
                    HStack(spacing: 8) {
                        Circle().fill(slice.color).frame(width: 10, height: 10)
                        Text(slice.name).font(.caption)
                        Spacer()
                        Text(AmountFormatter.money(Decimal(slice.amount)))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        // The chart itself is decorative; the legend rows carry the numbers, so
        // expose a single summary rather than unlabeled wedges to VoiceOver.
        .accessibilityElement(children: .contain)
    }
}

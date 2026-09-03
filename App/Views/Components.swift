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
    @EnvironmentObject private var privacy: PrivacyManager

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(privacy.isRevealed ? amount : "••••••")
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
            CategoryIconBadge(symbol: category.symbol, colorHex: category.colorHex, size: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 44 * 0.28, style: .continuous)
                        .strokeBorder(isSelected ? Color.brandPrimary : .clear, lineWidth: 2.5)
                )
            Text(category.name)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .multilineTextAlignment(.center)
                .foregroundStyle(isSelected ? Color.brandPrimary : .primary)
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
            status.isOver
                ? String(localized: "\(AmountFormatter.money(status.spent)) of \(AmountFormatter.money(status.budget)), over budget")
                : String(localized: "\(AmountFormatter.money(status.spent)) of \(AmountFormatter.money(status.budget))")
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
    /// Current categories, used to resolve `row.categoryName` to an icon/color
    /// swatch. Empty (the default) keeps the icon-less layout — callers that
    /// don't have a categories list on hand (e.g. Home's recent-activity row)
    /// are unaffected.
    var categories: [CategorySnapshot] = []
    @EnvironmentObject private var privacy: PrivacyManager

    private var resolvedCategory: CategorySnapshot? {
        guard !categories.isEmpty else { return nil }
        return CategorySnapshot.resolve(named: row.categoryName, in: categories)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let cat = resolvedCategory {
                CategoryIconBadge(symbol: cat.symbol, colorHex: cat.colorHex)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.categoryName.isEmpty ? "Uncategorized" : row.categoryName)
                    .font(.body)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let note = row.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(privacy.isRevealed
                     ? (row.kind == .expense ? "-" : "+") + AmountFormatter.money(row.amount)
                     : (row.kind == .expense ? "-" : "+") + "••••••")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(row.kind == .expense ? Color.primary : Color.moneyIn)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(row.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        // Merge the four fragments into a single spoken row.
        .accessibilityElement(children: .combine)
    }
}

/// A category's icon rendered on its stored color — the small swatch shown
/// beside each transaction row and, at a smaller size, each category chip.
struct CategoryIconBadge: View {
    let symbol: String
    let colorHex: String
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Color(hex: colorHex))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(.white)
            }
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
    @EnvironmentObject private var privacy: PrivacyManager

    private var accessibilityValueString: String {
        guard privacy.isRevealed else {
            return String(localized: "\(plan.daysUntilPayday) days until payday. Amounts hidden.")
        }
        // Whole sentences, joined by the locale's own list separator. Appending
        // fragments with `+=` baked English word order into every language and,
        // because none of the pieces went through the catalog, VoiceOver read
        // this card in English however the phone was set.
        var parts = [String(localized: "\(plan.daysUntilPayday) days until payday.")]
        if plan.isOverspent {
            parts.append(String(localized: "Over budget by \(AmountFormatter.money(plan.overspentBy)). Avoid new spending."))
        } else {
            parts.append(String(localized: "\(AmountFormatter.money(plan.remaining)) left to spend this cycle."))
            parts.append(String(localized: "Safe to spend \(AmountFormatter.money(plan.safeToSpendPerDay)) per day."))
        }
        if plan.savingsReserved > 0 {
            parts.append(String(localized: "\(AmountFormatter.money(plan.savingsReserved)) reserved for savings."))
        }
        return parts.joined(separator: " ")
    }

    private var spentFraction: Double {
        guard plan.salary > 0 else { return 0 }
        let fraction = NSDecimalNumber(decimal: plan.spentThisCycle / plan.salary).doubleValue
        return min(max(fraction, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: days + next payday date
            HStack {
                Label("\(plan.daysUntilPayday) days to payday", systemImage: "calendar")
                    .font(.callout)
                Spacer()
                Text(plan.nextPayday, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Cycle progress: spent vs salary
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if privacy.isRevealed {
                        // Single spaces. The key used to carry two on each side
                        // of "of" as a typographic tweak, which hands translators
                        // a string whose whitespace looks like a mistake — and
                        // any of them who normalises it silently changes the
                        // layout. Spacing belongs in the layout, not the string.
                        Text("\(AmountFormatter.money(plan.spentThisCycle)) of \(AmountFormatter.money(plan.salary))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(plan.isOverspent ? Color.moneyOut : .secondary)
                    } else {
                        Text("••••• of •••••")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                        Capsule()
                            .fill(plan.isOverspent ? Color.moneyOut : Color.brandPrimary)
                            .frame(width: geo.size.width * spentFraction)
                    }
                }
                .frame(height: 6)
            }

            // Stat blocks: remaining / daily allowance
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    StatBlock(
                        title: plan.isOverspent
                            ? String(localized: "Over budget by")
                            : String(localized: "Left to spend"),
                        amount: AmountFormatter.money(plan.isOverspent ? plan.overspentBy : plan.remaining),
                        tint: plan.isOverspent ? .moneyOut : .primary
                    )
                    StatBlock(
                        title: plan.isOverspent
                            ? String(localized: "Stop new spending")
                            : String(localized: "Safe to spend / day"),
                        amount: AmountFormatter.money(plan.safeToSpendPerDay),
                        tint: plan.isOverspent ? .moneyOut : .moneyIn
                    )
                }
            } else {
                HStack {
                    StatBlock(
                        title: plan.isOverspent
                            ? String(localized: "Over budget by")
                            : String(localized: "Left to spend"),
                        amount: AmountFormatter.money(plan.isOverspent ? plan.overspentBy : plan.remaining),
                        tint: plan.isOverspent ? .moneyOut : .primary
                    )
                    StatBlock(
                        title: plan.isOverspent
                            ? String(localized: "Stop new spending")
                            : String(localized: "Safe to spend / day"),
                        amount: AmountFormatter.money(plan.safeToSpendPerDay),
                        tint: plan.isOverspent ? .moneyOut : .moneyIn,
                        alignment: .trailing
                    )
                }
            }

            if plan.savingsReserved > 0 {
                Label(
                    "\(AmountFormatter.money(plan.savingsReserved)) reserved for savings  (\(plan.savingsRatePercent)%)",
                    systemImage: "banknote"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pay cycle")
        .accessibilityValue(accessibilityValueString)
    }
}

// MARK: - Month at a glance (Home's inline budget health + due-soon strip)

/// A compact status strip shown below the balance hero — never requires a tap.
/// Items due within 3 days are promoted to a prominent amber card.
/// Items due in 4–7 days stay as a compact strip.
/// Hidden by HomeView when both budgets and dueSoonItems are empty.
struct MonthGlanceCard: View {
    let budgets: [BudgetStatus]
    let dueSoonItems: [HomeViewModel.State.DueSoonItem]
    let isRevealed: Bool

    private var onTrack: Int { budgets.filter { !$0.isOver }.count }
    private var overBudget: Int { budgets.filter { $0.isOver }.count }
    // Auto-pay items never show as urgent — user delegated them to the app.
    private var urgentItems: [HomeViewModel.State.DueSoonItem] { dueSoonItems.filter { $0.daysUntil <= 3 && !$0.autoLog } }
    private var autoItems: [HomeViewModel.State.DueSoonItem] { dueSoonItems.filter { $0.autoLog } }
    private var soonItems: [HomeViewModel.State.DueSoonItem] { dueSoonItems.filter { $0.daysUntil > 3 && !$0.autoLog } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !budgets.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: overBudget > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(overBudget > 0 ? Color.moneyOut : Color.moneyIn)
                        .font(.subheadline)
                    Text(budgetLabel)
                        .font(.subheadline)
                    Spacer()
                    // The card opens Budgets. Without the chevron it reads as a
                    // status readout, and a tappable thing that does not look
                    // tappable is one nobody taps.
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            // Manual items due ≤3 days — urgent, needs user action.
            if !urgentItems.isEmpty {
                if !budgets.isEmpty { Divider() }
                ForEach(urgentItems) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.daysUntil == 0 ? "exclamationmark.circle.fill" : "clock.badge.exclamationmark.fill")
                            .foregroundStyle(item.daysUntil == 0 ? Color.moneyOut : Color.orange)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                            Text(urgencyText(for: item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(isRevealed ? AmountFormatter.money(item.amount) : "••••")
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundStyle(item.daysUntil == 0 ? Color.moneyOut : Color.orange)
                    }
                    .padding(10)
                    .background((item.daysUntil == 0 ? Color.moneyOut : Color.orange).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            // Auto-pay items — calm confirmation, no urgency.
            if !autoItems.isEmpty {
                if !budgets.isEmpty || !urgentItems.isEmpty { Divider() }
                HStack(spacing: 8) {
                    Image(systemName: "bolt.circle.fill")
                        .foregroundStyle(Color.moneyIn)
                        .font(.subheadline)
                    Text(autoLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            // Manual items due 4–7 days — soft heads-up.
            if !soonItems.isEmpty {
                if !budgets.isEmpty || !urgentItems.isEmpty || !autoItems.isEmpty { Divider() }
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                    Text(soonLabel)
                        .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func urgencyText(for item: HomeViewModel.State.DueSoonItem) -> String {
        switch item.daysUntil {
        case 0: return String(localized: "Due today")
        case 1: return String(localized: "Due tomorrow")
        default: return String(localized: "Due in \(item.daysUntil) days")
        }
    }

    private var autoLabel: String {
        if autoItems.count == 1 {
            return String(localized: "\(autoItems[0].name) · auto-logging")
        }
        return String(localized: "\(autoItems.count) payments auto-logging")
    }

    private var soonLabel: String {
        if soonItems.count == 1 {
            let item = soonItems[0]
            let amount = isRevealed ? AmountFormatter.money(item.amount) : "••••"
            return String(localized: "\(item.name) · \(amount) due soon")
        }
        return String(localized: "\(soonItems.count) payments due soon")
    }

    private var budgetLabel: String {
        // Counts go through the catalog as counts, not as a hand-picked
        // singular or plural. `overBudget == 1 ? "budget" : "budgets"` is only
        // right for the two-form languages; Russian and Arabic need four and
        // six, and no ternary can express that. A `%lld` key lets the catalog
        // carry each language's own plural rules.
        if overBudget > 0 {
            return String(localized: "\(overBudget) over budget · \(onTrack) on track")
        }
        return String(localized: "\(onTrack) budgets on track")
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if !budgets.isEmpty { parts.append(budgetLabel) }
        for item in urgentItems {
            parts.append("\(item.name), \(urgencyText(for: item)), \(AmountFormatter.money(item.amount))")
        }
        if !autoItems.isEmpty { parts.append(autoLabel) }
        if !soonItems.isEmpty { parts.append(soonLabel) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - Spending donut chart (Home's "by category" breakdown)

/// A donut of the month's expenses by category, colored to match each category's
/// stored hue, with the total in the center and a compact legend beneath.
struct SpendingDonutChart: View {
    let breakdown: SpendingBreakdown
    let colors: [UUID: String]
    let isRevealed: Bool

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
                    Text(isRevealed ? AmountFormatter.money(breakdown.total) : "••••")
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
                        Text(isRevealed ? AmountFormatter.money(Decimal(slice.amount)) : "••••")
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

// MARK: - Undo toast

/// Bottom-edge toast shown after a destructive-ish action (mark paid, record payment).
/// Auto-dismissed by the caller after ~4 seconds; tap "Undo" to reverse immediately.
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack {
            Text(message)
                .font(.subheadline)
            Spacer()
            Button("Undo", action: onUndo)
                .font(.subheadline.bold())
                .foregroundStyle(Color.brandPrimary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

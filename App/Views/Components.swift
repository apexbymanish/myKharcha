import SwiftUI
import UIKit
import KharchaKit

// MARK: - Color

extension Color {
    /// Display-only decoding of a category's stored `colorHex` (e.g. "#E07A5F").
    /// Purely visual — never used for any decision logic.
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
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
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
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
                Text("\(AmountFormatter.krw(status.spent)) / \(AmountFormatter.krw(status.budget))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(status.isOver ? .red : .secondary)
            }
            ProgressView(
                value: min((status.spent as NSDecimalNumber).doubleValue, (status.budget as NSDecimalNumber).doubleValue),
                total: max((status.budget as NSDecimalNumber).doubleValue, 1)
            )
            .tint(status.isOver ? .red : .accentColor)
        }
    }
}

// MARK: - Friend debt chip (Home's horizontal friends strip)

struct FriendDebtChip: View {
    let row: DebtRow

    private var phrase: String {
        row.amount > 0
            ? "\(row.name) owes you \(AmountFormatter.krw(row.amount))"
            : "You owe \(row.name) \(AmountFormatter.krw(abs(row.amount)))"
    }

    var body: some View {
        Text(phrase)
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background((row.amount > 0 ? Color.green : Color.red).opacity(0.15))
            .foregroundStyle(row.amount > 0 ? .green : .red)
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
                Text((row.kind == .expense ? "-" : "+") + AmountFormatter.krw(row.amount))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(row.kind == .expense ? Color.primary : Color.green)
                Text(row.date, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
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

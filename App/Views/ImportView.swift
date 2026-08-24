import SwiftUI
import KharchaKit

/// Paste notes / messages / email text; the app extracts expenses (on-device
/// model when available, regex fallback otherwise), flags duplicates, and
/// batch-imports the rows you keep.
struct ImportView: View {
    let store: ExpenseStore
    @StateObject private var vm: ImportViewModel
    @State private var text = ""
    @FocusState private var editorFocused: Bool

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: ImportViewModel(store: store, rates: FrankfurterRateService()))
    }

    var body: some View {
        List {
            Section {
                // A multiline TextField (axis: .vertical) instead of TextEditor —
                // TextEditor inside a List can hang the main thread on paste/layout.
                TextField("Paste or type here…", text: $text, axis: .vertical)
                    .lineLimit(4...12)
                    .focused($editorFocused)
                Button {
                    editorFocused = false
                    Task { await vm.parse(text) }
                } label: {
                    if vm.state.isParsing {
                        HStack { ProgressView(); Text("Detecting…") }
                    } else {
                        Label("Detect Transactions", systemImage: "sparkles")
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.state.isParsing)
            } header: {
                Text("Paste notes, messages, or email")
            } footer: {
                Text("The app finds amounts and dates, and flags anything that looks like a duplicate.")
            }

            if !vm.state.rows.isEmpty {
                Section {
                    ForEach(vm.state.rows) { row in
                        ImportRowView(
                            row: row,
                            categories: vm.state.categories,
                            onToggle: { vm.setInclude(row.id, $0) },
                            onCategory: { vm.setCategory(row.id, $0) }
                        )
                    }
                } header: {
                    Text("Detected — \(vm.selectedCount) selected")
                } footer: {
                    Text(vm.state.usedModel
                         ? "Detected on-device with Apple Intelligence."
                         : "Detected with text patterns.")
                }

                Section {
                    Button {
                        Task { await vm.importSelected() }
                    } label: {
                        Text("Import \(vm.selectedCount) Transaction\(vm.selectedCount == 1 ? "" : "s")")
                    }
                    .disabled(vm.selectedCount == 0)
                }
            }

            if let count = vm.state.importedCount {
                Label("Imported \(count) transaction\(count == 1 ? "" : "s").", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Color.moneyIn)
            }
            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle("Import from Text")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") {
                    text = ""
                    editorFocused = false
                    vm.clear()
                }
                .disabled(text.isEmpty && vm.state.rows.isEmpty && vm.state.importedCount == nil)
            }
        }
    }
}

/// One reviewable detected expense: include toggle, amount/date/note, a category
/// picker, and a duplicate badge.
private struct ImportRowView: View {
    let row: ImportViewModel.Row
    let categories: [CategorySnapshot]
    let onToggle: (Bool) -> Void
    let onCategory: (UUID?) -> Void

    private var includeBinding: Binding<Bool> {
        Binding(get: { row.include }, set: onToggle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle(isOn: includeBinding) {
                    HStack(spacing: 6) {
                        Text((row.kind == .income ? "+" : "") + AmountFormatter.money(row.amount))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(row.kind == .income ? Color.moneyIn : .primary)
                        if row.kind == .income {
                            Text("Income")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.moneyIn.opacity(0.2))
                                .foregroundStyle(Color.moneyIn)
                                .clipShape(Capsule())
                        }
                    }
                }
                .toggleStyle(.switch)
            }
            if let orig = row.originalAmount, let code = row.originalCurrency {
                Text("\(AmountFormatter.money(orig, currencyCode: code)) → \(AmountFormatter.money(row.amount))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(row.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !row.note.isEmpty {
                    Text(row.note).font(.caption)
                }
                if row.isDuplicate {
                    Text("Duplicate")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.moneyOut.opacity(0.2))
                        .foregroundStyle(Color.moneyOut)
                        .clipShape(Capsule())
                }
            }
            Menu {
                Button("Uncategorized") { onCategory(nil) }
                ForEach(categories, id: \.id) { category in
                    Button(category.name) { onCategory(category.id) }
                }
            } label: {
                let name = categories.first { $0.id == row.categoryID }?.name ?? "Uncategorized"
                Label(name, systemImage: "tag")
                    .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

import SwiftUI
import UIKit
import KharchaKit

struct SavingsView: View {
    let store: ExpenseStore
    @StateObject private var vm: SavingsViewModel
    @State private var showAddPot = false
    @State private var showAddGoal = false

    init(store: ExpenseStore) {
        self.store = store
        _vm = StateObject(wrappedValue: SavingsViewModel(store: store))
    }

    var body: some View {
        List {
            if !vm.state.pots.isEmpty {
                Section {
                    SavingsAllocationCard(total: vm.state.totalBalance, allocation: vm.state.allocation)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            Section("Pots") {
                if vm.state.pots.isEmpty {
                    EmptyStateView(
                        icon: "banknote",
                        title: "No savings pots",
                        message: "Add a bank/pot and record what you save. The app tells you how much to keep for rent, subs, and goals."
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
                ForEach(vm.state.pots) { pot in
                    NavigationLink {
                        SavingsPotDetailView(vm: vm, pot: pot)
                    } label: {
                        HStack {
                            Label(pot.name, systemImage: "building.columns")
                            Spacer()
                            Text(AmountFormatter.money(pot.balance))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(Color.moneyIn)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await vm.deletePot(id: pot.id) } }
                    }
                }
                Button {
                    showAddPot = true
                } label: {
                    Label("Add Pot", systemImage: "plus")
                }
            }

            Section("Goals") {
                if vm.state.goals.isEmpty {
                    Text("No goals yet").foregroundStyle(.secondary)
                }
                ForEach(vm.state.goals) { goal in
                    HStack {
                        Text(goal.name)
                        Spacer()
                        Text(AmountFormatter.money(goal.targetAmount))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await vm.deleteGoal(id: goal.id) } }
                    }
                }
                Button {
                    showAddGoal = true
                } label: {
                    Label("Add Goal", systemImage: "target")
                }
            }

            if let error = vm.state.errorMessage {
                InlineError(message: error)
            }
        }
        .navigationTitle("Savings")
        .textFieldAlert(isPresented: $showAddPot, title: "Add Pot", placeholder: "Bank / pot name") { name in
            Task { await vm.addPot(name: name, note: nil) }
        }
        .sheet(isPresented: $showAddGoal) {
            NavigationStack { AddSavingsGoalSheet(vm: vm) }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await vm.load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .kharchaRemoteDidChange)) { _ in
            Task { await vm.load() }
        }
    }
}

/// The "how should this be split" card: total, per-obligation reserves, free.
private struct SavingsAllocationCard: View {
    let total: Decimal
    let allocation: SavingsAllocation?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total saved").font(.subheadline).foregroundStyle(.white.opacity(0.9))
                Text(AmountFormatter.money(total))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
            if let a = allocation, !a.lines.isEmpty {
                Divider().overlay(.white.opacity(0.35))
                ForEach(a.lines, id: \.name) { line in
                    HStack {
                        Text(line.name).font(.subheadline).foregroundStyle(.white.opacity(0.9))
                        Spacer()
                        Text(AmountFormatter.money(line.reserved))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.white)
                        if line.shortfall > 0 {
                            Text("(-\(AmountFormatter.money(line.shortfall)))")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
                Divider().overlay(.white.opacity(0.35))
                HStack {
                    Text("Free to use").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer()
                    Text(AmountFormatter.money(a.free))
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
                if a.totalShortfall > 0 {
                    Text("Short \(AmountFormatter.money(a.totalShortfall)) for this month's commitments.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .brandPrimary.opacity(0.25), radius: 10, x: 0, y: 6)
        .accessibilityElement(children: .combine)
    }
}

/// A pot's ledger: balance + records + add deposit/withdrawal.
private struct SavingsPotDetailView: View {
    @ObservedObject var vm: SavingsViewModel
    let pot: SavingsPotSnapshot

    @State private var entries: [SavingsEntrySnapshot] = []
    @State private var showAddEntry = false

    private var balance: Decimal {
        vm.state.pots.first { $0.id == pot.id }?.balance ?? pot.balance
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Balance")
                    Spacer()
                    Text(AmountFormatter.money(balance))
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(Color.moneyIn)
                }
            }

            Section("Records") {
                if entries.isEmpty {
                    Text("No records yet").foregroundStyle(.secondary)
                }
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.amount >= 0 ? "Deposit" : "Withdrawal").font(.callout)
                            if let note = entry.note, !note.isEmpty {
                                Text(note).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(entry.date, style: .date).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text((entry.amount >= 0 ? "+" : "") + AmountFormatter.money(entry.amount))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(entry.amount >= 0 ? Color.moneyIn : Color.moneyOut)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            Task { await vm.deleteEntry(id: entry.id); await reload() }
                        }
                    }
                }
            }
        }
        .navigationTitle(pot.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddEntry = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add record")
            }
        }
        .sheet(isPresented: $showAddEntry, onDismiss: { Task { await reload() } }) {
            NavigationStack { AddSavingsEntrySheet(vm: vm, potID: pot.id) }
        }
        .task { await reload() }
    }

    private func reload() async {
        entries = await vm.entries(potID: pot.id)
    }
}

private struct AddSavingsEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: SavingsViewModel
    let potID: UUID

    @State private var isDeposit = true
    @State private var amountText = ""
    @State private var note = ""

    var body: some View {
        Form {
            Picker("Type", selection: $isDeposit) {
                Text("Deposit").tag(true)
                Text("Withdrawal").tag(false)
            }
            .pickerStyle(.segmented)
            TextField("Amount", text: $amountText).keyboardType(.decimalPad)
            TextField("Note (optional)", text: $note)
        }
        .navigationTitle(isDeposit ? "Deposit" : "Withdrawal")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let magnitude = ExpenseTextParser.decimal(from: amountText) else { return }
                    let amount = isDeposit ? magnitude : -magnitude
                    Task {
                        await vm.addEntry(potID: potID, amount: amount, note: note)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AddSavingsGoalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var vm: SavingsViewModel

    @State private var name = ""
    @State private var amountText = ""

    var body: some View {
        Form {
            TextField("Goal name", text: $name)
            TextField("Target amount", text: $amountText).keyboardType(.decimalPad)
        }
        .navigationTitle("Add Goal")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let target = ExpenseTextParser.decimal(from: amountText) else { return }
                    let priority = vm.state.goals.count
                    Task {
                        await vm.addGoal(name: name, targetAmount: target, priority: priority)
                        dismiss()
                    }
                }
            }
        }
    }
}

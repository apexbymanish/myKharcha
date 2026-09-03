import SwiftUI
import KharchaKit

/// The 3-way Type filter, shared between `HistoryView`'s controls row and
/// this sheet's Type section — a friendlier segmented-control surface over
/// `HistoryViewModel`'s optional `TxnKind?` filter.
enum TxnKindFilter: Hashable {
    case all, expense, income
}

/// Single sheet combining Type, Category, and Date range — replaces the old
/// toolbar filter menu plus the separate filter-chip and month/year scrollers
/// that used to sit inline in the History list.
struct FiltersSheetView: View {
    @ObservedObject var vm: HistoryViewModel
    @Binding var selectedYear: Int?
    @Binding var selectedMonth: Date?
    let availableYears: [Int]
    let availableMonths: [Date]
    let resultsCount: Int
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var kindFilterBinding: Binding<TxnKindFilter> {
        Binding(
            get: {
                switch vm.state.filterKind {
                case .expense: return .expense
                case .income: return .income
                case nil: return .all
                }
            },
            set: { newValue in
                Task {
                    switch newValue {
                    case .all: await vm.setKindFilter(nil)
                    case .expense: await vm.setKindFilter(.expense)
                    case .income: await vm.setKindFilter(.income)
                    }
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    typeSection
                    categorySection
                    dateRangeSection
                }
                .padding(16)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { onReset() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        Text(resultsCount == 1 ? "Show 1 result" : "Show \(resultsCount) results")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandPrimary)

                    Button("Clear all filters", action: onReset)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Type

    @ViewBuilder private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Type")
            Picker("Type", selection: kindFilterBinding) {
                Text("All").tag(TxnKindFilter.all)
                Text("Expenses").tag(TxnKindFilter.expense)
                Text("Income").tag(TxnKindFilter.income)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Category

    @ViewBuilder private var categorySection: some View {
        if !vm.state.categories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Category")
                FlowLayout(spacing: 8) {
                    ForEach(vm.state.categories, id: \.id) { cat in
                        let isActive = vm.state.filterCategoryName == cat.name
                        Button {
                            Task {
                                await vm.setCategoryFilter(isActive ? nil : cat.name)
                            }
                        } label: {
                            HStack(spacing: 7) {
                                CategoryIconBadge(symbol: cat.symbol, colorHex: cat.colorHex, size: 24)
                                Text(cat.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isActive ? Color.brandPrimary.opacity(0.12) : Color.secondary.opacity(0.08))
                            .overlay(
                                Capsule().strokeBorder(isActive ? Color.brandPrimary : .clear, lineWidth: 1.5)
                            )
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isActive ? [.isSelected] : [])
                    }
                }
            }
        }
    }

    // MARK: - Date range

    @ViewBuilder private var dateRangeSection: some View {
        if !vm.state.allRows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Date range")

                if availableYears.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            MonthChip(label: String(localized: "All years"), isActive: selectedYear == nil) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedYear = nil; selectedMonth = nil
                                }
                            }
                            ForEach(availableYears, id: \.self) { year in
                                let active = selectedYear == year
                                MonthChip(label: "\(year)", isActive: active) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        if active { selectedYear = nil; selectedMonth = nil }
                                        else      { selectedYear = year; selectedMonth = nil }
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        let allLabel = selectedYear != nil
                            ? String(localized: "All months")
                            : String(localized: "All time")
                        MonthChip(label: allLabel, isActive: selectedMonth == nil) {
                            withAnimation(.easeInOut(duration: 0.18)) { selectedMonth = nil }
                        }
                        ForEach(availableMonths, id: \.self) { month in
                            let isActive = selectedMonth.map {
                                Calendar.current.isDate($0, equalTo: month, toGranularity: .month)
                            } ?? false
                            let chipLabel = (selectedYear != nil || availableYears.count == 1)
                                ? month.formatted(.dateTime.month(.abbreviated))
                                : month.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
                            MonthChip(label: chipLabel, isActive: isActive) {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    if isActive {
                                        selectedMonth = nil
                                    } else {
                                        selectedMonth = month
                                        selectedYear = Calendar.current.component(.year, from: month)
                                        // Move the chart to the picked month so the
                                        // list filter and the chart never disagree.
                                        Task { await vm.setChartAnchor(month) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - Flow layout (wraps chips to new rows instead of truncating them)

/// Lays out subviews left-to-right, wrapping to a new row when one wouldn't
/// fit — used for the category chip grid so each chip sizes itself to its own
/// label instead of a fixed column width that truncates longer names.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Month/year pill (date-range navigation)

private struct MonthChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isActive ? Color.brandPrimary : Color.secondary.opacity(0.1))
                .foregroundStyle(isActive ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .animation(.easeInOut(duration: 0.15), value: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

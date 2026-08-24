import Foundation

/// Lists installments/loans, split into active and finished (closed or fully paid).
@MainActor
public final class InstallmentsViewModel: ObservableObject {
    public struct State: Sendable {
        public var active: [InstallmentSnapshot] = []
        public var finished: [InstallmentSnapshot] = []
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore

    public init(store: ExpenseStore) { self.store = store }

    public func load(now: Date = Date(), calendar: Calendar = .current) async {
        state.errorMessage = nil
        do {
            let all = try await store.installments(now: now, calendar: calendar)
            state.active = all.filter(\.isActive)
            state.finished = all.filter { !$0.isActive }
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func delete(_ id: UUID, now: Date = Date(), calendar: Calendar = .current) async {
        do {
            try await store.deleteInstallment(id: id)
            await load(now: now, calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}

/// Drives one installment's detail: header status, the payment ledger, and the
/// record / pay-off / close / delete-payment actions.
@MainActor
public final class InstallmentDetailViewModel: ObservableObject {
    public struct State: Sendable {
        public var installment: InstallmentSnapshot?
        public var payments: [InstallmentPaymentSnapshot] = []
        public var errorMessage: String?
    }

    @Published public private(set) var state = State()
    private let store: ExpenseStore
    public let installmentID: UUID

    public init(store: ExpenseStore, installmentID: UUID) {
        self.store = store
        self.installmentID = installmentID
    }

    public func load(now: Date = Date(), calendar: Calendar = .current) async {
        state.errorMessage = nil
        do {
            state.installment = try await store.installments(now: now, calendar: calendar).first { $0.id == installmentID }
            state.payments = try await store.installmentPayments(installmentID: installmentID)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    /// Default amount to pre-fill the record sheet with (this month's installment).
    public var suggestedPayment: Decimal { state.installment?.monthlyAmount ?? 0 }

    public func recordPayment(amount: Decimal, date: Date, now: Date = Date(), calendar: Calendar = .current) async {
        do {
            _ = try await store.recordInstallmentPayment(installmentID: installmentID, amount: amount, date: date, now: now, calendar: calendar)
            await load(now: now, calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func payOff(date: Date = Date(), now: Date = Date(), calendar: Calendar = .current) async {
        do {
            _ = try await store.payoffInstallment(installmentID: installmentID, date: date, now: now, calendar: calendar)
            await load(now: now, calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func close(now: Date = Date(), calendar: Calendar = .current) async {
        do {
            _ = try await store.closeInstallment(installmentID: installmentID, now: now, calendar: calendar)
            await load(now: now, calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }

    public func deletePayment(_ id: UUID, now: Date = Date(), calendar: Calendar = .current) async {
        do {
            try await store.deleteInstallmentPayment(id: id)
            await load(now: now, calendar: calendar)
        } catch {
            state.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Something went wrong."
        }
    }
}

import Foundation
import FirebaseFirestore
import KharchaKit

/// Local-first Firestore sync under `/users/{uid}/…`. Documents are keyed by the
/// local UUID; amounts are stored as exact-`Decimal` strings and every record
/// carries an `updatedAt` for newest-wins conflict resolution. Deletions are
/// propagated as tombstones so a removed record doesn't resurrect on pull.
struct FirestoreSync {
    let uid: String
    let store: ExpenseStore

    private var user: DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }

    // MARK: Push (local → cloud)

    func pushAll() async throws {
        try await pushCategories()
        try await pushFriends()
        try await pushTxns()
        try await pushDebts()
        try await pushRules()
        try await pushSavingsPots()
        try await pushSavingsEntries()
        try await pushSavingsGoals()
        try await pushInstallments()
        try await pushInstallmentPayments()
        try await pushTombstones()
    }

    private func pushInstallments() async throws {
        let col = user.collection("installments")
        for i in try await store.exportInstallments() {
            try await col.document(i.id.uuidString).setData([
                "name": i.name, "kind": i.kindRaw, "monthlyAmount": "\(i.monthlyAmount)",
                "termCount": i.termCount, "dayOfMonth": i.dayOfMonth,
                "startDate": Timestamp(date: i.startDate),
                "categoryID": i.categoryID?.uuidString ?? NSNull(),
                "remindDaysBefore": i.remindDaysBefore, "autoLog": i.autoLog,
                "recordPrincipalAsIncome": i.recordPrincipalAsIncome,
                "note": i.note ?? NSNull(), "isClosed": i.isClosed,
                "closedDate": i.closedDate.map { Timestamp(date: $0) } ?? NSNull(),
                "updatedAt": Timestamp(date: i.updatedAt)
            ], merge: true)
        }
    }
    private func pushInstallmentPayments() async throws {
        let col = user.collection("installmentPayments")
        for p in try await store.exportInstallmentPayments() {
            try await col.document(p.id.uuidString).setData([
                "installmentID": p.installmentID.uuidString, "amount": "\(p.amount)",
                "date": Timestamp(date: p.date), "note": p.note ?? NSNull(),
                "txnID": p.txnID?.uuidString ?? NSNull(), "updatedAt": Timestamp(date: p.updatedAt)
            ], merge: true)
        }
    }

    private func pushSavingsPots() async throws {
        let col = user.collection("savingsPots")
        for p in try await store.exportSavingsPots() {
            try await col.document(p.id.uuidString).setData([
                "name": p.name, "note": p.note ?? NSNull(), "updatedAt": Timestamp(date: p.updatedAt)
            ], merge: true)
        }
    }
    private func pushSavingsEntries() async throws {
        let col = user.collection("savingsEntries")
        for e in try await store.exportSavingsEntries() {
            try await col.document(e.id.uuidString).setData([
                "potID": e.potID.uuidString, "amount": "\(e.amount)", "note": e.note ?? NSNull(),
                "date": Timestamp(date: e.date), "updatedAt": Timestamp(date: e.updatedAt)
            ], merge: true)
        }
    }
    private func pushSavingsGoals() async throws {
        let col = user.collection("savingsGoals")
        for g in try await store.exportSavingsGoals() {
            try await col.document(g.id.uuidString).setData([
                "name": g.name, "targetAmount": "\(g.targetAmount)", "priority": g.priority,
                "updatedAt": Timestamp(date: g.updatedAt)
            ], merge: true)
        }
    }

    private func pushCategories() async throws {
        let col = user.collection("categories")
        for c in try await store.exportCategories() {
            try await col.document(c.id.uuidString).setData([
                "name": c.name, "symbol": c.symbol, "colorHex": c.colorHex,
                "monthlyBudget": c.monthlyBudget.map { "\($0)" } ?? NSNull(),
                "isFallback": c.isFallback,
                "kind": c.kindRaw,
                "updatedAt": Timestamp(date: c.updatedAt)
            ], merge: true)
        }
    }

    private func pushFriends() async throws {
        let col = user.collection("friends")
        for f in try await store.exportFriends() {
            try await col.document(f.id.uuidString).setData([
                "name": f.name,
                "phone": f.phone ?? NSNull(),
                "updatedAt": Timestamp(date: f.updatedAt)
            ], merge: true)
        }
    }

    private func pushTxns() async throws {
        let col = user.collection("txns")
        for t in try await store.exportTxns() {
            try await col.document(t.id.uuidString).setData([
                "date": Timestamp(date: t.date),
                "kind": t.kind.rawValue,
                "amount": "\(t.amount)",
                "categoryID": t.categoryID?.uuidString ?? NSNull(),
                "note": t.note ?? NSNull(),
                "source": t.source.rawValue,
                "updatedAt": Timestamp(date: t.updatedAt)
            ], merge: true)
        }
    }

    private func pushDebts() async throws {
        let col = user.collection("debts")
        for d in try await store.exportDebts() {
            try await col.document(d.id.uuidString).setData([
                "friendID": d.friendID?.uuidString ?? NSNull(),
                "amount": "\(d.amount)",
                "direction": d.direction == .iGave ? "iGave" : "iTook",
                "date": Timestamp(date: d.date),
                "note": d.note ?? NSNull(),
                "dueDate": d.dueDate.map { Timestamp(date: $0) } ?? NSNull(),
                "settledAmount": "\(d.settledAmount)",
                "settled": d.settled,
                "updatedAt": Timestamp(date: d.updatedAt)
            ], merge: true)
        }
    }

    private func pushRules() async throws {
        let col = user.collection("rules")
        for r in try await store.exportRules() {
            try await col.document(r.id.uuidString).setData([
                "name": r.name,
                "amount": "\(r.amount)",
                "categoryID": r.categoryID?.uuidString ?? NSNull(),
                "dayOfMonth": r.dayOfMonth,
                "remindDaysBefore": r.remindDaysBefore,
                "autoLog": r.autoLog,
                "updatedAt": Timestamp(date: r.updatedAt)
            ], merge: true)
        }
    }

    /// Write each tombstone and delete the corresponding data document.
    private func pushTombstones() async throws {
        let tombs = user.collection("tombstones")
        for t in try await store.exportTombstones() {
            try await tombs.document(t.id.uuidString).setData([
                "collection": t.collection,
                "deletedAt": Timestamp(date: t.deletedAt)
            ], merge: true)
            try? await user.collection(t.collection).document(t.id.uuidString).delete()
        }
    }

    // MARK: Pull (cloud → local). Tombstones first, then data (upserts respect them).

    func pullAll() async throws {
        try await pullTombstones()
        try await pullCategories()
        try await pullFriends()
        try await pullTxns()
        try await pullDebts()
        try await pullRules()
        try await pullSavingsPots()
        try await pullSavingsEntries()
        try await pullSavingsGoals()
        try await pullInstallments()
        try await pullInstallmentPayments()
    }

    private func pullInstallments() async throws {
        for doc in try await user.collection("installments").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            guard let monthly = (d["monthlyAmount"] as? String).flatMap({ Decimal(string: $0) }),
                  let startDate = (d["startDate"] as? Timestamp)?.dateValue() else { continue }
            try await store.upsertInstallment(
                id: id,
                name: d["name"] as? String ?? "",
                kindRaw: d["kind"] as? String ?? "purchase",
                monthlyAmount: monthly,
                termCount: d["termCount"] as? Int ?? 1,
                dayOfMonth: d["dayOfMonth"] as? Int ?? 1,
                startDate: startDate,
                categoryID: (d["categoryID"] as? String).flatMap { UUID(uuidString: $0) },
                remindDaysBefore: d["remindDaysBefore"] as? Int ?? 3,
                autoLog: d["autoLog"] as? Bool ?? false,
                recordPrincipalAsIncome: d["recordPrincipalAsIncome"] as? Bool ?? false,
                note: d["note"] as? String,
                isClosed: d["isClosed"] as? Bool ?? false,
                closedDate: (d["closedDate"] as? Timestamp)?.dateValue(),
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            )
        }
    }
    private func pullInstallmentPayments() async throws {
        for doc in try await user.collection("installmentPayments").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            guard let installmentID = (d["installmentID"] as? String).flatMap({ UUID(uuidString: $0) }),
                  let amount = (d["amount"] as? String).flatMap({ Decimal(string: $0) }),
                  let date = (d["date"] as? Timestamp)?.dateValue() else { continue }
            try await store.upsertInstallmentPayment(
                id: id, installmentID: installmentID, amount: amount, date: date,
                note: d["note"] as? String, txnID: (d["txnID"] as? String).flatMap { UUID(uuidString: $0) },
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            )
        }
    }

    private func pullSavingsPots() async throws {
        for doc in try await user.collection("savingsPots").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            try await store.upsertSavingsPot(
                id: id,
                name: d["name"] as? String ?? "",
                note: d["note"] as? String,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            )
        }
    }
    private func pullSavingsEntries() async throws {
        for doc in try await user.collection("savingsEntries").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            guard let potID = (d["potID"] as? String).flatMap({ UUID(uuidString: $0) }),
                  let amount = (d["amount"] as? String).flatMap({ Decimal(string: $0) }),
                  let date = (d["date"] as? Timestamp)?.dateValue() else { continue }
            try await store.upsertSavingsEntry(
                id: id, potID: potID, amount: amount, note: d["note"] as? String, date: date,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            )
        }
    }
    private func pullSavingsGoals() async throws {
        for doc in try await user.collection("savingsGoals").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            guard let target = (d["targetAmount"] as? String).flatMap({ Decimal(string: $0) }) else { continue }
            try await store.upsertSavingsGoal(
                id: id, name: d["name"] as? String ?? "", targetAmount: target,
                priority: d["priority"] as? Int ?? 0,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            )
        }
    }

    private func pullTombstones() async throws {
        for doc in try await user.collection("tombstones").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            guard let collection = d["collection"] as? String,
                  let deletedAt = (d["deletedAt"] as? Timestamp)?.dateValue() else { continue }
            try await store.applyRemoteTombstone(id: id, collection: collection, deletedAt: deletedAt)
        }
    }

    private func pullCategories() async throws {
        for doc in try await user.collection("categories").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            try await store.upsertCategory(
                id: id,
                name: d["name"] as? String ?? "",
                symbol: d["symbol"] as? String ?? "tag",
                colorHex: d["colorHex"] as? String ?? "#9A9A9A",
                monthlyBudget: (d["monthlyBudget"] as? String).flatMap { Decimal(string: $0) },
                isFallback: d["isFallback"] as? Bool ?? false,
                kindRaw: d["kind"] as? String ?? "expense",
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            )
        }
    }

    private func pullFriends() async throws {
        for doc in try await user.collection("friends").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            try await store.upsertFriend(
                id: id,
                name: d["name"] as? String ?? "",
                phone: d["phone"] as? String,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            )
        }
    }

    private func pullTxns() async throws {
        for doc in try await user.collection("txns").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            guard let amount = (d["amount"] as? String).flatMap({ Decimal(string: $0) }),
                  let date = (d["date"] as? Timestamp)?.dateValue() else { continue }
            try await store.upsertTxn(
                id: id,
                amount: amount,
                kind: TxnKind(rawValue: d["kind"] as? String ?? "") ?? .expense,
                categoryID: (d["categoryID"] as? String).flatMap { UUID(uuidString: $0) },
                note: d["note"] as? String,
                date: date,
                source: TxnSource(rawValue: d["source"] as? String ?? "") ?? .manual,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            )
        }
    }

    private func pullDebts() async throws {
        for doc in try await user.collection("debts").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            guard let amount = (d["amount"] as? String).flatMap({ Decimal(string: $0) }),
                  let date = (d["date"] as? Timestamp)?.dateValue() else { continue }
            try await store.upsertDebt(DebtExport(
                id: id,
                friendID: (d["friendID"] as? String).flatMap { UUID(uuidString: $0) },
                amount: amount,
                direction: (d["direction"] as? String) == "iTook" ? .iTook : .iGave,
                date: date,
                note: d["note"] as? String,
                dueDate: (d["dueDate"] as? Timestamp)?.dateValue(),
                settledAmount: (d["settledAmount"] as? String).flatMap { Decimal(string: $0) } ?? 0,
                settled: d["settled"] as? Bool ?? false,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            ))
        }
    }

    private func pullRules() async throws {
        for doc in try await user.collection("rules").getDocuments().documents {
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            let d = doc.data()
            guard let amount = (d["amount"] as? String).flatMap({ Decimal(string: $0) }) else { continue }
            try await store.upsertRule(
                id: id,
                name: d["name"] as? String ?? "",
                amount: amount,
                categoryID: (d["categoryID"] as? String).flatMap { UUID(uuidString: $0) },
                dayOfMonth: d["dayOfMonth"] as? Int ?? 1,
                remindDaysBefore: d["remindDaysBefore"] as? Int ?? 0,
                autoLog: d["autoLog"] as? Bool ?? false,
                updatedAt: (d["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            )
        }
    }
}

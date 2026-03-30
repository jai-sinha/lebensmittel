//
//  SyncEngine.swift
//  lebensmittel
//
//  Created by Jai Sinha on 10/15/25.
//

import Foundation
import SwiftData

// MARK: - Notification Name

extension Notification.Name {
    static let syncEngineDidFinish = Notification.Name("syncEngineDidFinish")
}

// MARK: - SyncEngine

/// Owns all writes to SwiftData and all outbound network sync.
/// Feature models call the enqueueXxx methods; SyncEngine handles persistence,
/// the durable operation queue, conflict resolution, ID remapping, and retries.
///

@MainActor
final class SyncEngine {

    static let shared = SyncEngine()

    /// Set to true to enable verbose logging — mirrors SocketService.verbose.
    static var verbose = false

    private var modelContext: ModelContext?
    private let networkClient = NetworkClient()
    private var isSyncing = false

    private init() {}

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        log("Configured")
    }

    // MARK: - Sync Trigger

    func syncIfNeeded() {
        guard !isSyncing else {
            log("Already syncing, skipping")
            return
        }
        guard ConnectivityMonitor.shared.isOnline else {
            log("Offline, skipping")
            return
        }
        Task {
            await drainQueue()
        }
    }

    // MARK: - Queue Drain

    private func drainQueue() async {
        guard let context = modelContext else { return }
        isSyncing = true
        defer { isSyncing = false }

        let descriptor = FetchDescriptor<SyncOperation>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        guard let ops = try? context.fetch(descriptor) else {
            log("Failed to fetch pending operations")
            return
        }
        guard !ops.isEmpty else {
            log("Queue empty")
            postFinished()
            return
        }

        log("Processing \(ops.count) operation(s)")

        for op in ops {
            if op.retryCount >= 3 {
                log("Operation \(op.id) hit max retries — discarding")
                context.delete(op)
                try? context.save()
                continue
            }

            do {
                try await process(op)
                context.delete(op)
                try? context.save()
                log("✓ \(op.entityType.rawValue) \(op.operationType.rawValue) \(op.id)")
            } catch {
                op.retryCount += 1
                op.lastError = error.localizedDescription
                try? context.save()
                log("✗ \(op.entityType.rawValue) \(op.operationType.rawValue) — \(error.localizedDescription). Retry \(op.retryCount)/3. Stopping.")
                return
            }
        }

        postFinished()
    }

    private func postFinished() {
        log("Sync complete — posting syncEngineDidFinish")
        NotificationCenter.default.post(name: .syncEngineDidFinish, object: nil)
    }

    // MARK: - Operation Processing

    private func process(_ op: SyncOperation) async throws {
        switch op.operationType {
        case .create: try await processCreate(op)
        case .update: try await processUpdate(op)
        case .delete: try await processDelete(op)
        }
    }

    private func processCreate(_ op: SyncOperation) async throws {
        guard let context = modelContext else { return }

        // For grocery and meal creates, regenerate the payload from the current local
        // entity so any field edits made while the item was .pendingCreate are captured.
        // For receipt creates the stored payload is used intentionally — it carries the
        // items snapshot that was captured at creation time and cannot be regenerated.
        let payload: Data
        switch op.entityType {
        case .grocery:
            if let local = findLocalGroceryItem(byLocalID: op.localID) {
                payload = (try? JSONEncoder().encode(
                    NewGroceryItem(
                        name: local.name, category: local.category,
                        isNeeded: local.isNeeded, isShoppingChecked: local.isShoppingChecked
                    )
                )) ?? op.payload
            } else {
                payload = op.payload
            }
        case .meal:
            if let local = findLocalMealPlan(byLocalID: op.localID) {
                payload = (try? JSONEncoder().encode(
                    NewMealPlan(date: local.date, mealDescription: local.mealDescription)
                )) ?? op.payload
            } else {
                payload = op.payload
            }
        case .receipt:
            payload = op.payload
        }

        var request = URLRequest(url: try entityURL(op.entityType))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let (data, response) = try await networkClient.send(request)
        try assertSuccess(response)

        // Parse server-assigned ID and remap into local entity + any later queued ops.
        let serverID: String
        switch op.entityType {
        case .grocery:
            serverID = try JSONDecoder().decode(GroceryItem.self, from: data).id
            findLocalGroceryItem(byLocalID: op.localID).map {
                $0.serverID = serverID
                $0.syncStatus = .synced
            }
        case .meal:
            serverID = try JSONDecoder().decode(MealPlan.self, from: data).id
            findLocalMealPlan(byLocalID: op.localID).map {
                $0.serverID = serverID
                $0.syncStatus = .synced
            }
        case .receipt:
            serverID = try JSONDecoder().decode(Receipt.self, from: data).id
            findLocalReceipt(byLocalID: op.localID).map {
                $0.serverID = serverID
                $0.syncStatus = .synced
            }
        }

        // Backfill serverID into later ops for the same local entity so they
        // can reference the correct server resource once the create has landed.
        fetchOps(for: op.localID, after: op.createdAt).forEach { $0.serverID = serverID }

        try? context.save()
    }

    private func processUpdate(_ op: SyncOperation) async throws {
        guard let context = modelContext else { return }
        guard let serverID = op.serverID else { throw SyncError.missingServerID }

        // GET current server state for conflict detection using the list endpoint,
        // then find the matching item in memory. The datasets are small enough that
        // fetching the full list is cheaper than adding new single-item GET endpoints.
        var getReq = URLRequest(url: try entityURL(op.entityType))
        getReq.httpMethod = "GET"
        let (listData, getResp) = try await networkClient.send(getReq)
        try assertSuccess(getResp)

        let serverData = try extractItem(
            entityType: op.entityType,
            serverID: serverID,
            from: listData
        )

        // Item is gone from the server — deleted by another client while we were offline.
        // Server wins: discard the local update and remove our local copy.
        guard let currentData = serverData else {
            log("Update target \(op.entityType.rawValue)/\(serverID) no longer exists on server — discarding local change (server wins)")
            deleteLocalEntity(entityType: op.entityType, localID: op.localID)
            try? context.save()
            return // op deleted by drainQueue on the success path
        }

        if let snapshot = op.baseSnapshot,
           (try? hasConflict(entityType: op.entityType, serverData: currentData, snapshot: snapshot)) == true {
            log("Conflict on \(op.entityType.rawValue)/\(serverID) — discarding local change (server wins)")
            applyServerState(currentData, entityType: op.entityType, serverID: serverID)
            try? context.save()
            return // op deleted by drainQueue on the success path
        }

        var patchReq = URLRequest(url: try entityURL(op.entityType, id: serverID))
        patchReq.httpMethod = "PATCH"
        patchReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        patchReq.httpBody = op.payload
        let (_, patchResp) = try await networkClient.send(patchReq)
        try assertSuccess(patchResp)

        markSynced(entityType: op.entityType, serverID: serverID)
        try? context.save()
    }

    private func processDelete(_ op: SyncOperation) async throws {
        guard let context = modelContext else { return }

        // Item was never synced — nothing on the server to delete.
        guard let serverID = op.serverID else {
            deleteLocalEntity(entityType: op.entityType, localID: op.localID)
            try? context.save()
            return
        }

        var req = URLRequest(url: try entityURL(op.entityType, id: serverID))
        req.httpMethod = "DELETE"
        let (_, resp) = try await networkClient.send(req)
        try assertSuccess(resp)

        deleteLocalEntity(entityType: op.entityType, localID: op.localID)
        try? context.save()
    }

    // MARK: - Conflict Detection

    private func hasConflict(
        entityType: SyncEntityType,
        serverData: Data,
        snapshot: Data
    ) throws -> Bool {
        switch entityType {
        case .grocery:
            let s = try JSONDecoder().decode(GroceryItem.self, from: serverData)
            let b = try JSONDecoder().decode(GroceryItem.self, from: snapshot)
            return s.name != b.name
                || s.category != b.category
                || s.isNeeded != b.isNeeded
                || s.isShoppingChecked != b.isShoppingChecked
        case .meal:
            let s = try JSONDecoder().decode(MealPlan.self, from: serverData)
            let b = try JSONDecoder().decode(MealPlan.self, from: snapshot)
            return s.mealDescription != b.mealDescription
        case .receipt:
            let s = try JSONDecoder().decode(Receipt.self, from: serverData)
            let b = try JSONDecoder().decode(Receipt.self, from: snapshot)
            return s.totalAmount != b.totalAmount
                || s.purchasedBy != b.purchasedBy
                || s.notes != b.notes
        }
    }

    // MARK: - Enqueue: Groceries

    @discardableResult
    func enqueueGroceryCreate(name: String, category: String) -> GroceryItem {
        let local = LocalGroceryItem(name: name, category: category)
        insertCreate(
            local,
            entityType: .grocery,
            localID: local.localID,
            encodable: NewGroceryItem(name: name, category: category)
        )
        return local.toGroceryItem()
    }

    /// `isNeeded` and `isShoppingChecked` are the desired final values.
    /// The caller (GroceriesModel) is responsible for deriving them from its
    /// GroceryItemField enum (e.g. setting isShoppingChecked = false when
    /// isNeeded is being toggled, matching the current backend behaviour).
    @discardableResult
    func enqueueGroceryUpdate(
        itemID: String,
        isNeeded: Bool,
        isShoppingChecked: Bool,
        snapshot: GroceryItem
    ) -> GroceryItem? {
        guard let local = findLocalGroceryItem(byModelID: itemID) else { return nil }

        local.isNeeded = isNeeded
        local.isShoppingChecked = isShoppingChecked

        if local.syncStatus == .pendingCreate {
            // Pending-create: just update local fields. processCreate regenerates
            // the payload from the current entity state at sync time.
            try? modelContext?.save()
        } else {
            local.syncStatus = .pendingUpdate
            upsertUpdateOp(
                for: local.localID,
                serverID: local.serverID,
                entityType: .grocery,
                payloadDict: ["isNeeded": isNeeded, "isShoppingChecked": isShoppingChecked],
                snapshot: snapshot
            )
        }
        return local.toGroceryItem()
    }

    func enqueueGroceryDelete(itemID: String) {
        guard let local = findLocalGroceryItem(byModelID: itemID),
              let context = modelContext else { return }

        if local.syncStatus == .pendingCreate {
            cancelOps(for: local.localID)
            context.delete(local)
        } else {
            local.syncStatus = .pendingDelete
            context.insert(SyncOperation(
                entityType: .grocery,
                operationType: .delete,
                payload: Data(),
                localID: local.localID,
                serverID: local.serverID
            ))
        }
        persist()
    }

    // MARK: - Enqueue: Meals

    @discardableResult
    func enqueueMealCreate(date: String, mealDescription: String) -> MealPlan {
        let local = LocalMealPlan(date: date, mealDescription: mealDescription)
        insertCreate(
            local,
            entityType: .meal,
            localID: local.localID,
            encodable: NewMealPlan(date: date, mealDescription: mealDescription)
        )
        return local.toMealPlan()
    }

    @discardableResult
    func enqueueMealUpdate(
        mealID: String,
        mealDescription: String,
        snapshot: MealPlan
    ) -> MealPlan? {
        guard let local = findLocalMealPlan(byModelID: mealID) else { return nil }

        local.mealDescription = mealDescription

        if local.syncStatus == .pendingCreate {
            // Pending-create: just update local fields. processCreate regenerates
            // the payload from the current entity state at sync time.
            try? modelContext?.save()
        } else {
            local.syncStatus = .pendingUpdate
            upsertUpdateOp(
                for: local.localID,
                serverID: local.serverID,
                entityType: .meal,
                payloadDict: ["mealDescription": mealDescription],
                snapshot: snapshot
            )
        }
        return local.toMealPlan()
    }

    func enqueueMealDelete(mealID: String) {
        guard let local = findLocalMealPlan(byModelID: mealID),
              let context = modelContext else { return }

        if local.syncStatus == .pendingCreate {
            cancelOps(for: local.localID)
            context.delete(local)
        } else {
            local.syncStatus = .pendingDelete
            context.insert(SyncOperation(
                entityType: .meal,
                operationType: .delete,
                payload: Data(),
                localID: local.localID,
                serverID: local.serverID
            ))
        }
        persist()
    }

    // MARK: - Enqueue: Receipts

    /// Replicates the server's receipt-creation transaction locally:
    /// snapshots the checked items, creates the receipt, resets grocery flags.
    /// A single SyncOperation with the explicit items list is enqueued;
    /// no separate PATCH ops are created for the grocery flag resets — the
    /// server performs those atomically as part of the receipt create transaction.
    @discardableResult
    func enqueueReceiptCreate(
        date: String,
        totalAmount: Double,
        purchasedBy: String,
        notes: String?,
        checkedItems: [GroceryItem]
    ) -> Receipt {
        guard let context = modelContext else {
            return Receipt(
                id: UUID().uuidString, date: date,
                totalAmount: totalAmount, purchasedBy: purchasedBy,
                items: [], notes: notes
            )
        }

        let itemNames = checkedItems.map { $0.name }

        let local = LocalReceipt(
            date: date, totalAmount: totalAmount,
            purchasedBy: purchasedBy, items: itemNames, notes: notes
        )
        context.insert(local)

        // Reset grocery flags locally. syncStatus is left unchanged — no separate
        // PATCH is needed because the receipt-create payload carries the items list
        // and the server resets the flags atomically in the same transaction.
        for item in checkedItems {
            findLocalGroceryItem(byModelID: item.id).map {
                $0.isNeeded = false
                $0.isShoppingChecked = false
            }
        }

        // Payload includes explicit items list (requires backend change to POST /api/receipts).
        struct ReceiptCreatePayload: Encodable {
            let date: String
            let totalAmount: Double
            let purchasedBy: String
            let notes: String?
            let items: [String]
        }
        let payload = (try? JSONEncoder().encode(
            ReceiptCreatePayload(
                date: date, totalAmount: totalAmount,
                purchasedBy: purchasedBy, notes: notes, items: itemNames
            )
        )) ?? Data()

        context.insert(SyncOperation(
            entityType: .receipt,
            operationType: .create,
            payload: payload,
            localID: local.localID
        ))
        persist()
        return local.toReceipt()
    }

    @discardableResult
    func enqueueReceiptUpdate(
        receiptID: String,
        totalAmount: Double,
        purchasedBy: String,
        notes: String,
        snapshot: Receipt
    ) -> Receipt? {
        guard let local = findLocalReceipt(byModelID: receiptID) else { return nil }

        local.totalAmount = totalAmount
        local.purchasedBy = purchasedBy
        local.notes = notes

        if local.syncStatus == .pendingCreate {
            try? modelContext?.save()
        } else {
            local.syncStatus = .pendingUpdate
            upsertUpdateOp(
                for: local.localID,
                serverID: local.serverID,
                entityType: .receipt,
                payloadDict: [
                    "totalAmount": totalAmount,
                    "purchasedBy": purchasedBy,
                    "notes": notes
                ],
                snapshot: snapshot
            )
        }
        return local.toReceipt()
    }

    func enqueueReceiptDelete(receiptID: String) {
        guard let local = findLocalReceipt(byModelID: receiptID),
              let context = modelContext else { return }

        if local.syncStatus == .pendingCreate {
            cancelOps(for: local.localID)
            context.delete(local)
        } else {
            local.syncStatus = .pendingDelete
            context.insert(SyncOperation(
                entityType: .receipt,
                operationType: .delete,
                payload: Data(),
                localID: local.localID,
                serverID: local.serverID
            ))
        }
        persist()
    }

    // MARK: - Merge (online fetch → upsert into SwiftData → return refreshed array)

    @discardableResult
    func mergeGroceries(_ serverItems: [GroceryItem]) -> [GroceryItem] {
        guard let context = modelContext else { return serverItems }
        for item in serverItems {
            if let local = findLocalGroceryItem(byServerID: item.id) {
                if local.syncStatus == .synced { local.applyServerValues(item) }
                // else: pending local change — skip; server wins after next sync
            } else {
                context.insert(LocalGroceryItem(
                    serverID: item.id, syncStatus: .synced,
                    name: item.name, category: item.category,
                    isNeeded: item.isNeeded, isShoppingChecked: item.isShoppingChecked
                ))
            }
        }
        try? context.save()
        return loadAllGroceryItems()
    }

    @discardableResult
    func mergeMealPlans(_ serverPlans: [MealPlan]) -> [MealPlan] {
        guard let context = modelContext else { return serverPlans }
        for plan in serverPlans {
            if let local = findLocalMealPlan(byServerID: plan.id) {
                if local.syncStatus == .synced { local.applyServerValues(plan) }
            } else {
                context.insert(LocalMealPlan(
                    serverID: plan.id, syncStatus: .synced,
                    date: plan.date, mealDescription: plan.mealDescription
                ))
            }
        }
        try? context.save()
        return loadAllMealPlans()
    }

    @discardableResult
    func mergeReceipts(_ serverReceipts: [Receipt]) -> [Receipt] {
        guard let context = modelContext else { return serverReceipts }
        for receipt in serverReceipts {
            if let local = findLocalReceipt(byServerID: receipt.id) {
                if local.syncStatus == .synced { local.applyServerValues(receipt) }
            } else {
                context.insert(LocalReceipt(
                    serverID: receipt.id, syncStatus: .synced,
                    date: receipt.date, totalAmount: receipt.totalAmount,
                    purchasedBy: receipt.purchasedBy, items: receipt.items, notes: receipt.notes
                ))
            }
        }
        try? context.save()
        return loadAllReceipts()
    }

    // MARK: - Load All (offline read path)

    func loadAllGroceryItems() -> [GroceryItem] {
        guard let context = modelContext else { return [] }
        let all = (try? context.fetch(FetchDescriptor<LocalGroceryItem>())) ?? []
        return all.filter { $0.syncStatus != .pendingDelete }.map { $0.toGroceryItem() }
    }

    func loadAllMealPlans() -> [MealPlan] {
        guard let context = modelContext else { return [] }
        let all = (try? context.fetch(FetchDescriptor<LocalMealPlan>())) ?? []
        return all.filter { $0.syncStatus != .pendingDelete }.map { $0.toMealPlan() }
    }

    func loadAllReceipts() -> [Receipt] {
        guard let context = modelContext else { return [] }
        let all = (try? context.fetch(FetchDescriptor<LocalReceipt>())) ?? []
        return all.filter { $0.syncStatus != .pendingDelete }.map { $0.toReceipt() }
    }

    // MARK: - WebSocket Filter

    /// True when there is at least one pending SyncOperation for the given server ID.
    /// Used by SocketService to skip incoming events for locally-dirty entities.
    func hasPendingOperation(serverID: String) -> Bool {
        guard let context = modelContext else { return false }
        let all = (try? context.fetch(FetchDescriptor<SyncOperation>())) ?? []
        return all.contains { $0.serverID == serverID }
    }

    // MARK: - Logout Cleanup

    func clearLocalData() {
        guard let context = modelContext else { return }
        try? context.delete(model: LocalGroceryItem.self)
        try? context.delete(model: LocalMealPlan.self)
        try? context.delete(model: LocalReceipt.self)
        try? context.delete(model: SyncOperation.self)
        try? context.save()
        log("Local store cleared")
    }

    // MARK: - Private Helpers

    /// Inserts a local entity and its create SyncOperation, then persists and flushes.
    private func insertCreate<T: Encodable>(
        _ local: some PersistentModel,
        entityType: SyncEntityType,
        localID: UUID,
        encodable: T
    ) {
        guard let context = modelContext else { return }
        context.insert(local)
        let payload = (try? JSONEncoder().encode(encodable)) ?? Data()
        context.insert(SyncOperation(
            entityType: entityType,
            operationType: .create,
            payload: payload,
            localID: localID
        ))
        persist()
    }

    /// Creates or replaces the pending update op for a given local entity.
    /// Replacing prevents queue bloat when the user edits an entity multiple times offline.
    private func upsertUpdateOp(
        for localID: UUID,
        serverID: String?,
        entityType: SyncEntityType,
        payloadDict: [String: Any],
        snapshot: some Encodable
    ) {
        guard let context = modelContext else { return }
        let snapshotData = (try? JSONEncoder().encode(snapshot)) ?? Data()
        let payloadData = (try? JSONSerialization.data(withJSONObject: payloadDict)) ?? Data()

        // Fetch all ops for this entity and filter in memory to avoid predicating
        // on the SyncOperationType enum property, which SwiftData stores as Codable.
        let all = (try? context.fetch(FetchDescriptor<SyncOperation>())) ?? []
        let existing = all.first { $0.localID == localID && $0.operationType == .update }

        if let op = existing {
            op.payload = payloadData
            op.baseSnapshot = snapshotData
            op.retryCount = 0
            op.lastError = nil
        } else {
            context.insert(SyncOperation(
                entityType: entityType,
                operationType: .update,
                payload: payloadData,
                baseSnapshot: snapshotData,
                localID: localID,
                serverID: serverID
            ))
        }
        persist()
    }

    /// Deletes all SyncOperations for a given localID (used when purging a pending-create entity).
    private func cancelOps(for localID: UUID) {
        guard let context = modelContext else { return }
        let all = (try? context.fetch(FetchDescriptor<SyncOperation>())) ?? []
        all.filter { $0.localID == localID }.forEach { context.delete($0) }
    }

    private func fetchOps(for localID: UUID, after date: Date) -> [SyncOperation] {
        guard let context = modelContext else { return [] }
        let all = (try? context.fetch(FetchDescriptor<SyncOperation>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))) ?? []
        return all.filter { $0.localID == localID && $0.createdAt > date }
    }

    private func applyServerState(_ data: Data, entityType: SyncEntityType, serverID: String) {
        switch entityType {
        case .grocery:
            if let item = try? JSONDecoder().decode(GroceryItem.self, from: data) {
                findLocalGroceryItem(byServerID: serverID)?.applyServerValues(item)
            }
        case .meal:
            if let plan = try? JSONDecoder().decode(MealPlan.self, from: data) {
                findLocalMealPlan(byServerID: serverID)?.applyServerValues(plan)
            }
        case .receipt:
            if let receipt = try? JSONDecoder().decode(Receipt.self, from: data) {
                findLocalReceipt(byServerID: serverID)?.applyServerValues(receipt)
            }
        }
    }

    private func markSynced(entityType: SyncEntityType, serverID: String) {
        switch entityType {
        case .grocery: findLocalGroceryItem(byServerID: serverID)?.syncStatus = .synced
        case .meal:    findLocalMealPlan(byServerID: serverID)?.syncStatus = .synced
        case .receipt: findLocalReceipt(byServerID: serverID)?.syncStatus = .synced
        }
    }

    private func deleteLocalEntity(entityType: SyncEntityType, localID: UUID) {
        guard let context = modelContext else { return }
        switch entityType {
        case .grocery: findLocalGroceryItem(byLocalID: localID).map { context.delete($0) }
        case .meal:    findLocalMealPlan(byLocalID: localID).map { context.delete($0) }
        case .receipt: findLocalReceipt(byLocalID: localID).map { context.delete($0) }
        }
    }

    /// Saves to SwiftData and immediately attempts a sync if online.
    private func persist() {
        try? modelContext?.save()
        if ConnectivityMonitor.shared.isOnline { syncIfNeeded() }
    }

    // MARK: - URL Helpers

    /// Finds the JSON data for a single entity inside a list-endpoint response body.
    /// Returns nil if the item is not found (e.g. deleted by another client).
    private func extractItem(
        entityType: SyncEntityType,
        serverID: String,
        from listData: Data
    ) throws -> Data? {
        switch entityType {
        case .grocery:
            let response = try JSONDecoder().decode(GroceryItemsResponse.self, from: listData)
            guard let item = response.groceryItems.first(where: { $0.id == serverID }) else { return nil }
            return try JSONEncoder().encode(item)
        case .meal:
            let response = try JSONDecoder().decode(MealPlansResponse.self, from: listData)
            guard let plan = response.mealPlans.first(where: { $0.id == serverID }) else { return nil }
            return try JSONEncoder().encode(plan)
        case .receipt:
            let response = try JSONDecoder().decode(ReceiptsResponse.self, from: listData)
            guard let receipt = response.receipts.first(where: { $0.id == serverID }) else { return nil }
            return try JSONEncoder().encode(receipt)
        }
    }

    private func entityURL(_ entityType: SyncEntityType, id: String? = nil) throws -> URL {
        var s = "https://ls.jsinha.com/api/"
        switch entityType {
        case .grocery: s += "grocery-items"
        case .meal:    s += "meal-plans"
        case .receipt: s += "receipts"
        }
        if let id { s += "/\(id)" }
        guard let url = URL(string: s) else { throw SyncError.invalidURL(s) }
        return url
    }

    private func assertSuccess(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            throw SyncError.serverError((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    // MARK: - Lookups

    private func findLocalGroceryItem(byLocalID id: UUID) -> LocalGroceryItem? {
        guard let ctx = modelContext else { return nil }
        return try? ctx.fetch(
            FetchDescriptor<LocalGroceryItem>(predicate: #Predicate { $0.localID == id })
        ).first
    }

    private func findLocalGroceryItem(byServerID id: String) -> LocalGroceryItem? {
        guard let ctx = modelContext else { return nil }
        let sid: String? = id
        return try? ctx.fetch(
            FetchDescriptor<LocalGroceryItem>(predicate: #Predicate { $0.serverID == sid })
        ).first
    }

    private func findLocalGroceryItem(byModelID id: String) -> LocalGroceryItem? {
        findLocalGroceryItem(byServerID: id)
            ?? UUID(uuidString: id).flatMap { findLocalGroceryItem(byLocalID: $0) }
    }

    private func findLocalMealPlan(byLocalID id: UUID) -> LocalMealPlan? {
        guard let ctx = modelContext else { return nil }
        return try? ctx.fetch(
            FetchDescriptor<LocalMealPlan>(predicate: #Predicate { $0.localID == id })
        ).first
    }

    private func findLocalMealPlan(byServerID id: String) -> LocalMealPlan? {
        guard let ctx = modelContext else { return nil }
        let sid: String? = id
        return try? ctx.fetch(
            FetchDescriptor<LocalMealPlan>(predicate: #Predicate { $0.serverID == sid })
        ).first
    }

    private func findLocalMealPlan(byModelID id: String) -> LocalMealPlan? {
        findLocalMealPlan(byServerID: id)
            ?? UUID(uuidString: id).flatMap { findLocalMealPlan(byLocalID: $0) }
    }

    private func findLocalReceipt(byLocalID id: UUID) -> LocalReceipt? {
        guard let ctx = modelContext else { return nil }
        return try? ctx.fetch(
            FetchDescriptor<LocalReceipt>(predicate: #Predicate { $0.localID == id })
        ).first
    }

    private func findLocalReceipt(byServerID id: String) -> LocalReceipt? {
        guard let ctx = modelContext else { return nil }
        let sid: String? = id
        return try? ctx.fetch(
            FetchDescriptor<LocalReceipt>(predicate: #Predicate { $0.serverID == sid })
        ).first
    }

    private func findLocalReceipt(byModelID id: String) -> LocalReceipt? {
        findLocalReceipt(byServerID: id)
            ?? UUID(uuidString: id).flatMap { findLocalReceipt(byLocalID: $0) }
    }

    private func log(_ msg: String) {
        if Self.verbose { print("[SyncEngine] \(msg)") }
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case invalidURL(String)
    case serverError(Int)
    case missingServerID

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u):  "Invalid URL: \(u)"
        case .serverError(let c): "Server returned HTTP \(c)"
        case .missingServerID:    "Update operation missing server ID"
        }
    }
}

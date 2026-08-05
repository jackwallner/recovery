import Foundation
import SwiftData
import os

/// The App Group SwiftData container, shared by the phone app and the Watch app.
///
/// Only the phone writes: it is the one process with the full HealthKit store
/// and the long history, so it owns the model. Everything else reads, and the
/// widget extensions read the much smaller `RecoverySnapshot` instead of opening
/// this store at all.
@MainActor
public enum DataService {
    public static let appGroupID = rechargeAppGroupID

    public static var sharedModelContainer: ModelContainer = {
        let schema = Schema([WorkoutRecord.self, RecoveryStateRecord.self, DailyContextRecord.self])
        let url = containerURL

        if let container = makeContainer(schema: schema, url: url) {
            return container
        }

        // A schema change or a half-written store leaves the file unusable.
        // Losing the cache costs one re-import from HealthKit, so wiping is
        // strictly better than refusing to launch.
        logger.error("ModelContainer failed to open; deleting the store and retrying")
        for file in [url, url.appendingPathExtension("wal"), url.appendingPathExtension("shm")] {
            try? FileManager.default.removeItem(at: file)
        }
        if let container = makeContainer(schema: schema, url: url) {
            return container
        }

        logger.critical("ModelContainer could not be recreated; falling back to an in-memory store")
        let inMemory = ModelConfiguration("Recharge", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // Force-try is the last resort: an in-memory container with a schema the
        // app itself declares has no remaining failure mode, and there is
        // nothing useful left to fall back to.
        return try! ModelContainer(for: schema, configurations: [inMemory])
    }()

    private static let logger = Logger(subsystem: "com.jackwallner.recharge", category: "DataService")

    private static func makeContainer(schema: Schema, url: URL) -> ModelContainer? {
        let config = ModelConfiguration("Recharge", schema: schema, url: url, cloudKitDatabase: .none)
        return try? ModelContainer(for: schema, configurations: [config])
    }

    private static var containerURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Recharge.store")
    }
}

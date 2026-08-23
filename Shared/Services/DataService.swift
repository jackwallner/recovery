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
        markLocalOnlyStorage()

        if let container = makeContainer(schema: schema, url: url) {
            markLocalOnlyStorage()
            return container
        }

        // A schema change or a half-written store can leave the file unusable.
        // Keep a recoverable copy rather than deleting the user's history. A
        // later migration or support investigation can still inspect it, while
        // HealthKit repopulates a fresh cache for this launch.
        logger.error("ModelContainer failed to open; quarantining the store and retrying")
        quarantinePersistentStore(at: url)
        if let container = makeContainer(schema: schema, url: url) {
            markLocalOnlyStorage()
            return container
        }

        logger.critical("ModelContainer could not be recreated; falling back to an in-memory store")
        let inMemory = ModelConfiguration("Recharge", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // Force-try is the last resort: an in-memory container with a schema the
        // app itself declares has no remaining failure mode, and there is
        // nothing useful left to fall back to.
        return try! ModelContainer(for: schema, configurations: [inMemory])
    }()

    private static let logger = Logger(subsystem: "com.jackwallner.recovery", category: "DataService")

    private static func makeContainer(schema: Schema, url: URL) -> ModelContainer? {
        let config = ModelConfiguration("Recharge", schema: schema, url: url, cloudKitDatabase: .none)
        return try? ModelContainer(for: schema, configurations: [config])
    }

    private static func quarantinePersistentStore(at url: URL) {
        let suffix = ".corrupt-\(UUID().uuidString)"
        let candidates = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
            url.appendingPathExtension("wal"),
            url.appendingPathExtension("shm")
        ]

        for file in candidates where FileManager.default.fileExists(atPath: file.path) {
            let destination = URL(fileURLWithPath: file.path + suffix)
            do {
                try FileManager.default.moveItem(at: file, to: destination)
                markExcludedFromBackup(destination)
                logger.info("Quarantined persistent store component \(file.lastPathComponent, privacy: .private)")
            } catch {
                logger.error("Could not quarantine store component \(file.lastPathComponent, privacy: .private): \(String(describing: error), privacy: .private)")
            }
        }
    }

    private static var containerURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Recharge.store")
    }

    /// Health-derived cache files are local-only. Marking the App Group root
    /// covers SwiftData, UserDefaults, snapshots, and quarantine copies, while
    /// the store components are marked again after every move.
    private static func markLocalOnlyStorage() {
        markExcludedFromBackup(containerURL.deletingLastPathComponent())
        markExcludedFromBackup(containerURL)
        for suffix in ["-wal", "-shm"] {
            markExcludedFromBackup(URL(fileURLWithPath: containerURL.path + suffix))
        }
    }

    private static func markExcludedFromBackup(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var fileURL = url
        try? fileURL.setResourceValues(values)
    }

    /// Removes quarantined copies when the user asks Recharge to delete its
    /// local health cache. The live SwiftData store is cleared through its
    /// context because deleting an open SQLite file is unsafe.
    public static func deleteQuarantinedStores() {
        let directory = containerURL.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.contains("Recharge.store.corrupt-") {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

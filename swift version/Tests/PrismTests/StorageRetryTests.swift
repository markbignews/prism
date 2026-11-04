import Foundation
import CSQLite
import Testing
@testable import Prism

@Suite struct StorageRetryTests {
    @Test func retryBudgetIsFiniteAndDoesNotReplayConflictsOrDiskFailures() throws {
        var attempts = 0
        var sleeps: [TimeInterval] = []
        #expect(throws: SQLiteStore.Failure.self) {
            try StorageWriter.withBusyRetry(sleep: { sleeps.append($0) }) {
                attempts += 1
                throw SQLiteStore.Failure(message: "busy", code: SQLITE_BUSY)
            }
        }
        #expect(attempts == 3 && sleeps == [0.25, 0.75])
        for failure in [SQLiteStore.Failure(message: "conflict", isConflict: true),
                        SQLiteStore.Failure(message: "full", code: SQLITE_FULL),
                        SQLiteStore.Failure(message: "readonly", code: SQLITE_READONLY),
                        SQLiteStore.Failure(message: "io", code: SQLITE_IOERR),
                        SQLiteStore.Failure(message: "statement locked", code: SQLITE_LOCKED)] {
            attempts = 0; sleeps = []
            #expect(throws: SQLiteStore.Failure.self) {
                try StorageWriter.withBusyRetry(sleep: { sleeps.append($0) }) { attempts += 1; throw failure }
            }
            #expect(attempts == 1 && sleeps.isEmpty)
        }
    }

    @Test func aBusyAttemptCanRecoverWithoutUserIntervention() throws {
        var attempts = 0
        let result = try StorageWriter.withBusyRetry(sleep: { _ in }) {
            attempts += 1
            // sqlite3.h's expression macro isn't imported by Swift.
            if attempts == 1 { throw SQLiteStore.Failure(message: "busy snapshot", code: SQLITE_BUSY | (2 << 8)) }
            return "saved"
        }
        #expect(result == "saved" && attempts == 2)
    }
}

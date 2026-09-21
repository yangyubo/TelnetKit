import Darwin
import Foundation
import Testing

import TelnetKit

/// The process's resident memory in bytes, for the connection soak test.
func residentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
        MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}

@Suite("Connection soak")
struct ConnectionSoakTests {
    @Test("hundreds of connect/close cycles leave no active connection and stable memory")
    func connectCloseSoak() async throws {
        let server = try await TestServer.start()
        defer { Task { await server.stop() } }

        func cycle() async throws {
            let connection = try await connectToServer(server)
            try await connection.send(text: "soak\n")
            await connection.close()
        }

        for _ in 0..<10 {
            try await cycle()
        }
        let baseline = residentMemoryBytes()
        for _ in 0..<300 {
            try await cycle()
        }
        let after = residentMemoryBytes()
        let growth = after > baseline ? after - baseline : 0

        #expect(await server.waitForNoActiveConnections(timeout: .seconds(5)))
        #expect(growth < 32 * 1024 * 1024, "resident memory grew by \(growth) bytes over 300 connections")
    }
}

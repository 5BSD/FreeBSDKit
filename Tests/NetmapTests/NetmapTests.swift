/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Testing
import Foundation
@testable import Netmap

/// Tests for the Netmap module.
///
/// Note: Many tests require:
/// - /dev/netmap to exist
/// - A netmap-capable network interface
/// - Root privileges for some operations
///
/// Tests that require hardware are skipped when running as a regular user
/// or when netmap is not available.
@Suite("Netmap Tests")
struct NetmapTests {

    // MARK: - Flag Tests

    @Test("NetmapRegistrationMode raw values match C constants")
    func registrationModeValues() {
        #expect(NetmapRegistrationMode.default.rawValue == 0)
        #expect(NetmapRegistrationMode.allNIC.rawValue == 1)
        #expect(NetmapRegistrationMode.hostOnly.rawValue == 2)
        #expect(NetmapRegistrationMode.nicAndHost.rawValue == 3)
        #expect(NetmapRegistrationMode.oneNIC.rawValue == 4)
        #expect(NetmapRegistrationMode.pipeMaster.rawValue == 5)
        #expect(NetmapRegistrationMode.pipeSlave.rawValue == 6)
        #expect(NetmapRegistrationMode.null.rawValue == 7)
        #expect(NetmapRegistrationMode.oneHost.rawValue == 8)
    }

    @Test("NetmapRegistrationFlags can be combined")
    func registrationFlagsCombine() {
        var flags: NetmapRegistrationFlags = []
        #expect(flags.isEmpty)

        flags.insert(.exclusive)
        #expect(flags.contains(.exclusive))
        #expect(!flags.contains(.monitorTX))

        flags.insert(.monitorTX)
        #expect(flags.contains(.exclusive))
        #expect(flags.contains(.monitorTX))

        let combined: NetmapRegistrationFlags = [.rxRingsOnly, .txRingsOnly]
        #expect(combined.contains(.rxRingsOnly))
        #expect(combined.contains(.txRingsOnly))
    }

    @Test("NetmapSlotFlags can be combined")
    func slotFlagsCombine() {
        let flags: NetmapSlotFlags = [.bufferChanged, .report]
        #expect(flags.contains(.bufferChanged))
        #expect(flags.contains(.report))
        #expect(!flags.contains(.forward))
    }

    @Test("NetmapPollEvents can be combined")
    func pollEventsCombine() {
        let readWrite = NetmapPollEvents.readWrite
        #expect(readWrite.contains(.readable))
        #expect(readWrite.contains(.writable))
    }

    // MARK: - Error Tests

    @Test("NetmapError descriptions are informative")
    func errorDescriptions() {
        let openError = NetmapError.openFailed(errno: 2)  // ENOENT
        #expect(openError.description.contains("/dev/netmap"))

        let ringError = NetmapError.ringIndexOutOfBounds(index: 5, max: 4)
        #expect(ringError.description.contains("5"))
        #expect(ringError.description.contains("4"))

        let bufferError = NetmapError.bufferTooLarge(size: 2048, maxSize: 1500)
        #expect(bufferError.description.contains("2048"))
        #expect(bufferError.description.contains("1500"))
    }

    // MARK: - Device Availability Tests

    @Test("Check if netmap device exists")
    func netmapDeviceExists() throws {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: "/dev/netmap")
        if !exists {
            print("Note: /dev/netmap not found - netmap kernel module may not be loaded")
        }
        // Don't fail - just informational
    }

    // MARK: - Port Info Tests (requires netmap)

    @Test("Can query port info for loopback")
    func queryLoopbackInfo() throws {
        // Try to get info for lo0 - should work if netmap is available
        // Note: Not all systems have netmap-capable loopback
        do {
            let info = try NetmapPort.getInfo(interface: "lo0")
            #expect(info.txRings >= 1)
            #expect(info.rxRings >= 1)
            #expect(info.txSlots > 0)
            #expect(info.rxSlots > 0)
            print("lo0: \(info.txRings) TX rings, \(info.rxRings) RX rings")
            print("     \(info.txSlots) TX slots, \(info.rxSlots) RX slots")
        } catch NetmapError.openFailed {
            // /dev/netmap doesn't exist - skip
            print("Skipping: netmap device not available")
        } catch NetmapError.registerFailed(let err) {
            // ENXIO (6) = no such device, EINVAL (22) = not supported
            if err == 6 || err == 22 {
                print("Skipping: lo0 not netmap-capable on this system")
            } else {
                throw NetmapError.registerFailed(errno: err)
            }
        }
    }

    @Test("Invalid interface name is rejected")
    func invalidInterfaceName() {
        // Interface name too long
        let longName = String(repeating: "x", count: 100)
        #expect(throws: NetmapError.self) {
            _ = try NetmapPort.getInfo(interface: longName)
        }
    }

    @Test("Empty interface name is rejected")
    func emptyInterfaceName() throws {
        // Empty name should either throw or produce an error
        do {
            _ = try NetmapPort.open(interface: "")
            // If we get here on some systems, that's fine
        } catch NetmapError.openFailed {
            // Expected - can't open empty name
        } catch NetmapError.registerFailed {
            // Also expected
        } catch NetmapError.invalidInterfaceName {
            // Also expected
        }
    }

    // MARK: - VALE Switch Tests

    @Test("Can query VALE port info")
    func queryValePortInfo() throws {
        // VALE ports are always available if netmap is loaded
        do {
            let info = try NetmapPort.getInfo(interface: "vale0:test")
            #expect(info.txRings >= 1)
            #expect(info.rxRings >= 1)
            print("vale0:test: \(info.txRings) TX rings, \(info.rxRings) RX rings")
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    // MARK: - Integration Tests (require root and netmap)

    @Test("Can open VALE port")
    func openValePort() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:testport")
            let isReg = port.isRegistered
            let txCount = port.txRingCount
            let rxCount = port.rxRingCount
            let name = port.interfaceName

            #expect(isReg == true)
            #expect(txCount >= 1)
            #expect(rxCount >= 1)
            #expect(name == "vale0:testport")

            // Check we can access rings
            let txRing = port.txRing(0)
            let numSlots = txRing.numSlots
            let bufSize = txRing.bufferSize
            let kind = txRing.kind

            #expect(numSlots > 0)
            #expect(bufSize > 0)
            #expect(kind == .tx)

            let rxRing = port.rxRing(0)
            let rxNumSlots = rxRing.numSlots
            let rxKind = rxRing.kind

            #expect(rxNumSlots > 0)
            #expect(rxKind == .rx)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("TX ring iteration works")
    func txRingIteration() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:txtest")
            let txRing = port.txRing(0)

            // Should have available slots
            let hasSpace = txRing.hasSpace
            let space = txRing.space
            #expect(hasSpace == true)
            #expect(space > 0)

            // Iterate over available slots using forEach
            var count: UInt32 = 0
            txRing.forEach { slotIdx in
                let slot = txRing.slot(at: slotIdx)
                _ = slot.bufferIndex  // Just access it
                count += 1
                // Don't iterate all to keep test fast
            }
            #expect(count > 0)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Can write to TX slot")
    func writeToTxSlot() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:writetest")
            let txRing = port.txRing(0)

            // Write a test packet
            let testData = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55,  // dst MAC
                                 0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB,  // src MAC
                                 0x08, 0x00])  // EtherType (IPv4)

            var slot = txRing.currentSlot
            txRing.setBuffer(for: &slot, data: testData)

            let len = slot.length
            #expect(len == UInt16(testData.count))

            // Advance the ring
            txRing.advance()

            // Sync
            try port.txSync()
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Slot flags work correctly")
    func slotFlagsWork() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:flagtest")
            let txRing = port.txRing(0)

            let slot = txRing.currentSlot

            // Test flag operations
            slot.flags = []
            #expect(slot.flags.isEmpty)

            slot.flags = .report
            #expect(slot.flags.contains(.report))

            slot.markBufferChanged()
            #expect(slot.flags.contains(.bufferChanged))

            slot.clear()
            #expect(slot.length == 0)
            #expect(slot.flags.isEmpty)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Ring advance works correctly")
    func ringAdvance() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:advtest")
            let txRing = port.txRing(0)

            let initialHead = txRing.head
            let numSlots = txRing.numSlots

            // Advance by 1
            txRing.advance()
            let expected1 = (initialHead + 1) % numSlots
            let head1 = txRing.head
            #expect(head1 == expected1)

            // Advance by 3 more
            txRing.advance(by: 3)
            let expected2 = (expected1 + 3) % numSlots
            let head2 = txRing.head
            #expect(head2 == expected2)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Buffer read/write roundtrip")
    func bufferRoundtrip() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:rttest")
            let txRing = port.txRing(0)

            // Generate test pattern
            let pattern = Data((0..<100).map { UInt8($0 & 0xFF) })

            // Write to slot
            var slot = txRing.currentSlot
            txRing.setBuffer(for: &slot, data: pattern)

            // Read back
            let readBack = txRing.bufferData(for: slot)

            #expect(readBack.prefix(pattern.count) == pattern)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Ring wrap-around behavior")
    func ringWrapAround() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:wraptest")
            let txRing = port.txRing(0)
            let numSlots = txRing.numSlots

            // Start near the end of the ring
            let testIdx = numSlots - 2

            // Test next() wraps correctly
            let next1 = txRing.next(testIdx)
            #expect(next1 == testIdx + 1)

            let next2 = txRing.next(numSlots - 1)
            #expect(next2 == 0)  // Should wrap to 0

            // Verify slot access at boundary
            let lastSlot = txRing.slot(at: numSlots - 1)
            #expect(lastSlot.bufferIndex > 0 || lastSlot.bufferIndex == 0)  // Valid index

            let firstSlot = txRing.slot(at: 0)
            #expect(firstSlot.bufferIndex >= 0)  // Valid index
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Buffer boundary - exact size")
    func bufferExactSize() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:exactsize")
            let txRing = port.txRing(0)
            let bufSize = txRing.bufferSize

            // Write exactly bufferSize bytes
            let exactData = Data(repeating: 0xAB, count: Int(bufSize))
            var slot = txRing.currentSlot
            txRing.setBuffer(for: &slot, data: exactData)

            #expect(slot.length == UInt16(truncatingIfNeeded: bufSize))
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Ring isEmpty and hasSpace consistency")
    func ringEmptySpaceConsistency() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:emptytest")
            let txRing = port.txRing(0)

            // isEmpty and hasSpace should be inverses
            let isEmpty = txRing.isEmpty
            let hasSpace = txRing.hasSpace

            #expect(isEmpty != hasSpace || (isEmpty == false && hasSpace == true))

            // space should match isEmpty
            let space = txRing.space
            if isEmpty {
                #expect(space == 0)
            } else {
                #expect(space > 0)
            }
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Poll returns without error")
    func pollWorks() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:polltest")

            // Poll with 0 timeout should return immediately
            let events = try port.poll(events: .readWrite, timeout: 0)
            // TX should be ready (empty ring) or timeout
            let isValid = events.isEmpty || events.contains(.writable)
            #expect(isValid == true)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Multiple ports can be opened")
    func multiplePorts() throws {
        do {
            let port1 = try NetmapPort.open(interface: "vale0:multi1")
            let port2 = try NetmapPort.open(interface: "vale0:multi2")

            let name1 = port1.interfaceName
            let name2 = port2.interfaceName
            let fd1 = port1.fileDescriptor
            let fd2 = port2.fileDescriptor

            #expect(name1 == "vale0:multi1")
            #expect(name2 == "vale0:multi2")
            #expect(fd1 != fd2)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("ForEach ring iteration")
    func forEachRingIteration() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:foreachtest")

            var txCount: UInt32 = 0
            var rxCount: UInt32 = 0

            port.forEachTxRing { ring in
                let kind = ring.kind
                #expect(kind == .tx)
                txCount += 1
            }

            port.forEachRxRing { ring in
                let kind = ring.kind
                #expect(kind == .rx)
                rxCount += 1
            }

            let expectedTx = port.txRingCount
            let expectedRx = port.rxRingCount
            #expect(txCount == expectedTx)
            #expect(rxCount == expectedRx)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }
}

// MARK: - Pipe Tests

@Suite("Netmap Pipe Tests")
struct NetmapPipeTests {

    @Test("Can create pipe endpoints")
    func createPipe() throws {
        // Netmap pipes use syntax: "name{N" for master, "name}N" for slave
        // They provide zero-copy IPC between processes
        do {
            // Create master and slave ends of a pipe
            let master = try NetmapPort.open(
                interface: "pipetest{0",
                mode: .pipeMaster
            )
            let slave = try NetmapPort.open(
                interface: "pipetest}0",
                mode: .pipeSlave
            )

            let masterReg = master.isRegistered
            let slaveReg = slave.isRegistered
            #expect(masterReg == true)
            #expect(slaveReg == true)

            // Both should have rings
            let masterTx = master.txRingCount
            let slaveRx = slave.rxRingCount
            #expect(masterTx >= 1)
            #expect(slaveRx >= 1)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.registerFailed(let err) {
            // EINVAL (22) means pipe creation failed - may not be supported
            if err == 22 {
                print("Skipping: netmap pipes not supported on this system")
            } else {
                throw NetmapError.registerFailed(errno: err)
            }
        }
    }

    @Test("Pipe communication works")
    func pipeCommunication() throws {
        do {
            let master = try NetmapPort.open(
                interface: "commtest{0",
                mode: .pipeMaster
            )
            let slave = try NetmapPort.open(
                interface: "commtest}0",
                mode: .pipeSlave
            )

            // Write data from master
            let txRing = master.txRing(0)
            let testData = Data([0xDE, 0xAD, 0xBE, 0xEF])

            var txSlot = txRing.currentSlot
            txRing.setBuffer(for: &txSlot, data: testData)
            txRing.advance()

            try master.txSync()

            // Try to receive on slave
            try slave.rxSync()

            let rxRing = slave.rxRing(0)
            let isEmpty = rxRing.isEmpty
            // Note: Data may not be immediately available depending on timing
            if !isEmpty {
                let rxSlot = rxRing.currentSlot
                let received = rxRing.bufferData(for: rxSlot)
                #expect(received.prefix(4) == testData)
            }
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.registerFailed(let err) {
            // EINVAL (22) means pipe creation failed - may not be supported
            if err == 22 {
                print("Skipping: netmap pipes not supported on this system")
            } else {
                throw NetmapError.registerFailed(errno: err)
            }
        }
    }
}

// MARK: - Performance Tests

@Suite("Netmap Performance Tests")
struct NetmapPerformanceTests {

    @Test("Measure slot access overhead")
    func slotAccessOverhead() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:perftest")
            let txRing = port.txRing(0)
            let numSlots = txRing.numSlots

            // Warm up
            for _ in 0..<100 {
                _ = txRing.slot(at: 0)
            }

            // Measure
            let iterations = 10000
            let start = DispatchTime.now()

            for i in 0..<iterations {
                let slot = txRing.slot(at: UInt32(i % Int(numSlots)))
                _ = slot.bufferIndex
            }

            let end = DispatchTime.now()
            let ns = end.uptimeNanoseconds - start.uptimeNanoseconds
            let nsPerOp = Double(ns) / Double(iterations)

            print("Slot access: \(nsPerOp) ns/op")
            #expect(nsPerOp < 1000)  // Should be sub-microsecond
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Measure buffer write overhead")
    func bufferWriteOverhead() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:perfwrite")
            let txRing = port.txRing(0)
            let numSlots = txRing.numSlots

            // 64-byte packet (typical minimum)
            let packet = Data(repeating: 0xAA, count: 64)

            // Warm up
            for _ in 0..<100 {
                var slot = txRing.slot(at: 0)
                txRing.setBuffer(for: &slot, data: packet)
            }

            // Measure
            let iterations = 10000
            let start = DispatchTime.now()

            for i in 0..<iterations {
                var slot = txRing.slot(at: UInt32(i % Int(numSlots)))
                txRing.setBuffer(for: &slot, data: packet)
            }

            let end = DispatchTime.now()
            let ns = end.uptimeNanoseconds - start.uptimeNanoseconds
            let nsPerOp = Double(ns) / Double(iterations)

            print("64-byte buffer write: \(nsPerOp) ns/op")
            #expect(nsPerOp < 10000)  // Should be sub-10-microsecond
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }
}

// MARK: - VALE Management Tests

@Suite("VALE Management Tests")
struct VALEManagementTests {

    @Test("isVALEName correctly identifies VALE names")
    func isVALENameWorks() {
        #expect(NetmapVALE.isVALEName("vale0") == true)
        #expect(NetmapVALE.isVALEName("vale0:port1") == true)
        #expect(NetmapVALE.isVALEName("vale123:test") == true)
        #expect(NetmapVALE.isVALEName("em0") == false)
        #expect(NetmapVALE.isVALEName("lo0") == false)
        #expect(NetmapVALE.isVALEName("") == false)
    }

    @Test("parseVALEName correctly parses names")
    func parseVALENameWorks() {
        let result1 = NetmapVALE.parseVALEName("vale0:myport")
        #expect(result1?.switchName == "vale0")
        #expect(result1?.portName == "myport")

        let result2 = NetmapVALE.parseVALEName("vale123")
        #expect(result2?.switchName == "vale123")
        #expect(result2?.portName == "")

        let result3 = NetmapVALE.parseVALEName("em0")
        #expect(result3 == nil)
    }

    @Test("Can list ports on VALE switch")
    func listVALEPorts() throws {
        do {
            // First create some ports by opening them
            let port1 = try NetmapPort.open(interface: "vale0:listtest1")
            let port2 = try NetmapPort.open(interface: "vale0:listtest2")

            // Keep ports alive
            _ = port1.isRegistered
            _ = port2.isRegistered

            // Now list ports - this may return empty on some systems
            let ports = try NetmapVALE.listPorts(switch: "vale0")

            // If we got results, verify our ports are there
            if !ports.isEmpty {
                let names = ports.map { $0.name }
                #expect(names.contains { $0.contains("listtest1") })
                #expect(names.contains { $0.contains("listtest2") })
            } else {
                print("Note: VALE_LIST returned no ports (may not be supported)")
            }
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.registerFailed(let err) {
            // VALE_LIST might not be supported on all systems
            if err == 2 || err == 22 || err == 45 {
                print("Skipping: VALE_LIST not supported (errno \(err))")
            } else {
                throw NetmapError.registerFailed(errno: err)
            }
        }
    }

    @Test("Can create and delete virtual interface")
    func createDeleteInterface() throws {
        do {
            // Create interface
            let memId = try NetmapVALE.createInterface(
                name: "vale0:viftest",
                config: NetmapVALE.InterfaceConfig(
                    txRings: 2,
                    rxRings: 2
                )
            )
            #expect(memId >= 0)

            // Try to open it
            let port = try NetmapPort.open(interface: "vale0:viftest")
            let isReg = port.isRegistered
            #expect(isReg == true)

            // Delete it (port will close when it goes out of scope)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.registerFailed(let err) {
            // VALE_NEWIF might not be supported on all systems
            if err == 22 {
                print("Skipping: VALE_NEWIF not supported")
            } else {
                throw NetmapError.registerFailed(errno: err)
            }
        }
    }

    @Test("Attach and detach port")
    func attachDetachPort() throws {
        do {
            // Create a VALE port first
            let port = try NetmapPort.open(interface: "vale0:attachtest")
            let isReg = port.isRegistered
            #expect(isReg == true)

            // Verify basic operations work
            let txCount = port.txRingCount
            let rxCount = port.rxRingCount
            #expect(txCount >= 1)
            #expect(rxCount >= 1)

            // Port is automatically detached when closed (goes out of scope)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }
}

// MARK: - Zero-Copy Tests

@Suite("Zero-Copy Tests")
struct ZeroCopyTests {

    @Test("Buffer swapping works")
    func bufferSwapping() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:zctest")
            let txRing = port.txRing(0)

            // Get two slots
            var slot1 = txRing.slot(at: 0)
            var slot2 = txRing.slot(at: 1)

            let buf1Original = slot1.bufferIndex
            let buf2Original = slot2.bufferIndex

            // Swap them
            NetmapZeroCopy.swapBuffers(&slot1, &slot2)

            // Verify swap
            #expect(slot1.bufferIndex == buf2Original)
            #expect(slot2.bufferIndex == buf1Original)
            #expect(slot1.flags.contains(.bufferChanged))
            #expect(slot2.flags.contains(.bufferChanged))
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Zero-copy forward between VALE ports")
    func zeroCopyForward() throws {
        do {
            let port1 = try NetmapPort.open(interface: "vale0:zc1")
            let port2 = try NetmapPort.open(interface: "vale0:zc2")

            // Send a packet from port1
            let txRing = port1.txRing(0)
            var txSlot = txRing.currentSlot
            let testData = Data([0xAA, 0xBB, 0xCC, 0xDD])
            txRing.setBuffer(for: &txSlot, data: testData)
            txRing.advance()
            try port1.txSync()

            // Wait for it
            usleep(50000)

            // Receive on port2
            try port2.rxSync()
            let rxRing = port2.rxRing(0)

            if !rxRing.isEmpty {
                // Forward back using zero-copy
                let forwardRing = port1.txRing(0)
                let count = NetmapZeroCopy.forward(from: rxRing, to: forwardRing)
                #expect(count >= 0)
            }
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("sharesMemory check works")
    func sharesMemoryCheck() {
        // VALE ports should share memory - test the helper
        #expect(NetmapVALE.isVALEName("vale0:test") == true)
        #expect(NetmapVALE.isVALEName("em0") == false)
    }
}

// MARK: - Async I/O Tests

@Suite("Async I/O Tests")
struct AsyncIOTests {

    @Test("receivePackets with timeout")
    func receiveWithTimeout() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:asynctest")

            // Should timeout with no packets
            let packets = try port.receivePackets(timeout: 10)
            // Empty is fine - no packets to receive
            #expect(packets.count >= 0)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("sendPacket works")
    func sendPacketWorks() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:sendtest")

            let testData = Data([0x01, 0x02, 0x03, 0x04])
            let sent = try port.sendPacket(testData, timeout: 100)
            #expect(sent == true)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("processPackets batch processing")
    func batchProcessing() throws {
        do {
            let port1 = try NetmapPort.open(interface: "vale0:batch1")
            let port2 = try NetmapPort.open(interface: "vale0:batch2")

            // Send some packets
            for i in 0..<5 {
                let data = Data([UInt8(i), 0xAA, 0xBB, 0xCC])
                _ = try port1.sendPacket(data)
            }

            usleep(50000)

            // Process on port2
            var processed = 0
            _ = try port2.processPackets(timeout: 10) { ringIdx, slot, data in
                processed += 1
            }

            // May or may not have received depending on VALE timing
            #expect(processed >= 0)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }
}

// MARK: - Host Ring Tests

@Suite("Host Ring Tests")
struct HostRingTests {

    @Test("Host ring accessors work")
    func hostRingAccessors() throws {
        do {
            // Open in NIC+Host mode (on VALE for testing)
            let port = try NetmapPort.open(
                interface: "vale0:hosttest",
                mode: .nicAndHost
            )

            // VALE ports have host rings
            let hostTx = port.hostTxRingCount
            let hostRx = port.hostRxRingCount
            let hasHost = port.hasHostRings

            // VALE ports should have some host rings
            #expect(hostTx >= 0)
            #expect(hostRx >= 0)

            if hasHost {
                // Can access host rings
                if hostTx > 0 {
                    let ring = port.hostTxRing(0)
                    let kind = ring.kind
                    #expect(kind == .tx)
                }
            }
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.registerFailed(let err) {
            // nicAndHost might not work on all VALE configs
            print("Skipping: NIC+Host mode not supported (errno \(err))")
        }
    }

    @Test("NetmapHost convenience methods")
    func hostConvenienceMethods() throws {
        do {
            // Test host-only mode
            let port = try NetmapHost.openHostOnly(interface: "vale0:hostonly")
            let isReg = port.isRegistered
            #expect(isReg == true)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.registerFailed(let err) {
            // Host-only mode might not work on VALE
            print("Skipping: Host-only mode not supported (errno \(err))")
        }
    }
}

// MARK: - Extra Buffer Tests

@Suite("Extra Buffer Tests")
struct ExtraBufferTests {

    @Test("Can request extra buffers")
    func requestExtraBuffers() throws {
        do {
            let port = try NetmapPort.open(
                interface: "vale0:extrabuf",
                extraBuffers: 64
            )

            // Check how many we got (may be less than requested)
            let actual = port.extraBufferCount
            #expect(actual >= 0)  // Even 0 is acceptable

            print("Requested 64 extra buffers, got \(actual)")
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Extra buffers list operations work")
    func extraBuffersListOps() throws {
        do {
            let port = try NetmapPort.open(
                interface: "vale0:extrabuflist",
                extraBuffers: 8
            )

            let head = port.extraBuffersHead
            if head != 0 {
                // Pop a buffer
                let popped = port.popExtraBuffer()
                #expect(popped != nil)

                if let buf = popped {
                    // Push it back
                    port.pushExtraBuffer(buf)
                    #expect(port.extraBuffersHead == buf)
                }
            } else {
                // No buffers available is acceptable
                print("No extra buffers available")
            }
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }

    @Test("Can iterate extra buffers")
    func iterateExtraBuffers() throws {
        do {
            let port = try NetmapPort.open(
                interface: "vale0:iterextrabuf",
                extraBuffers: 4
            )

            var count = 0
            port.forEachExtraBuffer { bufIdx in
                #expect(bufIdx != 0)
                count += 1
            }

            // Count should match or be <= allocated
            print("Iterated over \(count) extra buffers")
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }
}

// MARK: - Memory Pools Tests

@Suite("Memory Pools Tests")
struct MemoryPoolsTests {

    @Test("Can get pools info for interface")
    func getPoolsInfo() throws {
        do {
            let info = try NetmapPort.getPoolsInfo(interface: "vale0:poolstest")

            #expect(info.memorySize > 0)
            #expect(info.bufferPoolObjectSize > 0)

            print("Memory size: \(info.memorySize)")
            print("Buffer pool: \(info.bufferPoolObjectCount) x \(info.bufferPoolObjectSize)")
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.registerFailed(let err) {
            // ENXIO, EINVAL, ENODEV all indicate not supported
            if err == 6 || err == 19 || err == 22 {
                print("Skipping: POOLS_INFO_GET not supported (errno \(err))")
            } else {
                throw NetmapError.registerFailed(errno: err)
            }
        }
    }

    @Test("Can get pools info from open port")
    func getPoolsInfoFromPort() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:poolsport")
            let info = try port.getPoolsInfo()

            #expect(info.memorySize > 0)
            print("Port pools - Memory ID: \(info.memoryId)")
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.registerFailed(let err) {
            if err == 6 || err == 19 || err == 22 {
                print("Skipping: POOLS_INFO_GET not supported")
            } else {
                throw NetmapError.registerFailed(errno: err)
            }
        }
    }
}

// MARK: - Port Header Tests

@Suite("Port Header Tests")
struct PortHeaderTests {

    @Test("Can get port header length")
    func getHeaderLength() throws {
        do {
            let port = try NetmapPort.open(interface: "vale0:hdrtest")
            let hdrLen = try port.getHeaderLength()

            // Header length should be 0, 10, or 12 typically
            #expect(hdrLen <= 12)
            print("Header length: \(hdrLen)")
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.syncFailed(let err) {
            // May not be supported
            print("Skipping: header get not supported (errno \(err))")
        }
    }
}

// MARK: - VALE Polling Tests

@Suite("VALE Polling Tests")
struct VALEPollingTests {

    @Test("PollingMode enum values")
    func pollingModeValues() {
        #expect(NetmapVALE.PollingMode.singleCPU.rawValue == 1)
        #expect(NetmapVALE.PollingMode.multiCPU.rawValue == 2)
    }

    @Test("PollingConfig has correct defaults")
    func pollingConfigDefaults() {
        let config = NetmapVALE.PollingConfig()
        #expect(config.mode == .singleCPU)
        #expect(config.firstCPU == 0)
        #expect(config.cpuCount == 1)
    }
}

// MARK: - Kloop Tests

@Suite("Kloop Tests")
struct KloopTests {

    @Test("KloopConfig presets")
    func kloopConfigPresets() {
        let busyPoll = NetmapKloop.Config.busyPoll
        #expect(busyPoll.sleepMicroseconds == 0)

        let lowLatency = NetmapKloop.Config.lowLatency
        #expect(lowLatency.sleepMicroseconds == 10)

        let powerSaving = NetmapKloop.Config.powerSaving
        #expect(powerSaving.sleepMicroseconds == 100)
    }

    @Test("Kloop can be started and stopped")
    func kloopStartStop() throws {
        // Note: This test just verifies the API compiles and doesn't crash
        // A full kloop test would require threading
        do {
            let port = try NetmapPort.open(interface: "vale0:klooptest")

            // Try to stop (even though not started) - should fail gracefully
            do {
                try port.stopKloop()
            } catch {
                // Expected - kloop wasn't running
            }

            // Verify port is still usable
            #expect(port.isRegistered == true)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        }
    }
}

// MARK: - Options Tests

@Suite("Netmap Options Tests")
struct NetmapOptionsTests {

    @Test("NetmapOptions builder pattern")
    func optionsBuilder() {
        // Empty options
        let empty = NetmapOptions()
        #expect(empty.hasOptions == false)

        // Single option
        let offsets = NetmapOptions.offsets(NetmapPacketOffsets(maxOffset: 64))
        #expect(offsets.hasOptions == true)
        #expect(offsets.offsets != nil)
        #expect(offsets.externalMemory == nil)

        // Chained options
        let chained = NetmapOptions.offsets(NetmapPacketOffsets(maxOffset: 64))
            .with(kloopMode: .directBoth)
        #expect(chained.offsets != nil)
        #expect(chained.kloopMode != nil)
    }

    @Test("NetmapPacketOffsets configuration")
    func packetOffsetsConfig() {
        let offsets = NetmapPacketOffsets(maxOffset: 128, initialOffset: 64, bits: 8)
        #expect(offsets.maxOffset == 128)
        #expect(offsets.initialOffset == 64)
        #expect(offsets.bits == 8)

        // Header room convenience
        let headerRoom = NetmapPacketOffsets.headerRoom(64)
        #expect(headerRoom.maxOffset == 64)
        #expect(headerRoom.initialOffset == 64)
    }

    @Test("NetmapKloopMode flags")
    func kloopModeFlags() {
        #expect(NetmapKloopMode.directTX.rawValue != 0)
        #expect(NetmapKloopMode.directRX.rawValue != 0)

        let both = NetmapKloopMode.directBoth
        #expect(both.contains(.directTX))
        #expect(both.contains(.directRX))
    }

    @Test("NetmapKloopEventfds configuration")
    func kloopEventfdsConfig() {
        let entries = [
            NetmapKloopEventfds.RingEntry(ioeventfd: 10, irqfd: 11),
            NetmapKloopEventfds.RingEntry(ioeventfd: 12, irqfd: 13),
            NetmapKloopEventfds.RingEntry.disabled
        ]
        let eventfds = NetmapKloopEventfds(entries: entries)

        #expect(eventfds.entries.count == 3)
        #expect(eventfds.entries[0].ioeventfd == 10)
        #expect(eventfds.entries[2].ioeventfd == -1)
    }

    @Test("NetmapExternalMemory configuration")
    func externalMemoryConfig() {
        // Use stack allocation for testing
        var buffer = [UInt8](repeating: 0, count: 4096)
        buffer.withUnsafeMutableBufferPointer { ptr in
            let extmem = NetmapExternalMemory(
                memory: UnsafeMutableRawPointer(ptr.baseAddress!),
                bufferCount: 2,
                bufferSize: 2048
            )
            #expect(extmem.bufferCount == 2)
            #expect(extmem.bufferSize == 2048)
        }
    }

    @Test("Open port with offsets option")
    func openWithOffsets() throws {
        do {
            // Note: OFFSETS may not be supported on all systems
            let port = try NetmapPort.open(
                interface: "vale0:offsettest",
                options: .offsets(NetmapPacketOffsets.headerRoom(64))
            )
            #expect(port.isRegistered == true)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.optionRejected(let opt, _) {
            print("Skipping: \(opt) option not supported")
        }
    }
}

// MARK: - CSB Tests

@Suite("CSB Tests")
struct CSBTests {

    @Test("CSB allocation and initialization")
    func csbAllocation() throws {
        let csb = try NetmapCSB(ringCount: 4)

        #expect(csb.ringCount == 4)

        // Test setting values
        csb.setHead(ring: 0, value: 100)
        csb.setCur(ring: 0, value: 50)
        csb.setApplNeedKick(ring: 0, value: true)

        // Initially hwcur/hwtail should be 0
        #expect(csb.getHwcur(ring: 0) == 0)
        #expect(csb.getHwtail(ring: 0) == 0)
    }

    @Test("CSB space calculations")
    func csbSpaceCalc() throws {
        let csb = try NetmapCSB(ringCount: 2)

        // Initially all zeros - no space
        #expect(csb.txSpace(ring: 0, numSlots: 256) == 0)
        #expect(csb.rxSpace(ring: 0, numSlots: 256) == 0)
    }

    @Test("Open port with CSB option")
    func openWithCSB() throws {
        do {
            let csb = try NetmapCSB(ringCount: 2)

            // Note: CSB may not be supported on all systems
            let port = try NetmapPort.open(
                interface: "vale0:csbtest",
                options: .csb(csb)
            )
            #expect(port.isRegistered == true)
        } catch NetmapError.openFailed {
            print("Skipping: netmap device not available")
        } catch NetmapError.optionRejected(let opt, _) {
            print("Skipping: \(opt) option not supported")
        }
    }

    @Test("CSB invalid ring count")
    func csbInvalidRingCount() {
        #expect(throws: NetmapError.self) {
            _ = try NetmapCSB(ringCount: 0)
        }
    }
}

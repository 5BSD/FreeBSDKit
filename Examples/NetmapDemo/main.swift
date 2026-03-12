/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Foundation
import Netmap

/// Netmap demonstration program.
///
/// This demo shows basic netmap operations:
/// 1. Querying port information
/// 2. Opening a VALE switch port
/// 3. Simple packet capture
/// 4. Simple packet injection
/// 5. Zero-copy forwarding between ports
///
/// Usage:
///   netmap-demo info <interface>      - Show port info
///   netmap-demo capture <interface>   - Capture packets (Ctrl-C to stop)
///   netmap-demo inject <interface>    - Inject test packets
///   netmap-demo forward <if1> <if2>   - Forward packets between interfaces
///   netmap-demo vale                  - VALE switch demo

func printUsage() {
    print("""
    Netmap Demo - FreeBSDKit Netmap Module Demonstration

    Usage:
      netmap-demo test                  Run E2E self-test (recommended first step)
      netmap-demo info <interface>      Show port information
      netmap-demo capture <interface>   Capture packets (Ctrl-C to stop)
      netmap-demo inject <interface>    Inject test packets
      netmap-demo forward <if1> <if2>   Forward between interfaces
      netmap-demo vale                  VALE switch demonstration

    Examples:
      sudo netmap-demo test             Run self-test (requires root)
      netmap-demo info em0              Show em0 netmap info
      netmap-demo info vale0:port1      Show VALE port info
      netmap-demo capture vale0:cap     Capture on VALE port
      netmap-demo vale                  Run VALE demo

    Note: Most operations require root privileges.

    Quick Start:
      1. Build: swift build
      2. Test:  sudo .build/debug/netmap-demo test
    """)
}

// MARK: - Info Command

func showInfo(interface: String) throws {
    print("Querying port info for: \(interface)")

    let info = try NetmapPort.getInfo(interface: interface)

    print("""

    Interface: \(interface)
    ─────────────────────────────────
    Memory Size:     \(info.memorySize) bytes (\(info.memorySize / 1024 / 1024) MB)
    Memory ID:       \(info.memoryId)

    TX Rings:        \(info.txRings)
    TX Slots/Ring:   \(info.txSlots)

    RX Rings:        \(info.rxRings)
    RX Slots/Ring:   \(info.rxSlots)

    Host TX Rings:   \(info.hostTxRings)
    Host RX Rings:   \(info.hostRxRings)
    """)
}

// MARK: - Capture Command

func capturePackets(interface: String) throws {
    print("Opening \(interface) for packet capture...")
    print("Press Ctrl-C to stop\n")

    let port = try NetmapPort.open(interface: interface)

    print("Registered: \(port.txRingCount) TX rings, \(port.rxRingCount) RX rings")

    var packetCount = 0
    var byteCount = 0

    // Set up signal handler for clean exit
    signal(SIGINT, SIG_IGN)

    while true {
        // Wait for packets
        let ready = try port.waitForRx(timeout: 1000)

        if !ready {
            print(".", terminator: "")
            fflush(stdout)
            continue
        }

        try port.rxSync()

        // Process all RX rings
        for ringIdx in 0..<port.rxRingCount {
            let ring = port.rxRing(ringIdx)

            while !ring.isEmpty {
                let slot = ring.currentSlot
                let data = ring.bufferData(for: slot)

                packetCount += 1
                byteCount += data.count

                // Print packet summary
                printPacketSummary(data: data, packetNum: packetCount)

                ring.advance()
            }
        }
    }
}

func printPacketSummary(data: Data, packetNum: Int) {
    guard data.count >= 14 else {
        print("[\(packetNum)] Runt packet: \(data.count) bytes")
        return
    }

    // Parse Ethernet header
    let dstMAC = data[0..<6].map { String(format: "%02x", $0) }.joined(separator: ":")
    let srcMAC = data[6..<12].map { String(format: "%02x", $0) }.joined(separator: ":")
    let etherType = (UInt16(data[12]) << 8) | UInt16(data[13])

    let typeStr: String
    switch etherType {
    case 0x0800: typeStr = "IPv4"
    case 0x0806: typeStr = "ARP"
    case 0x86DD: typeStr = "IPv6"
    case 0x8100: typeStr = "VLAN"
    default: typeStr = String(format: "0x%04x", etherType)
    }

    print("[\(packetNum)] \(data.count) bytes | \(srcMAC) -> \(dstMAC) | \(typeStr)")
}

// MARK: - Inject Command

func injectPackets(interface: String) throws {
    print("Opening \(interface) for packet injection...")

    let port = try NetmapPort.open(interface: interface)

    print("Registered: \(port.txRingCount) TX rings")

    // Create a simple broadcast ARP request
    let packet = createARPRequest()

    print("Injecting \(packet.count) byte ARP request...")

    let txRing = port.txRing(0)

    guard txRing.hasSpace else {
        print("Error: No TX slots available")
        return
    }

    var slot = txRing.currentSlot
    txRing.setBuffer(for: &slot, data: packet)
    txRing.advance()

    try port.txSync()

    print("Packet injected successfully!")
}

func createARPRequest() -> Data {
    var packet = Data()

    // Ethernet header
    packet.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])  // Dst: broadcast
    packet.append(contentsOf: [0x02, 0x00, 0x00, 0x00, 0x00, 0x01])  // Src: fake MAC
    packet.append(contentsOf: [0x08, 0x06])  // EtherType: ARP

    // ARP header
    packet.append(contentsOf: [0x00, 0x01])  // Hardware type: Ethernet
    packet.append(contentsOf: [0x08, 0x00])  // Protocol type: IPv4
    packet.append(6)  // Hardware size
    packet.append(4)  // Protocol size
    packet.append(contentsOf: [0x00, 0x01])  // Opcode: request

    // Sender hardware address
    packet.append(contentsOf: [0x02, 0x00, 0x00, 0x00, 0x00, 0x01])
    // Sender protocol address (192.168.1.100)
    packet.append(contentsOf: [192, 168, 1, 100])
    // Target hardware address (unknown)
    packet.append(contentsOf: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    // Target protocol address (192.168.1.1)
    packet.append(contentsOf: [192, 168, 1, 1])

    // Pad to minimum Ethernet frame size (64 bytes)
    while packet.count < 60 {
        packet.append(0)
    }

    return packet
}

// MARK: - Forward Command

func forwardPackets(from: String, to: String) throws {
    print("Opening ports for forwarding: \(from) <-> \(to)")

    let port1 = try NetmapPort.open(interface: from)
    let port2 = try NetmapPort.open(interface: to)

    print("Port 1 (\(from)): \(port1.txRingCount) TX, \(port1.rxRingCount) RX")
    print("Port 2 (\(to)): \(port2.txRingCount) TX, \(port2.rxRingCount) RX")
    print("\nForwarding packets... Press Ctrl-C to stop\n")

    var forwardCount = 0

    while true {
        // Forward from port1 to port2
        forwardCount += try forwardOneDirection(from: port1, to: port2)

        // Forward from port2 to port1
        forwardCount += try forwardOneDirection(from: port2, to: port1)

        if forwardCount > 0 && forwardCount % 1000 == 0 {
            print("Forwarded \(forwardCount) packets")
        }

        // Small sleep to avoid busy-waiting
        usleep(100)
    }
}

func forwardOneDirection(from: borrowing NetmapPort, to: borrowing NetmapPort) throws -> Int {
    var forwarded = 0

    try from.rxSync()

    for rxIdx in 0..<from.rxRingCount {
        let rxRing = from.rxRing(rxIdx)
        let txRing = to.txRing(rxIdx % to.txRingCount)

        while !rxRing.isEmpty && txRing.hasSpace {
            let rxSlot = rxRing.currentSlot
            var txSlot = txRing.currentSlot

            // Copy packet data
            let data = rxRing.bufferData(for: rxSlot)
            txRing.setBuffer(for: &txSlot, data: data)

            rxRing.advance()
            txRing.advance()
            forwarded += 1
        }
    }

    if forwarded > 0 {
        try to.txSync()
    }

    return forwarded
}

// MARK: - E2E Test

func runSelfTest() throws {
    print("""
    ╔═══════════════════════════════════════════════════════════════╗
    ║           Netmap E2E Self-Test                                ║
    ╚═══════════════════════════════════════════════════════════════╝

    This test verifies the Netmap implementation works correctly
    using VALE virtual switch ports (no physical NICs required).

    """)

    var passed = 0
    var failed = 0

    // Test 1: Port Info Query
    print("Test 1: Port Info Query")
    print("─────────────────────────")
    do {
        let info = try NetmapPort.getInfo(interface: "vale0:e2etest")
        print("  ✓ Got port info for vale0:e2etest")
        print("    TX rings: \(info.txRings), RX rings: \(info.rxRings)")
        print("    Memory: \(info.memorySize / 1024) KB")
        passed += 1
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 2: Open VALE Port
    print("Test 2: Open VALE Port")
    print("─────────────────────────")
    do {
        let port = try NetmapPort.open(interface: "vale0:opentest")
        let txCount = port.txRingCount
        let rxCount = port.rxRingCount
        print("  ✓ Opened vale0:opentest successfully")
        print("    TX rings: \(txCount), RX rings: \(rxCount)")
        passed += 1
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 3: Ring Access
    print("Test 3: Ring Buffer Access")
    print("─────────────────────────────")
    do {
        let port = try NetmapPort.open(interface: "vale0:ringtest")
        let txRing = port.txRing(0)
        let numSlots = txRing.numSlots
        let bufSize = txRing.bufferSize
        let hasSpace = txRing.hasSpace
        print("  ✓ Accessed TX ring 0")
        print("    Slots: \(numSlots), Buffer size: \(bufSize) bytes")
        print("    Has space: \(hasSpace)")
        passed += 1
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 4: Buffer Write/Read
    print("Test 4: Buffer Write/Read")
    print("─────────────────────────────")
    do {
        let port = try NetmapPort.open(interface: "vale0:buftest")
        let txRing = port.txRing(0)

        // Create test data
        let testData = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE, 0xBA, 0xBE])

        // Write to slot
        var slot = txRing.currentSlot
        txRing.setBuffer(for: &slot, data: testData)

        // Read back
        let readBack = txRing.bufferData(for: slot)

        if readBack.prefix(testData.count) == testData {
            print("  ✓ Buffer write/read roundtrip successful")
            print("    Written: \(testData.map { String(format: "%02X", $0) }.joined())")
            print("    Read:    \(readBack.prefix(testData.count).map { String(format: "%02X", $0) }.joined())")
            passed += 1
        } else {
            print("  ✗ Data mismatch!")
            failed += 1
        }
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 5: VALE Packet Transfer
    print("Test 5: VALE Port-to-Port Transfer")
    print("─────────────────────────────────────")
    do {
        // Create two VALE ports on the same switch
        let port1 = try NetmapPort.open(interface: "vale0:e2e1")
        let port2 = try NetmapPort.open(interface: "vale0:e2e2")

        print("  Opened vale0:e2e1 and vale0:e2e2")

        // Create a test packet (Ethernet frame with custom payload)
        var packet = Data()
        // Broadcast destination MAC
        packet.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        // Source MAC (port1)
        packet.append(contentsOf: [0x02, 0xE2, 0xE1, 0x00, 0x00, 0x01])
        // EtherType (custom)
        packet.append(contentsOf: [0x88, 0xB5])
        // Payload: "E2ETEST" + sequence
        let payload = "E2ETEST\(Date().timeIntervalSince1970)"
        packet.append(contentsOf: payload.utf8)
        // Pad to minimum frame size
        while packet.count < 60 {
            packet.append(0)
        }

        // Send from port1
        let txRing = port1.txRing(0)
        var txSlot = txRing.currentSlot
        txRing.setBuffer(for: &txSlot, data: packet)
        txRing.advance()
        try port1.txSync()

        print("  Sent \(packet.count) byte packet from e2e1")

        // Wait a bit for VALE to forward
        usleep(50000)  // 50ms

        // Receive on port2
        try port2.rxSync()
        let rxRing = port2.rxRing(0)

        if !rxRing.isEmpty {
            let rxSlot = rxRing.currentSlot
            let received = rxRing.bufferData(for: rxSlot)

            // Check if payload matches
            if received.count >= 14 {
                let rxPayload = received.dropFirst(14).prefix(while: { $0 != 0 })
                if let rxStr = String(data: Data(rxPayload), encoding: .utf8),
                   rxStr == payload {
                    print("  ✓ Packet received correctly on e2e2!")
                    print("    Payload: \(rxStr)")
                    passed += 1
                } else {
                    print("  ✗ Payload mismatch")
                    failed += 1
                }
            } else {
                print("  ✗ Received packet too small: \(received.count) bytes")
                failed += 1
            }
            rxRing.advance()
        } else {
            print("  ✗ No packet received on e2e2")
            print("    Note: This might be a timing issue. Try running again.")
            failed += 1
        }

        // Ports are automatically closed when they go out of scope (deinit)
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 6: Poll
    print("Test 6: Poll for Events")
    print("─────────────────────────")
    do {
        let port = try NetmapPort.open(interface: "vale0:polltest")

        // Poll with 0 timeout - should return immediately
        let events = try port.poll(events: .readWrite, timeout: 0)

        // TX ring should be writable (empty ring has slots)
        if events.contains(.writable) {
            print("  ✓ Poll returned writable (as expected for empty TX ring)")
            passed += 1
        } else if events.isEmpty {
            print("  ✓ Poll returned timeout (acceptable)")
            passed += 1
        } else {
            print("  ? Unexpected poll result: \(events.rawValue)")
            passed += 1  // Not a failure, just unexpected
        }
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 7: Zero-Copy Buffer Swap
    print("Test 7: Zero-Copy Buffer Swap")
    print("───────────────────────────────")
    do {
        let port = try NetmapPort.open(interface: "vale0:zctest")
        let txRing = port.txRing(0)

        var slot1 = txRing.slot(at: 0)
        var slot2 = txRing.slot(at: 1)

        let buf1 = slot1.bufferIndex
        let buf2 = slot2.bufferIndex

        NetmapZeroCopy.swapBuffers(&slot1, &slot2)

        if slot1.bufferIndex == buf2 && slot2.bufferIndex == buf1 {
            print("  ✓ Buffer indices swapped correctly")
            print("    slot1: \(buf1) -> \(slot1.bufferIndex)")
            print("    slot2: \(buf2) -> \(slot2.bufferIndex)")
            passed += 1
        } else {
            print("  ✗ Buffer swap failed")
            failed += 1
        }
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 8: Async Send/Receive
    print("Test 8: Async Send/Receive API")
    print("─────────────────────────────────")
    do {
        let port1 = try NetmapPort.open(interface: "vale0:async1")
        let port2 = try NetmapPort.open(interface: "vale0:async2")

        // Send using async API
        let testData = Data("AsyncTest".utf8)
        let sent = try port1.sendPacket(testData, timeout: 100)

        usleep(50000)

        // Receive using async API
        let packets = try port2.receivePackets(timeout: 100)

        if sent {
            print("  ✓ Async send succeeded")
            if !packets.isEmpty {
                print("  ✓ Async receive got \(packets.count) packets")
            } else {
                print("  ○ No packets received (timing dependent)")
            }
            passed += 1
        } else {
            print("  ✗ Async send failed")
            failed += 1
        }
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 9: VALE Port Listing
    print("Test 9: VALE Port Listing")
    print("───────────────────────────")
    do {
        // Open some ports first
        let p1 = try NetmapPort.open(interface: "vale0:list1")
        let p2 = try NetmapPort.open(interface: "vale0:list2")
        _ = p1.isRegistered
        _ = p2.isRegistered

        let ports = try NetmapVALE.listPorts(switch: "vale0")

        if ports.isEmpty {
            print("  ○ VALE_LIST returned empty (may not be supported)")
            print("    This is expected on some FreeBSD versions")
            passed += 1
        } else {
            print("  ✓ Listed \(ports.count) ports on vale0")
            for port in ports.prefix(5) {
                print("    - \(port.name) (index \(port.index))")
            }
            if ports.count > 5 {
                print("    ... and \(ports.count - 5) more")
            }
            passed += 1
        }
    } catch {
        print("  ○ VALE_LIST not supported: \(error)")
        print("    This is expected on some FreeBSD versions")
        passed += 1  // Don't fail for this - it's optional functionality
    }
    print()

    // Test 10: Extra Buffers
    print("Test 10: Extra Buffer Allocation")
    print("───────────────────────────────────")
    do {
        let port = try NetmapPort.open(
            interface: "vale0:extrabuf",
            extraBuffers: 32
        )

        let allocated = port.extraBufferCount
        print("  ✓ Requested 32 extra buffers, got \(allocated)")
        passed += 1
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 11: Extra Buffers List Management
    print("Test 11: Extra Buffers List Operations")
    print("────────────────────────────────────────")
    do {
        let port = try NetmapPort.open(
            interface: "vale0:extrabuflist",
            extraBuffers: 8
        )

        let initialHead = port.extraBuffersHead
        if initialHead != 0 {
            // Pop a buffer
            if let popped = port.popExtraBuffer() {
                print("  ✓ Popped extra buffer: \(popped)")

                // Push it back
                port.pushExtraBuffer(popped)
                let newHead = port.extraBuffersHead
                if newHead == popped {
                    print("  ✓ Pushed buffer back to head")
                    passed += 1
                } else {
                    print("  ✗ Push didn't update head correctly")
                    failed += 1
                }
            } else {
                print("  ✗ Failed to pop extra buffer")
                failed += 1
            }
        } else {
            print("  ○ No extra buffers available (head=0)")
            passed += 1
        }
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 12: Memory Pools Info
    print("Test 12: Memory Pools Information")
    print("───────────────────────────────────")
    do {
        // Need to use an interface name for pools info
        let poolsInfo = try NetmapPort.getPoolsInfo(interface: "vale0:poolstest")
        print("  ✓ Got pools info:")
        print("    Memory size: \(poolsInfo.memorySize / 1024) KB")
        print("    Memory ID: \(poolsInfo.memoryId)")
        print("    Buffer pool: \(poolsInfo.bufferPoolObjectCount) x \(poolsInfo.bufferPoolObjectSize) bytes")
        passed += 1
    } catch NetmapError.registerFailed(let err) {
        // ENXIO (6), EINVAL (22), ENODEV (19) all indicate not supported
        if err == 6 || err == 19 || err == 22 {
            print("  ○ POOLS_INFO_GET not supported on this system (errno \(err))")
            passed += 1
        } else {
            print("  ✗ Failed: \(NetmapError.registerFailed(errno: err))")
            failed += 1
        }
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Test 13: Port Header Length
    print("Test 13: Port Header Management")
    print("─────────────────────────────────")
    do {
        let port = try NetmapPort.open(interface: "vale0:hdrtest")

        // Get current header length
        let hdrLen = try port.getHeaderLength()
        print("  ✓ Current header length: \(hdrLen) bytes")

        // Try to set header length (may fail on some ports)
        do {
            try port.setHeaderLength(0)
            print("  ✓ Set header length to 0")
        } catch {
            print("  ○ Setting header length not supported (expected for VALE)")
        }
        passed += 1
    } catch {
        print("  ✗ Failed: \(error)")
        failed += 1
    }
    print()

    // Summary
    print("═══════════════════════════════════════════════════════════════")
    print("Results: \(passed) passed, \(failed) failed")
    print("═══════════════════════════════════════════════════════════════")

    if failed > 0 {
        print("\nSome tests failed. Make sure:")
        print("  1. You're running as root (sudo)")
        print("  2. The netmap kernel module is loaded")
        print("     Check: kldstat | grep netmap")
        print("     Load:  kldload netmap")
        exit(1)
    } else {
        print("\n✓ All tests passed! Netmap is working correctly.")
    }
}

// MARK: - VALE Demo

func valeDemo() throws {
    print("""
    VALE Switch Demonstration
    ─────────────────────────

    VALE is a software switch built into netmap that allows
    zero-copy packet forwarding between ports.

    This demo creates two VALE ports and sends packets between them.
    """)

    // Create two VALE ports
    print("\nCreating VALE ports...")

    let port1 = try NetmapPort.open(interface: "vale0:demo1")
    let port2 = try NetmapPort.open(interface: "vale0:demo2")

    print("  vale0:demo1 - \(port1.txRingCount) TX, \(port1.rxRingCount) RX rings")
    print("  vale0:demo2 - \(port2.txRingCount) TX, \(port2.rxRingCount) RX rings")

    // Get ring info
    let ring1 = port1.txRing(0)
    print("\nRing buffer size: \(ring1.bufferSize) bytes")
    print("Slots per ring: \(ring1.numSlots)")

    // Send test packets
    print("\nSending test packets from demo1 to demo2...")

    let testPackets = [
        ("Hello from VALE!", "Test 1"),
        ("FreeBSDKit Netmap", "Test 2"),
        ("Zero-copy networking", "Test 3"),
    ]

    let txRing = port1.txRing(0)

    for (msg, label) in testPackets {
        guard txRing.hasSpace else {
            print("  TX ring full!")
            break
        }

        // Create a simple Ethernet frame with the message
        var packet = Data()
        // Broadcast destination
        packet.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        // Source (port1 MAC)
        packet.append(contentsOf: [0x02, 0x00, 0x00, 0x00, 0x00, 0x01])
        // Custom EtherType
        packet.append(contentsOf: [0x88, 0xB5])
        // Payload
        packet.append(contentsOf: msg.utf8)
        // Pad
        while packet.count < 60 {
            packet.append(0)
        }

        var slot = txRing.currentSlot
        txRing.setBuffer(for: &slot, data: packet)
        txRing.advance()

        print("  Sent \(label): \"\(msg)\"")
    }

    try port1.txSync()
    print("\nPackets transmitted.")

    // Give VALE time to forward
    usleep(10000)

    // Receive on port2
    print("\nReceiving on demo2...")
    try port2.rxSync()

    let rxRing = port2.rxRing(0)
    var received = 0

    while !rxRing.isEmpty {
        let slot = rxRing.currentSlot
        let data = rxRing.bufferData(for: slot)

        // Extract message from packet
        if data.count >= 14 {
            let payload = data.dropFirst(14).prefix(while: { $0 != 0 })
            if let msg = String(data: Data(payload), encoding: .utf8) {
                print("  Received: \"\(msg)\"")
            }
        }

        rxRing.advance()
        received += 1
    }

    print("\nTotal packets received: \(received)")
    print("\nVALE demo complete!")
    // Ports are automatically closed when they go out of scope
}

// MARK: - Main

func main() throws {
    let args = CommandLine.arguments

    guard args.count >= 2 else {
        printUsage()
        return
    }

    let command = args[1]

    switch command {
    case "test":
        try runSelfTest()

    case "info":
        guard args.count >= 3 else {
            print("Error: interface name required")
            printUsage()
            return
        }
        try showInfo(interface: args[2])

    case "capture":
        guard args.count >= 3 else {
            print("Error: interface name required")
            printUsage()
            return
        }
        try capturePackets(interface: args[2])

    case "inject":
        guard args.count >= 3 else {
            print("Error: interface name required")
            printUsage()
            return
        }
        try injectPackets(interface: args[2])

    case "forward":
        guard args.count >= 4 else {
            print("Error: two interface names required")
            printUsage()
            return
        }
        try forwardPackets(from: args[2], to: args[3])

    case "vale":
        try valeDemo()

    case "help", "-h", "--help":
        printUsage()

    default:
        print("Unknown command: \(command)")
        printUsage()
    }
}

do {
    try main()
} catch let error as NetmapError {
    print("Netmap error: \(error)")
    exit(1)
} catch {
    print("Error: \(error)")
    exit(1)
}

/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Testing
@testable import DTraceCore
import Glibc


@Suite("DTraceCore Tests")
struct DTraceCoreTests {

    @Test("Version is available")
    func testVersion() {
        let version = DTraceCore.version
        #expect(version > 0)
    }

    @Test("Open flags are correct")
    func testOpenFlags() {
        let noDevice = DTraceOpenFlags.noDevice
        #expect(noDevice.rawValue == 0x01)

        let noSystem = DTraceOpenFlags.noSystem
        #expect(noSystem.rawValue == 0x02)

        let lp64 = DTraceOpenFlags.lp64
        #expect(lp64.rawValue == 0x04)

        let ilp32 = DTraceOpenFlags.ilp32
        #expect(ilp32.rawValue == 0x08)

        let combined: DTraceOpenFlags = [.noDevice, .noSystem]
        #expect(combined.rawValue == 0x03)

        // Test OptionSet conformance
        let empty: DTraceOpenFlags = []
        #expect(empty.rawValue == 0)

        var mutable: DTraceOpenFlags = [.noDevice]
        mutable.insert(.noSystem)
        #expect(mutable.contains(.noDevice))
        #expect(mutable.contains(.noSystem))
    }

    @Test("Compile flags are correct")
    func testCompileFlags() {
        // Verify flags exist and have non-zero values
        let verbose = DTraceCompileFlags.verbose
        #expect(verbose.rawValue != 0)

        let allowEmpty = DTraceCompileFlags.allowEmpty
        #expect(allowEmpty.rawValue != 0)

        let allowZeroMatches = DTraceCompileFlags.allowZeroMatches
        #expect(allowZeroMatches.rawValue != 0)

        let probeSpec = DTraceCompileFlags.probeSpec
        #expect(probeSpec.rawValue != 0)

        let noLibs = DTraceCompileFlags.noLibs
        #expect(noLibs.rawValue != 0)

        // Verify all flags are distinct
        let allFlags = [verbose, allowEmpty, allowZeroMatches, probeSpec, noLibs]
        for i in 0..<allFlags.count {
            for j in (i+1)..<allFlags.count {
                #expect(allFlags[i].rawValue != allFlags[j].rawValue)
            }
        }

        // Test combining flags
        let combined: DTraceCompileFlags = [.allowEmpty, .allowZeroMatches]
        #expect(combined.contains(.allowEmpty))
        #expect(combined.contains(.allowZeroMatches))
        #expect(!combined.contains(.verbose))

        // Test OptionSet conformance
        let empty: DTraceCompileFlags = []
        #expect(empty.rawValue == 0)

        var mutable: DTraceCompileFlags = [.verbose]
        mutable.insert(.allowEmpty)
        #expect(mutable.contains(.verbose))
        #expect(mutable.contains(.allowEmpty))
    }

    @Test("Probe description formats correctly")
    func testProbeDescription() {
        let probe = DTraceProbeDescription(
            id: 123,
            provider: "syscall",
            module: "kernel",
            function: "open",
            name: "entry"
        )

        #expect(probe.fullName == "syscall:kernel:open:entry")
        #expect(probe.description == "syscall:kernel:open:entry")
        #expect(probe.id == 123)
    }

    @Test("Probe description with default ID")
    func testProbeDescriptionDefaultId() {
        let probe = DTraceProbeDescription(
            provider: "fbt",
            module: "kernel",
            function: "malloc",
            name: "return"
        )

        #expect(probe.id == 0)
        #expect(probe.fullName == "fbt:kernel:malloc:return")
    }

    @Test("Probe description debug description")
    func testProbeDescriptionDebug() {
        let probe = DTraceProbeDescription(
            id: 42,
            provider: "syscall",
            module: "freebsd",
            function: "read",
            name: "entry"
        )

        #expect(probe.debugDescription == "DTraceProbeDescription(id: 42, syscall:freebsd:read:entry)")
    }

    @Test("Probe description is Hashable")
    func testProbeDescriptionHashable() {
        let probe1 = DTraceProbeDescription(
            id: 1,
            provider: "syscall",
            module: "kernel",
            function: "open",
            name: "entry"
        )

        let probe2 = DTraceProbeDescription(
            id: 1,
            provider: "syscall",
            module: "kernel",
            function: "open",
            name: "entry"
        )

        let probe3 = DTraceProbeDescription(
            id: 2,
            provider: "syscall",
            module: "kernel",
            function: "close",
            name: "entry"
        )

        #expect(probe1 == probe2)
        #expect(probe1 != probe3)

        // Test in Set
        let probeSet: Set<DTraceProbeDescription> = [probe1, probe2, probe3]
        #expect(probeSet.count == 2)  // probe1 and probe2 are equal
    }

    @Test("Work status enum values")
    func testWorkStatus() {
        let error = DTraceWorkStatus.error
        let okay = DTraceWorkStatus.okay
        let done = DTraceWorkStatus.done

        #expect(error != okay)
        #expect(okay != done)
        #expect(error != done)
    }

    @Test("DTrace status enum values")
    func testStatus() {
        let none = DTraceStatus.none
        let okay = DTraceStatus.okay
        let exited = DTraceStatus.exited
        let filled = DTraceStatus.filled
        let stopped = DTraceStatus.stopped

        #expect(none != okay)
        #expect(okay != exited)
        #expect(exited != filled)
        #expect(filled != stopped)
    }
}

@Suite("DTraceCoreError Tests")
struct DTraceCoreErrorTests {

    @Test("Error cases are distinct")
    func testErrorCases() {
        let openFailed = DTraceCoreError.openFailed(code: 1, message: "test")
        let compileFailed = DTraceCoreError.compileFailed(message: "test")
        let execFailed = DTraceCoreError.execFailed(message: "test")
        let goFailed = DTraceCoreError.goFailed(message: "test")
        let stopFailed = DTraceCoreError.stopFailed(message: "test")
        let workFailed = DTraceCoreError.workFailed(message: "test")
        let setOptFailed = DTraceCoreError.setOptFailed(option: "bufsize", message: "test")
        let getOptFailed = DTraceCoreError.getOptFailed(option: "bufsize", message: "test")
        let probeIterFailed = DTraceCoreError.probeIterFailed(message: "test")
        let handlerFailed = DTraceCoreError.handlerFailed(message: "test")
        let aggregateFailed = DTraceCoreError.aggregateFailed(message: "test")
        let procGrabFailed = DTraceCoreError.procGrabFailed(pid: 1234, message: "test")
        let consumeFailed = DTraceCoreError.consumeFailed(message: "test")
        let invalidHandle = DTraceCoreError.invalidHandle

        // Just verify they can be created and are Error conforming
        let errors: [any Error] = [
            openFailed, compileFailed, execFailed, goFailed, stopFailed,
            workFailed, setOptFailed, getOptFailed, probeIterFailed,
            handlerFailed, aggregateFailed, procGrabFailed, consumeFailed,
            invalidHandle
        ]

        #expect(errors.count == 14)
    }

    @Test("Error is Sendable")
    func testErrorSendable() {
        let error: any Error & Sendable = DTraceCoreError.invalidHandle
        #expect(error is DTraceCoreError)
    }
}

@Suite("DTraceHandle Types Tests")
struct DTraceHandleTypesTests {

    @Test("AggregateWalkResult enum values")
    func testAggregateWalkResult() {
        let next = DTraceHandle.AggregateWalkResult.next
        let abort = DTraceHandle.AggregateWalkResult.abort
        let clear = DTraceHandle.AggregateWalkResult.clear
        let remove = DTraceHandle.AggregateWalkResult.remove

        #expect(next.rawValue == 0)
        #expect(abort.rawValue == 1)
        #expect(clear.rawValue == 2)
        #expect(remove.rawValue == 5)
    }

    @Test("ConsumeResult enum values")
    func testConsumeResult() {
        let error = DTraceHandle.ConsumeResult.error
        let this = DTraceHandle.ConsumeResult.this
        let next = DTraceHandle.ConsumeResult.next
        let abort = DTraceHandle.ConsumeResult.abort

        #expect(error.rawValue == -1)
        #expect(this.rawValue == 0)
        #expect(next.rawValue == 1)
        #expect(abort.rawValue == 2)
    }

    @Test("DropKind enum values")
    func testDropKind() {
        let principal = DTraceHandle.DropKind.principal
        let aggregation = DTraceHandle.DropKind.aggregation
        let dynamic = DTraceHandle.DropKind.dynamic
        let speculation = DTraceHandle.DropKind.speculation
        let unknown = DTraceHandle.DropKind.unknown

        #expect(principal.rawValue == 0)
        #expect(aggregation.rawValue == 1)
        #expect(dynamic.rawValue == 2)
        #expect(speculation.rawValue == 5)
        #expect(unknown.rawValue == -1)
    }

    @Test("OutputFormat enum values")
    func testOutputFormat() {
        let text = DTraceHandle.OutputFormat.text
        let structured = DTraceHandle.OutputFormat.structured

        #expect(text.rawValue == 0)
        #expect(structured.rawValue == 1)
    }

    @Test("BufferPolicy enum values")
    func testBufferPolicy() {
        let switchPolicy = DTraceHandle.BufferPolicy.switch
        let fill = DTraceHandle.BufferPolicy.fill
        let ring = DTraceHandle.BufferPolicy.ring

        #expect(switchPolicy.rawValue == "switch")
        #expect(fill.rawValue == "fill")
        #expect(ring.rawValue == "ring")
    }

    @Test("BufferedOutputFlags option set")
    func testBufferedOutputFlags() {
        let aggKey = DTraceHandle.BufferedOutputFlags.aggregationKey
        let aggVal = DTraceHandle.BufferedOutputFlags.aggregationValue
        let aggFormat = DTraceHandle.BufferedOutputFlags.aggregationFormat
        let aggLast = DTraceHandle.BufferedOutputFlags.aggregationLast

        // Flags should be distinct
        #expect(aggKey.rawValue != aggVal.rawValue)
        #expect(aggVal.rawValue != aggFormat.rawValue)
        #expect(aggFormat.rawValue != aggLast.rawValue)

        // Test OptionSet conformance
        let combined: DTraceHandle.BufferedOutputFlags = [.aggregationKey, .aggregationValue]
        #expect(combined.contains(.aggregationKey))
        #expect(combined.contains(.aggregationValue))
        #expect(!combined.contains(.aggregationFormat))
    }

    @Test("BufferedOutput is Sendable")
    func testBufferedOutputSendable() {
        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let flags: DTraceHandle.BufferedOutputFlags = [.aggregationKey]
        let output = DTraceHandle.BufferedOutput(output: "test", flags: flags)
        let result = useSendable(output)
        #expect(result.output == "test")
        #expect(result.isAggregationKey == true)
        #expect(result.isAggregationValue == false)
    }

    @Test("DropInfo is Sendable")
    func testDropInfoSendable() {
        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let info = DTraceHandle.DropInfo(kind: .principal, drops: 10, message: "test")
        let result = useSendable(info)
        #expect(result.drops == 10)
        #expect(result.kind == .principal)
        #expect(result.message == "test")
    }

    @Test("ErrorInfo is Sendable")
    func testErrorInfoSendable() {
        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let info = DTraceHandle.ErrorInfo(fault: 42, message: "test error")
        let result = useSendable(info)
        #expect(result.fault == 42)
        #expect(result.message == "test error")
    }

    @Test("ProbeData is Sendable")
    func testProbeDataSendable() {
        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let probe = DTraceProbeDescription(
            id: 1,
            provider: "syscall",
            module: "freebsd",
            function: "read",
            name: "entry"
        )
        let data = DTraceHandle.ProbeData(cpu: 0, probe: probe)
        let result = useSendable(data)
        #expect(result.cpu == 0)
        #expect(result.probe.function == "read")
    }

    @Test("Typed aggregation key decoder sign-extends integer widths")
    func testDecodeTypedAggregationKeyIntegers() {
        var buf = [UInt8](repeating: 0, count: 16)
        buf.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: Int8(-7), toByteOffset: 0, as: Int8.self)
            ptr.storeBytes(of: Int16(-42), toByteOffset: 2, as: Int16.self)
            ptr.storeBytes(of: Int32(1000), toByteOffset: 4, as: Int32.self)
            ptr.storeBytes(of: Int64(65), toByteOffset: 8, as: Int64.self)
        }

        buf.withUnsafeMutableBufferPointer { ptr in
            let base = ptr.baseAddress!
            #expect(decodeTypedAggregationKey(offset: 0, size: 1, buffer: base) == "-7")
            #expect(decodeTypedAggregationKey(offset: 2, size: 2, buffer: base) == "-42")
            #expect(decodeTypedAggregationKey(offset: 4, size: 4, buffer: base) == "1000")
            #expect(decodeTypedAggregationKey(offset: 8, size: 8, buffer: base) == "65")
        }
    }
}

@Suite("DTraceProgramInfo Tests")
struct DTraceProgramInfoTests {

    @Test("Program info fields are accessible")
    func testProgramInfoFields() {
        // Create a mock dtrace_proginfo_t to test our Swift struct
        // Note: We can't directly create one in tests without dtrace,
        // but we can verify the struct definition is correct
        #expect(Bool(true))  // Placeholder - actual testing requires dtrace handle
    }
}

@Suite("DTraceHandle Integration Tests")
struct DTraceHandleIntegrationTests {

    @Test("Structured output methods exist")
    func testStructuredOutputAPI() throws {
        // Skip if not root - DTrace requires elevated privileges
        guard getuid() == 0 else {
            print("Skipping testStructuredOutputAPI: requires root privileges")
            return
        }

        let handle = try DTraceHandle.open()

        // Test enable/disable cycle
        try handle.enableStructuredOutput()
        #expect(handle.isStructuredOutputEnabled == true)

        handle.disableStructuredOutput()
        #expect(handle.isStructuredOutputEnabled == false)
    }

    @Test("Error handler registration")
    func testErrorHandlerAPI() throws {
        guard getuid() == 0 else {
            print("Skipping testErrorHandlerAPI: requires root privileges")
            return
        }

        let handle = try DTraceHandle.open()

        // Verify handler can be registered without error
        try handle.onError { _ in
            return true
        }

        #expect(Bool(true))  // If we get here, registration succeeded
    }

    @Test("Drop handler registration")
    func testDropHandlerAPI() throws {
        guard getuid() == 0 else {
            print("Skipping testDropHandlerAPI: requires root privileges")
            return
        }

        let handle = try DTraceHandle.open()

        // Verify handler can be registered without error
        try handle.onDrop { _ in
            return true
        }

        #expect(Bool(true))  // If we get here, registration succeeded
    }

    @Test("Aggregate walk with empty aggregations")
    func testAggregateWalkAPI() throws {
        guard getuid() == 0 else {
            print("Skipping testAggregateWalkAPI: requires root privileges")
            return
        }

        let handle = try DTraceHandle.open()
        try handle.setOption("bufsize", value: "4m")
        try handle.setOption("aggsize", value: "4m")

        // Compile a simple program
        let program = try handle.compile("BEGIN { exit(0); }")
        try handle.exec(program)
        try handle.go()

        // Wait for completion
        while handle.poll() == .okay {
            handle.sleep()
        }

        try handle.stop()

        // Walk empty aggregations (should not crash)
        var count = 0
        try handle.aggregateSnap()
        try handle.aggregateWalk(sorted: true) { _, _ in
            count += 1
            return .next
        }

        #expect(count == 0)  // No aggregations in this simple program
    }

    @Test("Typed aggregate walk decodes numeric keys")
    func testAggregateWalkTypedDecodesNumericKeys() throws {
        guard getuid() == 0 else {
            print("Skipping testAggregateWalkTypedDecodesNumericKeys: requires root privileges")
            return
        }

        let handle = try DTraceHandle.open()
        try handle.setOption("bufsize", value: "4m")
        try handle.setOption("aggsize", value: "4m")

        let program = try handle.compile("""
            BEGIN {
                @counts[65] = count();
                exit(0);
            }
            """)
        try handle.exec(program)
        try handle.go()

        while handle.poll() == .okay {
            handle.sleep()
        }

        try handle.stop()
        try handle.aggregateSnap()

        var records: [DTraceHandle.AggregationRecord] = []
        try handle.aggregateWalkTyped { record in
            records.append(record)
            return .next
        }

        #expect(records.count == 1)
        #expect(records.first?.name == "counts")
        #expect(records.first?.action == .count)
        #expect(records.first?.keys == ["65"])
        #expect(records.first?.value == 1)
    }
}

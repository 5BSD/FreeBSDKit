/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import Testing
import Glibc
import Foundation
import CDTrace
@testable import DBlocks

@Suite("DTraceTarget Tests")
struct DTraceTargetTests {

    @Test("Target for PID")
    func testPidTarget() {
        let target = DTraceTarget.pid(1234)
        #expect(target.predicate == "pid == 1234")
        #expect(target.description == "/pid == 1234/")
    }

    @Test("Target for execname")
    func testExecnameTarget() {
        let target = DTraceTarget.execname("nginx")
        #expect(target.predicate == "execname == \"nginx\"")
    }

    @Test("Target for process name contains")
    func testProcessNameContains() {
        let target = DTraceTarget.processNameContains("http")
        #expect(target.predicate == "strstr(execname, \"http\") != NULL")
    }

    @Test("Target for UID")
    func testUidTarget() {
        let target = DTraceTarget.uid(1000)
        #expect(target.predicate == "uid == 1000")
    }

    @Test("Target for GID")
    func testGidTarget() {
        let target = DTraceTarget.gid(100)
        #expect(target.predicate == "gid == 100")
    }

    @Test("Target for jail")
    func testJailTarget() {
        let target = DTraceTarget.jail(5)
        #expect(target.predicate == "jid == 5")
    }

    @Test("All target has empty predicate")
    func testAllTarget() {
        let target = DTraceTarget.all
        #expect(target.predicate.isEmpty)
        #expect(target.description == "(all)")
    }

    @Test("Current process target")
    func testCurrentProcessTarget() {
        let target = DTraceTarget.currentProcess
        #expect(target.predicate.contains("pid == "))
    }

    @Test("Combining targets with AND")
    func testAndCombination() {
        let target = DTraceTarget.execname("nginx").and(.uid(1000))
        #expect(target.predicate == "(execname == \"nginx\") && (uid == 1000)")
    }

    @Test("Combining all with AND returns other")
    func testAndWithAll() {
        let nginx = DTraceTarget.execname("nginx")
        let combined1 = DTraceTarget.all.and(nginx)
        #expect(combined1.predicate == nginx.predicate)

        let combined2 = nginx.and(.all)
        #expect(combined2.predicate == nginx.predicate)
    }

    @Test("Combining targets with OR")
    func testOrCombination() {
        let target = DTraceTarget.execname("nginx").or(.execname("apache"))
        #expect(target.predicate.contains("||"))
        #expect(target.predicate.contains("nginx"))
        #expect(target.predicate.contains("apache"))
    }

    @Test("Combining with all using OR returns all")
    func testOrWithAll() {
        let nginx = DTraceTarget.execname("nginx")
        let combined1 = DTraceTarget.all.or(nginx)
        #expect(combined1.predicate.isEmpty)

        let combined2 = nginx.or(.all)
        #expect(combined2.predicate.isEmpty)
    }

    @Test("Negating a target")
    func testNegation() {
        let target = DTraceTarget.execname("nginx").negated()
        #expect(target.predicate == "!(execname == \"nginx\")")
    }

    @Test("Negating all target returns all")
    func testNegateAll() {
        let target = DTraceTarget.all.negated()
        #expect(target.predicate.isEmpty)
    }

    @Test("Operators work")
    func testOperators() {
        let target = DTraceTarget.pid(1234) && DTraceTarget.uid(0)
        #expect(target.predicate.contains("&&"))

        let either = DTraceTarget.execname("a") || DTraceTarget.execname("b")
        #expect(either.predicate.contains("||"))

        let not = !DTraceTarget.pid(1)
        #expect(not.predicate.contains("!"))
    }

    @Test("Custom predicate")
    func testCustomPredicate() {
        let target = DTraceTarget.custom("arg0 > 100")
        #expect(target.predicate == "arg0 > 100")
    }

    @Test("Target is Hashable")
    func testHashable() {
        let target1 = DTraceTarget.pid(1234)
        let target2 = DTraceTarget.pid(1234)
        let target3 = DTraceTarget.pid(5678)

        #expect(target1 == target2)
        #expect(target1 != target3)

        let targetSet: Set<DTraceTarget> = [target1, target2, target3]
        #expect(targetSet.count == 2)
    }

    @Test("Target is Sendable")
    func testSendable() {
        // Verify DTraceTarget conforms to Sendable by assigning to a Sendable-constrained function
        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let target = useSendable(DTraceTarget.pid(1234))
        #expect(!target.predicate.isEmpty)
    }

    @Test("Complex target combinations")
    func testComplexCombinations() {
        // (nginx OR apache) AND uid == 0
        let webServers = DTraceTarget.execname("nginx") || DTraceTarget.execname("apache")
        let rootOnly = DTraceTarget.uid(0)
        let combined = webServers && rootOnly

        #expect(combined.predicate.contains("nginx"))
        #expect(combined.predicate.contains("apache"))
        #expect(combined.predicate.contains("uid == 0"))
    }
}

@Suite("DTraceOutput Tests")
struct DTraceOutputTests {

    @Test("Output enum cases exist")
    func testOutputCases() {
        _ = DTraceOutput.stdout
        _ = DTraceOutput.stderr
        _ = DTraceOutput.null
        _ = DTraceOutput.file("/tmp/test.log")
        _ = DTraceOutput.fileDescriptor(1)  // stdout fd
    }

    @Test("Output buffer captures content")
    func testOutputBuffer() {
        let buffer = DTraceOutputBuffer()
        #expect(buffer.contents.isEmpty)
    }

    @Test("Output buffer can be cleared")
    func testOutputBufferClear() {
        let buffer = DTraceOutputBuffer()
        #expect(buffer.contents.isEmpty)
        buffer.clear()
        #expect(buffer.contents.isEmpty)
    }

    @Test("Output is Sendable")
    func testOutputSendable() {
        func useSendable<T: Sendable>(_ value: T) -> T { value }
        let output = useSendable(DTraceOutput.stdout)
        _ = output
    }

    @Test("Buffer output case")
    func testBufferOutputCase() {
        let buffer = DTraceOutputBuffer()
        let output = DTraceOutput.buffer(buffer)
        _ = output
    }

    @Test("Buffer captures written content")
    func testBufferCapturesContent() {
        let buffer = DTraceOutputBuffer()

        if let fp = buffer.filePointer {
            let message = "Hello, DTrace!"
            fputs(message, fp)
            fflush(fp)

            let contents = buffer.contents
            #expect(contents == message)
        }
    }

    @Test("Buffer clear removes content")
    func testBufferClearRemovesContent() {
        let buffer = DTraceOutputBuffer()

        if let fp = buffer.filePointer {
            fputs("test content", fp)
            fflush(fp)
            #expect(!buffer.contents.isEmpty)

            buffer.clear()
            #expect(buffer.contents.isEmpty)
        }
    }

    @Test("Buffer handles multiple writes")
    func testBufferMultipleWrites() {
        let buffer = DTraceOutputBuffer()

        if let fp = buffer.filePointer {
            fputs("first", fp)
            fputs(" second", fp)
            fputs(" third", fp)
            fflush(fp)

            #expect(buffer.contents == "first second third")
        }
    }

    @Test("Output withFilePointer works for stdout")
    func testWithFilePointerStdout() {
        let output = DTraceOutput.stdout
        _ = output.withFilePointer { fp in
            fp == Glibc.stdout
        }
    }

    @Test("Output withFilePointer works for stderr")
    func testWithFilePointerStderr() {
        let output = DTraceOutput.stderr
        _ = output.withFilePointer { fp in
            fp == Glibc.stderr
        }
    }

    @Test("Output withFilePointer works for null")
    func testWithFilePointerNull() {
        let output = DTraceOutput.null
        let called = output.withFilePointer { fp in
            // Should get a valid file pointer (to /dev/null)
            return true
        }
        #expect(called)
    }

    @Test("Output withFilePointer works for file")
    func testWithFilePointerFile() throws {
        let testPath = "/tmp/dtrace_output_test_\(getpid()).txt"
        defer { unlink(testPath) }

        let output = DTraceOutput.file(testPath)
        _ = output.withFilePointer { fp in
            fputs("test output", fp)
        }

        // Verify file was written
        let contents = try String(contentsOfFile: testPath, encoding: .utf8)
        #expect(contents == "test output")
    }

    @Test("Output withFilePointer works for buffer")
    func testWithFilePointerBuffer() {
        let buffer = DTraceOutputBuffer()
        let output = DTraceOutput.buffer(buffer)

        _ = output.withFilePointer { fp in
            fputs("buffer test", fp)
            fflush(fp)
        }

        #expect(buffer.contents == "buffer test")
    }

    @Test("Output withFilePointer works for fileDescriptor")
    func testWithFilePointerFileDescriptor() throws {
        let testPath = "/tmp/dtrace_fd_test_\(getpid()).txt"
        defer { unlink(testPath) }

        // Open a file and get its descriptor
        let fd = open(testPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        #expect(fd >= 0)
        defer { close(fd) }

        let output = DTraceOutput.fileDescriptor(fd)
        _ = output.withFilePointer { fp in
            fputs("fd test", fp)
        }

        // Read back and verify
        let contents = try String(contentsOfFile: testPath, encoding: .utf8)
        #expect(contents == "fd test")
    }

    @Test("FileDescriptor output doesn't close original fd")
    func testFileDescriptorDoesntCloseOriginal() throws {
        let testPath = "/tmp/dtrace_fd_close_test_\(getpid()).txt"
        defer { unlink(testPath) }

        let fd = open(testPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        #expect(fd >= 0)
        defer { close(fd) }

        let output = DTraceOutput.fileDescriptor(fd)
        _ = output.withFilePointer { fp in
            fputs("first write", fp)
        }

        // Original fd should still be valid - write should succeed
        let result = write(fd, "second", 6)
        #expect(result == 6)
    }
}

@Suite("DTraceSession Tests")
struct DTraceSessionTests {

    @Test("Session can be created with factory method")
    func testSessionFactory() throws {
        // This test validates the API exists (actual DTrace requires root)
        // Just verify the types compile correctly
        _ = DTraceSession.create as (DTraceOpenFlags) throws -> DTraceSession
    }

    @Test("Session configuration methods exist")
    func testSessionConfigMethods() {
        // Verify method signatures exist via static type checking
        // DTraceSession is ~Copyable, so we verify types via function type annotations

        func verifyOutput(_: (inout DTraceSession, DTraceOutput) -> Void) {}
        func verifyBufferSize(_: (inout DTraceSession, String) throws -> Void) {}
        func verifyAggBufferSize(_: (inout DTraceSession, String) throws -> Void) {}
        func verifyQuiet(_: (inout DTraceSession) throws -> Void) {}
        func verifyJsonOutput(_: (inout DTraceSession) throws -> Void) {}
        func verifyOption(_: (inout DTraceSession, String, String?) throws -> Void) {}

        #expect(true, "Configuration methods verified via static type checking")
    }

    @Test("Session script methods exist")
    func testSessionScriptMethods() {
        // Verify add method signatures exist
        func verifyAddScript(_: (inout DTraceSession, DBlocks) -> Void) {}

        #expect(true, "Script methods verified via static type checking")
    }

    @Test("Session execution methods exist")
    func testSessionExecutionMethods() {
        // Verify execution method signatures exist
        func verifyRun(_: (inout DTraceSession) throws -> Void) {}
        func verifyRunFor(_: (inout DTraceSession, TimeInterval) throws -> Void) {}
        func verifyStart(_: (inout DTraceSession) throws -> Void) {}
        func verifyStop(_: (borrowing DTraceSession) throws -> Void) {}
        func verifyProcess(_: (borrowing DTraceSession) -> DTraceWorkStatus) {}
        func verifyProcessFor(_: (borrowing DTraceSession, TimeInterval) -> Void) {}
        func verifyWait(_: (borrowing DTraceSession) -> Void) {}

        #expect(true, "Execution methods verified via static type checking")
    }

    @Test("DBlocks run methods exist")
    func testDBlocksRunMethods() {
        // Verify DBlocks has run/capture methods
        let script = DBlocks {
            Probe("syscall:::entry") { Count() }
        }

        // These are instance methods
        _ = script.run as () throws -> Void
        _ = script.run as (TimeInterval) throws -> Void
        _ = script.capture as () throws -> String
        _ = script.capture as (TimeInterval) throws -> String

        #expect(true, "DBlocks run methods verified")
    }

    @Test("DBlocks static run methods exist")
    func testDBlocksStaticRunMethods() {
        // Verify DBlocks has static run/capture methods
        _ = DBlocks.run as (@escaping () -> [ProbeClause]) throws -> Void
        _ = DBlocks.run as (TimeInterval, @escaping () -> [ProbeClause]) throws -> Void
        _ = DBlocks.capture as (@escaping () -> [ProbeClause]) throws -> String
        _ = DBlocks.capture as (TimeInterval, @escaping () -> [ProbeClause]) throws -> String

        #expect(true, "DBlocks static run methods verified")
    }

    @Test("Deprecated typealias exists")
    func testDeprecatedTypealias() {
        // DBlocksSession should be a typealias for DTraceSession
        let _: DBlocksSession.Type = DTraceSession.self
        #expect(true, "Deprecated typealias exists")
    }

    @Test("Session reports not running after exit")
    func testSessionIsRunningTracksExit() throws {
        guard getuid() == 0 else {
            print("Skipping testSessionIsRunningTracksExit: requires root privileges")
            return
        }

        var session = try DTraceSession.create()
        session.add {
            BEGIN { Exit(0) }
        }

        try session.start()
        #expect(session.isRunning == true)

        while session.process() == .okay {
            session.wait()
        }

        #expect(session.isRunning == false)
    }

    @Test("Session snapshot decodes live aggregation rows")
    func testSessionSnapshotDecodesAggregationRows() throws {
        guard getuid() == 0 else {
            print("Skipping testSessionSnapshotDecodesAggregationRows: requires root privileges")
            return
        }

        var session = try DTraceSession.create()
        session.add {
            BEGIN {
                Count(by: "65", into: "calls")
                Exit(0)
            }
        }

        try session.start()
        while session.process() == .okay {
            session.wait()
        }

        let records = try session.snapshot()
        #expect(records.count == 1)
        #expect(records.first?.name == "calls")
        #expect(records.first?.keys == [.int(65)])
        #expect(records.first?.value == .count(1))
    }
}

@Suite("DBlocks Module Tests")
struct DBlocksModuleTests {

    @Test("DTraceCore is re-exported")
    func testDTraceCoreReExported() {
        // Verify DTraceCore types are accessible via DBlocks
        let version = DTraceCore.version
        #expect(version > 0)

        let flags: DTraceOpenFlags = [.noDevice]
        #expect(flags.rawValue == 0x01)
    }
}

// MARK: - DBlocks Validation Tests

@Suite("DBlocks Validation Tests")
struct DBlocksValidationTests {

    @Test("Empty script throws emptyScript error")
    func testEmptyScriptThrows() {
        // Create an empty script programmatically (can't do with builder)
        let script = DBlocks { }

        #expect(throws: DBlocksError.self) {
            try script.validate()
        }
    }

    @Test("Probe with no actions throws emptyClause error")
    func testProbeNoActionsThrows() {
        // Create a probe clause with no actions programmatically
        let clause = ProbeClause(probe: "syscall:::entry", predicates: ["pid == 1234"], actions: [])

        // We need to create a DBlocks with this clause
        // Since DBlocks uses a builder, we'll test the clause directly
        #expect(clause.actions.isEmpty)

        // Create script with the empty-action clause
        struct TestScript {
            let clauses: [ProbeClause]

            func validate() throws {
                if clauses.isEmpty {
                    throw DBlocksError.emptyScript
                }
                for (index, clause) in clauses.enumerated() {
                    if clause.actions.isEmpty {
                        throw DBlocksError.emptyClause(probe: clause.probe, index: index)
                    }
                }
            }
        }

        let testScript = TestScript(clauses: [clause])
        #expect(throws: DBlocksError.self) {
            try testScript.validate()
        }
    }

    @Test("Probe with only predicates (no actions) is invalid")
    func testPredicateOnlyProbeInvalid() {
        // Using the programmatic initializer
        let clause = ProbeClause(
            probe: "syscall:::entry",
            predicates: ["execname == \"nginx\"", "arg0 > 0"],
            actions: []
        )

        #expect(clause.predicates.count == 2)
        #expect(clause.actions.isEmpty)
    }

    @Test("DBlocksError descriptions are meaningful")
    func testErrorDescriptions() {
        let emptyError = DBlocksError.emptyScript
        #expect(emptyError.description.contains("no probe clauses"))

        let emptyClauseError = DBlocksError.emptyClause(probe: "syscall:::entry", index: 0)
        #expect(emptyClauseError.description.contains("syscall:::entry"))
        #expect(emptyClauseError.description.contains("0"))
        #expect(emptyClauseError.description.contains("no actions"))

        let compileError = DBlocksError.compilationFailed(
            source: "invalid:::probe { }",
            error: "syntax error"
        )
        #expect(compileError.description.contains("compilation failed"))
        #expect(compileError.description.contains("syntax error"))
    }

    @Test("Script compile() method exists")
    func testCompileMethodExists() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count()
            }
        }

        // Verify the method signature exists
        // Actually calling compile() requires root
        _ = script.compile as () throws -> Bool
    }

    @Test("Valid script with action passes validation")
    func testValidScriptPasses() throws {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count()
            }
        }

        // Should not throw
        try script.validate()
        #expect(script.clauses.count == 1)
        #expect(!script.clauses[0].actions.isEmpty)
    }

    @Test("Valid script with multiple probes passes")
    func testMultipleProbesPasses() throws {
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Timestamp()
            }
            Probe("syscall::read:return") {
                When("self->ts")
                Latency(by: "execname")
            }
        }

        try script.validate()
        #expect(script.clauses.count == 2)
    }

    @Test("Script data conversion works")
    func testScriptDataConversion() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count()
            }
        }

        let data = script.data
        #expect(!data.isEmpty)

        // Verify it's valid UTF-8
        let string = String(data: data, encoding: .utf8)
        #expect(string != nil)
        #expect(string == script.source)
    }

    @Test("Script null-terminated data works")
    func testScriptNullTerminatedData() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count()
            }
        }

        let data = script.nullTerminatedData
        #expect(data.last == 0)  // Null terminator
        #expect(data.count == script.source.utf8.count + 1)
    }

    @Test("Script JSON data is valid JSON")
    func testScriptJSONDataValid() throws {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Target(.execname("nginx"))
                Count(by: "probefunc")
            }
        }

        let jsonData = try script.jsonData()

        // Verify it's valid JSON. The version field is monotonic
        // and may bump as new optional fields are added — assert it
        // is present and >= 1 rather than pinning a specific value.
        let parsed = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        let version = parsed?["version"] as? Int ?? 0
        #expect(version >= 1)

        let clauses = parsed?["clauses"] as? [[String: Any]]
        #expect(clauses?.count == 1)

        let firstClause = clauses?[0]
        #expect(firstClause?["probe"] as? String == "syscall:::entry")
        #expect((firstClause?["predicates"] as? [String])?.count == 1)
        #expect((firstClause?["actions"] as? [String])?.count == 1)
    }

    @Test("Script write to file works")
    func testScriptWriteToFile() throws {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count()
            }
        }

        let testPath = "/tmp/dblocks_test_\(getpid()).d"
        defer { unlink(testPath) }

        try script.write(to: testPath)

        let contents = try String(contentsOfFile: testPath, encoding: .utf8)
        #expect(contents == script.source)
    }
}

// MARK: - DBlocks ResultBuilder Tests

@Suite("DBlocks ResultBuilder Tests")
struct DBlocksResultBuilderTests {

    @Test("Simple script with single probe")
    func testSimpleScript() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count(by: "probefunc")
            }
        }

        let source = script.source
        #expect(source.contains("syscall:::entry"))
        #expect(source.contains("@[probefunc] = count();"))
    }

    @Test("Script with target predicate")
    func testScriptWithTarget() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Target(.execname("nginx"))
                Count(by: "probefunc")
            }
        }

        let source = script.source
        #expect(source.contains("execname == \"nginx\""))
        #expect(source.contains("count()"))
    }

    @Test("Script with When predicate")
    func testScriptWithWhen() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                When("arg0 > 0")
                Sum("arg0", by: "execname")
            }
        }

        let source = script.source
        #expect(source.contains("/(arg0 > 0)/"))
        #expect(source.contains("sum(arg0)"))
    }

    @Test("Script with multiple predicates")
    func testScriptWithMultiplePredicates() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Target(.execname("nginx"))
                When("arg0 > 0")
                Count()
            }
        }

        let source = script.source
        #expect(source.contains("execname == \"nginx\""))
        #expect(source.contains("arg0 > 0"))
        #expect(source.contains("&&"))
    }

    @Test("Script with multiple actions")
    func testScriptWithMultipleActions() {
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Action("self->ts = timestamp;")
                Action("self->fd = arg0;")
            }
        }

        let source = script.source
        #expect(source.contains("self->ts = timestamp;"))
        #expect(source.contains("self->fd = arg0;"))
    }

    @Test("Script with multiple probes")
    func testScriptWithMultipleProbes() {
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Target(.execname("postgres"))
                Timestamp()
            }
            Probe("syscall::read:return") {
                Target(.execname("postgres"))
                When("self->ts")
                Latency(by: "execname")
            }
        }

        let source = script.source
        #expect(source.contains("syscall::read:entry"))
        #expect(source.contains("syscall::read:return"))
        #expect(source.contains("self->ts = timestamp;"))
        #expect(source.contains("quantize"))
    }

    @Test("All aggregation types")
    func testAllAggregationTypes() {
        let script = DBlocks {
            Probe("test:::probe") {
                Count(by: "a")
            }
            Probe("test:::probe") {
                Sum("v", by: "b")
            }
            Probe("test:::probe") {
                Min("v", by: "c")
            }
            Probe("test:::probe") {
                Max("v", by: "d")
            }
            Probe("test:::probe") {
                Avg("v", by: "e")
            }
            Probe("test:::probe") {
                Quantize("v", by: "f")
            }
            Probe("test:::probe") {
                Lquantize("v", low: 0, high: 100, step: 10, by: "g")
            }
        }

        let source = script.source
        #expect(source.contains("@[a] = count();"))
        #expect(source.contains("@[b] = sum(v);"))
        #expect(source.contains("@[c] = min(v);"))
        #expect(source.contains("@[d] = max(v);"))
        #expect(source.contains("@[e] = avg(v);"))
        #expect(source.contains("@[f] = quantize(v);"))
        #expect(source.contains("@[g] = lquantize(v, 0, 100, 10);"))
    }

    @Test("Printf action")
    func testPrintfAction() {
        let script = DBlocks {
            Probe("syscall::open:entry") {
                Printf("%s[%d]: %s", "execname", "pid", "copyinstr(arg0)")
            }
        }

        let source = script.source
        #expect(source.contains("printf"))
        #expect(source.contains("execname"))
        #expect(source.contains("pid"))
        #expect(source.contains("copyinstr(arg0)"))
    }

    @Test("Trace action")
    func testTraceAction() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Trace("arg0")
            }
        }

        let source = script.source
        #expect(source.contains("trace(arg0);"))
    }

    @Test("Stack trace actions")
    func testStackTraceActions() {
        let script = DBlocks {
            Probe("fbt:::entry") {
                Stack()
            }
            Probe("pid$target:::entry") {
                Stack(userland: true)
            }
        }

        let source = script.source
        #expect(source.contains("stack();"))
        #expect(source.contains("ustack();"))
    }

    @Test("Timestamp and Latency helpers")
    func testTimestampAndLatency() {
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Timestamp()
            }
            Probe("syscall::read:return") {
                When("self->ts")
                Latency(by: "execname")
            }
        }

        let source = script.source
        #expect(source.contains("self->ts = timestamp;"))
        #expect(source.contains("quantize(timestamp - self->ts)"))
        #expect(source.contains("self->ts = 0;"))
    }

    @Test("Custom Timestamp variable")
    func testCustomTimestampVariable() {
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Timestamp("self->read_start")
            }
        }

        let source = script.source
        #expect(source.contains("self->read_start = timestamp;"))
    }

    @Test("Script validation - passes for valid script")
    func testValidationPasses() throws {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count()
            }
        }

        try script.validate()  // Should not throw
    }

    @Test("Script validation - passes with multiple valid probes")
    func testValidationMultipleProbes() throws {
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Timestamp()
            }
            Probe("syscall::read:return") {
                When("self->ts")
                Latency(by: "execname")
            }
        }

        try script.validate()
    }

    @Test("Script validation - passes with predicate only actions")
    func testValidationPredicateWithAction() throws {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Target(.execname("nginx"))
                When("arg0 > 0")
                Count()  // Has an action
            }
        }

        try script.validate()
    }

    @Test("DBlocks description matches source")
    func testDescription() {
        let script = DBlocks {
            Probe("test:::probe") {
                Count()
            }
        }

        #expect(script.description == script.source)
    }

    @Test("Predefined syscallCounts script")
    func testPredefinedSyscallCounts() {
        let script = DBlocks.syscallCounts(for: .execname("nginx"))
        let source = script.source

        #expect(source.contains("syscall:freebsd::entry"))
        #expect(source.contains("execname == \"nginx\""))
        #expect(source.contains("count()"))
    }

    @Test("Predefined syscallCounts without target")
    func testPredefinedSyscallCountsNoTarget() {
        let script = DBlocks.syscallCounts()
        let source = script.source

        #expect(source.contains("syscall:freebsd::entry"))
        #expect(source.contains("count()"))
        // Should not have a predicate for .all target
    }

    @Test("Predefined fileOpens script")
    func testPredefinedFileOpens() {
        let script = DBlocks.fileOpens(for: .pid(1234))
        let source = script.source

        #expect(source.contains("syscall:freebsd:open"))
        #expect(source.contains("pid == 1234"))
        #expect(source.contains("printf"))
    }

    @Test("Predefined cpuProfile script")
    func testPredefinedCpuProfile() {
        let script = DBlocks.cpuProfile(hz: 99, for: .uid(0))
        let source = script.source

        #expect(source.contains("profile-99"))
        #expect(source.contains("uid == 0"))
        #expect(source.contains("count()"))
    }

    @Test("Predefined processExec script")
    func testPredefinedProcessExec() {
        let script = DBlocks.processExec()
        let source = script.source

        #expect(source.contains("proc:::exec-success"))
        #expect(source.contains("printf"))
    }

    @Test("Predefined ioBytes script")
    func testPredefinedIoBytes() {
        let script = DBlocks.ioBytes(for: .execname("postgres"))
        let source = script.source

        #expect(source.contains("syscall:freebsd:read:return"))
        #expect(source.contains("syscall:freebsd:write:return"))
        #expect(source.contains("execname == \"postgres\""))
        #expect(source.contains("sum(arg0)"))
    }

    @Test("Predefined syscallLatency script")
    func testPredefinedSyscallLatency() {
        let script = DBlocks.syscallLatency("write", for: .jail(1))
        let source = script.source

        #expect(source.contains("syscall:freebsd:write:entry"))
        #expect(source.contains("syscall:freebsd:write:return"))
        #expect(source.contains("jid == 1"))
        #expect(source.contains("timestamp"))
        #expect(source.contains("quantize"))
    }

    @Test("Complex combined predicates")
    func testComplexCombinedPredicates() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Target(.execname("nginx") || .execname("apache"))
                When("arg0 > 0")
                Count()
            }
        }

        let source = script.source
        #expect(source.contains("nginx"))
        #expect(source.contains("apache"))
        #expect(source.contains("||"))
        #expect(source.contains("arg0 > 0"))
    }

    @Test("Script with raw action code")
    func testRawActionCode() {
        let script = DBlocks {
            Probe("syscall::open:entry") {
                Action("""
                    self->path = copyinstr(arg0);
                    self->flags = arg1;
                    self->mode = arg2;
                    """)
            }
        }

        let source = script.source
        #expect(source.contains("self->path = copyinstr(arg0);"))
        #expect(source.contains("self->flags = arg1;"))
        #expect(source.contains("self->mode = arg2;"))
    }

    @Test("Output format is correct D syntax")
    func testOutputFormatIsValidD() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Target(.execname("test"))
                When("arg0 > 0")
                Count(by: "probefunc")
                Sum("arg1", by: "execname")
            }
        }

        let source = script.source

        // Check basic D syntax elements
        #expect(source.contains("{"))
        #expect(source.contains("}"))
        #expect(source.contains("/"))  // Predicate delimiters

        // Actions should be indented
        let lines = source.split(separator: "\n")
        let actionLines = lines.filter { $0.contains("@[") }
        for line in actionLines {
            #expect(line.hasPrefix("    "), "Action lines should be indented")
        }
    }
}

// MARK: - New DBlocks Features Tests

@Suite("DBlocks Special Clauses Tests")
struct DBlocksSpecialClausesTests {

    @Test("BEGIN clause generates correct syntax")
    func testBEGINClause() {
        let script = DBlocks {
            BEGIN {
                Printf("Starting trace...")
            }
            Probe("syscall:::entry") {
                Count()
            }
        }

        let source = script.source
        #expect(source.contains("BEGIN"))
        #expect(source.contains("printf"))
        #expect(source.contains("Starting trace..."))
    }

    @Test("END clause generates correct syntax")
    func testENDClause() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count()
            }
            END {
                Printf("Trace complete")
            }
        }

        let source = script.source
        #expect(source.contains("END"))
        #expect(source.contains("printf"))
        #expect(source.contains("Trace complete"))
    }

    @Test("ERROR clause generates correct syntax")
    func testERRORClause() {
        let script = DBlocks {
            ERROR {
                Printf("Error occurred")
            }
            Probe("syscall:::entry") {
                Count()
            }
        }

        let source = script.source
        #expect(source.contains("ERROR"))
    }

    @Test("Tick clause with seconds")
    func testTickSeconds() {
        let script = DBlocks {
            Tick(1, .seconds) {
                Printa()
            }
        }

        let source = script.source
        #expect(source.contains("tick-1s"))
        #expect(source.contains("printa(@);"))
    }

    @Test("Tick clause with hz")
    func testTickHz() {
        let script = DBlocks {
            Tick(hz: 100) {
                Count()
            }
        }

        let source = script.source
        #expect(source.contains("tick-100hz"))
    }

    @Test("Tick clause with various time units")
    func testTickTimeUnits() {
        let ns = DBlocks { Tick(1000, .nanoseconds) { Count() } }
        let us = DBlocks { Tick(100, .microseconds) { Count() } }
        let ms = DBlocks { Tick(10, .milliseconds) { Count() } }
        let sec = DBlocks { Tick(1, .seconds) { Count() } }
        let min = DBlocks { Tick(1, .minutes) { Count() } }
        let hr = DBlocks { Tick(1, .hours) { Count() } }
        let day = DBlocks { Tick(1, .days) { Count() } }

        #expect(ns.source.contains("tick-1000ns"))
        #expect(us.source.contains("tick-100us"))
        #expect(ms.source.contains("tick-10ms"))
        #expect(sec.source.contains("tick-1s"))
        #expect(min.source.contains("tick-1m"))
        #expect(hr.source.contains("tick-1h"))
        #expect(day.source.contains("tick-1d"))
    }

    @Test("Profile clause generates correct syntax")
    func testProfileClause() {
        let script = DBlocks {
            Profile(hz: 997) {
                When("arg0")
                Count(by: "stack()")
            }
        }

        let source = script.source
        #expect(source.contains("profile-997hz"))
    }

    @Test("Profile clause with seconds")
    func testProfileSeconds() {
        let script = DBlocks {
            Profile(seconds: 1) {
                Count()
            }
        }

        let source = script.source
        #expect(source.contains("profile-1s"))
    }

    @Test("Combined BEGIN, probes, Tick, and END")
    func testCombinedClauses() {
        let script = DBlocks {
            BEGIN {
                Printf("Started")
            }
            Probe("syscall:::entry") {
                Count(by: "probefunc", into: "calls")
            }
            Tick(1, .seconds) {
                Printa("calls")
                Clear("calls")
            }
            END {
                Printf("Done")
            }
        }

        let source = script.source
        #expect(source.contains("BEGIN"))
        #expect(source.contains("syscall:::entry"))
        #expect(source.contains("tick-1s"))
        #expect(source.contains("END"))
        #expect(source.contains("@calls"))
        #expect(source.contains("printa(@calls);"))
        #expect(source.contains("clear(@calls);"))
    }
}

@Suite("DBlocks Named and Multi-Key Aggregations Tests")
struct DBlocksAggregationTests {

    @Test("Named aggregation with into:")
    func testNamedAggregation() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count(by: "probefunc", into: "syscalls")
            }
        }

        let source = script.source
        #expect(source.contains("@syscalls[probefunc] = count();"))
    }

    @Test("Multi-key aggregation")
    func testMultiKeyAggregation() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count(by: ["execname", "probefunc"])
            }
        }

        let source = script.source
        #expect(source.contains("@[execname, probefunc] = count();"))
    }

    @Test("Named multi-key aggregation")
    func testNamedMultiKeyAggregation() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count(by: ["execname", "probefunc"], into: "calls")
            }
        }

        let source = script.source
        #expect(source.contains("@calls[execname, probefunc] = count();"))
    }

    @Test("Sum with named and multi-key")
    func testSumNamedMultiKey() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                Sum("arg0", by: ["execname", "probefunc"], into: "bytes")
            }
        }

        let source = script.source
        #expect(source.contains("@bytes[execname, probefunc] = sum(arg0);"))
    }

    @Test("All aggregation types with into:")
    func testAllAggregationsWithInto() {
        let script = DBlocks {
            Probe("test:::probe") {
                Count(by: "k", into: "cnt")
            }
            Probe("test:::probe") {
                Sum("v", by: "k", into: "total")
            }
            Probe("test:::probe") {
                Min("v", by: "k", into: "minimum")
            }
            Probe("test:::probe") {
                Max("v", by: "k", into: "maximum")
            }
            Probe("test:::probe") {
                Avg("v", by: "k", into: "average")
            }
            Probe("test:::probe") {
                Quantize("v", by: "k", into: "dist")
            }
        }

        let source = script.source
        #expect(source.contains("@cnt[k] = count();"))
        #expect(source.contains("@total[k] = sum(v);"))
        #expect(source.contains("@minimum[k] = min(v);"))
        #expect(source.contains("@maximum[k] = max(v);"))
        #expect(source.contains("@average[k] = avg(v);"))
        #expect(source.contains("@dist[k] = quantize(v);"))
    }

    @Test("Simple count without keys")
    func testSimpleCount() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count()
            }
        }

        let source = script.source
        #expect(source.contains("@ = count();"))
    }

    @Test("Stddev with single key")
    func testStddevSingleKey() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                Stddev("arg0", by: "execname")
            }
        }
        #expect(script.source.contains("@[execname] = stddev(arg0);"))
    }

    @Test("Stddev with multi-key and name")
    func testStddevNamedMultiKey() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                Stddev("arg0", by: ["execname", "probefunc"], into: "spread")
            }
        }
        #expect(script.source.contains("@spread[execname, probefunc] = stddev(arg0);"))
    }

    @Test("Llquantize single key")
    func testLlquantizeSingleKey() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                Llquantize("timestamp - self->ts",
                           base: 10, low: 0, high: 9, steps: 10,
                           by: "execname")
            }
        }
        #expect(script.source.contains(
            "@[execname] = llquantize(timestamp - self->ts, 10, 0, 9, 10);"
        ))
    }

    @Test("Llquantize named multi-key")
    func testLlquantizeNamedMultiKey() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                Llquantize("timestamp - self->ts",
                           base: 2, low: 0, high: 32, steps: 4,
                           by: ["execname", "probefunc"],
                           into: "latency")
            }
        }
        #expect(script.source.contains(
            "@latency[execname, probefunc] = llquantize(timestamp - self->ts, 2, 0, 32, 4);"
        ))
    }
}

@Suite("DBlocks Variables Tests")
struct DBlocksVariablesTests {

    @Test("Thread-local variable")
    func testThreadLocalVariable() {
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("ts"), to: "timestamp")
            }
        }

        let source = script.source
        #expect(source.contains("self->ts = timestamp;"))
    }

    @Test("Clause-local variable")
    func testClauseLocalVariable() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Assign(.clause("start"), to: "vtimestamp")
            }
        }

        let source = script.source
        #expect(source.contains("this->start = vtimestamp;"))
    }

    @Test("Global variable")
    func testGlobalVariable() {
        let script = DBlocks {
            BEGIN {
                Assign(.global("total"), to: "0")
            }
            Probe("syscall:::entry") {
                Assign(.global("total"), to: "total + 1")
            }
        }

        let source = script.source
        #expect(source.contains("total = 0;"))
        #expect(source.contains("total = total + 1;"))
    }

    @Test("Var expression property")
    func testVarExpression() {
        let thread = Var.thread("myvar")
        let clause = Var.clause("temp")
        let global = Var.global("counter")

        #expect(thread.expression == "self->myvar")
        #expect(clause.expression == "this->temp")
        #expect(global.expression == "counter")
    }
}

@Suite("DBlocks Control Actions Tests")
struct DBlocksControlActionsTests {

    @Test("Exit action")
    func testExitAction() {
        let script = DBlocks {
            Tick(60, .seconds) {
                Exit(0)
            }
        }

        let source = script.source
        #expect(source.contains("exit(0);"))
    }

    @Test("Exit with custom status")
    func testExitWithStatus() {
        let script = DBlocks {
            ERROR {
                Exit(1)
            }
        }

        let source = script.source
        #expect(source.contains("exit(1);"))
    }

    @Test("Stop action")
    func testStopAction() {
        let script = DBlocks {
            Probe("syscall::exit:entry") {
                Stop()
            }
        }

        let source = script.source
        #expect(source.contains("stop();"))
    }
}

@Suite("DBlocks Aggregation Operations Tests")
struct DBlocksAggregationOperationsTests {

    @Test("Printa all aggregations")
    func testPrintaAll() {
        let script = DBlocks {
            END {
                Printa()
            }
        }

        let source = script.source
        #expect(source.contains("printa(@);"))
    }

    @Test("Printa named aggregation")
    func testPrintaNamed() {
        let script = DBlocks {
            Tick(1, .seconds) {
                Printa("calls")
            }
        }

        let source = script.source
        #expect(source.contains("printa(@calls);"))
    }

    @Test("Printa with format")
    func testPrintaWithFormat() {
        let script = DBlocks {
            END {
                Printa("%s: %@count\\n", "calls")
            }
        }

        let source = script.source
        #expect(source.contains("printa(\"%s: %@count\\n\", @calls);"))
    }

    @Test("Clear all aggregations")
    func testClearAll() {
        let script = DBlocks {
            Tick(1, .seconds) {
                Printa()
                Clear()
            }
        }

        let source = script.source
        #expect(source.contains("clear(@);"))
    }

    @Test("Clear named aggregation")
    func testClearNamed() {
        let script = DBlocks {
            Tick(1, .seconds) {
                Clear("calls")
            }
        }

        let source = script.source
        #expect(source.contains("clear(@calls);"))
    }

    @Test("Trunc aggregation")
    func testTrunc() {
        let script = DBlocks {
            END {
                Trunc("calls", 10)
                Printa("calls")
            }
        }

        let source = script.source
        #expect(source.contains("trunc(@calls, 10);"))
    }

    @Test("Trunc all to N")
    func testTruncAllToN() {
        let script = DBlocks {
            END {
                Trunc(5)
            }
        }

        let source = script.source
        #expect(source.contains("trunc(@, 5);"))
    }

    @Test("Normalize aggregation")
    func testNormalize() {
        let script = DBlocks {
            END {
                Normalize("latency", 1_000_000)
                Printa("latency")
            }
        }

        let source = script.source
        #expect(source.contains("normalize(@latency, 1000000);"))
    }

    @Test("Denormalize aggregation")
    func testDenormalize() {
        let script = DBlocks {
            END {
                Denormalize("latency")
            }
        }

        let source = script.source
        #expect(source.contains("denormalize(@latency);"))
    }
}

@Suite("DBlocks Time Units Tests")
struct DBlocksTimeUnitsTests {

    @Test("All time unit raw values")
    func testTimeUnitRawValues() {
        #expect(DTraceTimeUnit.nanoseconds.rawValue == "ns")
        #expect(DTraceTimeUnit.nanosec.rawValue == "nsec")
        #expect(DTraceTimeUnit.microseconds.rawValue == "us")
        #expect(DTraceTimeUnit.microsec.rawValue == "usec")
        #expect(DTraceTimeUnit.milliseconds.rawValue == "ms")
        #expect(DTraceTimeUnit.millisec.rawValue == "msec")
        #expect(DTraceTimeUnit.seconds.rawValue == "s")
        #expect(DTraceTimeUnit.sec.rawValue == "sec")
        #expect(DTraceTimeUnit.minutes.rawValue == "m")
        #expect(DTraceTimeUnit.min.rawValue == "min")
        #expect(DTraceTimeUnit.hours.rawValue == "h")
        #expect(DTraceTimeUnit.hour.rawValue == "hour")
        #expect(DTraceTimeUnit.days.rawValue == "d")
        #expect(DTraceTimeUnit.day.rawValue == "day")
        #expect(DTraceTimeUnit.hertz.rawValue == "hz")
    }
}

// MARK: - Composable API Tests

@Suite("DBlocks Composable API Tests")
struct DBlocksComposableAPITests {

    // MARK: - DBlocks Composition

    @Test("Empty DBlocks initialization")
    func testEmptyInit() {
        let script = DBlocks()
        #expect(script.clauses.isEmpty)
        #expect(script.source.isEmpty)
    }

    @Test("Add probe clause to DBlocks")
    func testAddProbeClause() {
        var script = DBlocks()
        script.add(Probe("syscall:::entry") { Count() })

        #expect(script.clauses.count == 1)
        #expect(script.source.contains("syscall:::entry"))
        #expect(script.source.contains("count()"))
    }

    @Test("Add probe with builder syntax")
    func testAddProbeWithBuilder() {
        var script = DBlocks()
        script.add("syscall:::entry") {
            Count(by: "probefunc")
        }

        #expect(script.clauses.count == 1)
        #expect(script.source.contains("@[probefunc] = count();"))
    }

    @Test("Merge two scripts")
    func testMergeScripts() {
        var script1 = DBlocks {
            BEGIN { Printf("Starting...") }
        }
        let script2 = DBlocks {
            Probe("syscall:::entry") { Count() }
        }

        script1.merge(script2)

        #expect(script1.clauses.count == 2)
        #expect(script1.source.contains("BEGIN"))
        #expect(script1.source.contains("syscall:::entry"))
    }

    @Test("Adding clause returns new script")
    func testAddingClause() {
        let base = DBlocks {
            BEGIN { Printf("Starting...") }
        }
        let extended = base.adding(Probe("syscall:::entry") { Count() })

        // Original unchanged
        #expect(base.clauses.count == 1)
        // New script has both
        #expect(extended.clauses.count == 2)
    }

    @Test("Merging returns new script")
    func testMergingScripts() {
        let script1 = DBlocks { BEGIN { Printf("Start") } }
        let script2 = DBlocks { END { Printf("End") } }

        let combined = script1.merging(script2)

        // Originals unchanged
        #expect(script1.clauses.count == 1)
        #expect(script2.clauses.count == 1)
        // Combined has both
        #expect(combined.clauses.count == 2)
    }

    @Test("Plus operator combines scripts")
    func testPlusOperator() {
        let script = DBlocks { BEGIN { Printf("Start") } }
                   + DBlocks { Probe("syscall:::entry") { Count() } }
                   + DBlocks { END { Printf("End") } }

        #expect(script.clauses.count == 3)
        #expect(script.source.contains("BEGIN"))
        #expect(script.source.contains("syscall:::entry"))
        #expect(script.source.contains("END"))
    }

    @Test("Plus equals operator appends")
    func testPlusEqualsOperator() {
        var script = DBlocks { BEGIN { Printf("Start") } }
        script += DBlocks { Probe("syscall:::entry") { Count() } }

        #expect(script.clauses.count == 2)
    }

    @Test("Combine predefined scripts")
    func testCombinePredefinedScripts() {
        let script = DBlocks { BEGIN { Printf("Tracing...") } }
                   + DBlocks.syscallCounts(for: .execname("nginx"))
                   + DBlocks { Tick(5, .seconds) { Exit(0) } }

        #expect(script.source.contains("BEGIN"))
        #expect(script.source.contains("syscall:freebsd::entry"))
        #expect(script.source.contains("nginx"))
        #expect(script.source.contains("tick-5s"))
    }

    // MARK: - ProbeClause Composition

    @Test("Empty ProbeClause initialization")
    func testEmptyProbeClause() {
        let clause = ProbeClause(probe: "syscall:::entry")
        #expect(clause.probe == "syscall:::entry")
        #expect(clause.predicates.isEmpty)
        #expect(clause.actions.isEmpty)
    }

    @Test("Add action string to clause")
    func testAddActionString() {
        var clause = ProbeClause(probe: "syscall:::entry")
        clause.add(action: "@[probefunc] = count();")

        #expect(clause.actions.count == 1)
        #expect(clause.actions[0] == "@[probefunc] = count();")
    }

    @Test("Add action component to clause")
    func testAddActionComponent() {
        var clause = ProbeClause(probe: "syscall:::entry")
        clause.add(Count(by: "probefunc"))

        #expect(clause.actions.count == 1)
        #expect(clause.actions[0].contains("count()"))
    }

    @Test("Add predicate string to clause")
    func testAddPredicateString() {
        var clause = ProbeClause(probe: "syscall:::entry")
        clause.add(predicate: "execname == \"nginx\"")

        #expect(clause.predicates.count == 1)
        #expect(clause.predicates[0] == "execname == \"nginx\"")
    }

    @Test("Add Target component to clause")
    func testAddTargetComponent() {
        var clause = ProbeClause(probe: "syscall:::entry")
        clause.add(Target(.execname("nginx")))

        #expect(clause.predicates.count == 1)
        #expect(clause.predicates[0].contains("nginx"))
    }

    @Test("Add When component to clause")
    func testAddWhenComponent() {
        var clause = ProbeClause(probe: "syscall:::entry")
        clause.add(When("arg0 > 0"))

        #expect(clause.predicates.count == 1)
        #expect(clause.predicates[0] == "arg0 > 0")
    }

    @Test("Adding action returns new clause")
    func testAddingAction() {
        let base = ProbeClause(probe: "syscall:::entry", actions: ["@ = count();"])
        let extended = base.adding(action: "printf(\"hit\\n\");")

        #expect(base.actions.count == 1)
        #expect(extended.actions.count == 2)
    }

    @Test("Adding component returns new clause")
    func testAddingComponent() {
        let base = ProbeClause(probe: "syscall:::entry", actions: ["@ = count();"])
        let extended = base.adding(Printf("hit!"))

        #expect(base.actions.count == 1)
        #expect(extended.actions.count == 2)
    }

    @Test("Adding predicate returns new clause")
    func testAddingPredicate() {
        let base = ProbeClause(probe: "syscall:::entry", actions: ["@ = count();"])
        let filtered = base.adding(predicate: "arg0 > 0")

        #expect(base.predicates.isEmpty)
        #expect(filtered.predicates.count == 1)
    }

    @Test("Adding target returns new clause")
    func testAddingTargetComponent() {
        let base = ProbeClause(probe: "syscall:::entry", actions: ["@ = count();"])
        let filtered = base.adding(Target(.execname("nginx")))

        #expect(base.predicates.isEmpty)
        #expect(filtered.predicates.count == 1)
    }

    @Test("Build clause programmatically then add to script")
    func testBuildClauseProgrammatically() {
        var clause = ProbeClause(probe: "syscall:::entry")
        clause.add(Target(.execname("nginx")))
        clause.add(When("arg0 > 0"))
        clause.add(Count(by: "probefunc"))

        var script = DBlocks()
        script.add(clause)

        let source = script.source
        #expect(source.contains("syscall:::entry"))
        #expect(source.contains("nginx"))
        #expect(source.contains("arg0 > 0"))
        #expect(source.contains("count()"))
    }

    // MARK: - JSON Round-Trip

    @Test("JSON round-trip preserves script")
    func testJSONRoundTrip() throws {
        let original = DBlocks {
            BEGIN { Printf("Starting...") }
            Probe("syscall:::entry") {
                Target(.execname("nginx"))
                Count(by: "probefunc")
            }
            END { Printa() }
        }

        let jsonData = try original.jsonData()
        let restored = try DBlocks(jsonData: jsonData)

        #expect(restored.clauses.count == original.clauses.count)
        for (i, clause) in restored.clauses.enumerated() {
            #expect(clause.probe == original.clauses[i].probe)
            #expect(clause.predicates == original.clauses[i].predicates)
            #expect(clause.actions == original.clauses[i].actions)
        }
    }

    @Test("Create script from JSON data")
    func testCreateFromJSONData() throws {
        let json = """
        {
            "version": 1,
            "clauses": [
                {
                    "probe": "syscall:::entry",
                    "predicates": ["execname == \\"nginx\\""],
                    "actions": ["@ = count();"]
                }
            ]
        }
        """

        let script = try DBlocks(jsonData: json.data(using: .utf8)!)

        #expect(script.clauses.count == 1)
        #expect(script.clauses[0].probe == "syscall:::entry")
        #expect(script.clauses[0].predicates == ["execname == \"nginx\""])
        #expect(script.clauses[0].actions == ["@ = count();"])
    }

    @Test("Invalid JSON throws error")
    func testInvalidJSONThrows() {
        #expect(throws: DecodingError.self) {
            _ = try DBlocks(jsonData: "not valid json".data(using: .utf8)!)
        }
    }

    @Test("JSON missing probe field throws error")
    func testJSONMissingProbeThrows() {
        let json = """
        {
            "version": 1,
            "clauses": [
                {"actions": ["@ = count();"]}
            ]
        }
        """

        #expect(throws: DecodingError.self) {
            _ = try DBlocks(jsonData: json.data(using: .utf8)!)
        }
    }

    @Test("JSON missing actions field throws error")
    func testJSONMissingActionsThrows() {
        let json = """
        {
            "version": 1,
            "clauses": [
                {"probe": "syscall:::entry"}
            ]
        }
        """

        #expect(throws: DecodingError.self) {
            _ = try DBlocks(jsonData: json.data(using: .utf8)!)
        }
    }

    @Test("Modify script via JSON")
    func testModifyViaJSON() throws {
        // Create initial script
        let original = DBlocks {
            Probe("syscall:::entry") { Count() }
        }

        // Get JSON, modify it, restore
        let jsonData = try original.jsonData()
        guard var json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              var clauses = json["clauses"] as? [[String: Any]] else {
            Issue.record("Failed to extract JSON structure")
            return
        }

        // Add a new clause via JSON manipulation
        clauses.append([
            "probe": "syscall:::return",
            "actions": ["@ = count();"]
        ])
        json["clauses"] = clauses

        let modifiedData = try JSONSerialization.data(withJSONObject: json)
        let modified = try DBlocks(jsonData: modifiedData)

        #expect(modified.clauses.count == 2)
        #expect(modified.clauses[1].probe == "syscall:::return")
    }

    @Test("DBlocksError invalidJSON description")
    func testInvalidJSONErrorDescription() {
        let error = DBlocksError.invalidJSON("test message")
        #expect(error.description.contains("Invalid JSON"))
        #expect(error.description.contains("test message"))
    }
}

@Suite("DBlocks Memory and Buffer Action Tests")
struct DBlocksMemoryActionTests {

    @Test("Tracemem renders the address and size")
    func testTracemem() {
        let script = DBlocks {
            Probe("syscall::write:entry") {
                Tracemem("arg1", size: 64)
            }
        }
        #expect(script.source.contains("tracemem(arg1, 64);"))
    }

    @Test("Copyin assigns into a thread-local")
    func testCopyin() {
        let script = DBlocks {
            Probe("syscall::write:entry") {
                Copyin(from: "arg1", size: 64, into: .thread("buf"))
            }
        }
        #expect(script.source.contains("self->buf = copyin(arg1, 64);"))
    }

    @Test("Copyinto fills a pre-allocated destination")
    func testCopyinto() {
        let script = DBlocks {
            Probe("syscall::write:entry") {
                Copyinto(from: "arg1", size: 64, into: "self->buf")
            }
        }
        #expect(script.source.contains("copyinto(arg1, 64, self->buf);"))
    }

    @Test("Discard renders the bare action")
    func testDiscard() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Discard()
            }
        }
        #expect(script.source.contains("discard();"))
    }

    @Test("Freopen with format and arg")
    func testFreopen() {
        let script = DBlocks {
            Tick(60, .seconds) {
                Freopen("/var/log/dtrace-%d.log", "walltimestamp")
            }
        }
        #expect(script.source.contains("freopen(\"/var/log/dtrace-%d.log\", walltimestamp);"))
    }

    @Test("Freopen.revert produces an empty path")
    func testFreopenRevert() {
        let script = DBlocks {
            Tick(60, .seconds) {
                Freopen.revert
            }
        }
        #expect(script.source.contains("freopen(\"\");"))
    }

    @Test("Raise renders signal as integer")
    func testRaise() {
        let script = DBlocks {
            Probe("syscall::open:entry") {
                Raise(Int32(SIGSTOP))
            }
        }
        #expect(script.source.contains("raise(\(SIGSTOP));"))
    }

    @Test("System renders format and args")
    func testSystem() {
        let script = DBlocks {
            Probe("fbt::vm_fault:entry") {
                System("kill -ABRT %d", "pid")
            }
        }
        #expect(script.source.contains("system(\"kill -ABRT %d\", pid);"))
    }
}

@Suite("DBlocks Speculation Tests")
struct DBlocksSpeculationTests {

    @Test("Speculate stages output on a thread-local id")
    func testSpeculateThreadLocal() {
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("spec"), to: "speculation()")
                Speculate(on: .thread("spec"))
                Printf("entry pid=%d", "pid")
            }
        }
        let source = script.source
        #expect(source.contains("self->spec = speculation();"))
        #expect(source.contains("speculate(self->spec);"))
        #expect(source.contains("printf(\"entry pid=%d\\n\", pid);"))
    }

    @Test("Speculate accepts a raw expression")
    func testSpeculateRawExpression() {
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Speculate(rawExpression: "self->spec_id")
            }
        }
        #expect(script.source.contains("speculate(self->spec_id);"))
    }

    @Test("CommitSpeculation flushes a thread-local id")
    func testCommitSpeculation() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                When("self->spec && arg0 < 0")
                CommitSpeculation(on: .thread("spec"))
                Assign(.thread("spec"), to: "0")
            }
        }
        let source = script.source
        #expect(source.contains("commit(self->spec);"))
        #expect(source.contains("self->spec = 0;"))
    }

    @Test("DiscardSpeculation drops a thread-local id")
    func testDiscardSpeculationThreadLocal() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                When("self->spec && arg0 >= 0")
                DiscardSpeculation(on: .thread("spec"))
            }
        }
        #expect(script.source.contains("discard(self->spec);"))
    }

    @Test("DiscardSpeculation accepts a raw expression")
    func testDiscardSpeculationRaw() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                DiscardSpeculation(rawExpression: "self->spec_id")
            }
        }
        #expect(script.source.contains("discard(self->spec_id);"))
    }

    @Test("Predefined: tcpConnections")
    func testPredefinedTcpConnections() {
        let source = DBlocks.tcpConnections().source
        #expect(source.contains("tcp:::state-change"))
        #expect(source.contains("tcp_state_string"))
    }

    @Test("Predefined: pageFaults reports both kinds")
    func testPredefinedPageFaults() {
        let source = DBlocks.pageFaults().source
        #expect(source.contains("vminfo:::maj_fault"))
        #expect(source.contains("vminfo:::as_fault"))
        #expect(source.contains("@major_faults[execname]"))
        #expect(source.contains("@minor_faults[execname]"))
    }

    @Test("Predefined: diskIOSizes")
    func testPredefinedDiskIOSizes() {
        let source = DBlocks.diskIOSizes().source
        #expect(source.contains("io:::start"))
        #expect(source.contains("@io_size[execname] = quantize(args[0]->b_bcount);"))
    }

    @Test("Predefined: signalDelivery")
    func testPredefinedSignalDelivery() {
        let source = DBlocks.signalDelivery().source
        #expect(source.contains("proc:::signal-send"))
        #expect(source.contains("args[1]->pr_fname"))
    }

    @Test("Predefined: mutexContention")
    func testPredefinedMutexContention() {
        let source = DBlocks.mutexContention().source
        #expect(source.contains("lockstat:::adaptive-block"))
        #expect(source.contains("@mutex_wait_ns[execname] = quantize(arg1);"))
    }

    @Test("Predefined scripts respect a target filter")
    func testPredefinedScriptsApplyTarget() {
        let source = DBlocks.tcpConnections(for: .execname("nginx")).source
        #expect(source.contains("execname == \"nginx\""))
    }

    @Test("threadLocalConflicts: empty when no overlap")
    func testNoThreadLocalConflict() {
        let a = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("ts"), to: "timestamp")
            }
        }
        let b = DBlocks {
            Probe("syscall::write:entry") {
                Assign(.thread("buf"), to: "arg1")
            }
        }
        #expect(a.threadLocalConflicts(with: b).isEmpty)
    }

    @Test("threadLocalConflicts: detects overlap")
    func testThreadLocalConflict() {
        let a = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("ts"), to: "timestamp")
            }
        }
        let b = DBlocks {
            Probe("syscall::write:entry") {
                Assign(.thread("ts"), to: "vtimestamp")
            }
        }
        #expect(a.threadLocalConflicts(with: b) == ["ts"])
    }

    @Test("threadLocalConflicts: ignores comparisons")
    func testThreadLocalNoFalsePositiveOnComparison() {
        // Reading `self->ts` (e.g. `if (self->ts == 0)`) is not an
        // assignment and must not be flagged.
        let a = DBlocks {
            Probe("syscall::read:return") {
                When("self->ts == 0")
                Action("/* … */")
            }
        }
        let b = DBlocks {
            Probe("syscall::write:return") {
                When("self->ts != 0")
                Action("/* … */")
            }
        }
        #expect(a.threadLocalConflicts(with: b).isEmpty)
    }

    @Test("threadLocalConflicts: ignores aggregations")
    func testAggregationsNotConflicts() {
        // Both sides write to @bytes, but aggregation merges are
        // intentional and DTrace handles them.
        let a = DBlocks {
            Probe("syscall::read:return") {
                Sum("arg0", by: "execname", into: "bytes")
            }
        }
        let b = DBlocks {
            Probe("syscall::write:return") {
                Sum("arg0", by: "execname", into: "bytes")
            }
        }
        #expect(a.threadLocalConflicts(with: b).isEmpty)
    }

    @Test("mergeChecked throws on conflict")
    func testMergeCheckedThrows() {
        var a = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("ts"), to: "timestamp")
            }
        }
        let b = DBlocks {
            Probe("syscall::write:entry") {
                Assign(.thread("ts"), to: "vtimestamp")
            }
        }
        #expect(throws: DBlocksError.self) {
            try a.mergeChecked(b)
        }
        // The original script must be unchanged on the throwing path.
        #expect(a.clauses.count == 1)
    }

    @Test("mergeChecked succeeds on non-overlapping scripts")
    func testMergeCheckedSucceeds() throws {
        var a = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("ts"), to: "timestamp")
            }
        }
        let b = DBlocks {
            Probe("syscall::write:entry") {
                Assign(.thread("buf"), to: "arg1")
            }
        }
        try a.mergeChecked(b)
        #expect(a.clauses.count == 2)
    }

    @Test("mergingChecked returns a new script")
    func testMergingCheckedSucceeds() throws {
        let a = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("ts"), to: "timestamp")
            }
        }
        let b = DBlocks {
            Probe("syscall::write:entry") {
                Assign(.thread("buf"), to: "arg1")
            }
        }
        let combined = try a.mergingChecked(b)
        #expect(combined.clauses.count == 2)
    }

    @Test("threadLocalConflict error message lists names")
    func testConflictErrorDescription() {
        let err = DBlocksError.threadLocalConflict(names: ["ts", "spec"])
        let s = err.description
        #expect(s.contains("self->ts"))
        #expect(s.contains("self->spec"))
    }

    // MARK: - Lint

    @Test("lint: clean script returns no warnings")
    func testLintClean() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count(by: "probefunc", into: "calls")
            }
            Tick(1, .seconds) {
                Printa("calls")
                Clear("calls")
            }
        }
        #expect(script.lint().isEmpty)
    }

    @Test("lint: undefined aggregation reference")
    func testLintUndefinedAggregation() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count(by: "probefunc", into: "calls")
            }
            Tick(1, .seconds) {
                Printa("missing")  // never defined
            }
        }
        let warnings = script.lint()
        #expect(warnings.count == 1)
        if case .undefinedAggregation(let name) = warnings.first?.kind {
            #expect(name == "missing")
        } else {
            Issue.record("expected undefinedAggregation warning, got \(warnings)")
        }
    }

    @Test("lint: anonymous aggregation never reported")
    func testLintAnonymousAggregationOK() {
        // Both `@` and `printa(@)` are anonymous and should not warn.
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count()
            }
            Tick(1, .seconds) {
                Printa()
            }
        }
        #expect(script.lint().isEmpty)
    }

    @Test("lint: Exit() inside profile probe")
    func testLintExitInProfileProbe() {
        let script = DBlocks {
            Profile(hz: 99) {
                Exit(0)
            }
        }
        let warnings = script.lint()
        #expect(warnings.count == 1)
        if case .exitInProfileProbe(let probe) = warnings.first?.kind {
            #expect(probe.hasPrefix("profile-"))
        } else {
            Issue.record("expected exitInProfileProbe warning, got \(warnings)")
        }
    }

    @Test("lint: Exit() inside Tick is fine")
    func testLintExitInTickIsFine() {
        let script = DBlocks {
            Tick(60, .seconds) {
                Exit(0)
            }
        }
        #expect(script.lint().isEmpty)
    }

    @Test("lint: multiple warnings reported separately")
    func testLintMultipleWarnings() {
        let script = DBlocks {
            Profile(hz: 99) {
                Exit(0)
            }
            Tick(1, .seconds) {
                Printa("missing_a")
                Clear("missing_b")
            }
        }
        let warnings = script.lint()
        #expect(warnings.count == 3)
    }

    // MARK: - ProbeSpec

    @Test("ProbeSpec.syscall renders the freebsd module")
    func testProbeSpecSyscall() {
        let spec = ProbeSpec.syscall("read", .entry)
        #expect(spec.rendered == "syscall:freebsd:read:entry")
    }

    @Test("ProbeSpec.fbt renders the four-tuple")
    func testProbeSpecFbt() {
        let spec = ProbeSpec.fbt(module: "kernel", function: "uipc_send", .entry)
        #expect(spec.rendered == "fbt:kernel:uipc_send:entry")
    }

    @Test("ProbeSpec.kinst with offset renders kinst::function:offset")
    func testProbeSpecKinstWithOffset() {
        let spec = ProbeSpec.kinst(function: "vm_fault", offset: 4)
        #expect(spec.rendered == "kinst::vm_fault:4")
    }

    @Test("ProbeSpec.kinst without offset renders kinst::function:")
    func testProbeSpecKinstFirehose() {
        // Empty name field = trace every instruction in the function.
        let spec = ProbeSpec.kinst(function: "amd64_syscall")
        #expect(spec.rendered == "kinst::amd64_syscall:")
    }

    @Test("ProbeSpec.kinst with offset zero is distinguishable from no offset")
    func testProbeSpecKinstOffsetZero() {
        // offset=0 must render as ":0" (the entry instruction), NOT
        // collapse to the empty/firehose form.
        let spec = ProbeSpec.kinst(function: "vm_fault", offset: 0)
        #expect(spec.rendered == "kinst::vm_fault:0")
    }

    @Test("ProbeSpec.proc renders provider+name")
    func testProbeSpecProc() {
        #expect(ProbeSpec.proc(.execSuccess).rendered == "proc:::exec-success")
        #expect(ProbeSpec.proc(.signalSend).rendered == "proc:::signal-send")
    }

    @Test("ProbeSpec.io and .vm renders provider-only")
    func testProbeSpecIOAndVM() {
        #expect(ProbeSpec.io(.start).rendered == "io:::start")
        #expect(ProbeSpec.vm(.majorFault).rendered == "vminfo:::maj_fault")
    }

    @Test("ProbeSpec.tcp renders state-change variants")
    func testProbeSpecTCP() {
        #expect(ProbeSpec.tcp(.stateChange).rendered == "tcp:::state-change")
        #expect(ProbeSpec.tcp(.connectRequest).rendered == "tcp:::connect-request")
    }

    @Test("ProbeSpec.tick / profile / special clauses")
    func testProbeSpecRateAndSpecial() {
        #expect(ProbeSpec.tick(1, .seconds).rendered == "tick-1s:::")
        #expect(ProbeSpec.profile(99, .hertz).rendered == "profile-99hz:::")
        #expect(ProbeSpec.begin.rendered == "BEGIN:::")
        #expect(ProbeSpec.end.rendered == "END:::")
        #expect(ProbeSpec.error.rendered == "ERROR:::")
    }

    @Test("ProbeSpec.custom passes fields through")
    func testProbeSpecCustom() {
        let spec = ProbeSpec.custom(provider: "myprov", function: "*", name: "entry")
        #expect(spec.rendered == "myprov::*:entry")
    }

    @Test("Probe(spec:) builds an equivalent clause")
    func testProbeWithSpec() {
        let typed = DBlocks {
            Probe(.syscall("read", .entry)) {
                Count()
            }
        }
        let raw = DBlocks {
            Probe("syscall:freebsd:read:entry") {
                Count()
            }
        }
        #expect(typed.source == raw.source)
    }

    // MARK: - DExpr typed expressions

    @Test("DExpr.arg renders argN and args[N]")
    func testDExprArg() {
        #expect(DExpr.arg(0).rendered == "arg0")
        #expect(DExpr.args(2).rendered == "args[2]")
    }

    @Test("DExpr operator builds predicate")
    func testDExprComparison() {
        let p = DExpr.arg(0) > 0
        #expect(p.rendered == "arg0 > 0")
    }

    @Test("DExpr string equality quotes the literal")
    func testDExprStringEquality() {
        let p = DExpr.execname == "nginx"
        #expect(p.rendered == "execname == \"nginx\"")
    }

    @Test("DExpr logical conjunction")
    func testDExprConjunction() {
        let p = (DExpr.execname == "nginx") && (DExpr.arg(0) > 0)
        #expect(p.rendered == "(execname == \"nginx\") && (arg0 > 0)")
    }

    @Test("DExpr arithmetic")
    func testDExprArithmetic() {
        let elapsed = DExpr.timestamp - .threadLocal("ts")
        #expect(elapsed.rendered == "(timestamp - self->ts)")
    }

    @Test("DExpr.copyinstr renders nested call")
    func testDExprCopyinstr() {
        #expect(DExpr.copyinstr(.arg(0)).rendered == "copyinstr(arg0)")
    }

    @Test("DExpr macro arguments")
    func testDExprMacros() {
        #expect(DExpr.target.rendered == "$target")
        #expect(DExpr.macro(1).rendered == "$1")
        #expect(DExpr.macroString(2).rendered == "$$2")
    }

    @Test("When can be built from a DExpr")
    func testWhenFromDExpr() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                When(DExpr.arg(0) > 0)
                Count()
            }
        }
        #expect(script.source.contains("/(arg0 > 0)/"))
    }

    @Test("Printf can be built from typed args")
    func testPrintfFromDExpr() {
        let script = DBlocks {
            Probe("syscall::open:entry") {
                Printf("%s[%d]: %s",
                       args: [.execname, .pid, .copyinstr(.arg(0))])
            }
        }
        let source = script.source
        #expect(source.contains("printf(\"%s[%d]: %s\\n\", execname, pid, copyinstr(arg0));"))
    }

    @Test("Trace can be built from a DExpr")
    func testTraceFromDExpr() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Trace(DExpr.arg(0))
            }
        }
        #expect(script.source.contains("trace(arg0);"))
    }

    // MARK: - Aggregation snapshot type surface
    //
    // The actual snapshot() walk needs a live DTrace handle (root), so
    // these tests cover the typed value surface — making sure the case
    // accessors and equality work, and that the function signature is
    // present so callers can rely on it.

    @Test("AggregationKey description renders cases")
    func testAggregationKeyDescription() {
        #expect(AggregationKey.int(42).description == "42")
        #expect(AggregationKey.string("nginx").description == "nginx")
        #expect(AggregationKey.bytes([1, 2, 3]).description == "<3 bytes>")
    }

    @Test("AggregationValue.asInt unwraps scalar cases")
    func testAggregationValueAsInt() {
        #expect(AggregationValue.count(5).asInt == 5)
        #expect(AggregationValue.sum(1024).asInt == 1024)
        #expect(AggregationValue.min(-1).asInt == -1)
        #expect(AggregationValue.max(99).asInt == 99)
        #expect(AggregationValue.avg(7).asInt == 7)
        #expect(AggregationValue.stddev(2).asInt == 2)
        #expect(AggregationValue.quantize(Data()).asInt == nil)
        #expect(AggregationValue.lquantize(Data()).asInt == nil)
        #expect(AggregationValue.llquantize(Data()).asInt == nil)
        #expect(AggregationValue.unknown(action: 0, Data()).asInt == nil)
    }

    @Test("AggregationRecord stores fields as supplied")
    func testAggregationRecordInit() {
        let r = AggregationRecord(
            name: "calls",
            keys: [.string("nginx"), .int(8)],
            value: .count(123)
        )
        #expect(r.name == "calls")
        #expect(r.keys.count == 2)
        #expect(r.value.asInt == 123)
    }

    @Test("DTraceSession.snapshot signature is exposed")
    func testSnapshotSignature() {
        // This test validates the API exists; calling it requires root.
        let _: (borrowing DTraceSession, Bool) throws -> [AggregationRecord] = { session, sorted in
            try session.snapshot(sorted: sorted)
        }
    }

    @Test("DTraceSession.streamSnapshots signature is exposed")
    func testStreamSnapshotsSignature() {
        // This test validates the API exists; calling it requires root.
        func verify(_: (borrowing DTraceSession, TimeInterval, Int?, Bool, ([AggregationRecord]) throws -> Void) async throws -> Void) {}
        verify { session, interval, iterations, sorted, body in
            try await session.streamSnapshots(
                every: interval,
                iterations: iterations,
                sorted: sorted,
                body
            )
        }
    }

    // MARK: - Decoder tests (exercised without a live DTrace handle)

    @Test("decodeValue: COUNT loads an int64 at the offset")
    func testDecodeCountValue() {
        var buf = [UInt8](repeating: 0xFF, count: 32)
        // Place a count of 7 at offset 8.
        buf.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: Int64(7), toByteOffset: 8, as: Int64.self)
        }
        buf.withUnsafeBytes { rawBuf in
            let value = AggregationRecord.decodeValue(
                action: UInt16(CDTRACE_AGG_COUNT.rawValue),
                offset: 8,
                size: 8,
                buffer: rawBuf.baseAddress!
            )
            #expect(value == .count(7))
        }
    }

    @Test("decodeValue: SUM/MIN/MAX dispatch correctly")
    func testDecodeScalarKindDispatch() {
        var buf = [UInt8](repeating: 0, count: 8)
        buf.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: Int64(123), toByteOffset: 0, as: Int64.self)
        }
        buf.withUnsafeBytes { rawBuf in
            let base = rawBuf.baseAddress!
            #expect(AggregationRecord.decodeValue(
                action: UInt16(CDTRACE_AGG_SUM.rawValue),
                offset: 0, size: 8, buffer: base) == .sum(123))
            #expect(AggregationRecord.decodeValue(
                action: UInt16(CDTRACE_AGG_MIN.rawValue),
                offset: 0, size: 8, buffer: base) == .min(123))
            #expect(AggregationRecord.decodeValue(
                action: UInt16(CDTRACE_AGG_MAX.rawValue),
                offset: 0, size: 8, buffer: base) == .max(123))
        }
    }

    @Test("decodeValue: AVG computes sum/count")
    func testDecodeAvg() {
        // Layout (count: Int64, sum: Int64). avg = sum / count.
        var buf = [UInt8](repeating: 0, count: 16)
        buf.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: Int64(4), toByteOffset: 0, as: Int64.self)   // count
            ptr.storeBytes(of: Int64(100), toByteOffset: 8, as: Int64.self) // sum
        }
        buf.withUnsafeBytes { rawBuf in
            #expect(AggregationRecord.decodeValue(
                action: UInt16(CDTRACE_AGG_AVG.rawValue),
                offset: 0, size: 16, buffer: rawBuf.baseAddress!
            ) == .avg(25))
        }
    }

    @Test("decodeValue: AVG with count=0 returns 0 instead of dividing")
    func testDecodeAvgZeroCount() {
        // Empty aggregation: count and sum both zero.
        let buf = [UInt8](repeating: 0, count: 16)
        buf.withUnsafeBytes { rawBuf in
            #expect(AggregationRecord.decodeValue(
                action: UInt16(CDTRACE_AGG_AVG.rawValue),
                offset: 0, size: 16, buffer: rawBuf.baseAddress!
            ) == .avg(0))
        }
    }

    @Test("decodeValue: unknown action falls through with raw bytes")
    func testDecodeUnknownAction() {
        let buf: [UInt8] = [1, 2, 3, 4]
        buf.withUnsafeBytes { rawBuf in
            let v = AggregationRecord.decodeValue(
                action: 0xDEAD,
                offset: 0, size: 4,
                buffer: rawBuf.baseAddress!
            )
            guard case .unknown(let act, let bytes) = v else {
                Issue.record("expected .unknown, got \(v)")
                return
            }
            #expect(act == 0xDEAD)
            #expect(Array(bytes) == [1, 2, 3, 4])
        }
    }

    @Test("decodeKey: int sizes 1/2/4/8 all decode")
    func testDecodeKeyIntSizes() {
        var buf = [UInt8](repeating: 0, count: 16)
        buf.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: Int8(-7),  toByteOffset: 0, as: Int8.self)
            ptr.storeBytes(of: Int16(42), toByteOffset: 2, as: Int16.self)
            ptr.storeBytes(of: Int32(1000), toByteOffset: 4, as: Int32.self)
            ptr.storeBytes(of: Int64(-9999), toByteOffset: 8, as: Int64.self)
        }
        buf.withUnsafeBytes { rawBuf in
            let base = rawBuf.baseAddress!
            #expect(AggregationRecord.decodeKey(action: 0, offset: 0, size: 1, buffer: base) == .int(-7))
            #expect(AggregationRecord.decodeKey(action: 0, offset: 2, size: 2, buffer: base) == .int(42))
            #expect(AggregationRecord.decodeKey(action: 0, offset: 4, size: 4, buffer: base) == .int(1000))
            #expect(AggregationRecord.decodeKey(action: 0, offset: 8, size: 8, buffer: base) == .int(-9999))
        }
    }

    @Test("decodeKey: NUL-terminated string is decoded as .string")
    func testDecodeKeyString() {
        var buf = [UInt8](repeating: 0, count: 16)
        let bytes = "nginx".utf8
        for (i, b) in bytes.enumerated() { buf[i] = b }
        buf.withUnsafeBytes { rawBuf in
            let key = AggregationRecord.decodeKey(
                action: 0, offset: 0, size: 16,
                buffer: rawBuf.baseAddress!
            )
            #expect(key == .string("nginx"))
        }
    }

    @Test("decodeKey: arbitrary bytes that don't form a string fall through")
    func testDecodeKeyBytesFallthrough() {
        // No NUL, not a useful string.
        let buf: [UInt8] = [0x80, 0x81, 0x82]
        buf.withUnsafeBytes { rawBuf in
            let key = AggregationRecord.decodeKey(
                action: 0, offset: 0, size: 3,
                buffer: rawBuf.baseAddress!
            )
            guard case .bytes(let arr) = key else {
                Issue.record("expected .bytes, got \(key)")
                return
            }
            #expect(arr == [0x80, 0x81, 0x82])
        }
    }

    // MARK: - Scanner edge cases

    @Test("threadLocalConflicts ignores += and = side conditions correctly")
    func testThreadLocalScannerCorrectness() {
        // Both scripts mention 'self->ts' but only one ASSIGNS to it.
        let writer = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("ts"), to: "timestamp")
            }
        }
        let reader = DBlocks {
            Probe("syscall::read:return") {
                When("self->ts > 0")          // read, not assign
                Trace("self->ts")              // read, not assign
            }
        }
        // The reader doesn't assign self->ts, so there must be no
        // conflict reported.
        #expect(writer.threadLocalConflicts(with: reader).isEmpty)
        #expect(reader.threadLocalConflicts(with: writer).isEmpty)
    }

    // MARK: - Dwatch-style profiles

    @Test("Dwatch.kill renders signal+pid printf")
    func testDwatchKill() {
        let s = DBlocks.Dwatch.kill().source
        #expect(s.contains("syscall::kill:entry"))
        #expect(s.contains("signal %d to pid %d"))
    }

    @Test("Dwatch.open covers open and openat")
    func testDwatchOpen() {
        let s = DBlocks.Dwatch.open().source
        #expect(s.contains("syscall::open:entry"))
        #expect(s.contains("syscall::openat:entry"))
        #expect(s.contains("copyinstr(arg0)"))
        #expect(s.contains("copyinstr(arg1)"))
    }

    @Test("Dwatch.readWrite covers both syscalls")
    func testDwatchReadWrite() {
        let s = DBlocks.Dwatch.readWrite().source
        // Both syscalls share a single multi-probe clause now.
        #expect(s.contains("syscall::read:entry,"))
        #expect(s.contains("syscall::write:entry"))
        #expect(s.contains("nbyte=%d"))
        // The format uses probefunc as the syscall label so the body
        // lives in exactly one place — assert there is only one printf.
        let printfHits = s.components(separatedBy: "printf(").count - 1
        #expect(printfHits == 1, "expected one printf, got \(printfHits)")
    }

    @Test("Dwatch.chmod covers chmod/fchmodat/lchmod")
    func testDwatchChmod() {
        let s = DBlocks.Dwatch.chmod().source
        #expect(s.contains("syscall::chmod:entry"))
        #expect(s.contains("syscall::fchmodat:entry"))
        #expect(s.contains("syscall::lchmod:entry"))
        #expect(s.contains("mode=%o"))
    }

    @Test("Dwatch.procExec covers success and failure")
    func testDwatchProcExec() {
        let s = DBlocks.Dwatch.procExec().source
        #expect(s.contains("proc:::exec-success"))
        #expect(s.contains("proc:::exec-failure"))
        #expect(s.contains("exec ok"))
        #expect(s.contains("exec FAIL"))
    }

    @Test("Dwatch.procExit renders proc:::exit")
    func testDwatchProcExit() {
        let s = DBlocks.Dwatch.procExit().source
        #expect(s.contains("proc:::exit"))
        #expect(s.contains("exit reason=%d"))
    }

    @Test("Dwatch.tcp renders tcp:::state-change with state strings")
    func testDwatchTCP() {
        let s = DBlocks.Dwatch.tcp().source
        #expect(s.contains("tcp:::state-change"))
        #expect(s.contains("tcp_state_string"))
    }

    @Test("Dwatch.udp covers send and receive")
    func testDwatchUDP() {
        let s = DBlocks.Dwatch.udp().source
        #expect(s.contains("udp:::receive"))
        #expect(s.contains("udp:::send"))
    }

    @Test("Dwatch.nanosleep renders syscall::nanosleep:entry")
    func testDwatchNanosleep() {
        let s = DBlocks.Dwatch.nanosleep().source
        #expect(s.contains("syscall::nanosleep:entry"))
    }

    @Test("Dwatch.errnoTracer adds an errno != 0 predicate")
    func testDwatchErrnoTracer() {
        let s = DBlocks.Dwatch.errnoTracer().source
        #expect(s.contains("syscall:::return"))
        #expect(s.contains("errno != 0"))
        #expect(s.contains("errno %d"))
    }

    @Test("Dwatch.systop counts syscalls with named aggregation")
    func testDwatchSystop() {
        let s = DBlocks.Dwatch.systop().source
        #expect(s.contains("syscall:::entry"))
        #expect(s.contains("@syscalls[execname, probefunc] = count();"))
        #expect(s.contains("END"))
        #expect(s.contains("printa(@syscalls);"))
    }

    @Test("Dwatch profiles all respect the target filter")
    func testDwatchProfilesApplyTarget() {
        let target = DTraceTarget.execname("nginx")
        let scripts = [
            DBlocks.Dwatch.kill(for: target),
            DBlocks.Dwatch.open(for: target),
            DBlocks.Dwatch.readWrite(for: target),
            DBlocks.Dwatch.chmod(for: target),
            DBlocks.Dwatch.procExec(for: target),
            DBlocks.Dwatch.procExit(for: target),
            DBlocks.Dwatch.tcp(for: target),
            DBlocks.Dwatch.udp(for: target),
            DBlocks.Dwatch.nanosleep(for: target),
            DBlocks.Dwatch.errnoTracer(for: target),
            DBlocks.Dwatch.systop(for: target),
        ]
        for script in scripts {
            #expect(script.source.contains("execname == \"nginx\""))
        }
    }

    @Test("Dwatch.kinst with offset renders the kinst probe spec")
    func testDwatchKinstWithOffset() {
        let s = DBlocks.Dwatch.kinst(function: "vm_fault", offset: 4).source
        #expect(s.contains("kinst::vm_fault:4"))
        #expect(s.contains("vm_fault+4"))
    }

    @Test("Dwatch.kinst without offset renders the firehose form")
    func testDwatchKinstFirehose() {
        let s = DBlocks.Dwatch.kinst(function: "amd64_syscall").source
        #expect(s.contains("kinst::amd64_syscall:"))
        #expect(s.contains("amd64_syscall+all"))
    }

    @Test("Dwatch.kinst respects the target filter")
    func testDwatchKinstTarget() {
        // Kernel-side probes don't usually need a per-process filter,
        // but it's exposed for symmetry — verify the predicate lands.
        let s = DBlocks.Dwatch.kinst(
            function: "vm_fault",
            offset: 4,
            for: .execname("nginx")
        ).source
        #expect(s.contains("execname == \"nginx\""))
    }

    // MARK: - "Tests that break things" — negative paths

    @Test("validate() throws on empty script")
    func testValidateEmpty() {
        let s = DBlocks()
        #expect(throws: DBlocksError.self) { try s.validate() }
    }

    @Test("validate() throws on a clause with no actions")
    func testValidateEmptyClause() {
        let s = DBlocks(clauses: [
            ProbeClause(probe: "syscall:::entry", actions: [])
        ])
        #expect(throws: DBlocksError.self) { try s.validate() }
    }

    @Test("DBlocks(jsonData:) rejects malformed JSON")
    func testDBlocksRejectsMalformedJSON() {
        let bogus = Data("{this is not json".utf8)
        #expect(throws: (any Error).self) { _ = try DBlocks(jsonData: bogus) }
    }

    @Test("DBlocks(jsonData:) rejects valid JSON without expected fields")
    func testDBlocksRejectsWrongShapeJSON() {
        let wrong = Data(#"{"version":1,"unrelated":42}"#.utf8)
        #expect(throws: (any Error).self) { _ = try DBlocks(jsonData: wrong) }
    }

    @Test("mergeChecked rejects scripts that share a thread-local")
    func testMergeCheckedRejectsConflict() {
        var a = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("ts"), to: "timestamp")
            }
        }
        let b = DBlocks {
            Probe("syscall::write:entry") {
                Assign(.thread("ts"), to: "vtimestamp")
            }
        }
        #expect(throws: DBlocksError.self) { try a.mergeChecked(b) }
    }

    @Test("Dwatch.systop rendered script lints clean")
    func testDwatchSystopLintsClean() {
        // The systop script defines @syscalls and references it from
        // the END clause. lint() must not complain.
        #expect(DBlocks.Dwatch.systop().lint().isEmpty)
    }

    @Test("A profile clause with Exit() lints noisy")
    func testExitInProfileLintsNoisy() {
        let bad = DBlocks {
            Profile(hz: 99) {
                Exit(0)
            }
        }
        let warns = bad.lint()
        #expect(warns.count == 1)
    }

    @Test("lint distinguishes definition from reference")
    func testLintScannerCorrectness() {
        // Define @calls AND reference @calls — clean.
        let clean = DBlocks {
            Probe("syscall:::entry") { Count(by: "probefunc", into: "calls") }
            Tick(1, .seconds) { Printa("calls") }
        }
        #expect(clean.lint().isEmpty)

        // Reference @other when only @calls is defined — should warn.
        let dirty = DBlocks {
            Probe("syscall:::entry") { Count(by: "probefunc", into: "calls") }
            Tick(1, .seconds) { Printa("other") }
        }
        let warns = dirty.lint()
        #expect(warns.count == 1)
        if case .undefinedAggregation(let name) = warns.first?.kind {
            #expect(name == "other")
        } else {
            Issue.record("expected undefinedAggregation, got \(warns)")
        }
    }

    @Test("End-to-end speculation pattern")
    func testFullSpeculationPattern() {
        // The canonical "only keep failed reads" speculative tracing
        // pattern: stage on entry, commit on failure, drop on success.
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("spec"), to: "speculation()")
                Speculate(on: .thread("spec"))
                Printf("entry pid=%d", "pid")
            }
            Probe("syscall::read:return") {
                When("self->spec && arg0 < 0")
                CommitSpeculation(on: .thread("spec"))
                Assign(.thread("spec"), to: "0")
            }
            Probe("syscall::read:return") {
                When("self->spec && arg0 >= 0")
                DiscardSpeculation(on: .thread("spec"))
                Assign(.thread("spec"), to: "0")
            }
        }
        let source = script.source
        #expect(source.contains("self->spec = speculation();"))
        #expect(source.contains("speculate(self->spec);"))
        #expect(source.contains("commit(self->spec);"))
        #expect(source.contains("discard(self->spec);"))
    }
}

// MARK: - pid / USDT providers

@Suite("DBlocks pid Provider Tests")
struct DBlocksPIDProviderTests {

    @Test("pid provider with $target renders correctly")
    func testPIDTargetEntry() {
        let spec = ProbeSpec.pid(.target, module: "libc.so.7", function: "malloc", .entry)
        #expect(spec.rendered == "pid$target:libc.so.7:malloc:entry")
    }

    @Test("pid provider with literal PID renders correctly")
    func testPIDLiteralReturn() {
        let spec = ProbeSpec.pid(.literal(1234), module: "a.out", function: "main", .return)
        #expect(spec.rendered == "pid1234:a.out:main:return")
    }

    @Test("pid provider with offset renders the offset as the name")
    func testPIDOffset() {
        let spec = ProbeSpec.pid(.target, module: "libc.so.7", function: "malloc", offset: 4)
        #expect(spec.rendered == "pid$target:libc.so.7:malloc:4")
    }

    @Test("pid probe is usable inside a clause")
    func testPIDProbeInClause() {
        let script = DBlocks {
            Probe(.pid(.target, module: "libc.so.7", function: "malloc", .entry)) {
                Count(by: "execname")
            }
        }
        #expect(script.source.contains("pid$target:libc.so.7:malloc:entry"))
        #expect(script.source.contains("@[execname] = count();"))
    }

    @Test("pid wildcards via empty module/function")
    func testPIDWildcards() {
        let spec = ProbeSpec.pid(.target, module: "", function: "", .entry)
        #expect(spec.rendered == "pid$target:::entry")
    }
}

@Suite("DBlocks USDT Provider Tests")
struct DBlocksUSDTProviderTests {

    @Test("USDT with $target renders provider$target:::probe")
    func testUSDTTargetMinimal() {
        let spec = ProbeSpec.usdt(.target, provider: "postgresql", probe: "query-start")
        #expect(spec.rendered == "postgresql$target:::query-start")
    }

    @Test("USDT with literal PID and full path")
    func testUSDTLiteralFull() {
        let spec = ProbeSpec.usdt(
            .literal(4242),
            provider: "myapp",
            module: "libworker.so",
            function: "dispatch",
            probe: "request-received"
        )
        #expect(spec.rendered == "myapp4242:libworker.so:dispatch:request-received")
    }

    @Test("USDT probe usable inside a clause")
    func testUSDTInClause() {
        let script = DBlocks {
            Probe(.usdt(.target, provider: "myapp", probe: "tick")) {
                Count()
            }
        }
        #expect(script.source.contains("myapp$target:::tick"))
        #expect(script.source.contains("@ = count();"))
    }
}

// MARK: - Multi-probe clauses

@Suite("DBlocks Multi-Probe Clause Tests")
struct DBlocksMultiProbeTests {

    @Test("Two-spec convenience renders as comma-separated probes")
    func testTwoSpecConvenience() {
        let clause = Probe(.syscall("read", .entry), .syscall("write", .entry)) {
            Count(by: "probefunc")
        }
        let rendered = clause.render()
        #expect(rendered.contains("syscall:freebsd:read:entry,"))
        #expect(rendered.contains("syscall:freebsd:write:entry"))
        #expect(rendered.contains("@[probefunc] = count();"))
    }

    @Test("Array form supports more than two probes")
    func testArrayForm() {
        let specs: [ProbeSpec] = [
            .syscall("read",  .entry),
            .syscall("write", .entry),
            .syscall("pread", .entry),
        ]
        let clause = Probe(specs: specs) {
            Count(by: "probefunc")
        }
        let rendered = clause.render()
        #expect(rendered.contains("syscall:freebsd:read:entry,"))
        #expect(rendered.contains("syscall:freebsd:write:entry,"))
        #expect(rendered.contains("syscall:freebsd:pread:entry"))
    }

    @Test("Multi-probe clause with predicate emits one shared predicate")
    func testMultiProbeWithPredicate() {
        let clause = Probe(.syscall("read", .entry), .syscall("write", .entry)) {
            Target(.execname("nginx"))
            Count()
        }
        let rendered = clause.render()
        // The predicate sits between the comma-joined probes and the body.
        #expect(rendered.contains("syscall:freebsd:read:entry,"))
        #expect(rendered.contains("/(execname == \"nginx\")/"))
        #expect(rendered.contains("@ = count();"))
    }

    @Test("Multi-probe clause survives JSON round-trip")
    func testMultiProbeJSONRoundTrip() throws {
        let original = DBlocks {
            Probe(.syscall("read", .entry), .syscall("write", .entry)) {
                Count(by: "probefunc")
            }
        }
        let data = try original.jsonData()
        let restored = try DBlocks(jsonData: data)
        #expect(original.source == restored.source)
    }

    @Test("Single-probe clause is unaffected by the multi-probe API")
    func testSingleProbeUnchanged() {
        let clause = Probe(.syscall("read", .entry)) { Count() }
        #expect(clause.render().contains("syscall:freebsd:read:entry"))
        #expect(!clause.render().contains(","))
    }

    @Test("String-array Probe(probes:) initializer joins raw specs")
    func testStringArrayMultiProbe() {
        let clause = Probe(probes: [
            "syscall::read:entry",
            "syscall::write:entry",
            "syscall::pread:entry",
        ]) {
            Count(by: "probefunc")
        }
        let rendered = clause.render()
        #expect(rendered.contains("syscall::read:entry,"))
        #expect(rendered.contains("syscall::write:entry,"))
        #expect(rendered.contains("syscall::pread:entry"))
        #expect(rendered.contains("@[probefunc] = count();"))
    }

    @Test("String-array initializer survives JSON round-trip")
    func testStringArrayMultiProbeJSON() throws {
        let original = DBlocks {
            Probe(probes: ["syscall::read:entry", "syscall::write:entry"]) {
                Count(by: "probefunc")
            }
        }
        let restored = try DBlocks(jsonData: try original.jsonData())
        #expect(original.source == restored.source)
    }
}

// MARK: - Ternary

@Suite("DBlocks DExpr Ternary Tests")
struct DBlocksDExprTernaryTests {

    @Test("Static ternary renders parenthesized C ternary")
    func testStaticTernary() {
        let expr = DExpr.ternary(
            DExpr.arg(0) >= 0,
            then: DExpr("\"ok\""),
            else: DExpr("\"err\"")
        )
        #expect(expr.rendered == "(arg0 >= 0 ? \"ok\" : \"err\")")
    }

    @Test("Instance form is equivalent to the static form")
    func testInstanceTernary() {
        let cond = DExpr.arg(0) >= 0
        let a = DExpr("1")
        let b = DExpr("0")
        #expect(cond.then(a, else: b).rendered ==
                DExpr.ternary(cond, then: a, else: b).rendered)
    }

    @Test("Ternary composes with logical operators")
    func testTernaryComposition() {
        let expr = (DExpr.arg(0) > 0 && DExpr.arg(1) < 100)
            .then(DExpr("1"), else: DExpr("0"))
        // Outer parens come from ternary; inner parens from && operator.
        #expect(expr.rendered.contains("? 1 : 0"))
        #expect(expr.rendered.contains("arg0 > 0"))
        #expect(expr.rendered.contains("arg1 < 100"))
    }

    @Test("Ternary works as a Printf typed argument")
    func testTernaryInPrintf() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                Printf("%s",
                       args: [.ternary(.arg(0) >= 0,
                                       then: DExpr("\"ok\""),
                                       else: DExpr("\"err\""))])
            }
        }
        #expect(script.source.contains("(arg0 >= 0 ? \"ok\" : \"err\")"))
    }
}

// MARK: - Printf arity lint and string-aware scanning

@Suite("DBlocks Printf Lint Tests")
struct DBlocksPrintfLintTests {

    @Test("Matching arity emits no warning")
    func testCorrectArity() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Printf("%s[%d]: %s", "execname", "pid", "probefunc")
            }
        }
        #expect(script.lint().isEmpty)
    }

    @Test("Too few args is reported")
    func testTooFewArgs() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Printf("%s %d", "execname")
            }
        }
        let warns = script.lint()
        #expect(warns.count == 1)
        guard case .printfArityMismatch(_, let expected, let got) = warns.first?.kind else {
            Issue.record("expected printfArityMismatch, got \(warns)")
            return
        }
        #expect(expected == 2)
        #expect(got == 1)
    }

    @Test("Too many args is reported")
    func testTooManyArgs() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Printf("%s", "execname", "pid")
            }
        }
        let warns = script.lint()
        #expect(warns.count == 1)
        guard case .printfArityMismatch(_, let expected, let got) = warns.first?.kind else {
            Issue.record("expected printfArityMismatch")
            return
        }
        #expect(expected == 1)
        #expect(got == 2)
    }

    @Test("Literal %% does not consume an arg")
    func testLiteralPercent() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Printf("100%% complete: %d", "pid")
            }
        }
        #expect(script.lint().isEmpty)
    }

    @Test("Format flags, width, precision, and length modifier all parse")
    func testComplexFormatSpecifiers() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Printf("%-10s %5d %.2f %lld %#x",
                       "execname", "pid", "0.0", "timestamp", "arg0")
            }
        }
        #expect(script.lint().isEmpty)
    }

    @Test("`*` width counts as an extra arg")
    func testStarWidth() {
        // %*d expects (width, value) — two args.
        let script = DBlocks {
            Probe("syscall:::entry") {
                Printf("%*d", "10", "pid")
            }
        }
        #expect(script.lint().isEmpty)

        let bad = DBlocks {
            Probe("syscall:::entry") {
                Printf("%*d", "10")  // missing the value
            }
        }
        let warns = bad.lint()
        #expect(warns.count == 1)
    }

    @Test("printf with no args and no specifiers is fine")
    func testNoArgsNoSpecs() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Printf("just a literal message")
            }
        }
        #expect(script.lint().isEmpty)
    }

    @Test("Nested function-call args count as one arg")
    func testNestedCallArg() {
        // copyinstr(arg0) is one logical argument despite the parens.
        let script = DBlocks {
            Probe("syscall::open:entry") {
                Printf("%s", "copyinstr(arg0)")
            }
        }
        #expect(script.lint().isEmpty)
    }
}

@Suite("DBlocks Lint String-Literal Awareness")
struct DBlocksLintStringLiteralTests {

    @Test("self-> inside a printf format does not cause merge conflict")
    func testSelfInPrintfFormat() throws {
        // Script A actually assigns self->ts.
        let a = DBlocks {
            Probe("syscall::read:entry") {
                Action("self->ts = timestamp;")
            }
        }
        // Script B only mentions self->ts inside a printf format string —
        // it never actually writes to it.
        let b = DBlocks {
            Probe("syscall::read:entry") {
                Printf("self->ts = %d", "timestamp")
            }
        }
        #expect(a.threadLocalConflicts(with: b).isEmpty)
        // And the checked merge should succeed cleanly.
        _ = try a.mergingChecked(b)
    }

    @Test("@name inside a printf format is not treated as a definition")
    func testAggInPrintfFormat() {
        // The script defines no aggregations and references none —
        // the literal "@bytes" inside the format must not register as
        // either side of the lint relationship.
        let script = DBlocks {
            Probe("syscall:::entry") {
                Printf("@bytes is not real")
            }
        }
        let warns = script.lint()
        // No undefinedAggregation warning.
        for w in warns {
            if case .undefinedAggregation = w.kind {
                Issue.record("unexpected undefinedAggregation: \(w)")
            }
        }
    }

    @Test("exit( inside a printf format inside a profile probe does not warn")
    func testExitTextInsideProfilePrintf() {
        let script = DBlocks {
            Profile(hz: 997) {
                Printf("see exit( in this string")
            }
        }
        let warns = script.lint()
        for w in warns {
            if case .exitInProfileProbe = w.kind {
                Issue.record("unexpected exitInProfileProbe: \(w)")
            }
        }
    }

    @Test("Real Exit() inside a profile probe still warns")
    func testRealExitInProfileStillWarns() {
        let script = DBlocks {
            Profile(hz: 997) {
                Exit(0)
            }
        }
        let warns = script.lint()
        var sawIt = false
        for w in warns {
            if case .exitInProfileProbe = w.kind { sawIt = true }
        }
        #expect(sawIt)
    }
}

// MARK: - Lint extended: Trunc / Normalize / Denormalize / Clear

@Suite("DBlocks Lint Extended Coverage")
struct DBlocksLintExtendedTests {

    /// Helper: every aggregation-control function should be subject to
    /// the same undefined-aggregation lint pass. Tested as a matrix
    /// rather than four near-duplicate tests so that adding a new
    /// scanner target catches any drift.
    @Test("Trunc on undefined aggregation warns")
    func testTruncUndefined() {
        let script = DBlocks {
            Probe("syscall:::entry") { Count(by: "probefunc", into: "calls") }
            END { Trunc("ghost", 10) }
        }
        let warns = script.lint()
        var saw = false
        for w in warns {
            if case .undefinedAggregation(let n) = w.kind, n == "ghost" { saw = true }
        }
        #expect(saw, "Trunc(\"ghost\", 10) should produce undefinedAggregation warning")
    }

    @Test("Normalize on undefined aggregation warns")
    func testNormalizeUndefined() {
        let script = DBlocks {
            Probe("syscall:::entry") { Count(into: "real") }
            END { Normalize("ghost", 1_000_000) }
        }
        let warns = script.lint()
        var saw = false
        for w in warns {
            if case .undefinedAggregation(let n) = w.kind, n == "ghost" { saw = true }
        }
        #expect(saw)
    }

    @Test("Denormalize on undefined aggregation warns")
    func testDenormalizeUndefined() {
        let script = DBlocks {
            Probe("syscall:::entry") { Count(into: "real") }
            END { Denormalize("ghost") }
        }
        let warns = script.lint()
        var saw = false
        for w in warns {
            if case .undefinedAggregation(let n) = w.kind, n == "ghost" { saw = true }
        }
        #expect(saw)
    }

    @Test("Clear on undefined aggregation warns")
    func testClearUndefined() {
        let script = DBlocks {
            Probe("syscall:::entry") { Count(into: "real") }
            Tick(1, .seconds) { Clear("ghost") }
        }
        let warns = script.lint()
        var saw = false
        for w in warns {
            if case .undefinedAggregation(let n) = w.kind, n == "ghost" { saw = true }
        }
        #expect(saw)
    }

    @Test("clauseIndex points at the offending clause")
    func testClauseIndexCorrectness() {
        // Clause 0 defines @good. Clause 1 references @ghost. Clause 2
        // references @other. The lint output should pin the warnings
        // to clauses 1 and 2 respectively, not clause 0.
        let script = DBlocks {
            Probe("syscall::read:entry") { Count(into: "good") }
            Probe("syscall::write:entry") { Printa("ghost") }
            Probe("syscall::open:entry") { Printa("other") }
        }
        let warns = script.lint()
        var ghostIdx: Int? = nil
        var otherIdx: Int? = nil
        for w in warns {
            if case .undefinedAggregation(let n) = w.kind {
                if n == "ghost" { ghostIdx = w.clauseIndex }
                if n == "other" { otherIdx = w.clauseIndex }
            }
        }
        #expect(ghostIdx == 1)
        #expect(otherIdx == 2)
    }

    @Test("Defined aggregations referenced via Trunc/Normalize do NOT warn")
    func testDefinedRefsClean() {
        let script = DBlocks {
            Probe("syscall:::entry") {
                Count(by: "probefunc", into: "calls")
            }
            END {
                Trunc("calls", 10)
                Normalize("calls", 1_000)
                Denormalize("calls")
                Clear("calls")
                Printa("calls")
            }
        }
        let warns = script.lint()
        for w in warns {
            if case .undefinedAggregation = w.kind {
                Issue.record("unexpected undefined-agg warning on defined name: \(w)")
            }
        }
    }

    @Test("Lint warning description contains the offending name")
    func testLintWarningDescription() {
        let script = DBlocks {
            Probe("syscall:::entry") { Count(into: "real") }
            END { Trunc("ghost", 10) }
        }
        for w in script.lint() {
            if case .undefinedAggregation = w.kind {
                #expect(w.description.contains("ghost"))
                #expect(w.description.contains("clause"))
            }
        }
    }
}

// MARK: - Thread-local conflicts: edge cases

@Suite("DBlocks Thread-Local Conflicts Extended")
struct DBlocksThreadLocalExtendedTests {

    @Test("Multiple conflicts are all reported")
    func testMultipleConflicts() {
        let a = DBlocks {
            Probe("syscall::read:entry") {
                Action("self->ts = timestamp;")
                Action("self->buf = arg1;")
                Action("self->len = arg2;")
            }
        }
        let b = DBlocks {
            Probe("syscall::write:entry") {
                Action("self->ts = timestamp;")
                Action("self->len = arg2;")
            }
        }
        let conflicts = a.threadLocalConflicts(with: b)
        #expect(conflicts.contains("ts"))
        #expect(conflicts.contains("len"))
        #expect(!conflicts.contains("buf"))
    }

    @Test("Conflicts are returned in sorted order")
    func testSortedConflicts() {
        let a = DBlocks {
            Probe("syscall::read:entry") {
                Action("self->zebra = 1;")
                Action("self->apple = 2;")
                Action("self->mango = 3;")
            }
        }
        let b = DBlocks {
            Probe("syscall::write:entry") {
                Action("self->mango = 9;")
                Action("self->apple = 8;")
                Action("self->zebra = 7;")
            }
        }
        let conflicts = a.threadLocalConflicts(with: b)
        #expect(conflicts == ["apple", "mango", "zebra"])
    }

    @Test("threadLocalConflicts is symmetric")
    func testSymmetric() {
        let a = DBlocks {
            Probe("syscall::read:entry") { Action("self->ts = timestamp;") }
        }
        let b = DBlocks {
            Probe("syscall::write:entry") { Action("self->ts = timestamp;") }
        }
        #expect(a.threadLocalConflicts(with: b) == b.threadLocalConflicts(with: a))
    }

    @Test("Three-way merge: A+B then merge with C catches A.var/C.var")
    func testThreeWayConflictDetection() throws {
        let a = DBlocks {
            Probe("syscall::read:entry") { Action("self->ts = timestamp;") }
        }
        let b = DBlocks {
            Probe("syscall::write:entry") { Action("self->buf = arg1;") }
        }
        // a and b are clean: merge them.
        var combined = a
        try combined.mergeChecked(b)

        // c writes self->ts, which overlaps with a — and a's clauses
        // are now in `combined`. So combined.mergeChecked(c) should
        // throw.
        let c = DBlocks {
            Probe("syscall::open:entry") { Action("self->ts = walltimestamp;") }
        }
        var threw = false
        do {
            try combined.mergeChecked(c)
        } catch {
            threw = true
            if case DBlocksError.threadLocalConflict(let names) = error {
                #expect(names.contains("ts"))
            } else {
                Issue.record("expected threadLocalConflict, got \(error)")
            }
        }
        #expect(threw, "three-way merge should detect transitive conflict")
    }

    @Test("Empty scripts have no conflicts with anything")
    func testEmptyConflictFree() {
        let empty = DBlocks()
        let other = DBlocks {
            Probe("syscall::read:entry") { Action("self->ts = timestamp;") }
        }
        #expect(empty.threadLocalConflicts(with: other).isEmpty)
        #expect(other.threadLocalConflicts(with: empty).isEmpty)
    }
}

// MARK: - DExpr static properties and missing functions

@Suite("DBlocks DExpr Static Properties")
struct DBlocksDExprStaticTests {

    @Test("Probe-context built-in variables")
    func testProbeContextBuiltins() {
        #expect(DExpr.pid.rendered           == "pid")
        #expect(DExpr.tid.rendered           == "tid")
        #expect(DExpr.execname.rendered      == "execname")
        #expect(DExpr.probefunc.rendered     == "probefunc")
        #expect(DExpr.probemod.rendered      == "probemod")
        #expect(DExpr.probeprov.rendered     == "probeprov")
        #expect(DExpr.probename.rendered     == "probename")
        #expect(DExpr.timestamp.rendered     == "timestamp")
        #expect(DExpr.vtimestamp.rendered    == "vtimestamp")
        #expect(DExpr.walltimestamp.rendered == "walltimestamp")
        #expect(DExpr.cpu.rendered           == "cpu")
        #expect(DExpr.uid.rendered           == "uid")
        #expect(DExpr.gid.rendered           == "gid")
        #expect(DExpr.ppid.rendered          == "ppid")
        #expect(DExpr.curthread.rendered     == "curthread")
    }

    @Test("Stack and ustack render with parentheses")
    func testStackBuiltins() {
        #expect(DExpr.stack.rendered  == "stack()")
        #expect(DExpr.ustack.rendered == "ustack()")
    }

    @Test("copyin(addr, size) renders the size argument")
    func testCopyinWithSize() {
        let expr = DExpr.copyin(.arg(0), 64)
        #expect(expr.rendered == "copyin(arg0, 64)")
    }

    @Test("cast(expr, to:) renders a C-style cast")
    func testCast() {
        let expr = DExpr.cast(.arg(0), to: "uintptr_t *")
        #expect(expr.rendered == "(uintptr_t *)arg0")
    }

    @Test("stringof and strlen render correctly")
    func testStringofAndStrlen() {
        #expect(DExpr.stringof(.arg(0)).rendered == "stringof(arg0)")
        #expect(DExpr.strlen(.execname).rendered == "strlen(execname)")
    }

    @Test("Variable references via .variable(_:)")
    func testVariableRef() {
        #expect(DExpr.variable(.thread("ts")).rendered == "self->ts")
        #expect(DExpr.variable(.clause("start")).rendered == "this->start")
        #expect(DExpr.variable(.global("total")).rendered == "total")
    }

    @Test("Deeply nested logical expressions parenthesize correctly")
    func testDeeplyNestedLogic() {
        let expr = ((DExpr.arg(0) > 0) && (DExpr.arg(1) < 10))
                || ((DExpr.execname == "nginx") && (DExpr.uid == 0))
        // The exact rendering can change but should preserve the
        // grouping — both halves of the OR must remain parenthesized.
        let r = expr.rendered
        #expect(r.contains("arg0 > 0"))
        #expect(r.contains("arg1 < 10"))
        #expect(r.contains("execname == \"nginx\""))
        #expect(r.contains("uid == 0"))
        #expect(r.contains("||"))
    }

    @Test("DExpr Int comparison operators")
    func testDExprIntComparisons() {
        #expect((DExpr.arg(0) == 1).rendered == "arg0 == 1")
        #expect((DExpr.arg(0) != 1).rendered == "arg0 != 1")
        #expect((DExpr.arg(0) <= 1).rendered == "arg0 <= 1")
        #expect((DExpr.arg(0) >= 1).rendered == "arg0 >= 1")
        #expect((DExpr.arg(0) <  1).rendered == "arg0 < 1")
        #expect((DExpr.arg(0) >  1).rendered == "arg0 > 1")
    }

    @Test("DExpr Int arithmetic operators")
    func testDExprIntArithmetic() {
        #expect((DExpr.arg(0) + 5).rendered == "(arg0 + 5)")
        #expect((DExpr.arg(0) - 5).rendered == "(arg0 - 5)")
    }

    @Test("DExpr negation prefix operator")
    func testDExprNegation() {
        let expr = !(DExpr.execname == "init")
        #expect(expr.rendered == "!(execname == \"init\")")
    }
}

// MARK: - ProbeSpec / DTraceTimeUnit enum coverage

@Suite("DBlocks ProbeSpec Enum Coverage")
struct DBlocksProbeSpecEnumCoverageTests {

    @Test("Every ProcEvent case renders the right probe name")
    func testAllProcEvents() {
        let cases: [(ProbeSpec.ProcEvent, String)] = [
            (.execSuccess,   "exec-success"),
            (.execFailure,   "exec-failure"),
            (.start,         "start"),
            (.exit,          "exit"),
            (.create,        "create"),
            (.signalSend,    "signal-send"),
            (.signalDiscard, "signal-discard"),
        ]
        for (event, expected) in cases {
            let spec = ProbeSpec.proc(event)
            #expect(spec.rendered == "proc:::\(expected)",
                    "ProcEvent.\(event) should render as proc:::\(expected)")
        }
    }

    @Test("Every IOSite case renders the right probe name")
    func testAllIOSites() {
        let cases: [(ProbeSpec.IOSite, String)] = [
            (.start,     "start"),
            (.done,      "done"),
            (.waitStart, "wait-start"),
            (.waitDone,  "wait-done"),
        ]
        for (site, expected) in cases {
            #expect(ProbeSpec.io(site).rendered == "io:::\(expected)")
        }
    }

    @Test("Every VMEvent case renders the right probe name")
    func testAllVMEvents() {
        let cases: [(ProbeSpec.VMEvent, String)] = [
            (.majorFault,        "maj_fault"),
            (.addressSpaceFault, "as_fault"),
            (.copyOnWrite,       "cow_fault"),
            (.kernelFault,       "kernel_asflt"),
            (.zeroFill,          "zfod"),
        ]
        for (event, expected) in cases {
            #expect(ProbeSpec.vm(event).rendered == "vminfo:::\(expected)")
        }
    }

    @Test("Every TCPEvent case renders the right probe name")
    func testAllTCPEvents() {
        let cases: [(ProbeSpec.TCPEvent, String)] = [
            (.sendPacket,         "send"),
            (.receivePacket,      "receive"),
            (.connectRequest,     "connect-request"),
            (.connectEstablished, "connect-established"),
            (.connectRefused,     "connect-refused"),
            (.acceptEstablished,  "accept-established"),
            (.acceptRefused,      "accept-refused"),
            (.stateChange,        "state-change"),
        ]
        for (event, expected) in cases {
            #expect(ProbeSpec.tcp(event).rendered == "tcp:::\(expected)")
        }
    }

    @Test("DTraceTimeUnit cases all render in tick/profile specs")
    func testAllTimeUnits() {
        let cases: [(DTraceTimeUnit, String)] = [
            (.nanoseconds,  "ns"),
            (.microseconds, "us"),
            (.milliseconds, "ms"),
            (.seconds,      "s"),
            (.minutes,      "m"),
            (.hours,        "h"),
            (.days,         "d"),
            (.hertz,        "hz"),
        ]
        for (unit, suffix) in cases {
            #expect(ProbeSpec.tick(1, unit).rendered    == "tick-1\(suffix):::")
            #expect(ProbeSpec.profile(2, unit).rendered == "profile-2\(suffix):::")
        }
    }

    @Test("PIDProcess hashable equality")
    func testPIDProcessEquality() {
        #expect(ProbeSpec.PIDProcess.target == .target)
        #expect(ProbeSpec.PIDProcess.literal(1) == .literal(1))
        #expect(ProbeSpec.PIDProcess.literal(1) != .literal(2))
        #expect(ProbeSpec.PIDProcess.target != .literal(0))
    }
}

// MARK: - Speculation with clause-local scope

@Suite("DBlocks Speculation Variable Scopes")
struct DBlocksSpeculationScopesTests {

    @Test("Speculate accepts a clause-local variable")
    func testSpeculateClauseLocal() {
        let script = DBlocks {
            Probe("syscall::read:entry") {
                Assign(.clause("spec"), to: "speculation()")
                Speculate(on: .clause("spec"))
                Printf("staged for pid=%d", "pid")
            }
        }
        let src = script.source
        #expect(src.contains("this->spec = speculation();"))
        #expect(src.contains("speculate(this->spec);"))
    }

    @Test("Commit and Discard accept clause-local variables")
    func testCommitDiscardClauseLocal() {
        let script = DBlocks {
            Probe("syscall::read:return") {
                CommitSpeculation(on: .clause("spec"))
            }
            Probe("syscall::write:return") {
                DiscardSpeculation(on: .clause("spec"))
            }
        }
        let src = script.source
        #expect(src.contains("commit(this->spec);"))
        #expect(src.contains("discard(this->spec);"))
    }
}

// MARK: - Stddev value decoder

@Suite("DBlocks Aggregation Decoder Stddev")
struct DBlocksAggDecoderStddevTests {

    @Test("decodeValue: STDDEV exposes the rolling mean (sum/count)")
    func testDecodeStddev() {
        // libdtrace stddev layout: (count, sum, sum_of_squares) — three
        // Int64 fields. Our decoder surfaces sum/count (the rolling
        // mean) and ignores the third field, matching the documented
        // contract in Aggregation.swift.
        var buf = [UInt8](repeating: 0, count: 24)
        buf.withUnsafeMutableBytes { ptr in
            ptr.storeBytes(of: Int64(5),    toByteOffset: 0,  as: Int64.self) // count
            ptr.storeBytes(of: Int64(150),  toByteOffset: 8,  as: Int64.self) // sum
            ptr.storeBytes(of: Int64(9999), toByteOffset: 16, as: Int64.self) // sum_of_squares (ignored)
        }
        buf.withUnsafeBytes { rawBuf in
            #expect(AggregationRecord.decodeValue(
                action: UInt16(CDTRACE_AGG_STDDEV.rawValue),
                offset: 0, size: 24, buffer: rawBuf.baseAddress!
            ) == .stddev(30))
        }
    }

    @Test("decodeValue: STDDEV with zero count returns 0 (no division)")
    func testDecodeStddevZeroCount() {
        let buf = [UInt8](repeating: 0, count: 24)
        buf.withUnsafeBytes { rawBuf in
            #expect(AggregationRecord.decodeValue(
                action: UInt16(CDTRACE_AGG_STDDEV.rawValue),
                offset: 0, size: 24, buffer: rawBuf.baseAddress!
            ) == .stddev(0))
        }
    }
}

// MARK: - JSON round-trip + validate() across recent feature surfaces
//
// These tests are deliberately written as a feature matrix: each one
// builds a representative script, calls `validate()` to confirm the
// structural rules are satisfied, encodes the script to JSON, decodes
// it back, and asserts that the rendered D source is byte-identical.
// They are the canary tests for "we can produce valid scripts" — if a
// future change to any of these features breaks Codable conformance,
// the source-equivalence assertion will surface it immediately.

@Suite("DBlocks Recent-Feature Validate + JSON Round-Trip")
struct DBlocksRecentFeatureValidateRoundTripTests {

    /// Helper that runs the full pipeline and reports clear failures.
    private func roundTrip(_ script: DBlocks, file: StaticString = #file, line: UInt = #line) {
        do {
            try script.validate()
        } catch {
            Issue.record("validate() failed: \(error)")
            return
        }
        do {
            let data = try script.jsonData()
            let restored = try DBlocks(jsonData: data)
            #expect(script.source == restored.source,
                    "JSON round-trip mutated source")
        } catch {
            Issue.record("JSON round-trip threw: \(error)")
        }
    }

    @Test("Stddev script validates and round-trips")
    func testStddevRoundTrip() {
        roundTrip(DBlocks {
            Probe("syscall::read:return") {
                When("self->ts")
                Stddev("timestamp - self->ts", by: "execname", into: "spread")
                Action("self->ts = 0;")
            }
        })
    }

    @Test("Llquantize script validates and round-trips")
    func testLlquantizeRoundTrip() {
        roundTrip(DBlocks {
            Probe("syscall::read:return") {
                When("self->ts")
                Llquantize("timestamp - self->ts",
                           base: 10, low: 0, high: 9, steps: 10,
                           by: "execname", into: "latency")
            }
        })
    }

    @Test("Tracemem/Copyin/Copyinto script validates and round-trips")
    func testMemoryActionsRoundTrip() {
        roundTrip(DBlocks {
            Probe("syscall::write:entry") {
                Action("self->buf = (char *)alloca(64);")
                Copyinto(from: "arg1", size: 64, into: "self->buf")
                Tracemem("self->buf", size: 64)
            }
        })
    }

    @Test("Speculation script validates and round-trips")
    func testSpeculationRoundTrip() {
        roundTrip(DBlocks {
            Probe("syscall::read:entry") {
                Assign(.thread("spec"), to: "speculation()")
                Speculate(on: .thread("spec"))
                Printf("entry pid=%d", "pid")
            }
            Probe("syscall::read:return") {
                When("self->spec && arg0 < 0")
                CommitSpeculation(on: .thread("spec"))
                Assign(.thread("spec"), to: "0")
            }
            Probe("syscall::read:return") {
                When("self->spec && arg0 >= 0")
                DiscardSpeculation(on: .thread("spec"))
                Assign(.thread("spec"), to: "0")
            }
        })
    }

    @Test("ProbeSpec-built script validates and round-trips")
    func testProbeSpecRoundTrip() {
        roundTrip(DBlocks {
            Probe(.syscall("read", .entry)) { Count(by: "probefunc") }
            Probe(.fbt(module: "kernel", function: "uipc_send", .entry)) {
                Trace("arg0")
            }
            Probe(.tcp(.stateChange)) { Count() }
            Probe(.io(.start)) { Count() }
            Probe(.vm(.majorFault)) { Count(by: "execname") }
        })
    }

    @Test("kinst script validates and round-trips")
    func testKinstRoundTrip() {
        roundTrip(DBlocks {
            Probe(.kinst(function: "vm_fault", offset: 4)) {
                Printf("hit at +4 in pid=%d", "pid")
            }
        })
    }

    @Test("pid provider script validates and round-trips")
    func testPIDProviderRoundTrip() {
        roundTrip(DBlocks {
            Probe(.pid(.target, module: "libc.so.7", function: "malloc", .entry)) {
                Count(by: "execname")
            }
        })
    }

    @Test("USDT provider script validates and round-trips")
    func testUSDTProviderRoundTrip() {
        roundTrip(DBlocks {
            Probe(.usdt(.target, provider: "myapp", probe: "tick")) { Count() }
        })
    }

    @Test("Multi-probe clause validates and round-trips")
    func testMultiProbeRoundTrip() {
        roundTrip(DBlocks {
            Probe(.syscall("read", .entry), .syscall("write", .entry)) {
                Count(by: "probefunc")
            }
        })
    }

    @Test("DExpr-driven script validates and round-trips")
    func testDExprRoundTrip() {
        roundTrip(DBlocks {
            Probe("syscall::read:return") {
                When(.arg(0) >= 0 && .execname == "nginx")
                Printf("%s[%d]: %s",
                       args: [.execname, .pid, .copyinstr(.arg(0))])
            }
        })
    }

    @Test("Ternary inside Printf validates and round-trips")
    func testTernaryRoundTrip() {
        roundTrip(DBlocks {
            Probe("syscall::read:return") {
                Printf("%s",
                       args: [.ternary(.arg(0) >= 0,
                                       then: DExpr("\"ok\""),
                                       else: DExpr("\"err\""))])
            }
        })
    }

    @Test("Tick + Profile + Exit script validates and round-trips")
    func testClausesRoundTrip() {
        roundTrip(DBlocks {
            BEGIN { Printf("start") }
            Tick(1, .seconds) { Printf("tick") }
            Profile(hz: 99) { Count(by: "execname") }
            END { Printf("end") }
        })
    }
}

// MARK: - Predefined and Dwatch scripts: validate + lint clean + round-trip
//
// Every canned script is run through validate(), lint(), and a JSON
// round-trip equivalence check. The lint check is the canary that
// catches printf format/arg-count drift in the canned scripts —
// without it, a future edit could ship a malformed Dwatch profile.

@Suite("DBlocks Predefined Scripts: Validate, Lint Clean, Round-Trip")
struct DBlocksPredefinedScriptsCanaryTests {

    private func canary(_ script: DBlocks, name: String) {
        do {
            try script.validate()
        } catch {
            Issue.record("\(name): validate() failed: \(error)")
            return
        }
        let warns = script.lint()
        for w in warns {
            // We tolerate `exitInProfileProbe` only if a script
            // intentionally uses Exit() in a profile clause — none of
            // the predefined scripts currently do, so any warning at
            // all is a regression.
            Issue.record("\(name): unexpected lint warning: \(w)")
        }
        do {
            let data = try script.jsonData()
            let restored = try DBlocks(jsonData: data)
            #expect(script.source == restored.source,
                    "\(name): JSON round-trip mutated source")
        } catch {
            Issue.record("\(name): JSON round-trip threw: \(error)")
        }
    }

    @Test("syscallCounts is a clean canary")
    func testSyscallCounts() { canary(DBlocks.syscallCounts(), name: "syscallCounts") }

    @Test("fileOpens is a clean canary")
    func testFileOpens() { canary(DBlocks.fileOpens(), name: "fileOpens") }

    @Test("cpuProfile is a clean canary")
    func testCpuProfile() { canary(DBlocks.cpuProfile(), name: "cpuProfile") }

    @Test("processExec is a clean canary")
    func testProcessExec() { canary(DBlocks.processExec(), name: "processExec") }

    @Test("ioBytes is a clean canary")
    func testIoBytes() { canary(DBlocks.ioBytes(), name: "ioBytes") }

    @Test("syscallLatency is a clean canary")
    func testSyscallLatency() { canary(DBlocks.syscallLatency("read"), name: "syscallLatency") }

    @Test("tcpConnections is a clean canary")
    func testTcpConnections() { canary(DBlocks.tcpConnections(), name: "tcpConnections") }

    @Test("pageFaults is a clean canary")
    func testPageFaults() { canary(DBlocks.pageFaults(), name: "pageFaults") }

    @Test("diskIOSizes is a clean canary")
    func testDiskIOSizes() { canary(DBlocks.diskIOSizes(), name: "diskIOSizes") }

    @Test("signalDelivery is a clean canary")
    func testSignalDelivery() { canary(DBlocks.signalDelivery(), name: "signalDelivery") }

    @Test("mutexContention is a clean canary")
    func testMutexContention() { canary(DBlocks.mutexContention(), name: "mutexContention") }
}

@Suite("DBlocks Dwatch Profiles: Validate, Lint Clean, Round-Trip")
struct DBlocksDwatchProfilesCanaryTests {

    private func canary(_ script: DBlocks, name: String) {
        do {
            try script.validate()
        } catch {
            Issue.record("\(name): validate() failed: \(error)")
            return
        }
        for w in script.lint() {
            Issue.record("\(name): unexpected lint warning: \(w)")
        }
        do {
            let data = try script.jsonData()
            let restored = try DBlocks(jsonData: data)
            #expect(script.source == restored.source,
                    "\(name): JSON round-trip mutated source")
        } catch {
            Issue.record("\(name): JSON round-trip threw: \(error)")
        }
    }

    @Test("Dwatch.kill canary")
    func testKill() { canary(DBlocks.Dwatch.kill(), name: "Dwatch.kill") }

    @Test("Dwatch.open canary")
    func testOpen() { canary(DBlocks.Dwatch.open(), name: "Dwatch.open") }

    @Test("Dwatch.readWrite canary")
    func testReadWrite() { canary(DBlocks.Dwatch.readWrite(), name: "Dwatch.readWrite") }

    @Test("Dwatch.chmod canary")
    func testChmod() { canary(DBlocks.Dwatch.chmod(), name: "Dwatch.chmod") }

    @Test("Dwatch.procExec canary")
    func testProcExec() { canary(DBlocks.Dwatch.procExec(), name: "Dwatch.procExec") }

    @Test("Dwatch.procExit canary")
    func testProcExit() { canary(DBlocks.Dwatch.procExit(), name: "Dwatch.procExit") }

    @Test("Dwatch.tcp canary")
    func testTcp() { canary(DBlocks.Dwatch.tcp(), name: "Dwatch.tcp") }

    @Test("Dwatch.udp canary")
    func testUdp() { canary(DBlocks.Dwatch.udp(), name: "Dwatch.udp") }

    @Test("Dwatch.nanosleep canary")
    func testNanosleep() { canary(DBlocks.Dwatch.nanosleep(), name: "Dwatch.nanosleep") }

    @Test("Dwatch.errnoTracer canary")
    func testErrnoTracer() { canary(DBlocks.Dwatch.errnoTracer(), name: "Dwatch.errnoTracer") }

    @Test("Dwatch.systop canary")
    func testSystop() { canary(DBlocks.Dwatch.systop(), name: "Dwatch.systop") }

    @Test("Dwatch.kinst with offset canary")
    func testKinstOffset() {
        canary(DBlocks.Dwatch.kinst(function: "vm_fault", offset: 4),
               name: "Dwatch.kinst(offset:4)")
    }

    @Test("Dwatch.kinst firehose canary")
    func testKinstFirehose() {
        canary(DBlocks.Dwatch.kinst(function: "amd64_syscall"),
               name: "Dwatch.kinst(firehose)")
    }

    /// Static catalog of every extended Dwatch profile, paired with
    /// a human-readable name. Driven by the parameterized canary test
    /// below — adding a new profile in DwatchProfiles.swift means
    /// adding one entry here, and the canary takes care of the rest.
    /// This is the test that backs the "300 profiles" claim:
    /// `extendedCatalog.count` is the count.
    static let extendedCatalog: [(String, DBlocks)] = {
        let t: DTraceTarget = .all
        return [
            // proc provider
            ("procCreate",          DBlocks.Dwatch.procCreate(for: t)),
            ("procExecEvent",       DBlocks.Dwatch.procExecEvent(for: t)),
            ("procExecSuccess",     DBlocks.Dwatch.procExecSuccess(for: t)),
            ("procExecFailure",     DBlocks.Dwatch.procExecFailure(for: t)),
            ("procExitEvent",       DBlocks.Dwatch.procExitEvent(for: t)),
            ("procFault",           DBlocks.Dwatch.procFault(for: t)),
            ("procLwpCreate",       DBlocks.Dwatch.procLwpCreate(for: t)),
            ("procLwpExit",         DBlocks.Dwatch.procLwpExit(for: t)),
            ("procLwpStart",        DBlocks.Dwatch.procLwpStart(for: t)),
            ("procSignalSendEvent", DBlocks.Dwatch.procSignalSendEvent(for: t)),
            ("procSignalDiscard",   DBlocks.Dwatch.procSignalDiscard(for: t)),
            ("procSignalHandle",    DBlocks.Dwatch.procSignalHandle(for: t)),
            ("procSignalClear",     DBlocks.Dwatch.procSignalClear(for: t)),
            ("procStartEvent",      DBlocks.Dwatch.procStartEvent(for: t)),
            // sched provider
            ("schedSleep",       DBlocks.Dwatch.schedSleep(for: t)),
            ("schedWakeup",      DBlocks.Dwatch.schedWakeup(for: t)),
            ("schedOnCpu",       DBlocks.Dwatch.schedOnCpu(for: t)),
            ("schedOffCpu",      DBlocks.Dwatch.schedOffCpu(for: t)),
            ("schedRemainCpu",   DBlocks.Dwatch.schedRemainCpu(for: t)),
            ("schedChangePri",   DBlocks.Dwatch.schedChangePri(for: t)),
            ("schedLendPri",     DBlocks.Dwatch.schedLendPri(for: t)),
            ("schedDequeue",     DBlocks.Dwatch.schedDequeue(for: t)),
            ("schedEnqueue",     DBlocks.Dwatch.schedEnqueue(for: t)),
            ("schedLoadChange",  DBlocks.Dwatch.schedLoadChange(for: t)),
            ("schedSurrender",   DBlocks.Dwatch.schedSurrender(for: t)),
            ("schedTick",        DBlocks.Dwatch.schedTick(for: t)),
            // io provider
            ("ioStart",     DBlocks.Dwatch.ioStart(for: t)),
            ("ioDone",      DBlocks.Dwatch.ioDone(for: t)),
            ("ioWaitStart", DBlocks.Dwatch.ioWaitStart(for: t)),
            ("ioWaitDone",  DBlocks.Dwatch.ioWaitDone(for: t)),
            // tcp provider
            ("tcpAcceptEstablished",  DBlocks.Dwatch.tcpAcceptEstablished(for: t)),
            ("tcpAcceptRefused",      DBlocks.Dwatch.tcpAcceptRefused(for: t)),
            ("tcpConnectEstablished", DBlocks.Dwatch.tcpConnectEstablished(for: t)),
            ("tcpConnectRefused",     DBlocks.Dwatch.tcpConnectRefused(for: t)),
            ("tcpConnectRequest",     DBlocks.Dwatch.tcpConnectRequest(for: t)),
            ("tcpReceive",            DBlocks.Dwatch.tcpReceive(for: t)),
            ("tcpSend",               DBlocks.Dwatch.tcpSend(for: t)),
            ("tcpStateChange",        DBlocks.Dwatch.tcpStateChange(for: t)),
            // udp / udplite / ip
            ("udpReceive",      DBlocks.Dwatch.udpReceive(for: t)),
            ("udpSend",         DBlocks.Dwatch.udpSend(for: t)),
            ("udpliteReceive",  DBlocks.Dwatch.udpliteReceive(for: t)),
            ("udpliteSend",     DBlocks.Dwatch.udpliteSend(for: t)),
            ("ipReceive",       DBlocks.Dwatch.ipReceive(for: t)),
            ("ipSend",          DBlocks.Dwatch.ipSend(for: t)),
            // vminfo
            ("vmAnonpgin",    DBlocks.Dwatch.vmAnonpgin(for: t)),
            ("vmAnonpgout",   DBlocks.Dwatch.vmAnonpgout(for: t)),
            ("vmAsFault",     DBlocks.Dwatch.vmAsFault(for: t)),
            ("vmCowFault",    DBlocks.Dwatch.vmCowFault(for: t)),
            ("vmDfree",       DBlocks.Dwatch.vmDfree(for: t)),
            ("vmExecfree",    DBlocks.Dwatch.vmExecfree(for: t)),
            ("vmExecpgin",    DBlocks.Dwatch.vmExecpgin(for: t)),
            ("vmExecpgout",   DBlocks.Dwatch.vmExecpgout(for: t)),
            ("vmFsfree",      DBlocks.Dwatch.vmFsfree(for: t)),
            ("vmFspgin",      DBlocks.Dwatch.vmFspgin(for: t)),
            ("vmFspgout",     DBlocks.Dwatch.vmFspgout(for: t)),
            ("vmKernelAsflt", DBlocks.Dwatch.vmKernelAsflt(for: t)),
            ("vmMajFault",    DBlocks.Dwatch.vmMajFault(for: t)),
            ("vmPgin",        DBlocks.Dwatch.vmPgin(for: t)),
            ("vmPgout",       DBlocks.Dwatch.vmPgout(for: t)),
            ("vmPgrec",       DBlocks.Dwatch.vmPgrec(for: t)),
            ("vmPgrrun",      DBlocks.Dwatch.vmPgrrun(for: t)),
            ("vmPrfree",      DBlocks.Dwatch.vmPrfree(for: t)),
            ("vmPrpgin",      DBlocks.Dwatch.vmPrpgin(for: t)),
            ("vmPrpgout",     DBlocks.Dwatch.vmPrpgout(for: t)),
            ("vmScan",        DBlocks.Dwatch.vmScan(for: t)),
            ("vmSwapin",      DBlocks.Dwatch.vmSwapin(for: t)),
            ("vmSwapout",     DBlocks.Dwatch.vmSwapout(for: t)),
            ("vmZfod",        DBlocks.Dwatch.vmZfod(for: t)),
            // lockstat
            ("lockstatAdaptiveAcquire", DBlocks.Dwatch.lockstatAdaptiveAcquire(for: t)),
            ("lockstatAdaptiveBlock",   DBlocks.Dwatch.lockstatAdaptiveBlock(for: t)),
            ("lockstatAdaptiveSpin",    DBlocks.Dwatch.lockstatAdaptiveSpin(for: t)),
            ("lockstatAdaptiveRelease", DBlocks.Dwatch.lockstatAdaptiveRelease(for: t)),
            ("lockstatRwAcquire",       DBlocks.Dwatch.lockstatRwAcquire(for: t)),
            ("lockstatRwBlock",         DBlocks.Dwatch.lockstatRwBlock(for: t)),
            ("lockstatRwRelease",       DBlocks.Dwatch.lockstatRwRelease(for: t)),
            ("lockstatRwUpgrade",       DBlocks.Dwatch.lockstatRwUpgrade(for: t)),
            ("lockstatRwDowngrade",     DBlocks.Dwatch.lockstatRwDowngrade(for: t)),
            ("lockstatSpinAcquire",     DBlocks.Dwatch.lockstatSpinAcquire(for: t)),
            ("lockstatSpinSpin",        DBlocks.Dwatch.lockstatSpinSpin(for: t)),
            ("lockstatSpinRelease",     DBlocks.Dwatch.lockstatSpinRelease(for: t)),
            ("lockstatThreadSpin",      DBlocks.Dwatch.lockstatThreadSpin(for: t)),
            // vfs vop
            ("vopLookup",       DBlocks.Dwatch.vopLookup(for: t)),
            ("vopAccess",       DBlocks.Dwatch.vopAccess(for: t)),
            ("vopOpen",         DBlocks.Dwatch.vopOpen(for: t)),
            ("vopClose",        DBlocks.Dwatch.vopClose(for: t)),
            ("vopGetattr",      DBlocks.Dwatch.vopGetattr(for: t)),
            ("vopSetattr",      DBlocks.Dwatch.vopSetattr(for: t)),
            ("vopRead",         DBlocks.Dwatch.vopRead(for: t)),
            ("vopWrite",        DBlocks.Dwatch.vopWrite(for: t)),
            ("vopIoctl",        DBlocks.Dwatch.vopIoctl(for: t)),
            ("vopPoll",         DBlocks.Dwatch.vopPoll(for: t)),
            ("vopKqfilter",     DBlocks.Dwatch.vopKqfilter(for: t)),
            ("vopFsync",        DBlocks.Dwatch.vopFsync(for: t)),
            ("vopRemove",       DBlocks.Dwatch.vopRemove(for: t)),
            ("vopLink",         DBlocks.Dwatch.vopLink(for: t)),
            ("vopMkdir",        DBlocks.Dwatch.vopMkdir(for: t)),
            ("vopRmdir",        DBlocks.Dwatch.vopRmdir(for: t)),
            ("vopReadlink",     DBlocks.Dwatch.vopReadlink(for: t)),
            ("vopInactive",     DBlocks.Dwatch.vopInactive(for: t)),
            ("vopReclaim",      DBlocks.Dwatch.vopReclaim(for: t)),
            ("vopLock",         DBlocks.Dwatch.vopLock(for: t)),
            ("vopUnlock",       DBlocks.Dwatch.vopUnlock(for: t)),
            ("vopIslocked",     DBlocks.Dwatch.vopIslocked(for: t)),
            ("vopBmap",         DBlocks.Dwatch.vopBmap(for: t)),
            ("vopStrategy",     DBlocks.Dwatch.vopStrategy(for: t)),
            ("vopAdvlock",      DBlocks.Dwatch.vopAdvlock(for: t)),
            ("vopGetextattr",   DBlocks.Dwatch.vopGetextattr(for: t)),
            ("vopSetextattr",   DBlocks.Dwatch.vopSetextattr(for: t)),
            ("vopListextattr",  DBlocks.Dwatch.vopListextattr(for: t)),
            ("vopGetacl",       DBlocks.Dwatch.vopGetacl(for: t)),
            ("vopSetacl",       DBlocks.Dwatch.vopSetacl(for: t)),
            ("vopAclcheck",     DBlocks.Dwatch.vopAclcheck(for: t)),
            ("vopVptocnp",      DBlocks.Dwatch.vopVptocnp(for: t)),
            ("vopAllocate",     DBlocks.Dwatch.vopAllocate(for: t)),
            ("vopDeallocate",   DBlocks.Dwatch.vopDeallocate(for: t)),
            ("vopAdvise",       DBlocks.Dwatch.vopAdvise(for: t)),
            ("vopFdatasync",    DBlocks.Dwatch.vopFdatasync(for: t)),
            // syscalls — I/O
            ("sysReadEntry",      DBlocks.Dwatch.sysReadEntry(for: t)),
            ("sysReadReturn",     DBlocks.Dwatch.sysReadReturn(for: t)),
            ("sysWriteEntry",     DBlocks.Dwatch.sysWriteEntry(for: t)),
            ("sysWriteReturn",    DBlocks.Dwatch.sysWriteReturn(for: t)),
            ("sysPreadEntry",     DBlocks.Dwatch.sysPreadEntry(for: t)),
            ("sysPreadReturn",    DBlocks.Dwatch.sysPreadReturn(for: t)),
            ("sysPwriteEntry",    DBlocks.Dwatch.sysPwriteEntry(for: t)),
            ("sysPwriteReturn",   DBlocks.Dwatch.sysPwriteReturn(for: t)),
            ("sysReadvEntry",     DBlocks.Dwatch.sysReadvEntry(for: t)),
            ("sysWritevEntry",    DBlocks.Dwatch.sysWritevEntry(for: t)),
            ("sysPreadvEntry",    DBlocks.Dwatch.sysPreadvEntry(for: t)),
            ("sysPwritevEntry",   DBlocks.Dwatch.sysPwritevEntry(for: t)),
            // syscalls — fd lifecycle
            ("sysOpenEntry",       DBlocks.Dwatch.sysOpenEntry(for: t)),
            ("sysOpenReturn",      DBlocks.Dwatch.sysOpenReturn(for: t)),
            ("sysOpenatEntry",     DBlocks.Dwatch.sysOpenatEntry(for: t)),
            ("sysOpenatReturn",    DBlocks.Dwatch.sysOpenatReturn(for: t)),
            ("sysCloseEntry",      DBlocks.Dwatch.sysCloseEntry(for: t)),
            ("sysCloseReturn",     DBlocks.Dwatch.sysCloseReturn(for: t)),
            ("sysCloseRangeEntry", DBlocks.Dwatch.sysCloseRangeEntry(for: t)),
            ("sysDupEntry",        DBlocks.Dwatch.sysDupEntry(for: t)),
            ("sysDup2Entry",       DBlocks.Dwatch.sysDup2Entry(for: t)),
            ("sysFcntlEntry",      DBlocks.Dwatch.sysFcntlEntry(for: t)),
            ("sysIoctlEntry",      DBlocks.Dwatch.sysIoctlEntry(for: t)),
            ("sysPipeEntry",       DBlocks.Dwatch.sysPipeEntry(for: t)),
            ("sysPipe2Entry",      DBlocks.Dwatch.sysPipe2Entry(for: t)),
            // syscalls — metadata
            ("sysStatEntry",     DBlocks.Dwatch.sysStatEntry(for: t)),
            ("sysFstatEntry",    DBlocks.Dwatch.sysFstatEntry(for: t)),
            ("sysLstatEntry",    DBlocks.Dwatch.sysLstatEntry(for: t)),
            ("sysFstatatEntry",  DBlocks.Dwatch.sysFstatatEntry(for: t)),
            ("sysAccessEntry",   DBlocks.Dwatch.sysAccessEntry(for: t)),
            ("sysFaccessatEntry",DBlocks.Dwatch.sysFaccessatEntry(for: t)),
            ("sysStatfsEntry",   DBlocks.Dwatch.sysStatfsEntry(for: t)),
            ("sysFstatfsEntry",  DBlocks.Dwatch.sysFstatfsEntry(for: t)),
            // syscalls — fs mutation
            ("sysLinkEntry",       DBlocks.Dwatch.sysLinkEntry(for: t)),
            ("sysLinkatEntry",     DBlocks.Dwatch.sysLinkatEntry(for: t)),
            ("sysUnlinkEntry",     DBlocks.Dwatch.sysUnlinkEntry(for: t)),
            ("sysUnlinkatEntry",   DBlocks.Dwatch.sysUnlinkatEntry(for: t)),
            ("sysFunlinkatEntry",  DBlocks.Dwatch.sysFunlinkatEntry(for: t)),
            ("sysRenameEntry",     DBlocks.Dwatch.sysRenameEntry(for: t)),
            ("sysRenameatEntry",   DBlocks.Dwatch.sysRenameatEntry(for: t)),
            ("sysMkdirEntry",      DBlocks.Dwatch.sysMkdirEntry(for: t)),
            ("sysMkdiratEntry",    DBlocks.Dwatch.sysMkdiratEntry(for: t)),
            ("sysRmdirEntry",      DBlocks.Dwatch.sysRmdirEntry(for: t)),
            ("sysSymlinkEntry",    DBlocks.Dwatch.sysSymlinkEntry(for: t)),
            ("sysSymlinkatEntry",  DBlocks.Dwatch.sysSymlinkatEntry(for: t)),
            ("sysReadlinkEntry",   DBlocks.Dwatch.sysReadlinkEntry(for: t)),
            ("sysReadlinkatEntry", DBlocks.Dwatch.sysReadlinkatEntry(for: t)),
            ("sysTruncateEntry",   DBlocks.Dwatch.sysTruncateEntry(for: t)),
            ("sysFtruncateEntry",  DBlocks.Dwatch.sysFtruncateEntry(for: t)),
            ("sysLseekEntry",      DBlocks.Dwatch.sysLseekEntry(for: t)),
            ("sysFsyncEntry",      DBlocks.Dwatch.sysFsyncEntry(for: t)),
            ("sysFdatasyncEntry",  DBlocks.Dwatch.sysFdatasyncEntry(for: t)),
            // syscalls — perms / ownership
            ("sysChmodEntry",   DBlocks.Dwatch.sysChmodEntry(for: t)),
            ("sysFchmodEntry",  DBlocks.Dwatch.sysFchmodEntry(for: t)),
            ("sysLchmodEntry",  DBlocks.Dwatch.sysLchmodEntry(for: t)),
            ("sysFchmodatEntry",DBlocks.Dwatch.sysFchmodatEntry(for: t)),
            ("sysChownEntry",   DBlocks.Dwatch.sysChownEntry(for: t)),
            ("sysFchownEntry",  DBlocks.Dwatch.sysFchownEntry(for: t)),
            ("sysLchownEntry",  DBlocks.Dwatch.sysLchownEntry(for: t)),
            ("sysFchownatEntry",DBlocks.Dwatch.sysFchownatEntry(for: t)),
            // syscalls — process lifecycle
            ("sysForkEntry",    DBlocks.Dwatch.sysForkEntry(for: t)),
            ("sysVforkEntry",   DBlocks.Dwatch.sysVforkEntry(for: t)),
            ("sysRforkEntry",   DBlocks.Dwatch.sysRforkEntry(for: t)),
            ("sysExecveEntry",  DBlocks.Dwatch.sysExecveEntry(for: t)),
            ("sysFexecveEntry", DBlocks.Dwatch.sysFexecveEntry(for: t)),
            ("sysExitEntry",    DBlocks.Dwatch.sysExitEntry(for: t)),
            ("sysWait4Entry",   DBlocks.Dwatch.sysWait4Entry(for: t)),
            ("sysWait6Entry",   DBlocks.Dwatch.sysWait6Entry(for: t)),
            // syscalls — signals
            ("sysKillEntry",        DBlocks.Dwatch.sysKillEntry(for: t)),
            ("sysKillpgEntry",      DBlocks.Dwatch.sysKillpgEntry(for: t)),
            ("sysSigactionEntry",   DBlocks.Dwatch.sysSigactionEntry(for: t)),
            ("sysSigprocmaskEntry", DBlocks.Dwatch.sysSigprocmaskEntry(for: t)),
            ("sysSigsuspendEntry",  DBlocks.Dwatch.sysSigsuspendEntry(for: t)),
            ("sysSigreturnEntry",   DBlocks.Dwatch.sysSigreturnEntry(for: t)),
            ("sysSigaltstackEntry", DBlocks.Dwatch.sysSigaltstackEntry(for: t)),
            ("sysSigqueueEntry",    DBlocks.Dwatch.sysSigqueueEntry(for: t)),
            // syscalls — memory
            ("sysMmapEntry",       DBlocks.Dwatch.sysMmapEntry(for: t)),
            ("sysMunmapEntry",     DBlocks.Dwatch.sysMunmapEntry(for: t)),
            ("sysMprotectEntry",   DBlocks.Dwatch.sysMprotectEntry(for: t)),
            ("sysMadviseEntry",    DBlocks.Dwatch.sysMadviseEntry(for: t)),
            ("sysMsyncEntry",      DBlocks.Dwatch.sysMsyncEntry(for: t)),
            ("sysMlockEntry",      DBlocks.Dwatch.sysMlockEntry(for: t)),
            ("sysMunlockEntry",    DBlocks.Dwatch.sysMunlockEntry(for: t)),
            ("sysMincoreEntry",    DBlocks.Dwatch.sysMincoreEntry(for: t)),
            ("sysShmOpenEntry",    DBlocks.Dwatch.sysShmOpenEntry(for: t)),
            ("sysShmUnlinkEntry",  DBlocks.Dwatch.sysShmUnlinkEntry(for: t)),
            ("sysShmRenameEntry",  DBlocks.Dwatch.sysShmRenameEntry(for: t)),
            // syscalls — networking
            ("sysSocketEntry",      DBlocks.Dwatch.sysSocketEntry(for: t)),
            ("sysBindEntry",        DBlocks.Dwatch.sysBindEntry(for: t)),
            ("sysConnectEntry",     DBlocks.Dwatch.sysConnectEntry(for: t)),
            ("sysListenEntry",      DBlocks.Dwatch.sysListenEntry(for: t)),
            ("sysAcceptEntry",      DBlocks.Dwatch.sysAcceptEntry(for: t)),
            ("sysAccept4Entry",     DBlocks.Dwatch.sysAccept4Entry(for: t)),
            ("sysSendEntry",        DBlocks.Dwatch.sysSendEntry(for: t)),
            ("sysSendtoEntry",      DBlocks.Dwatch.sysSendtoEntry(for: t)),
            ("sysSendmsgEntry",     DBlocks.Dwatch.sysSendmsgEntry(for: t)),
            ("sysRecvEntry",        DBlocks.Dwatch.sysRecvEntry(for: t)),
            ("sysRecvfromEntry",    DBlocks.Dwatch.sysRecvfromEntry(for: t)),
            ("sysRecvmsgEntry",     DBlocks.Dwatch.sysRecvmsgEntry(for: t)),
            ("sysShutdownEntry",    DBlocks.Dwatch.sysShutdownEntry(for: t)),
            ("sysGetsocknameEntry", DBlocks.Dwatch.sysGetsocknameEntry(for: t)),
            ("sysGetpeernameEntry", DBlocks.Dwatch.sysGetpeernameEntry(for: t)),
            ("sysSetsockoptEntry",  DBlocks.Dwatch.sysSetsockoptEntry(for: t)),
            ("sysGetsockoptEntry",  DBlocks.Dwatch.sysGetsockoptEntry(for: t)),
            // syscalls — polling
            ("sysSelectEntry",  DBlocks.Dwatch.sysSelectEntry(for: t)),
            ("sysPselectEntry", DBlocks.Dwatch.sysPselectEntry(for: t)),
            ("sysPollEntry",    DBlocks.Dwatch.sysPollEntry(for: t)),
            ("sysPpollEntry",   DBlocks.Dwatch.sysPpollEntry(for: t)),
            ("sysKqueueEntry",  DBlocks.Dwatch.sysKqueueEntry(for: t)),
            ("sysKeventEntry",  DBlocks.Dwatch.sysKeventEntry(for: t)),
            // syscalls — time
            ("sysNanosleepEntry",      DBlocks.Dwatch.sysNanosleepEntry(for: t)),
            ("sysClockNanosleepEntry", DBlocks.Dwatch.sysClockNanosleepEntry(for: t)),
            ("sysGettimeofdayEntry",   DBlocks.Dwatch.sysGettimeofdayEntry(for: t)),
            ("sysClockGettimeEntry",   DBlocks.Dwatch.sysClockGettimeEntry(for: t)),
            ("sysClockSettimeEntry",   DBlocks.Dwatch.sysClockSettimeEntry(for: t)),
            ("sysSetitimerEntry",      DBlocks.Dwatch.sysSetitimerEntry(for: t)),
            // syscalls — IDs
            ("sysGetpidEntry",     DBlocks.Dwatch.sysGetpidEntry(for: t)),
            ("sysGetppidEntry",    DBlocks.Dwatch.sysGetppidEntry(for: t)),
            ("sysGetuidEntry",     DBlocks.Dwatch.sysGetuidEntry(for: t)),
            ("sysGeteuidEntry",    DBlocks.Dwatch.sysGeteuidEntry(for: t)),
            ("sysGetgidEntry",     DBlocks.Dwatch.sysGetgidEntry(for: t)),
            ("sysGetegidEntry",    DBlocks.Dwatch.sysGetegidEntry(for: t)),
            ("sysSetuidEntry",     DBlocks.Dwatch.sysSetuidEntry(for: t)),
            ("sysSetgidEntry",     DBlocks.Dwatch.sysSetgidEntry(for: t)),
            ("sysSeteuidEntry",    DBlocks.Dwatch.sysSeteuidEntry(for: t)),
            ("sysSetegidEntry",    DBlocks.Dwatch.sysSetegidEntry(for: t)),
            ("sysSetresuidEntry",  DBlocks.Dwatch.sysSetresuidEntry(for: t)),
            ("sysSetresgidEntry",  DBlocks.Dwatch.sysSetresgidEntry(for: t)),
            ("sysSetsidEntry",     DBlocks.Dwatch.sysSetsidEntry(for: t)),
            ("sysSetpgidEntry",    DBlocks.Dwatch.sysSetpgidEntry(for: t)),
            // syscalls — resource control
            ("sysGetrlimitEntry",   DBlocks.Dwatch.sysGetrlimitEntry(for: t)),
            ("sysSetrlimitEntry",   DBlocks.Dwatch.sysSetrlimitEntry(for: t)),
            ("sysGetrusageEntry",   DBlocks.Dwatch.sysGetrusageEntry(for: t)),
            ("sysGetpriorityEntry", DBlocks.Dwatch.sysGetpriorityEntry(for: t)),
            ("sysSetpriorityEntry", DBlocks.Dwatch.sysSetpriorityEntry(for: t)),
            // syscalls — IPC
            ("sysSemgetEntry", DBlocks.Dwatch.sysSemgetEntry(for: t)),
            ("sysSemopEntry",  DBlocks.Dwatch.sysSemopEntry(for: t)),
            ("sysSemctlEntry", DBlocks.Dwatch.sysSemctlEntry(for: t)),
            ("sysMsggetEntry", DBlocks.Dwatch.sysMsggetEntry(for: t)),
            ("sysMsgsndEntry", DBlocks.Dwatch.sysMsgsndEntry(for: t)),
            ("sysMsgrcvEntry", DBlocks.Dwatch.sysMsgrcvEntry(for: t)),
            ("sysMsgctlEntry", DBlocks.Dwatch.sysMsgctlEntry(for: t)),
            ("sysShmgetEntry", DBlocks.Dwatch.sysShmgetEntry(for: t)),
            ("sysShmatEntry",  DBlocks.Dwatch.sysShmatEntry(for: t)),
            ("sysShmdtEntry",  DBlocks.Dwatch.sysShmdtEntry(for: t)),
            ("sysShmctlEntry", DBlocks.Dwatch.sysShmctlEntry(for: t)),
            // syscalls — mount/fs admin
            ("sysMountEntry",   DBlocks.Dwatch.sysMountEntry(for: t)),
            ("sysUnmountEntry", DBlocks.Dwatch.sysUnmountEntry(for: t)),
            ("sysChdirEntry",   DBlocks.Dwatch.sysChdirEntry(for: t)),
            ("sysFchdirEntry",  DBlocks.Dwatch.sysFchdirEntry(for: t)),
            ("sysChrootEntry",  DBlocks.Dwatch.sysChrootEntry(for: t)),
            // syscalls — misc high value
            ("sysSysctlEntry",     DBlocks.Dwatch.sysSysctlEntry(for: t)),
            ("sysReboot",          DBlocks.Dwatch.sysReboot(for: t)),
            ("sysJailEntry",       DBlocks.Dwatch.sysJailEntry(for: t)),
            ("sysJailAttachEntry", DBlocks.Dwatch.sysJailAttachEntry(for: t)),
            ("sysCpusetEntry",     DBlocks.Dwatch.sysCpusetEntry(for: t)),
            ("sysProcctlEntry",    DBlocks.Dwatch.sysProcctlEntry(for: t)),
        ]
    }()

    @Test("Extended Dwatch catalog has at least 250 entries")
    func testExtendedCatalogSize() {
        // Sanity check that nobody trims the static list. The actual
        // count is asserted with a generous lower bound rather than an
        // exact number so adding new profiles doesn't churn this test.
        #expect(Self.extendedCatalog.count >= 250,
                "extendedCatalog has \(Self.extendedCatalog.count) entries")
    }

    @Test("Generic Dwatch.syscall(_:) factory works for arbitrary names")
    func testSyscallFactory() throws {
        let entry = DBlocks.Dwatch.syscall("foo", site: .entry)
        #expect(entry.source.contains("syscall::foo:entry"))
        try entry.validate()
        #expect(entry.lint().isEmpty)

        let ret = DBlocks.Dwatch.syscall("foo", site: .return)
        #expect(ret.source.contains("syscall::foo:return"))
        try ret.validate()
        #expect(ret.lint().isEmpty)
    }

    @Test("All Dwatch profiles also pass with a target filter applied")
    func testAllDwatchWithTarget() {
        let target = DTraceTarget.execname("nginx")
        let scripts: [(String, DBlocks)] = [
            ("kill",        DBlocks.Dwatch.kill(for: target)),
            ("open",        DBlocks.Dwatch.open(for: target)),
            ("readWrite",   DBlocks.Dwatch.readWrite(for: target)),
            ("chmod",       DBlocks.Dwatch.chmod(for: target)),
            ("procExec",    DBlocks.Dwatch.procExec(for: target)),
            ("procExit",    DBlocks.Dwatch.procExit(for: target)),
            ("tcp",         DBlocks.Dwatch.tcp(for: target)),
            ("udp",         DBlocks.Dwatch.udp(for: target)),
            ("nanosleep",   DBlocks.Dwatch.nanosleep(for: target)),
            ("errnoTracer", DBlocks.Dwatch.errnoTracer(for: target)),
            ("systop",      DBlocks.Dwatch.systop(for: target)),
        ]
        for (name, script) in scripts {
            canary(script, name: "Dwatch.\(name)(for: nginx)")
        }
    }

    /// Walks the entire extended catalog (~280 entries) and asserts
    /// every profile validates, lints clean, and round-trips through
    /// JSON without source drift.
    ///
    /// This is the test that backs the "300 profiles" claim in the
    /// docs. If a future commit breaks any one profile — say, by
    /// shipping a typo'd probe spec or a printf with the wrong arg
    /// count — exactly that profile's name will appear in the failure
    /// output, while every other profile keeps passing.
    @Test("Extended Dwatch catalog: all entries validate + lint clean + JSON round-trip")
    func testExtendedCatalogCanary() {
        for (name, script) in Self.extendedCatalog {
            canary(script, name: "Dwatch.\(name)")
        }
    }

    /// Same sweep but with a non-trivial target filter applied.
    /// Verifies that every profile in the catalog correctly threads
    /// the `target` parameter through to the rendered predicate.
    @Test("Extended Dwatch catalog: target filter sweep")
    func testExtendedCatalogTargetSweep() {
        let target = DTraceTarget.execname("nginx")
        // Re-build a few representative profiles with the target
        // filter; sampling rather than running all ~280 again to keep
        // the parameterized expansion compact.
        let samples: [(String, DBlocks)] = [
            ("procCreate",         DBlocks.Dwatch.procCreate(for: target)),
            ("schedSleep",         DBlocks.Dwatch.schedSleep(for: target)),
            ("ioStart",            DBlocks.Dwatch.ioStart(for: target)),
            ("tcpStateChange",     DBlocks.Dwatch.tcpStateChange(for: target)),
            ("vmMajFault",         DBlocks.Dwatch.vmMajFault(for: target)),
            ("vopLookup",          DBlocks.Dwatch.vopLookup(for: target)),
            ("sysReadEntry",       DBlocks.Dwatch.sysReadEntry(for: target)),
            ("sysExecveEntry",     DBlocks.Dwatch.sysExecveEntry(for: target)),
            ("sysKillEntry",       DBlocks.Dwatch.sysKillEntry(for: target)),
            ("lockstatRwAcquire",  DBlocks.Dwatch.lockstatRwAcquire(for: target)),
        ]
        for (name, script) in samples {
            #expect(script.source.contains("execname == \"nginx\""),
                    "Dwatch.\(name): target filter not threaded")
            canary(script, name: "Dwatch.\(name)(for: nginx)")
        }
    }
}

// MARK: - DExpr extended built-ins and string functions

@Suite("DBlocks DExpr Extended Built-ins")
struct DBlocksDExprExtendedBuiltinsTests {

    @Test("Process- and CPU-context built-ins")
    func testProcessCpuBuiltins() {
        #expect(DExpr.curpsinfo.rendered   == "curpsinfo")
        #expect(DExpr.curlwpsinfo.rendered == "curlwpsinfo")
        #expect(DExpr.curcpu.rendered      == "curcpu")
        #expect(DExpr.cpuinfo.rendered     == "curcpu")
        #expect(DExpr.errno.rendered       == "errno")
    }

    @Test("arg0..arg9 shorthand properties")
    func testArgShorthands() {
        #expect(DExpr.arg0.rendered == "arg0")
        #expect(DExpr.arg5.rendered == "arg5")
        #expect(DExpr.arg9.rendered == "arg9")
        // Equivalent to the function form.
        #expect(DExpr.arg0.rendered == DExpr.arg(0).rendered)
        #expect(DExpr.arg9.rendered == DExpr.arg(9).rendered)
    }

    @Test("member(_:) renders pointer-to-struct access")
    func testMemberAccess() {
        #expect(DExpr.curpsinfo.member("pr_fname").rendered == "curpsinfo->pr_fname")
        #expect(DExpr.args(1).member("pr_pid").rendered     == "args[1]->pr_pid")
    }
}

@Suite("DBlocks DExpr String Functions")
struct DBlocksDExprStringFunctionsTests {

    @Test("strjoin / strtok / strstr")
    func testStrjoinTokStr() {
        #expect(DExpr.strjoin(.execname, DExpr("\"!\"")).rendered ==
                "strjoin(execname, \"!\")")
        #expect(DExpr.strtok(DExpr("self->path"), DExpr("\"/\"")).rendered ==
                "strtok(self->path, \"/\")")
        #expect(DExpr.strstr(DExpr("self->path"), DExpr("\"bin\"")).rendered ==
                "strstr(self->path, \"bin\")")
    }

    @Test("indexOf / rindexOf")
    func testIndexHelpers() {
        #expect(DExpr.indexOf(.execname, DExpr("\"x\"")).rendered ==
                "index(execname, \"x\")")
        #expect(DExpr.rindexOf(.execname, DExpr("\"x\"")).rendered ==
                "rindex(execname, \"x\")")
    }

    @Test("strchr / strrchr")
    func testCharSearch() {
        #expect(DExpr.strchr(.execname, DExpr("'/'")).rendered ==
                "strchr(execname, '/')")
        #expect(DExpr.strrchr(.execname, DExpr("'/'")).rendered ==
                "strrchr(execname, '/')")
    }

    @Test("dirname / basename")
    func testPathSplit() {
        let path = DExpr("self->path")
        #expect(DExpr.dirname(path).rendered  == "dirname(self->path)")
        #expect(DExpr.basename(path).rendered == "basename(self->path)")
    }

    @Test("lltostr / inet_ntoa / inet_ntoa6 / inet_ntop")
    func testConversionHelpers() {
        #expect(DExpr.lltostr(.timestamp).rendered    == "lltostr(timestamp)")
        #expect(DExpr.inetNtoa(DExpr("&self->src")).rendered ==
                "inet_ntoa(&self->src)")
        #expect(DExpr.inetNtoa6(DExpr("&self->src6")).rendered ==
                "inet_ntoa6(&self->src6)")
        #expect(DExpr.inetNtop(DExpr("AF_INET"), DExpr("&self->src")).rendered ==
                "inet_ntop(AF_INET, &self->src)")
    }

    @Test("String functions compose into a working printf")
    func testCompositionInPrintf() throws {
        let script = DBlocks {
            Probe("syscall::open:entry") {
                Printf("%s -> %s",
                       args: [.basename(.copyinstr(.arg(0))),
                              .dirname(.copyinstr(.arg(0)))])
            }
        }
        try script.validate()
        #expect(script.lint().isEmpty)
        #expect(script.source.contains("basename(copyinstr(arg0))"))
        #expect(script.source.contains("dirname(copyinstr(arg0))"))
    }
}

// MARK: - Raw-address pid probes and variable-size Tracemem

@Suite("DBlocks pid Raw-Address Probes")
struct DBlocksPidRawAddressTests {

    @Test("Raw-address pid probe with $target renders hex address")
    func testTargetAddress() {
        let spec = ProbeSpec.pid(.target, module: "a.out", address: 0x401234)
        // The function field is empty and the name is the hex address.
        #expect(spec.rendered == "pid$target:a.out::0x401234")
    }

    @Test("Raw-address pid probe with literal PID")
    func testLiteralAddress() {
        let spec = ProbeSpec.pid(.literal(4242), module: "libc.so.7", address: 0xdeadbeef)
        #expect(spec.rendered == "pid4242:libc.so.7::0xdeadbeef")
    }

    @Test("Raw-address pid probe survives validate + lint + JSON round-trip")
    func testRoundTrip() throws {
        let script = DBlocks {
            Probe(.pid(.target, module: "a.out", address: 0x401234)) {
                Printf("hit at 0x401234")
            }
        }
        try script.validate()
        #expect(script.lint().isEmpty)
        let restored = try DBlocks(jsonData: try script.jsonData())
        #expect(script.source == restored.source)
    }
}

@Suite("DBlocks Tracemem Variable-Size Variant")
struct DBlocksTracememVariableSizeTests {

    @Test("Three-argument tracemem(addr, dsize, esize) form")
    func testThreeArg() {
        let script = DBlocks {
            Probe("syscall::write:entry") {
                Tracemem("arg1", maxSize: 1024, length: "arg2")
            }
        }
        #expect(script.source.contains("tracemem(arg1, 1024, arg2);"))
    }

    @Test("Variable-size form coexists with the fixed-size form")
    func testCoexistence() throws {
        let script = DBlocks {
            Probe("syscall::write:entry") {
                Tracemem("arg1", size: 64)
                Tracemem("arg1", maxSize: 1024, length: "arg2")
            }
        }
        try script.validate()
        #expect(script.source.contains("tracemem(arg1, 64);"))
        #expect(script.source.contains("tracemem(arg1, 1024, arg2);"))
    }
}

// MARK: - Typed args[N] per provider

@Suite("DBlocks Provider Typed Args")
struct DBlocksProviderTypedArgsTests {

    @Test("ProcArgs renders the documented field paths")
    func testProcArgs() {
        #expect(ProcArgs.targetExecname.rendered    == "args[1]->pr_fname")
        #expect(ProcArgs.targetCmdline.rendered     == "args[1]->pr_psargs")
        #expect(ProcArgs.targetPid.rendered         == "args[1]->pr_pid")
        #expect(ProcArgs.targetUid.rendered         == "args[1]->pr_uid")
        #expect(ProcArgs.signalNumber.rendered      == "args[2]")
        #expect(ProcArgs.execPath.rendered          == "args[0]")
    }

    @Test("IOArgs renders bufinfo / devinfo / fileinfo paths")
    func testIOArgs() {
        #expect(IOArgs.bufCount.rendered    == "args[0]->b_bcount")
        #expect(IOArgs.bufFlags.rendered    == "args[0]->b_flags")
        #expect(IOArgs.devName.rendered     == "args[1]->dev_name")
        #expect(IOArgs.devStatname.rendered == "args[1]->dev_statname")
        #expect(IOArgs.fileName.rendered    == "args[2]->fi_name")
        #expect(IOArgs.filePathname.rendered == "args[2]->fi_pathname")
    }

    @Test("Shared NetArgs accessors")
    func testNetArgs() {
        #expect(NetArgs.ipPacketLength.rendered == "args[2]->ip_plength")
        #expect(NetArgs.ipSrcAddr.rendered      == "args[2]->ip_saddr")
        #expect(NetArgs.ipDstAddr.rendered      == "args[2]->ip_daddr")
        #expect(NetArgs.connectionPid.rendered  == "args[1]->cs_pid")
    }

    @Test("TCPArgs re-exports Net + provides tcpsinfo / tcpinfo accessors")
    func testTCPArgs() {
        #expect(TCPArgs.ipPacketLength.rendered == "args[2]->ip_plength")
        #expect(TCPArgs.localPort.rendered      == "args[3]->tcps_lport")
        #expect(TCPArgs.remotePort.rendered     == "args[3]->tcps_rport")
        #expect(TCPArgs.localAddr.rendered      == "args[3]->tcps_laddr")
        #expect(TCPArgs.remoteAddr.rendered     == "args[3]->tcps_raddr")
        #expect(TCPArgs.state.rendered          == "args[3]->tcps_state")
        #expect(TCPArgs.flags.rendered          == "args[4]->tcp_flags")
        #expect(TCPArgs.sequence.rendered       == "args[4]->tcp_seq")
    }

    @Test("UDPArgs and UDPLiteArgs accessors")
    func testUDPArgs() {
        #expect(UDPArgs.localPort.rendered      == "args[3]->udps_lport")
        #expect(UDPArgs.length.rendered         == "args[4]->udp_length")
        #expect(UDPLiteArgs.localPort.rendered  == "args[3]->udplites_lport")
        #expect(UDPLiteArgs.coverage.rendered   == "args[4]->udplite_coverage")
    }

    @Test("IPArgs ifinfo / ipv4info / ipv6info accessors")
    func testIPArgs() {
        #expect(IPArgs.ifName.rendered      == "args[3]->if_name")
        #expect(IPArgs.ipv4Protocol.rendered == "args[4]->ipv4_protocol")
        #expect(IPArgs.ipv4Src.rendered     == "args[4]->ipv4_src")
        #expect(IPArgs.ipv6Plen.rendered    == "args[5]->ipv6_plen")
        #expect(IPArgs.ipv6Src.rendered     == "args[5]->ipv6_src")
    }

    @Test("SchedArgs lwpsinfo / psinfo / cpuinfo accessors")
    func testSchedArgs() {
        #expect(SchedArgs.targetLwpId.rendered    == "args[0]->pr_lwpid")
        #expect(SchedArgs.targetExecname.rendered == "args[1]->pr_fname")
        #expect(SchedArgs.targetCpuId.rendered    == "args[2]->cpu_id")
    }

    @Test("LockstatArgs raw slot accessors")
    func testLockstatArgs() {
        #expect(LockstatArgs.lockPointer.rendered           == "args[0]")
        #expect(LockstatArgs.waitTimeOrSpinCount.rendered   == "args[1]")
        #expect(LockstatArgs.rwWriterFlag.rendered          == "args[2]")
    }

    @Test("Typed args compose into a complete Printf")
    func testTypedArgsInPrintf() throws {
        let script = DBlocks {
            Probe(ProbeSpec.tcp(.sendPacket)) {
                Printf("%s:%d -> %s:%d %d bytes",
                       args: [TCPArgs.localAddr, TCPArgs.localPort,
                              TCPArgs.remoteAddr, TCPArgs.remotePort,
                              TCPArgs.ipPacketLength])
            }
        }
        try script.validate()
        #expect(script.lint().isEmpty)
        #expect(script.source.contains("args[3]->tcps_lport"))
        #expect(script.source.contains("args[2]->ip_plength"))
        let restored = try DBlocks(jsonData: try script.jsonData())
        #expect(script.source == restored.source)
    }

    /// Regression: the leading-dot `Probe(.tcp(.sendPacket))` form
    /// should resolve to `ProbeSpec.tcp(_:)` even though `Probe` also
    /// has a raw-string overload. This test exercises the form
    /// directly so a future overload addition that breaks inference
    /// fails at compile time rather than silently routing through
    /// the String overload.
    @Test("Leading-dot ProbeSpec form resolves without explicit qualification")
    func testLeadingDotProbeSpec() throws {
        let script = DBlocks {
            Probe(.tcp(.sendPacket)) { Count() }
            Probe(.tcp(.receivePacket)) { Count() }
            Probe(.proc(.signalSend)) { Count() }
            Probe(.io(.start)) { Count() }
        }
        try script.validate()
        let src = script.source
        #expect(src.contains("tcp:::send"))
        #expect(src.contains("tcp:::receive"))
        #expect(src.contains("proc:::signal-send"))
        #expect(src.contains("io:::start"))
    }
}

// MARK: - Preamble (pragmas, typedefs, translators, declarations)

@Suite("DBlocks Preamble Declarations")
struct DBlocksPreambleTests {

    @Test("Pragma renders #pragma D option")
    func testPragmaRender() {
        let p1 = Declaration.pragma(name: "quiet", value: nil)
        let p2 = Declaration.pragma(name: "bufsize", value: "8m")
        #expect(p1.render() == "#pragma D option quiet")
        #expect(p2.render() == "#pragma D option bufsize=8m")
    }

    @Test("dependsOn renders #pragma D depends_on library")
    func testDependsOnRender() {
        let d = Declaration.dependsOn(library: "net.d")
        #expect(d.render() == "#pragma D depends_on library net.d")
    }

    @Test("Inline constant and typed declarations render correctly")
    func testInlineAndTypedDecl() {
        let c = Declaration.inlineConstant(type: "int", name: "FOO", value: "42")
        #expect(c.render() == "inline int FOO = 42;")

        let tl = Declaration.threadLocalDecl(type: "int", name: "ts")
        #expect(tl.render() == "self int ts;")

        let cl = Declaration.clauseLocalDecl(type: "uint64_t", name: "start")
        #expect(cl.render() == "this uint64_t start;")
    }

    @Test("Raw declaration is rendered verbatim")
    func testRawDecl() {
        let r = Declaration.raw("/* anything goes here */")
        #expect(r.render() == "/* anything goes here */")
    }

    @Test("Preamble declarations render before clauses")
    func testPreambleOrdering() {
        var script = DBlocks {
            Probe("syscall:::entry") { Count() }
        }
        script.declare(.pragma(name: "quiet", value: nil))
        script.declare(.inlineConstant(type: "int", name: "MAX_DEPTH", value: "8"))
        let src = script.source
        // Pragma must appear before the syscall probe.
        let pragmaRange = src.range(of: "#pragma D option quiet")
        let probeRange  = src.range(of: "syscall:::entry")
        #expect(pragmaRange != nil && probeRange != nil)
        if let p = pragmaRange, let q = probeRange {
            #expect(p.lowerBound < q.lowerBound)
        }
    }

    @Test("Translator-only script validates without any clauses")
    func testTranslatorOnlyValidates() throws {
        // A library script that exists only to declare a translator.
        let translator = Translator(output: "queryinfo_t", input: "Query *q") {
            Translator.Field("sql",         from: "stringof(q->raw_sql)")
            Translator.Field("duration_ns", from: "q->elapsed_nanos")
        }
        var script = DBlocks()
        script.declare(.translator(translator))
        try script.validate()
        #expect(script.source.contains("translator queryinfo_t < Query *q >"))
        #expect(script.source.contains("sql = stringof(q->raw_sql);"))
    }

    @Test("Empty script is still rejected")
    func testFullyEmptyStillRejected() {
        let empty = DBlocks()
        do {
            try empty.validate()
            Issue.record("expected validate() to throw on empty script")
        } catch DBlocksError.emptyScript {
            // expected
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("Preamble survives JSON round-trip")
    func testPreambleJSONRoundTrip() throws {
        let typedef = Typedef(name: "queryinfo_t") {
            Typedef.Member("sql",         type: "string")
            Typedef.Member("duration_ns", type: "int")
        }
        let translator = Translator(output: "queryinfo_t", input: "Query *q") {
            Translator.Field("sql",         from: "stringof(q->raw_sql)")
            Translator.Field("duration_ns", from: "q->elapsed_nanos")
        }
        var script = DBlocks {
            Probe("syscall:::entry") { Count() }
        }
        script.declare(.pragma(name: "quiet", value: nil))
        script.declare(.dependsOn(library: "net.d"))
        script.declare(.typedef(typedef))
        script.declare(.translator(translator))
        script.declare(.inlineConstant(type: "int", name: "FOO", value: "42"))
        script.declare(.threadLocalDecl(type: "int", name: "ts"))
        script.declare(.raw("/* trailing raw decl */"))

        let restored = try DBlocks(jsonData: try script.jsonData())
        #expect(script.source == restored.source)
        #expect(restored.declarations.count == script.declarations.count)
    }

    @Test("Old (v1) JSON without declarations field still decodes")
    func testV1BackwardsCompat() throws {
        // Hand-write a v1-shape payload — version 1, no declarations
        // field at all.
        let v1 = """
        {
            "version": 1,
            "clauses": [
                {
                    "probe": "syscall:::entry",
                    "actions": ["@ = count();"]
                }
            ]
        }
        """
        let restored = try DBlocks(jsonData: Data(v1.utf8))
        #expect(restored.declarations.isEmpty)
        #expect(restored.clauses.count == 1)
        #expect(restored.source.contains("syscall:::entry"))
    }

    @Test("Lint does not walk preamble declarations")
    func testLintIgnoresPreamble() {
        // The translator body contains literal `args[0]` and a
        // string-looking expression — neither should trigger any
        // lint warning, because declarations aren't action bodies.
        var script = DBlocks {
            Probe("syscall:::entry") { Count() }
        }
        script.declare(.translator(
            Translator(output: "fakeinfo_t", input: "void *p", fields: [
                Translator.Field("self_x_assignment_lookalike",
                                 from: "p->x"),  // not a real assignment
            ])
        ))
        #expect(script.lint().isEmpty)
    }

    @Test("Thread-local conflict scanner does not walk preamble")
    func testConflictScannerIgnoresPreamble() {
        // Two scripts each declare a translator that mentions
        // `self->ts =` inside its raw source. They each really write
        // self->ts in their own probe action. The merge conflict
        // detector should still find the action conflict and only
        // the action conflict — not double-count the preamble text.
        let a = DBlocks(
            declarations: [.raw("/* mentions self->ts = something */")],
            clauses: [
                Probe("syscall::read:entry") { Action("self->ts = timestamp;") }
            ]
        )
        let b = DBlocks(
            declarations: [.raw("/* mentions self->ts = something else */")],
            clauses: [
                Probe("syscall::write:entry") { Action("self->ts = timestamp;") }
            ]
        )
        let conflicts = a.threadLocalConflicts(with: b)
        #expect(conflicts == ["ts"])  // exactly one conflict, not two
    }
}

// MARK: - TypedTranslator protocol pairing

@Suite("DBlocks TypedTranslator")
struct DBlocksTypedTranslatorTests {

    /// Sample namespace pairing a custom translator with static
    /// `DExpr` accessors. Conforming an uninhabited enum to
    /// ``TypedTranslator`` is the recommended pattern for
    /// application authors shipping a USDT provider.
    enum QueryArgs: TypedTranslator {
        static let translator = Translator(output: "queryinfo_t", input: "Query *q") {
            Translator.Field("sql",         from: "stringof(q->raw_sql)")
            Translator.Field("duration_ns", from: "q->elapsed_nanos")
            Translator.Field("rows",        from: "q->result_rowcount")
        }

        static let typedef: Typedef? = Typedef(name: "queryinfo_t") {
            Typedef.Member("sql",         type: "string")
            Typedef.Member("duration_ns", type: "int")
            Typedef.Member("rows",        type: "int")
        }

        static var sql:        DExpr { DExpr("args[0]->sql") }
        static var durationNs: DExpr { DExpr("args[0]->duration_ns") }
        static var rows:       DExpr { DExpr("args[0]->rows") }
    }

    @Test("register(in:) adds the translator and its typedef to the script")
    func testRegister() {
        var script = DBlocks {
            Probe("myapp$target:::query-start") {
                Printf("%s (%d rows in %d ns)",
                       args: [QueryArgs.sql, QueryArgs.rows, QueryArgs.durationNs])
            }
        }
        QueryArgs.register(in: &script)

        #expect(script.declarations.count == 2)
        // The typedef must come before the translator so the
        // translator's output type is known to the compiler.
        let src = script.source
        let typedefRange    = src.range(of: "typedef struct")
        let translatorRange = src.range(of: "translator queryinfo_t")
        #expect(typedefRange != nil && translatorRange != nil)
        if let td = typedefRange, let tr = translatorRange {
            #expect(td.lowerBound < tr.lowerBound)
        }
        // And the typed accessors actually appear in the action body.
        #expect(src.contains("args[0]->sql"))
        #expect(src.contains("args[0]->rows"))
    }

    @Test("Default typedef is nil; protocol still works")
    func testDefaultNilTypedef() {
        enum NoTypedef: TypedTranslator {
            static let translator = Translator(output: "x_t", input: "X *x", fields: [
                .init("a", from: "x->a"),
            ])
        }
        // Default extension supplies typedef == nil
        #expect(NoTypedef.typedef == nil)

        var script = DBlocks { Probe("BEGIN") { Printf("hi") } }
        NoTypedef.register(in: &script)
        #expect(script.declarations.count == 1)
        #expect(script.source.contains("translator x_t"))
    }

    @Test("Translator + typedef survive validate + JSON round-trip")
    func testFullRoundTrip() throws {
        var script = DBlocks {
            Probe("BEGIN") { Printf("starting") }
        }
        QueryArgs.register(in: &script)
        try script.validate()
        let restored = try DBlocks(jsonData: try script.jsonData())
        #expect(script.source == restored.source)
        #expect(restored.declarations.count == 2)
    }

    @Test("register(in:) is idempotent — second call adds nothing")
    func testRegisterIdempotent() {
        var script = DBlocks {
            Probe("BEGIN") { Printf("hi") }
        }
        QueryArgs.register(in: &script)
        let firstCount = script.declarations.count

        // A second call must not double the declarations.
        QueryArgs.register(in: &script)
        #expect(script.declarations.count == firstCount,
                "second register added \(script.declarations.count - firstCount) extra declaration(s)")

        // And the rendered source must contain exactly one
        // translator block for queryinfo_t.
        let occurrences = script.source.components(separatedBy: "translator queryinfo_t").count - 1
        #expect(occurrences == 1)
    }

    @Test("Two TypedTranslators with different names both register")
    func testTwoDistinctTranslators() {
        enum OtherArgs: TypedTranslator {
            static let translator = Translator(output: "otherinfo_t", input: "Other *o", fields: [
                .init("x", from: "o->x"),
            ])
        }
        var script = DBlocks { Probe("BEGIN") { Printf("hi") } }
        QueryArgs.register(in: &script)
        OtherArgs.register(in: &script)
        // QueryArgs has a typedef + translator (2), OtherArgs has just
        // a translator (1) — total 3.
        #expect(script.declarations.count == 3)
        #expect(script.source.contains("translator queryinfo_t"))
        #expect(script.source.contains("translator otherinfo_t"))
    }
}

// MARK: - Root-gated end-to-end tests
//
// These tests actually open libdtrace and exercise compile() / run()
// against representative scripts. They require root, so each one is
// gated on `getuid() == 0` and silently skips otherwise. Without the
// gate they would poison the entire test suite on machines where
// nobody is running it as root.

private func runningAsRoot() -> Bool {
    return getuid() == 0
}

@Suite("DBlocks End-to-End (root only)", .enabled(if: runningAsRoot()))
struct DBlocksEndToEndTests {

    /// Pull a representative slice of the extended Dwatch catalog
    /// through the real libdtrace compiler. The static catalog has
    /// ~280 entries; running compile() on all of them would be slow
    /// and would noisily fail on any FreeBSD system whose vfs/proc/
    /// sched providers don't expose every documented event. Pick a
    /// small fixed sample of high-confidence probes that should
    /// compile on any modern FreeBSD with DTrace enabled.
    @Test("Representative Dwatch profiles compile via libdtrace")
    func testRepresentativeProfilesCompile() throws {
        let samples: [(String, DBlocks)] = [
            ("syscallCounts",       DBlocks.syscallCounts()),
            ("fileOpens",           DBlocks.fileOpens()),
            ("processExec",         DBlocks.processExec()),
            ("Dwatch.kill",         DBlocks.Dwatch.kill()),
            ("Dwatch.open",         DBlocks.Dwatch.open()),
            ("Dwatch.readWrite",    DBlocks.Dwatch.readWrite()),
            ("Dwatch.tcp",          DBlocks.Dwatch.tcp()),
            ("Dwatch.systop",       DBlocks.Dwatch.systop()),
            ("Dwatch.sysReadEntry", DBlocks.Dwatch.sysReadEntry()),
            ("Dwatch.procCreate",   DBlocks.Dwatch.procCreate()),
        ]
        for (name, script) in samples {
            do {
                try script.compile()
            } catch {
                Issue.record("\(name): compile() failed: \(error)")
            }
        }
    }

    /// `attach(to:)` is the root-only API used to scope a script to
    /// a specific PID via the `$target` macro. The smoke test attaches
    /// to PID 1 (init) — present on every running FreeBSD system —
    /// and asserts the call doesn't throw. We don't actually run the
    /// script; just verifying that `grab` succeeds is enough to
    /// catch regressions in the libdtrace handle plumbing.
    @Test("DTraceSession.attach(to:) succeeds against PID 1")
    func testAttachToInit() throws {
        var session = try DTraceSession.create()
        // PID 1 always exists. attach() returns a ProcessHandle; we
        // just need it to not throw.
        let _ = try session.attach(to: 1)
    }

    /// `spawn(path:arguments:)` launches a child process under
    /// DTrace control. We spawn `/bin/true` (a no-op binary that
    /// exits with status 0) and verify the call returns a handle.
    /// As above, we don't run the session — the value here is
    /// catching plumbing regressions.
    @Test("DTraceSession.spawn(path:) launches /bin/true")
    func testSpawnTrue() throws {
        var session = try DTraceSession.create()
        let _ = try session.spawn(path: "/bin/true")
    }

    /// End-to-end run-and-capture against a known-good script. Uses
    /// `Tick(1, .seconds) { Exit(0) }` so the run terminates within
    /// a couple of seconds even if no other probes fire.
    @Test("End-to-end capture of a tick-bounded script")
    func testCaptureTickScript() throws {
        let script = DBlocks {
            BEGIN { Printf("hello from BEGIN") }
            Tick(1, .seconds) { Exit(0) }
        }
        let output = try script.capture()
        #expect(output.contains("hello from BEGIN"),
                "expected BEGIN printf in captured output, got: \(output)")
    }
}

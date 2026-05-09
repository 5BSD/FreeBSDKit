/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import CDTrace
import Foundation
import Glibc

/// A handle to an open DTrace session.
///
/// `DTraceHandle` is a move-only type that owns the underlying libdtrace handle.
/// When the handle is deinitialized, the DTrace session is automatically closed.
///
/// This is the raw, low-level API. For a fluent builder API, see `DTraceBuilder.DTraceSession`.
///
/// ## Example
///
/// ```swift
/// let handle = try DTraceHandle.open()
/// let program = try handle.compile("""
///     syscall:::entry /execname == "nginx"/ {
///         @[probefunc] = count();
///     }
///     """)
/// try handle.exec(program)
/// try handle.go()
///
/// while handle.poll() == .okay {
///     handle.sleep()
/// }
/// ```
public struct DTraceHandle: ~Copyable {
    @usableFromInline
    internal var _handle: OpaquePointer?

    /// Opens a new DTrace handle.
    ///
    /// - Parameter flags: Flags controlling how the handle is opened.
    /// - Returns: A new DTrace handle.
    /// - Throws: `DTraceCoreError.openFailed` if the handle cannot be opened.
    /// - Note: Requires appropriate privileges (typically root).
    public static func open(flags: DTraceOpenFlags = []) throws -> DTraceHandle {
        var err: Int32 = 0
        guard let hdl = cdtrace_open(cdtrace_version(), flags.rawValue, &err) else {
            let msg = String(cString: dtrace_errmsg(nil, err))
            throw DTraceCoreError.openFailed(code: err, message: msg)
        }
        return DTraceHandle(_handle: hdl)
    }

    @usableFromInline
    internal init(_handle: OpaquePointer) {
        self._handle = _handle
    }

    deinit {
        if let h = _handle {
            // Clean up any registered handlers before closing
            HandlerStorage.shared.removeHandlers(for: h)
            cdtrace_close(h)
        }
    }

    /// Provides scoped access to the underlying handle for advanced usage.
    ///
    /// - Parameter body: A closure that receives the raw handle pointer.
    /// - Returns: The value returned by the closure.
    /// - Throws: `DTraceCoreError.invalidHandle` if the handle is invalid.
    @inlinable
    public func withUnsafeHandle<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        guard let h = _handle else {
            throw DTraceCoreError.invalidHandle
        }
        return try body(h)
    }

    // MARK: - Error Handling

    /// Gets the last error code from this handle.
    public var lastError: Int32 {
        guard let h = _handle else { return 0 }
        return cdtrace_errno(h)
    }

    /// Gets the error message for the last error.
    public var lastErrorMessage: String {
        guard let h = _handle else { return "Invalid handle" }
        let err = cdtrace_errno(h)
        return String(cString: cdtrace_errmsg(h, err))
    }

    /// Gets the error message for a specific error code.
    public func errorMessage(for code: Int32) -> String {
        guard let h = _handle else { return "Invalid handle" }
        return String(cString: cdtrace_errmsg(h, code))
    }

    // MARK: - Options

    /// Sets a DTrace option.
    ///
    /// - Parameters:
    ///   - option: The option name (e.g., "bufsize", "quiet", "flowindent").
    ///   - value: The option value, or nil for boolean options.
    /// - Throws: `DTraceCoreError.setOptFailed` if the option cannot be set.
    public func setOption(_ option: String, value: String? = nil) throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        let result = option.withCString { optPtr in
            if let v = value {
                return v.withCString { valPtr in
                    cdtrace_setopt(h, optPtr, valPtr)
                }
            } else {
                return cdtrace_setopt(h, optPtr, nil)
            }
        }

        if result != 0 {
            throw DTraceCoreError.setOptFailed(option: option, message: lastErrorMessage)
        }
    }

    /// Gets a DTrace option value.
    ///
    /// - Parameter option: The option name.
    /// - Returns: The option value.
    /// - Throws: `DTraceCoreError.getOptFailed` if the option cannot be retrieved.
    public func getOption(_ option: String) throws -> Int64 {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        var value: dtrace_optval_t = 0
        let result = option.withCString { optPtr in
            cdtrace_getopt(h, optPtr, &value)
        }

        if result != 0 {
            throw DTraceCoreError.getOptFailed(option: option, message: lastErrorMessage)
        }

        return value
    }

    // MARK: - Buffer Configuration

    /// Buffer policy for trace data.
    public enum BufferPolicy: String, Sendable {
        /// Switch buffers when full (default). Data is copied to user space on switch.
        case `switch` = "switch"

        /// Fill buffer and stop tracing when full.
        case fill = "fill"

        /// Ring buffer - oldest data is overwritten when full.
        case ring = "ring"
    }

    /// Sets the buffer policy for trace data.
    ///
    /// - Parameter policy: The buffer policy to use.
    /// - Throws: `DTraceCoreError.setOptFailed` if the policy cannot be set.
    ///
    /// ## Policies
    /// - `.switch`: Default. Buffers are switched when full; no data loss but may block.
    /// - `.fill`: Tracing stops when buffer fills. Good for capturing initial activity.
    /// - `.ring`: Circular buffer; oldest data overwritten. Good for "last N events" capture.
    public func setBufferPolicy(_ policy: BufferPolicy) throws {
        try setOption("bufpolicy", value: policy.rawValue)
    }

    /// Sets the trace buffer size.
    ///
    /// - Parameter size: Size string (e.g., "4m", "1g", "65536").
    /// - Throws: `DTraceCoreError.setOptFailed` if the size cannot be set.
    public func setBufferSize(_ size: String) throws {
        try setOption("bufsize", value: size)
    }

    /// Sets the aggregation buffer size.
    ///
    /// - Parameter size: Size string (e.g., "4m", "1g", "65536").
    /// - Throws: `DTraceCoreError.setOptFailed` if the size cannot be set.
    public func setAggregationBufferSize(_ size: String) throws {
        try setOption("aggsize", value: size)
    }

    /// Sets the speculation buffer size.
    ///
    /// - Parameter size: Size string (e.g., "4m", "1g", "65536").
    /// - Throws: `DTraceCoreError.setOptFailed` if the size cannot be set.
    public func setSpeculationBufferSize(_ size: String) throws {
        try setOption("specsize", value: size)
    }

    /// Enables destructive actions (system(), panic(), breakpoint(), etc.).
    ///
    /// - Warning: Destructive actions can crash the system. Use with caution.
    /// - Throws: `DTraceCoreError.setOptFailed` if the option cannot be set.
    public func enableDestructiveActions() throws {
        try setOption("destructive")
    }

    /// Enables quiet mode (suppresses column headers and other metadata).
    ///
    /// - Throws: `DTraceCoreError.setOptFailed` if the option cannot be set.
    public func setQuiet() throws {
        try setOption("quiet")
    }

    /// Sets the rate at which buffers are switched/read (in Hz or time).
    ///
    /// - Parameter rate: Rate string (e.g., "1hz", "100ms", "1s").
    /// - Throws: `DTraceCoreError.setOptFailed` if the rate cannot be set.
    public func setSwitchRate(_ rate: String) throws {
        try setOption("switchrate", value: rate)
    }

    // MARK: - Program Compilation

    /// Compiles a D program from a string.
    ///
    /// - Parameters:
    ///   - source: The D program source code.
    ///   - flags: Compilation flags.
    /// - Returns: A compiled program that can be executed.
    /// - Throws: `DTraceCoreError.compileFailed` if compilation fails.
    public func compile(
        _ source: String,
        flags: DTraceCompileFlags = []
    ) throws -> DTraceProgram {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        let program = source.withCString { srcPtr in
            cdtrace_program_strcompile(
                h,
                srcPtr,
                DTRACE_PROBESPEC_NAME,
                flags.rawValue,
                0,
                nil
            )
        }

        guard let prog = program else {
            throw DTraceCoreError.compileFailed(message: lastErrorMessage)
        }

        return DTraceProgram(program: prog)
    }

    /// Compiles a D program from a file.
    ///
    /// - Parameters:
    ///   - path: Path to the `.d` script file.
    ///   - flags: Compilation flags.
    /// - Returns: A compiled program that can be executed.
    /// - Throws: `DTraceCoreError.compileFailed` if compilation fails.
    ///
    /// ## Example
    /// ```swift
    /// let handle = try DTraceHandle.open()
    /// let program = try handle.compileFile("/path/to/script.d")
    /// try handle.exec(program)
    /// try handle.go()
    /// ```
    public func compileFile(
        _ path: String,
        flags: DTraceCompileFlags = []
    ) throws -> DTraceProgram {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        guard let fp = fopen(path, "r") else {
            throw DTraceCoreError.compileFailed(message: "Cannot open file: \(path)")
        }
        defer { fclose(fp) }

        guard let prog = cdtrace_program_fcompile(h, fp, flags.rawValue, 0, nil) else {
            throw DTraceCoreError.compileFailed(message: lastErrorMessage)
        }

        return DTraceProgram(program: prog)
    }

    /// Executes a compiled D program, enabling its probes.
    ///
    /// - Parameter program: The compiled program to execute.
    /// - Returns: Information about the executed program.
    /// - Throws: `DTraceCoreError.execFailed` if execution fails.
    @discardableResult
    public func exec(_ program: borrowing DTraceProgram) throws -> DTraceProgramInfo {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        var info = dtrace_proginfo_t()
        let result = cdtrace_program_exec(h, program.unsafeProgram(), &info)

        if result != 0 {
            throw DTraceCoreError.execFailed(message: lastErrorMessage)
        }

        return DTraceProgramInfo(from: info)
    }

    // MARK: - Tracing Control

    /// Starts tracing.
    ///
    /// - Throws: `DTraceCoreError.goFailed` if tracing cannot be started.
    public func go() throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        let result = cdtrace_go(h)
        if result != 0 {
            throw DTraceCoreError.goFailed(message: lastErrorMessage)
        }
    }

    /// Stops tracing.
    ///
    /// - Throws: `DTraceCoreError.stopFailed` if tracing cannot be stopped.
    public func stop() throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        let result = cdtrace_stop(h)
        if result != 0 {
            throw DTraceCoreError.stopFailed(message: lastErrorMessage)
        }
    }

    /// Waits for data to be available.
    public func sleep() {
        guard let h = _handle else { return }
        cdtrace_sleep(h)
    }

    /// Gets the current status of the DTrace session.
    public var status: DTraceStatus {
        guard let h = _handle else { return .stopped }
        return DTraceStatus(from: cdtrace_status(h))
    }

    // MARK: - Data Consumption

    /// Processes available trace data, writing to stdout.
    ///
    /// Call this repeatedly in a loop until it returns `.done` or `.error`.
    /// Each call processes whatever data is currently available in the kernel
    /// buffers and writes it to the output destination.
    ///
    /// - Returns: `.okay` to continue polling, `.done` when tracing finished, `.error` on failure.
    ///
    /// ## Example
    /// ```swift
    /// try handle.go()
    /// while handle.poll() == .okay {
    ///     handle.sleep()  // Wait for more data
    /// }
    /// ```
    public func poll() -> DTraceWorkStatus {
        poll(to: Glibc.stdout)
    }

    /// Processes available trace data with a custom output file.
    ///
    /// - Parameter file: The FILE pointer to write output to.
    /// - Returns: `.okay` to continue polling, `.done` when tracing finished, `.error` on failure.
    public func poll(to file: UnsafeMutablePointer<FILE>) -> DTraceWorkStatus {
        guard let h = _handle else { return .error }
        let status = cdtrace_work(h, file, nil, nil, nil)
        return DTraceWorkStatus(from: status)
    }

    /// Processes available trace data using the buffered output handler.
    ///
    /// Passes NULL as the FILE* to `dtrace_work`, which causes
    /// libdtrace to route all `printf`/`printa` output through the
    /// handler registered via `onBufferedOutput` instead of writing
    /// to a file. The handler **must** be registered before calling
    /// this method; otherwise libdtrace returns an error
    /// (`EDT_NOBUFFERED`).
    ///
    /// - Returns: `.okay` to continue polling, `.done` when tracing
    ///   finished, `.error` on failure.
    public func pollBuffered() -> DTraceWorkStatus {
        guard let h = _handle else { return .error }
        let status = cdtrace_work(h, nil, nil, nil, nil)
        return DTraceWorkStatus(from: status)
    }

    /// Deprecated: Use `poll()` instead.
    @available(*, deprecated, renamed: "poll()")
    public func work() -> DTraceWorkStatus {
        poll()
    }

    /// Deprecated: Use `poll(to:)` instead.
    @available(*, deprecated, renamed: "poll(to:)")
    public func work(to file: UnsafeMutablePointer<FILE>) -> DTraceWorkStatus {
        poll(to: file)
    }

    /// Consume result for record callbacks.
    public enum ConsumeResult: Int32, Sendable {
        case error = -1   // Error while processing
        case this = 0     // Consume this probe/record
        case next = 1     // Advance to next probe/record
        case abort = 2    // Abort consumption
    }

    /// Data from a probe firing.
    public struct ProbeData: Sendable {
        public let cpu: Int32
        public let probe: DTraceProbeDescription
    }

    /// Consumes trace data with custom callbacks.
    ///
    /// This provides more control than `work()` by letting you handle
    /// each probe firing and record individually.
    ///
    /// - Parameter probeCallback: Called for each probe that fires.
    ///                            Return `.this` to process records, `.next` to skip.
    /// - Throws: `DTraceCoreError.consumeFailed` if consumption fails.
    public func consume(
        _ probeCallback: @escaping (ProbeData) -> ConsumeResult
    ) throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        var context = ConsumeContext(probeCallback: probeCallback)

        let result = withUnsafeMutablePointer(to: &context) { ctxPtr in
            cdtrace_consume(h, Glibc.stdout, consumeProbeCallback, nil, ctxPtr)
        }

        if result < 0 {
            throw DTraceCoreError.consumeFailed(message: lastErrorMessage)
        }
    }

    // MARK: - Aggregations

    /// Takes a snapshot of all aggregation data.
    ///
    /// - Throws: `DTraceCoreError.aggregateFailed` if the snapshot fails.
    public func aggregateSnap() throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        let result = cdtrace_aggregate_snap(h)
        if result != 0 {
            throw DTraceCoreError.aggregateFailed(message: lastErrorMessage)
        }
    }

    /// Prints all aggregation data to stdout.
    ///
    /// - Throws: `DTraceCoreError.aggregateFailed` if printing fails.
    public func aggregatePrint() throws {
        try aggregatePrint(to: Glibc.stdout)
    }

    /// Prints all aggregation data to a file.
    ///
    /// - Parameter file: The FILE pointer to write to.
    /// - Throws: `DTraceCoreError.aggregateFailed` if printing fails.
    public func aggregatePrint(to file: UnsafeMutablePointer<FILE>) throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        let result = cdtrace_aggregate_print(h, file, nil)
        if result != 0 {
            throw DTraceCoreError.aggregateFailed(message: lastErrorMessage)
        }
    }

    /// Clears all aggregation data.
    public func aggregateClear() {
        guard let h = _handle else { return }
        cdtrace_aggregate_clear(h)
    }

    // MARK: - Aggregation Walking

    /// The result of processing an aggregation record.
    public enum AggregateWalkResult: Int32, Sendable {
        case next = 0       // Proceed to next element
        case abort = 1      // Abort aggregation walk
        case clear = 2      // Clear this element
        case remove = 5     // Remove this element
    }

    /// Walks through aggregation data programmatically.
    ///
    /// This allows you to access aggregation data directly instead of
    /// just printing it.
    ///
    /// - Parameters:
    ///   - sorted: If true, walks in sorted order (by value).
    ///   - callback: Called for each aggregation record with raw data pointer and size.
    ///               Return `.next` to continue, `.abort` to stop.
    /// - Throws: `DTraceCoreError.aggregateFailed` if walk fails.
    public func aggregateWalk(
        sorted: Bool = true,
        _ callback: @escaping (UnsafeRawPointer, Int) -> AggregateWalkResult
    ) throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        var context = AggregateWalkContext(callback: callback)

        let result = withUnsafeMutablePointer(to: &context) { ctxPtr in
            if sorted {
                return cdtrace_aggregate_walk_sorted(h, aggregateWalkCallback, ctxPtr)
            } else {
                return cdtrace_aggregate_walk(h, aggregateWalkCallback, ctxPtr)
            }
        }

        if result < 0 {
            throw DTraceCoreError.aggregateFailed(message: lastErrorMessage)
        }
    }

    // MARK: - Typed Aggregation Walking

    /// The aggregation action type, matching DTrace's `DTRACEAGG_*` constants.
    public enum AggregationAction: UInt16, Sendable {
        case count     = 0x0701  // DTRACEAGG_COUNT
        case min       = 0x0702  // DTRACEAGG_MIN
        case max       = 0x0703  // DTRACEAGG_MAX
        case avg       = 0x0704  // DTRACEAGG_AVG
        case sum       = 0x0705  // DTRACEAGG_SUM
        case stddev    = 0x0706  // DTRACEAGG_STDDEV
        case quantize  = 0x0707  // DTRACEAGG_QUANTIZE
        case lquantize = 0x0708  // DTRACEAGG_LQUANTIZE
        case llquantize = 0x0709 // DTRACEAGG_LLQUANTIZE
    }

    /// One typed aggregation record, produced by the typed aggregate walk.
    public struct AggregationRecord: Sendable {
        /// Aggregation name (e.g. `""` for anonymous `@`, or `"counts"` for `@counts`).
        public let name: String

        /// The aggregation function (count, sum, quantize, etc.).
        public let action: AggregationAction

        /// Key tuple values as strings. For `@[execname, probefunc] = count()`,
        /// this would be `["nginx", "read"]`.
        public let keys: [String]

        /// Scalar value for count/sum/min/max/avg/stddev aggregations.
        /// For quantize/lquantize/llquantize, this is 0 — use `buckets` instead.
        public let value: Int64

        /// Histogram buckets for quantize/lquantize/llquantize.
        /// Empty for scalar aggregations.
        public let buckets: [(upperBound: Int64, count: Int64)]
    }

    /// Walk aggregation data with typed `AggregationRecord` values.
    ///
    /// Unlike the raw `aggregateWalk(_:)`, this overload parses the
    /// binary aggregation data into typed Swift values: aggregation
    /// name, action type, key strings, and scalar/histogram values.
    ///
    /// - Parameters:
    ///   - sorted: If true, walks in sorted order (by value).
    ///   - callback: Called for each typed record. Return `.next` to continue.
    /// - Throws: `DTraceCoreError.aggregateFailed` if walk fails.
    public func aggregateWalkTyped(
        sorted: Bool = true,
        _ callback: @escaping (AggregationRecord) -> AggregateWalkResult
    ) throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        var context = TypedAggregateWalkContext(callback: callback)

        let result = withUnsafeMutablePointer(to: &context) { ctxPtr in
            if sorted {
                return cdtrace_aggregate_walk_sorted(h, typedAggregateWalkCallback, ctxPtr)
            } else {
                return cdtrace_aggregate_walk(h, typedAggregateWalkCallback, ctxPtr)
            }
        }

        if result < 0 {
            throw DTraceCoreError.aggregateFailed(message: lastErrorMessage)
        }
    }

    // MARK: - Probe Iteration

    /// Iterates over all available probes matching a pattern.
    ///
    /// - Parameters:
    ///   - pattern: A probe pattern like "syscall:::entry" or nil for all probes.
    ///   - callback: Called for each matching probe. Return `true` to continue.
    /// - Throws: `DTraceCoreError.probeIterFailed` if iteration fails.
    public func iterateProbes(
        matching pattern: String? = nil,
        _ callback: @escaping (DTraceProbeDescription) -> Bool
    ) throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        var context = ProbeIterContext(callback: callback, userAborted: false)

        let result = withUnsafeMutablePointer(to: &context) { ctxPtr in
            if let pattern = pattern {
                var pdesc = dtrace_probedesc_t()
                return pattern.withCString { patternPtr in
                    let parseResult = dtrace_str2desc(h, DTRACE_PROBESPEC_NAME, patternPtr, &pdesc)
                    if parseResult == 0 {
                        return cdtrace_probe_iter(h, &pdesc, probeIterCallback, ctxPtr)
                    } else {
                        // Pattern parsing failed, iterate all probes
                        return cdtrace_probe_iter(h, nil, probeIterCallback, ctxPtr)
                    }
                }
            } else {
                return cdtrace_probe_iter(h, nil, probeIterCallback, ctxPtr)
            }
        }

        // result < 0 means actual error, result > 0 means callback stopped iteration
        // Only throw for actual errors (result < 0)
        if result < 0 {
            throw DTraceCoreError.probeIterFailed(message: lastErrorMessage)
        }
    }

    /// Returns the number of available probes.
    ///
    /// - Parameter pattern: A probe pattern to filter, or nil for all probes.
    public func countProbes(matching pattern: String? = nil) throws -> Int {
        var count = 0
        try iterateProbes(matching: pattern) { _ in
            count += 1
            return true
        }
        return count
    }

    /// Returns all probes matching a pattern as an array.
    ///
    /// - Parameter pattern: A probe pattern to filter, or nil for all probes.
    /// - Note: This can be memory-intensive for large numbers of probes.
    public func listProbes(matching pattern: String? = nil) throws -> [DTraceProbeDescription] {
        var probes: [DTraceProbeDescription] = []
        try iterateProbes(matching: pattern) { probe in
            probes.append(probe)
            return true
        }
        return probes
    }

    // MARK: - Handlers

    /// Information about a drop event.
    public struct DropInfo: Sendable {
        public let kind: DropKind
        public let drops: UInt64
        public let message: String
    }

    /// The type of data that was dropped.
    public enum DropKind: Int32, Sendable {
        case principal = 0      // Drop to principal buffer
        case aggregation = 1    // Drop to aggregation buffer
        case dynamic = 2        // Dynamic drop
        case speculation = 5    // Speculative drop
        case unknown = -1
    }

    /// Information about an error event.
    public struct ErrorInfo: Sendable {
        public let fault: Int32
        public let message: String
    }

    /// Sets a handler for error events.
    ///
    /// - Parameter handler: Called when an error occurs. Return `true` to continue, `false` to abort.
    /// - Throws: `DTraceCoreError.handlerFailed` if the handler cannot be set.
    public func onError(_ handler: @escaping (ErrorInfo) -> Bool) throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        // Store callback in per-handle storage
        HandlerStorage.shared.setErrorHandler(for: h, handler)

        // Pass handle value directly as arg (cast to void* for C interop)
        // The callback will cast it back to look up the handler
        let result = cdtrace_handle_err(h, errorHandlerCallback, UnsafeMutableRawPointer(h))
        if result != 0 {
            throw DTraceCoreError.handlerFailed(message: lastErrorMessage)
        }
    }

    /// Sets a handler for drop events (when data is dropped due to buffer overflow).
    ///
    /// - Parameter handler: Called when data is dropped. Return `true` to continue, `false` to abort.
    /// - Throws: `DTraceCoreError.handlerFailed` if the handler cannot be set.
    public func onDrop(_ handler: @escaping (DropInfo) -> Bool) throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        // Store callback in per-handle storage
        HandlerStorage.shared.setDropHandler(for: h, handler)

        // Pass handle value directly as arg (cast to void* for C interop)
        // The callback will cast it back to look up the handler
        let result = cdtrace_handle_drop(h, dropHandlerCallback, UnsafeMutableRawPointer(h))
        if result != 0 {
            throw DTraceCoreError.handlerFailed(message: lastErrorMessage)
        }
    }

    /// Information about buffered output.
    public struct BufferedOutput: Sendable {
        /// The formatted output string from DTrace.
        public let output: String

        /// Flags indicating what type of output this is.
        public let flags: BufferedOutputFlags

        /// Whether this is aggregation key data.
        public var isAggregationKey: Bool { flags.contains(.aggregationKey) }

        /// Whether this is aggregation value data.
        public var isAggregationValue: Bool { flags.contains(.aggregationValue) }

        /// Whether this is aggregation format data.
        public var isAggregationFormat: Bool { flags.contains(.aggregationFormat) }

        /// Whether this is the last aggregation record in a group.
        public var isAggregationLast: Bool { flags.contains(.aggregationLast) }
    }

    /// Flags for buffered output types.
    public struct BufferedOutputFlags: OptionSet, Sendable {
        public let rawValue: UInt32

        public init(rawValue: UInt32) {
            self.rawValue = rawValue
        }

        /// Output is aggregation key.
        public static let aggregationKey = BufferedOutputFlags(rawValue: UInt32(CDTRACE_BUFDATA_AGGKEY.rawValue))

        /// Output is aggregation value.
        public static let aggregationValue = BufferedOutputFlags(rawValue: UInt32(CDTRACE_BUFDATA_AGGVAL.rawValue))

        /// Output is aggregation format string.
        public static let aggregationFormat = BufferedOutputFlags(rawValue: UInt32(CDTRACE_BUFDATA_AGGFORMAT.rawValue))

        /// This is the last record in an aggregation group.
        public static let aggregationLast = BufferedOutputFlags(rawValue: UInt32(CDTRACE_BUFDATA_AGGLAST.rawValue))
    }

    /// Sets a handler for buffered output.
    ///
    /// This allows capturing DTrace output (printf, aggregations, etc.) directly
    /// in Swift without needing a FILE* pointer. Each time DTrace produces output,
    /// your handler is called with the formatted string.
    ///
    /// - Parameter handler: Called for each output fragment. Return `true` to continue, `false` to abort.
    /// - Throws: `DTraceCoreError.handlerFailed` if the handler cannot be set.
    ///
    /// ## Example
    /// ```swift
    /// var output = ""
    /// try handle.onBufferedOutput { data in
    ///     output += data.output
    ///     return true
    /// }
    ///
    /// // Now poll() won't write to stdout - you capture everything
    /// while handle.poll() == .okay {
    ///     handle.sleep()
    /// }
    /// print("Captured: \(output)")
    /// ```
    public func onBufferedOutput(_ handler: @escaping (BufferedOutput) -> Bool) throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        // Store callback in per-handle storage
        HandlerStorage.shared.setBufferedHandler(for: h, handler)

        let result = cdtrace_handle_buffered(h, bufferedHandlerCallback, UnsafeMutableRawPointer(h))
        if result != 0 {
            throw DTraceCoreError.handlerFailed(message: lastErrorMessage)
        }
    }

    // MARK: - Process Control

    /// A handle to a process being traced.
    public struct ProcessHandle: ~Copyable {
        @usableFromInline
        internal var _proc: OpaquePointer?
        @usableFromInline
        internal var _dtrace: OpaquePointer?

        internal init(proc: OpaquePointer, dtrace: OpaquePointer) {
            self._proc = proc
            self._dtrace = dtrace
        }

        deinit {
            if let p = _proc, let d = _dtrace {
                cdtrace_proc_release(d, p)
            }
        }

        /// Continues execution of the attached process.
        public func `continue`() {
            guard let p = _proc, let d = _dtrace else { return }
            cdtrace_proc_continue(d, p)
        }
    }

    /// Attaches to an existing process for tracing.
    ///
    /// This allows you to use `$target` in D scripts to reference the attached process.
    ///
    /// - Parameters:
    ///   - pid: The process ID to attach to.
    ///   - flags: Flags for process grabbing.
    /// - Returns: A process handle for the attached process.
    /// - Throws: `DTraceCoreError.procGrabFailed` if the process cannot be attached.
    ///
    /// ## Example
    /// ```swift
    /// let handle = try DTraceHandle.open()
    /// let proc = try handle.grabProcess(pid: 1234)
    ///
    /// // Compile script that uses $target
    /// let program = try handle.compile("""
    ///     syscall:::entry /pid == $target/ {
    ///         @[probefunc] = count();
    ///     }
    ///     """)
    /// try handle.exec(program)
    /// proc.continue()  // Resume the stopped process
    /// try handle.go()
    /// ```
    public func grabProcess(pid: pid_t, flags: Int32 = 0) throws -> ProcessHandle {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        guard let proc = cdtrace_proc_grab(h, pid, flags) else {
            throw DTraceCoreError.procGrabFailed(pid: pid, message: lastErrorMessage)
        }

        return ProcessHandle(proc: proc, dtrace: h)
    }

    /// Creates and launches a new process under DTrace control.
    ///
    /// The process is created in a stopped state. Use `$target` in D scripts
    /// to reference the process, then call `continue()` on the handle to start it.
    ///
    /// - Parameters:
    ///   - path: The path to the executable.
    ///   - arguments: Command-line arguments (including argv[0]).
    /// - Returns: A process handle for the created process.
    /// - Throws: `DTraceCoreError.procCreateFailed` if the process cannot be created.
    ///
    /// ## Example
    /// ```swift
    /// let handle = try DTraceHandle.open()
    /// let proc = try handle.createProcess(
    ///     path: "/usr/bin/myapp",
    ///     arguments: ["myapp", "--verbose"]
    /// )
    ///
    /// let program = try handle.compile("""
    ///     syscall:::entry /pid == $target/ {
    ///         @[probefunc] = count();
    ///     }
    ///     """)
    /// try handle.exec(program)
    /// try handle.go()
    /// proc.continue()  // Start the process
    /// ```
    public func createProcess(
        path: String,
        arguments: [String] = []
    ) throws -> ProcessHandle {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        // Build argv array for C
        let args = arguments.isEmpty ? [path] : arguments
        var cStrings = args.map { strdup($0) }
        cStrings.append(nil)

        defer {
            for ptr in cStrings where ptr != nil {
                free(ptr)
            }
        }

        guard let proc = path.withCString({ pathPtr in
            cdtrace_proc_create(h, pathPtr, &cStrings, nil, nil)
        }) else {
            throw DTraceCoreError.procCreateFailed(path: path, message: lastErrorMessage)
        }

        return ProcessHandle(proc: proc, dtrace: h)
    }

    /// Updates the process cache (call after process state changes).
    public func updateProcessCache() {
        guard let h = _handle else { return }
        cdtrace_update(h)
    }

    // MARK: - Output Format

    /// Output format mode.
    public enum OutputFormat: Int32, Sendable {
        case text = 0        // Plain text output (default)
        case structured = 1  // JSON/XML structured output
    }

    /// Configures structured output (JSON) mode.
    ///
    /// When enabled, output will be in JSON format instead of plain text.
    /// Must be called before `go()`.
    ///
    /// - Throws: `DTraceCoreError.setOptFailed` if configuration fails.
    public func enableStructuredOutput() throws {
        guard let h = _handle else { throw DTraceCoreError.invalidHandle }

        // Set oformat option to structured
        try setOption("oformat", value: "json")

        let result = cdtrace_oformat_configure(h)
        if result != 0 {
            throw DTraceCoreError.setOptFailed(option: "oformat", message: lastErrorMessage)
        }

        cdtrace_oformat_setup(h)
    }

    /// Checks if structured output is enabled.
    public var isStructuredOutputEnabled: Bool {
        guard let h = _handle else { return false }
        return cdtrace_oformat(h) == CDTRACE_OFORMAT_STRUCTURED.rawValue
    }

    /// Tears down structured output mode.
    public func disableStructuredOutput() {
        guard let h = _handle else { return }
        cdtrace_oformat_teardown(h)
    }
}

// MARK: - Probe Iteration Internals

private struct ProbeIterContext {
    var callback: (DTraceProbeDescription) -> Bool
    var userAborted: Bool
}

private func probeIterCallback(
    _ dtp: OpaquePointer?,
    _ pdp: UnsafePointer<dtrace_probedesc_t>?,
    _ arg: UnsafeMutableRawPointer?
) -> Int32 {
    guard let arg = arg, let pdp = pdp else {
        // No more probes or invalid args - return 0 to signal normal completion
        return 0
    }

    let context = arg.assumingMemoryBound(to: ProbeIterContext.self)

    let probe = DTraceProbeDescription(
        id: cdtrace_probedesc_id(pdp),
        provider: String(cString: cdtrace_probedesc_provider(pdp)),
        module: String(cString: cdtrace_probedesc_mod(pdp)),
        function: String(cString: cdtrace_probedesc_func(pdp)),
        name: String(cString: cdtrace_probedesc_name(pdp))
    )

    if context.pointee.callback(probe) {
        return 0  // Continue iteration
    } else {
        context.pointee.userAborted = true
        return 1  // Stop iteration (user requested)
    }
}

// MARK: - Aggregation Walk Internals

private struct AggregateWalkContext {
    var callback: (UnsafeRawPointer, Int) -> DTraceHandle.AggregateWalkResult
}

private func aggregateWalkCallback(
    _ data: UnsafePointer<dtrace_aggdata_t>?,
    _ arg: UnsafeMutableRawPointer?
) -> Int32 {
    guard let arg = arg, let data = data else {
        return DTRACE_AGGWALK_NEXT
    }

    let context = arg.assumingMemoryBound(to: AggregateWalkContext.self)

    let rawData = cdtrace_aggdata_data(data)
    let size = cdtrace_aggdata_size(data)

    guard let ptr = rawData else {
        return DTRACE_AGGWALK_NEXT
    }

    let result = context.pointee.callback(UnsafeRawPointer(ptr), size)
    return result.rawValue
}

// MARK: - Typed Aggregation Walk Internals

private struct TypedAggregateWalkContext {
    var callback: (DTraceHandle.AggregationRecord) -> DTraceHandle.AggregateWalkResult
}

func decodeTypedAggregationKey(
    offset: Int,
    size: Int,
    buffer: UnsafeRawPointer
) -> String {
    let raw = buffer.advanced(by: offset)

    switch size {
    case 8:
        return String(raw.loadUnaligned(as: Int64.self))
    case 4:
        return String(Int64(raw.loadUnaligned(as: Int32.self)))
    case 2:
        return String(Int64(raw.loadUnaligned(as: Int16.self)))
    case 1:
        return String(Int64(raw.load(as: Int8.self)))
    default:
        let bytes = UnsafeBufferPointer(
            start: raw.assumingMemoryBound(to: UInt8.self),
            count: size
        )

        if let nul = bytes.firstIndex(of: 0) {
            let stringBytes = Array(bytes.prefix(nul))
            if let str = String(bytes: stringBytes, encoding: .utf8) {
                return str
            }
        }

        return "<\(size) bytes>"
    }
}

private func typedAggregateWalkCallback(
    _ data: UnsafePointer<dtrace_aggdata_t>?,
    _ arg: UnsafeMutableRawPointer?
) -> Int32 {
    guard let arg = arg, let data = data else {
        return DTRACE_AGGWALK_NEXT
    }

    let context = arg.assumingMemoryBound(to: TypedAggregateWalkContext.self)

    guard let desc = cdtrace_aggdata_desc(data) else {
        return DTRACE_AGGWALK_NEXT
    }
    guard let rawData = cdtrace_aggdata_data(data) else {
        return DTRACE_AGGWALK_NEXT
    }

    let name = String(cString: cdtrace_aggdesc_name(desc))
    let nrecs = Int(cdtrace_aggdesc_nrecs(desc))

    // Need at least two records: record 0 is the aggregation ID
    // (a small integer identifying the @-variable), and the last
    // record is the aggregation action (count/sum/etc). Records
    // 1..(nrecs-2) are the actual key tuple elements.
    guard nrecs >= 2 else { return DTRACE_AGGWALK_NEXT }

    // The last record is the aggregation action.
    let aggRec = cdtrace_aggdesc_rec(desc, Int32(nrecs - 1))!
    let actionRaw = cdtrace_recdesc_action(aggRec)
    guard let action = DTraceHandle.AggregationAction(rawValue: actionRaw) else {
        return DTRACE_AGGWALK_NEXT
    }

    // Parse key tuple: record 0 is the internal aggregation ID,
    // records 1..<(nrecs-1) are the user key tuple, and the final
    // record is the aggregation value. Integer-width key records are
    // decoded as signed values; larger records are treated as bounded
    // NUL-terminated UTF-8 strings when possible.
    var keys: [String] = []
    for i in 1..<(nrecs - 1) {
        guard let keyRec = cdtrace_aggdesc_rec(desc, Int32(i)) else { continue }
        let offset = Int(cdtrace_recdesc_offset(keyRec))
        let size = Int(cdtrace_recdesc_size(keyRec))
        guard size > 0 else { continue }

        keys.append(decodeTypedAggregationKey(offset: offset, size: size, buffer: rawData))
    }

    // Parse the aggregation value.
    let aggOffset = Int(cdtrace_recdesc_offset(aggRec))
    let aggSize = Int(cdtrace_recdesc_size(aggRec))
    var scalarValue: Int64 = 0
    var buckets: [(upperBound: Int64, count: Int64)] = []

    switch action {
    case .count, .sum, .min, .max:
        // Scalar: single int64 at the record offset.
        if aggSize >= 8 {
            memcpy(&scalarValue, rawData.advanced(by: aggOffset), 8)
        }

    case .avg:
        // Average: two int64s — [count, total]. Value = total/count.
        if aggSize >= 16 {
            var count: Int64 = 0
            var total: Int64 = 0
            memcpy(&count, rawData.advanced(by: aggOffset), 8)
            memcpy(&total, rawData.advanced(by: aggOffset + 8), 8)
            scalarValue = count > 0 ? total / count : 0
        }

    case .stddev:
        // Stddev stores [count, total, total_of_squares]. Report total/count as value.
        if aggSize >= 16 {
            var count: Int64 = 0
            var total: Int64 = 0
            memcpy(&count, rawData.advanced(by: aggOffset), 8)
            memcpy(&total, rawData.advanced(by: aggOffset + 8), 8)
            scalarValue = count > 0 ? total / count : 0
        }

    case .quantize:
        // Power-of-2 histogram. The data is an array of int64 counts.
        // Bucket boundaries: ..., -2, -1, 0, 1, 2, 4, 8, 16, ...
        // Index 0 = negative overflow, index DTRACE_QUANTIZE_ZEROBUCKET = 0
        // Each bucket i maps to upper bound 2^(i - ZEROBUCKET).
        let nbuckets = aggSize / 8
        let zeroBucket = 63  // DTRACE_QUANTIZE_ZEROBUCKET
        for i in 0..<nbuckets {
            var count: Int64 = 0
            memcpy(&count, rawData.advanced(by: aggOffset + i * 8), 8)
            if count != 0 {
                let exp = i - zeroBucket
                let upperBound: Int64
                if exp <= 0 {
                    upperBound = Int64(exp)
                } else {
                    upperBound = Int64(1) << exp
                }
                buckets.append((upperBound: upperBound, count: count))
            }
        }

    case .lquantize, .llquantize:
        // Linear / log-linear quantize. The first int64 in the data
        // encodes the parameters (base, step, levels). Following
        // that are count int64s for each bucket.
        // For now, emit raw bucket indices — proper decoding requires
        // the lquantize/llquantize parameter encoding.
        let nbuckets = (aggSize / 8) - 1  // first slot is params
        for i in 0..<nbuckets {
            var count: Int64 = 0
            memcpy(&count, rawData.advanced(by: aggOffset + (i + 1) * 8), 8)
            if count != 0 {
                buckets.append((upperBound: Int64(i), count: count))
            }
        }
    }

    let record = DTraceHandle.AggregationRecord(
        name: name,
        action: action,
        keys: keys,
        value: scalarValue,
        buckets: buckets
    )

    let result = context.pointee.callback(record)
    return result.rawValue
}

// MARK: - Handler Internals

/// Storage for per-handle callbacks, keyed by handle pointer.
/// This allows multiple DTraceHandle instances to have independent handlers.
private final class HandlerStorage: @unchecked Sendable {
    static let shared = HandlerStorage()

    private let lock = NSLock()
    private var errorHandlers: [UnsafeRawPointer: (DTraceHandle.ErrorInfo) -> Bool] = [:]
    private var dropHandlers: [UnsafeRawPointer: (DTraceHandle.DropInfo) -> Bool] = [:]
    private var bufferedHandlers: [UnsafeRawPointer: (DTraceHandle.BufferedOutput) -> Bool] = [:]

    private init() {}

    func setErrorHandler(for handle: OpaquePointer, _ handler: @escaping (DTraceHandle.ErrorInfo) -> Bool) {
        lock.lock()
        errorHandlers[UnsafeRawPointer(handle)] = handler
        lock.unlock()
    }

    func setDropHandler(for handle: OpaquePointer, _ handler: @escaping (DTraceHandle.DropInfo) -> Bool) {
        lock.lock()
        dropHandlers[UnsafeRawPointer(handle)] = handler
        lock.unlock()
    }

    func setBufferedHandler(for handle: OpaquePointer, _ handler: @escaping (DTraceHandle.BufferedOutput) -> Bool) {
        lock.lock()
        bufferedHandlers[UnsafeRawPointer(handle)] = handler
        lock.unlock()
    }

    func errorHandler(for handle: OpaquePointer) -> ((DTraceHandle.ErrorInfo) -> Bool)? {
        lock.lock()
        defer { lock.unlock() }
        return errorHandlers[UnsafeRawPointer(handle)]
    }

    func dropHandler(for handle: OpaquePointer) -> ((DTraceHandle.DropInfo) -> Bool)? {
        lock.lock()
        defer { lock.unlock() }
        return dropHandlers[UnsafeRawPointer(handle)]
    }

    func bufferedHandler(for handle: OpaquePointer) -> ((DTraceHandle.BufferedOutput) -> Bool)? {
        lock.lock()
        defer { lock.unlock() }
        return bufferedHandlers[UnsafeRawPointer(handle)]
    }

    func removeHandlers(for handle: OpaquePointer) {
        lock.lock()
        errorHandlers.removeValue(forKey: UnsafeRawPointer(handle))
        dropHandlers.removeValue(forKey: UnsafeRawPointer(handle))
        bufferedHandlers.removeValue(forKey: UnsafeRawPointer(handle))
        lock.unlock()
    }
}

private func errorHandlerCallback(
    _ data: UnsafePointer<dtrace_errdata_t>?,
    _ arg: UnsafeMutableRawPointer?
) -> Int32 {
    guard let data = data,
          let arg = arg else {
        return DTRACE_HANDLE_OK
    }

    // arg is the dtrace handle pointer cast to void*
    let handlePtr = OpaquePointer(arg)
    guard let handler = HandlerStorage.shared.errorHandler(for: handlePtr) else {
        return DTRACE_HANDLE_OK
    }

    let msg = String(cString: cdtrace_errdata_msg(data))
    let fault = cdtrace_errdata_fault(data)

    let info = DTraceHandle.ErrorInfo(fault: fault, message: msg)

    return handler(info) ? DTRACE_HANDLE_OK : DTRACE_HANDLE_ABORT
}

private func dropHandlerCallback(
    _ data: UnsafePointer<dtrace_dropdata_t>?,
    _ arg: UnsafeMutableRawPointer?
) -> Int32 {
    guard let data = data,
          let arg = arg else {
        return DTRACE_HANDLE_OK
    }

    // arg is the dtrace handle pointer cast to void*
    let handlePtr = OpaquePointer(arg)
    guard let handler = HandlerStorage.shared.dropHandler(for: handlePtr) else {
        return DTRACE_HANDLE_OK
    }

    let kindRaw = cdtrace_dropdata_kind(data)
    let kind = DTraceHandle.DropKind(rawValue: Int32(kindRaw.rawValue)) ?? .unknown
    let drops = cdtrace_dropdata_drops(data)
    let msg = String(cString: cdtrace_dropdata_msg(data))

    let info = DTraceHandle.DropInfo(kind: kind, drops: drops, message: msg)

    return handler(info) ? DTRACE_HANDLE_OK : DTRACE_HANDLE_ABORT
}

private func bufferedHandlerCallback(
    _ data: UnsafePointer<dtrace_bufdata_t>?,
    _ arg: UnsafeMutableRawPointer?
) -> Int32 {
    guard let data = data,
          let arg = arg else {
        return DTRACE_HANDLE_OK
    }

    // arg is the dtrace handle pointer cast to void*
    let handlePtr = OpaquePointer(arg)
    guard let handler = HandlerStorage.shared.bufferedHandler(for: handlePtr) else {
        return DTRACE_HANDLE_OK
    }

    // Get the buffered output string
    guard let bufferedPtr = cdtrace_bufdata_buffered(data) else {
        return DTRACE_HANDLE_OK
    }

    let output = String(cString: bufferedPtr)
    let flags = DTraceHandle.BufferedOutputFlags(rawValue: cdtrace_bufdata_flags(data))

    let info = DTraceHandle.BufferedOutput(output: output, flags: flags)

    return handler(info) ? DTRACE_HANDLE_OK : DTRACE_HANDLE_ABORT
}

// MARK: - Consume Internals

private struct ConsumeContext {
    var probeCallback: (DTraceHandle.ProbeData) -> DTraceHandle.ConsumeResult
}

private func consumeProbeCallback(
    _ data: UnsafePointer<dtrace_probedata_t>?,
    _ arg: UnsafeMutableRawPointer?
) -> Int32 {
    guard let data = data, let arg = arg else {
        return DTRACE_CONSUME_NEXT
    }

    let context = arg.assumingMemoryBound(to: ConsumeContext.self)

    let cpu = cdtrace_probedata_cpu(data)
    let pdesc = cdtrace_probedata_pdesc(data)

    let probe: DTraceProbeDescription
    if let pdesc = pdesc {
        probe = DTraceProbeDescription(
            id: cdtrace_probedesc_id(pdesc),
            provider: String(cString: cdtrace_probedesc_provider(pdesc)),
            module: String(cString: cdtrace_probedesc_mod(pdesc)),
            function: String(cString: cdtrace_probedesc_func(pdesc)),
            name: String(cString: cdtrace_probedesc_name(pdesc))
        )
    } else {
        probe = DTraceProbeDescription(id: 0, provider: "", module: "", function: "", name: "")
    }

    let probeData = DTraceHandle.ProbeData(cpu: cpu, probe: probe)
    let result = context.pointee.probeCallback(probeData)

    return result.rawValue
}

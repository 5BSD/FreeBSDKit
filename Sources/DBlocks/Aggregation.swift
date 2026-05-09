/*
 * Copyright (c) 2026 Kory Heard
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

import DTraceCore
import CDTrace
import Foundation

// `dtrace_aggdata_t` and `dtrace_recdesc_t` come from the system
// `<dtrace.h>` header that the CDTrace shim re-exports.

// MARK: - Aggregation key

/// A single key column in an aggregation row.
///
/// DTrace aggregation keys can be integers or strings depending on
/// what the script's grouping expression evaluated to. The wrapper
/// preserves the underlying type when it can recognize it; anything
/// else falls through as raw bytes.
public enum AggregationKey: Sendable, Equatable {
    case int(Int64)
    case string(String)
    case bytes([UInt8])

    /// String view of the key, suitable for display.
    public var description: String {
        switch self {
        case .int(let v):    return String(v)
        case .string(let s): return s
        case .bytes(let b):  return "<\(b.count) bytes>"
        }
    }
}

// MARK: - Aggregation value

/// The summarized value of an aggregation row.
///
/// Scalar aggregations (`count`, `sum`, `min`, `max`, `avg`, `stddev`)
/// are decoded into `Int64`. Bucketed aggregations (`quantize`,
/// `lquantize`, `llquantize`) are surfaced as raw bytes for now —
/// follow-up work will decode their bucket layouts.
///
/// - Note: `stddev` currently carries the rolling **mean**, not the
///   computed standard deviation. The kernel records (count, sum,
///   sum-of-squares) but the sqrt-over-second-moment math is left to
///   a follow-up; the value here is reported so callers at least see
///   something useful, and the field name will become accurate when
///   that math lands. Use the `quantize` family if you want the full
///   distribution today.
public enum AggregationValue: Sendable, Equatable {
    case count(Int64)
    case sum(Int64)
    case min(Int64)
    case max(Int64)
    case avg(Int64)
    case stddev(Int64)
    /// A `quantize` (power-of-2 histogram) value, as raw bytes. Decode
    /// with libdtrace until typed support lands.
    case quantize(Data)
    /// An `lquantize` (linear histogram) value, as raw bytes.
    case lquantize(Data)
    /// An `llquantize` (log-linear histogram) value, as raw bytes.
    case llquantize(Data)
    /// An aggregation kind we did not recognize, with the raw payload.
    case unknown(action: UInt16, Data)

    /// Convenience: pull a scalar Int64 out of any of the integer-shaped
    /// cases (count/sum/min/max/avg/stddev). Returns `nil` for the
    /// histogram cases.
    public var asInt: Int64? {
        switch self {
        case .count(let v), .sum(let v), .min(let v),
             .max(let v),   .avg(let v), .stddev(let v):
            return v
        default:
            return nil
        }
    }
}

// MARK: - Aggregation record

/// A single aggregation row.
///
/// Roughly equivalent to one line of `printa(@name)` output, but in a
/// form Swift code can introspect: the aggregation's name, the key
/// columns, and the typed value.
public struct AggregationRecord: Sendable, Equatable {
    /// Name of the aggregation, e.g. `"calls"`. Empty for anonymous
    /// aggregations declared with `Count()` and friends.
    public let name: String

    /// Key columns, in the order they appeared in the aggregation
    /// expression's `[…]` brackets.
    public let keys: [AggregationKey]

    /// The summarized value.
    public let value: AggregationValue

    public init(name: String, keys: [AggregationKey], value: AggregationValue) {
        self.name = name
        self.keys = keys
        self.value = value
    }
}

// MARK: - Decoder

extension AggregationRecord {

    /// Decode a single `dtrace_aggdata_t *` into an `AggregationRecord`.
    /// Returns `nil` if the description does not have the minimum
    /// record layout DTrace uses for aggregations: record 0 is the
    /// internal aggregation ID, the final record is the value payload,
    /// and records 1..<(nrecs-1) are the user-visible key tuple.
    static func decode(from aggdata: UnsafePointer<dtrace_aggdata_t>) -> AggregationRecord? {
        let desc = cdtrace_aggdata_desc(aggdata)
        guard let desc else { return nil }
        let nrecs = Int(cdtrace_aggdesc_nrecs(desc))
        guard nrecs >= 2 else { return nil }

        let name: String
        if let cname = cdtrace_aggdesc_name(desc) {
            name = String(cString: cname)
        } else {
            name = ""
        }

        guard let dataBase = cdtrace_aggdata_data(aggdata) else { return nil }

        // Record 0 is the libdtrace aggregation ID, not a user key.
        // The last record is the aggregation value; records 1..<(nrecs-1)
        // describe the user-visible key tuple.
        var keys: [AggregationKey] = []
        keys.reserveCapacity(nrecs - 2)
        for i in 1..<(nrecs - 1) {
            guard let rec = cdtrace_aggdesc_rec(desc, Int32(i)) else { continue }
            keys.append(decodeKey(rec: rec, dataBase: dataBase))
        }

        let valueRec = cdtrace_aggdesc_rec(desc, Int32(nrecs - 1))!
        let value = decodeValue(rec: valueRec, dataBase: dataBase)

        return AggregationRecord(name: name, keys: keys, value: value)
    }

    static func decodeKey(
        action: UInt16,
        offset: Int,
        size: Int,
        buffer: UnsafeRawPointer
    ) -> AggregationKey {
        let raw = buffer.advanced(by: offset)

        // Heuristic: int-sized scalars (1, 2, 4, 8 bytes) come back as
        // signed integers; anything bigger is treated as a NUL-terminated
        // string until we hit a NUL or run out of bytes; otherwise raw
        // bytes. All multi-byte loads use loadUnaligned because the
        // kernel buffer is not guaranteed to be naturally aligned at
        // every record offset.
        switch size {
        case 8:
            return .int(raw.loadUnaligned(as: Int64.self))
        case 4:
            return .int(Int64(raw.loadUnaligned(as: Int32.self)))
        case 2:
            return .int(Int64(raw.loadUnaligned(as: Int16.self)))
        case 1:
            return .int(Int64(raw.load(as: Int8.self)))
        default:
            // Try string first.
            let buf = UnsafeBufferPointer(
                start: raw.assumingMemoryBound(to: UInt8.self),
                count: size
            )
            if let nul = buf.firstIndex(of: 0) {
                let bytes = Array(buf.prefix(nul))
                if let str = String(bytes: bytes, encoding: .utf8) {
                    return .string(str)
                }
            }
            return .bytes(Array(buf))
        }
    }

    private static func decodeKey(
        rec: UnsafePointer<dtrace_recdesc_t>,
        dataBase: UnsafeMutablePointer<CChar>
    ) -> AggregationKey {
        let action = cdtrace_recdesc_action(rec)
        let offset = Int(cdtrace_recdesc_offset(rec))
        let size = Int(cdtrace_recdesc_size(rec))
        return decodeKey(
            action: action,
            offset: offset,
            size: size,
            buffer: UnsafeRawPointer(dataBase)
        )
    }

    /// Pure-data decoder for aggregation values, exposed as `internal`
    /// so unit tests can drive it without a live DTrace handle.
    static func decodeValue(
        action: UInt16,
        offset: Int,
        size: Int,
        buffer: UnsafeRawPointer
    ) -> AggregationValue {
        let raw = buffer.advanced(by: offset)

        // All scalar loads use loadUnaligned: the kernel data buffer is
        // not guaranteed to be 8-byte aligned at every record offset,
        // and a misaligned load(as:) is undefined behavior in Swift even
        // though x86_64 typically tolerates it.
        func loadInt() -> Int64 {
            raw.loadUnaligned(as: Int64.self)
        }

        func loadAvg() -> Int64 {
            // libdtrace stores avg as a (count, sum) pair of int64s and
            // its `printa` reports sum/count.
            let count = raw.loadUnaligned(as: Int64.self)
            let sum = raw.loadUnaligned(fromByteOffset: 8, as: Int64.self)
            return count == 0 ? 0 : sum / count
        }

        func loadBytes() -> Data {
            Data(bytes: raw, count: size)
        }

        switch UInt32(action) {
        case UInt32(CDTRACE_AGG_COUNT.rawValue):
            return .count(loadInt())
        case UInt32(CDTRACE_AGG_MIN.rawValue):
            return .min(loadInt())
        case UInt32(CDTRACE_AGG_MAX.rawValue):
            return .max(loadInt())
        case UInt32(CDTRACE_AGG_SUM.rawValue):
            return .sum(loadInt())
        case UInt32(CDTRACE_AGG_AVG.rawValue):
            return .avg(loadAvg())
        case UInt32(CDTRACE_AGG_STDDEV.rawValue):
            // The stddev record is laid out as (count, sum, sum_of_squares).
            // The full sample standard deviation needs sqrt over the
            // second moment, which we don't compute today. Surface the
            // rolling mean (which matches the first column libdtrace
            // prints) so callers at least see something they can index
            // by, and document that the value is the mean, not the
            // deviation.
            return .stddev(loadAvg())
        case UInt32(CDTRACE_AGG_QUANTIZE.rawValue):
            return .quantize(loadBytes())
        case UInt32(CDTRACE_AGG_LQUANTIZE.rawValue):
            return .lquantize(loadBytes())
        case UInt32(CDTRACE_AGG_LLQUANTIZE.rawValue):
            return .llquantize(loadBytes())
        default:
            return .unknown(action: action, loadBytes())
        }
    }

    private static func decodeValue(
        rec: UnsafePointer<dtrace_recdesc_t>,
        dataBase: UnsafeMutablePointer<CChar>
    ) -> AggregationValue {
        let action = cdtrace_recdesc_action(rec)
        let offset = Int(cdtrace_recdesc_offset(rec))
        let size = Int(cdtrace_recdesc_size(rec))
        return decodeValue(
            action: action,
            offset: offset,
            size: size,
            buffer: UnsafeRawPointer(dataBase)
        )
    }
}

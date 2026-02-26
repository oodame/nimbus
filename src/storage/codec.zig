const std = @import("std");

pub const Error = error{
    VarintTooBig,
    IncompleteVarint,
    BufferTooSmall,
};

/// Encodes a value as a varint and writes it to the provided buffer.
///
/// The buffer must be large enough to hold the encoded varint. For a 32-bit value, the maximum size is 5 bytes; for a 64-bit value, the maximum size is 10 bytes.
/// Returns the number of bytes written, or an error if the buffer is too small.
///
/// The layout of the varint encoding is as follows:
/// - Each byte has the most significant bit (MSB) as a continuation flag. If the MSB is 1, it indicates that there are more bytes to read. If the MSB is 0, it indicates that this is the last byte of the varint.
/// - The remaining 7 bits of each byte are used to store the value. The first byte contains the least significant 7 bits of the value, the second byte contains the next 7 bits, and so on.
/// - For example, the value 300 would be encoded as two bytes: 0b10111100 (0xBC) and 0b00000001 (0x01).
pub fn writeVarint(comptime T: type, buf: []u8, value: T) usize {
    switch (T) {
        u32 => return writeVarint32(buf, value),
        u64 => return writeVarint64(buf, value),
        else => @compileError("Only support 32/64 bit unsigned integer types"),
    }
}

fn writeVarint32(buf: []u8, value: u32) usize {
    var i: usize = 0;
    if (value < (1 << 7)) {
        buf[i] = @intCast(value);
        i += 1;
    } else if (value < (1 << 14)) {
        buf[i] = @intCast((value & 0x7F) | 0x80);
        buf[i + 1] = @intCast(value >> 7);
        i += 2;
    } else if (value < (1 << 21)) {
        buf[i] = @intCast((value & 0x7F) | 0x80);
        buf[i + 1] = @intCast(((value >> 7) & 0x7F) | 0x80);
        buf[i + 2] = @intCast(value >> 14);
        i += 3;
    } else if (value < (1 << 28)) {
        buf[i] = @intCast((value & 0x7F) | 0x80);
        buf[i + 1] = @intCast(((value >> 7) & 0x7F) | 0x80);
        buf[i + 2] = @intCast(((value >> 14) & 0x7F) | 0x80);
        buf[i + 3] = @intCast(value >> 21);
        i += 4;
    } else {
        buf[i] = @intCast((value & 0x7F) | 0x80);
        buf[i + 1] = @intCast(((value >> 7) & 0x7F) | 0x80);
        buf[i + 2] = @intCast(((value >> 14) & 0x7F) | 0x80);
        buf[i + 3] = @intCast(((value >> 21) & 0x7F) | 0x80);
        buf[i + 4] = @intCast(value >> 28);
        i += 5;
    }
    return i;
}

fn writeVarint64(buf: []u8, value: u64) usize {
    var i: usize = 0;
    var val = value;
    while (val >= 0x80) : (i += 1) {
        buf[i] = @intCast((val & 0x7F) | 0x80);
        val >>= 7;
    }
    buf[i] = @intCast(val);
    return i + 1;
}

/// Reads a varint-encoded value from the provided buffer. The buffer should contain a valid varint encoding of the expected type.
pub fn readVarint(comptime T: type, buf: []const u8) !struct { result: T, pos: usize } {
    var pos: usize = 0;
    switch (T) {
        u32 => {
            const value = try readVarint32(buf, &pos);
            return .{ .result = value, .pos = pos };
        },
        u64 => {
            const value = try readVarint64(buf, &pos);
            return .{ .result = value, .pos = pos };
        },
        else => @compileError("Only support 32/64 bit unsigned integer types"),
    }
}

// TODO: inline this function and optimize it by unrolling the loop for small bytes of variants.
fn readVarint32(buf: []const u8, pos: *usize) !u32 {
    var result: u32 = 0;
    const start = pos.*;
    if (start >= buf.len) {
        return Error.IncompleteVarint;
    }
    // first byte
    if (buf[start] & 0x80 == 0) {
        result = @as(u32, buf[start]);
        pos.* += 1;
        return result;
    }
    var shift: usize = 0;
    while (shift <= 28) : (shift += 7) {
        if (start + shift / 7 >= buf.len) {
            return Error.IncompleteVarint;
        }
        const byte = buf[start + shift / 7];
        result |= @as(u32, byte & 0x7F) << @as(u5, @intCast(shift));
        if (byte & 0x80 == 0) {
            pos.* += shift / 7 + 1;
            return result;
        }
    }
    return Error.VarintTooBig;
}

fn readVarint64(buf: []const u8, pos: *usize) !u64 {
    var result: u64 = 0;
    const start = pos.*;
    var shift: usize = 0;
    while (shift <= 63) : (shift += 7) {
        if (start + shift / 7 >= buf.len) {
            return Error.IncompleteVarint;
        }
        const byte = buf[start + shift / 7];
        result |= @as(u64, byte & 0x7F) << @as(u6, @intCast(shift));
        if (byte & 0x80 == 0) {
            pos.* += shift / 7 + 1;
            return result;
        }
    }
    return error.VarintTooBig;
}

/// Returns the number of bytes required to encode the given value as a varint.
pub fn varintLength(value: u64) usize {
    var len: usize = 1;
    var val = value;
    while (val >= 0x80) : (len += 1) {
        val >>= 7;
    }
    return len;
}

/// Writes a length-prefixed slice to the provided buffer. The length is encoded as a varint, followed by the data bytes.
pub fn writeSlice(buf: []u8, data: []const u8) !void {
    const pos = writeVarint(u32, buf, @as(u32, @intCast(data.len)));
    if (pos + data.len > buf.len) {
        return Error.BufferTooSmall;
    }
    @memcpy(buf[pos .. pos + data.len], data);
}

/// Reads a length-prefixed slice from the provided buffer. The length is expected to be encoded as a varint, followed by the data bytes.
pub fn readSlice(buf: []const u8) !struct { []const u8, usize } {
    const res = try readVarint(u32, buf);
    if (res.pos + res.result > buf.len) {
        return Error.BufferTooSmall;
    }
    return .{ buf[res.pos .. res.pos + res.result], res.pos + res.result };
}

const testing = std.testing;

test "Varint: encoding and decoding u32" {
    var buf: [5]u8 = undefined;
    const value: u32 = 300;
    const len = writeVarint(u32, &buf, value);
    const res = try readVarint(u32, &buf);
    try testing.expectEqual(value, res.result);
    try testing.expectEqual(len, res.pos);
}

test "Varint: encoding and decoding u64" {
    var buf: [10]u8 = undefined;
    const value: u64 = 300;
    const len = writeVarint(u64, &buf, value);
    const res = try readVarint(u64, &buf);
    try testing.expectEqual(value, res.result);
    try testing.expectEqual(len, res.pos);
}

test "Varint: write u32 single byte values" {
    var buf: [10]u8 = undefined;

    // test 0-127 values (single byte encoding)
    const single_byte_values = [_]u32{ 0, 1, 42, 127 };
    const expected_lengths = [_]usize{ 1, 1, 1, 1 };

    for (single_byte_values, expected_lengths) |value, expected_len| {
        const len = writeVarint(u32, &buf, value);
        try testing.expectEqual(expected_len, len);
        try testing.expectEqual(@as(u8, @intCast(value)), buf[0]);
    }
}

test "Varint: write u32 multi-byte values" {
    var buf: [10]u8 = undefined;

    const test_cases = [_]struct { value: u32, expected_bytes: []const u8 }{
        .{ .value = 128, .expected_bytes = &[_]u8{ 0x80, 0x01 } },
        .{ .value = 300, .expected_bytes = &[_]u8{ 0xAC, 0x02 } },
        .{ .value = 16384, .expected_bytes = &[_]u8{ 0x80, 0x80, 0x01 } },
        .{ .value = 2097151, .expected_bytes = &[_]u8{ 0xFF, 0xFF, 0x7F } },
        .{ .value = 268435455, .expected_bytes = &[_]u8{ 0xFF, 0xFF, 0xFF, 0x7F } },
        .{ .value = std.math.maxInt(u32), .expected_bytes = &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x0F } },
    };

    for (test_cases) |case| {
        const len = writeVarint(u32, &buf, case.value);
        try testing.expectEqual(case.expected_bytes.len, len);
        try testing.expectEqualSlices(u8, case.expected_bytes, buf[0..len]);
    }
}

test "Varint: write u64 values" {
    var buf: [20]u8 = undefined;

    const test_cases = [_]struct { value: u64, expected_len: usize }{
        .{ .value = 0, .expected_len = 1 },
        .{ .value = 127, .expected_len = 1 },
        .{ .value = 128, .expected_len = 2 },
        .{ .value = 16383, .expected_len = 2 },
        .{ .value = 16384, .expected_len = 3 },
        .{ .value = 0x1FFFFFFFFFFFFF, .expected_len = 8 },
        .{ .value = std.math.maxInt(u64), .expected_len = 10 },
    };

    for (test_cases) |case| {
        const len = writeVarint(u64, &buf, case.value);
        try testing.expectEqual(case.expected_len, len);
    }
}

test "Varint: read u32 round-trip" {
    var buf: [10]u8 = undefined;

    const test_values = [_]u32{ 0, 1, 42, 127, 128, 255, 256, 300, 16383, 16384, 65535, 65536, 2097151, 2097152, 268435455, 268435456, std.math.maxInt(u32) };

    for (test_values) |original_value| {
        const encoded_len = writeVarint(u32, &buf, original_value);
        const result = try readVarint(u32, buf[0..encoded_len]);

        try testing.expectEqual(original_value, result.result);
        try testing.expectEqual(encoded_len, result.pos);
    }
}

test "Varint: read u64 round-trip" {
    var buf: [20]u8 = undefined;

    const test_values = [_]u64{ 0, 1, 127, 128, 16383, 16384, 2097151, 2097152, 268435455, 268435456, 34359738367, 34359738368, 4398046511103, 4398046511104, 562949953421311, 562949953421312, 72057594037927935, 72057594037927936, 9223372036854775807, std.math.maxInt(u64) };

    for (test_values) |original_value| {
        const encoded_len = writeVarint(u64, &buf, original_value);
        const result = try readVarint(u64, buf[0..encoded_len]);

        try testing.expectEqual(original_value, result.result);
        try testing.expectEqual(encoded_len, result.pos);
    }
}

test "Varint: read error cases" {
    // test empty buffer case
    {
        const empty_buf: []const u8 = &[_]u8{};
        try testing.expectError(Error.IncompleteVarint, readVarint(u32, empty_buf));
    }

    // test incomplete varint (all bytes have continuation bit set)
    {
        const incomplete_buf = [_]u8{ 0x80, 0x80, 0x80 }; // all bytes indicate continuation but no terminating byte
        try testing.expectError(Error.IncompleteVarint, readVarint(u32, &incomplete_buf));
    }

    // test varint that claims to be a u32 but has more than 4 bytes of data (invalid encoding)
    {
        const oversized_buf = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }; // the fifth byte has all bits set, which is invalid for a u32 varint
        try testing.expectError(Error.VarintTooBig, readVarint(u32, &oversized_buf));
    }
}

test "Varint: length correctness" {
    const test_cases = [_]struct { value: u64, expected_len: usize }{
        .{ .value = 0, .expected_len = 1 },
        .{ .value = 127, .expected_len = 1 },
        .{ .value = 128, .expected_len = 2 },
        .{ .value = 16383, .expected_len = 2 },
        .{ .value = 16384, .expected_len = 3 },
        .{ .value = 2097151, .expected_len = 3 },
        .{ .value = 2097152, .expected_len = 4 },
        .{ .value = 268435455, .expected_len = 4 },
        .{ .value = 268435456, .expected_len = 5 },
        .{ .value = std.math.maxInt(u32), .expected_len = 5 },
        .{ .value = std.math.maxInt(u64), .expected_len = 10 },
    };

    for (test_cases) |case| {
        try testing.expectEqual(case.expected_len, varintLength(case.value));
    }
}

test "Varint: length consistency with writeVarint" {
    var buf: [20]u8 = undefined;

    const test_values = [_]u64{ 0, 1, 127, 128, 16383, 16384, std.math.maxInt(u32), std.math.maxInt(u64) };

    for (test_values) |value| {
        const predicted_len = varintLength(value);
        const actual_len = if (value <= std.math.maxInt(u32))
            writeVarint(u32, &buf, @intCast(value))
        else
            writeVarint(u64, &buf, value);

        try testing.expectEqual(predicted_len, actual_len);
    }
}

test "Slice: basic read/write functionality" {
    var buf: [100]u8 = undefined;

    const test_data = "Hello, World!";
    try writeSlice(&buf, test_data);

    const result = try readSlice(&buf);
    try testing.expectEqualStrings(test_data, result[0]);
}

test "Slice: read/write various data sizes" {
    var buf: [1000]u8 = undefined;

    const test_cases = [_][]const u8{
        "", // empty string
        "a", // single character
        "Hello", // short string
        "A" ** 127, // 127 bytes (single byte length encoding)
        "B" ** 128, // 128 bytes (double byte length encoding)
        "C" ** 300, // 300 bytes (multi-byte length encoding)
    };

    for (test_cases) |test_data| {
        // clear the buffer before each test case
        @memset(&buf, 0);

        try writeSlice(&buf, test_data);
        const result = try readSlice(&buf);

        try testing.expectEqual(test_data.len, result[0].len);
        try testing.expectEqualStrings(test_data, result[0]);
    }
}

test "Slice: write buffer too small error" {
    var small_buf: [5]u8 = undefined;
    const large_data = "This string is definitely too large for the buffer";

    try testing.expectError(Error.BufferTooSmall, writeSlice(&small_buf, large_data));
}

test "Slice: read buffer too small error" {
    var buf: [10]u8 = undefined;

    // manually encode the length 1000 as a varint into the buffer
    const len = writeVarint(u32, &buf, 1000);

    // try to read the slice, which should fail because the buffer is too small to hold the declared length
    try testing.expectError(Error.BufferTooSmall, readSlice(buf[0..len]));
}

test "Variant: large dataset encoding/decoding performance" {
    const allocator = testing.allocator;
    var buf = try allocator.alloc(u8, 1000000); // 1MB buffer
    defer allocator.free(buf);

    // test the performance of encoding and decoding 1000 random values
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    const values = try allocator.alloc(u32, 1000);
    defer allocator.free(values);

    for (values) |*value| {
        value.* = random.int(u32);
    }

    const start_time = std.time.nanoTimestamp();

    var pos: usize = 0;
    for (values) |value| {
        const len = writeVarint(u32, buf[pos..], value);
        pos += len;
    }

    // decode the values back and verify correctness
    pos = 0;
    for (values) |expected_value| {
        const result = try readVarint(u32, buf[pos..]);
        try testing.expectEqual(expected_value, result.result);
        pos += result.pos;
    }

    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;

    std.log.info("Encoded/decoded 1000 values in {} ns", .{duration});
}

test "Varint: boundary values" {
    var buf: [20]u8 = undefined;

    // test all kinds of boundary values
    const boundary_values = [_]u64{
        (1 << 7) - 1, // 127 (max single byte)
        (1 << 7), // 128 (min double byte)
        (1 << 14) - 1, // 16383 (max double byte)
        (1 << 14), // 16384 (min triple byte)
        (1 << 21) - 1, // max triple byte
        (1 << 21), // min quadruple byte
        (1 << 28) - 1, // max quadruple byte
        (1 << 28), // min quintuple byte
        std.math.maxInt(u32), // max u32 value
        (1 << 35) - 1, // max 5-byte varint
        (1 << 35), // min 6-byte varint
        (1 << 42) - 1, // max 6-byte varint
        (1 << 42), // min 7-byte varint
        (1 << 49) - 1, // max 7-byte varint
        (1 << 49), // min 8-byte varint
        (1 << 56) - 1, // max 8-byte varint
        (1 << 56), // min 9-byte varint
        (1 << 63) - 1, // max 9-byte varint
        (1 << 63), // min 10-byte varint
        std.math.maxInt(u64), // max u64 value
    };

    for (boundary_values) |value| {
        if (value <= std.math.maxInt(u32)) {
            const len = writeVarint(u32, &buf, @intCast(value));
            const result = try readVarint(u32, buf[0..len]);
            try testing.expectEqual(@as(u32, @intCast(value)), result.result);
        }

        const len64 = writeVarint(u64, &buf, value);
        const result64 = try readVarint(u64, buf[0..len64]);
        try testing.expectEqual(value, result64.result);
    }
}

test "Varint: specific encoding verification" {
    var buf: [10]u8 = undefined;

    // varify specific value encoding, for example:
    // 300 = 0b100101100 = 0b0000010 0b0101100
    // encoding: 0b10101100 (0xAC), 0b00000010 (0x02)
    {
        const len = writeVarint(u32, &buf, 300);
        try testing.expectEqual(@as(usize, 2), len);
        try testing.expectEqual(@as(u8, 0xAC), buf[0]);
        try testing.expectEqual(@as(u8, 0x02), buf[1]);

        const result = try readVarint(u32, buf[0..len]);
        try testing.expectEqual(@as(u32, 300), result.result);
    }
}

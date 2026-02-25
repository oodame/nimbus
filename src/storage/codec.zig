const std = @import("std");

pub const Error = error{
    VarintTooBig,
    IncompleteVarint,
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
    if (@sizeOf(T) == 4) {
        return writeVarint32(buf, @as(u32, value));
    } else if (@sizeOf(T) == 8) {
        return writeVarint64(buf, @as(u64, value));
    } else {
        @compileError("Only support 32/64 bit variant");
    }
}

fn writeVarint32(buf: []u8, value: u32) usize {
    var i: usize = 0;
    if (value < (1 << 7)) {
        buf[i] = @as(u8, value);
        i += 1;
    } else if (value < (1 << 14)) {
        buf[i] = @as(u8, (value & 0x7F) | 0x80);
        buf[i + 1] = @as(u8, value >> 7);
        i += 2;
    } else if (value < (1 << 21)) {
        buf[i] = @as(u8, (value & 0x7F) | 0x80);
        buf[i + 1] = @as(u8, ((value >> 7) & 0x7F) | 0x80);
        buf[i + 2] = @as(u8, value >> 14);
        i += 3;
    } else if (value < (1 << 28)) {
        buf[i] = @as(u8, (value & 0x7F) | 0x80);
        buf[i + 1] = @as(u8, ((value >> 7) & 0x7F) | 0x80);
        buf[i + 2] = @as(u8, ((value >> 14) & 0x7F) | 0x80);
        buf[i + 3] = @as(u8, value >> 21);
        i += 4;
    } else {
        buf[i] = @as(u8, (value & 0x7F) | 0x80);
        buf[i + 1] = @as(u8, ((value >> 7) & 0x7F) | 0x80);
        buf[i + 2] = @as(u8, ((value >> 14) & 0x7F) | 0x80);
        buf[i + 3] = @as(u8, ((value >> 21) & 0x7F) | 0x80);
        buf[i + 4] = @as(u8, value >> 28);
        i += 5;
    }
    return i;
}

fn writeVarint64(buf: []u8, value: u64) usize {
    var i: usize = 0;
    while (value >= 0x80) : (i += 1) {
        buf[i] = @as(u8, (value & 0x7F) | 0x80);
        value >>= 7;
    }
    buf[i] = @as(u8, value);
    return i;
}

/// Reads a varint-encoded value from the provided buffer. The buffer should contain a valid varint encoding of the expected type.
pub fn readVarint(comptime T: type, buf: []const u8) !struct { T, usize } {
    var result: T = 0;
    var shift: T = 0;
    for (buf, 0..) |byte, i| {
        result |= @as(T, byte & 0x7F) << shift;
        if ((byte & 0x80) == 0) {
            return .{ result, i + 1 };
        }
        shift += 7;
        if (shift >= (@sizeOf(T) * 8 + 6)) {
            return error.VarintTooBig;
        }
    }
    return error.IncompleteVarint;
}

fn readVarint32(buf: []const u8, pos: *usize) !u32 {
    var result: u32 = 0;
    const start = pos.*;
    // first byte
    if (buf[start] & 0x80 == 0) {
        result = @as(u32, buf[start]);
        pos.* += 1;
        return result;
    }
    for (0..29) |shift| {
        const byte = buf[start + shift / 7];
        result |= @as(u32, byte & 0x7F) << (shift * 7);
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
    while (value >= 0x80) : (len += 1) {
        value >>= 7;
    }
    return len;
}

/// Writes a length-prefixed slice to the provided buffer. The length is encoded as a varint, followed by the data bytes.
pub fn writeSlice(buf: []u8, data: []const u8) !void {
    const pos = writeVarint(u32, buf, @as(u32, data.len));
    if (pos + data.len > buf.len) {
        return error.BufferTooSmall;
    }
    @memcpy(buf[pos..], data);
}

/// Reads a length-prefixed slice from the provided buffer. The length is expected to be encoded as a varint, followed by the data bytes.
pub fn readSlice(buf: []const u8) !struct { []const u8, usize } {
    const len, const headerSize = try readVarint(u32, buf);
    if (headerSize + len > buf.len) {
        return error.BufferTooSmall;
    }
    return .{ buf[headerSize .. headerSize + len], headerSize + len };
}

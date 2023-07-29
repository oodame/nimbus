const std = @import("std");
const ErrorCode = @import("../error_code.zig").ErrorCode;

/// A string view of a const bytes.
pub const Slice = []const u8;

pub const Error = struct {
    code: ErrorCode,
    msg: Slice,
};

pub fn Result(comptime T: type) type {
    return union(enum) {
        val: T,
        err: Error,
    };
}
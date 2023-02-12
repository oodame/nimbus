const std = @import("std");
const mem = std.mem;
const math = std.math;

pub fn RowSetType(
    comptime KeyType: type, 
    comptime ValueType: type,
    comptime key_comparator_type: fn (KeyType, KeyType) callconv(.Inline) math.Order
) type {
    return struct {
        const RowSet = @This();
        // Export generic argument types
        pub const Key = KeyType;
        pub const Value = ValueType;
        pub const key_comparator = key_comparator_type;
    };
}
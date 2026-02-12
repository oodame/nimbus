//! By convention, root.zig is the root source file when making a library.
const std = @import("std");
const Allocator = std.mem.Allocator;
const skiplist = @import("storage/skiplist.zig");
pub const SkipList = skiplist.SkipList;
pub const WalManager = @import("storage/wal.zig").WalManager;

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}

// block
pub const BlockBuilder = struct {
    allocator: Allocator,
    buffer: std.ArrayList(u8),
    last_key: std.ArrayList(u8),
    count: u32,

    pub fn init(allocator: Allocator) !BlockBuilder {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
            .last_key = std.ArrayList(u8).init(allocator),
            .count = 0,
        };
    }
};

pub const ChunkBuilder = struct {
    allocator: Allocator,
    buffer: std.ArrayList(u8),
    last_key: std.ArrayList(u8),
    count: u32,

    pub fn init(allocator: Allocator) !ChunkBuilder {
        return .{
            .allocator = allocator,
            .buffer = std.ArrayList(u8).init(allocator),
            .last_key = std.ArrayList(u8).init(allocator),
            .count = 0,
        };
    }

    // pub fn add(self: *ChunkBuilder, )
};

pub const StorageType = enum {
    btree,
    lsm,
};

// pub fn Storage(comptime storage_type: StorageType) type {}

/// Represents a Graph in memory. The underling storage could be a btree or lsm.
/// TODO: use comptime to set different storage backend.
/// TODO: try to use block arena
pub const MemGraph = struct {
    allocator: std.heap.ArenaAllocator,
    refs: i32,

    pub const Options = struct {};

    pub fn init() MemGraph {
        return .{
            .allocator = std.heap.ArenaAllocator(std.heap.page_allocator),
        };
    }

    pub fn deinit(self: *MemGraph) void {
        self.allocator.deinit();
        std.debug.assert(self.refs == 0);
    }

    pub fn ref(self: *MemGraph) void {
        self.refs = self.refs + 1;
    }

    pub fn unref(self: *MemGraph) void {
        std.debug.assert(self.refs > 0);
        self.refs = self.refs - 1;
        if (self.refs == 0) {
            self.deinit();
        }
    }

    // pub fn put(self: *MemGraph, key: []const u8, value: []const u8) !void {}
};

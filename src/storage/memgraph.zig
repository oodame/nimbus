//! MemGraph: In-memory graph storage with buffered writes.

const std = @import("std");
const SkipList = @import("skiplist.zig").SkipList;
const Dir = @import("types.zig").Dir;

const WriteBatch = struct {};

/// TODO: an idea to implement an efficient in-memory graph data structure:
/// - Use a skip list to store vertices
/// - Each vertex entry contains either:
///   - A skiplist of outgoing/incoming edges (sort by <dir, label, dst>), or
///   - A vector of edges, with edges number is expected to be small (< 16).
///   - When the number of edges exceeds a threshold, convert the vector to a skiplist.
/// MemGraph represents a graph in memory, buffering writes before flushing them to persistent storage.
const MemGraph = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) MemGraph {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(_: *MemGraph) void {
        // Clean up resources if needed.
    }

    // pub fn putVertex(self: *MemGraph, id: []const u8, properties: ?[]const u8) !void {
    //     // Implementation to add a vertex.
    // }

    // pub fn deleteVertex(self: *MemGraph, id: []const u8) !void {
    //     // Implementation to delete a vertex.
    // }

    // pub fn putEdge(self: *MemGraph, src: []const u8, dir: Dir, label: []const u8, dst: []const u8, properties: ?[]const u8) !void {
    //     // Implementation to add an edge.
    // }

    // pub fn deleteEdge(self: *MemGraph, src: []const u8, dir: Dir, label: []const u8, dst: []const u8) !void {
    //     // Implementation to delete an edge.
    // }

    // pub fn write(self: *MemGraph, write_batch: *const WriteBatch) !void {
    //     // Implementation to add edges from a write batch.
    // }
};

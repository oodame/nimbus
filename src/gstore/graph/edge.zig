const std = @import("std");
const mem = std.mem;
const math = std.math;

/// Stands for an edge in the graph, which is composed by its key fields, and
/// corresponding properties.
///
/// Note that `Edge` is just a view of a physical Edge memory.
pub const Edge = struct {
    src: []const u8,
    kind: u32,
    rank: u64,
    dst: []const u8,

    pub fn init(src: []const u8, kind: u32, rank: u64, dst: []const u8) Edge {
        return Edge {
            .src = src,
            .kind = kind,
            .rank = rank,
            .dst = dst,
        };        
    }

    /// Compares two edges
    pub fn compare(self: *Edge, other: *Edge) math.Order {

    }
};
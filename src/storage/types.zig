const std = @import("std");

/// Direction of an edge in the graph.
pub const Dir = enum(u8) {
    out = 0,
    in = 1,
};

/// Key representing a vertex in the graph.
pub const VertexKey = struct {
    id: []const u8,
};

/// Key representing an edge in the graph.
pub const EdgeKey = struct {
    src: []const u8,
    dir: Dir,
    label: []const u8,
    dst: []const u8,
};

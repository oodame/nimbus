const std = @import("std");
const mem = std.mem;
const math = std.math;

/// Stands for a vertex in the graph, which is composed by its key fields,
/// and corresponding properties.
///
/// Note that `Vertex` is just a view of a physical Vertex memory.
pub const Vertex = struct {
    id: []const u8,
    kind: u32,

    pub fn init(id: []const u8, kind: u32) Vertex {
        return Vertex{
            .id = id,
            .kind = kind,
        };
    }

    /// Compares two vertices
    pub fn compare(self: *Vertex, other: *Vertex) math.Order {}
};

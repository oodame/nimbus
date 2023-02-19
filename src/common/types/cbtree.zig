const std = @import("std");
const Slice = @import("types.zig").Slice;

const NodeKind = enum {
    INTERNAL,
    LEAF,
};

const NodeStatusFlag = packed struct(u64) {
    LOCKED: bool = false,
    SPLITTING: bool = false,
    INSERTING: bool = false,
};

const BTreeNode = struct {

};

/// An `LeafNode` with a fanout of N.
/// +------------+------------+-----+----------------+--------------+
/// | key0, ptr0 | key1, ptr1 | ... | keyN-1, ptrN-1 | keyN-1, ptrN |
/// +------------+------------+-----+----------------+--------------+
/// le(key0) |   gt(key0) |          gt(keyN-2)  |   gt(keyN-1) | 
///          v   le(key1) v          le(keyN-1)  v              v
///      +-------+    +-------+              +---------+    +-------+
///      | page0 |    | page1 |    ...       | pageN-1 |    | pageN |
///      +-------+    +-------+              +---------+    +-------+
///
const LeafNode = struct {

};

/// Returns an internal node.
fn InternalNodeType(key_size: u32, comptime fanout: u32) type {
    return struct {
        // Exports Key type
        var keys: [fanout]Slice = undefined;
        var child_ptrs: [fanout]*BTreeNode = undefined;
        var child_num: u32 = 0;
        const buf: Slice = undefined;

        const Self = @This();
        const Key = [key_size]u8;

        pub fn init(allocator: *std.mem.Allocator, split_key: Key, lchild: *BTreeNode, rchild: *BTreeNode) !Self {
            buf = try allocator.alignedAlloc(u8, key_size * fanout);
            std.mem.copy(u8, buf, split_key);
            keys[0] = buf[0..];
            child_ptrs[0] = lchild;
            child_ptrs[1] = rchild;
            child_num = 2;
        }

        pub fn deinit(self: *Self, allocator: *std.mem.Allocator) void {
            allocator.free(self.buf);
        }
    };
}

/// 
const InternalNode = struct {
    allocator: *std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: *std.mem.Allocator, split_key: Slice, lchild: *BTreeNode, rchild: *BTreeNode) Self {

    }
};

fn BTreeNodeType() type {
    return union(enum) {
        internal: struct {

        },
        leaf: struct {

        }
    };


    return struct {
        const Self = @This();

        var father: *Self = undefined;
    };
}

/// Concurrent B-Tree
pub fn ConcurrentBTreeType(
    comptime NodeType: type,
    comptime ArenaType: type,
) type {
    return struct {
        root: *NodeType,


        const Self = @This();


        const MutateBatch = struct {

        };

        /// Insert an entry into the tree.
        /// 
        /// Returns true if insert successfully, false if an entry with the given key already exists.
        pub fn insert(self: *Self, key: Slice, value: Slice) bool {

        }

        fn prepareBatch(self: *Self, batch: *MutateBatch) void {

        }

        fn traverseToLeaf(self: *Self, key: Slice) *NodeType {
            var node = stableRoot(self);

        }

        fn stableRoot(self: *Self) *NodeType {
            var node = self.root;
            return blk: while (node.*.father) : (node = node.*.father) {
                break :blk node;
            };
        }

    };
}